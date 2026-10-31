import AppKit
import QuartzCore
import RiftletCapture

public struct ScreenshotEntryControlSnapshot: Sendable {
    public let slot: ScreenshotEntrySlot
    public let mode: ScreenshotMode?
    public let frame: CGRect
    public let windowNumber: Int
    public let isCancel: Bool
    public let isEnabled: Bool
}

/// Geometry and local UI facts only; not proof of WindowServer routing or
/// capture exclusion. All frames use AppKit screen coordinates.
public struct ScreenshotEntryDiagnosticSnapshot: Sendable {
    public let isEnabled: Bool
    public let pointerMonitorCount: Int
    public let hasScheduledFrame: Bool
    public let isExpanded: Bool
    public let mode: ScreenshotMode
    public let defaultMode: ScreenshotMode
    public let isHidden: Bool
    public let isCaptureSuppressed: Bool
    public let isBusy: Bool
    public let glyphAlpha: CGFloat
    public let surfaceAlpha: CGFloat
    public let expansion: CGFloat
    public let cancelSlotPosition: CGFloat
    public let visualWindowNumber: Int
    public let captureStatusText: String?
    public let captureStatusWindowNumber: Int
    public let captureStatusFrame: CGRect
    public let controls: [ScreenshotEntryControlSnapshot]
}

private final class ScreenshotEntryPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(decorative: Bool) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false; isFloatingPanel = true; becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false; animationBehavior = .none
        ignoresMouseEvents = decorative
        if decorative { setAccessibilityHidden(true) }
    }
}

private final class ScreenshotEntryInputView: NSView {
    var onPress: ((Bool) -> Void)?
    var onInvoke: (() -> Void)?
    var isEnabled = true {
        didSet {
            setAccessibilityEnabled(isEnabled)
            if !isEnabled { releasePress() }
        }
    }
    private var pressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, window?.isVisible == true, window?.ignoresMouseEvents == false,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        pressed = true; onPress?(true)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldInvoke = pressed && isEnabled && window?.isVisible == true
            && bounds.contains(convert(event.locationInWindow, from: nil))
        releasePress()
        if shouldInvoke { onInvoke?() }
    }

    func releasePress() {
        guard pressed else { return }
        pressed = false; onPress?(false)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, window?.isVisible == true, let onInvoke else { return false }
        onInvoke(); return true
    }
}

