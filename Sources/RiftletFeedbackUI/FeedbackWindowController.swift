import AppKit
import RiftletFeedback
import RiftletUI

@MainActor
public final class FeedbackWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let engine: FeedbackEngine?
    private let diagnostics: FeedbackDiagnostics
    private let appVersion: String
    private let demo: Bool
    private var draft = FeedbackDraft()
    private var loaded = false
    private var busy = false
    private var autosave: Task<Void, Never>?
    private var records: [FeedbackRecord] = []
    private let text = NSTextView()
    private let kind = NSPopUpButton()
    private let consent = NSButton(checkboxWithTitle: "附带最近的技术诊断（仅本次）", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "正在打开本地反馈草稿…")
    private let send = NSButton(title: "发送反馈", target: nil, action: nil)
    private let reports = NSPopUpButton()
    private var previewWindow: NSWindow?
    private var loading: Task<Void, Never>?
    private let characterCount = NSTextField(labelWithString: "0 / 4,000 字符")
    private let recordsDisclosure = NSButton(title: "本机反馈记录 · 0", target: nil, action: nil)
    private let recordsBody = NSStackView()
    private var recordsExpanded = false
    private var hasPresented = false
    // Production always writes the same sidecar. Tests suspend this narrow seam
    // to verify that close cannot race text, kind or consent edits.
    var persistDraft: (@Sendable (FeedbackDraft) async throws -> Void)?
    var isEditingEnabled: Bool { text.isEditable && kind.isEnabled && consent.isEnabled }
    var statusText: String { status.stringValue }
    var draftForTesting: FeedbackDraft { draft }
    public var isVisible: Bool { window?.isVisible == true }
    public var diagnosticSelected: Bool { consent.state == .on }
    public var currentText: String { text.string }

    public init(engine: FeedbackEngine?, diagnostics: FeedbackDiagnostics, appVersion: String, demo: Bool = false) {
        self.engine = engine; self.diagnostics = diagnostics; self.appVersion = appVersion; self.demo = demo
        if let engine { persistDraft = { value in try await engine.store.saveDraft(value) } }
        let window = RiftVisualStyle.window(outerSize: NSSize(width: 600, height: 540),
            minimum: NSSize(width: 560, height: 500), title: demo ? "反馈与建议 — 离线合成演示" : "反馈与建议")
        super.init(window: window)
        window.delegate = self; window.isReleasedWhenClosed = false
        build()
        loading = Task { [weak self] in await self?.load() }
    }
    required init?(coder: NSCoder) { return nil }
    func waitUntilLoaded() async { await loading?.value }

    private func build() {
        guard let content = window?.contentView else { return }
        let stack = RiftVisualStyle.documentStack([], spacing: 12)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 16, right: 24)
        let scroller = RiftVisualStyle.topAlignedScrollView()
        scroller.documentView = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = RiftVisualStyle.label("哪里不顺手？", role: "title")
        let introduction = RiftVisualStyle.label("也欢迎告诉我，你希望它怎样工作。", role: "secondary")
        kind.addItems(withTitles: ["遇到问题", "改进建议"]); kind.target = self; kind.action = #selector(changedKind)
        kind.setAccessibilityLabel("反馈类型"); kind.font = RiftVisualStyle.bodyFont
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.documentView = text; scroll.backgroundColor = RiftVisualStyle.surface
        text.isRichText = false; text.importsGraphics = false; text.isAutomaticQuoteSubstitutionEnabled = false
        text.font = RiftVisualStyle.bodyFont; text.textColor = RiftVisualStyle.ink; text.backgroundColor = RiftVisualStyle.surface
        text.insertionPointColor = RiftVisualStyle.accent
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 12, height: 12); text.delegate = self
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
        text.defaultParagraphStyle = paragraph
        text.setAccessibilityLabel("发生了什么？你原本希望怎样？")
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        characterCount.font = RiftVisualStyle.secondaryFont; characterCount.textColor = RiftVisualStyle.secondary
        consent.target = self; consent.action = #selector(changedConsent); consent.font = RiftVisualStyle.bodyFont
        let preview = NSButton(title: "预览…", target: self, action: #selector(showPreview)); RiftVisualStyle.style(preview)
        let diagnosticsRow = NSStackView(views: [consent, preview]); diagnosticsRow.spacing = 8
        let privacy = RiftVisualStyle.label("你输入的文字及主动勾选的诊断会发送到开发者的私有反馈中心，可供开发者和获授权的 AI 辅助分析。不会自动附带截图、聊天、剪贴板、完整路径或浏览器资料。请勿填写密码等秘密。", role: "secondary")
        status.font = RiftVisualStyle.secondaryFont; status.textColor = RiftVisualStyle.secondary
        send.title = engine?.configured == true ? "发送反馈" : "保存待发送"
        send.target = self; send.action = #selector(submit); RiftVisualStyle.style(send, prominent: true)
        let close = NSButton(title: "保存并关闭", target: self, action: #selector(closeRequested)); RiftVisualStyle.style(close)
        // Neither button is the Return default: Return and IME stay in the editor.
        let actions = NSStackView(views: [close, send]); actions.spacing = 8
        let footer = RiftVisualStyle.vertical([status, actions], spacing: 12)
        reports.setAccessibilityLabel("已提交的本机反馈记录")
        recordsDisclosure.setButtonType(.onOff); recordsDisclosure.bezelStyle = .inline
        recordsDisclosure.font = RiftVisualStyle.bodyFont; recordsDisclosure.contentTintColor = RiftVisualStyle.ink
        recordsDisclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        recordsDisclosure.imagePosition = .imageLeading
        recordsDisclosure.target = self; recordsDisclosure.action = #selector(toggleRecords)
        recordsDisclosure.setAccessibilityLabel("展开本机反馈记录")
        recordsBody.orientation = .vertical; recordsBody.alignment = .leading; recordsBody.spacing = 8
        recordsBody.addArrangedSubview(reports)
        for (title, action) in [("查看正文", #selector(showSaved)), ("刷新状态", #selector(refreshSelected)),
                                ("取消待发送／申请删除", #selector(deleteSelected)), ("移除已取消／已删除的本机正文…", #selector(forgetSelected))] {
            let button = NSButton(title: title, target: self, action: action); RiftVisualStyle.style(button); recordsBody.addArrangedSubview(button)
        }
        recordsBody.isHidden = true
        for view in [heading, introduction, kind, scroll, characterCount, diagnosticsRow, privacy, recordsDisclosure, recordsBody] {
            stack.addArrangedSubview(view)
            if view !== kind && view !== recordsDisclosure { view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true }
        }
        for view in [scroller, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        status.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            scroller.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroller.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroller.topAnchor.constraint(equalTo: content.topAnchor), scroller.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            stack.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor), stack.leadingAnchor.constraint(equalTo: scroller.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scroller.contentView.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])
        controlsEnabled(false)
    }
    @objc private func toggleRecords() {
        // Reuse the same document and editor; folding never saves, submits,
        // rebuilds draft controls, or changes diagnostic consent.
        recordsExpanded.toggle(); recordsBody.isHidden = !recordsExpanded
        recordsDisclosure.state = recordsExpanded ? .on : .off
        recordsDisclosure.image = NSImage(systemSymbolName: recordsExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        recordsDisclosure.setAccessibilityLabel(recordsExpanded ? "收起本机反馈记录" : "展开本机反馈记录")
    }
    private func updateCharacterCount() {
        characterCount.stringValue = "\(text.string.count) / 4,000 字符"
        characterCount.textColor = text.string.count > 4_000 || text.string.utf8.count > 16 * 1024 ? .systemOrange : RiftVisualStyle.secondary
    }
    private func controlsEnabled(_ enabled: Bool) {
        text.isEditable = enabled; kind.isEnabled = enabled; consent.isEnabled = enabled; send.isEnabled = enabled
    }
    private func load() async {
        guard let engine else {
            loaded = true; controlsEnabled(true)
            status.stringValue = "反馈存储暂不可用。输入内容会留在此窗口，关闭前请复制保存。"
            return
        }
        do {
            draft = try await engine.store.draft(); applyDraft(); loaded = true; controlsEnabled(true)
            status.stringValue = engine.configured ? "草稿保存在这台 Mac；关闭不会发送。" : "接收服务尚未配置。可保存待发送；当前不会上传。"
            await refreshRecords()
        } catch { loaded = true; controlsEnabled(true); failure() }
    }
    public func show() {
        if let window {
            let size = hasPresented ? window.frame.size : NSSize(width: 600, height: 540)
            if !hasPresented { window.center() }
            RiftVisualStyle.restoreWindowSize(window, size: size, constrainOrigin: !hasPresented)
            showWindow(nil)
            RiftVisualStyle.restoreWindowSize(window, size: size, constrainOrigin: !hasPresented)
            hasPresented = true
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeFirstResponder(text)
        Task { await refreshRecords() }
    }
    private func applyDraft() {
        text.string = draft.text; kind.selectItem(at: draft.kind == .problem ? 0 : 1)
        consent.state = draft.diagnostic == nil ? .off : .on
        updateCharacterCount()
    }
    private func nextDraft() -> FeedbackDraft {
        draft.revision += 1; draft.text = text.string
        draft.kind = kind.indexOfSelectedItem == 0 ? .problem : .suggestion
        return draft
    }
    public func textDidChange(_ notification: Notification) { updateCharacterCount(); saveEdited() }
    @objc private func changedKind() { saveEdited() }
    @objc private func changedConsent() {
        guard loaded, !busy else { return }
        draft.diagnostic = consent.state == .on ? diagnostics.snapshot() : nil
        saveEdited()
    }
    private func saveEdited() {
        guard loaded, !busy else { return }
        let value = nextDraft(); autosave?.cancel()
        autosave = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                try Task.checkCancellation()
                guard let persistDraft else { throw FeedbackFailure.storageUnavailable }
                try await persistDraft(value)
                if draft.revision == value.revision { status.stringValue = "草稿已保存在本机；没有发送。" }
            } catch is CancellationError { return }
            catch { if draft.revision == value.revision { failure() } }
        }
    }
    private func failure() {
        status.stringValue = "未能可靠保存或处理反馈；文字仍在这里。请保留窗口或复制正文，不会报告发送成功。"
    }
    public func saveBeforeClosing(lockOnSuccess: Bool = false) async -> Bool {
        guard loaded, !busy, !text.hasMarkedText() else { return false }
        busy = true; controlsEnabled(false); autosave?.cancel()
        var saved = false
        defer {
            // App termination still awaits outbox stop and clean-exit persistence.
            // No new editing may enter between this save and the final quit reply.
            if !lockOnSuccess || !saved { busy = false; controlsEnabled(true) }
        }
        guard let persistDraft else { saved = text.string.isEmpty; return saved }
        let value = nextDraft()
        do { try await persistDraft(value); saved = true; return true }
        catch { failure(); return false }
    }
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // NSWindow.close() does NOT invoke windowShouldClose again. A reusable
        // "mayClose" flag would skip saving on a later reopening of the window.
        Task { if await saveBeforeClosing() { sender.close() } }
        return false
    }
    @objc private func closeRequested() { window?.performClose(nil) }
    @objc private func showPreview() {
        let value = (try? draft.diagnostic?.preview()) ?? "未附带诊断。勾选后会冻结当时的白名单快照；之后的新事件不会加入本次提交。"
        showText(value, title: "本次诊断预览")
    }
    private func showText(_ value: String, title: String) {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; panel.backgroundColor = RiftVisualStyle.window
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let view = NSTextView(frame: scroll.bounds); view.isEditable = false; view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular); view.string = value
        view.textColor = RiftVisualStyle.ink; view.backgroundColor = RiftVisualStyle.window
        view.textContainerInset = NSSize(width: 24, height: 24)
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        scroll.documentView = view; panel.contentView?.addSubview(scroll)
        previewWindow = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
    }
    @objc private func submit() { Task { await submitCurrentDraft() } }
    func submitCurrentDraft() async {
        guard loaded, !busy, let engine else { failure(); return }
        guard !text.hasMarkedText() else { return }
        let value = nextDraft(); busy = true; controlsEnabled(false); autosave?.cancel()
        do {
            let id = try await engine.enqueue(value, appVersion: appVersion)
            draft = FeedbackDraft(revision: value.revision + 1); applyDraft()
            status.stringValue = "已保存在本机，等待接收。编号 RF-\(id)"
            busy = false; controlsEnabled(true)
            await refreshRecords()
            await engine.pump(); await refreshRecords()
            if draft.revision == value.revision + 1, let record = records.first(where: { $0.id == id }) {
                status.stringValue = "\(demo ? "离线演示（非云端）：" : "")\(record.label)。编号 RF-\(id)"
            }
        } catch {
            busy = false; controlsEnabled(true)
            switch error {
            case FeedbackFailure.invalidText:
                status.stringValue = "请输入文字，最多 4,000 个 Unicode 字符且 16 KiB；原文仍在草稿中。"
            case FeedbackFailure.capacity:
                status.stringValue = "待发送或本机记录已满；没有覆盖旧反馈，当前草稿保留。"
            case FeedbackFailure.secretUnavailable:
                status.stringValue = "无法保存反馈访问凭证。请检查钥匙串；原文已保留为草稿。"
            default: failure()
            }
        }
    }
    private func refreshRecords() async {
        guard let engine else { return }
        do {
            let selected = reports.selectedItem?.representedObject as? String
            records = try await engine.store.records(); reports.removeAllItems()
            recordsDisclosure.title = "本机反馈记录 · \(records.count)"
            for record in records {
                reports.addItem(withTitle: "RF-\(record.id.prefix(8)) · \(demo ? "演示：" : "")\(record.label)")
                reports.lastItem?.representedObject = record.id
            }
            if let selected, let index = records.firstIndex(where: { $0.id == selected }) { reports.selectItem(at: index) }
            if records.isEmpty { reports.addItem(withTitle: "尚无已提交反馈") }
        } catch { failure() }
    }
    private var selected: FeedbackRecord? {
        guard let id = reports.selectedItem?.representedObject as? String else { return nil }
        return records.first { $0.id == id }
    }
    @objc private func showSaved() {
        if let selected { showText(selected.envelope.text, title: "本机保存的反馈 RF-\(selected.id)") }
    }
    @objc private func refreshSelected() {
        guard let selected, let engine else { return }
        Task {
            do {
                if selected.state == .queued || selected.state == .deletionQueued { await engine.pump() }
                else { try await engine.refresh(id: selected.id) }
                await refreshRecords()
            } catch { status.stringValue = "服务暂不可用；本机正文和反馈编号保留。" }
        }
    }
    @objc private func forgetSelected() {
        guard let selected, let engine else { return }
        guard selected.state == .cancelled || selected.state == .deleted else {
            status.stringValue = "先取消未发送反馈或等待服务确认删除，再移除本机正文。"; return
        }
        let alert = NSAlert(); alert.messageText = "移除这条本机反馈正文及访问凭证？"
        alert.informativeText = "删除这条已取消或已删除反馈的本机正文和钥匙串凭证；不改变其他反馈或任何截图。"
        alert.addButton(withTitle: "移除"); alert.addButton(withTitle: "保留")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { do { try await engine.forgetResolved(id: selected.id); await refreshRecords() } catch { failure() } }
    }
    @objc private func deleteSelected() {
        guard let selected, let engine else { return }
        let alert = NSAlert(); alert.messageText = "取消待发送或申请删除这条反馈？"
        alert.informativeText = "尚未尝试发送的记录只取消本机投递。其余提交申请云端删除，私有维护副本可能需要维护者处理；不会把关闭 Issue 当成删除。本机正文暂时保留。"
        alert.addButton(withTitle: "申请删除"); alert.addButton(withTitle: "保留")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { do { try await engine.requestDeletion(id: selected.id); await refreshRecords() } catch { failure() } }
    }
}
