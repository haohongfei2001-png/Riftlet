import AppKit

/// The menu and popover are two projections of the same host snapshot/actions.
/// Updates never order a window, request permission, or mutate preferences.
@MainActor
public final class RiftControlCenterController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onAction: SettingsProductActionHandler
    private let popover = NSPopover()
    private let body = RiftControlCenterViewController()
    public let contextMenu = NSMenu(title: "Riftlet")
    private var snapshot: SettingsProductSnapshot?
    private var menuTracking = false
    private var localMonitor: Any?
    private var outsideMouseMonitor: Any?
    private var outsideMouseGeneration: UInt64 = 0
    private let installOutsideMouseMonitor: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    private let removeOutsideMouseMonitor: (Any) -> Void
    private var pressBeganWhileShown = false
    private var interactionSuspended = false
    private var buttons: [String: NSButton] = [:]
    private let scroll = RiftVisualStyle.topAlignedScrollView()
    private let problemLabel = SettingsNativeStyle.label("", role: "rowTitle")
    private let stack = RiftVisualStyle.documentStack([], spacing: 3)

    public var isShown: Bool { popover.isShown }
    public var window: NSWindow? { body.view.window }
    public var contentView: NSView { body.view }

    public convenience init(statusItem: NSStatusItem, onAction: @escaping SettingsProductActionHandler) {
        self.init(statusItem: statusItem, onAction: onAction,
                  installOutsideMouseMonitor: { mask, handler in
                      NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
                  }, removeOutsideMouseMonitor: { NSEvent.removeMonitor($0) })
    }

    // The narrow monitor seam lets tests deliver a retained old callback and
    // verify cleanup without observing or sending real cross-application input.
    init(statusItem: NSStatusItem, onAction: @escaping SettingsProductActionHandler,
         installOutsideMouseMonitor: @escaping (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?,
         removeOutsideMouseMonitor: @escaping (Any) -> Void) {
        self.statusItem = statusItem; self.onAction = onAction
        self.installOutsideMouseMonitor = installOutsideMouseMonitor
        self.removeOutsideMouseMonitor = removeOutsideMouseMonitor
        super.init()
        configureContent()
        popover.contentViewController = body
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        body.onEscape = { [weak self] in self?.close() }
        contextMenu.delegate = self
        contextMenu.autoenablesItems = false
        statusItem.menu = nil
        if let button = statusItem.button {
            button.title = ""
            button.image = Self.templateIcon()
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Riftlet")
            button.setAccessibilityValue(ProductCopy.text("正在准备截图收录", "Preparing screenshot collection"))
            button.target = self; button.action = #selector(statusPressed(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // App-local mouse observation closes exceptions such as a key-on-demand
        // panel. It never swallows/replays an event or observes browser contents.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isStatusEvent(event) {
                    self.pressBeganWhileShown = self.isShown
                    if self.isShown { self.close() }
                } else if self.isShown && event.window !== self.window {
                    self.close()
                }
            }
            return event
        }
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideMouseMonitor { removeOutsideMouseMonitor(outsideMouseMonitor) }
    }

    public func update(_ value: SettingsProductSnapshot) {
        guard snapshot.map({ value.revision >= $0.revision }) ?? true else { return }
        snapshot = value
        refreshControls()
        if !menuTracking { refreshMenu() }
    }

    public func close() {
        stopOutsideMouseObservation()
        popover.close()
        statusItem.button?.highlight(false)
    }

    private func startOutsideMouseObservation() {
        guard outsideMouseMonitor == nil, isShown else { return }
        outsideMouseGeneration &+= 1
        let generation = outsideMouseGeneration
        // A status popover can open while another application stays active.
        // Our local monitor cannot see its next click, and no resign-active
        // transition is guaranteed. Observe only other applications' mouse-down
        // events, without altering their delivery or changing focus.
        outsideMouseMonitor = installOutsideMouseMonitor([.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.outsideMouseGeneration == generation, self.isShown else { return }
                self.close()
            }
        }
    }

    private func stopOutsideMouseObservation() {
        // Removing a monitor does not give an already queued callback authority
        // over a later presentation of this same popover.
        outsideMouseGeneration &+= 1
        guard let monitor = outsideMouseMonitor else { return }
        outsideMouseMonitor = nil
        removeOutsideMouseMonitor(monitor)
    }

    /// The host uses this only after settings have approved App Quit. Keeping
    /// the status item's direct event route closed prevents a fresh popover
    /// while another owner completes asynchronous termination preparation.
    public func setInteractionSuspended(_ suspended: Bool) {
        guard interactionSuspended != suspended else { return }
        interactionSuspended = suspended
        if suspended {
            pressBeganWhileShown = false
            contextMenu.cancelTracking()
            close()
        }
        statusItem.button?.isEnabled = !suspended
        refreshControls()
        if !menuTracking { refreshMenu() }
    }

    /// Read-only native control lookup for isolated UI verification.
    public func control(identifier: String) -> NSView? {
        return buttons[identifier]
    }

    private func configureContent() {
        body.view = SettingsSurfaceView(role: .window, radius: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        scroll.documentView = stack
        body.view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: body.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: body.view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: body.view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: body.view.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor)
        ])
        let settings = button(ProductCopy.text("设置…", "Settings…"), id: "control.settings", symbol: "gearshape")
        let history = button(ProductCopy.text("截图仓库", "Screenshot Library"), id: "control.history", symbol: "photo.on.rectangle")
        let update = button(ProductCopy.text("检查更新…", "Check for Updates…"), id: "control.update", symbol: "arrow.down.circle")
        let quit = button(ProductCopy.text("退出 Riftlet", "Quit Riftlet"), id: "control.quit", symbol: "power")
        problemLabel.identifier = .init("control.status")
        append(problemLabel)
        append(button("", id: "control.recovery", symbol: "arrow.right.circle"))
        [settings, history, update].forEach(append)
        append(separator())
        append(quit)
        let controls: [NSView] = [settings, history, update, quit]
        for (a, b) in zip(controls, controls.dropFirst() + [settings]) { a.nextKeyView = b }
        body.view.setAccessibilityLabel(ProductCopy.text("Riftlet 菜单", "Riftlet Menu"))
        body.view.frame.size = NSSize(width: SettingsNativeStyle.controlCenterWidth, height: 166)
    }


    private func append(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
    }

    private func button(_ title: String, id: String, symbol: String? = nil) -> NSButton {
        let value = SettingsNativeStyle.button(title)
        value.identifier = .init(id)
        value.target = self; value.action = #selector(buttonPressed(_:))
        value.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        if let symbol {
            value.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            value.imagePosition = .imageLeading; value.alignment = .left
            value.isBordered = false
            value.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        }
        buttons[id] = value
        return value
    }

    private func separator() -> NSView { let value = NSBox(); value.boxType = .separator; return value }

    private func refreshControls() {
        guard let snapshot else { return }
        buttons.values.forEach { $0.isEnabled = true }
        popover.appearance = NSApp.appearance
        let projection = RiftControlCenterPresentation(snapshot)
        let actionable = [.attention, .paused, .hidden].contains(projection.state)
        problemLabel.stringValue = projection.title
        problemLabel.isHidden = !actionable
        let recovery = projection.recovery(snapshot)
        buttons["control.recovery"]?.isHidden = recovery == nil
        buttons["control.recovery"]?.title = recovery?.0 ?? ""
        buttons["control.recovery"]?.setAccessibilityLabel(recovery?.0)
        if let quit = buttons["control.quit"], let action = buttons["control.recovery"], let settings = buttons["control.settings"] {
            action.nextKeyView = settings
            quit.nextKeyView = recovery == nil ? settings : action
        }
        let update = snapshot.updater
        let updateButton = buttons["control.update"]
        updateButton?.title = update?.checkTitle ?? ProductCopy.text("检查更新…", "Check for Updates…")
        updateButton?.setAccessibilityLabel(updateButton?.title)
        updateButton?.isEnabled = update?.canCheck == true
        let hasUpdate = update?.availableVersion != nil
        // Keep a stable icon size. Available updates are described by the menu
        // action and accessibility value, without widening the menu-bar item.
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        buttons["control.history"]?.isEnabled = snapshot.capabilities.canOpenHistory
        statusItem.button?.toolTip = projection.title + "\n" + projection.detail
        statusItem.button?.setAccessibilityValue(hasUpdate ? projection.title + ProductCopy.text("，有新版本", ", update available") : projection.title)
        popover.animates = !snapshot.accessibility.reduceMotion
        if interactionSuspended {
            buttons.values.forEach { $0.isEnabled = false }
        }
        for button in buttons.values {
            button.contentTintColor = button.isEnabled ? .labelColor : nil
        }
        if isShown { fitPopover() }
    }

    private func fitPopover() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let maximumHeight = max(160, (screen?.visibleFrame.height ?? 700) - 32)
        body.view.frame.size.width = SettingsNativeStyle.controlCenterWidth
        body.view.layoutSubtreeIfNeeded()
        let required = stack.fittingSize.height
        popover.contentSize = NSSize(width: SettingsNativeStyle.controlCenterWidth,
                                     height: min(maximumHeight, max(160, required)))
    }

    private func isStatusEvent(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button, event.window === button.window else { return false }
        return button.bounds.contains(button.convert(event.locationInWindow, from: nil))
    }

    @objc private func statusPressed(_ sender: Any?) {
        guard !interactionSuspended else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true) {
            pressBeganWhileShown = false
            close(); refreshMenu()
            guard let button = statusItem.button else { return }
            contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            return
        }
        // Transient closing can occur on mouseDown before this mouseUp action.
        // Preserve that gesture's close intent without replaying the event.
        let closesExisting = event?.type == .leftMouseUp && pressBeganWhileShown
        pressBeganWhileShown = false
        if isShown || closesExisting { close(); return }
        guard snapshot != nil, let button = statusItem.button, button.window?.isVisible == true else { return }
        fitPopover()
        popover.appearance = NSApp.appearance
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if popover.isShown {
            startOutsideMouseObservation()
            statusItem.button?.highlight(true)
            // A button-only popover may stay non-key after show. Give this
            // explicitly opened window the keyboard route so native Escape
            // can dismiss it, without activating the application separately.
            body.view.window?.makeKey()
        }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard !interactionSuspended, sender.isEnabled, let snapshot else { return }
        let action: SettingsProductAction
        switch sender.identifier?.rawValue {
        case "control.recovery":
            guard let recovery = RiftControlCenterPresentation(snapshot).recovery(snapshot) else { return }
            action = recovery.1
        case "control.settings": action = .openSettings(.general)
        case "control.quit": action = .quit
        case "control.update": guard snapshot.updater?.canCheck == true else { return }; action = .checkForUpdates
        case "control.history": guard snapshot.capabilities.canOpenHistory else { return }; action = .openHistory
        default: return
        }
        close()
        Task { if !interactionSuspended { await onAction(action) } }
    }

    private func refreshMenu() {
        contextMenu.removeAllItems()
        guard let snapshot else { return }
        let projection = RiftControlCenterPresentation(snapshot)
        if [.attention, .paused, .hidden].contains(projection.state) {
            contextMenu.addItem(statusHeading(projection.title))
            if let recovery = projection.recovery(snapshot) { addMenu(recovery.0, recovery.1) }
            contextMenu.addItem(.separator())
        }
        addMenu(ProductCopy.text("设置…", "Settings…"), .openSettings(.general), key: ",")
        addMenu(ProductCopy.text("截图仓库", "Screenshot Library"), .openHistory, enabled: snapshot.capabilities.canOpenHistory)
        addMenu(snapshot.updater?.checkTitle ?? ProductCopy.text("检查更新…", "Check for Updates…"),
                .checkForUpdates, enabled: snapshot.updater?.canCheck == true)
        contextMenu.addItem(.separator())
        addMenu(ProductCopy.text("退出 Riftlet", "Quit Riftlet"), .quit, key: "q")
    }

    // A status is static text. Drawing it as a disabled command makes a
    // running application look unavailable, including in a non-key menu.
    private func statusHeading(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.textColor = .labelColor
        label.sizeToFit()
        let inset: CGFloat = 14
        let view = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 2 * inset,
                                        height: label.frame.height + 8))
        label.frame.origin = NSPoint(x: inset, y: 4)
        view.addSubview(label)
        item.view = view
        item.isEnabled = false
        return item
    }

    private func addMenu(_ title: String, _ action: SettingsProductAction, enabled: Bool = true, key: String = "") {
        let item = NSMenuItem(title: title, action: #selector(menuPressed(_:)), keyEquivalent: key)
        item.target = self; item.isEnabled = enabled && !interactionSuspended
        item.representedObject = RiftControlCenterMenuAction(action)
        contextMenu.addItem(item)
    }

    @objc private func menuPressed(_ sender: NSMenuItem) {
        guard !interactionSuspended, sender.isEnabled, let action = sender.representedObject as? RiftControlCenterMenuAction else { return }
        close()
        Task { if !interactionSuspended { await onAction(action.value) } }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) { refreshMenu() }
    public func menuWillOpen(_ menu: NSMenu) { menuTracking = true; close() }
    public func menuDidClose(_ menu: NSMenu) { menuTracking = false }
    public func popoverDidClose(_ notification: Notification) {
        stopOutsideMouseObservation()
        statusItem.button?.highlight(false)
    }

    private static func templateIcon() -> NSImage {
        // The two foreground paths of website-assets/riftlet.svg, without the app icon’s tile.
        // SVG coordinates run downwards. Keep its original proportions and center the smaller mark in an 18 pt canvas.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 13, y: 9))
            path.line(to: NSPoint(x: 34, y: 9))
            path.line(to: NSPoint(x: 34, y: 71))
            path.line(to: NSPoint(x: 13, y: 71))
            path.curve(to: NSPoint(x: 4, y: 62),
                       controlPoint1: NSPoint(x: 8, y: 71), controlPoint2: NSPoint(x: 4, y: 67))
            path.line(to: NSPoint(x: 4, y: 18))
            path.curve(to: NSPoint(x: 13, y: 9),
                       controlPoint1: NSPoint(x: 4, y: 13), controlPoint2: NSPoint(x: 8, y: 9))
            path.close()

            path.move(to: NSPoint(x: 40, y: 9))
            path.line(to: NSPoint(x: 45, y: 9))
            path.curve(to: NSPoint(x: 64, y: 29),
                       controlPoint1: NSPoint(x: 57, y: 9), controlPoint2: NSPoint(x: 64, y: 18))
            path.curve(to: NSPoint(x: 47, y: 49),
                       controlPoint1: NSPoint(x: 64, y: 39), controlPoint2: NSPoint(x: 57, y: 46))
            path.line(to: NSPoint(x: 64, y: 71))
            path.line(to: NSPoint(x: 48, y: 71))
            path.line(to: NSPoint(x: 40, y: 59))
            path.close()

            var fit = AffineTransform(translationByX: 9, byY: 9)
            fit.scale(0.21)
            fit.translate(x: -34, y: -40)
            path.transform(using: fit)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor private final class RiftControlCenterViewController: NSViewController {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor private final class RiftControlCenterMenuAction: NSObject {
    let value: SettingsProductAction
    init(_ value: SettingsProductAction) { self.value = value }
}