private final class ScreenshotEntryGlyphView: NSView {
    var configuration = ScreenshotEntryConfiguration()
    var session = ScreenshotEntrySession()
    var expansion: CGFloat = 0
    var cancelSlotPosition: CGFloat = 0
    var isBusy = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let c = configuration
        let height = c.controlSize + 3 * c.slotPitch * expansion
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: c.controlSize, height: height),
                     xRadius: 10 + 2 * expansion, yRadius: 10 + 2 * expansion).addClip()
        let cancelCenter = CGPoint(x: c.controlSize / 2,
                                   y: c.controlSize / 2 + cancelSlotPosition * c.slotPitch)
        NSGraphicsContext.saveGraphicsState()
        if session.isExpanded {
            let visibleGlyphs = NSBezierPath(rect: bounds)
            visibleGlyphs.appendRoundedRect(
                CGRect(x: cancelCenter.x - c.upperControlSize / 2,
                       y: cancelCenter.y - c.upperControlSize / 2,
                       width: c.upperControlSize, height: c.upperControlSize), xRadius: 8, yRadius: 8)
            visibleGlyphs.windingRule = .evenOdd
            visibleGlyphs.addClip()
        }
        for slot in ScreenshotEntrySlot.allCases {
            if slot != .anchor && expansion == 0 { continue }
            let center = CGPoint(x: c.controlSize / 2,
                                 y: c.controlSize / 2 + CGFloat(slot.rawValue) * c.slotPitch)
            let isCancel = session.isExpanded && slot == session.activeSlot
            let dimmed = isBusy && !isCancel
            let color = NSColor.labelColor.withAlphaComponent(dimmed ? 0.35 : 0.90)
            if slot == .anchor && !session.isExpanded {
                drawSymbol(.camera, at: center, color: color)
            } else if slot == .more {
                drawSymbol(.more, at: center, color: color)
            } else {
                drawSymbol(.mode(session.modes[slot.rawValue]), at: center, color: color)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if session.isExpanded {
            drawSymbol(.cancel, at: cancelCenter, color: NSColor.labelColor.withAlphaComponent(0.90))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private enum Symbol { case camera, cancel, more, mode(ScreenshotMode) }

    /// Crisp, fixed 17-point strokes. Only alpha changes; no blur, scaling,
    /// moving mode glyphs, or SF Symbol changes between OS releases.
    private func drawSymbol(_ symbol: Symbol, at center: CGPoint, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x - 8.5, yBy: center.y - 8.5)
        transform.scale(by: 17 / 24)
        transform.concat()
        color.setStroke(); color.setFill()
        let path = NSBezierPath()
        path.lineWidth = 1.65
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            path.move(to: CGPoint(x: x1, y: y1)); path.line(to: CGPoint(x: x2, y: y2))
        }
        switch symbol {
        case .camera:
            path.move(to: CGPoint(x: 4, y: 5))
            path.line(to: CGPoint(x: 20, y: 5))
            path.curve(to: CGPoint(x: 22, y: 7), controlPoint1: CGPoint(x: 21.1, y: 5), controlPoint2: CGPoint(x: 22, y: 5.9))
            path.line(to: CGPoint(x: 22, y: 16))
            path.curve(to: CGPoint(x: 20, y: 18), controlPoint1: CGPoint(x: 22, y: 17.1), controlPoint2: CGPoint(x: 21.1, y: 18))
            path.line(to: CGPoint(x: 16, y: 18)); path.line(to: CGPoint(x: 14.5, y: 21))
            path.line(to: CGPoint(x: 9.5, y: 21)); path.line(to: CGPoint(x: 8, y: 18))
            path.line(to: CGPoint(x: 4, y: 18))
            path.curve(to: CGPoint(x: 2, y: 16), controlPoint1: CGPoint(x: 2.9, y: 18), controlPoint2: CGPoint(x: 2, y: 17.1))
            path.line(to: CGPoint(x: 2, y: 7))
            path.curve(to: CGPoint(x: 4, y: 5), controlPoint1: CGPoint(x: 2, y: 5.9), controlPoint2: CGPoint(x: 2.9, y: 5))
            path.close(); path.appendOval(in: CGRect(x: 8.5, y: 8, width: 7, height: 7))
        case .cancel:
            line(6, 6, 18, 18); line(6, 18, 18, 6)
        case .more:
            for x in [CGFloat(5), 12, 19] {
                NSBezierPath(ovalIn: CGRect(x: x - 1.2, y: 10.8, width: 2.4, height: 2.4)).fill()
            }
        case .mode(.window):
            path.appendRoundedRect(CGRect(x: 3, y: 4, width: 18, height: 16), xRadius: 2, yRadius: 2)
            line(3, 15, 21, 15)
            line(6, 17.5, 6.1, 17.5); line(9, 17.5, 9.1, 17.5)
        case .mode(.region):
            line(3, 15, 3, 20); line(3, 20, 8, 20)
            line(16, 20, 21, 20); line(21, 20, 21, 15)
            line(21, 9, 21, 4); line(21, 4, 16, 4)
            line(8, 4, 3, 4); line(3, 4, 3, 9)
        case .mode(.fullScreen):
            path.appendRoundedRect(CGRect(x: 2, y: 7, width: 20, height: 14), xRadius: 2, yRadius: 2)
            line(8, 3, 16, 3); line(12, 3, 12, 7)
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class ScreenshotEntryRailView: NSView {
    let surface = NSView()
    let glass = NSVisualEffectView()
    let selection = NSView()
    let glyphs = ScreenshotEntryGlyphView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        surface.wantsLayer = true
        glass.wantsLayer = true
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.isEmphasized = false
        glass.layer?.masksToBounds = true
        selection.wantsLayer = true
        selection.layer?.cornerRadius = 8
        glyphs.wantsLayer = true
        addSubview(surface); surface.addSubview(glass); glass.addSubview(selection)
        addSubview(glyphs)
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors(); glyphs.needsDisplay = true
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAppearance() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refreshAppearance() }

    func refreshAppearance() { updateColors(); glyphs.needsDisplay = true }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let pixel = 1 / max(1, window?.backingScaleFactor ?? 1)
            let border: NSColor = contrast ? RiftVisualStyle.ink
                : NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? RiftVisualStyle.separator
                : NSColor.white.withAlphaComponent(dark ? 0.14 : 0.48)
            glass.layer?.borderWidth = contrast ? 1 : pixel
            glass.layer?.borderColor = border.cgColor
            // Reduce Transparency must also defeat the optical parent alpha;
            // an opaque material inside a translucent parent still leaks desktop.
            let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            glass.state = opaque ? .inactive : .active
            glass.layer?.backgroundColor = opaque ? RiftVisualStyle.surface.cgColor : NSColor.clear.cgColor
            surface.layer?.shadowColor = NSColor.black.cgColor
            surface.layer?.shadowOpacity = dark ? 0.22 : 0.13
            surface.layer?.shadowOffset = CGSize(width: 0, height: -3)
            surface.layer?.shadowRadius = 8
            selection.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(dark ? 0.10 : 0.065).cgColor
            selection.layer?.borderWidth = contrast ? 1 : pixel
            selection.layer?.borderColor = (contrast ? RiftVisualStyle.ink : NSColor.labelColor.withAlphaComponent(0.12)).cgColor
        }
    }

    func render(configuration c: ScreenshotEntryConfiguration, session: ScreenshotEntrySession,
                expansion: CGFloat, cancelSlotPosition: CGFloat,
                alphas: ScreenshotEntryAlphas, busy: Bool) {
        let origin = CGPoint(x: c.shadowOutset, y: c.shadowOutset)
        let height = c.controlSize + 3 * c.slotPitch * expansion
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.frame = CGRect(origin: origin, size: CGSize(width: c.controlSize, height: height))
        glass.frame = surface.bounds
        glass.layer?.cornerRadius = 10 + 2 * expansion
        surface.layer?.shadowPath = CGPath(roundedRect: surface.bounds,
                                           cornerWidth: 10 + 2 * expansion,
                                           cornerHeight: 10 + 2 * expansion, transform: nil)
        let selectedSize = c.upperControlSize
        selection.frame = CGRect(x: (c.controlSize - selectedSize) / 2,
                                 y: c.controlSize / 2 + cancelSlotPosition * c.slotPitch - selectedSize / 2,
                                 width: selectedSize, height: selectedSize)
        selection.alphaValue = session.isExpanded ? expansion : 0
        surface.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? (alphas.surface > 0 ? 1 : 0) : alphas.surface
        glyphs.frame = CGRect(origin: origin,
                             size: CGSize(width: c.controlSize, height: c.controlSize + 3 * c.slotPitch))
        glyphs.configuration = c; glyphs.session = session; glyphs.expansion = expansion
        glyphs.cancelSlotPosition = cancelSlotPosition
        glyphs.isBusy = busy; glyphs.alphaValue = alphas.glyph
        CATransaction.commit()
        glyphs.needsDisplay = true
    }
}

