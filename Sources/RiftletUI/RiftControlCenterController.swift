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
    private var busy: Set<String> = []
    private let title = SettingsNativeStyle.label(ProductCopy.text("正在准备截图收录", "Preparing screenshot collection"), role: "heading")
    private let detail = SettingsNativeStyle.label(ProductCopy.text("正在读取当前状态。", "Checking status…"), role: "caption")
    private let symbol = NSImageView()
    private let recovery = SettingsNativeStyle.button("")
    private let capture = SettingsNativeStyle.button(ProductCopy.text("截图…", "Take Screenshot…"))
    private let captureHint = SettingsNativeStyle.label("", role: "caption")
    private let pause = NSSwitch()
    private let hide = NSSwitch()
    private var buttons: [String: NSButton] = [:]
    private let scroll = RiftVisualStyle.topAlignedScrollView()
    private let stack = RiftVisualStyle.documentStack([], spacing: 10)

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
        if identifier == "control.pause" { return pause }
        if identifier == "control.hide" { return hide }
        return buttons[identifier]
    }

    private func configureContent() {
        body.view = SettingsSurfaceView(role: .window, radius: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 17, left: 17, bottom: 17, right: 17)
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
        symbol.imageScaling = .scaleProportionallyDown
        symbol.setAccessibilityElement(false)
        symbol.widthAnchor.constraint(equalToConstant: 17).isActive = true
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.identifier = .init("control.status")
        detail.identifier = .init("control.detail")
        capture.identifier = .init("control.capture")
        capture.target = self; capture.action = #selector(buttonPressed(_:))
        capture.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        capture.imagePosition = .imageLeading
        capture.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttons["control.capture"] = capture
        // The fixed-width popover must fit complete status words even when the
        // capture action has a longer localized title. Keep that same button
        // on its own action row instead of compressing the status beside it.
        append(SettingsNativeStyle.stack([symbol, title, spacer()], vertical: false, spacing: 7))
        append(detail)
        append(SettingsNativeStyle.stack([capture, spacer()], vertical: false, spacing: 7))
        recovery.identifier = .init("control.recovery")
        recovery.target = self; recovery.action = #selector(buttonPressed(_:))
        recovery.isHidden = true
        buttons["control.recovery"] = recovery
        append(recovery)
        let update = button(ProductCopy.text("查看更新…", "View Update…"), id: "control.update", symbol: "arrow.down.circle")
        update.isHidden = true
        append(update)
        captureHint.isHidden = true
        append(captureHint)
        append(separator())
        append(toggleRow(ProductCopy.text("暂停收录", "Pause Collection"), symbol: "pause", control: pause, id: "control.pause"))
        append(toggleRow(ProductCopy.text("隐藏桌面截图", "Hide Desktop Screenshots"), symbol: "eye.slash", control: hide, id: "control.hide"))
        append(separator())
        let history = button(ProductCopy.text("截图历史", "Screenshot History"), id: "control.history", symbol: "clock")
        let settings = button(ProductCopy.text("设置", "Settings"), id: "control.settings", symbol: "gearshape")
        append(SettingsNativeStyle.stack([history, spacer(), settings], vertical: false, spacing: 8))
        let controls: [NSView] = [capture, recovery, update, pause, hide, history, settings]
        for (a, b) in zip(controls, controls.dropFirst() + [capture]) { a.nextKeyView = b }
        body.view.setAccessibilityLabel(ProductCopy.text("Riftlet 控制中心", "Riftlet Control Center"))
        body.view.frame.size = NSSize(width: SettingsNativeStyle.controlCenterWidth, height: 230)
    }

    private func append(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -34).isActive = true
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

    private func toggleRow(_ name: String, symbol: String, control: NSSwitch, id: String) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = SettingsNativeStyle.color(.accentInk)
        icon.setAccessibilityElement(false)
        icon.widthAnchor.constraint(equalToConstant: 19).isActive = true
        let text = SettingsNativeStyle.stack([icon, SettingsNativeStyle.label(name, role: "rowTitle"), spacer()],
                                            vertical: false, spacing: 9)
        control.identifier = .init(id); control.setAccessibilityLabel(name)
        control.target = self; control.action = #selector(toggleChanged(_:))
        control.controlSize = .small
        control.widthAnchor.constraint(equalToConstant: 44).isActive = true
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        text.identifier = .init(id + ".text")
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = SettingsNativeStyle.stack([text, control], vertical: false, spacing: 8)
        // The copy owns the space to the left of the fixed-width switch. A
        // separate expanding spacer can otherwise compress wrapping labels to
        // their shortest intrinsic width while leaving the row mostly blank.
        text.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -52).isActive = true
        return row
    }

    private func spacer() -> NSView {
        let value = NSView()
        value.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return value
    }

    private func separator() -> NSView { let value = NSBox(); value.boxType = .separator; return value }

    private func refreshControls() {
        guard let snapshot else { return }
        buttons.values.forEach { $0.isEnabled = true }
        popover.appearance = NSApp.appearance
        let projection = RiftControlCenterPresentation(snapshot)
        title.stringValue = projection.title
        detail.stringValue = projection.detail
        symbol.image = NSImage(systemSymbolName: projection.symbol, accessibilityDescription: nil)
        symbol.contentTintColor = SettingsNativeStyle.color(projection.state == .attention ? .warning : .accent)
        let update = snapshot.updater
        buttons["control.update"]?.title = update?.checkTitle ?? ProductCopy.text("检查更新…", "Check for Updates…")
        buttons["control.update"]?.isHidden = update?.availableVersion == nil
        buttons["control.update"]?.isEnabled = update?.canCheck == true
        let hasUpdate = update?.availableVersion != nil
        statusItem.button?.title = hasUpdate ? "•" : ""
        statusItem.button?.imagePosition = hasUpdate ? .imageLeading : .imageOnly
        recovery.title = projection.recoveryTitle ?? ""
        recovery.setAccessibilityLabel(recovery.title)
        recovery.isHidden = projection.recoveryPage == nil
        capture.isEnabled = projection.primaryEnabled
        captureHint.isHidden = projection.captureHint == nil
        captureHint.stringValue = projection.captureHint ?? ""
        pause.state = snapshot.state.owner.collectionPaused ? .on : .off
        hide.state = snapshot.state.owner.isHidden ? .on : .off
        pause.isEnabled = snapshot.capabilities.canChangeCollection
            && snapshot.state.domains[.collection]?.isSaving != true && !busy.contains("collection")
        hide.isEnabled = snapshot.capabilities.canChangeVisibility
            && snapshot.state.domains[.visibility]?.isSaving != true && !busy.contains("visibility")
        buttons["control.history"]?.isEnabled = snapshot.capabilities.canOpenHistory
        statusItem.button?.toolTip = projection.title + "\n" + projection.detail
        statusItem.button?.setAccessibilityValue(hasUpdate ? projection.title + ProductCopy.text("，有新版本", ", update available") : projection.title)
        popover.animates = !snapshot.accessibility.reduceMotion
        if interactionSuspended {
            pause.isEnabled = false; hide.isEnabled = false
            buttons.values.forEach { $0.isEnabled = false }
        }
        if isShown { fitPopover() }
    }

    private func fitPopover() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let maximumHeight = max(180, (screen?.visibleFrame.height ?? 700) - 32)
        body.view.frame.size.width = SettingsNativeStyle.controlCenterWidth
        body.view.layoutSubtreeIfNeeded()
        let required = stack.fittingSize.height
        popover.contentSize = NSSize(width: SettingsNativeStyle.controlCenterWidth,
                                     height: min(maximumHeight, max(180, required)))
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

    @objc private func toggleChanged(_ sender: NSSwitch) {
        guard !interactionSuspended, let snapshot else { return }
        let isPause = sender === pause
        let key = isPause ? "collection" : "visibility"
        guard !busy.contains(key), sender.isEnabled else { refreshControls(); return }
        let target = sender.state == .on
        let action: SettingsProductAction = isPause ? .settings(.setCollectionPaused(target)) : .settings(.setHidden(target))
        guard isPause ? snapshot.capabilities.canChangeCollection : snapshot.capabilities.canChangeVisibility else { refreshControls(); return }
        busy.insert(key); refreshControls()
        Task { [weak self] in
            guard let self else { return }
            if !self.interactionSuspended { await self.onAction(action) }
            self.busy.remove(key)
            self.refreshControls()
        }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard !interactionSuspended, sender.isEnabled, let snapshot else { return }
        let action: SettingsProductAction
        switch sender.identifier?.rawValue {
        case "control.settings": action = .openSettings(.general)
        case "control.capture": guard snapshot.capabilities.canCapture else { return }; action = .capture
        case "control.recovery":
            guard let page = RiftControlCenterPresentation(snapshot).recoveryPage else { return }
            action = .openSettings(page)
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
        let heading = NSMenuItem(title: RiftControlCenterPresentation(snapshot).title, action: nil, keyEquivalent: "")
        heading.isEnabled = false; contextMenu.addItem(heading)
        addMenu(ProductCopy.text("截图…", "Take Screenshot…"), .capture, enabled: snapshot.capabilities.canCapture)
        contextMenu.addItem(.separator())
        addMenu(snapshot.state.owner.collectionPaused ? ProductCopy.text("继续收录", "Resume Collection") : ProductCopy.text("暂停收录", "Pause Collection"),
                .settings(.setCollectionPaused(!snapshot.state.owner.collectionPaused)),
                enabled: pause.isEnabled)
        addMenu(snapshot.state.owner.isHidden ? ProductCopy.text("显示桌面截图", "Show Desktop Screenshots") : ProductCopy.text("隐藏桌面截图", "Hide Desktop Screenshots"),
                .settings(.setHidden(!snapshot.state.owner.isHidden)), enabled: hide.isEnabled)
        addMenu(ProductCopy.text("截图历史…", "Screenshot History…"), .openHistory, enabled: snapshot.capabilities.canOpenHistory)
        addMenu(ProductCopy.text("定位最新截图", "Locate Newest Screenshot"), .showLatest, enabled: snapshot.setup.visibleCount > 0)
        addMenu(ProductCopy.text("定位最早截图", "Locate Oldest Screenshot"), .showOldest, enabled: snapshot.setup.visibleCount > 0)
        addMenu(ProductCopy.text("从边缘收起全部", "Remove All from Desktop"), .clearVisible, enabled: snapshot.capabilities.canClearVisible && snapshot.setup.visibleCount > 0)
        contextMenu.addItem(.separator())
        addMenu(ProductCopy.text("设置…", "Settings…"), .openSettings(.general), key: ",")
        if let updater = snapshot.updater {
            addMenu(updater.checkTitle, .checkForUpdates, enabled: updater.canCheck)
        }
        addMenu(ProductCopy.text("反馈与建议…", "Feedback…"), .openFeedback)
        addMenu(ProductCopy.text("退出 Riftlet", "Quit Riftlet"), .quit, key: "q")
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
        // SVG coordinates run downwards. Center its 60 × 62 mark in the 18 pt menu image.
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
            fit.scale(0.25)
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
