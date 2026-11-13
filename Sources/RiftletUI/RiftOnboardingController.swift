import AppKit

/// Three-step guidance uses the same host facts and explicit settings commands.
/// Its only local state is navigation; it stores no permission/completion flags.
@MainActor
public final class RiftOnboardingController: NSObject, NSWindowDelegate, NSMenuDelegate {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("RiftletOnboarding")
    public let window: NSWindow
    public private(set) var currentStep = 0
    public var isVisible: Bool { window.isVisible }
    private let onAction: SettingsProductActionHandler
    private var snapshot: SettingsProductSnapshot?
    private var hasPresented = false
    private var finishedThisPresentation = false
    private var busy: Set<SettingsDomain> = []
    private var controls: [String: NSView] = [:]
    private var pages: [NSView] = []
    private let progress = SettingsNativeStyle.stack([], vertical: false, spacing: 9)
    private let content = RiftVisualStyle.documentStack([], spacing: 16)
    private let scroll = RiftVisualStyle.topAlignedScrollView()
    private let next = SettingsNativeStyle.button("继续")
    private let back = SettingsNativeStyle.button("上一步")
    private let later = SettingsNativeStyle.button("稍后设置")
    private let introTitle = SettingsNativeStyle.label("从截图到输入。\n点一下就够了。", role: "title")
    private let introDescription = SettingsNativeStyle.label("")
    private let introCapability = SettingsNativeStyle.label("", role: "secondary")
    private let sourceDetail = SettingsNativeStyle.label("", role: "secondary")
    private let sourcePath = SettingsNativeStyle.label("", role: "caption")
    private let automationDetail = SettingsNativeStyle.label("", role: "secondary")
    private let scriptDetail = SettingsNativeStyle.label("")
    private lazy var chromeMenuSection = section("在 Chrome 中开启一键附加", symbol: "menubar.rectangle", views: [scriptDetail])
    private let permissionHint = SettingsNativeStyle.label("", role: "caption")
    private let sourceAccess = SettingsNativeStyle.button("允许访问…")
    private let automation = SettingsNativeStyle.button("检查 Chrome 权限…")
    private let display = NSPopUpButton(frame: .zero, pullsDown: false)
    private var displayMenuTracking = false
    private var displayRefreshPending = false
    private var displaySignature: [RiftSettingsDisplay] = []
    private var representedPreferredDisplayID: UInt32?
    private let placementPreview = RiftOnboardingPlacementPreview()
    private var placements: [RiftPlacement: NSButton] = [:]
    private let placementHint = SettingsNativeStyle.label("", role: "caption")
    private let placementError = SettingsNativeStyle.label("", role: "secondary")
    private let displayError = SettingsNativeStyle.label("", role: "secondary")
    private let finishHint = SettingsNativeStyle.label("", role: "secondary")

    public init(onAction: @escaping SettingsProductActionHandler) {
        self.onAction = onAction
        window = RiftVisualStyle.window(outerSize: SettingsNativeStyle.onboardingSize,
            minimum: NSSize(width: 520, height: 416), title: "开始使用 Riftlet")
        super.init()
        window.identifier = Self.windowIdentifier
        window.delegate = self
        window.animationBehavior = .none
        window.autorecalculatesKeyViewLoop = true
        configureContent()
        refreshStep()
    }

    public func update(_ value: SettingsProductSnapshot) {
        guard snapshot.map({ value.revision >= $0.revision }) ?? true else { return }
        snapshot = value
        refreshFacts()
    }