/// AppKit presentation only. The host owns capture, saved preferences, queue
/// geometry and editing. A completed screenshot never closes this rail.
@MainActor
public final class ScreenshotEntryController: NSObject, NSMenuDelegate {
    public var onGeometryChange: (() -> Void)?
    public var onBegin: ((ScreenshotMode) -> Void)?
    public var onMode: ((ScreenshotMode) -> Void)?
    public var onCancel: (() -> Void)?
    public var onOptions: ((InteractiveScreenshotOptions) -> Void)?
    public var onSettings: ((ScreenshotMode) -> Void)?
    public var onMenuVisibility: ((Bool) -> Void)?

    public private(set) var configuration: ScreenshotEntryConfiguration
    public private(set) var options: InteractiveScreenshotOptions
    public private(set) var isEnabled: Bool
    public private(set) var isHidden = false
    public private(set) var isCaptureSuppressed = false
    public private(set) var isBusy = false
    public private(set) var capturePresentation: InteractiveScreenshotPresentation?
    public var isExpanded: Bool { session.isExpanded }
    public var mode: ScreenshotMode { session.mode }
    public var defaultMode: ScreenshotMode { session.defaultMode }

    private let initialOptions: InteractiveScreenshotOptions
    private var session: ScreenshotEntrySession
    private var optics = ScreenshotEntryOptics()
    private var rail = ScreenshotEntryRailMotion()
    private var cancelMotion = ScreenshotEntryCancelMotion()
    private let decoration = ScreenshotEntryPanel(decorative: true)
    private let drawing = ScreenshotEntryRailView(frame: .zero)
    private let captureStatusPanel = ScreenshotEntryPanel(decorative: true)
    private let captureStatusSurface = RiftSurfaceView(frame: .zero)
    private let captureStatusLabel = NSTextField(wrappingLabelWithString: "")
    private var captureStatusText: String?
    private var announcedRequestID: UUID?
    private var lastAnnouncedNextMode: ScreenshotMode?
    private var inputs: [(panel: ScreenshotEntryPanel, view: ScreenshotEntryInputView)] = []
    private var suppliedScreen: NSScreen?
    private var layout: ScreenshotEntryLayout?
    private var queueFrames: [CGRect] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var accessibilityObserver: NSObjectProtocol?
    private var frameTimer: Timer?
    private var requestedAnchor: CGPoint?
    private var pendingGeometry: (NSScreen?, CGPoint?, [CGRect], ScreenshotEntryConfiguration?)?
    private var pressedSlot: ScreenshotEntrySlot?
    private var suppressionStarted: TimeInterval?
    private var menu: NSMenu?
    private var menuIsOpen = false
    private var closed = false
    private var observationGeneration: UInt64 = 0

