import AppKit

/// The lightweight, explicitly opened first-use/status surface. This class has
/// no upload, Automation, file mutation or browser capability. Host callbacks
/// own permission checks and all persistence. Refresh never orders a window.
@MainActor
public final class RiftSetupController: NSObject, NSWindowDelegate {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("RiftletSetup")
    private let setupWindow: NSWindow
    private let onRecheck: () -> Void
    private let onOpenSource: () -> Void
    private let onPermission: () -> Void
    private let onDismiss: () -> Void
    private let onChooseSourceAccess: (() -> Void)?
    private let onToggleHidden: (() -> Void)?
    private let onToggleCollection: (() -> Void)?
    private let onOpenHistory: (() -> Void)?
    private var dismissPending = false
    private var silentClose = false
    private var onboardingStep: Int?
    private var hasPresented = false
    private var settingsSize = NSSize(width: 680, height: 520)
    private var onboardingSize = NSSize(width: 560, height: 520)
    private var settingsSection = 0
    private let pageHost = NSView()
    private let navigation = NSStackView()
    private let progress = NSTextField(labelWithString: "")
    private let backButton = NSButton(title: "上一步", target: nil, action: nil)
    private let laterButton = NSButton(title: "稍后设置", target: nil, action: nil)
    private let nextButton = NSButton(title: "继续", target: nil, action: nil)
    private let footer = NSStackView()
    private var sidebarWidth: NSLayoutConstraint?
    private var contentLeading: NSLayoutConstraint?
    private let onOpenEntrySettings: (() -> Void)?
    private let onOpenDisplaySettings: (() -> Void)?
    private let onOpenFeedback: (() -> Void)?
    private let onSettingsChange: ((RiftSettingsChange) throws -> RiftSettingsSnapshot)?
    private lazy var settingsForm = RiftSettingsForm { [weak self] change in
        guard let self, let save = self.onSettingsChange else { throw CocoaError(.fileWriteUnknown) }
        return try save(change)
    }

    private let source = NSTextField(wrappingLabelWithString: "")
    private let path = NSTextField(wrappingLabelWithString: "")
    private let collection = NSTextField(wrappingLabelWithString: "")
    private let rift = NSTextField(wrappingLabelWithString: "")
    private let pending = NSTextField(wrappingLabelWithString: "")
    private let attachment = NSTextField(wrappingLabelWithString: "")
    private let permission = NSTextField(wrappingLabelWithString: "")
    private let support = NSTextField(wrappingLabelWithString: "")
    private let storage = NSTextField(wrappingLabelWithString: "")
    private let issue = NSTextField(wrappingLabelWithString: "")
    private let firstUseDescription = RiftVisualStyle.label("")
    private let firstUseFlow = RiftVisualStyle.label("", role: "heading")
    private let firstUseNextStep = RiftVisualStyle.label("")
    private let recheckButton = NSButton(title: "重新检查", target: nil, action: nil)
    private let sourceButton = NSButton(title: "查看截图位置", target: nil, action: nil)
    private let accessButton = NSButton(title: "允许访问截图位置…", target: nil, action: nil)
    private let permissionButton = NSButton(title: "检查 Chrome 权限…", target: nil, action: nil)
    private let hideButton = NSButton(title: "隐藏裂缝", target: nil, action: nil)
    private let pauseButton = NSButton(title: "暂停收录", target: nil, action: nil)
    private let historyButton = NSButton(title: "内部历史", target: nil, action: nil)
    private let doneButton = NSButton(title: "完成", target: nil, action: nil)
    public private(set) var presentation = SetupPresentation(snapshot: .init())
    public var isVisible: Bool { setupWindow.isVisible }

