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
    private let service = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "正在打开本地反馈草稿…")
    private let send = NSButton(title: "发送反馈", target: nil, action: nil)
    private let recoveryActions = NSStackView()
    private let retrySave = NSButton(title: "重试保存", target: nil, action: nil)
    private let copyText = NSButton(title: "复制正文", target: nil, action: nil)
    // This only selects the explicitly labelled recovery button's action. It
    // never schedules a later close after an unrelated edit or autosave.
    private var retryClosesWindow = false
    private var previewWindow: NSWindow?
    private var loading: Task<Void, Never>?
    private let characterCount = NSTextField(labelWithString: "0 / 4,000 字符")
    private let recordsDisclosure = NSButton(title: "本机反馈记录 · 0", target: nil, action: nil)
    private let recordsBody = NSStackView()
    private var recordsExpanded = false
    private var recordsRefreshGeneration: UInt64 = 0
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
        characterCount.identifier = NSUserInterfaceItemIdentifier("feedback.characterCount")
        characterCount.toolTip = "组合符号和 emoji 可能包含多个字符，按组成字符计数；发送限制与这里的计数一致。正文最多 16 KiB。"
        consent.target = self; consent.action = #selector(changedConsent); consent.font = RiftVisualStyle.bodyFont
        let preview = NSButton(title: "预览…", target: self, action: #selector(showPreview)); RiftVisualStyle.style(preview)
        let diagnosticsRow = NSStackView(views: [consent, preview]); diagnosticsRow.spacing = 8
        let privacy = RiftVisualStyle.label("反馈服务可用时，只有你提交的文字及主动勾选的诊断会发往开发者的私有反馈中心，可供开发者和获授权的 AI 辅助分析。不会自动附带截图、聊天、剪贴板、完整路径或浏览器资料。请勿填写密码等秘密。", role: "secondary")
        privacy.identifier = NSUserInterfaceItemIdentifier("feedback.privacy")
        service.font = RiftVisualStyle.secondaryFont; service.textColor = RiftVisualStyle.secondary
        service.identifier = NSUserInterfaceItemIdentifier("feedback.serviceCapability")
        if demo {
            service.stringValue = "离线合成演示；不会向云端发送反馈。"
        } else if engine == nil {
            service.stringValue = "本地反馈存储暂不可用；当前不会上传。"
        } else if engine?.configured == true {
            service.stringValue = "反馈服务已配置；只有提交后才投递，云端接收状态以对应记录为准。"
        } else {
            service.stringValue = "接收服务尚未配置。可保存待发送；当前不会上传。"
        }
        status.font = RiftVisualStyle.secondaryFont; status.textColor = RiftVisualStyle.secondary
        send.title = engine?.configured == true ? "发送反馈" : "保存待发送"
        send.target = self; send.action = #selector(submit); RiftVisualStyle.style(send, prominent: true)
        let close = NSButton(title: "保存并关闭", target: self, action: #selector(closeRequested)); RiftVisualStyle.style(close)
        retrySave.target = self; retrySave.action = #selector(retrySaveRequested)
        retrySave.identifier = NSUserInterfaceItemIdentifier("feedback.retrySave")
        copyText.target = self; copyText.action = #selector(copyTextRequested)
        copyText.identifier = NSUserInterfaceItemIdentifier("feedback.copyText")
        for button in [retrySave, copyText] { RiftVisualStyle.style(button); recoveryActions.addArrangedSubview(button) }
        recoveryActions.spacing = 8; recoveryActions.isHidden = true
        // Neither button is the Return default: Return and IME stay in the editor.
        let actions = NSStackView(views: [close, send]); actions.spacing = 8
        let footer = RiftVisualStyle.vertical([service, status, recoveryActions, actions], spacing: 8)
        recordsDisclosure.setButtonType(.onOff); recordsDisclosure.bezelStyle = .inline
        recordsDisclosure.identifier = NSUserInterfaceItemIdentifier("feedback.recordsDisclosure")
        recordsDisclosure.font = RiftVisualStyle.bodyFont; recordsDisclosure.contentTintColor = RiftVisualStyle.ink
        recordsDisclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        recordsDisclosure.imagePosition = .imageLeading
        recordsDisclosure.target = self; recordsDisclosure.action = #selector(toggleRecords)
        recordsDisclosure.setAccessibilityLabel("展开本机反馈记录")
        recordsBody.orientation = .vertical; recordsBody.alignment = .leading; recordsBody.spacing = 8
        rebuildRecords()
        recordsBody.isHidden = true
        for view in [heading, introduction, kind, scroll, characterCount, diagnosticsRow, privacy, recordsDisclosure, recordsBody] {
            stack.addArrangedSubview(view)
            if view !== kind && view !== recordsDisclosure { view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true }
        }
        for view in [scroller, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        for label in [service, status] { label.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true }
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
        characterCount.stringValue = "\(text.string.unicodeScalars.count) / 4,000 字符"
        let containsText = !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        characterCount.textColor = containsText && !submissionTextIsValid ? .systemOrange : RiftVisualStyle.secondary
        updateSendAvailability()
    }
    private var submissionTextIsValid: Bool {
        // Reuse the envelope's scalar/UTF-8/blank validation instead of keeping
        // a second UI admission rule. This creates no outbox record or receipt.
        (try? FeedbackEnvelope(draft: FeedbackDraft(text: text.string), appVersion: appVersion)) != nil
    }
    private func updateSendAvailability() {
        send.isEnabled = loaded && !busy && text.isEditable && engine != nil
            && submissionTextIsValid
        retrySave.isEnabled = loaded && !busy && text.isEditable && persistDraft != nil
        copyText.isEnabled = loaded && !busy && !text.string.isEmpty
    }
    private func controlsEnabled(_ enabled: Bool) {
        text.isEditable = enabled; kind.isEnabled = enabled; consent.isEnabled = enabled
        updateSendAvailability()
    }
    private func load() async {
        guard let engine else {
            loaded = true; controlsEnabled(true)
            draftSaveFailed(closeAttempt: false)
            return
        }
        do {
            draft = try await engine.store.draft(); applyDraft(); loaded = true; controlsEnabled(true)
            status.stringValue = "草稿保存在这台 Mac；关闭不会发送。"
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
        recoveryActions.isHidden = true; retryClosesWindow = false
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
                if draft.revision == value.revision { draftSaved() }
            } catch is CancellationError { return }
            catch { if draft.revision == value.revision { draftSaveFailed(closeAttempt: false) } }
        }
    }
    private func failure() {
        status.stringValue = "未能可靠保存或处理反馈；文字仍在这里。请保留窗口或复制正文，不会报告发送成功。"
    }
    private func draftSaved() {
        recoveryActions.isHidden = true; retryClosesWindow = false
        status.stringValue = "草稿已保存在本机；没有发送。"
    }
    private func draftSaveFailed(closeAttempt: Bool) {
        retryClosesWindow = closeAttempt
        retrySave.title = closeAttempt ? "重试保存并关闭" : "重试保存"
        retrySave.isHidden = persistDraft == nil
        recoveryActions.isHidden = false
        status.stringValue = persistDraft == nil
            ? "反馈存储暂不可用。文字仍在此窗口；关闭前请复制正文保存。"
            : "未能可靠保存草稿；文字仍在此窗口。可重试保存或复制正文，没有发送。"
        updateSendAvailability()
    }
    public func saveBeforeClosing(lockOnSuccess: Bool = false) async -> Bool {
        await saveCurrentDraft(lockOnSuccess: lockOnSuccess, closeAttempt: true)
    }
    private func saveCurrentDraft(lockOnSuccess: Bool, closeAttempt: Bool) async -> Bool {
        guard loaded else { status.stringValue = "正在打开本地草稿，请稍候再关闭。"; return false }
        guard !busy else { status.stringValue = "正在保存或处理反馈，请稍候再关闭。"; return false }
        guard !text.hasMarkedText() else {
            status.stringValue = "请先完成当前文字输入，再保存并关闭。"; return false
        }
        busy = true; controlsEnabled(false); autosave?.cancel()
        status.stringValue = closeAttempt ? "正在保存草稿；保存完成后才能关闭。" : "正在保存草稿；不会发送。"
        var saved = false
        defer {
            // App termination still awaits outbox stop and clean-exit persistence.
            // No new editing may enter between this save and the final quit reply.
            if !lockOnSuccess || !saved { busy = false; controlsEnabled(true) }
        }
        guard let persistDraft else {
            saved = text.string.isEmpty
            if !saved { draftSaveFailed(closeAttempt: closeAttempt) }
            return saved
        }
        let value = nextDraft()
        do { try await persistDraft(value); saved = true; draftSaved(); return true }
        catch { draftSaveFailed(closeAttempt: closeAttempt); return false }
    }
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // NSWindow.close() does NOT invoke windowShouldClose again. A reusable
        // "mayClose" flag would skip saving on a later reopening of the window.
        Task { if await saveBeforeClosing() { sender.close() } }
        return false
    }
    @objc private func closeRequested() { window?.performClose(nil) }
    @objc private func retrySaveRequested() {
        guard loaded, !busy else { return }
        if retryClosesWindow { window?.performClose(nil); return }
        Task { _ = await saveCurrentDraft(lockOnSuccess: false, closeAttempt: false) }
    }
    /// The caller supplies a private pasteboard in software tests. Production
    /// invokes this only from the explicit Copy Body button; no diagnostics,
    /// saved records or capability credentials are included.
    @discardableResult
    func copyDraftText(to pasteboard: NSPasteboard) -> Bool {
        guard loaded, !busy, !text.string.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text.string, forType: .string)
    }
    @objc private func copyTextRequested() {
        status.stringValue = copyDraftText(to: .general)
            ? "正文已复制；没有发送或关闭反馈。"
            : "无法复制正文，请选择文字后手动复制。"
    }
    @objc private func showPreview() {
        let value = (try? draft.diagnostic?.preview()) ?? "未附带诊断。勾选后会冻结当时的白名单快照；之后的新事件不会加入本次提交。"
        showText(value, title: "本次诊断预览", monospaced: true)
    }
    private func showText(_ value: String, title: String, monospaced: Bool = false) {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; panel.backgroundColor = RiftVisualStyle.window
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let view = NSTextView(frame: scroll.bounds); view.isEditable = false; view.isRichText = false
        view.font = monospaced ? .monospacedSystemFont(ofSize: 11, weight: .regular) : RiftVisualStyle.bodyFont
        view.string = value
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
    func refreshRecords() async {
        guard let engine else { return }
        recordsRefreshGeneration &+= 1
        let generation = recordsRefreshGeneration
        do {
            let latest = try await engine.store.records()
            guard generation == recordsRefreshGeneration else { return }
            records = latest
            recordsDisclosure.title = "本机反馈记录 · \(records.count)"
            rebuildRecords()
        } catch { failure() }
    }

    private func recordButton(_ title: String, record: FeedbackRecord, action: Selector) -> NSButton {
        let button = FeedbackRecordButton(title: title, recordID: record.id, target: self, action: action)
        RiftVisualStyle.style(button); button.font = RiftVisualStyle.secondaryFont; button.controlSize = .small
        button.setAccessibilityLabel("\(title)，反馈 RF-\(record.id.prefix(8))")
        return button
    }
    private func rebuildRecords() {
        // Replace only this folded region. The editor, first responder, marked
        // text, selection and draft controls stay alive during every refresh.
        for view in recordsBody.arrangedSubviews { recordsBody.removeArrangedSubview(view); view.removeFromSuperview() }
        if records.isEmpty {
            let empty = RiftVisualStyle.label("尚无已提交反馈。保存草稿不会生成待发送记录。", role: "secondary")
            recordsBody.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: recordsBody.widthAnchor).isActive = true
            return
        }
        for record in records {
            let identifier = RiftVisualStyle.label("RF-\(record.id.prefix(8))", role: "heading")
            identifier.toolTip = "RF-\(record.id)"
            let state = RiftVisualStyle.label("\(demo ? "离线演示（非云端）：" : "")\(record.label)", role: "secondary")
            state.identifier = NSUserInterfaceItemIdentifier("feedback.record.status.\(record.id)")
            let body = FeedbackRecordBodyView(text: record.envelope.text, recordID: record.id)
            let actions = NSStackView(views: [recordButton("查看完整正文", record: record, action: #selector(showSaved(_:)))])
            actions.spacing = 8; actions.alignment = .centerY
            if record.state != .cancelled && record.state != .deleted {
                actions.addArrangedSubview(recordButton("刷新状态", record: record, action: #selector(refreshRecord(_:))))
            }
            switch record.state {
            case .cancelled, .deleted:
                actions.addArrangedSubview(recordButton("移除本机正文与凭证…", record: record, action: #selector(forgetRecord(_:))))
            case .deletionQueued, .deletionPending:
                actions.addArrangedSubview(RiftVisualStyle.label("等待删除确认", role: "secondary"))
            default:
                let canCancelLocally = record.attempts == 0 && [.queued, .blocked, .deletionBlocked].contains(record.state)
                let title = canCancelLocally ? "取消待发送" : record.state == .deletionBlocked ? "重新申请删除" : "申请删除"
                actions.addArrangedSubview(recordButton(title, record: record, action: #selector(deleteRecord(_:))))
            }
            let card = RiftVisualStyle.card([identifier, state, body, actions])
            card.identifier = NSUserInterfaceItemIdentifier("feedback.record.\(record.id)")
            recordsBody.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: recordsBody.widthAnchor).isActive = true
            if let content = body.superview { body.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        }
    }
    private func record(for sender: FeedbackRecordButton) -> FeedbackRecord? { records.first { $0.id == sender.recordID } }
    @objc private func showSaved(_ sender: FeedbackRecordButton) {
        if let record = record(for: sender) { showText(record.envelope.text, title: "本机保存的反馈 RF-\(record.id)") }
    }
    @objc private func refreshRecord(_ sender: FeedbackRecordButton) {
        guard let record = record(for: sender), let engine else { return }
        Task {
            do {
                if record.state == .queued || record.state == .deletionQueued { await engine.pump() }
                else { try await engine.refresh(id: record.id) }
                await refreshRecords()
            } catch { status.stringValue = "服务暂不可用；本机正文和反馈编号保留。" }
        }
    }
    @objc private func forgetRecord(_ sender: FeedbackRecordButton) {
        guard let record = record(for: sender), let engine else { return }
        guard record.state == .cancelled || record.state == .deleted else {
            status.stringValue = "先取消未发送反馈或等待服务确认删除，再移除本机正文。"; return
        }
        confirmRecordAction(title: "移除这条本机反馈正文及访问凭证？",
            message: "只移除反馈 RF-\(record.id.prefix(8)) 的已取消或已确认删除的本机正文和钥匙串凭证。不改变其他反馈或任何截图。",
            button: "移除") { [weak self] in
                do { try await engine.forgetResolved(id: record.id); await self?.refreshRecords() }
                catch { self?.failure() }
            }
    }
    @objc private func deleteRecord(_ sender: FeedbackRecordButton) {
        guard let record = record(for: sender), let engine else { return }
        confirmRecordAction(title: sender.title == "取消待发送" ? "取消这条待发送反馈？" : "申请删除这条反馈？",
            message: "只处理反馈 RF-\(record.id.prefix(8))。确认时仍未尝试发送的记录仅取消本机投递；已尝试发送的记录会申请云端删除，包括需要维护者处理的私有维护副本。本机正文暂时保留，不改变其他反馈或任何截图。",
            button: sender.title) { [weak self] in
                do { try await engine.requestDeletion(id: record.id); await self?.refreshRecords() }
                catch { self?.failure() }
            }
    }
    private func confirmRecordAction(title: String, message: String, button: String,
                                     operation: @escaping @MainActor () async -> Void) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        let destructive = alert.addButton(withTitle: button)
        let keep = alert.addButton(withTitle: "保留")
        destructive.keyEquivalent = ""
        // Return/Enter invoke the default cell; Escape is a separate key
        // equivalent on that same non-destructive button. Neither may confirm.
        alert.layout()
        alert.window.defaultButtonCell = keep.cell as? NSButtonCell
        keep.keyEquivalent = "\u{1b}"; keep.keyEquivalentModifierMask = []
        alert.window.initialFirstResponder = keep
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in await operation() }
        }
    }
}

@MainActor
private final class FeedbackRecordButton: NSButton {
    let recordID: String
    init(title: String, recordID: String, target: AnyObject, action: Selector) {
        self.recordID = recordID
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
    }
    required init?(coder: NSCoder) { nil }
}