    public init(configuration: ScreenshotEntryConfiguration = .init(),
                defaultMode: ScreenshotMode = .window,
                options: InteractiveScreenshotOptions = .init(),
                isEnabled: Bool = true) {
        self.configuration = configuration.validated
        self.isEnabled = isEnabled
        var initial = options
        initial.delay = options.delay.isFinite ? min(60, max(0, options.delay)) : 0
        self.options = initial; initialOptions = initial
        session = ScreenshotEntrySession(defaultMode: defaultMode)
        super.init()
        decoration.contentView = drawing
        captureStatusPanel.contentView = captureStatusSurface
        captureStatusSurface.addSubview(captureStatusLabel)
        captureStatusLabel.isSelectable = false
        captureStatusLabel.setAccessibilityElement(false)
        for slot in ScreenshotEntrySlot.allCases {
            let panel = ScreenshotEntryPanel(decorative: false)
            let view = ScreenshotEntryInputView(frame: .zero)
            panel.contentView = view
            view.setAccessibilityIdentifier("riftlet-screenshot-\(slot.rawValue)")
            view.onPress = { [weak self] pressed in
                guard let self, !self.closed, self.isEnabled else { return }
                self.pressedSlot = pressed ? slot : nil
                if !pressed {
                    Task { @MainActor [weak self] in
                        guard let self, !self.closed, !self.isHidden, self.pressedSlot == nil, let pending = self.pendingGeometry else { return }
                        self.pendingGeometry = nil
                        self.configure(screen: pending.0, anchor: pending.1, queueFrames: pending.2, configuration: pending.3)
                    }
                }
                self.requestFrame()
            }
            view.onInvoke = { [weak self] in self?.perform(slot: slot) }
            inputs.append((panel, view))
        }
        updateControls()
    }

