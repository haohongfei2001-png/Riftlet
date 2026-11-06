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
    private var pressBeganWhileShown = false
    private var interactionSuspended = false
    private var busy: Set<String> = []
    private let title = SettingsNativeStyle.label("正在准备截图收录", role: "heading")
    private let detail = SettingsNativeStyle.label("正在读取当前状态。", role: "caption")
    private let symbol = NSImageView()
    private let recovery = SettingsNativeStyle.button("")
    private let capture = SettingsNativeStyle.button("截图…")
    private let captureHint = SettingsNativeStyle.label("", role: "caption")
    private let pause = NSSwitch()
    private let hide = NSSwitch()
    private let footer = SettingsNativeStyle.label("截图后点一下，即可附加", role: "caption")
    private var buttons: [String: NSButton] = [:]
    private let scroll = RiftVisualStyle.topAlignedScrollView()
    private let stack = RiftVisualStyle.documentStack([], spacing: 10)

    public var isShown: Bool { popover.isShown }
    public var window: NSWindow? { body.view.window }
    public var contentView: NSView { body.view }

    public init(statusItem: NSStatusItem, onAction: @escaping SettingsProductActionHandler) {
        self.statusItem = statusItem; self.onAction = onAction
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
            button.setAccessibilityValue("正在准备截图收录")
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
    }

    public func update(_ value: SettingsProductSnapshot) {
        guard snapshot.map({ value.revision >= $0.revision }) ?? true else { return }
        snapshot = value
        refreshControls()
        if !menuTracking { refreshMenu() }
    }

    public func close() {
        popover.close()
        statusItem.button?.highlight(false)
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
        let brand = SettingsNativeStyle.label("Riftlet", role: "heading")
        let settings = button("设置", id: "control.settings")
        settings.font = .systemFont(ofSize: 11)
        let header = SettingsNativeStyle.stack([brand, spacer(), settings], vertical: false, spacing: 8)
        append(header)
        symbol.imageScaling = .scaleProportionallyDown
        symbol.setAccessibilityElement(false)
        symbol.widthAnchor.constraint(equalToConstant: 24).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 24).isActive = true
        title.identifier = .init("control.status")
        detail.identifier = .init("control.detail")
        recovery.identifier = .init("control.recovery")
        recovery.target = self; recovery.action = #selector(buttonPressed(_:))
        recovery.font = .systemFont(ofSize: 11)
        recovery.isHidden = true
        buttons["control.recovery"] = recovery
        let statusText = SettingsNativeStyle.stack([title, detail, recovery], spacing: 5)
        for label in [title, detail] { label.widthAnchor.constraint(equalTo: statusText.widthAnchor).isActive = true }
        let status = SettingsNativeStyle.stack([symbol, statusText], vertical: false, spacing: 10)
        status.alignment = .top
        append(status)
        capture.identifier = .init("control.capture")
        capture.target = self; capture.action = #selector(buttonPressed(_:))
        capture.bezelColor = SettingsNativeStyle.color(.accent)
        capture.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        capture.imagePosition = .imageLeading
        capture.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        buttons["control.capture"] = capture
        captureHint.isHidden = true
        append(group([capture, captureHint], spacing: 5))
        append(separator())
        append(group([
            toggleRow("暂停收录", detail: "保留已有截图", control: pause, id: "control.pause"),
            toggleRow("隐藏裂缝", detail: "只隐藏边缘微图，不改变收录设置", control: hide, id: "control.hide")
        ], spacing: 9))
        append(separator())
        append(group([
            button("截图历史…", id: "control.history", symbol: "clock.arrow.circlepath"),
            button("从边缘收起全部", id: "control.clear", symbol: "archivebox"),
            button("定位最新截图", id: "control.latest", symbol: "photo")
        ], spacing: 2))
        let feedback = button("反馈与建议…", id: "control.feedback")
        feedback.font = .systemFont(ofSize: 11)
        let quit = button("退出", id: "control.quit")
        quit.font = .systemFont(ofSize: 11)
        append(group([SettingsNativeStyle.stack([feedback, spacer(), quit], vertical: false, spacing: 8),
                      footer], spacing: 5))
        let controls: [NSView] = [settings, recovery, capture, pause, hide,
                                  buttons["control.history"]!, buttons["control.clear"]!,
                                  buttons["control.latest"]!, feedback, quit]
        for (a, b) in zip(controls, controls.dropFirst() + [settings]) { a.nextKeyView = b }
        body.view.setAccessibilityLabel("Riftlet 控制中心")
        body.view.frame.size = NSSize(width: SettingsNativeStyle.controlCenterWidth, height: 520)
    }

    private func append(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -34).isActive = true
    }

    private func group(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let value = SettingsNativeStyle.stack(views, spacing: spacing)
        for view in views { view.widthAnchor.constraint(equalTo: value.widthAnchor).isActive = true }
        return value
    }

    private func button(_ title: String, id: String, symbol: String? = nil) -> NSButton {
        let value = SettingsNativeStyle.button(title)
        value.identifier = .init(id)
        value.target = self; value.action = #selector(buttonPressed(_:))
        value.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        if let symbol {
            value.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            value.imagePosition = .imageLeading; value.alignment = .left
            value.bezelStyle = .recessed
            value.showsBorderOnlyWhileMouseInside = true
            value.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        }
        buttons[id] = value
        return value
    }

    private func toggleRow(_ name: String, detail: String, control: NSSwitch, id: String) -> NSView {
        let text = SettingsNativeStyle.stack([SettingsNativeStyle.label(name, role: "rowTitle"),
                                             SettingsNativeStyle.label(detail, role: "caption")], spacing: 3)
        control.identifier = .init(id); control.setAccessibilityLabel(name)
        control.target = self; control.action = #selector(toggleChanged(_:))
        control.controlSize = .small
        control.widthAnchor.constraint(equalToConstant: 44).isActive = true
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        for child in text.arrangedSubviews { child.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true }
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
        buttons["control.clear"]?.isEnabled = snapshot.capabilities.canClearVisible && snapshot.setup.visibleCount > 0
        buttons["control.latest"]?.isEnabled = snapshot.setup.visibleCount > 0
        footer.stringValue = snapshot.reviewEnvironment ? "审核示例留在本机，不连接浏览器。"
            : snapshot.state.owner.isHidden ? "裂缝已隐藏；文件与历史保留。"
            : snapshot.state.owner.collectionPaused ? "已有截图仍可使用。" : "只附加图片，由你决定何时发送。"
        statusItem.button?.toolTip = projection.title + "\n" + projection.detail
        statusItem.button?.setAccessibilityValue(projection.title)
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
            statusItem.button?.highlight(true)
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
        case "control.history": guard snapshot.capabilities.canOpenHistory else { return }; action = .openHistory
        case "control.clear": guard snapshot.capabilities.canClearVisible, snapshot.setup.visibleCount > 0 else { return }; action = .clearVisible
        case "control.latest": guard snapshot.setup.visibleCount > 0 else { return }; action = .showLatest
        case "control.feedback": action = .openFeedback
        case "control.quit": action = .quit
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
        addMenu("截图…", .capture, enabled: snapshot.capabilities.canCapture)
        contextMenu.addItem(.separator())
        addMenu(snapshot.state.owner.collectionPaused ? "继续收录" : "暂停收录",
                .settings(.setCollectionPaused(!snapshot.state.owner.collectionPaused)),
                enabled: pause.isEnabled)
        addMenu(snapshot.state.owner.isHidden ? "显示裂缝" : "隐藏裂缝",
                .settings(.setHidden(!snapshot.state.owner.isHidden)), enabled: hide.isEnabled)
        addMenu("截图历史…", .openHistory, enabled: snapshot.capabilities.canOpenHistory)
        addMenu("定位最新截图", .showLatest, enabled: snapshot.setup.visibleCount > 0)
        addMenu("定位最早截图", .showOldest, enabled: snapshot.setup.visibleCount > 0)
        contextMenu.addItem(.separator())
        addMenu("设置…", .openSettings(.general), key: ",")
        addMenu("反馈与建议…", .openFeedback)
        addMenu("退出 Riftlet", .quit, key: "q")
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
    public func popoverDidClose(_ notification: Notification) { statusItem.button?.highlight(false) }

    private static func templateIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 21), flipped: true) { _ in
            let transform = AffineTransform(scale: 0.64)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 5, y: 5)); path.line(to: NSPoint(x: 16, y: 5))
            path.curve(to: NSPoint(x: 24, y: 12), controlPoint1: NSPoint(x: 21, y: 5), controlPoint2: NSPoint(x: 24, y: 8))
            path.curve(to: NSPoint(x: 16, y: 19), controlPoint1: NSPoint(x: 24, y: 16), controlPoint2: NSPoint(x: 21, y: 19))
            for point in [NSPoint(x: 14, y: 19), NSPoint(x: 23, y: 28), NSPoint(x: 15, y: 28), NSPoint(x: 5, y: 18)] { path.line(to: point) }
            path.close(); path.transform(using: transform)
            NSColor.black.setFill(); path.fill()
            NSColor.clear.setFill(); NSRect(x: 6 * 0.64, y: 2 * 0.64, width: 2 * 0.64, height: 28 * 0.64).fill(using: .copy)
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
