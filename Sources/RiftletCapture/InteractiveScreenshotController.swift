import AppKit
import CoreGraphics
import QuartzCore

/// Explicit-user-action screenshot selection. There is no startup permission
/// request, system interactive modal, global keyboard listener or upload path.
/// Public API basis:
/// https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
/// https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded
/// https://developer.apple.com/documentation/coregraphics/kcgwindowbounds
@MainActor
public final class InteractiveScreenshotController {
    public static var selectionWindowLevel: NSWindow.Level { .statusBar }
    public static var controlsWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: selectionWindowLevel.rawValue + 1)
    }

    public var onCapture: ((InteractiveScreenshotCapture) -> Void)?
    public var onCancel: (() -> Void)?
    public var onError: ((InteractiveScreenshotError) -> Void)?
    public var onStateChange: ((InteractiveScreenshotState) -> Void)?
    /// true: temporarily hide host-owned Riftlet windows; false: restore the same
    /// expanded state. Selection panels are already transparent before true and
    /// must be excluded from host orderOut so their local Escape receiver survives.
    public var onCaptureVisibilityChanged: ((_ isHidden: Bool) -> Void)?

    public var isActive: Bool { session.isActive }
    public private(set) var isEnabled: Bool
    public var isCapturing: Bool { session.pending != nil }
    public var currentMode: ScreenshotMode { session.mode }
    public var presentationSnapshot: InteractiveScreenshotPresentation? {
        guard session.isActive, let request = session.pending, session.owns(request) else { return nil }
        return InteractiveScreenshotPresentation(sessionID: request.sessionID, requestID: request.id,
            confirmedMode: request.mode, nextMode: session.mode, state: state)
    }
    public var selectionWindowIDs: Set<Int> { Set(panels.map(\.windowNumber)) }
    public private(set) var state: InteractiveScreenshotState = .idle

    private let outputDirectory: URL
    private let permission: any InteractiveScreenshotPermissionChecking
    private let capturer: any InteractiveScreenshotCapturing
    private let displays: @MainActor () -> [InteractiveScreenshotDisplay]
    private let windows: @MainActor () -> [InteractiveScreenshotWindow]
    private let presentsPanels: Bool
    private var session = InteractiveScreenshotSession()
    private var panels: [InteractiveScreenshotSelectionPanel] = []
    private var captureTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var startAttemptID = UUID()
    private var interactionSuspended = false
    private var hostUIHidden = false
    private var selectionHidden = false
    private var highlightedRect: CGRect?
    private var cachedWindows: [InteractiveScreenshotWindow] = []
    private var lastWindowRefresh: TimeInterval = -.infinity
    private var previousFrontmost: NSRunningApplication?

    private struct Gesture {
        let revision: UInt64
        let mode: ScreenshotMode
        let start: CGPoint
        let display: InteractiveScreenshotDisplay
        let window: InteractiveScreenshotWindow?
        let topology: [InteractiveScreenshotDisplay]
    }
    private var gesture: Gesture?

    public convenience init(outputDirectory: URL, isEnabled: Bool = true) {
        self.init(outputDirectory: outputDirectory, permission: InteractiveScreenshotPermission(),
                  capturer: InteractiveScreenshotSystemCapture(), displays: Self.currentDisplays,
                  windows: Self.currentWindows, presentsPanels: true, isEnabled: isEnabled)
    }

    init(outputDirectory: URL, permission: any InteractiveScreenshotPermissionChecking,
         capturer: any InteractiveScreenshotCapturing,
         displays: @escaping @MainActor () -> [InteractiveScreenshotDisplay],
         windows: @escaping @MainActor () -> [InteractiveScreenshotWindow], presentsPanels: Bool,
         isEnabled: Bool = true) {
        self.outputDirectory = outputDirectory
        self.permission = permission; self.capturer = capturer
        self.displays = displays; self.windows = windows; self.presentsPanels = presentsPanels
        self.isEnabled = isEnabled
    }

    /// Disabling is independent of system screenshot collection. It invalidates
    /// even a permission request whose synchronous OS call runs a nested event
    /// loop, so its late return cannot recreate an already disabled session.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { cancel() }
    }

    /// Called by the host only after the user clicks its capture entry.
    public func start(mode: ScreenshotMode, options: InteractiveScreenshotOptions = .init()) {
        guard isEnabled else { return }
        if session.isActive { updateOptions(options); updateMode(mode); return }
        let attempt = UUID(); startAttemptID = attempt
        let originalFrontmost = NSWorkspace.shared.frontmostApplication
        var granted = permission.hasAccess()
        guard isEnabled, startAttemptID == attempt else { return }
        if !granted { granted = permission.requestAccess() }
        guard isEnabled, startAttemptID == attempt else { return }
        guard granted else {
            onError?(.screenRecordingPermissionRequired); return
        }
        guard !displays().isEmpty else { onError?(.noDisplay); return }
        // Capture this before a possible system permission prompt changes focus.
        previousFrontmost = originalFrontmost
        if previousFrontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier { previousFrontmost = nil }
        session.start(mode: mode, options: options)
        let sessionID = session.id
        interactionSuspended = false; selectionHidden = false; gesture = nil; highlightedRect = nil
        refreshWindowCache(force: true)
        setState(.selecting(mode))
        guard isEnabled, session.isActive, session.id == sessionID else { return }
        if presentsPanels { rebuildPanels() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.session.id == sessionID else { return }
                self.environmentChanged(reportDisplayChange: true)
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.session.id == sessionID else { return }
                    self.environmentChanged()
                }
            })
        }
    }

    /// No pending selection/countdown is resumed automatically on another Space
    /// or after sleep. A fresh explicit gesture establishes a new target.
    func environmentChanged(reportDisplayChange: Bool = false) {
        let hadPendingCapture = isCapturing
        cancel()
        if reportDisplayChange && hadPendingCapture { onError?(.displayConfigurationChanged) }
    }

    public func updateMode(_ mode: ScreenshotMode) {
        session.updateMode(mode)
        guard isEnabled, session.isActive else { return }
        gesture = nil; setHighlight(nil); refreshWindowCache(force: true)
        if session.isActive && !isCapturing { setState(.selecting(mode)) }
        for panel in panels { panel.selectionView.mode = mode; panel.invalidateCursorRects(for: panel.selectionView) }
    }

    public func updateOptions(_ options: InteractiveScreenshotOptions) { session.updateOptions(options) }

    /// Menus and host editors own their keyboard/closing click while suspended.
    /// A resumed selection requires a new complete down/up; no event is replayed.
    public func setInteractionSuspended(_ suspended: Bool) {
        interactionSuspended = suspended; gesture = nil; setHighlight(nil)
        if suspended { panels.forEach { $0.orderOut(nil) } }
        // A pending countdown/exposure still needs its local Escape receiver.
        // Pointer handlers independently refuse a second capture while busy.
        else if session.isActive { presentPanels() }
    }

    public func cancel() {
        startAttemptID = UUID()
        guard session.isActive else { return }
        session.cancel(); gesture = nil; captureTask?.cancel(); captureTask = nil; capturer.cancel()
        panels.forEach { $0.orderOut(nil); $0.close() }; panels.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspace.removeObserver($0) }
        workspaceObservers.removeAll()
        screenObserver = nil; highlightedRect = nil; selectionHidden = false
        cachedWindows.removeAll(); lastWindowRefresh = -.infinity
        restoreHostUI()
        setState(.idle)
        // Nonactivating panels normally release keyboard focus themselves. Only
        // restore the prior app if a host editor activated Riftlet; never override
        // a different application the user deliberately switched to meanwhile.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let previousFrontmost, !previousFrontmost.isTerminated {
            previousFrontmost.activate(options: [.activateIgnoringOtherApps])
        }
        previousFrontmost = nil
        onCancel?()
    }

    private func setState(_ value: InteractiveScreenshotState) {
        guard state != value else { return }
        state = value; onStateChange?(value)
    }

    private func rebuildPanels() {
        panels.forEach { $0.orderOut(nil); $0.close() }; panels.removeAll()
        guard session.isActive else { return }
        let sessionID = session.id
        for display in displays() {
            let panel = InteractiveScreenshotSelectionPanel(frame: display.frame)
            panel.selectionView.mode = session.mode
            panel.selectionView.onMove = { [weak self] point in
                guard let self, self.session.id == sessionID else { return }; self.pointerMoved(point)
            }
            panel.selectionView.onDown = { [weak self] point in
                guard let self, self.session.id == sessionID else { return }; self.pointerDown(at: point)
            }
            panel.selectionView.onDrag = { [weak self] point in
                guard let self, self.session.id == sessionID else { return }; self.pointerDragged(to: point)
            }
            panel.selectionView.onUp = { [weak self] point in
                guard let self, self.session.id == sessionID else { return }; self.pointerUp(at: point)
            }
            panel.selectionView.onCancel = { [weak self] in
                guard let self, self.session.id == sessionID, !self.interactionSuspended else { return }; self.cancel()
            }
            panels.append(panel)
        }
        if !interactionSuspended { presentPanels() }
    }

    private func presentPanels() {
        guard presentsPanels, session.isActive, !interactionSuspended else { return }
        for panel in panels {
            panel.alphaValue = selectionHidden ? 0 : 1
            panel.selectionView.mode = session.mode
            panel.orderFrontRegardless()
            panel.invalidateCursorRects(for: panel.selectionView)
        }
        let receiver = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels.first
        receiver?.makeKey()
        if let receiver { receiver.makeFirstResponder(receiver.selectionView) }
    }

    private func setHighlight(_ rect: CGRect?) {
        guard rect != highlightedRect else { return }
        highlightedRect = rect
        for panel in panels {
            panel.selectionView.targetRect = rect.map { $0.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY) }
            panel.selectionView.needsDisplay = true
        }
    }

    private func refreshWindowCache(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastWindowRefresh > 0.08 else { return }
        cachedWindows = windows(); lastWindowRefresh = now
    }

    private func window(at point: CGPoint, force: Bool = false) -> InteractiveScreenshotWindow? {
        refreshWindowCache(force: force)
        return cachedWindows.first { $0.rect.contains(point) }
    }

    func pointerMoved(_ point: CGPoint) {
        guard session.isActive, !interactionSuspended, !isCapturing else { return }
        switch session.mode {
        case .window: setHighlight(window(at: point)?.rect)
        case .fullScreen: setHighlight(displays().first(where: { $0.frame.contains(point) })?.frame)
        case .region: if gesture == nil { setHighlight(nil) }
        }
    }

    func pointerDown(at point: CGPoint) {
        let currentDisplays = displays()
        guard session.isActive, !interactionSuspended, !isCapturing,
              let display = currentDisplays.first(where: { $0.frame.contains(point) }) else { return }
        let targetWindow = session.mode == .window ? window(at: point, force: true) : nil
        guard session.mode != .window || targetWindow != nil else { return }
        gesture = Gesture(revision: session.selectionRevision, mode: session.mode, start: point,
                          display: display, window: targetWindow, topology: currentDisplays)
        if session.mode == .region { setHighlight(nil) }
        else { setHighlight(targetWindow?.rect ?? display.frame) }
    }

    func pointerDragged(to point: CGPoint) {
        guard let gesture, gesture.revision == session.selectionRevision,
              gesture.mode == .region, !interactionSuspended, !isCapturing else { return }
        let currentDisplays = displays()
        guard InteractiveScreenshotGeometry.sameTopology(gesture.topology, currentDisplays) else {
            self.gesture = nil; setHighlight(nil); return
        }
        setHighlight(InteractiveScreenshotGeometry.dragRect(from: gesture.start, to: point, displays: currentDisplays))
    }

    func pointerUp(at point: CGPoint) {
        guard let selected = gesture else { return }
        gesture = nil
        guard session.isActive, !interactionSuspended, !isCapturing,
              selected.revision == session.selectionRevision, selected.mode == session.mode else { return }
        let currentDisplays = displays()
        guard InteractiveScreenshotGeometry.sameTopology(selected.topology, currentDisplays) else {
            setHighlight(nil); onError?(.displayConfigurationChanged); return
        }
        let rect: CGRect
        switch selected.mode {
        case .region:
            guard let region = InteractiveScreenshotGeometry.dragRect(from: selected.start, to: point, displays: currentDisplays) else { setHighlight(nil); return }
            rect = region
        case .window:
            guard hypot(point.x - selected.start.x, point.y - selected.start.y) <= 8,
                  let original = selected.window, let current = window(at: point, force: true),
                  current == original else { setHighlight(nil); return }
            rect = original.rect
        case .fullScreen:
            guard hypot(point.x - selected.start.x, point.y - selected.start.y) <= 8,
                  selected.display.frame.contains(point) else { return }
            rect = selected.display.frame
        }
        let involved = [selected.display] + currentDisplays.filter { $0.id != selected.display.id && $0.frame.intersects(rect) }
        guard let reference = involved.first else { onError?(.noDisplay); return }
        let top = reference.frame.maxY + reference.quartzFrame.minY
        let quartz = selected.mode == .fullScreen ? selected.display.quartzFrame
            : InteractiveScreenshotGeometry.quartzRect(fromAppKit: rect, primaryScreenTop: top)
        submitSelection(InteractiveScreenshotTarget(rect: rect, quartzRect: quartz, displays: involved,
            window: selected.window, topology: currentDisplays))
    }

    /// Internal deterministic seam; normal callers arrive from a complete native gesture.
    func submitSelection(_ target: InteractiveScreenshotTarget) {
        guard isEnabled, !interactionSuspended, let request = session.beginCapture(target: target) else { return }
        setHighlight(nil)
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let deadline = ProcessInfo.processInfo.systemUptime + request.options.delay
                while true {
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0 else { break }
                    try Task.checkCancellation()
                    guard self.session.owns(request) else { return }
                    self.setState(.countdown(Int(ceil(remaining))))
                    try await Task.sleep(nanoseconds: UInt64(min(1, remaining) * 1_000_000_000))
                }
                try Task.checkCancellation()
                guard self.session.owns(request) else { return }
                guard self.permission.hasAccess() else { throw InteractiveScreenshotError.screenRecordingPermissionRequired }
                try self.validateTarget(request.target)
                self.setState(.capturing(request.mode))
                try Task.checkCancellation()
                guard self.isEnabled, self.session.owns(request) else { return }
                let hiddenIDs = self.hideForCapture(request)
                try await self.waitForHiddenWindows(hiddenIDs)
                try Task.checkCancellation()
                guard self.session.owns(request) else { return }
                try self.validateTarget(request.target)
                let file = try await self.capturer.capture(request, outputDirectory: self.outputDirectory)
                try Task.checkCancellation()
                guard self.session.owns(request) else { return }
                try self.validateTarget(request.target)
                guard self.session.complete(request) else { return }
                self.captureTask = nil
                self.restoreAfterCapture()
                guard self.isEnabled, self.session.isActive, self.session.id == request.sessionID else { return }
                self.setState(.selecting(self.session.mode))
                guard self.isEnabled, self.session.isActive, self.session.id == request.sessionID else { return }
                let result = InteractiveScreenshotCapture(sourceURL: file.sourceURL, pngData: file.data,
                    mode: request.mode, rect: request.target.rect, displayID: request.target.displays[0].id,
                    displayIDs: request.target.displays.map(\.id), windowID: request.target.window?.id,
                    pixelWidth: file.pixelWidth, pixelHeight: file.pixelHeight, options: request.options,
                    hasSystemScreenshotMetadata: file.hasSystemScreenshotMetadata)
                self.onCapture?(result)
                if self.session.isActive && !self.interactionSuspended { self.presentPanels() }
            } catch {
                guard self.session.complete(request) else { return }
                self.captureTask = nil; self.restoreAfterCapture()
                guard self.isEnabled, self.session.isActive, self.session.id == request.sessionID else { return }
                self.setState(.selecting(self.session.mode))
                guard self.isEnabled, self.session.isActive, self.session.id == request.sessionID else { return }
                if !(error is CancellationError) { self.onError?(error as? InteractiveScreenshotError ?? .invalidOutput) }
                if self.session.isActive && !self.interactionSuspended { self.presentPanels() }
            }
        }
    }

    private func validateTarget(_ target: InteractiveScreenshotTarget) throws {
        let currentDisplays = displays()
        guard InteractiveScreenshotGeometry.sameTopology(target.topology, currentDisplays) else {
            throw InteractiveScreenshotError.displayConfigurationChanged
        }
        guard target.displays.allSatisfy({ currentDisplays.contains($0) }) else {
            throw InteractiveScreenshotError.displayConfigurationChanged
        }
        if let selected = target.window {
            guard windows().contains(selected) else {
                throw InteractiveScreenshotError.selectedWindowUnavailable
            }
        }
    }

    private func hideForCapture(_ request: InteractiveScreenshotRequest) -> Set<UInt32> {
        guard presentsPanels else { return [] }
        let ownIDs = Set(panels.compactMap { UInt32(exactly: $0.windowNumber) })
        var expectedHidden = ownIDs
        if request.mode != .window {
            for window in NSApp.windows where window.isVisible && window.alphaValue > 0 && window.frame.intersects(request.target.rect) {
                if let id = UInt32(exactly: window.windowNumber) { expectedHidden.insert(id) }
            }
        }
        // Keep the key receiver ordered, but fully transparent, during the short
        // noninteractive system capture. Escape still works without global keys.
        selectionHidden = true
        panels.forEach { $0.alphaValue = 0 }
        NSCursor.arrow.set()
        if request.mode != .window { hostUIHidden = true; onCaptureVisibilityChanged?(true) }
        CATransaction.flush()
        return expectedHidden
    }

    private func waitForHiddenWindows(_ ids: Set<UInt32>) async throws {
        guard !ids.isEmpty else { return }
        // This observes WindowServer withdrawal/alpha, rather than claiming that
        // an arbitrary delay alone guarantees compositor exclusion.
        for _ in 0..<20 {
            try Task.checkCancellation()
            guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
                throw InteractiveScreenshotError.captureOverlayStillVisible
            }
            let stillVisible = info.contains { value in
                guard let id = (value[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                      ids.contains(id) else { return false }
                return ((value[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.0001
            }
            if !stillVisible { return }
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        throw InteractiveScreenshotError.captureOverlayStillVisible
    }

    private func restoreHostUI() {
        guard hostUIHidden else { return }
        hostUIHidden = false; onCaptureVisibilityChanged?(false)
    }

    private func restoreAfterCapture() {
        selectionHidden = false
        if session.isActive && !interactionSuspended { panels.forEach { $0.alphaValue = 1 } }
        restoreHostUI()
    }

    private static func currentDisplays() -> [InteractiveScreenshotDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return InteractiveScreenshotDisplay(id: number.uint32Value, frame: screen.frame,
                quartzFrame: CGDisplayBounds(number.uint32Value), scale: screen.backingScaleFactor)
        }
    }

    private static func currentWindows() -> [InteractiveScreenshotWindow] {
        let screens = currentDisplays()
        guard let screen = screens.first,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let top = screen.frame.maxY + screen.quartzFrame.minY
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { value in
            guard let id = (value[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (value[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  let layer = (value[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer >= 0, layer <= NSWindow.Level.floating.rawValue,
                  ((value[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.001,
                  let dictionary = value[kCGWindowBounds as String] as? [String: Any] else { return nil }
            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(dictionary as CFDictionary, &bounds),
                  InteractiveScreenshotGeometry.isUsable(bounds) else { return nil }
            return InteractiveScreenshotWindow(id: id, ownerPID: pid,
                rect: InteractiveScreenshotGeometry.appKitRect(fromQuartz: bounds, primaryScreenTop: top))
        }
    }
}

@MainActor
private final class InteractiveScreenshotSelectionPanel: NSPanel {
    let selectionView: InteractiveScreenshotSelectionView
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect) {
        selectionView = InteractiveScreenshotSelectionView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = InteractiveScreenshotController.selectionWindowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true; hidesOnDeactivate = false; animationBehavior = .none
        acceptsMouseMovedEvents = true; contentView = selectionView
    }
}

@MainActor
private final class InteractiveScreenshotSelectionView: NSView {
    var mode: ScreenshotMode = .window
    var targetRect: CGRect?
    var onMove: ((CGPoint) -> Void)?
    var onDown: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onUp: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private lazy var cameraCursor: NSCursor = {
        guard let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil) else { return .crosshair }
        image.size = NSSize(width: 24, height: 20)
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 10))
    }()

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect], owner: self, userInfo: nil)
        if let tracking { addTrackingArea(tracking) }
        super.updateTrackingAreas()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: mode == .region ? .crosshair : cameraCursor) }
    override func cursorUpdate(with event: NSEvent) { (mode == .region ? NSCursor.crosshair : cameraCursor).set() }
    private func point(_ event: NSEvent) -> CGPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation }
    override func mouseMoved(with event: NSEvent) { onMove?(point(event)) }
    override func mouseDown(with event: NSEvent) { guard event.buttonNumber == 0 else { return }; onDown?(point(event)) }
    override func mouseDragged(with event: NSEvent) { onDrag?(point(event)) }
    override func mouseUp(with event: NSEvent) { guard event.buttonNumber == 0 else { return }; onUp?(point(event)) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onCancel?() } }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let targetRect {
            dim.append(NSBezierPath(rect: targetRect)); dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(targetRect == nil ? 0.06 : 0.17).setFill(); dim.fill()
        guard let targetRect else { return }
        if mode == .window { NSColor.controlAccentColor.withAlphaComponent(0.10).setFill(); NSBezierPath(rect: targetRect).fill() }
        let pixel = 1 / max(1, window?.backingScaleFactor ?? 1)
        let border = NSBezierPath(rect: targetRect.insetBy(dx: pixel / 2, dy: pixel / 2))
        border.lineWidth = pixel; NSColor.white.withAlphaComponent(0.95).setStroke(); border.stroke()
    }
}