    /// Stops all entry-only work without changing collection or saved media.
    /// The host separately cancels the engine and invalidates its callbacks.
    /// Re-enabling restores an idle entry; it never resumes an old selection.
    public func setEnabled(_ enabled: Bool) {
        guard !closed, enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            stopObservation()
            closePreferences()
            inputs.forEach { $0.view.releasePress() }
            pressedSlot = nil
            session.setExpanded(false)
            setCapturePresentation(nil)
            isBusy = false
            isCaptureSuppressed = false
            suppressionStarted = nil
            optics = ScreenshotEntryOptics()
            rail.setExpanded(false, at: uptime, duration: 0, animated: false)
            cancelMotion.move(to: .anchor, at: uptime, animated: false)
            orderOut()
            paint()
        } else {
            drawing.refreshAppearance()
            reconcileObservation()
            observePointer()
        }
        updateControls()
        requestFrame()
    }

    private func reconcileObservation() {
        guard !closed, isEnabled, !isHidden, layout != nil else {
            stopObservation(); return
        }
        guard globalMonitor == nil, localMonitor == nil, accessibilityObserver == nil else { return }
        observationGeneration &+= 1
        let generation = observationGeneration
        // Mouse-only observation. The local handler always returns the original
        // event; no listener posts, consumes or redirects another app's input.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                         .otherMouseDragged, .leftMouseDown, .leftMouseUp,
                                         .rightMouseDown, .rightMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self, self.observationGeneration == generation else { return }
            self.observePointer()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if let self, self.observationGeneration == generation { self.observePointer() }
            return event
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.observationGeneration == generation else { return }
                    self.applyAccessibilityDisplayOptions(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                }
            }
    }

    private func stopObservation() {
        observationGeneration &+= 1
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        stopFrames()
    }

    /// Applies presentation policy without changing a capture/session/input fact.
    /// The explicit value also permits regression checks without changing macOS preferences.
    func applyAccessibilityDisplayOptions(reduceMotion: Bool) {
        guard !closed, isEnabled else { return }
        drawing.refreshAppearance()
        if reduceMotion {
            stopFrames()
            let time = uptime
            rail.setExpanded(session.isExpanded, at: time, duration: configuration.expansionDuration, animated: false)
            cancelMotion.move(to: session.isExpanded ? session.activeSlot : .anchor, at: time, animated: false)
            // Paint the current semantic endpoint even while capture hides us;
            // restoration must never resume the abandoned spatial interpolation.
            paint()
        }
        requestFrame()
    }

    public func configure(screen: NSScreen?, anchor: CGPoint? = nil,
                          queueFrames: [CGRect] = [],
                          configuration: ScreenshotEntryConfiguration? = nil) {
        guard !closed else { return }
        guard pressedSlot == nil else {
            pendingGeometry = (screen, anchor, queueFrames, configuration)
            return
        }
        pendingGeometry = nil
        requestedAnchor = anchor
        if let configuration { self.configuration = configuration.validated }
        suppliedScreen = screen
        self.queueFrames = queueFrames.filter {
            !$0.isEmpty && !$0.isNull && !$0.isInfinite
                && [$0.minX, $0.minY, $0.width, $0.height].allSatisfy { $0.isFinite }
        }
        layout = screen.flatMap {
            ScreenshotEntryLayout.avoidingInputs(screenFrame: $0.frame, visibleFrame: $0.visibleFrame,
                                       anchor: anchor ?? CGPoint(x: $0.frame.maxX - self.configuration.anchorRightInset,
                                                                 y: $0.frame.maxY - self.configuration.anchorFromTop),
                                       inputs: self.queueFrames, configuration: self.configuration, expanded: self.session.isExpanded)
        }
        if let layout {
            decoration.setFrame(layout.visualWindowFrame, display: true)
            for slot in ScreenshotEntrySlot.allCases {
                inputs[slot.rawValue].panel.setFrame(layout.controlFrames[slot.rawValue], display: true)
            }
        }
        reconcileObservation()
        observePointer()
        requestFrame()
        onGeometryChange?()
    }

    /// Changing this preference never changes the running session or its slots.
    public func setDefaultMode(_ mode: ScreenshotMode) {
        guard !closed else { return }
        session.setDefaultMode(mode); updateControls()
    }

    public func setOptions(_ options: InteractiveScreenshotOptions) {
        guard !closed else { return }
        self.options = options
        self.options.delay = options.delay.isFinite ? min(60, max(0, options.delay)) : 0
    }

    public func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard !closed, (!expanded || isEnabled), expanded != session.isExpanded else { return }
        inputs.forEach { $0.view.releasePress() }
        session.setExpanded(expanded)
        if expanded { cancelMotion.move(to: .anchor, at: uptime, animated: false) }
        isBusy = false
        if expanded { options = initialOptions }
        pressedSlot = nil
        configure(screen: suppliedScreen, anchor: requestedAnchor, queueFrames: queueFrames)
        if !expanded {
            setCapturePresentation(nil)
            closePreferences()
            if let layout, let screen = suppliedScreen {
                optics.resume(anchor: layout.anchor, screenWidth: screen.frame.width,
                              configuration: configuration.optics, afterCancel: true)
            }
        }
        rail.setExpanded(expanded, at: uptime, duration: configuration.expansionDuration,
                         animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        updateControls()
        requestFrame()
    }

    /// Updates semantics immediately. No alpha or spatial-memory reset occurs.
    public func setMode(_ mode: ScreenshotMode) {
        guard !closed, isEnabled else { return }
        inputs.forEach { $0.view.releasePress() }
        session.setMode(mode)
        cancelMotion.move(to: session.activeSlot, at: uptime,
                          animated: session.isExpanded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        updateControls(); requestFrame()
    }

    public func setHidden(_ hidden: Bool) {
        guard !closed, hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            pendingGeometry = nil
            setCapturePresentation(nil)
            inputs.forEach { $0.view.releasePress() }
            closePreferences(); orderOut()
        }
        reconcileObservation()
        if !hidden { optics.resumeClock(); observePointer(); requestFrame() }
    }

    /// Capture can hide its own controls for a few frames without collapsing,
    /// ending a session, changing any alpha, or changing the selected mode.
    public func setCaptureSuppressed(_ suppressed: Bool) {
        guard !closed, isEnabled, suppressed != isCaptureSuppressed else { return }
        isCaptureSuppressed = suppressed
        if suppressed {
            suppressionStarted = uptime
            inputs.forEach { $0.view.releasePress() }
            orderOut()
        } else {
            if let start = suppressionStarted {
                let elapsed = uptime - start
                rail.shiftClock(by: elapsed); cancelMotion.shiftClock(by: elapsed)
            }
            suppressionStarted = nil
            optics.resumeClock()
            // Restore the exact current drawing before advancing its next frame.
            paint(); updateWindowVisibility(); scheduleFrameIfNeeded()
        }
    }

    /// Editing/processing is host-owned. The current mode's X remains enabled.
    public func setBusy(_ busy: Bool) {
        guard !closed, isEnabled else { return }
        isBusy = busy; updateControls(); requestFrame()
    }

    /// Displays only the host's current frozen request. No countdown timer or
    /// capture action is owned here; every number comes from the real engine.
    public func setCapturePresentation(_ value: InteractiveScreenshotPresentation?) {
        let accepted = !closed && isEnabled && !isHidden && session.isExpanded ? value : nil
        capturePresentation = accepted
        let text: String?
        if let accepted, let seconds = accepted.remainingSeconds {
            text = "已选\(Self.name(accepted.confirmedMode)) · \(seconds) 秒后拍摄"
        } else if let accepted, case .capturing = accepted.state {
            text = "正在拍摄已选\(Self.name(accepted.confirmedMode))"
        } else { text = nil }
        captureStatusText = text.map { firstLine in
            guard let accepted, accepted.nextMode != accepted.confirmedMode else { return firstLine }
            return firstLine + "\n下一张：\(Self.name(accepted.nextMode))"
        }
        updateControls()
        updateCaptureStatusVisibility()
        if let accepted, let text = captureStatusText {
            let announcement: String?
            if announcedRequestID != accepted.requestID {
                announcedRequestID = accepted.requestID
                lastAnnouncedNextMode = accepted.nextMode
                announcement = text + "。按 Escape 或结束截图退出。"
            } else if lastAnnouncedNextMode != accepted.nextMode {
                lastAnnouncedNextMode = accepted.nextMode
                announcement = "下一张改为\(Self.name(accepted.nextMode))，本次仍为已选\(Self.name(accepted.confirmedMode))。"
            } else { announcement = nil }
            if let announcement {
                NSAccessibility.post(element: inputs[session.activeSlot.rawValue].view,
                    notification: .announcementRequested,
                    userInfo: [.announcement: announcement,
                               .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
    }

    public var captureExclusionWindowIDs: [CGWindowID] {
        ([decoration, captureStatusPanel] + inputs.map(\.panel)).compactMap {
            $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil
        }
    }

    public var inputFrames: [CGRect] {
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed, let layout else { return [] }
        return ScreenshotEntrySlot.allCases.compactMap { slot in
            let input = inputs[slot.rawValue]
            return input.view.isEnabled && input.panel.isVisible ? layout.controlFrames[slot.rawValue] : nil
        }
    }

    public var diagnosticSnapshot: ScreenshotEntryDiagnosticSnapshot {
        let controls = ScreenshotEntrySlot.allCases.map { slot in
            ScreenshotEntryControlSnapshot(slot: slot,
                mode: slot == .more ? nil : session.modes[slot.rawValue],
                frame: inputs[slot.rawValue].panel.frame,
                windowNumber: inputs[slot.rawValue].panel.windowNumber,
                isCancel: session.isExpanded && slot == session.activeSlot,
                isEnabled: inputs[slot.rawValue].view.isEnabled)
        }
        return ScreenshotEntryDiagnosticSnapshot(isEnabled: isEnabled,
            pointerMonitorCount: (globalMonitor == nil ? 0 : 1) + (localMonitor == nil ? 0 : 1),
            hasScheduledFrame: frameTimer != nil, isExpanded: isExpanded, mode: mode,
            defaultMode: defaultMode, isHidden: isHidden, isCaptureSuppressed: isCaptureSuppressed,
            isBusy: isBusy, glyphAlpha: optics.alphas.glyph, surfaceAlpha: optics.alphas.surface,
            expansion: rail.value, cancelSlotPosition: cancelMotion.value,
            visualWindowNumber: decoration.windowNumber, captureStatusText: captureStatusText,
            captureStatusWindowNumber: captureStatusPanel.windowNumber,
            captureStatusFrame: captureStatusPanel.frame, controls: controls)
    }

    public func close() {
        guard !closed else { return }
        closed = true
        pendingGeometry = nil
        isEnabled = false
        capturePresentation = nil; captureStatusText = nil
        closePreferences()
        stopObservation()
        for input in inputs {
            input.view.onPress = nil; input.view.onInvoke = nil
            input.view.isEnabled = false; input.panel.close()
        }
        decoration.close()
        captureStatusPanel.close()
    }

    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func observePointer() {
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed, let screen = suppliedScreen, let layout else { return }
        optics.observe(point: NSEvent.mouseLocation, at: uptime, anchor: layout.anchor,
                       screenFrame: screen.frame, pointerIsDown: NSEvent.pressedMouseButtons != 0,
                       configuration: configuration.optics)
        updateWindowVisibility()
        requestFrame()
    }

    private func perform(slot: ScreenshotEntrySlot) {
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed,
              inputs[slot.rawValue].view.isEnabled, let action = session.action(for: slot) else { return }
        switch action {
        case .begin:
            setExpanded(true)
            onBegin?(session.mode)
        case .select(let mode):
            setMode(mode)
            onMode?(mode)
        case .cancel:
            setExpanded(false)
            onCancel?()
        case .options:
            showOptions()
        }
    }

    private func updateControls() {
        let level: NSWindow.Level = session.isExpanded
            ? InteractiveScreenshotController.controlsWindowLevel : .floating
        decoration.level = level
        captureStatusPanel.level = level
        for slot in ScreenshotEntrySlot.allCases {
            let input = inputs[slot.rawValue]
            input.panel.level = level
            let active = session.isExpanded && slot == session.activeSlot
            input.view.isEnabled = isEnabled && (session.isExpanded || slot == .anchor) && (!isBusy || active)
            let label: String
            if !session.isExpanded { label = "截图，默认\(Self.name(session.defaultMode))" }
            else if active { label = "结束截图" }
            else if slot == .more { label = "更多截图选项" }
            else { label = "截取\(Self.name(session.modes[slot.rawValue]))" }
            input.view.setAccessibilityLabel(label)
            input.view.setAccessibilityHelp(active ? (captureStatusText ?? "按 Escape 或结束截图退出。") : nil)
            input.view.toolTip = label
        }
    }

    private func requestFrame() {
        updateWindowVisibility()
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed, layout != nil else { stopFrames(); return }
        guard frameTimer == nil else { return }
        advanceFrame()
        scheduleFrameIfNeeded()
    }

    private func scheduleFrameIfNeeded() {
        guard frameTimer == nil, !closed, isEnabled, !isHidden, !isCaptureSuppressed, layout != nil,
              !optics.isSettled || !rail.isSettled || !cancelMotion.isSettled else { return }
        let timer = Timer(timeInterval: 1 / 60, target: self, selector: #selector(animationFrame(_:)),
                          userInfo: nil, repeats: true)
        timer.tolerance = 0.002
        frameTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func animationFrame(_ timer: Timer) {
        guard timer === frameTimer else { return }
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed else { stopFrames(); return }
        advanceFrame()
        if optics.isSettled && rail.isSettled && cancelMotion.isSettled { stopFrames() }
    }

    private func advanceFrame() {
        guard let layout, let screen = suppliedScreen else { orderOut(); return }
        let time = uptime
        optics.advance(at: time, anchor: layout.anchor, screenWidth: screen.frame.width,
                       queueFrames: queueFrames, expanded: session.isExpanded,
                       pressed: pressedSlot != nil, configuration: configuration)
        rail.advance(at: time)
        cancelMotion.advance(at: time)
        paint(); updateWindowVisibility()
    }

    private func paint() {
        drawing.render(configuration: configuration, session: session, expansion: rail.value,
                       cancelSlotPosition: cancelMotion.value,
                       alphas: optics.alphas, busy: isBusy)
    }

    private func updateWindowVisibility() {
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed, let layout else { orderOut(); return }
        if optics.alphas.glyph > 0 || optics.alphas.surface > 0 {
            if !decoration.isVisible { decoration.orderFrontRegardless() }
        } else { decoration.orderOut(nil) }
        for slot in ScreenshotEntrySlot.allCases {
            let input = inputs[slot.rawValue]
            let shown = session.isExpanded || slot == .anchor
            guard shown else { input.panel.orderOut(nil); continue }
            if !input.panel.isVisible { input.panel.orderFrontRegardless() }
            let overEntry = optics.point.map { layout.entryFrame.contains($0) } ?? false
            let overQueue = optics.point.map { point in queueFrames.contains { $0.contains(point) } } ?? false
            // Clickability depends on geometry/role, never alpha or animation.
            input.panel.ignoresMouseEvents = !input.view.isEnabled
                || (!session.isExpanded && (!overEntry || overQueue))
            input.view.setAccessibilityHidden(false)
        }
        updateCaptureStatusVisibility()
    }

    private func updateCaptureStatusVisibility() {
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed, session.isExpanded,
              let text = captureStatusText, let layout, let screen = suppliedScreen else {
            captureStatusPanel.orderOut(nil); return
        }
        // Use the inward free column on either edge. A left-side queue must
        // not reuse the old right-only status rectangle over its controls.
        let safe = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let obstacles = queueFrames + layout.controlFrames
        let leading = obstacles.map(\.minX).min() ?? safe.maxX
        let trailing = obstacles.map(\.maxX).max() ?? safe.minX
        let leftEnd = min(safe.maxX, leading - 12)
        let rightStart = max(safe.minX, trailing + 12)
        let leftWidth = min(CGFloat(240),leftEnd - safe.minX)
        let rightWidth = min(CGFloat(240),safe.maxX - rightStart)
        let preferRight = layout.anchor.x < safe.midX
        let useRight = preferRight ? rightWidth >= 144 : leftWidth < 144 && rightWidth >= 144
        let width = useRight ? rightWidth : leftWidth
        guard width >= 144 else { captureStatusPanel.orderOut(nil); return }
        let x = useRight ? rightStart : leftEnd - width
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: RiftVisualStyle.ink,
            .paragraphStyle: paragraph])
        let measured = attributed.boundingRect(with: CGSize(width: width - 24, height: 120),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let height = ceil(max(18, measured)) + 24
        guard height <= safe.height else { captureStatusPanel.orderOut(nil); return }
        let y = max(safe.minY, min(layout.anchor.y - height / 2, safe.maxY - height))
        captureStatusPanel.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
        captureStatusLabel.attributedStringValue = attributed
        captureStatusLabel.frame = CGRect(x: 12, y: 12, width: width - 24, height: height - 24)
        if !captureStatusPanel.isVisible { captureStatusPanel.orderFrontRegardless() }
    }

    private func orderOut() {
        stopFrames()
        decoration.orderOut(nil)
        captureStatusPanel.orderOut(nil)
        inputs.forEach { $0.panel.orderOut(nil) }
    }

    private func stopFrames() { frameTimer?.invalidate(); frameTimer = nil }

    private static func name(_ mode: ScreenshotMode) -> String {
        switch mode { case .window: return "窗口"; case .region: return "区域"; case .fullScreen: return "全屏" }
    }

    /// Explicit settings access exposes the existing choices without starting capture.
    public func showPreferences() { showOptions(requiresExpanded: false) }

    public func closePreferences() {
        let activeMenu = menu
        menu = nil
        activeMenu?.cancelTrackingWithoutAnimation()
        if menuIsOpen { menuIsOpen = false; onMenuVisibility?(false) }
    }

    private func showOptions(requiresExpanded: Bool = true) {
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed,
              (!requiresExpanded || session.isExpanded), !isBusy, !menuIsOpen else { return }
        let menu = NSMenu(title: "截图选项")
        menu.autoenablesItems = false; menu.delegate = self
        let defaults = NSMenu(title: "默认截图方式")
        defaults.autoenablesItems = false
        for mode in [ScreenshotMode.window, .region, .fullScreen] {
            let item = NSMenuItem(title: Self.name(mode), action: #selector(changeDefault(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = mode.rawValue
            item.state = mode == session.defaultMode ? .on : .off
            defaults.addItem(item)
        }
        let defaultItem = NSMenuItem(title: "默认截图方式", action: nil, keyEquivalent: "")
        defaultItem.submenu = defaults; menu.addItem(defaultItem)
        menu.addItem(.separator())
        let pointer = NSMenuItem(title: "显示指针", action: #selector(togglePointer(_:)), keyEquivalent: "")
        pointer.target = self; pointer.state = options.showPointer ? .on : .off; menu.addItem(pointer)
        let delays = NSMenu(title: "延时")
        delays.autoenablesItems = false
        for seconds in [0, 5, 10] {
            let item = NSMenuItem(title: seconds == 0 ? "无" : "\(seconds) 秒",
                                 action: #selector(changeDelay(_:)), keyEquivalent: "")
            item.target = self; item.tag = seconds
            item.state = options.delay == TimeInterval(seconds) ? .on : .off
            delays.addItem(item)
        }
        let delay = NSMenuItem(title: "延时", action: nil, keyEquivalent: "")
        delay.submenu = delays; menu.addItem(delay)
        let edit = NSMenuItem(title: "截图后编辑", action: #selector(toggleEditing(_:)), keyEquivalent: "")
        edit.target = self; edit.state = options.editAfter ? .on : .off; menu.addItem(edit)
        self.menu = menu
        if session.isExpanded {
            let view = inputs[ScreenshotEntrySlot.more.rawValue].view
            menu.popUp(positioning: nil, at: CGPoint(x: -menu.size.width - 6, y: view.bounds.maxY), in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        if self.menu === menu { closePreferences() }
    }

    private func ownsMenuAction(_ sender: NSMenuItem) -> Bool {
        guard !closed, isEnabled, !isHidden, !isCaptureSuppressed, let activeMenu = menu,
              let itemMenu = sender.menu else { return false }
        return itemMenu === activeMenu || itemMenu.supermenu === activeMenu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard !closed, isEnabled, menu === self.menu, !menuIsOpen else { return }
        menuIsOpen = true; onMenuVisibility?(true)
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu, menuIsOpen else { return }
        menuIsOpen = false; onMenuVisibility?(false)
    }

    @objc private func changeDefault(_ sender: NSMenuItem) {
        guard ownsMenuAction(sender), let raw = sender.representedObject as? String, let value = ScreenshotMode(rawValue: raw) else { return }
        setDefaultMode(value); onSettings?(value)
    }

    @objc private func togglePointer(_ sender: NSMenuItem) {
        guard ownsMenuAction(sender) else { return }
        options.showPointer.toggle(); onOptions?(options)
    }

    @objc private func changeDelay(_ sender: NSMenuItem) {
        guard ownsMenuAction(sender) else { return }
        options.delay = TimeInterval(sender.tag); onOptions?(options)
    }

    @objc private func toggleEditing(_ sender: NSMenuItem) {
        guard ownsMenuAction(sender) else { return }
        options.editAfter.toggle(); onOptions?(options)
    }

    deinit {
        frameTimer?.invalidate()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
}