    public init(onRecheck: @escaping () -> Void, onOpenSource: @escaping () -> Void,
                onPermission: @escaping () -> Void, onDismiss: @escaping () -> Void,
                onChooseSourceAccess: (() -> Void)? = nil,
                onToggleHidden: (() -> Void)? = nil, onToggleCollection: (() -> Void)? = nil,
                onOpenHistory: (() -> Void)? = nil,
                onOpenEntrySettings: (() -> Void)? = nil, onOpenDisplaySettings: (() -> Void)? = nil,
                onOpenFeedback: (() -> Void)? = nil,
                onSettingsChange: ((RiftSettingsChange) throws -> RiftSettingsSnapshot)? = nil) {
        self.onRecheck = onRecheck; self.onOpenSource = onOpenSource
        self.onPermission = onPermission; self.onDismiss = onDismiss
        self.onChooseSourceAccess = onChooseSourceAccess; self.onToggleHidden = onToggleHidden
        self.onToggleCollection = onToggleCollection; self.onOpenHistory = onOpenHistory
        self.onOpenEntrySettings = onOpenEntrySettings; self.onOpenDisplaySettings = onOpenDisplaySettings
        self.onOpenFeedback = onOpenFeedback; self.onSettingsChange = onSettingsChange
        setupWindow = RiftVisualStyle.window(outerSize: NSSize(width: 680, height: 520),
            minimum: NSSize(width: 620, height: 480), title: "Riftlet — 设置与运行状态")
        super.init()
        setupWindow.title = "Riftlet — 设置与运行状态"
        setupWindow.identifier = Self.windowIdentifier
        setupWindow.isReleasedWhenClosed = false
        setupWindow.minSize = NSSize(width: 620, height: 480)
        setupWindow.animationBehavior = .none
        setupWindow.delegate = self
        configureContent()
        update(snapshot: .init())
        setupWindow.center()
    }

    public func update(snapshot: SetupSnapshot) {
        presentation = SetupPresentation(snapshot: snapshot)
        source.stringValue = presentation.sourceText
        path.stringValue = presentation.sourcePath
        collection.stringValue = presentation.collectionText
        rift.stringValue = presentation.riftText
        pending.stringValue = presentation.pendingText ?? ""
        pending.isHidden = presentation.pendingText == nil
        attachment.stringValue = presentation.attachmentText
        permission.stringValue = presentation.permissionText ?? ""
        permission.isHidden = presentation.permissionText == nil
        support.stringValue = presentation.supportText
        storage.stringValue = presentation.storageText
        issue.stringValue = presentation.issueText ?? ""
        issue.isHidden = presentation.issueText == nil
        firstUseDescription.stringValue = presentation.firstUseDescription
        firstUseFlow.stringValue = presentation.firstUseFlow
        firstUseNextStep.stringValue = presentation.firstUseNextStep
        sourceButton.isEnabled = presentation.hasSourceLocation
        accessButton.isHidden = onChooseSourceAccess == nil
        accessButton.isEnabled = presentation.hasSourceLocation && onChooseSourceAccess != nil && !snapshot.isChecking
        recheckButton.title = snapshot.isChecking ? "正在检查…" : "重新检查"
        recheckButton.isEnabled = !snapshot.isChecking
        permissionButton.title = presentation.permissionActionTitle
        permissionButton.isEnabled = presentation.canRequestPermission && !snapshot.isChecking
        permissionButton.isHidden = presentation.permissionText == nil
        hideButton.title = presentation.hideActionTitle; hideButton.isEnabled = onToggleHidden != nil
        pauseButton.title = presentation.collectionActionTitle
        pauseButton.isEnabled = onToggleCollection != nil && !snapshot.isChecking
        recheckButton.setAccessibilityLabel(recheckButton.title)
        permissionButton.setAccessibilityLabel(permissionButton.title)
        hideButton.setAccessibilityLabel(hideButton.title)
        pauseButton.setAccessibilityLabel(pauseButton.title)
        historyButton.isEnabled = onOpenHistory != nil
        for field in [source, path, collection, rift, pending, attachment, permission, support, storage, issue,
                      firstUseDescription, firstUseFlow, firstUseNextStep] {
            RiftVisualStyle.applyTextStyle(field)
        }
    }