    /// Returning true is the host's boundary for the existing presented.v1 key.
    /// This never writes a first-use/completion preference itself.
    @discardableResult
    public func show() -> Bool {
        guard snapshot != nil, let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        let previousFrame = window.frame
        if !isVisible {
            currentStep = 0; finishedThisPresentation = false
            refreshStep()
        }
        if !hasPresented {
            var outer = SettingsNativeStyle.onboardingSize
            let visible = screen.visibleFrame
            outer.width = min(outer.width, visible.width)
            outer.height = min(outer.height, visible.height)
            let frame = NSRect(x: visible.midX - outer.width / 2, y: visible.midY - outer.height / 2,
                               width: outer.width, height: outer.height)
            layout(keeping: frame)
        } else {
            let reachable = RiftVisualStyle.reachableWindowFrame(previousFrame,
                visibleFrames: NSScreen.screens.map(\.visibleFrame), preferredFrame: window.screen?.visibleFrame)
            layout(keeping: reachable)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hasPresented = window.isVisible
        return window.isVisible
    }

    public func closeForTeardown() { window.close() }
    public func control(identifier: String) -> NSView? { controls[identifier] }

    private func layout(keeping frame: NSRect) {
        // Wrapping text and hidden stack pages can change the native fitting
        // width. Complete that pass first, then restore the explicit window
        // size; never read a fitting result back as the user's resize choice.
        // Do not run a second eager layout/center pass after applying this size.
        window.contentView?.layoutSubtreeIfNeeded()
        guard window.frame != frame else { return }
        window.setContentSize(window.contentRect(forFrameRect: frame).size)
        window.setFrame(frame, display: false)
    }

    private func configureContent() {
        let root = SettingsSurfaceView(role: .window)
        window.contentView = root
        progress.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(progress); root.addSubview(scroll)
        for (index, title) in ["截图", "连接", "位置"].enumerated() {
            if index > 0 {
                let separator = NSImageView()
                separator.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 9, weight: .regular))
                separator.contentTintColor = .tertiaryLabelColor
                separator.setAccessibilityElement(false)
                progress.addArrangedSubview(separator)
            }
            let label = SettingsNativeStyle.label(title, role: "caption")
            label.tag = index
            label.identifier = .init("onboarding.progress.\(index)")
            progress.addArrangedSubview(label)
        }
        scroll.documentView = content
        scroll.setAccessibilityLabel("Riftlet 使用引导内容")
        next.identifier = .init("onboarding.next"); next.target = self; next.action = #selector(nextStep)
        next.keyEquivalent = "\r"; next.bezelColor = SettingsNativeStyle.color(.accent)
        back.identifier = .init("onboarding.back"); back.target = self; back.action = #selector(previousStep)
        later.identifier = .init("onboarding.later"); later.target = self; later.action = #selector(deferSetup)
        later.keyEquivalent = "\u{1b}"
        let footer = SettingsNativeStyle.stack([back, later, NSView(), next], vertical: false, spacing: 12)
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.arrangedSubviews[2].setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addSubview(footer)
        for button in [next, back, later] {
            controls[button.identifier!.rawValue] = button
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        }
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            progress.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -26),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            scroll.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 13),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22)
        ])
        introDescription.identifier = .init("onboarding.introDescription")
        introCapability.identifier = .init("onboarding.capability")
        controls["onboarding.introDescription"] = introDescription
        controls["onboarding.capability"] = introCapability
        introTitle.font = .systemFont(ofSize: 28, weight: .semibold)
        let intro = page([introTitle, introDescription, RiftOnboardingPlacementPreview(workflow: true), introCapability])
        sourceAccess.identifier = .init("onboarding.sourceAccess")
        sourceAccess.target = self; sourceAccess.action = #selector(actionPressed(_:))
        controls["onboarding.sourceAccess"] = sourceAccess
        automation.identifier = .init("onboarding.automation")
        automation.target = self; automation.action = #selector(actionPressed(_:))
        controls["onboarding.automation"] = automation
        sourceDetail.identifier = .init("onboarding.sourceStatus")
        automationDetail.identifier = .init("onboarding.automationStatus")
        scriptDetail.identifier = .init("onboarding.scriptStatus")
        controls["onboarding.scriptStatus"] = scriptDetail
        let connections = page([
            SettingsNativeStyle.label("连接截图与草稿", role: "title"),
            chromeMenuSection,
            section("截图文件夹", symbol: "folder", views: [sourceDetail, sourcePath, sourceAccess]),
            section("允许 Riftlet 控制 Chrome", symbol: "macwindow", views: [automationDetail, automation]),
            permissionHint, actionButton("重新检查连接", id: "onboarding.recheck")
        ])
        display.identifier = .init("onboarding.display"); display.setAccessibilityLabel("所在显示器")
        display.target = self; display.action = #selector(displayChanged)
        display.menu?.delegate = self
        display.menu?.autoenablesItems = false
        display.font = .systemFont(ofSize: 13)
        display.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        controls["onboarding.display"] = display
        let choices = SettingsNativeStyle.stack([], vertical: false, spacing: 1)
        choices.distribution = .fillEqually
        for placement in RiftPlacement.allCases {
            let button = SettingsNativeStyle.button(placement.title)
            button.setButtonType(.pushOnPushOff); button.bezelStyle = .roundRect
            button.identifier = .init("onboarding.placement." + placement.rawValue)
            button.target = self; button.action = #selector(placementChanged(_:))
            button.setAccessibilityLabel("桌面位置：" + placement.title)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
            placements[placement] = button; controls[button.identifier!.rawValue] = button
            choices.addArrangedSubview(button)
        }
        let displayRetry = actionButton("重试显示器选择", id: "onboarding.retryDisplay")
        let placementRetry = actionButton("重试位置选择", id: "onboarding.retryPlacement")
        let displayRow = SettingsNativeStyle.stack([SettingsNativeStyle.label("所在显示器", role: "rowTitle"), display, NSView()],
                                                  vertical: false, spacing: 8)
        controls["onboarding.finishHint"] = finishHint
        let placementPage = page([
            SettingsNativeStyle.label("选一个顺手的位置", role: "title"),
            SettingsNativeStyle.label("新截图会从所选的屏幕边缘出现。之后可以在设置中调整。", role: "secondary"),
            placementPreview, choices, displayRow,
            displayError, displayRetry, placementError, placementRetry, placementHint, finishHint
        ])
        pages = [intro, connections, placementPage]
        for page in pages {
            content.addArrangedSubview(page)
            page.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        window.initialFirstResponder = next
        root.setAccessibilityLabel("开始使用 Riftlet，三步引导")
    }

    private func page(_ views: [NSView]) -> NSView {
        let value = SettingsNativeStyle.stack(views, spacing: 12)
        for view in views { view.widthAnchor.constraint(equalTo: value.widthAnchor).isActive = true }
        return value
    }

    private func section(_ title: String, symbol: String, views: [NSView]) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = SettingsNativeStyle.color(.accentInk)
        icon.setAccessibilityElement(false)
        let header = SettingsNativeStyle.stack([icon, SettingsNativeStyle.label(title, role: "heading"), NSView()],
                                             vertical: false, spacing: 8)
        let line = NSBox(); line.boxType = .separator
        let stack = SettingsNativeStyle.stack([line, header] + views, spacing: 5)
        for child in stack.arrangedSubviews where !(child is NSButton) {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func actionButton(_ title: String, id: String) -> NSButton {
        let value = SettingsNativeStyle.button(title)
        value.identifier = .init(id); value.target = self; value.action = #selector(actionPressed(_:))
        value.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        controls[id] = value
        return value
    }

    private func refreshFacts() {
        guard let snapshot else { return }
        let preservedFrame = hasPresented ? window.frame : nil
        defer { if let preservedFrame { layout(keeping: preservedFrame) } }
        let presentation = SetupPresentation(snapshot: snapshot.setup)
        if snapshot.setup.attachment == .available || snapshot.reviewEnvironment {
            introTitle.stringValue = "从一张截图开始"
            introDescription.stringValue = "照常按 ⇧⌘4 截图。将目标 ChatGPT 草稿留在 Chrome 前台，点一下屏幕边缘的微图即可附加。"
        } else {
            introTitle.stringValue = presentation.firstUseTitle
            introDescription.stringValue = presentation.firstUseDescription
        }
        introCapability.stringValue = snapshot.reviewEnvironment
            ? "当前为隔离审核：只演示本机流程，不连接浏览器或上传。"
            : presentation.firstUseCapability
        sourceDetail.stringValue = presentation.sourceText
        sourcePath.stringValue = presentation.sourcePath
        sourcePath.isHidden = !presentation.hasSourceLocation
        sourceAccess.isHidden = !presentation.needsSourceAccess
        sourceAccess.isEnabled = snapshot.capabilities.canChooseSource && presentation.needsSourceAccess
        automationDetail.stringValue = presentation.automationStatusText ?? "当前模式不需要 Chrome 自动化。"
        automation.title = presentation.permissionActionTitle
        automation.setAccessibilityLabel(automation.title)
        automation.isEnabled = snapshot.capabilities.canRequestAutomation && presentation.canRequestPermission
        automation.isHidden = snapshot.setup.permission == .notNeeded
        scriptDetail.stringValue = presentation.chromeScriptInstructions ?? ""
        chromeMenuSection.isHidden = presentation.chromeScriptInstructions == nil
        permissionHint.stringValue = snapshot.screenRecording == .granted
            ? "Riftlet 内置截图已获屏幕录制权限。"
            : "只用 ⇧⌘4 截图时，无需授予屏幕录制权限。"
        (controls["onboarding.recheck"] as? NSButton)?.isEnabled = snapshot.capabilities.canRecheck
        let settings = snapshot.state.owner.settings
        refreshDisplay()
        for (placement, button) in placements {
            button.state = settings.configuration.placement == placement ? .on : .off
            button.isEnabled = snapshot.capabilities.canEditPreferences
                && snapshot.state.domains[.placement]?.isSaving != true && !busy.contains(.placement)
            button.contentTintColor = button.state == .on ? SettingsNativeStyle.color(.accentInk) : SettingsNativeStyle.color(.ink)
        }
        placementPreview.configuration = settings.configuration
        placementPreview.entryEnabled = settings.entryEnabled
        placementHint.stringValue = settings.configuration.placement == nil
            ? "沿用之前的桌面位置。选择一个位置即可更改。"
            : ""
        placementHint.isHidden = placementHint.stringValue.isEmpty && !settings.displayRestoreAvailable
        if settings.displayRestoreAvailable {
            placementHint.stringValue += " 当前暂用可用显示器，已选屏幕的偏好仍保留。"
        }
        updateError(.display, label: displayError, retryID: "onboarding.retryDisplay", name: "显示器")
        updateError(.placement, label: placementError, retryID: "onboarding.retryPlacement", name: "位置")
        let ready = snapshot.setup.source == .accessible
            && (snapshot.setup.permission == .granted || snapshot.setup.permission == .notNeeded)
        if snapshot.reviewEnvironment {
            finishHint.stringValue = "完成后，可从菜单栏的 Riftlet 图标打开设置和截图历史。隔离审核不会连接浏览器或上传。"
        } else if snapshot.setup.issue == .chromeJavaScriptDisabled, let instructions = presentation.chromeScriptInstructions {
            finishHint.stringValue = "一键附加还差一步。" + instructions
        } else if ready && snapshot.setup.attachment == .available {
            finishHint.stringValue = "打开要用的 Chrome 聊天草稿，截一张图，再点屏幕边缘的微图。需要帮助时，从菜单栏打开 Riftlet 设置。"
        } else {
            finishHint.stringValue = "可以先开始。之后点菜单栏的 Riftlet 图标，打开“设置 → 权限与帮助”继续连接。"
        }
        if snapshot.state.owner.collectionPaused || snapshot.state.owner.isHidden {
            finishHint.stringValue += " 当前暂停和隐藏设置会保留。"
        }
    }

    private func updateError(_ domain: SettingsDomain, label: NSTextField, retryID: String, name: String) {
        guard let snapshot else { return }
        let state = snapshot.state.domains[domain]
        let failed = state?.hasIssue == true
        label.stringValue = failed ? "\(name)未能保存，仍保留原选择。可以重试这次选择。" : ""
        label.textColor = SettingsNativeStyle.color(.warning)
        label.isHidden = !failed
        let retry = controls[retryID] as? NSButton
        retry?.isHidden = state?.saveFailure == nil
        retry?.isEnabled = snapshot.capabilities.canEditPreferences && state?.pending != nil
            && state?.isSaving != true && !busy.contains(domain)
    }

    private func refreshDisplay() {
        guard let snapshot else { return }
        guard !displayMenuTracking else { displayRefreshPending = true; return }
        let settings = snapshot.state.owner.settings
        let preferred = settings.configuration.preferredDisplayID ?? settings.preferredDisplayID
        if displaySignature != settings.displays || representedPreferredDisplayID != preferred || display.numberOfItems == 0 {
            displaySignature = settings.displays; representedPreferredDisplayID = preferred
            display.removeAllItems()
            let primary = NSMenuItem(title: "使用主显示器", action: nil, keyEquivalent: "")
            primary.representedObject = NSNull(); display.menu?.addItem(primary)
            for screen in settings.displays {
                // addItem(withTitle:) deduplicates equal titles. Each physical
                // display instead gets its own native item and stable identity.
                let item = NSMenuItem(title: screen.name, action: nil, keyEquivalent: "")
                item.representedObject = NSNumber(value: screen.id)
                display.menu?.addItem(item)
            }
            if let preferred, !settings.displays.contains(where: { $0.id == preferred }) {
                let item = NSMenuItem(title: "已选显示器（未连接）", action: nil, keyEquivalent: "")
                item.representedObject = NSNumber(value: preferred); item.isEnabled = false
                display.menu?.addItem(item)
            }
        }
        if let item = display.itemArray.first(where: { item in
            if let preferred { return (item.representedObject as? NSNumber)?.uint32Value == preferred }
            return item.representedObject is NSNull
        }) { display.select(item) }
        display.isEnabled = snapshot.capabilities.canEditPreferences && !settings.displays.isEmpty
            && snapshot.state.domains[.display]?.isSaving != true && !busy.contains(.display)
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if menu === display.menu { displayMenuTracking = true }
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard menu === display.menu else { return }
        displayMenuTracking = false
        // Let the native picker action read the item that was actually chosen
        // before a queued background display-list refresh can replace it.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !displayMenuTracking, displayRefreshPending else { return }
            displayRefreshPending = false; refreshDisplay()
        }
    }

    private func refreshStep() {
        let preservedFrame = hasPresented ? window.frame : nil
        defer { if let preservedFrame { layout(keeping: preservedFrame) } }
        for (index, page) in pages.enumerated() { page.isHidden = index != currentStep }
        for view in progress.arrangedSubviews {
            guard let label = view as? NSTextField else { continue }
            let index = label.tag
            label.textColor = SettingsNativeStyle.color(index == currentStep ? .accentInk : .secondary)
            label.font = .systemFont(ofSize: 11, weight: index == currentStep ? .semibold : .regular)
        }
        progress.setAccessibilityLabel("第 \(currentStep + 1) 步，共 3 步")
        back.isHidden = currentStep == 0
        next.title = currentStep == 2 ? "开始使用" : "继续"
        next.setAccessibilityLabel(next.title)
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        window.recalculateKeyViewLoop()
    }

    @objc private func previousStep() { guard currentStep > 0 else { return }; currentStep -= 1; refreshStep() }
    @objc private func nextStep() {
        if currentStep < 2 { currentStep += 1; refreshStep(); return }
        guard !finishedThisPresentation else { return }
        finishedThisPresentation = true
        window.close()
        Task { await onAction(.finishOnboarding) }
    }
    @objc private func deferSetup() { window.performClose(nil) }

    @objc private func actionPressed(_ sender: NSButton) {
        guard sender.isEnabled, !sender.isHidden, let snapshot else { return }
        switch sender.identifier?.rawValue {
        case "onboarding.sourceAccess":
            guard snapshot.capabilities.canChooseSource else { return }; send(.chooseSourceAccess)
        case "onboarding.automation":
            guard snapshot.capabilities.canRequestAutomation else { return }; send(.requestAutomation)
        case "onboarding.recheck":
            guard snapshot.capabilities.canRecheck else { return }; send(.recheck)
        case "onboarding.retryDisplay": send(.settings(.retry(.display)), domain: .display)
        case "onboarding.retryPlacement": send(.settings(.retry(.placement)), domain: .placement)
        default: break
        }
    }

    @objc private func displayChanged() {
        guard display.isEnabled, snapshot?.capabilities.canEditPreferences == true,
              let item = display.selectedItem else { return }
        let target: UInt32?
        if item.representedObject is NSNull { target = nil }
        else if let number = item.representedObject as? NSNumber { target = number.uint32Value }
        else { return }
        send(.settings(.selectDisplay(target)), domain: .display)
    }

    @objc private func placementChanged(_ sender: NSButton) {
        guard sender.isEnabled, let placement = placements.first(where: { $0.value === sender })?.key else { return }
        send(.settings(.selectPlacement(placement)), domain: .placement)
    }

    private func send(_ action: SettingsProductAction, domain: SettingsDomain? = nil) {
        if let domain {
            guard !busy.contains(domain) else { refreshFacts(); return }
            busy.insert(domain); refreshFacts()
        }
        Task { [weak self] in
            guard let self else { return }
            await self.onAction(action)
            if let domain { self.busy.remove(domain); self.refreshFacts() }
        }
    }
}
