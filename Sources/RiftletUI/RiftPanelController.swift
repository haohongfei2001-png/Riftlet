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
    public let windowNumber: Int
    public let frame: CGRect
    public let imageClipFrame: CGRect
    public let numberFrame: CGRect
}

public struct RiftDiagnosticSnapshot: Sendable {
    public let rows: [RiftDiagnosticRow]
    public let lineFrame: CGRect
    public let isHolding: Bool
    public let isTransitioning: Bool
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
    var onDown: ((NSEvent) -> Bool)?
    var onUp: ((Bool) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var onAccessiblePress: (() -> Bool)?
    var onApproach: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onRemove: (() -> Void)?
    var onMenuVisibility: ((Bool) -> Void)?
    var feedback: String?
    private var approachTracking: NSTrackingArea?

    init(record: AssetRecord, geometry: RiftRowLayout, configuration: RiftConfiguration) {
        self.record = record; self.geometry = geometry; self.configuration = configuration
        ordinal = geometry.ordinal
        super.init(frame: NSRect(origin: .zero, size: geometry.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageClip.masksToBounds = true
        layer?.addSublayer(imageClip)
        imageClip.addSublayer(imageLayer)
        imageLayer.contentsGravity = .resizeAspect
        updateGeometry(geometry)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
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
        let remove = NSMenuItem(title: "Remove from Riftlet", action: #selector(removeFromRift(_:)), keyEquivalent: "")
        remove.target = self; menu.addItem(remove); menu.delegate = self
        return menu
    }

    @objc private func removeFromRift(_ sender: NSMenuItem) { onRemove?() }
    func menuWillOpen(_ menu: NSMenu) { onMenuVisibility?(true) }
    func menuDidClose(_ menu: NSMenu) { onMenuVisibility?(false) }

    func updateGeometry(_ geometry: RiftRowLayout) {
        self.geometry = geometry
        frame.size = geometry.frame.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageClip.frame = geometry.imageClipFrame
        imageLayer.setAffineTransform(.identity)
        imageLayer.frame = CGRect(origin: .zero, size: geometry.imageFrame.size)
        imageLayer.setAffineTransform(CGAffineTransform(translationX: imageOffset, y: 0))
        CATransaction.commit()
        needsDisplay = true
    }

    func setImage(_ image: CGImage?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.contents = image
        CATransaction.commit()
        needsDisplay = true
    }

    func updateDescription() {
        let suffix: String
        switch record.status {
        case .pending: suffix = "ready to attach"
        case .transferring: suffix = "attachment pending"
        case .unknown: suffix = "result unknown, retained"
        case .failed: suffix = "attachment failed, retained"
        case .missing: suffix = "private image missing"
        case .used: suffix = "attachment verified"
        }
        setAccessibilityLabel("Screenshot \(ordinal), \(suffix)")
        toolTip = feedback ?? "Screenshot \(ordinal) · \(suffix). Scroll for earlier or later captures."
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = NSFont.monospacedDigitSystemFont(ofSize: configuration.numberFontSize, weight: .regular)
        let text = NSAttributedString(string: String(ordinal), attributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor
        ])
        text.draw(in: geometry.numberFrame)
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

    func animateImage(to offset: CGFloat, duration: TimeInterval) {
        let start = imageLayer.presentation()?.affineTransform().tx ?? imageOffset
        imageOffset = offset
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.setAffineTransform(CGAffineTransform(translationX: offset, y: 0))
        CATransaction.commit()
        guard duration > 0 else { imageLayer.removeAllAnimations(); return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = start; animation.toValue = offset; animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        imageLayer.add(animation, forKey: "rift.translation")
    }

    override func mouseDown(with event: NSEvent) {
        guard geometry.containsSelectionPoint(convert(event.locationInWindow, from: nil)) else { return }
        _ = onDown?(event)
    }
    override func mouseUp(with event: NSEvent) {
        onUp?(geometry.containsSelectionPoint(convert(event.locationInWindow, from: nil)))
    }
    override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY) }
    override func accessibilityPerformPress() -> Bool { onAccessiblePress?() ?? false }
}

private struct RowWindow {
    let panel: RiftPanel
    let view: RiftRowView
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

/// The UI consumes committed state only. It has no adapter, receipt policy or file-deletion API.
/// Per-row input windows leave genuine window-free gaps; the entire line is click-through.
/// Actual transparent-pixel hit behavior, first-click focus and Spaces require Mac GUI validation.
@MainActor
public final class RiftPanelController {
    public private(set) var configuration: RiftConfiguration
    public private(set) var visibleRange: Range<Int> = 0..<0
    public private(set) var userHidden = false
    private let cache: ThumbnailCache
    private let onSelect: (UUID) -> Void
    private let onPress: (UUID, TimeInterval) -> Void
    private let onSelectionBoundary: (RiftSelectionBoundary) -> Void
    private let onApproach: () -> Void
    private let onPresentationBoundary: (RiftPresentationBoundary) -> Void
    private let onRemove: (UUID) -> Void
    private let onInteractionChange: (RiftInteractionSnapshot) -> Void
    private let holdsSelectionUntilFinished: Bool
    private let interactionFence: QueueInteractionFence?
    private var interaction = RiftInteractionState()
    private var selectionVersions: [UUID: Int64] = [:]
    private var hoveredIDs: Set<UUID> = []
    private let decoration: RiftPanel
    private var rowWindows: [UUID: RowWindow] = [:]
    private var lastRecords: [AssetRecord] = []
    private var deferredRecords: [AssetRecord]?
    private var firstVisibleIndex = 0
    private var gate = PointerSelectionGate()
    private var transitioning = false
    private var closed = false
    private var generation: UInt = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var scrollAccumulator: CGFloat = 0

    public var diagnosticSnapshot: RiftDiagnosticSnapshot {
        let rows = rowWindows.filter { $0.value.panel.isVisible }.map { id, row in
            RiftDiagnosticRow(assetID: id, ordinal: row.view.ordinal,
                windowNumber: row.panel.windowNumber, frame: row.panel.frame,
                imageClipFrame: row.panel.convertToScreen(row.view.convert(row.view.geometry.imageClipFrame, to: nil)),
                numberFrame: row.panel.convertToScreen(row.view.convert(row.view.geometry.numberFrame, to: nil)))
        }.sorted { $0.ordinal < $1.ordinal }
        return RiftDiagnosticSnapshot(rows: rows, lineFrame: decoration.isVisible ? decoration.frame : .zero,
                                      isHolding: gate.isHolding, isTransitioning: transitioning)
    }

    public init(mediaDirectory: URL, configuration: RiftConfiguration = .init(),
                onPress: @escaping (UUID, TimeInterval) -> Void = { _, _ in },
                onSelectionBoundary: @escaping (RiftSelectionBoundary) -> Void = { _ in },
                onApproach: @escaping () -> Void = {},
                onPresentationBoundary: @escaping (RiftPresentationBoundary) -> Void = { _ in },
                holdsSelectionUntilFinished: Bool = false,
                interactionFence: QueueInteractionFence? = nil,
                onRemove: @escaping (UUID) -> Void = { _ in },
                onInteractionChange: @escaping (RiftInteractionSnapshot) -> Void = { _ in },
                onSelect: @escaping (UUID) -> Void) {
        // Configuration loaded from user data should be validated before construction.
        // Defensive fallback prevents malformed geometry from positioning windows off-screen.
        self.configuration = (try? configuration.validate()) != nil ? configuration : RiftConfiguration()
        self.onSelect = onSelect
        self.onPress = onPress
        self.onSelectionBoundary = onSelectionBoundary
        self.onApproach = onApproach
        self.onPresentationBoundary = onPresentationBoundary
        self.onRemove = onRemove
        self.onInteractionChange = onInteractionChange
        self.holdsSelectionUntilFinished = holdsSelectionUntilFinished
        self.interactionFence = interactionFence
        cache = ThumbnailCache(directory: mediaDirectory)
        decoration = RiftPanel(frame: .zero, decorative: true)
        let line = NSView(frame: .zero)
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.48).cgColor
        decoration.contentView = line
        observe(NSApplication.didChangeScreenParametersNotification, center: .default)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { [self] in self.reflow() }
        }
        observers.append((center, token))
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func duration(_ normal: Double) -> TimeInterval {
        reduceMotion ? min(normal, configuration.reducedMotionDuration) : normal
    }

    private var screen: NSScreen? {
        let screens = NSScreen.screens
        let ids = screens.compactMap {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        }
        let mainID = (NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let selected = RiftDisplaySelection.choose(preferred: configuration.preferredDisplayID,
                                                          main: mainID, available: ids) else { return screens.first }
        return screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == selected
        }
    }

    public var interactionSnapshot: RiftInteractionSnapshot { interaction.snapshot }

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
        mutateInteraction { $0.beginAnimation(token) }
        DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
            guard let self, !self.closed, self.generation == epoch else { return }
            self.mutateInteraction { $0.endAnimation(token) }
            self.flushDeferred()
        }
    }

    /// Called after durable prepare or a definite pre-input cancellation. It is
    /// intentionally separate from mouseUp so target capture cannot lose its row.
    public func finishSelection(_ assetID: UUID) {
        selectionVersions.removeValue(forKey: assetID)
        mutateInteraction { $0.finishSelection(assetID) }
        flushDeferred()
    }

    public func setFeedback(_ reason: String?, for assetID: UUID) {
        rowWindows[assetID]?.view.feedback = reason.map { String($0.prefix(256)) }
        rowWindows[assetID]?.view.updateDescription()
    }

    /// App persists this independent intent. No new image, wake, reflow or late
    /// animation may reverse it; only an explicit call with false shows the rift.
    public func setUserHidden(_ hidden: Bool) {
        guard !closed, hidden != userHidden else { return }
        userHidden = hidden
        resetWindows()
        if !hidden { apply(lastRecords, animateShift: false) }
    }

    private func present(_ panel: NSPanel) {
        guard !closed, !userHidden else { panel.orderOut(nil); return }
        panel.orderFrontRegardless()
    }

    private func flushDeferred() {
        guard !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting,
              let records = deferredRecords else { return }
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
        let includesArchive = containsNewArchive(records)
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
        guard !swallowed.isEmpty else { apply(records, animateShift: false); return }
        setTransitioning(true); deferredRecords = records
        let token = generation
        let swallowTime = duration(configuration.swallowDuration)
        // Scheduling is after existing hold/selection/transition deferral gates.
        for record in swallowed { recordPresentation(.swallowScheduled, record: record, duration: swallowTime) }
        for record in swallowed {
            guard let window = rowWindows[record.id] else { continue }
            // Commit the presentation transition before any pending press-return
            // timer can run; that timer must never undo the inward exit motion.
            window.view.record = record
            recordPresentation(.swallowActualStart, record: record, duration: swallowTime)
            window.view.animateImage(to: window.view.geometry.imageClipFrame.width + 2, duration: swallowTime)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = swallowTime
                window.panel.animator().alphaValue = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + swallowTime) { [weak self] in
            guard let self, !self.closed, !self.userHidden, self.generation == token else { return }
            for record in swallowed {
                if let window = self.rowWindows.removeValue(forKey: record.id) {
                    window.panel.close()
                    self.recordPresentation(.swallowClose, record: record, duration: swallowTime)
                }
            }
            self.setTransitioning(false)
            let next = self.deferredRecords ?? records
            self.deferredRecords = nil
            self.apply(next, animateShift: true)
        }
    }

    private func apply(_ records: [AssetRecord], animateShift: Bool) {
        guard !closed else { return }
        guard !userHidden else { lastRecords = records; return }
        guard let screen else {
            rowWindows.values.forEach { $0.panel.orderOut(nil) }
            decoration.orderOut(nil); lastRecords = records; return
        }
        let oldIDs = Set(lastRecords.filter { $0.visibility == .visible }.map(\.id))
        let hasNewCapture = !lastRecords.isEmpty && records.contains {
            $0.visibility == .visible && $0.visibilityReason == .capture && !oldIDs.contains($0.id)
        }
        var layout = RiftLayout.make(records: records, visibleFrame: screen.visibleFrame,
                                     configuration: configuration, firstVisibleIndex: firstVisibleIndex)
        if hasNewCapture && layout.totalCount > layout.capacity {
            firstVisibleIndex = max(0, layout.totalCount - layout.capacity)
            layout = RiftLayout.make(records: records, visibleFrame: screen.visibleFrame,
                                     configuration: configuration, firstVisibleIndex: firstVisibleIndex)
        }
        firstVisibleIndex = layout.firstVisibleIndex
        visibleRange = firstVisibleIndex..<(firstVisibleIndex + layout.rows.count)
        let visibleIDs = Set(layout.rows.map(\.assetID))
        for id in Array(rowWindows.keys) where !visibleIDs.contains(id) {
            rowWindows.removeValue(forKey: id)?.panel.close()
        }
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let shouldShift = animateShift && !layout.rows.isEmpty
        let shiftTime = shouldShift ? duration(configuration.shiftDuration) : 0
        let token = generation
        if shouldShift { setTransitioning(true) }
        for geometry in layout.rows {
            guard let record = byID[geometry.assetID] else { continue }
            let window: RowWindow
            let isNew: Bool
            if let existing = rowWindows[record.id] { window = existing; isNew = false }
            else {
                let panel = RiftPanel(frame: geometry.frame)
                let view = RiftRowView(record: record, geometry: geometry, configuration: configuration)
                panel.contentView = view
                window = RowWindow(panel: panel, view: view)
                rowWindows[record.id] = window
                wire(window, id: record.id)
                isNew = true
            }
            let oldStatus = window.view.record.status
            window.view.record = record
            window.view.configuration = configuration
            // Keep old label/row widths during the vertical move. Otherwise 10 → 9
            // would first jump the image sideways and clip the old two-digit label.
            if !shouldShift || isNew { window.view.updateGeometry(geometry) }
            if !shouldShift || isNew { window.view.ordinal = geometry.ordinal }
            window.view.updateDescription()
            if shouldShift && !isNew {
                let origin = CGPoint(x: geometry.frame.maxX - window.panel.frame.width,
                                     y: geometry.frame.midY - window.panel.frame.height / 2)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = shiftTime
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.panel.animator().setFrameOrigin(origin)
                }
            } else { window.panel.setFrame(geometry.frame, display: true) }
            present(window.panel)
            // The press response ends independently of upload completion. A
            // pre-start UNKNOWN is retained without a perpetual pressed pose.
            let expectedOffset: CGFloat = 0
            if isNew {
                window.panel.alphaValue = 0
                window.view.animateImage(to: expectedOffset, duration: 0)
                let arrivalTime = duration(configuration.arrivalDuration)
                trackAnimation(arrivalTime)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = arrivalTime
                    window.panel.animator().alphaValue = 1
                }
            } else if oldStatus != record.status || window.view.imageOffset != expectedOffset {
                window.view.animateImage(to: expectedOffset, duration: duration(
                    record.status == .failed ? configuration.returnDuration : configuration.pressDuration))
            }
            let pixels = Int(ceil(max(configuration.fitWidth, configuration.fitHeight) * screen.backingScaleFactor))
            cache.image(for: record.image, maxPixelSize: pixels) { [weak view = window.view] image in
                view?.setImage(image)
            }
        }
        decoration.setFrame(layout.lineFrame, display: true)
        decoration.contentView?.frame = CGRect(origin: .zero, size: layout.lineFrame.size)
        if !layout.rows.isEmpty && !layout.lineFrame.isEmpty { present(decoration) }
        else { decoration.orderOut(nil) }
        lastRecords = records
        refreshHoverFromPointer()
        if shouldShift {
            DispatchQueue.main.asyncAfter(deadline: .now() + shiftTime) { [weak self] in
                guard let self, !self.closed, self.generation == token else { return }
                for geometry in layout.rows {
                    let row = self.rowWindows[geometry.assetID]
                    row?.panel.setFrame(geometry.frame, display: true)
                    let view = row?.view
                    view?.updateGeometry(geometry)
                    view?.ordinal = geometry.ordinal; view?.updateDescription(); view?.needsDisplay = true
                }
                self.setTransitioning(false)
                self.refreshHoverFromPointer()
                self.flushDeferred()
            }
        }
    }

    private func refreshHoverFromPointer() {
        // Event/geometry driven only: also catches a newly shown row underneath a
        // stationary pointer. This is not a global mouse polling timer.
        let point = NSEvent.mouseLocation
        hoveredIDs = userHidden ? [] : Set(rowWindows.compactMap { id, row in
            row.panel.isVisible && row.panel.frame.contains(point) ? id : nil
        })
        mutateInteraction { $0.setHovered(hoveredIDs) }
    }

    private func returnPress(_ id: UUID) {
        guard let row = rowWindows[id], !userHidden, row.view.record.visibility == .visible else { return }
        let time = duration(configuration.returnDuration)
        trackAnimation(time)
        row.view.animateImage(to: 0, duration: time)
    }

    private func wire(_ window: RowWindow, id: UUID) {
        window.view.onHover = { [weak self] inside in
            guard let self, !self.userHidden, !self.closed else { return }
            if inside { self.hoveredIDs.insert(id) } else { self.hoveredIDs.remove(id) }
            self.mutateInteraction { $0.setHovered(self.hoveredIDs) }
            self.flushDeferred()
        }
        window.view.onApproach = { [weak self] in
            guard let self, !self.gate.isHolding, !self.transitioning, !self.userHidden else { return }
            self.onApproach()
        }
        window.view.onMenuVisibility = { [weak self] open in
            guard let self, !self.closed else { return }
            self.mutateInteraction { $0.setMenu(id, open: open) }
            if !open { self.flushDeferred() }
        }
        window.view.onRemove = { [weak self] in
            guard let self, !self.gate.isHolding, !self.transitioning,
                  !self.userHidden, self.selectionVersions[id] == nil else { return }
            self.onRemove(id)
        }
        window.view.onDown = { [weak self, weak view = window.view] event in
            guard let self, let view else { return false }
            let point = view.window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
            let accepts = !self.userHidden && !self.transitioning && self.selectionVersions[id] == nil
                && view.record.visibility == .visible && view.record.status != .transferring
                && view.record.status != .used
            let accepted = self.gate.begin(assetID: id, screenPoint: point, timestamp: event.timestamp,
                                          clickCount: event.clickCount, doubleClickInterval: NSEvent.doubleClickInterval,
                                          acceptsSelection: accepts)
            if accepted {
                self.selectionVersions[id] = view.record.visibilityRevision
                self.mutateInteraction { $0.beginSelection(id, held: true) }
                view.feedback = nil; view.updateDescription()
                self.onPress(id, event.timestamp)
                self.onSelectionBoundary(RiftSelectionBoundary(assetID: id, source: .mouse,
                    eventUptime: event.timestamp, eventNumber: event.eventNumber,
                    windowNumber: event.windowNumber, clickCount: event.clickCount))
                let time = self.duration(self.configuration.pressDuration)
                self.trackAnimation(time)
                view.animateImage(to: self.configuration.inwardDistance, duration: time)
            }
            return accepted
        }
        window.view.onUp = { [weak self] inside in
            guard let self else { return }
            let held = self.interaction.heldID
            let selected = self.gate.end(inside: inside)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + self.duration(self.configuration.pressDuration)) { [weak self] in
                    guard let self, !self.closed, self.generation == epoch else { return }
                    self.returnPress(selected)
                }
            }
            self.flushDeferred()
        }
        window.view.onScroll = { [weak self] delta in self?.scroll(delta) }
        window.view.onAccessiblePress = { [weak self, weak view = window.view] in
            guard let self, let view, !self.userHidden, !self.transitioning, !self.gate.isHolding,
                  self.selectionVersions[id] == nil, view.record.visibility == .visible,
                  [.pending, .failed, .unknown, .missing].contains(view.record.status) else { return false }
            let invocationUptime = ProcessInfo.processInfo.systemUptime
            self.selectionVersions[id] = view.record.visibilityRevision
            self.mutateInteraction { $0.beginSelection(id, held: false) }
            view.feedback = nil; view.updateDescription()
            self.onPress(id, invocationUptime)
            self.onSelectionBoundary(RiftSelectionBoundary(assetID: id, source: .accessibility,
                eventUptime: invocationUptime))
            let time = self.duration(self.configuration.pressDuration)
            self.trackAnimation(time)
            view.animateImage(to: self.configuration.inwardDistance, duration: time)
            self.onSelect(id)
            if !self.holdsSelectionUntilFinished { self.finishSelection(id) }
            let epoch = self.generation
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                guard let self, !self.closed, self.generation == epoch else { return }
                self.returnPress(id)
            }
            return true
        }
    }

    private func scroll(_ delta: CGFloat) {
        guard !userHidden, !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting else { return }
        scrollAccumulator += delta
        guard abs(scrollAccumulator) >= 8 else { return }
        firstVisibleIndex = max(0, firstVisibleIndex + (scrollAccumulator < 0 ? 1 : -1))
        scrollAccumulator = 0
        apply(lastRecords, animateShift: false)
    }

    public func showLatest() {
        guard !userHidden, !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting else { return }
        firstVisibleIndex = lastRecords.filter { $0.visibility == .visible }.count
        apply(lastRecords, animateShift: false)
    }

    /// Explicit history restoration may reveal one existing item without
    /// changing its sort order or reversing the independent user-hidden intent.
    public func showAsset(_ assetID: UUID) {
        guard !userHidden, !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting,
              let index = lastRecords.filter({ $0.visibility == .visible }).firstIndex(where: { $0.id == assetID }) else { return }
        guard !visibleRange.contains(index) else { return }
        firstVisibleIndex = index
        apply(lastRecords, animateShift: false)
    }

    public func showOldest() {
        guard !userHidden, !gate.isHolding, !transitioning, !interaction.snapshot.isSelecting else { return }
        firstVisibleIndex = 0; apply(lastRecords, animateShift: false)
    }

    public func updateConfiguration(_ configuration: RiftConfiguration) throws {
        try configuration.validate()
        self.configuration = configuration
        reflow()
    }

    private func containsNewArchive(_ records: [AssetRecord]) -> Bool {
        let previousVisible = Set(lastRecords.filter { $0.visibility == .visible }.map(\.id))
        return records.contains { $0.visibility == .archived && previousVisible.contains($0.id) }
    }

    private func resetWindows() {
        generation &+= 1; transitioning = false
        let held = interaction.heldID
        gate.cancel()
        if let held { selectionVersions.removeValue(forKey: held) }
        lastRecords = deferredRecords ?? lastRecords
        deferredRecords = nil
        hoveredIDs.removeAll()
        mutateInteraction { $0.resetPresentation() }
        rowWindows.values.forEach { $0.panel.close() }
        rowWindows.removeAll()
        visibleRange = 0..<0
        decoration.orderOut(nil)
    }

    private func reflow() {
        guard !closed else { return }
        let pending = deferredRecords
        let displayed = lastRecords
        let protectedArchive = pending.map { containsNewArchive($0) && interaction.snapshot.blocksAutomaticArchive } ?? false
        resetWindows()
        if protectedArchive && !userHidden { lastRecords = displayed }
        if !userHidden { apply(lastRecords, animateShift: false) }
        // A wake/display event must not bypass an archive already deferred for
        // a pointer or an accepted selection. Recheck after new geometry exists.
        if protectedArchive, let pending { render(pending) }
    }

    public func close() {
        guard !closed else { return }
        closed = true; generation &+= 1; gate.cancel()
        selectionVersions.removeAll(); hoveredIDs.removeAll()
        mutateInteraction { $0.close() }
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        rowWindows.values.forEach { $0.panel.close() }; rowWindows.removeAll()
        decoration.close(); cache.clear()
    }

    deinit { observers.forEach { $0.0.removeObserver($0.1) } }
}