    /// Refresh local preference controls without presenting a window or saving.
    public func updateSettings(_ snapshot: RiftSettingsSnapshot) {
        settingsForm.update(snapshot, enabled: onSettingsChange != nil && !presentation.snapshot.isChecking)
    }

    /// Present only for a deliberate menu action, never a background update.
    public func show(section: RiftSettingsSection? = nil) {
        if let section { settingsSection = section.rawValue }
        rememberSize()
        onboardingStep = nil
        setupWindow.minSize = NSSize(width: 620, height: 480)
        rebuildPage()
        present(size: settingsSize)
    }

    /// Host calls this only at its existing first-use presentation boundary.
    public func showOnboarding() {
        rememberSize()
        onboardingStep = 0
        setupWindow.minSize = NSSize(width: 520, height: 480)
        rebuildPage()
        present(size: onboardingSize)
    }

    private func rememberSize() {
        guard hasPresented else { return }
        if onboardingStep == nil { settingsSize = setupWindow.frame.size }
        else { onboardingSize = setupWindow.frame.size }
    }

    private func present(size: NSSize) {
        dismissPending = true
        RiftVisualStyle.restoreWindowSize(setupWindow, size: size, constrainOrigin: !hasPresented)
        setupWindow.makeKeyAndOrderFront(nil)
        RiftVisualStyle.restoreWindowSize(setupWindow, size: size, constrainOrigin: !hasPresented)
        hasPresented = true
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Owner teardown does not count as a user dismissing first-use guidance.
    public func close() {
        settingsForm.stop()
        silentClose = true
        setupWindow.close()
        dismissPending = false
        silentClose = false
    }

    public func windowWillClose(_ notification: Notification) {
        settingsForm.stop()
        guard dismissPending, !silentClose else { return }
        dismissPending = false
        onDismiss()
    }

    private func configureContent() {
        guard let content = setupWindow.contentView else { return }
        for field in [source, path, collection, rift, pending, attachment, permission, support, storage, issue] {
            field.font = RiftVisualStyle.bodyFont; field.textColor = RiftVisualStyle.ink
            field.maximumNumberOfLines = 0; field.lineBreakMode = .byWordWrapping; field.isSelectable = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        path.font = .monospacedSystemFont(ofSize: 11, weight: .regular); path.textColor = RiftVisualStyle.secondary
        path.setAccessibilityLabel("本机系统截图保存位置")
        support.font = RiftVisualStyle.secondaryFont; support.textColor = RiftVisualStyle.secondary
        issue.textColor = .systemOrange
        let controls: [(NSButton, String, Selector)] = [
            (recheckButton, "recheck", #selector(recheck)), (sourceButton, "source", #selector(openSource)),
            (accessButton, "sourceAccess", #selector(chooseSourceAccess)), (permissionButton, "permission", #selector(requestPermission)),
            (hideButton, "hide", #selector(toggleHidden)), (pauseButton, "pause", #selector(toggleCollection)),
            (historyButton, "history", #selector(openHistory)), (doneButton, "done", #selector(done)),
            (backButton, "back", #selector(previousStep)), (laterButton, "later", #selector(done)),
            (nextButton, "next", #selector(nextStep))]
        for (button, id, action) in controls {
            RiftVisualStyle.style(button, prominent: button === doneButton || button === nextButton)
            button.target = self; button.action = action; button.identifier = .init("setup." + id)
            button.setAccessibilityLabel(button.title)
        }
        doneButton.keyEquivalent = "\r"
        navigation.orientation = .vertical; navigation.alignment = .leading; navigation.spacing = 4
        let product = RiftVisualStyle.label("Riftlet", role: "heading")
        navigation.addArrangedSubview(product)
        navigation.setCustomSpacing(24, after: product)
        let symbols = ["slider.horizontal.3", "camera", "display", "lock.shield", "info.circle"]
        for (i, title) in ["运行状态", "截图入口", "显示与动效", "隐私与存储", "关于与支持"].enumerated() {
            let button = RiftSidebarButton(title: title, target: self, action: #selector(selectSection(_:)))
            button.tag = i; button.symbolName = symbols[i]; button.font = RiftVisualStyle.bodyFont
            button.alignment = .left; button.setButtonType(.pushOnPushOff)
            button.widthAnchor.constraint(equalToConstant: 132).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            navigation.addArrangedSubview(button)
        }
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow
        sidebar.addSubview(navigation); navigation.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            navigation.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24)])
        progress.font = RiftVisualStyle.secondaryFont; progress.textColor = RiftVisualStyle.secondary
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 8
        for view in [sidebar, progress, pageHost, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 156)
        contentLeading = pageHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 24)
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor), sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor), sidebarWidth!,
            progress.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor), progress.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            pageHost.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 12), contentLeading!,
            pageHost.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            pageHost.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])
        rebuildPage()
        setupWindow.initialFirstResponder = doneButton
    }

