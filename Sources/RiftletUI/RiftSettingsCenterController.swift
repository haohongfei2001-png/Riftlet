import AppKit
import RiftletCapture

/// One native settings window over the existing owner/model. Rendering cannot
/// persist preferences, request permission, start capture, or reopen the window.
@MainActor
public final class RiftSettingsCenterController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSMenuDelegate {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("RiftletSettingsCenter")
    public let window: NSWindow
    public var isVisible: Bool { window.isVisible }
    public private(set) var selectedPage: SettingsPage = .general

    let model: SettingsStateModel
    let onAction: SettingsProductActionHandler
    var product: SettingsProductSnapshot
    let scroll = RiftVisualStyle.topAlignedScrollView()
    let footerStatus = SettingsNativeStyle.label("", role: "secondary")
    var pages: [SettingsPage: NSStackView] = [:]
    var navigation: [SettingsPage: NSButton] = [:]
    var labels: [String: NSTextField] = [:]
    var controls: [String: NSControl] = [:]
    var numericFields: [SettingsField: NSTextField] = [:]
    var numericSliders: [SettingsField: NSSlider] = [:]
    var handlers: [ObjectIdentifier: () -> Void] = [:]
    var errorRows: [SettingsDomain: NSStackView] = [:]
    var errorLabels: [SettingsDomain: NSTextField] = [:]
    var retryButtons: [SettingsDomain: NSButton] = [:]
    var disclosures: [String: (button: NSButton, content: NSView)] = [:]
    var pageWidthConstraints: [SettingsPage: NSLayoutConstraint] = [:]
    var pagePositionConstraints: [NSLayoutConstraint] = []
    var displayItems: [RiftSettingsDisplay] = []
    var displaySelection: UInt32?
    var displayMenuTracking = false
    var displayRefreshPending = false
    var archiveCustom = false
    var archiveField: NSTextField!
    var archiveCustomRow: NSView!
    var legacyFieldRow: NSView!
    let geometryPreview = RiftSettingsCenterPreview(kind: .geometry)
    let arrivalPreview = RiftSettingsCenterPreview(kind: .arrival)
    let swallowPreview = RiftSettingsCenterPreview(kind: .swallow)
    private var allowClose = false
    private var hasPositioned = false
    private(set) var pendingCloseAlert: NSAlert?
    private var suspendedEditor: (field: NSTextField, selection: NSRange)?
    private var closingAfterApply = false

    public init(model: SettingsStateModel, onAction: @escaping SettingsProductActionHandler) {
        self.model = model; self.onAction = onAction
        product = SettingsProductSnapshot(revision: 0, setup: .init(), state: model.snapshot)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsNativeStyle.settingsSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.identifier = Self.windowIdentifier
        window.title = "Riftlet 设置"
        window.isReleasedWhenClosed = false
        window.minSize = SettingsNativeStyle.settingsMinimumSize
        window.delegate = self
        buildWindow()
        render()
    }

    /// The host is the only subscriber to model.onChange and projects all owners.
    public func update(_ snapshot: SettingsProductSnapshot) {
        guard snapshot.revision >= product.revision else { return }
        product = snapshot
        render()
    }

