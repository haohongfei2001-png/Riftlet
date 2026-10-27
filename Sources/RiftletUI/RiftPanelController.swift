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

private final class RiftRowView: NSView {
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
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        toolTip = "Screenshot \(ordinal) · \(suffix). Scroll for earlier or later captures."
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

    override func mouseDown(with event: NSEvent) { _ = onDown?(event) }
    override func mouseUp(with event: NSEvent) {
        onUp?(bounds.contains(convert(event.locationInWindow, from: nil)))
    }
    override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY) }
    override func accessibilityPerformPress() -> Bool { onAccessiblePress?() ?? false }
}

private struct RowWindow {
    let panel: RiftPanel
    let view: RiftRowView
}

/// The UI consumes committed state only. It has no adapter, receipt policy or file-deletion API.
/// Per-row input windows leave genuine window-free gaps; the entire line is click-through.
/// Actual transparent-pixel hit behavior, first-click focus and Spaces require Mac GUI validation.
@MainActor
public final class RiftPanelController {
    public private(set) var configuration: RiftConfiguration
    public private(set) var visibleRange: Range<Int> = 0..<0
    private let cache: ThumbnailCache
    private let onSelect: (UUID) -> Void
    private let onPress: (UUID, TimeInterval) -> Void
    private let onSelectionBoundary: (RiftSelectionBoundary) -> Void
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
        let rows = rowWindows.map { id, row in
            RiftDiagnosticRow(assetID: id, ordinal: row.view.ordinal,
                windowNumber: row.panel.windowNumber, frame: row.panel.frame,
                imageClipFrame: row.panel.convertToScreen(row.view.convert(row.view.geometry.imageClipFrame, to: nil)),
                numberFrame: row.panel.convertToScreen(row.view.convert(row.view.geometry.numberFrame, to: nil)))
        }.sorted { $0.ordinal < $1.ordinal }
        return RiftDiagnosticSnapshot(rows: rows, lineFrame: decoration.frame,
                                      isHolding: gate.isHolding, isTransitioning: transitioning)
    }

    public init(mediaDirectory: URL, configuration: RiftConfiguration = .init(),
                onPress: @escaping (UUID, TimeInterval) -> Void = { _, _ in },
                onSelectionBoundary: @escaping (RiftSelectionBoundary) -> Void = { _ in },
                onSelect: @escaping (UUID) -> Void) {
        // Configuration loaded from user data should be validated before construction.
        // Defensive fallback prevents malformed geometry from positioning windows off-screen.
        self.configuration = (try? configuration.validate()) != nil ? configuration : RiftConfiguration()
        self.onSelect = onSelect
        self.onPress = onPress
        self.onSelectionBoundary = onSelectionBoundary
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

    /// Pass the latest records including newly used records. Historical used records are not replayed.
    public func render(_ records: [AssetRecord]) {
        guard !closed else { return }
        if gate.isHolding || transitioning { deferredRecords = records; return }
        let newlyUsed = records.filter { $0.status == .used && rowWindows[$0.id] != nil }
        if !newlyUsed.isEmpty {
            transitioning = true; deferredRecords = records
            let token = generation
            let swallowTime = duration(configuration.swallowDuration)
            for record in newlyUsed {
                guard let window = rowWindows[record.id] else { continue }
                window.view.animateImage(to: window.view.geometry.imageClipFrame.width + 2, duration: swallowTime)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = swallowTime
                    window.panel.animator().alphaValue = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + swallowTime) { [weak self] in
                guard let self, !self.closed, self.generation == token else { return }
                for record in newlyUsed { self.rowWindows.removeValue(forKey: record.id)?.panel.close() }
                self.transitioning = false
                let next = self.deferredRecords ?? records
                self.deferredRecords = nil
                self.apply(next, animateShift: true)
            }
            return
        }
        apply(records, animateShift: false)
    }

    private func apply(_ records: [AssetRecord], animateShift: Bool) {
        guard let screen, !closed else { lastRecords = records; return }
        let oldIDs = Set(lastRecords.filter { $0.status != .used }.map(\.id))
        let activeIDs = Set(records.filter { $0.status != .used }.map(\.id))
        let hasNewCapture = !activeIDs.subtracting(oldIDs).isEmpty && !lastRecords.isEmpty
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
        let shiftTime = animateShift ? duration(configuration.shiftDuration) : 0
        let token = generation
        if animateShift { transitioning = true }
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
            if !animateShift || isNew { window.view.updateGeometry(geometry) }
            if !animateShift || isNew { window.view.ordinal = geometry.ordinal }
            window.view.updateDescription()
            if animateShift && !isNew {
                let origin = CGPoint(x: geometry.frame.maxX - window.panel.frame.width,
                                     y: geometry.frame.midY - window.panel.frame.height / 2)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = shiftTime
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.panel.animator().setFrameOrigin(origin)
                }
            } else { window.panel.setFrame(geometry.frame, display: true) }
            window.panel.orderFrontRegardless()
            let expectedOffset: CGFloat = (record.status == .transferring || record.status == .unknown)
                ? configuration.inwardDistance : 0
            if isNew {
                window.panel.alphaValue = 0
                window.view.animateImage(to: expectedOffset, duration: 0)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration(configuration.arrivalDuration)
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
        decoration.orderFrontRegardless()
        lastRecords = records
        if animateShift {
            DispatchQueue.main.asyncAfter(deadline: .now() + shiftTime) { [weak self] in
                guard let self, !self.closed, self.generation == token else { return }
                for geometry in layout.rows {
                    let row = self.rowWindows[geometry.assetID]
                    row?.panel.setFrame(geometry.frame, display: true)
                    let view = row?.view
                    view?.updateGeometry(geometry)
                    view?.ordinal = geometry.ordinal; view?.updateDescription(); view?.needsDisplay = true
                }
                self.transitioning = false
                if let next = self.deferredRecords { self.deferredRecords = nil; self.render(next) }
            }
        }
    }

    private func wire(_ window: RowWindow, id: UUID) {
        window.view.onDown = { [weak self, weak view = window.view] event in
            guard let self, let view else { return false }
            let point = view.window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
            let accepts = !self.transitioning && view.record.status != .transferring
                && view.record.status != .used && view.record.status != .missing
            let accepted = self.gate.begin(assetID: id, screenPoint: point, timestamp: event.timestamp,
                                          clickCount: event.clickCount, doubleClickInterval: NSEvent.doubleClickInterval,
                                          acceptsSelection: accepts)
            if accepted {
                self.onPress(id, event.timestamp)
                self.onSelectionBoundary(RiftSelectionBoundary(assetID: id, source: .mouse,
                    eventUptime: event.timestamp, eventNumber: event.eventNumber,
                    windowNumber: event.windowNumber, clickCount: event.clickCount))
                view.animateImage(to: self.configuration.inwardDistance,
                                             duration: self.duration(self.configuration.pressDuration)) }
            return accepted
        }
        window.view.onUp = { [weak self, weak view = window.view] inside in
            guard let self else { return }
            let selected = self.gate.end(inside: inside)
            if selected == nil, let view {
                let retained: CGFloat = view.record.status == .unknown ? self.configuration.inwardDistance : 0
                view.animateImage(to: retained, duration: self.duration(self.configuration.returnDuration))
            }
            if let next = self.deferredRecords { self.deferredRecords = nil; self.render(next) }
            if let selected {
                self.onSelect(selected)
                // A disabled adapter may leave the persistent state pending. End the press
                // response in that case; this timer never changes a transfer/queue state.
                DispatchQueue.main.asyncAfter(deadline: .now() + self.duration(self.configuration.pressDuration) + 0.05) { [weak self] in
                    guard let self, let row = self.rowWindows[selected],
                          row.view.record.status == .pending || row.view.record.status == .failed else { return }
                    row.view.animateImage(to: 0, duration: self.duration(self.configuration.returnDuration))
                }
            }
        }
        window.view.onScroll = { [weak self] delta in self?.scroll(delta) }
        window.view.onAccessiblePress = { [weak self, weak view = window.view] in
            guard let self, let view, !self.transitioning, !self.gate.isHolding,
                  [.pending, .failed, .unknown].contains(view.record.status) else { return false }
            // AX has an invocation boundary, not a physical mouse event timestamp.
            let invocationUptime = ProcessInfo.processInfo.systemUptime
            self.onPress(id, invocationUptime)
            self.onSelectionBoundary(RiftSelectionBoundary(assetID: id, source: .accessibility,
                eventUptime: invocationUptime))
            self.onSelect(id); return true
        }
    }

    private func scroll(_ delta: CGFloat) {
        guard !gate.isHolding, !transitioning else { return }
        scrollAccumulator += delta
        guard abs(scrollAccumulator) >= 8 else { return }
        firstVisibleIndex = max(0, firstVisibleIndex + (scrollAccumulator < 0 ? 1 : -1))
        scrollAccumulator = 0
        apply(lastRecords, animateShift: false)
    }

    public func showLatest() {
        guard !gate.isHolding, !transitioning else { return }
        firstVisibleIndex = lastRecords.filter { $0.status != .used }.count
        apply(lastRecords, animateShift: false)
    }

    public func showOldest() {
        guard !gate.isHolding, !transitioning else { return }
        firstVisibleIndex = 0; apply(lastRecords, animateShift: false)
    }

    public func updateConfiguration(_ configuration: RiftConfiguration) throws {
        try configuration.validate()
        self.configuration = configuration
        reflow()
    }

    private func reflow() {
        guard !closed else { return }
        generation &+= 1; transitioning = false; gate.cancel()
        let records = deferredRecords ?? lastRecords
        deferredRecords = nil
        rowWindows.values.forEach { $0.panel.close() }
        rowWindows.removeAll()
        apply(records, animateShift: false)
    }

    public func close() {
        guard !closed else { return }
        closed = true; generation &+= 1; gate.cancel()
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        rowWindows.values.forEach { $0.panel.close() }; rowWindows.removeAll()
        decoration.close(); cache.clear()
    }

    deinit { observers.forEach { $0.0.removeObserver($0.1) } }
}