    private func rebuildPage() {
        settingsForm.stop()
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        footer.arrangedSubviews.forEach { footer.removeArrangedSubview($0); $0.removeFromSuperview() }
        let safetyNote = RiftVisualStyle.label("不发送消息，不删除原截图。", role: "secondary")
        safetyNote.identifier = .init("setup.safetyNote")
        safetyNote.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let footerSpace = NSView()
        footerSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerSpace.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(safetyNote); footer.addArrangedSubview(footerSpace)
        navigation.superview?.isHidden = onboardingStep != nil
        sidebarWidth?.constant = onboardingStep == nil ? 156 : 0
        progress.stringValue = onboardingStep.map { "认识 Riftlet  ·  连接与权限  ·  开始使用    \($0 + 1) / 3" } ?? "内部候选"
        setupWindow.title = onboardingStep == nil ? "Riftlet — 设置与运行状态" : "Riftlet — 开始使用 · 内部候选"
        var views: [NSView] = []
        let sourceCard = { [self] in RiftVisualStyle.card([RiftVisualStyle.label("系统截图位置", role: "heading"), source, path, buttons([sourceButton, accessButton])]) }
        let chromeCard = { [self] in RiftVisualStyle.card([RiftVisualStyle.label("当前 ChatGPT 草稿", role: "heading"), attachment, permission, permissionButton]) }
        if let step = onboardingStep {
            if step == 0 {
                views = [RiftVisualStyle.label("截图一次，点击一次", role: "title"),
                    firstUseDescription, RiftFirstUseIllustration(frame: .zero),
                    RiftVisualStyle.vertical([RiftVisualStyle.label("沿用 macOS 系统截图习惯"),
                        RiftVisualStyle.label("只附加图片，不发送消息"),
                        RiftVisualStyle.label("原图与本地历史始终保留")], spacing: 8)]
            } else if step == 1 {
                views = [RiftVisualStyle.label("连接你已经在用的工具", role: "title"),
                    RiftVisualStyle.label("允许访问不等于目标已经验证；也可稍后设置，继续本地收录。", role: "secondary"), sourceCard(), chromeCard()]
            } else {
                views = [RiftVisualStyle.label("下一张截图，从这里开始", role: "title"),
                    firstUseFlow, firstUseNextStep, attachment, support]
            }
            backButton.isHidden = step == 0; nextButton.title = step == 2 ? "开始使用" : step == 0 ? "继续" : "下一步"
            nextButton.setAccessibilityLabel(nextButton.title)
            nextButton.keyEquivalent = "\r"; doneButton.keyEquivalent = ""
            [laterButton, backButton, nextButton].forEach { footer.addArrangedSubview($0) }
        } else {
            nextButton.keyEquivalent = ""; doneButton.keyEquivalent = "\r"
            for button in navigation.arrangedSubviews.compactMap({ $0 as? NSButton }) {
                button.state = button.tag == settingsSection ? .on : .off
                button.contentTintColor = button.tag == settingsSection ? RiftVisualStyle.accent : RiftVisualStyle.ink
            }
            switch settingsSection {
            case 1:
                views = [RiftVisualStyle.label("截图入口", role: "title")]
                    + settingsForm.content(for: .captureEntry) + [sourceCard()]
            case 2:
                views = [RiftVisualStyle.label("显示与动效", role: "title")]
                    + settingsForm.content(for: .display)
                    + [RiftVisualStyle.label("减少动态、减少透明度与提高对比度遵循 macOS 设置。", role: "secondary")]
            case 3:
                views = [RiftVisualStyle.label("隐私与存储", role: "title")]
                    + settingsForm.content(for: .privacy)
                    + [RiftVisualStyle.card([RiftVisualStyle.label("本机存储", role: "heading"), storage, pending]),
                       RiftVisualStyle.label("用量是逻辑文件大小，不代表可释放空间；不会自动清理原图。", role: "secondary")]
            case 4:
                views = [RiftVisualStyle.label("关于 Riftlet", role: "title"),
                    firstUseDescription,
                    RiftVisualStyle.card([RiftVisualStyle.label("内部候选 · 薄界", role: "heading"), support]),
                    actionButton("反馈与建议…", action: #selector(openFeedback), available: onOpenFeedback != nil)]
            default:
                views = [RiftVisualStyle.label("运行状态", role: "title"),
                    RiftVisualStyle.card([collection, rift, pending, buttons([hideButton, pauseButton, historyButton])]),
                    RiftVisualStyle.card([source, path, buttons([sourceButton, accessButton]), attachment, permission, permissionButton])]
            }
            [recheckButton, doneButton].forEach { footer.addArrangedSubview($0) }
        }
        // Current blockers stay visible on every page, without changing focus.
        views.insert(issue, at: min(1, views.count))
        let stack = RiftVisualStyle.documentStack(views, spacing: 16)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in views where !(view is NSButton) { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        let scroll = RiftVisualStyle.topAlignedScrollView()
        // Keep the settings column stable while document height and status
        // labels settle. Legacy scrollers retain their native gutter; overlay
        // scrollers still hide automatically and keep the user's chosen style.
        scroll.autohidesScrollers = false
        scroll.documentView = stack; scroll.translatesAutoresizingMaskIntoConstraints = false; pageHost.addSubview(scroll)
        scroll.setAccessibilityLabel("Riftlet 首次使用与运行状态")
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor), scroll.topAnchor.constraint(equalTo: pageHost.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor), stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor)])
    }
    private func actionButton(_ title: String, action: Selector, available: Bool) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); RiftVisualStyle.style(button); button.isEnabled = available; return button
    }
    private func buttons(_ controls: [NSButton]) -> NSStackView {
        let row = NSStackView(views: controls); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8; return row
    }
    @objc private func selectSection(_ sender: NSButton) { settingsSection = sender.tag; rebuildPage() }
    @objc private func previousStep() { guard let step = onboardingStep, step > 0 else { return }; onboardingStep = step - 1; rebuildPage() }
    @objc private func nextStep() { guard let step = onboardingStep else { return }; if step == 2 { done() } else { onboardingStep = step + 1; rebuildPage() } }
    @objc private func openEntry() { onOpenEntrySettings?() }
    @objc private func openDisplay() { onOpenDisplaySettings?() }
    @objc private func openFeedback() { onOpenFeedback?() }

    @objc private func recheck() { guard !presentation.snapshot.isChecking else { return }; onRecheck() }
    @objc private func openSource() { guard presentation.hasSourceLocation else { return }; onOpenSource() }
    @objc private func chooseSourceAccess() {
        guard presentation.hasSourceLocation, !presentation.snapshot.isChecking else { return }
        onChooseSourceAccess?()
    }
    @objc private func requestPermission() {
        guard presentation.canRequestPermission, !presentation.snapshot.isChecking else { return }
        onPermission()
    }
    @objc private func toggleHidden() { onToggleHidden?() }
    @objc private func toggleCollection() { guard !presentation.snapshot.isChecking else { return }; onToggleCollection?() }
    @objc private func openHistory() { onOpenHistory?() }
    @objc private func done() { setupWindow.performClose(nil) }
}
