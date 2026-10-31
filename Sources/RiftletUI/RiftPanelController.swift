import AppKit
import QuartzCore
import RiftletCore

/// The AppKit invocation path, not a claim that a human hardware device acted.
/// Automation can also deliver mouse events through the native event queue.
public enum RiftSelectionSource: String, Sendable {
    case mouse, accessibility
}

/// A fresh observation emitted at an accepted press boundary. Mouse metadata is
/// taken only from that NSEvent; accessibility invocations have no mouse event.
public struct RiftSelectionBoundary: Equatable, Sendable {
    public let assetID: UUID
    public let source: RiftSelectionSource
    public let eventUptime: TimeInterval
    public let eventNumber: Int?
    public let windowNumber: Int?
    public let clickCount: Int?

    public init(assetID: UUID, source: RiftSelectionSource, eventUptime: TimeInterval,
                eventNumber: Int? = nil, windowNumber: Int? = nil, clickCount: Int? = nil) {
        self.assetID = assetID; self.source = source; self.eventUptime = eventUptime
        self.eventNumber = eventNumber; self.windowNumber = windowNumber; self.clickCount = clickCount
    }
}

/// Read-only native geometry for the standalone acceptance helper. Rectangles
/// are in screen points; observing this value never changes input or layout.
public struct RiftDiagnosticRow: Equatable, Sendable {
    public let assetID: UUID
    public let ordinal: Int
    /// Original visual/AX window; it always ignores mouse events.
    public let windowNumber: Int
    public let frame: CGRect
    public let imageClipFrame: CGRect
    public let numberFrame: CGRect
    public let imageInputWindowNumber: Int
    public let numberInputWindowNumber: Int
    public let imageInputFrame: CGRect
    public let numberInputFrame: CGRect
}

public struct RiftDiagnosticSnapshot: Sendable {
    public let rows: [RiftDiagnosticRow]
    public let lineFrame: CGRect
    public let isHolding: Bool
    public let isTransitioning: Bool
}

public struct RiftArrivalDiagnostic: Sendable {
    public let selectedMode: ArrivalMotionMode
    public let effectiveMode: ArrivalMotionMode
    public let activeAssetID: UUID?
    public let pendingAssetID: UUID?
    public let overlayCount: Int
}

/// Minimal native AppKit structure informed by Tendedero's LinePanel, implemented here
/// without its private CGS calls, pointer polling, capacity eviction or artwork.
private final class RiftPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect, decorative: Bool = false) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = decorative
        animationBehavior = .none
        // sharingType.none is deliberately NOT used as an unproved screenshot-exclusion promise.
    }
}

private final class RiftRowView: NSView, NSMenuDelegate {
    var record: AssetRecord
    var geometry: RiftRowLayout
    var configuration: RiftConfiguration
    var ordinal: Int
    let imageClip = CALayer()
    let imageLayer = CALayer()
    var imageOffset: CGFloat = 0
    var requestedPixelSize: Int = 0
    var reportedImageReady = false
    private var arrivalImageOwner: UUID?
    var onDown: ((NSEvent) -> Bool)?
    var onUp: ((Bool, CGPoint?) -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    var onAccessiblePress: (() -> Bool)?
    var onPreview: (() -> Bool)?
    var onApproach: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onRemove: (() -> Void)?
    var onOpenOriginal: (() -> Void)?
    var onMenuVisibility: ((Bool) -> Void)?
    var feedback: String?
    private var approachTracking: NSTrackingArea?

    init(record: AssetRecord, geometry: RiftRowLayout, configuration: RiftConfiguration) {
        self.record = record; self.geometry = geometry; self.configuration = configuration
        ordinal = geometry.ordinal
        super.init(frame: NSRect(origin: .zero, size: geometry.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageClip.name = "rift.image.clip"
        imageLayer.name = "rift.image.content"
        imageClip.masksToBounds = true
        imageClip.cornerRadius = 1.5
        imageClip.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        layer?.addSublayer(imageClip)
        imageClip.addSublayer(imageLayer)
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .linear
        updateGeometry(geometry)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "预览完整截图", handler: { [weak self] in
            self?.onPreview?() ?? false
        }), NSAccessibilityCustomAction(name: "查看原图", handler: { [weak self] in
            guard let action = self?.onOpenOriginal else { return false }; action(); return true
        })])
        updateDescription()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    // Acceptance identity exists only for a currently visible synthetic row.
    override func accessibilityIdentifier() -> String {
        guard record.image.origin == .synthetic, record.visibility == .visible,
              window?.isVisible == true else { return "" }
        return "riftlet-synthetic-\(record.id.uuidString)"
    }

    override func isAccessibilityEnabled() -> Bool {
        guard record.image.origin == .synthetic else { return super.isAccessibilityEnabled() }
        return record.visibility == .visible && window?.isVisible == true
            && [.pending, .failed, .unknown, .missing].contains(record.status)
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let approachTracking { removeTrackingArea(approachTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        approachTracking = area; addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true); onApproach?() }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard record.visibility == .visible else { return nil }
        let menu = NSMenu()
        let original = NSMenuItem(title: "查看原图", action: #selector(openOriginal(_:)), keyEquivalent: "")
        original.target = self; menu.addItem(original)
        let remove = NSMenuItem(title: "从裂缝移除", action: #selector(removeFromRift(_:)), keyEquivalent: "")
        remove.target = self; menu.addItem(remove); menu.delegate = self
        return menu
    }

    @objc private func openOriginal(_ sender: NSMenuItem) { onOpenOriginal?() }
    @objc private func removeFromRift(_ sender: NSMenuItem) { onRemove?() }
    func menuWillOpen(_ menu: NSMenu) { onMenuVisibility?(true) }
    func menuDidClose(_ menu: NSMenu) { onMenuVisibility?(false) }

    func updateGeometry(_ geometry: RiftRowLayout) {
        self.geometry = geometry
        frame.size = geometry.frame.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageClip.frame = geometry.imageClipFrame
        imageClip.maskedCorners = configuration.placement?.side == .left ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        imageLayer.setAffineTransform(.identity)
        imageLayer.frame = CGRect(x: geometry.imageFrame.minX - geometry.imageClipFrame.minX, y: 0, width: geometry.imageFrame.width, height: geometry.imageFrame.height)
        imageLayer.setAffineTransform(CGAffineTransform(translationX: imageOffset, y: 0))
        CATransaction.commit()
        needsDisplay = true
    }

    func setImage(_ image: CGImage?, arrivalOwner: UUID? = nil) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let arrivalOwner {
            // Commit the decoded pixels and their handoff visibility together.
            // Ordering the flight window must never expose this target first.
            arrivalImageOwner = arrivalOwner
            imageLayer.isHidden = true
        }
        imageLayer.contents = image
        CATransaction.commit()
        needsDisplay = true
    }

    func ownsArrivalImage(_ owner: UUID) -> Bool { arrivalImageOwner == owner }

    func restoreArrivalImage(owner: UUID) {
        guard arrivalImageOwner == owner else { return }
        resetArrivalImage()
    }

    /// A global motion-policy cancellation abandons every presentation owner.
    /// Ordinary cache refreshes must never use this unconditional restoration.
    func resetArrivalImage() {
        arrivalImageOwner = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.isHidden = false
        CATransaction.commit()
    }

    func updateDescription() {
        let suffix: String
        switch record.status {
        case .pending: suffix = "可附加"
        case .transferring: suffix = "附加处理中"
        case .unknown: suffix = "结果待核对，图片已保留"
        case .failed: suffix = record.visibilityReason == .safeFailure ? "上传失败，可重新选择" : "未附加，图片已保留"
        case .missing: suffix = "本机图片不可用"
        case .used: suffix = "已核对完成"
        }
        setAccessibilityLabel("截图 \(ordinal)，\(feedback ?? suffix)")
        let help = feedback ?? "截图 \(ordinal) · \(suffix)"
        // Full preview already describes the hovered image. Reserve tooltip
        // surfaces for actual light feedback rather than covering that preview.
        toolTip = feedback
        setAccessibilityHelp(help)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = NSFont.monospacedDigitSystemFont(ofSize: configuration.numberFontSize, weight: .regular)
        let text = NSAttributedString(string: String(ordinal), attributes: [
            .font: font, .foregroundColor: RiftVisualStyle.secondary
        ])
        if geometry.numberIsPad {
            RiftVisualStyle.surface.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.8).setFill()
            let stroke: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 1 / max(1, window?.backingScaleFactor ?? 1)
            let pad = NSBezierPath(roundedRect: geometry.numberFrame.insetBy(dx: stroke / 2, dy: stroke / 2), xRadius: 5, yRadius: 5)
            pad.fill(); RiftVisualStyle.separator.setStroke(); pad.lineWidth = stroke; pad.stroke()
        }
        let textSize = text.size()
        text.draw(at: CGPoint(x: geometry.numberFrame.midX - textSize.width / 2,
                              y: geometry.numberFrame.midY - textSize.height / 2))
        let underlineY = geometry.numberFrame.minY - 2
        let length = min(8, geometry.numberFrame.width)
        let x = geometry.numberFrame.maxX - length
        if record.status == .transferring || record.status == .unknown {
            NSColor.secondaryLabelColor.withAlphaComponent(0.7).setFill()
            CGRect(x: x, y: underlineY, width: length, height: 0.7).fill()
            if record.status == .unknown {
                CGRect(x: x, y: underlineY - 3, width: length, height: 0.7).fill()
            }
        }
        if record.status == .missing {
            NSColor.tertiaryLabelColor.setStroke()
            let path = NSBezierPath(rect: geometry.imageClipFrame.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 0.7; path.stroke()
        }
    }

    func animateImage(to offset: CGFloat, duration: TimeInterval, power: Double? = nil) {
        let start = imageLayer.presentation()?.affineTransform().tx ?? imageOffset
        let animation: CAKeyframeAnimation?
        if duration > 0 {
            let keyframes = CAKeyframeAnimation(keyPath: "transform.translation.x")
            keyframes.values = (0...24).map { sample in
                let t = Double(sample) / 24
                let u = power.map { pow(t, $0) } ?? (1 - pow(1 - t, 3))
                return Double(start) + Double(offset - start) * u
            }
            keyframes.duration = duration
            keyframes.calculationMode = .linear
            animation = keyframes
        } else { animation = nil }
        imageOffset = offset
        // Publish the final model and its explicit transition together. A
        // separate model commit can expose a fully swallowed frame before the
        // animation is installed, then briefly reveal that image again.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.setAffineTransform(CGAffineTransform(translationX: offset, y: 0))
        if let animation { imageLayer.add(animation, forKey: "rift.translation") }
        else { imageLayer.removeAllAnimations() }
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        guard geometry.containsSelectionPoint(convert(event.locationInWindow, from: nil)) else { return }
        _ = onDown?(event)
    }
    override func mouseUp(with event: NSEvent) {
        onUp?(geometry.containsSelectionPoint(convert(event.locationInWindow, from: nil)),
              event.window?.convertPoint(toScreen: event.locationInWindow))
    }
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }
    override func accessibilityPerformPress() -> Bool { onAccessiblePress?() ?? false }
}

/// Native input islands. The original row remains the sole drawing and AX
/// owner; no synthetic event is posted or forwarded to another application.
private final class RiftInputView: NSView {
    weak var rowView: RiftRowView?
    private var approachTracking: NSTrackingArea?

