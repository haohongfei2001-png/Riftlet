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
                onOpenHistory: (() -> Void)? = nil) {
        self.onRecheck = onRecheck; self.onOpenSource = onOpenSource
        self.onPermission = onPermission; self.onDismiss = onDismiss
        self.onChooseSourceAccess = onChooseSourceAccess; self.onToggleHidden = onToggleHidden
        self.onToggleCollection = onToggleCollection; self.onOpenHistory = onOpenHistory
        setupWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 660),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        super.init()
        setupWindow.title = "Riftlet — 开始使用与运行状态"
        setupWindow.identifier = Self.windowIdentifier
        setupWindow.isReleasedWhenClosed = false
        setupWindow.minSize = NSSize(width: 560, height: 440)
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
    }

    /// Call only for first-run presentation or a deliberate menu action. The
    /// status model, background imports and permission updates never call this.
    public func show() {
        dismissPending = true
        setupWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Owner teardown does not count as a user dismissing first-use guidance.
    public func close() {
        silentClose = true
        setupWindow.close()
        dismissPending = false
        silentClose = false
    }

    public func windowWillClose(_ notification: Notification) {
        guard dismissPending, !silentClose else { return }
        dismissPending = false
        onDismiss()
    }

    private func configureContent() {
        guard let content = setupWindow.contentView else { return }
        let title = NSTextField(labelWithString: "截图一次，点击一次")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let introduction = NSTextField(wrappingLabelWithString:
            "日常仍使用 macOS 系统截图。这里查看收录、显示与当前附件能力；以后可从菜单栏重新打开。")
        introduction.textColor = .secondaryLabelColor
        let privacy = NSTextField(wrappingLabelWithString:
            "系统原截图不会因隐藏、移除或归档而删除。裂缝可能被系统截图拍入；需要时可先隐藏裂缝。正常成功没有弹窗或通知。")
        privacy.font = .systemFont(ofSize: 11); privacy.textColor = .secondaryLabelColor

        for field in [introduction, source, path, collection, rift, pending, attachment, permission, support, storage, issue, privacy] {
            field.font = field === privacy ? .systemFont(ofSize: 11) : .systemFont(ofSize: 12)
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.isSelectable = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        path.textColor = .secondaryLabelColor
        path.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        path.setAccessibilityLabel("本机系统截图保存位置")
        support.textColor = .secondaryLabelColor
        issue.textColor = .systemOrange

        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for view in [title, introduction, heading("截图来源"), source, path,
                     buttons([sourceButton, accessButton]), collection,
                     heading("显示与待核实记录"), rift, pending,
                     buttons([hideButton, pauseButton, historyButton]),
                     heading("当前附件能力"), attachment, permission, permissionButton, support,
                     heading("本机存储"), storage, issue, privacy] {
            stack.addArrangedSubview(view)
            if view is NSTextField {
                view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
            }
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.documentView = stack
        scroll.setAccessibilityLabel("Riftlet 首次使用与运行状态")
        content.addSubview(scroll)

        for button in [recheckButton, sourceButton, accessButton, permissionButton,
                       hideButton, pauseButton, historyButton, doneButton] {
            button.bezelStyle = .rounded; button.target = self
            button.setAccessibilityLabel(button.title)
        }
        recheckButton.identifier = .init("setup.recheck"); recheckButton.action = #selector(recheck)
        sourceButton.identifier = .init("setup.source"); sourceButton.action = #selector(openSource)
        accessButton.identifier = .init("setup.sourceAccess"); accessButton.action = #selector(chooseSourceAccess)
        permissionButton.identifier = .init("setup.permission"); permissionButton.action = #selector(requestPermission)
        hideButton.identifier = .init("setup.hide"); hideButton.action = #selector(toggleHidden)
        pauseButton.identifier = .init("setup.pause"); pauseButton.action = #selector(toggleCollection)
        historyButton.identifier = .init("setup.history"); historyButton.action = #selector(openHistory)
        doneButton.identifier = .init("setup.done"); doneButton.action = #selector(done)
        doneButton.keyEquivalent = "\r"
        let footer = buttons([recheckButton, doneButton])
        footer.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(footer)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
        setupWindow.initialFirstResponder = doneButton
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func buttons(_ controls: [NSButton]) -> NSStackView {
        let row = NSStackView(views: controls)
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
        return row
    }

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