    public func show(page: SettingsPage = .general) {
        navigate(to: page)
        if !hasPositioned { window.center(); hasPositioned = true }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Host teardown is distinct from the user closing an edited form.
    public func closeForTeardown() {
        allowClose = true
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .abort) }
        pendingCloseAlert = nil
        suspendedEditor = nil
        stopPreviews(); window.close()
        allowClose = false
    }

    func buildWindow() {
        let root = SettingsSurfaceView(role: .window)
        let sidebar = SettingsSurfaceView(role: .sidebar)
        let content = NSView()
        let footer = SettingsSurfaceView(role: .window)
        window.contentView = root
        [sidebar, content, footer, scroll, footerStatus].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        root.addSubview(sidebar); root.addSubview(content)
        content.addSubview(scroll); content.addSubview(footer); footer.addSubview(footerStatus)
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        scroll.identifier = .init("settings.center.scroll")
        scroll.setAccessibilityLabel("设置页面")
        let brand = SettingsNativeStyle.label("Riftlet", role: "heading")
        let sidebarStack = SettingsNativeStyle.stack([brand], spacing: 7)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)
        for page in SettingsPage.allCases {
            let button = makeButton(page.title, id: "nav.\(page.rawValue)") { [weak self] in self?.navigate(to: page) }
            button.setButtonType(.toggle)
            button.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.bezelStyle = .regularSquare
            button.isBordered = false
            navigation[page] = button
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        }
        let note = SettingsNativeStyle.label("只附加图片\n不发送消息", role: "caption")
        note.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(note)
        let close = makeButton("关闭", id: "close") { [weak self] in self?.window.performClose(nil) }
        close.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(close)
        footerStatus.identifier = .init("settings.center.footerStatus")
        footerStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: SettingsNativeStyle.sidebarWidth),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 22),
            note.leadingAnchor.constraint(equalTo: sidebarStack.leadingAnchor), note.trailingAnchor.constraint(equalTo: sidebarStack.trailingAnchor),
            note.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -20),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor), content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor), footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 53),
            close.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -26), close.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            close.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            footerStatus.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 31),
            footerStatus.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -12),
            footerStatus.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        buildPages()
        mountPage(.general)
        window.initialFirstResponder = navigation[.general]
    }

    func navigate(to page: SettingsPage) {
        guard page != selectedPage || scroll.documentView == nil else { return }
        flushEditor()
        window.makeFirstResponder(nil)
        stopPreviews()
        selectedPage = page
        mountPage(page)
        render()
        window.recalculateKeyViewLoop()
    }

    func mountPage(_ page: SettingsPage) {
        guard let document = pages[page] else { return }
        NSLayoutConstraint.deactivate(pagePositionConstraints)
        NSLayoutConstraint.deactivate(Array(pageWidthConstraints.values))
        scroll.documentView = document
        pagePositionConstraints = [document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
                                   document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)]
        NSLayoutConstraint.activate(pagePositionConstraints)
        pageWidthConstraints[page]?.isActive = true
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        window.title = "Riftlet — \(page.title)"
    }

    func dispatch(_ action: SettingsProductAction) {
        // Native switches/pop-ups tentatively change themselves before invoking
        // their action. Immediately project actual owner state while awaiting it.
        render()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await onAction(action)
            // The host normally sends an update during the action. Rendering the
            // same controls again is harmless and also supports narrow test hosts.
            render()
        }
    }

    @objc func invoked(_ sender: NSControl) {
        guard sender.isEnabled else { return }
        handlers[ObjectIdentifier(sender)]?()
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        record(field)
        refreshDraftPresentation()
    }
    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        record(field)
        refreshDraftPresentation()
    }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText(),
              let field = control as? NSTextField else { return false }
        record(field)
        if field === archiveField { dispatch(.settings(.applyArchive)) }
        else if numericFields.values.contains(where: { $0 === field }) { dispatch(.settings(.applyLayout)) }
        else { return false }
        return true
    }

    func record(_ field: NSTextField) {
        let text = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        if field === archiveField {
            if model.archiveDraftText != text { model.setArchiveDraftText(text) }
        } else if let key = numericFields.first(where: { $0.value === field })?.key,
                  model.text(for: key) != text {
            model.setDraftText(text, for: key)
        }
    }
    func flushEditor() {
        for field in numericFields.values where field.currentEditor() != nil { record(field) }
        if archiveField?.currentEditor() != nil { record(archiveField) }
    }
    func stopPreviews() { arrivalPreview.stop(); swallowPreview.stop() }

    public func menuWillOpen(_ menu: NSMenu) {
        if menu === (controls["display"] as? NSPopUpButton)?.menu { displayMenuTracking = true }
    }
    public func menuDidClose(_ menu: NSMenu) {
        guard menu === (controls["display"] as? NSPopUpButton)?.menu else { return }
        displayMenuTracking = false
        // Native item action is delivered after tracking ends. Do not replace
        // its represented display identity before that action has been read.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !displayMenuTracking, displayRefreshPending else { return }
            displayRefreshPending = false; renderDisplay()
        }
    }

    var needsCloseConfirmation: Bool {
        let state = model.snapshot
        return model.hasLayoutDraft || model.hasArchiveDraft || [SettingsDomain.layout, .archive].contains {
            state.domains[$0]?.hasIssue == true || state.domains[$0]?.isSaving == true
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowClose { return true }
        flushEditor()
        guard needsCloseConfirmation else { stopPreviews(); return true }
        presentCloseConfirmation()
        return false
    }
    public func windowWillClose(_ notification: Notification) { stopPreviews() }

    func presentCloseConfirmation() {
        guard pendingCloseAlert == nil, window.attachedSheet == nil else { return }
        if let field = (Array(numericFields.values) + [archiveField].compactMap { $0 }).first(where: { $0.currentEditor() != nil }),
           let editor = field.currentEditor() as? NSTextView {
            suspendedEditor = (field, editor.selectedRange())
        }
        let alert = NSAlert()
        alert.messageText = "要保存更改后再关闭吗？"
        alert.informativeText = "位置、动效参数与归档时限还有未确认的更改。已生效的即时开关不受影响。"
        alert.alertStyle = .informational
        for (name, id) in [("继续编辑", "continue"), ("不保存", "discard"), ("应用并关闭", "apply")] {
            let button = alert.addButton(withTitle: name)
            button.identifier = .init("settings.center.close.\(id)")
            button.setAccessibilityLabel(name)
        }
        alert.buttons[0].keyEquivalent = "\u{1b}"
        alert.buttons[0].keyEquivalentModifierMask = []
        alert.window.defaultButtonCell = alert.buttons[0].cell as? NSButtonCell
        pendingCloseAlert = alert
        refreshCloseButtons()
        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                pendingCloseAlert = nil
                if response == .alertSecondButtonReturn {
                    await onAction(.settings(.discardDrafts))
                    render()
                    if !needsCloseConfirmation { finishUserClose() }
                } else if response == .alertThirdButtonReturn {
                    guard !closingAfterApply else { return }
                    closingAfterApply = true
                    await onAction(.settings(.applyDrafts))
                    closingAfterApply = false
                    render()
                    if !needsCloseConfirmation { finishUserClose() }
                } else { restoreEditor() }
            }
        }
    }
    func refreshCloseButtons() {
        guard let alert = pendingCloseAlert else { return }
        let busy = [SettingsDomain.layout, .archive].contains { model.snapshot.domains[$0]?.isSaving == true }
        alert.buttons[1].isEnabled = !busy
        alert.buttons[2].isEnabled = !busy && product.capabilities.canEditPreferences
        alert.informativeText = busy
            ? "正在保存已有更改。请继续编辑或等待保存结束；关闭窗口不会取消已经开始的写入。"
            : "位置、动效参数与归档时限还有未确认的更改。已生效的即时开关不受影响。"
    }
    private func restoreEditor() {
        guard let context = suspendedEditor else { return }
        suspendedEditor = nil
        guard context.field.window === window, !context.field.isHiddenOrHasHiddenAncestor else { return }
        window.makeFirstResponder(context.field)
        if let editor = context.field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
            let count = (editor.string as NSString).length
            let start = min(context.selection.location, count)
            editor.setSelectedRange(NSRange(location: start, length: min(context.selection.length, count - start)))
        }
    }
    private func finishUserClose() {
        suspendedEditor = nil
        allowClose = true; stopPreviews(); window.close(); allowClose = false
    }

}
