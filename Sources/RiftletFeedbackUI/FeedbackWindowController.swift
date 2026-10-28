import AppKit
import RiftletFeedback

@MainActor
public final class FeedbackWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let engine: FeedbackEngine?
    private let diagnostics: FeedbackDiagnostics
    private let appVersion: String
    private let demo: Bool
    private var draft = FeedbackDraft()
    private var loaded = false
    private var busy = false
    private var mayClose = false
    private var autosave: Task<Void,Never>?
    private var records: [FeedbackRecord] = []
    private let text = NSTextView()
    private let kind = NSPopUpButton()
    private let consent = NSButton(checkboxWithTitle: "附带最近的技术诊断（仅本次）", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "正在打开本地反馈草稿…")
    private let send = NSButton(title: "发送反馈", target: nil, action: nil)
    private let reports = NSPopUpButton()
    private var previewWindow: NSWindow?
    public var isVisible: Bool { window?.isVisible == true }
    public var diagnosticSelected: Bool { consent.state == .on }
    public var currentText: String { text.string }

    public init(engine: FeedbackEngine?, diagnostics: FeedbackDiagnostics, appVersion: String, demo: Bool = false) {
        self.engine = engine; self.diagnostics = diagnostics; self.appVersion = appVersion; self.demo = demo
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 560,height: 560), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.title = demo ? "反馈与建议 — 离线合成演示" : "反馈与建议"
        window.minSize = NSSize(width: 500,height: 520)
        super.init(window: window); window.delegate = self; window.isReleasedWhenClosed = false
        build()
        Task { await load() }
    }
    required init?(coder: NSCoder) { return nil }
    private func build() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor,constant: 20),stack.trailingAnchor.constraint(equalTo: content.trailingAnchor,constant: -20),stack.topAnchor.constraint(equalTo: content.topAnchor,constant: 20),stack.bottomAnchor.constraint(equalTo: content.bottomAnchor,constant: -20)])
        let heading = NSTextField(wrappingLabelWithString: "哪里不顺手？也欢迎告诉我你的想法。")
        heading.font = .systemFont(ofSize: 16, weight: .semibold); stack.addArrangedSubview(heading)
        kind.addItems(withTitles: ["遇到问题", "改进建议"]); kind.target = self; kind.action = #selector(changedKind)
        kind.setAccessibilityLabel("反馈类型"); stack.addArrangedSubview(kind)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.documentView = text; text.isRichText = false; text.importsGraphics = false
        text.isAutomaticQuoteSubstitutionEnabled = false; text.font = .systemFont(ofSize: 14)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 8,height: 8); text.delegate = self
        text.setAccessibilityLabel("发生了什么？你原本希望怎样？")
        stack.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        consent.target = self; consent.action = #selector(changedConsent); stack.addArrangedSubview(consent)
        let preview = NSButton(title: "查看将发送的诊断…", target: self, action: #selector(showPreview))
        stack.addArrangedSubview(preview)
        let privacy = NSTextField(wrappingLabelWithString: "仅发送你输入的文字及主动勾选的诊断，可供开发者和获授权的 AI 辅助分析。不会自动附带截图、聊天、剪贴板、完整路径或浏览器资料。文字中也请勿填写密码等秘密。")
        privacy.font = .systemFont(ofSize: 11); privacy.textColor = .secondaryLabelColor
        stack.addArrangedSubview(privacy); privacy.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.font = .systemFont(ofSize: 12); stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        send.target = self; send.action = #selector(submit)
        // No global Return binding: Return/IME composition always stays in editor.
        let close = NSButton(title: "保存并关闭",target: self,action: #selector(closeRequested))
        let actions = NSStackView(views:[close,send]); actions.spacing = 12; stack.addArrangedSubview(actions)
        reports.setAccessibilityLabel("已提交的本机反馈记录"); stack.addArrangedSubview(reports)
        let historyActions = NSStackView(views:[NSButton(title:"查看正文",target:self,action:#selector(showSaved)),NSButton(title:"刷新状态",target:self,action:#selector(refreshSelected)),NSButton(title:"取消待发送／申请删除",target:self,action:#selector(deleteSelected))])
        historyActions.spacing = 8; stack.addArrangedSubview(historyActions)
        stack.addArrangedSubview(NSButton(title:"移除已取消／已删除的本机正文…",target:self,action:#selector(forgetSelected)))
        controlsEnabled(false)
    }
    private func controlsEnabled(_ enabled: Bool) { text.isEditable = enabled; kind.isEnabled = enabled; consent.isEnabled = enabled; send.isEnabled = enabled }
    private func load() async {
        guard let engine else { loaded = true; controlsEnabled(true); status.stringValue = "反馈存储暂不可用。输入内容会留在此窗口，关闭前请复制保存。"; return }
        do {
            draft = try await engine.store.draft(); applyDraft(); loaded = true; controlsEnabled(true)
            status.stringValue = engine.configured ? "草稿保存在这台 Mac；关闭不会发送。" : "接收服务尚未配置。可保存待发送；当前不会上传。"
            await refreshRecords()
        } catch { loaded = true; controlsEnabled(true); failure() }
    }
    public func show() { window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeFirstResponder(text) }
    private func applyDraft() {
        text.string = draft.text; kind.selectItem(at: draft.kind == .problem ? 0 : 1)
        consent.state = draft.diagnostic == nil ? .off : .on
    }
    private func nextDraft() -> FeedbackDraft {
        draft.revision += 1; draft.text = text.string; draft.kind = kind.indexOfSelectedItem == 0 ? .problem : .suggestion
        return draft
    }
    public func textDidChange(_ notification: Notification) { saveEdited() }
    @objc private func changedKind() { saveEdited() }
    @objc private func changedConsent() {
        draft.diagnostic = consent.state == .on ? diagnostics.snapshot() : nil
        saveEdited()
    }
    private func saveEdited() {
        guard loaded,!busy else { return }
        let value = nextDraft()
        autosave?.cancel()
        autosave = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                try Task.checkCancellation()
                guard let engine else { throw FeedbackFailure.storageUnavailable }
                try await engine.store.saveDraft(value)
                if draft.revision == value.revision { status.stringValue = "草稿已保存在本机；没有发送。" }
            } catch is CancellationError { return } catch { if draft.revision == value.revision { failure() } }
        }
    }
    private func failure() { status.stringValue = "未能可靠保存或处理反馈；文字仍在这里。请保留窗口或复制正文，不会报告发送成功。" }
    public func saveBeforeClosing() async -> Bool {
        guard loaded,!busy else { return false }
        autosave?.cancel()
        guard let engine else { return text.string.isEmpty }
        let value = nextDraft()
        do {try await engine.store.saveDraft(value);return true} catch {failure();return false}
    }
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if mayClose { mayClose = false; return true }
        Task { if await saveBeforeClosing() { mayClose = true; close() } }
        return false
    }
    @objc private func closeRequested() { window?.performClose(nil) }
    @objc private func showPreview() {
        let value = (try? draft.diagnostic?.preview()) ?? "未附带诊断。勾选后会冻结当时的白名单快照；之后的新事件不会加入本次提交。"
        showText(value,title: "本次诊断预览")
    }
    private func showText(_ value: String,title: String) {
        let panel = NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:420),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        panel.title=title;panel.isReleasedWhenClosed=false
        let scroll=NSScrollView(frame:panel.contentView!.bounds);scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true
        let view=NSTextView(frame:scroll.bounds);view.isEditable=false;view.isRichText=false;view.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        view.string=value;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true
        scroll.documentView=view;panel.contentView?.addSubview(scroll);previewWindow=panel;panel.center();panel.makeKeyAndOrderFront(nil)
    }
    @objc private func submit() {
        guard loaded,!busy,let engine else {failure();return}
        guard !text.hasMarkedText() else {return}
        let value=nextDraft();busy=true;controlsEnabled(false)
        Task {
            do {
                let id=try await engine.enqueue(value,appVersion:appVersion)
                draft=try await engine.store.draft();applyDraft()
                status.stringValue = "已保存在本机，等待接收。编号 RF-\(id)"
                busy=false;controlsEnabled(true);await refreshRecords()
                await engine.pump();await refreshRecords()
            } catch {
                busy=false;controlsEnabled(true)
                switch error {
                case FeedbackFailure.invalidText:status.stringValue="请输入文字，最多 4,000 个 Unicode 字符且 16 KiB；原文仍在草稿中。"
                case FeedbackFailure.capacity:status.stringValue="待发送或本机记录已满；没有覆盖旧反馈，当前草稿保留。"
                case FeedbackFailure.secretUnavailable:status.stringValue="无法保存反馈访问凭证。请检查钥匙串；原文已保留为草稿。"
                default:failure()
                }
            }
        }
    }
    private func refreshRecords() async {
        guard let engine else {return}
        do {
            let selected=reports.selectedItem?.representedObject as? String
            records=try await engine.store.records();reports.removeAllItems()
            for record in records {
                reports.addItem(withTitle:"RF-\(record.id.prefix(8)) · \(demo ? "演示：" : "")\(record.label)")
                reports.lastItem?.representedObject=record.id
            }
            if let selected,let index=records.firstIndex(where:{$0.id==selected}){reports.selectItem(at:index)}
            if records.isEmpty{reports.addItem(withTitle:"尚无已提交反馈")}
        } catch {failure()}
    }
    private var selected: FeedbackRecord? {guard let id=reports.selectedItem?.representedObject as? String else{return nil};return records.first{$0.id==id}}
    @objc private func showSaved() {if let selected {showText(selected.envelope.text,title:"本机保存的反馈 RF-\(selected.id)")}}
    @objc private func refreshSelected() {
        guard let selected,let engine else{return}
        Task {do {if selected.state == .queued {await engine.pump()} else {try await engine.refresh(id:selected.id)};await refreshRecords()} catch {status.stringValue="服务暂不可用；本机正文和反馈编号保留。"}}
    }
    @objc private func forgetSelected() {
        guard let selected,let engine else{return}
        guard selected.state == .cancelled || selected.state == .deleted else {
            status.stringValue="先取消未发送反馈或等待服务确认删除，再移除本机正文。";return
        }
        let alert=NSAlert();alert.messageText="移除这条本机反馈正文？";alert.informativeText="这是本机内容删除，不改变其他反馈或任何截图。"
        alert.addButton(withTitle:"移除正文");alert.addButton(withTitle:"保留")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        Task {do {try await engine.store.forgetResolved(id:selected.id);await refreshRecords()}catch{failure()}}
    }
    @objc private func deleteSelected() {
        guard let selected,let engine else{return}
        let alert=NSAlert();alert.messageText="取消待发送或申请删除这条反馈？"
        alert.informativeText="尚未尝试发送的记录只取消本机投递。其余提交申请云端删除，私有维护副本可能需要维护者处理；不会把关闭 Issue 当成删除。本机正文暂时保留。"
        alert.addButton(withTitle:"申请删除");alert.addButton(withTitle:"保留")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        Task {do {try await engine.requestDeletion(id:selected.id);await refreshRecords()}catch{failure()}}
    }
}