    init(rowView: RiftRowView) {
        self.rowView = rowView
        super.init(frame: .zero)
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func isInsideOriginalRow(_ event: NSEvent) -> Bool {
        guard let eventWindow = event.window, eventWindow === window,
              eventWindow.isVisible, let rowView, let visualWindow = rowView.window,
              visualWindow.isVisible else { return false }
        let screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
        let localPoint = rowView.convert(visualWindow.convertPoint(fromScreen: screenPoint), from: nil)
        return rowView.geometry.containsSelectionPoint(localPoint)
    }

    override func mouseDown(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)), isInsideOriginalRow(event) else { return }
        _ = rowView?.onDown?(event)
    }
    override func mouseUp(with event: NSEvent) {
        // AppKit routes release to the original down window even outside its
        // bounds. Test the union of this original asset's two regions, never a
        // replacement row under the release point.
        rowView?.onUp?(isInsideOriginalRow(event), event.window?.convertPoint(toScreen: event.locationInWindow))
    }
    override func scrollWheel(with event: NSEvent) { rowView?.onScroll?(event) }
    override func menu(for event: NSEvent) -> NSMenu? { rowView?.menu(for: event) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let approachTracking { removeTrackingArea(approachTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        approachTracking = area; addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { rowView?.onHover?(true); rowView?.onApproach?() }
    override func mouseExited(with event: NSEvent) { rowView?.onHover?(false) }
}

/// Tracking areas may be rebuilt while the pointer remains in the same input
/// island. Treat those notifications as one approach, not fresh browser work.
struct RiftPointerApproachState {
    private var hovered: Set<UUID> = []
    private var reported: Set<UUID> = []

    mutating func update(hovered: Set<UUID>) {
        self.hovered = hovered
        reported.formIntersection(hovered)
    }

    mutating func enter(_ id: UUID) -> Bool {
        guard hovered.contains(id) else { return false }
        return reported.insert(id).inserted
    }
}

private struct RowWindow {
    let panel: RiftPanel
    let view: RiftRowView
    let imageInput: RiftPanel
    let numberInput: RiftPanel

    var panels: [RiftPanel] { [panel, imageInput, numberInput] }

    init(record: AssetRecord, geometry: RiftRowLayout, configuration: RiftConfiguration) {
        panel = RiftPanel(frame: geometry.frame, decorative: true)
        view = RiftRowView(record: record, geometry: geometry, configuration: configuration)
        panel.contentView = view
        imageInput = RiftPanel(frame: .zero)
        numberInput = RiftPanel(frame: .zero)
        for input in [imageInput, numberInput] {
            input.contentView = RiftInputView(rowView: view)
            input.setAccessibilityHidden(true)
        }
        syncInputFrames()
    }

    func syncInputFrames() {
        imageInput.setFrame(panel.convertToScreen(view.convert(view.geometry.imageClipFrame, to: nil)), display: true)
        numberInput.setFrame(panel.convertToScreen(view.convert(view.geometry.numberFrame, to: nil)), display: true)
        for input in [imageInput, numberInput] { input.contentView?.toolTip = view.toolTip }
    }

    func close() { panels.forEach { $0.close() } }
    func orderOut() { panels.forEach { $0.orderOut(nil) } }
}

/// Optional acceptance diagnostics only. These times describe AppKit code paths,
/// not rendered pixels, SQLite commit time, or human input provenance.
public enum RiftPresentationPhase: String, Sendable {
    case swallowScheduled, swallowActualStart, swallowClose
}

public struct RiftPresentationBoundary: Sendable {
    public let phase: RiftPresentationPhase
    public let assetID: UUID
    public let operationID: UUID?
    public let visibilityRevision: Int64
    public let generation: UInt
    public let uptime: TimeInterval
    public let actualDuration: TimeInterval
}

/// Presentation ownership only; neither case grants attachment or retry rights.
public enum RiftFeedbackOwner: Equatable, Sendable {
    case selection(UUID)
    case operation(UUID)
}

public enum RiftFeedbackTiming: Equatable, Sendable { case immediate, waiting }

/// The UI consumes committed state only. It has no adapter, receipt policy or file-deletion API.
/// Per-row input windows leave genuine window-free gaps; the entire line is click-through.
/// Actual transparent-pixel hit behavior, first-click focus and Spaces require Mac GUI validation.
@MainActor
public final class RiftPanelController {
    public private(set) var configuration: RiftConfiguration
    public var requestedConfiguration: RiftConfiguration { deferredConfiguration ?? configuration }
    public private(set) var arrivalMode: ArrivalMotionMode
    public var effectiveArrivalMode: ArrivalMotionMode { arrivalMode.effective(reduceMotion: reduceMotion) }
    public var arrivalDestinationDisplayID: UInt32? {
        (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    public private(set) var magnetParameters: MagnetMotionParameters
    public private(set) var visibleRange: Range<Int> = 0..<0
    public private(set) var userHidden = false
    /// Capture presentation is transient and never changes persisted Hide or
    /// any asset/transfer state. Header reservation also bounds long queues.
    public private(set) var captureSuppressed = false
    private var captureSessionActive = false
    public var screenshotEntryAnchor: CGPoint? {
        guard !closed else { return nil }
        if let layout = pagerLayout { return layout.cameraAnchor }
        // The independent camera must exist before the first queue render.
        // Resolve geometry only; do not synthesize a row or change saved intent.
        guard let screen else { return nil }
        return RiftLayout.make(records: lastRecords, visibleFrame: screen.visibleFrame,
            configuration: configuration, firstVisibleIndex: firstVisibleIndex).cameraAnchor
    }
    public var screenshotEntryExclusionFrames: [CGRect] {
        guard let layout = pagerLayout else { return [] }
        return layout.rows.flatMap { r in [r.imageClipFrame.offsetBy(dx: r.frame.minX, dy: r.frame.minY), r.numberFrame.offsetBy(dx: r.frame.minX, dy: r.frame.minY)] } + [layout.earlierArrowFrame, layout.laterArrowFrame].filter { !$0.isEmpty }
    }
    private var deferredConfiguration: RiftConfiguration?
    private var viewportAnchor: UUID?
    private var wheelGestureUsed = false
    private var lastWheelTime: TimeInterval = 0
    public var onGeometryChange: (() -> Void)?
    private let cache: ThumbnailCache
    private let onSelect: (UUID) -> Void
    private let onPress: (UUID, TimeInterval) -> Void
    private let onSelectionBoundary: (RiftSelectionBoundary) -> Void
    private let onApproach: () -> Void
    private let onPresentationBoundary: (RiftPresentationBoundary) -> Void
    private let onArrivalBoundary: (RiftArrivalBoundary) -> Void
    private let onRemove: (UUID) -> Void
    private let onOpenOriginal: (UUID) -> Void
    private var extraPreviewExclusions: [CGRect] = []
    public func setExtraPreviewExclusions(_ frames: [CGRect]) {
        guard frames != extraPreviewExclusions else { return }
        extraPreviewExclusions = frames; peek.cancel()
    }
    private let onInteractionChange: (RiftInteractionSnapshot) -> Void
    private let holdsSelectionUntilFinished: Bool
    private let interactionFence: QueueInteractionFence?
    private var interaction = RiftInteractionState()
    private var selectionVersions: [UUID: Int64] = [:]
    private var hoveredIDs: Set<UUID> = []
    private var pointerApproach = RiftPointerApproachState()
    private let decoration: RiftPanel
    private let pager = RiftPager()
    private var pagerLayout: RiftLayoutResult?
    private let peek = RiftPeek()
    private struct FeedbackState: Equatable {
        let owner: RiftFeedbackOwner?
        let revision: Int64
        let operationID: UUID?
        let text: String
        let timing: RiftFeedbackTiming
    }
    private var feedbackStates: [UUID: FeedbackState] = [:]
    private var rowWindows: [UUID: RowWindow] = [:]
    private var lastRecords: [AssetRecord] = []
    private var deferredRecords: [AssetRecord]?
    private var pendingRefillRecords: [AssetRecord]?
    private var refillTimer: Timer?
    private var refillOutsideSince: TimeInterval?
    private let detailProtectionToken = UUID()
    private var detailPresented = false
    public func setDetailPresented(_ presented: Bool) {
        detailPresented = presented
        mutateInteraction { state in
            if presented { state.beginAnimation(detailProtectionToken) }
            else { state.endAnimation(detailProtectionToken) }
        }
        if !presented { flushDeferred() }
    }
    private var committingRefill = false
    private var refillNotBefore: TimeInterval = 0
    var refillProtectionDeadline: TimeInterval { refillNotBefore }
    private func deferRefill(_ records: [AssetRecord]) {
        // Tombstones preserve slot geometry, never a decorative line to an absent image.
        let frames = rowWindows.values.map { row in
            row.view.geometry.imageFrame.offsetBy(dx: row.view.geometry.frame.minX, dy: row.view.geometry.frame.minY)
        }
        if let top = frames.map(\.maxY).max(), let bottom = frames.map(\.minY).min(), let old = pagerLayout?.lineFrame {
            decoration.setFrame(CGRect(x:old.minX,y:bottom,width:old.width,height:top-bottom),display:true)
        } else { decoration.orderOut(nil) }
        pendingRefillRecords = records
        refillNotBefore = ProcessInfo.processInfo.systemUptime + NSEvent.doubleClickInterval
        refillOutsideSince = nil
        guard refillTimer == nil else { return }
        refillTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tryRefill() }
        }
    }
    private func tryRefill() {
        evaluateRefillBoundary(now: ProcessInfo.processInfo.systemUptime, pointer: NSEvent.mouseLocation)
    }

    /// Same boundary evaluator for production timer and deterministic native tests.
    /// It cannot authorize input, change a receipt or create a queue operation.
    func evaluateRefillBoundary(now: TimeInterval, pointer: CGPoint) {
        guard !closed, let records = pendingRefillRecords else { refillTimer?.invalidate(); refillTimer = nil; return }
        refreshHoverFromPointer(point: pointer)
        let envelope = pagerLayout?.rows.reduce(CGRect.null) { $0.union($1.frame) } ?? .null
        guard !gate.isHolding, !transitioning, !detailPresented, !interaction.snapshot.blocksAutomaticArchive,
              !envelope.contains(pointer) else { refillOutsideSince = nil; return }
        if refillOutsideSince == nil { refillOutsideSince = now }
        guard now >= refillNotBefore, now - (refillOutsideSince ?? now) >= 0.35 else { return }
        pendingRefillRecords = nil; refillTimer?.invalidate(); refillTimer = nil
        committingRefill = true; render(records); committingRefill = false
        flushDeferred()
    }
    private var firstVisibleIndex = 0
    private var pageCapacity = 0
    private var gate = PointerSelectionGate()
    private var transitioning = false
    private var closed = false
    private var generation: UInt = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var scrollAccumulator: CGFloat = 0
    private let reduceMotionOverride: (() -> Bool)?
    private let flight = MagnetFlightPresenter()
    private struct ArrivalCandidate {
        let assetID: UUID
        let token: UUID
        let readyUptime: TimeInterval
        var source: RiftArrivalSource?
    }
    private var arrivalCandidate: ArrivalCandidate?
    private var arrivalAnimationToken: UUID?
    private var shortAnimationTokens = Set<UUID>()
    private var lastCaptureReadyUptime: TimeInterval?
    private var queueTransitionEpoch: UInt = 0
    private var finishQueueAnimation: ((Bool) -> Void)?
    private var pressRegions: [UUID: [CGRect]] = [:]
    /// Presentation budget only. Late metadata never replays an already shown image.
    private let maximumArrivalAge: TimeInterval = 0.35
    private let burstQuietInterval: TimeInterval = 0.45

    public var arrivalDiagnostic: RiftArrivalDiagnostic {
        RiftArrivalDiagnostic(selectedMode: arrivalMode, effectiveMode: effectiveArrivalMode,
            activeAssetID: flight.currentAssetID, pendingAssetID: arrivalCandidate?.assetID,
            overlayCount: flight.activePanelCount)
    }

    public var diagnosticSnapshot: RiftDiagnosticSnapshot {
        let rows = rowWindows.filter { $0.value.panel.isVisible }.map { id, row in
            RiftDiagnosticRow(assetID: id, ordinal: row.view.ordinal,
                windowNumber: row.panel.windowNumber, frame: row.panel.frame,
                imageClipFrame: row.panel.convertToScreen(row.view.convert(row.view.geometry.imageClipFrame, to: nil)),
                numberFrame: row.panel.convertToScreen(row.view.convert(row.view.geometry.numberFrame, to: nil)),
                imageInputWindowNumber: row.imageInput.windowNumber,
                numberInputWindowNumber: row.numberInput.windowNumber,
                imageInputFrame: row.imageInput.frame, numberInputFrame: row.numberInput.frame)
        }.sorted { $0.ordinal < $1.ordinal }
        return RiftDiagnosticSnapshot(rows: rows, lineFrame: decoration.isVisible ? decoration.frame : .zero,
                                      isHolding: gate.isHolding, isTransitioning: transitioning)
    }

    public init(mediaDirectory: URL, configuration: RiftConfiguration = .init(),
                arrivalMode: ArrivalMotionMode = .provisionalFallback,
                magnetParameters: MagnetMotionParameters = .init(),
                reduceMotionOverride: (() -> Bool)? = nil,
                onPress: @escaping (UUID, TimeInterval) -> Void = { _, _ in },
                onSelectionBoundary: @escaping (RiftSelectionBoundary) -> Void = { _ in },
                onApproach: @escaping () -> Void = {},
                onPresentationBoundary: @escaping (RiftPresentationBoundary) -> Void = { _ in },
                onArrivalBoundary: @escaping (RiftArrivalBoundary) -> Void = { _ in },
                holdsSelectionUntilFinished: Bool = false,
                interactionFence: QueueInteractionFence? = nil,
                onRemove: @escaping (UUID) -> Void = { _ in },
                onOpenOriginal: @escaping (UUID) -> Void = { _ in },
                onInteractionChange: @escaping (RiftInteractionSnapshot) -> Void = { _ in },
                onSelect: @escaping (UUID) -> Void) {
        // Configuration loaded from user data should be validated before construction.
        // Defensive fallback prevents malformed geometry from positioning windows off-screen.
        self.configuration = (try? configuration.validate()) != nil ? configuration : RiftConfiguration()
        self.arrivalMode = arrivalMode
        self.magnetParameters = magnetParameters
        self.reduceMotionOverride = reduceMotionOverride
        self.onSelect = onSelect
        self.onPress = onPress
        self.onSelectionBoundary = onSelectionBoundary
        self.onApproach = onApproach
        self.onPresentationBoundary = onPresentationBoundary
        self.onArrivalBoundary = onArrivalBoundary
        self.onRemove = onRemove
        self.onOpenOriginal = onOpenOriginal
        self.onInteractionChange = onInteractionChange
        self.holdsSelectionUntilFinished = holdsSelectionUntilFinished
        self.interactionFence = interactionFence
        cache = ThumbnailCache(directory: mediaDirectory)
        decoration = RiftPanel(frame: .zero, decorative: true)
        decoration.contentView = RiftLineView(frame: .zero)
        peek.onNoteVisibilityChange = { [weak self] id, _ in
            guard let self, let row = self.rowWindows[id] else { return }
            self.updateFeedbackDescription(row)
        }
        pager.onStep = { [weak self] direction in self?.page(direction) }
        observe(NSApplication.didChangeScreenParametersNotification, center: .default)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: NSWorkspace.shared.notificationCenter)
        let accessibility = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.motionPolicyChanged() }
            }
        observers.append((NSWorkspace.shared.notificationCenter, accessibility))
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { [self] in self.reflow() }
        }
        observers.append((center, token))
    }

    private var reduceMotion: Bool { reduceMotionOverride?() ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func duration(_ normal: Double) -> TimeInterval {
        reduceMotion ? min(0.08, normal) : normal
    }

    private var pressOffset: CGFloat { reduceMotion ? 0 : (configuration.placement?.side == .left ? -configuration.inwardDistance : configuration.inwardDistance) }

    /// Called immediately after import, independently of optional metadata/decode.
    /// One pending candidate and at most one flying copy; bursts settle statically.
    @discardableResult
    public func noteCaptureReady(_ assetID: UUID, uptime: TimeInterval) -> UUID? {
        cancelDecorations(reason: .captureObserved)
        finishQueueTransition(allowShift: false)
        let now = ProcessInfo.processInfo.systemUptime
        guard uptime.isFinite, uptime >= 0, uptime <= now else { return nil }
        let previous = lastCaptureReadyUptime
        // Invalid clocks cannot poison later captures, and an out-of-order old
        // observation cannot rewind the quiet interval to replay a burst flight.
        lastCaptureReadyUptime = max(previous ?? uptime, uptime)
        guard !closed, !userHidden, !captureSuppressed, effectiveArrivalMode == .magnet,
              now - uptime <= maximumArrivalAge,
              previous.map({ uptime - $0 >= burstQuietInterval }) ?? true,
              !lastRecords.contains(where: { $0.id == assetID }) else { return nil }
        let token = UUID()
        arrivalCandidate = ArrivalCandidate(assetID: assetID, token: token, readyUptime: uptime)
        return token
    }

    /// A result arriving after the first image decode is deliberately ignored.
    /// No metadata timeout, retry, hidden row or animation completion gates input.
    public func resolveArrivalSource(_ source: RiftArrivalSource?, assetID: UUID, token: UUID) {
        guard var candidate = arrivalCandidate, candidate.assetID == assetID,
              candidate.token == token, !closed, !userHidden, !captureSuppressed else { return }
        guard effectiveArrivalMode == .magnet, let source,
              ProcessInfo.processInfo.systemUptime - candidate.readyUptime <= maximumArrivalAge else {
            arrivalCandidate = nil; return
        }
        candidate.source = source; arrivalCandidate = candidate
    }

    /// Integration seam for screenshot UI suppression, hide, and topology changes.
    /// This can release decoration only; it cannot mutate a durable asset.
    public func cancelDecorations(reason: MagnetFlightEndReason = .cancelled) {
        arrivalCandidate = nil
        peek.cancel()
        flight.cancel(reason: reason)
    }

    public func setArrivalMode(_ mode: ArrivalMotionMode) {
        arrivalMode = mode; motionPolicyChanged()
    }

    private func motionPolicyChanged() {
        cancelDecorations(reason: reduceMotion ? .reduceMotion : .settingsChanged)
        finishQueueTransition(allowShift: false)
        for token in shortAnimationTokens { mutateInteraction { $0.endAnimation(token) } }
        shortAnimationTokens.removeAll()
        // Do not reset PointerSelectionGate or an accepted business selection.
        for row in rowWindows.values {
            row.view.animateImage(to: 0, duration: 0)
            row.view.resetArrivalImage()
            row.panels.forEach { $0.alphaValue = 1 }
        }
        flushDeferred()
    }

    private func finishQueueTransition(allowShift: Bool) {
        guard let finish = finishQueueAnimation else { return }
        finishQueueAnimation = nil; queueTransitionEpoch &+= 1
        finish(allowShift)
    }

    private var displaySession = RiftDisplaySessionSelection()
    private var restoreDisplayRequested = false
    public var displayRestoreAvailable: Bool { displaySession.restoreAvailable }
    public func restorePreferredDisplay() {
        guard !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting else { return }
        restoreDisplayRequested = true; reflow()
    }
    private var screen: NSScreen? {
        let screens = NSScreen.screens
        let displays = screens.compactMap { screen -> RiftDisplaySessionSelection.Display? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            return .init(id: id, uuid: uuid)
        }
        let mainID = (NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        defer { restoreDisplayRequested = false }
        guard let selected = displaySession.resolve(preferred: configuration.preferredDisplayID, uuid: configuration.preferredDisplayUUID,
            main: mainID, available: displays, restore: restoreDisplayRequested) else { return screens.first }
        return screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == selected
        }
    }

    public var interactionSnapshot: RiftInteractionSnapshot { interaction.snapshot }

    public var preferredScreen: NSScreen? { screen }

    public func setCaptureHeaderAnchor(_ anchor: CGPoint?) { /* R2 camera never extends the slit. */ }

    public func setCaptureSessionActive(_ active: Bool) {
        guard !closed else { return }
        captureSessionActive = active
        for panel in allPresentationPanels {
            panel.level = active ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .floating
        }
        updatePager()
    }

    public func setCaptureSuppressed(_ suppressed: Bool) {
        guard !closed, suppressed != captureSuppressed else { return }
        captureSuppressed = suppressed
        if suppressed {
            cancelDecorations(reason: .cancelled); pager.hide()
            allPresentationPanels.forEach { $0.orderOut(nil) }
        } else if !userHidden {
            // Restore the current presentation in place. lastRecords can still
            // describe the pre-swallow queue while a close/shift timer owns the
            // transition; re-applying it here would reverse that animation.
            rowWindows.values.forEach { row in row.panels.forEach { present($0) } }
            if !rowWindows.isEmpty && !decoration.frame.isEmpty { present(decoration) }
        }
        updatePager()
        refreshHoverFromPointer()
        onGeometryChange?()
    }

    private func updatePager() {
        guard let pagerLayout else { pager.hide(); return }
        pager.update(pagerLayout, hidden: captureSuppressed || userHidden || closed, level: decoration.level)
    }

    private var allPresentationPanels: [NSPanel] {
        [decoration, peek.presentationPanel] + rowWindows.values.flatMap { [$0.panel, $0.imageInput, $0.numberInput] }
    }

    /// The displayed version is captured before an asynchronous store call. A
    /// later archive response must not replace an accepted click with a new row.
    public func selectionRevision(for assetID: UUID) -> Int64? { selectionVersions[assetID] }

    private func mutateInteraction(_ update: (inout RiftInteractionState) -> Void) {
        let before = interaction.snapshot
        update(&interaction)
        let after = interaction.snapshot
        guard after != before else { return }
        // Synchronous fence update precedes callbacks/awaits. The store owns the
        // second transaction-side revision check; this UI cannot grant upload rights.
        interactionFence?.update(blocked: after.blocksAutomaticArchive)
        onInteractionChange(after)
    }

    private func setTransitioning(_ value: Bool) {
        transitioning = value
        mutateInteraction { $0.setTransitioning(value) }
    }

    private func trackAnimation(_ time: TimeInterval) {
        guard time > 0 else { return }
        let token = UUID(), epoch = generation
        shortAnimationTokens.insert(token)
        mutateInteraction { $0.beginAnimation(token) }
        DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
            guard let self, !self.closed, self.generation == epoch else { return }
            self.shortAnimationTokens.remove(token)
            self.mutateInteraction { $0.endAnimation(token) }
            self.flushDeferred()
        }
    }

    /// Called after durable prepare or a definite pre-input cancellation. It is
    /// intentionally separate from mouseUp so target capture cannot lose its row.
    public func finishSelection(_ assetID: UUID) {
        selectionVersions.removeValue(forKey: assetID)
        pressRegions.removeValue(forKey: assetID)
        mutateInteraction { $0.finishSelection(assetID) }
        flushDeferred()
    }

    public func setFeedback(_ reason: String?, for assetID: UUID,
                            owner: RiftFeedbackOwner? = nil, visibilityRevision: Int64? = nil,
                            timing: RiftFeedbackTiming = .immediate) {
        guard !closed, let row = rowWindows[assetID] else { return }
        guard let reason else {
            feedbackStates.removeValue(forKey: assetID)
            if peek.assetID == assetID { peek.cancel() }
            row.view.feedback = nil; updateFeedbackDescription(row)
            return
        }
        let record = row.view.record
        guard record.visibility == .visible,
              visibilityRevision == nil || visibilityRevision == record.visibilityRevision else { return }
        if let owner, case .operation(let operationID) = owner {
            guard operationID == record.activeOperationID, selectionVersions[assetID] == nil else { return }
        }
        let state = FeedbackState(owner: owner, revision: record.visibilityRevision,
            operationID: record.activeOperationID, text: String(reason.prefix(256)), timing: timing)
        // Repeated durable projections must not postpone the first 250ms
        // deadline or restart an already expired explanation.
        guard feedbackStates[assetID] != state else { return }
        if peek.assetID == assetID { peek.cancel() }
        feedbackStates[assetID] = state
        row.view.feedback = state.text; updateFeedbackDescription(row)
        scheduleFeedback(assetID, state: state, delay: timing == .waiting ? 0.25 : 0,
                         requiresPointer: timing == .waiting)
    }

    /// A completed waiting phase must not erase a newer cancellation or error.
    public func clearFeedback(matching reason: String, for assetID: UUID, owner: RiftFeedbackOwner? = nil) {
        guard rowWindows[assetID]?.view.feedback == reason,
              owner == nil || feedbackStates[assetID]?.owner == owner else { return }
        setFeedback(nil, for: assetID)
    }

    private func updateFeedbackDescription(_ row: RowWindow) {
        row.view.updateDescription()
        // Keep tooltip as the fallback, but do not stack the native tooltip on
        // the same visible custom explanation. AX retains the full reason.
        if peek.assetID == row.view.record.id, peek.isNoteVisible { row.view.toolTip = nil }
        for input in [row.imageInput, row.numberInput] { input.contentView?.toolTip = row.view.toolTip }
    }

    private func scheduleFeedback(_ id: UUID, state: FeedbackState, delay: TimeInterval,
                                  requiresPointer: Bool) {
        guard let row = rowWindows[id], !closed, !userHidden, !captureSuppressed,
              !gate.isHolding, !transitioning else { return }
        let island = [row.imageInput, row.numberInput].first {
            $0.isVisible && $0.frame.contains(NSEvent.mouseLocation)
        }
        if requiresPointer && island == nil { return }
        let token = generation
        peek.scheduleNote(id: id, text: state.text, delay: delay, leftSide: configuration.placement?.side == .left, stillValid: { [weak self] in
            guard let self else { return false }
            return !self.closed && !self.userHidden && !self.captureSuppressed
                && !self.gate.isHolding && !self.transitioning && self.generation == token
                && self.rowWindows[id]?.view === row.view && self.feedbackStates[id] == state
                && row.view.record.visibility == .visible && row.view.record.visibilityRevision == state.revision
                && row.view.record.activeOperationID == state.operationID
                && (!requiresPointer || (island?.isVisible == true && island?.frame.contains(NSEvent.mouseLocation) == true))
        }, anchor: { [weak self] in
            guard let self, let screen = self.screen else { return nil }
            let inputs = self.rowWindows.values.flatMap { [$0.imageInput, $0.numberInput] }
                .filter { $0.isVisible && !$0.frame.isEmpty }
            let frames = inputs.map(\.frame) + self.screenshotEntryExclusionFrames + self.extraPreviewExclusions
            guard let leading = self.configuration.placement?.side == .left
                ? frames.map(\.maxX).max() : frames.map(\.minX).min() else { return nil }
            return (row.panel.frame, screen.visibleFrame, leading)
        })
    }

    /// App persists this independent intent. No new image, wake, reflow or late
    /// animation may reverse it; only an explicit call with false shows the rift.
    public func setUserHidden(_ hidden: Bool) {
        guard !closed, hidden != userHidden else { return }
        userHidden = hidden
        resetWindows()
        if !hidden { apply(lastRecords) }
    }

    private func present(_ panel: NSPanel) {
        guard !closed, !userHidden, !captureSuppressed else { panel.orderOut(nil); return }
        panel.level = captureSessionActive ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .floating
        panel.orderFrontRegardless()
    }

    private func flushDeferred() {
        guard !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting, pendingRefillRecords == nil else { return }
        if let config = deferredConfiguration {
            deferredConfiguration = nil
            if configuration.preferredDisplayID != config.preferredDisplayID || configuration.preferredDisplayUUID != config.preferredDisplayUUID { displaySession.userSelectedDisplay() }
            configuration = config; reflow()
        }
        guard let records = deferredRecords else { return }
        deferredRecords = nil; render(records)
    }

    private func recordPresentation(_ phase: RiftPresentationPhase, record: AssetRecord,
                                    duration: TimeInterval) {
        onPresentationBoundary(RiftPresentationBoundary(phase: phase, assetID: record.id,
            operationID: record.activeOperationID, visibilityRevision: record.visibilityRevision,
            generation: generation, uptime: ProcessInfo.processInfo.systemUptime,
            actualDuration: duration))
    }

    /// Supply the committed visibility of newly swallowed records, even while
    /// their final backend result remains unresolved. READY never triggers UI exit.
    public func render(_ records: [AssetRecord]) {
        guard !closed else { return }
        if userHidden { lastRecords = records; deferredRecords = nil; return }
        if pendingRefillRecords != nil { pendingRefillRecords = records }
        let includesArchive = containsNewArchive(records)
        if includesArchive && interaction.snapshot.blocksAutomaticArchive {
            // Do not cancel the very decoration that currently protects a
            // just-committed archive from disappearing underneath the user.
            deferredRecords = records; return
        }
        if let id = flight.currentAssetID,
           !records.contains(where: { $0.id == id && $0.visibility == .visible
               && $0.status == .pending }) {
            cancelDecorations()
        }
        // New durable captures do not wait for a previous swallow/compaction.
        // Finish only the visual transition whose start was already committed.
        let known = Set(lastRecords.map(\.id))
        if transitioning && records.contains(where: {
            $0.visibility == .visible && $0.visibilityReason == .capture && !known.contains($0.id)
        }) && !gate.isHolding && !interaction.snapshot.isSelecting {
            deferredRecords = records
            finishQueueTransition(allowShift: false)
            return
        }
        if gate.isHolding || transitioning || interaction.snapshot.isSelecting
            || (includesArchive && interaction.snapshot.blocksAutomaticArchive) {
            // Also protects the post-commit/pre-render gap: a pointer may arrive
            // after the store archived a row but before its snapshot reaches UI.
            deferredRecords = records; return
        }
        let swallowed = records.filter {
            $0.visibility == .swallowed && $0.visibilityReason == .uploadStarted
                && rowWindows[$0.id]?.view.record.visibility == .visible
        }
        if swallowed.isEmpty, !committingRefill {
            let visible = Set(records.filter { $0.visibility == .visible }.map(\.id))
            let removed = rowWindows.keys.filter { !visible.contains($0) }
            if !removed.isEmpty {
                cancelDecorations(reason: .geometryChanged)
                for id in removed { rowWindows.removeValue(forKey: id)?.close() }
                deferRefill(records); return
            }
        }
        if swallowed.isEmpty, pendingRefillRecords != nil, !committingRefill { return }
        guard !swallowed.isEmpty else { apply(records, animateShift: committingRefill); return }
        cancelDecorations()
        let token = generation
        let swallowTime = duration(configuration.swallowDuration)
        // Scheduling is after existing hold/selection/transition deferral gates.
        for record in swallowed { recordPresentation(.swallowScheduled, record: record, duration: swallowTime) }
        // A true zero-time path: no alpha animator, translation, asyncAfter(0),
        // transition latch, or extra run-loop turn before final rows exist.
        if swallowTime == 0 {
            for record in swallowed {
                recordPresentation(.swallowActualStart, record: record, duration: 0)
                rowWindows.removeValue(forKey: record.id)?.close()
                recordPresentation(.swallowClose, record: record, duration: 0)
            }
            deferredRecords = nil
            deferRefill(records)
            return
        }
        setTransitioning(true); deferredRecords = records
        for record in swallowed {
            guard let window = rowWindows[record.id] else { continue }
            // Commit the presentation transition before any pending press-return
            // timer can run; that timer must never undo the inward exit motion.
            window.view.record = record
            recordPresentation(.swallowActualStart, record: record, duration: swallowTime)
            window.view.animateImage(to: self.reduceMotion ? 0 : (self.configuration.placement?.side == .left ? -56 : 56), duration: swallowTime, power: 1.35)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = swallowTime
                window.panels.forEach { $0.animator().alphaValue = 0 }
            }
        }
        queueTransitionEpoch &+= 1
        let transition = queueTransitionEpoch
        let began = ProcessInfo.processInfo.systemUptime
        finishQueueAnimation = { [weak self] allowShift in
            guard let self, !self.closed, !self.userHidden, self.generation == token else { return }
            for record in swallowed {
                if let window = self.rowWindows.removeValue(forKey: record.id) {
                    window.close()
                    self.recordPresentation(.swallowClose, record: record, duration: allowShift ? swallowTime
                        : min(swallowTime, max(0, ProcessInfo.processInfo.systemUptime - began)))
                }
            }
            self.setTransitioning(false)
            let next = self.deferredRecords ?? records
            self.deferredRecords = nil
            self.deferRefill(next)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + swallowTime) { [weak self] in
            guard let self, self.queueTransitionEpoch == transition else { return }
            self.finishQueueTransition(allowShift: true)
        }
    }

    private func apply(_ records: [AssetRecord], animateShift: Bool = false) {
        guard !closed else { return }
        guard !userHidden else { lastRecords = records; return }
        guard let screen else {
            cancelDecorations(reason: .geometryChanged)
            rowWindows.values.forEach { $0.orderOut() }
            decoration.orderOut(nil); lastRecords = records; return
        }
        if let anchor = viewportAnchor {
            let active = records.filter { $0.visibility == .visible }
            let survivors = [anchor] + (pagerLayout?.rows.map(\.assetID) ?? [])
            firstVisibleIndex = RiftLayout.survivingAnchorIndex(previous: survivors,
                current: active.map(\.id), fallback: firstVisibleIndex)
        }
        let queueFrame = screen.visibleFrame
        let makeLayout = { (index: Int) in
            RiftLayout.make(records: records, visibleFrame: queueFrame,
                configuration: self.configuration, firstVisibleIndex: index,
                backingScale: screen.backingScaleFactor,
                highContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        }
        let layout = makeLayout(firstVisibleIndex)
        viewportAnchor = layout.rows.first?.assetID
        let shiftTime = reduceMotion ? 0 : configuration.shiftDuration
        let movingFrames = Dictionary(uniqueKeysWithValues: layout.rows.compactMap { geometry -> (UUID, CGRect)? in
            guard animateShift, shiftTime > 0, let row = rowWindows[geometry.assetID],
                  row.panel.frame != geometry.frame else { return nil }
            return (geometry.assetID, row.panel.frame)
        })
        let shouldShift = !movingFrames.isEmpty
        firstVisibleIndex = layout.firstVisibleIndex
        pageCapacity = layout.capacity
        visibleRange = firstVisibleIndex..<(firstVisibleIndex + layout.rows.count)
        if let flyingID = flight.currentAssetID,
           let old = rowWindows[flyingID],
           layout.rows.first(where: { $0.assetID == flyingID }) != old.view.geometry {
            cancelDecorations(reason: .geometryChanged)
        }
        let visibleIDs = Set(layout.rows.map(\.assetID))
        if let previewID = peek.assetID {
            let old = rowWindows[previewID]?.view
            let next = layout.rows.first { $0.assetID == previewID }
            let nextRecord = records.first { $0.id == previewID }
            let visibleGeometryChanged = layout.rows.count != rowWindows.count
                || layout.rows.contains { $0 != rowWindows[$0.assetID]?.view.geometry }
            if next == nil || visibleGeometryChanged || nextRecord?.visibilityRevision != old?.record.visibilityRevision
                || nextRecord?.activeOperationID != old?.record.activeOperationID {
                peek.cancel()
            }
        }
        for id in Array(rowWindows.keys) where !visibleIDs.contains(id) {
            flight.cancel(assetID: id)
            feedbackStates.removeValue(forKey: id)
            rowWindows.removeValue(forKey: id)?.close()
        }
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let token = generation
        for geometry in layout.rows {
            guard let record = byID[geometry.assetID] else { continue }
            let window: RowWindow
            let isNew: Bool
            if let existing = rowWindows[record.id] { window = existing; isNew = false }
            else {
                window = RowWindow(record: record, geometry: geometry, configuration: configuration)
                rowWindows[record.id] = window
                wire(window, id: record.id)
                isNew = true
            }
            let oldStatus = window.view.record.status
            if window.view.record.visibilityRevision != record.visibilityRevision
                || window.view.record.activeOperationID != record.activeOperationID {
                feedbackStates.removeValue(forKey: record.id)
                window.view.feedback = nil
            }
            window.view.record = record
            window.view.configuration = configuration
            // Each frame moves the visual panel and its two input islands together.
            // A press finishes the decoration while retaining the original asset/regions.
            if movingFrames[record.id] == nil {
                window.view.updateGeometry(geometry)
                window.view.ordinal = geometry.ordinal
            }
            updateFeedbackDescription(window)
            window.panel.setFrame(movingFrames[record.id] ?? geometry.frame, display: true)
            window.syncInputFrames()
            window.panels.forEach { present($0) }
            // The press response ends independently of upload completion. A
            // pre-start UNKNOWN is retained without a perpetual pressed pose.
            let expectedOffset: CGFloat = 0
            if isNew {
                // Input windows and the final queue position exist immediately.
                // Only an optional, independently owned image copy may animate.
                window.panels.forEach { $0.alphaValue = 1 }
                window.view.animateImage(to: expectedOffset, duration: 0)
                reportArrival(.rowAvailable, id: record.id)
            } else if oldStatus != record.status || window.view.imageOffset != expectedOffset {
                window.view.animateImage(to: expectedOffset, duration: duration(
                    record.status == .failed ? configuration.returnDuration : configuration.pressDuration))
            }
            let hasCandidate = arrivalCandidate?.assetID == record.id && effectiveArrivalMode == .magnet
            let normalLongest = CGFloat(max(configuration.fitWidth, configuration.fitHeight))
            let longest = hasCandidate ? max(normalLongest,
                max(magnetParameters.initialMaximumSize.width, magnetParameters.initialMaximumSize.height))
                : normalLongest
            let pixels = max(window.view.requestedPixelSize, Int(ceil(longest * screen.backingScaleFactor)))
            window.view.requestedPixelSize = pixels
            let revision = record.visibilityRevision
            cache.image(for: record.image, maxPixelSize: pixels) { [weak self, weak view = window.view] image in
                guard let self, let view, !self.closed, !self.userHidden, self.generation == token,
                      self.rowWindows[record.id]?.view === view,
                      view.record.visibility == .visible, view.record.visibilityRevision == revision else { return }
                // Only this new candidate may hand its image to a flight. Hide
                // it in the same transaction that publishes the decoded pixels,
                // before any native flight-window ordering can display them.
                let arrivalOwner = isNew && image != nil && self.effectiveArrivalMode == .magnet
                    && self.arrivalCandidate?.assetID == record.id ? self.arrivalCandidate?.token : nil
                // Exactly the same decoded pixels are used for source and row.
                view.setImage(image, arrivalOwner: arrivalOwner)
                if image != nil, !view.reportedImageReady {
                    view.reportedImageReady = true
                    self.reportArrival(.imageDecoded, id: record.id)
                }
                if let arrivalOwner, let image {
                    if !self.startArrivalIfPossible(id: record.id, image: image, owner: arrivalOwner) {
                        // A rejected/cancelled handoff is an immediate static
                        // fallback. A stale owner cannot reveal a newer flight.
                        view.restoreArrivalImage(owner: arrivalOwner)
                    }
                }
                else if isNew, self.arrivalCandidate?.assetID == record.id { self.arrivalCandidate = nil }
            }
        }
        let lineFrame = layout.lineFrame
        decoration.setFrame(lineFrame, display: true)
        decoration.contentView?.frame = CGRect(origin: .zero, size: lineFrame.size)
        if !layout.rows.isEmpty && !layout.lineFrame.isEmpty { present(decoration) }
        else { decoration.orderOut(nil) }
        pagerLayout = layout; updatePager()
        lastRecords = records
        refreshHoverFromPointer()
        onGeometryChange?()
        if shouldShift {
            setTransitioning(true)
            queueTransitionEpoch &+= 1
            let transition = queueTransitionEpoch
            let began = ProcessInfo.processInfo.systemUptime
            finishQueueAnimation = { [weak self] _ in
                guard let self, !self.closed, self.generation == token else { return }
                for geometry in layout.rows {
                    guard let row = self.rowWindows[geometry.assetID] else { continue }
                    row.view.updateGeometry(geometry)
                    row.view.ordinal = geometry.ordinal; row.view.updateDescription()
                    row.panel.setFrame(geometry.frame, display: true)
                    row.syncInputFrames()
                }
                self.setTransitioning(false)
                self.refreshHoverFromPointer()
                self.onGeometryChange?()
                self.flushDeferred()
            }
            func step() {
                guard !self.closed, self.generation == token, self.queueTransitionEpoch == transition else { return }
                let t = min(1, max(0, (ProcessInfo.processInfo.systemUptime - began) / shiftTime))
                let eased = 1 - pow(1 - t, 3)
                for geometry in layout.rows {
                    guard let start = movingFrames[geometry.assetID], let row = self.rowWindows[geometry.assetID] else { continue }
                    // Keep the old local width/ordinal and the fixed plane
                    // until completion, including the 10→9 digit boundary.
                    var frame = start
                    frame.origin.y = start.minY + (geometry.frame.minY - start.minY) * eased
                    row.panel.setFrame(frame, display: true)
                    row.syncInputFrames()
                }
                if t >= 1 { self.finishQueueTransition(allowShift: false) }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { step() } }
            }
            step()
        }
    }

    private func startArrivalIfPossible(id: UUID, image: CGImage, owner: UUID) -> Bool {
        guard let candidate = arrivalCandidate, candidate.assetID == id,
              candidate.token == owner else { return false }
        arrivalCandidate = nil
        guard !closed, !userHidden, !captureSuppressed, effectiveArrivalMode == .magnet,
              selectionVersions[id] == nil, !gate.isHolding, !transitioning,
              ProcessInfo.processInfo.systemUptime - candidate.readyUptime <= maximumArrivalAge,
              let source = candidate.source, let screen, let row = rowWindows[id],
              row.view.ownsArrivalImage(owner),
              row.view.record.visibility == .visible, row.view.record.status == .pending,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              source.displayID == displayID, source.displayFrame == screen.frame,
              source.backingScale == screen.backingScaleFactor else { return false }
        let target = row.panel.convertToScreen(row.view.convert(row.view.geometry.imageFrame, to: nil))
        let clip = row.panel.convertToScreen(row.view.convert(row.view.geometry.imageClipFrame, to: nil))
        let left = configuration.placement?.side == .left
        let edge = left ? clip.minX : clip.maxX
        guard let plan = MagnetMotionPlan(sourceRect: source.rect, targetImageFrame: target,
            clippingEdgeX: edge, screenFrame: screen.frame, parameters: magnetParameters, leftSide: left) else { return false }
        let token = UUID(), epoch = generation, revision = row.view.record.visibilityRevision
        let started = flight.start(assetID: id, image: image, plan: plan,
            backingScale: screen.backingScaleFactor,
            elapsedSinceAssetReady: ProcessInfo.processInfo.systemUptime - candidate.readyUptime,
            onAnimationObservation: { [weak self] event in
                guard let self else { return }
                let phase: RiftArrivalPhase = event.phase == .started ? .animationDelegateStarted : .animationDelegateStopped
                let finished = event.finished.map { String($0) } ?? "none"
                self.onArrivalBoundary(RiftArrivalBoundary(phase: phase, assetID: id, uptime: event.uptime,
                    mode: self.effectiveArrivalMode,
                    reason: "finished=\(finished);callbackMainThread=\(event.wasMainThread)"))
            }) { [weak self, weak view = row.view] completion in
                guard let self else { return }
                if let view, self.rowWindows[id]?.view === view,
                   view.record.visibilityRevision == revision { view.restoreArrivalImage(owner: owner) }
                if self.arrivalAnimationToken == token {
                    self.arrivalAnimationToken = nil
                    self.mutateInteraction { $0.endAnimation(token) }
                }
                self.reportArrival(.decorationEnded, id: id, reason: completion.reason.rawValue)
                if [.finished, .timedOut].contains(completion.reason), self.generation == epoch { self.flushDeferred() }
            }
        if started {
            if decoration.isVisible { present(decoration) }
            arrivalAnimationToken = token
            mutateInteraction { $0.beginAnimation(token) }
            reportArrival(.decorationStarted, id: id)
        }
        return started
    }

    private func reportArrival(_ phase: RiftArrivalPhase, id: UUID, reason: String? = nil) {
        onArrivalBoundary(RiftArrivalBoundary(phase: phase, assetID: id,
            uptime: ProcessInfo.processInfo.systemUptime, mode: effectiveArrivalMode, reason: reason))
    }

    private func refreshHoverFromPointer(point: CGPoint = NSEvent.mouseLocation) {
        // Event/geometry driven only: also catches a newly shown row underneath a
        // stationary pointer. This is not a global mouse polling timer.
        hoveredIDs = userHidden ? [] : Set(rowWindows.compactMap { id, row in
            row.panel.isVisible && [row.imageInput, row.numberInput].contains(where: {
                $0.isVisible && $0.frame.contains(point)
            }) ? id : nil
        })
        pointerApproach.update(hovered: hoveredIDs)
        mutateInteraction { $0.setHovered(hoveredIDs) }
    }

    private func returnPress(_ id: UUID) {
        guard let row = rowWindows[id], !userHidden, row.view.record.visibility == .visible else { return }
        let time = duration(0.08)
        trackAnimation(time)
        row.view.animateImage(to: 0, duration: time)
    }

    private func wire(_ window: RowWindow, id: UUID) {
        window.view.onHover = { [weak self] inside in
            guard let self, !self.userHidden, !self.closed else { return }
            // Use both input islands so an exit from one cannot clear a hover
            // already inside the other. Event-driven only; no polling timer.
            self.refreshHoverFromPointer()
            if self.hoveredIDs.contains(id) { self.schedulePeek(id) }
            else if self.peek.assetID == id { self.peek.leave() }
            self.flushDeferred()
        }
        window.view.onPreview = { [weak self] in
            guard let self, self.rowWindows[id] != nil, !self.gate.isHolding,
                  !self.transitioning, !self.userHidden, !self.captureSuppressed else { return false }
            self.schedulePeek(id, immediate: true); return true
        }
        window.view.onApproach = { [weak self] in
            guard let self, !self.closed, !self.captureSuppressed, !self.gate.isHolding,
                  !self.transitioning, !self.userHidden, self.pointerApproach.enter(id) else { return }
            self.onApproach()
        }
        window.view.onMenuVisibility = { [weak self] open in
            guard let self, !self.closed else { return }
            if open { self.peek.cancel() }
            self.mutateInteraction { $0.setMenu(id, open: open) }
            if !open { self.flushDeferred() }
        }
        window.view.onOpenOriginal = { [weak self] in
            guard let self, !self.gate.isHolding, !self.transitioning, self.rowWindows[id] != nil else { return }
            self.peek.cancel(); self.onOpenOriginal(id)
        }
        window.view.onRemove = { [weak self] in
            guard let self, !self.gate.isHolding, !self.transitioning,
                  !self.userHidden, self.selectionVersions[id] == nil else { return }
            self.onRemove(id)
        }
        let inputWindowNumbers: Set<Int> = [window.imageInput.windowNumber, window.numberInput.windowNumber]
        window.view.onDown = { [weak self, weak view = window.view] event in
            guard let self, let view, let eventWindow = event.window,
                  inputWindowNumbers.contains(eventWindow.windowNumber) else { return false }
            self.peek.cancel()
            let point = eventWindow.convertPoint(toScreen: event.locationInWindow)
            let originalRegions = self.rowWindows[id].map { [$0.imageInput.frame, $0.numberInput.frame] } ?? []
            // A decorative queue move is interruptible. Preserve the ORIGINAL
            // asset and press regions if snapping its windows changes geometry.
            self.finishQueueTransition(allowShift: false)
            let accepts = !self.closed && !self.userHidden && !self.captureSuppressed && self.rowWindows[id]?.view === view
                && self.selectionVersions[id] == nil
                && view.record.visibility == .visible && view.record.status != .transferring
                && view.record.status != .used
            let accepted = self.gate.begin(assetID: id, screenPoint: point, timestamp: event.timestamp,
                                          clickCount: event.clickCount, doubleClickInterval: NSEvent.doubleClickInterval,
                                          acceptsSelection: accepts)
            if accepted {
                self.selectionVersions[id] = view.record.visibilityRevision
                self.pressRegions[id] = originalRegions
                self.mutateInteraction { $0.beginSelection(id, held: true) }
                self.cancelDecorations(reason: .clicked)
                self.setFeedback(nil, for: id)
                self.onPress(id, event.timestamp)
                self.onSelectionBoundary(RiftSelectionBoundary(assetID: id, source: .mouse,
                    eventUptime: event.timestamp, eventNumber: event.eventNumber,
                    windowNumber: event.windowNumber, clickCount: event.clickCount))
                let time = self.duration(self.configuration.pressDuration)
                self.trackAnimation(time)
                view.animateImage(to: self.pressOffset, duration: time)
            }
            return accepted
        }
        window.view.onUp = { [weak self] inside, releasePoint in
            guard let self, !self.closed, self.interaction.heldID == id else { return }
            let held = self.interaction.heldID
            let originalInside = releasePoint.map { point in
                self.pressRegions[id]?.contains(where: { $0.contains(point) }) ?? false
            } ?? false
            let selected = self.gate.end(inside: inside || originalInside)
            self.pressRegions.removeValue(forKey: id)
            self.mutateInteraction { $0.releasePointer(accepted: selected != nil) }
            if let held, selected == nil {
                self.selectionVersions.removeValue(forKey: held)
                self.returnPress(held)
            }
            if let selected {
                self.onSelect(selected)
                if !self.holdsSelectionUntilFinished { self.finishSelection(selected) }
                // Presentation only: a rejected or still-awaiting-input click
                // naturally releases its pressed pose without forging a receipt.
                let epoch = self.generation
                let pressTime = self.duration(self.configuration.pressDuration)
                if pressTime > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + pressTime) { [weak self] in
                        guard let self, !self.closed, self.generation == epoch else { return }
                        self.returnPress(selected)
                    }
                }
            }
            self.flushDeferred()
        }
        window.view.onScroll = { [weak self] delta in self?.scroll(delta) }
        window.view.onAccessiblePress = { [weak self, weak view = window.view] in
            guard let self, let view, !self.closed, !self.userHidden, !self.captureSuppressed, !self.gate.isHolding else { return false }
            self.finishQueueTransition(allowShift: false)
            guard self.rowWindows[id]?.view === view,
                  self.selectionVersions[id] == nil, view.record.visibility == .visible,
                  [.pending, .failed, .unknown, .missing].contains(view.record.status) else { return false }
            let invocationUptime = ProcessInfo.processInfo.systemUptime
            self.selectionVersions[id] = view.record.visibilityRevision
            self.mutateInteraction { $0.beginSelection(id, held: false) }
            self.cancelDecorations(reason: .clicked)
            self.setFeedback(nil, for: id)
            self.onPress(id, invocationUptime)
            self.onSelectionBoundary(RiftSelectionBoundary(assetID: id, source: .accessibility,
                eventUptime: invocationUptime))
            let time = self.duration(self.configuration.pressDuration)
            self.trackAnimation(time)
            view.animateImage(to: self.pressOffset, duration: time)
            self.onSelect(id)
            if !self.holdsSelectionUntilFinished { self.finishSelection(id) }
            let epoch = self.generation
            if time > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                    guard let self, !self.closed, self.generation == epoch else { return }
                    self.returnPress(id)
                }
            }
            return true
        }
    }

    private func schedulePeek(_ id: UUID, immediate: Bool = false) {
        // An explicit preview action still opens the image. Ordinary hover
        // reads the current reason first, on the very same pointer-free panel.
        if !immediate, let state = feedbackStates[id] {
            scheduleFeedback(id, state: state, delay: 0.45, requiresPointer: true)
            return
        }
        guard let row = rowWindows[id], let screen, !closed, !userHidden, !captureSuppressed,
              !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting else { return }
        let revision = row.view.record.visibilityRevision
        peek.schedule(id: id, immediate: immediate, leftSide: configuration.placement?.side == .left, stillValid: { [weak self] in
            guard let self else { return false }
            return !self.closed && !self.userHidden && !self.captureSuppressed && !self.gate.isHolding
                && !self.transitioning && !self.interaction.snapshot.isSelecting
                && self.rowWindows[id]?.view === row.view && row.view.record.visibility == .visible
                && row.view.record.visibilityRevision == revision
                && (immediate || self.hoveredIDs.contains(id))
        }, load: { [weak self] completion in
            self?.cache.image(for: row.view.record.image, maxPixelSize: Int(320 * screen.backingScaleFactor), completion: completion)
        }, anchor: { [weak self] in
            guard let self, let screen = self.screen else { return nil }
            let inputs = self.rowWindows.values.flatMap { [$0.imageInput, $0.numberInput] }
                .filter { $0.isVisible && !$0.frame.isEmpty }
            let frames = inputs.map(\.frame) + self.screenshotEntryExclusionFrames + self.extraPreviewExclusions
            guard let leading = self.configuration.placement?.side == .left
                ? frames.map(\.maxX).max() : frames.map(\.minX).min() else { return nil }
            return (row.panel.frame, screen.visibleFrame, leading)
        })
    }

    private func page(_ direction: Int) {
        guard !userHidden, !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting, pendingRefillRecords == nil else { return }
        let next = RiftLayout.pageStart(from: firstVisibleIndex, direction: direction,
            totalCount: lastRecords.filter { $0.visibility == .visible }.count, capacity: pageCapacity)
        guard next != firstVisibleIndex else { return }
        cancelDecorations()
        viewportAnchor = nil; firstVisibleIndex = next
        apply(lastRecords)
        let epoch = generation
        let plan = RiftPageTransition(direction: direction, reduceMotion: reduceMotion)
        let destinations = rowWindows.values.flatMap { $0.panels }.map { ($0, $0.frame) }
        setTransitioning(true)
        for row in rowWindows.values { row.imageInput.ignoresMouseEvents = true; row.numberInput.ignoresMouseEvents = true }
        for (panel, frame) in destinations { panel.alphaValue = 0; panel.setFrame(plan.initialFrame(for: frame), display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = plan.duration
            for (panel, frame) in destinations {
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.closed, self.generation == epoch else { return }
                for row in self.rowWindows.values { row.imageInput.ignoresMouseEvents = false; row.numberInput.ignoresMouseEvents = false }
                self.setTransitioning(false); self.flushDeferred()
            }
        }
    }

    private func scroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) || (event.phase.isEmpty && event.timestamp - lastWheelTime > 0.35) {
            wheelGestureUsed = false; scrollAccumulator = 0
        }
        lastWheelTime = event.timestamp
        guard !wheelGestureUsed else { return }
        scrollAccumulator += event.scrollingDeltaY
        guard abs(scrollAccumulator) >= 8 else { return }
        wheelGestureUsed = true
        page(scrollAccumulator < 0 ? 1 : -1)
        scrollAccumulator = 0
    }

    public func showLatest() {
        guard !userHidden, !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting, pendingRefillRecords == nil else { return }
        cancelDecorations()
        viewportAnchor = nil
        firstVisibleIndex = lastRecords.filter { $0.visibility == .visible }.count
        apply(lastRecords)
    }

    /// Explicit history restoration may reveal one existing item without
    /// changing its sort order or reversing the independent user-hidden intent.
    public func showAsset(_ assetID: UUID) {
        guard !userHidden, !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting, pendingRefillRecords == nil,
              let index = lastRecords.filter({ $0.visibility == .visible }).firstIndex(where: { $0.id == assetID }) else { return }
        guard !visibleRange.contains(index) else { return }
        cancelDecorations()
        viewportAnchor = nil
        firstVisibleIndex = index
        apply(lastRecords)
    }

    public func showOldest() {
        guard !userHidden, !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting, pendingRefillRecords == nil else { return }
        cancelDecorations()
        viewportAnchor = nil
        firstVisibleIndex = 0; apply(lastRecords)
    }

    public func updateConfiguration(_ configuration: RiftConfiguration) throws {
        try configuration.validate()
        guard !gate.isHolding, !interaction.snapshot.isSelecting, !transitioning, pendingRefillRecords == nil else {
            deferredConfiguration = configuration; return
        }
        deferredConfiguration = nil
        if self.configuration.preferredDisplayID != configuration.preferredDisplayID || self.configuration.preferredDisplayUUID != configuration.preferredDisplayUUID { displaySession.userSelectedDisplay() }
        self.configuration = configuration
        reflow()
    }

    private func containsNewArchive(_ records: [AssetRecord]) -> Bool {
        let previousVisible = Set(lastRecords.filter { $0.visibility == .visible }.map(\.id))
        return records.contains { $0.visibility == .archived && previousVisible.contains($0.id) }
    }

    private func resetWindows() {
        cancelDecorations(reason: userHidden ? .hidden : .geometryChanged)
        finishQueueAnimation = nil; queueTransitionEpoch &+= 1
        generation &+= 1; transitioning = false
        let held = interaction.heldID
        gate.cancel()
        if let held { selectionVersions.removeValue(forKey: held) }
        lastRecords = pendingRefillRecords ?? deferredRecords ?? lastRecords
        pendingRefillRecords = nil; refillTimer?.invalidate(); refillTimer = nil
        deferredRecords = nil
        hoveredIDs.removeAll(); pointerApproach.update(hovered: [])
        pressRegions.removeAll(); shortAnimationTokens.removeAll()
        mutateInteraction { $0.resetPresentation() }
        if detailPresented { mutateInteraction { $0.beginAnimation(detailProtectionToken) } }
        rowWindows.values.forEach { $0.close() }
        rowWindows.removeAll()
        feedbackStates.removeAll()
        visibleRange = 0..<0
        decoration.orderOut(nil); pagerLayout = nil; pager.hide(); peek.cancel()
    }

    private func reflow() {
        guard !closed else { return }
        guard !gate.isHolding, !interaction.snapshot.isSelecting, pendingRefillRecords == nil else { return }
        let pending = deferredRecords
        let displayed = lastRecords
        let protectedArchive = pending.map { containsNewArchive($0) && interaction.snapshot.blocksAutomaticArchive } ?? false
        resetWindows()
        if protectedArchive && !userHidden { lastRecords = displayed }
        if !userHidden { apply(lastRecords) }
        // A wake/display event must not bypass an archive already deferred for
        // a pointer or an accepted selection. Recheck after new geometry exists.
        if protectedArchive, let pending { render(pending) }
    }

    public func close() {
        guard !closed else { return }
        cancelDecorations(reason: .closed); flight.close()
        finishQueueAnimation = nil; queueTransitionEpoch &+= 1
        closed = true; generation &+= 1; gate.cancel()
        pressRegions.removeAll(); shortAnimationTokens.removeAll()
        selectionVersions.removeAll(); hoveredIDs.removeAll(); pointerApproach.update(hovered: []); feedbackStates.removeAll()
        mutateInteraction { $0.close() }
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        refillTimer?.invalidate(); refillTimer = nil; pendingRefillRecords = nil
        rowWindows.values.forEach { $0.close() }; rowWindows.removeAll()
        decoration.close(); pager.close(); peek.close(); cache.clear()
    }

    deinit { observers.forEach { $0.0.removeObserver($0.1) } }
}
