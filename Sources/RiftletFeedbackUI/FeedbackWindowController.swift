import AppKit
import RiftletFeedback
import RiftletUI

@MainActor
public final class FeedbackWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let engine: FeedbackEngine?
    private let diagnostics: FeedbackDiagnostics
    private let appVersion: String
    private let copy: ProductCopy
    private let demo: Bool
    private var draft = FeedbackDraft()
    // A fresh editor has no changes. Loading and successful storage operations
    // replace this baseline, including the consent snapshot and feedback kind.
    private var cleanDraft: FeedbackDraft? = FeedbackDraft()
    private var loaded = false
    private var draftReadFailed = false
    private var busy = false
    private var autosave: Task<Void, Never>?
    private var autosaveWriting: Task<Void, Never>?
    private var records: [FeedbackRecord] = []
    private let text = NSTextView()
    private let kind = NSPopUpButton()
    private lazy var consent = NSButton(checkboxWithTitle: copy.text("附带最近的技术诊断（仅本次）", "Include recent diagnostics with this report"), target: nil, action: nil)
    private let service = NSTextField(wrappingLabelWithString: "")
    private lazy var status = NSTextField(wrappingLabelWithString: copy.text("正在打开本地反馈草稿…", "Opening your feedback draft…"))
    private lazy var send = NSButton(title: copy.text("发送反馈", "Send Feedback"), target: nil, action: nil)
    private let recoveryActions = NSStackView()
    private lazy var retrySave = NSButton(title: copy.text("重试保存", "Retry Save"), target: nil, action: nil)
    private lazy var copyText = NSButton(title: copy.text("复制正文", "Copy Text"), target: nil, action: nil)
    // This only selects the explicitly labelled recovery button's action. It
    // never schedules a later close after an unrelated edit or autosave.
    private var retryClosesWindow = false
    private var previewWindow: NSWindow?
    private var loading: Task<Void, Never>?
    private lazy var characterCount = NSTextField(labelWithString: copy.text("0 / 4,000 字符", "0 / 4,000 characters"))
    private lazy var recordsDisclosure = NSButton(title: copy.text("本机反馈记录 · 0", "Feedback on This Mac · 0"), target: nil, action: nil)
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

    public init(engine: FeedbackEngine?, diagnostics: FeedbackDiagnostics, appVersion: String, demo: Bool = false, copy: ProductCopy = .current) {
        self.copy = copy
        self.engine = engine; self.diagnostics = diagnostics; self.appVersion = appVersion; self.demo = demo
        if let engine { persistDraft = { value in try await engine.store.saveDraft(value) } }
        let window = RiftVisualStyle.window(outerSize: NSSize(width: 506, height: 464),
            minimum: NSSize(width: 450, height: 386), title: demo ? copy.text("反馈与建议 — 离线合成演示", "Feedback — Offline Demo") : copy.text("反馈与建议", "Feedback"))
        super.init(window: window)
        window.delegate = self; window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        build()
        loading = Task { [weak self] in await self?.load() }
    }
    required init?(coder: NSCoder) { return nil }
    func waitUntilLoaded() async { await loading?.value }

    private func build() {
        guard let content = window?.contentView else { return }
        let stack = RiftVisualStyle.documentStack([], spacing: 8)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 16, right: 24)
        let scroller = RiftVisualStyle.topAlignedScrollView()
        scroller.documentView = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = RiftVisualStyle.label(copy.text("使用反馈", "Feedback"), role: "title")
        heading.font = .systemFont(ofSize: 24, weight: .semibold)
        heading.textColor = .labelColor
        let introduction = RiftVisualStyle.label(copy.text("你遇到了什么问题，或有什么建议？", "What happened, or what would you like to improve?"), role: "secondary")
        kind.addItems(withTitles: [copy.text("遇到问题", "Report a Problem"), copy.text("改进建议", "Make a Suggestion")]); kind.target = self; kind.action = #selector(changedKind)
        kind.setAccessibilityLabel(copy.text("反馈类型", "Feedback type")); kind.font = RiftVisualStyle.bodyFont
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.documentView = text; scroll.backgroundColor = .textBackgroundColor
        text.isRichText = false; text.importsGraphics = false; text.isAutomaticQuoteSubstitutionEnabled = false
        text.font = RiftVisualStyle.bodyFont; text.textColor = .textColor; text.backgroundColor = .textBackgroundColor
        text.insertionPointColor = RiftVisualStyle.accent
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 12, height: 12); text.delegate = self
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
        text.defaultParagraphStyle = paragraph
        text.setAccessibilityLabel(copy.text("发生了什么？你原本希望怎样？", "What happened and what did you expect?"))
        scroll.heightAnchor.constraint(equalToConstant: 104).isActive = true
        characterCount.font = RiftVisualStyle.secondaryFont; characterCount.textColor = RiftVisualStyle.secondary
        characterCount.identifier = NSUserInterfaceItemIdentifier("feedback.characterCount")
        characterCount.toolTip = copy.text("组合符号和 emoji 可能包含多个字符，按组成字符计数；发送限制与这里的计数一致。正文最多 16 KiB。", "Counts Unicode scalars. Some emoji and combined characters count as more than one. The message limit is 16 KiB.")
        consent.target = self; consent.action = #selector(changedConsent); consent.font = RiftVisualStyle.bodyFont
        let preview = NSButton(title: copy.text("预览…", "Preview…"), target: self, action: #selector(showPreview)); RiftVisualStyle.style(preview)
        let diagnosticsRow = NSStackView(views: [consent, preview]); diagnosticsRow.spacing = 8
        let privacy = RiftVisualStyle.label(copy.text("反馈服务可用时，只有你提交的文字及主动勾选的诊断会发往开发者的私有反馈中心，可供开发者和获授权的 AI 辅助分析。不会自动附带截图、聊天、剪贴板、完整路径或浏览器资料。请勿填写密码等秘密。", "The developer and authorized AI tools may review your submitted text and any diagnostics you choose to include in a private feedback center. Screenshots, chats, clipboard contents, full paths, and browser data are never attached automatically. Keep passwords and other secrets out of your report."), role: "secondary")
        privacy.identifier = NSUserInterfaceItemIdentifier("feedback.privacy")
        service.font = RiftVisualStyle.secondaryFont; service.textColor = RiftVisualStyle.secondary
        service.identifier = NSUserInterfaceItemIdentifier("feedback.serviceCapability")
        if demo {
            service.stringValue = copy.text("离线合成演示；不会向云端发送反馈。", "Offline demo. Feedback stays on this Mac.")
        } else if engine == nil {
            service.stringValue = copy.text("本地反馈存储暂不可用；当前不会上传。", "Local feedback storage is unavailable. Sending is paused.")
        } else if engine?.configured == true {
            service.stringValue = copy.text("点“发送反馈”后，可在下方查看发送状态。", "Check the status of sent feedback below.")
        } else {
            service.stringValue = copy.text("接收服务尚未配置。可保存待发送；当前不会上传。", "The feedback service is not configured. You can save a report for later.")
        }
        status.font = RiftVisualStyle.secondaryFont; status.textColor = RiftVisualStyle.secondary
        send.title = engine?.configured == true ? copy.text("发送反馈", "Send Feedback") : copy.text("保存待发送", "Save for Later")
        send.target = self; send.action = #selector(submit); RiftVisualStyle.style(send, prominent: true)
        let close = NSButton(title: copy.text("保存并关闭", "Save and Close"), target: self, action: #selector(closeRequested)); RiftVisualStyle.style(close)
        retrySave.target = self; retrySave.action = #selector(retrySaveRequested)
        retrySave.identifier = NSUserInterfaceItemIdentifier("feedback.retrySave")
        copyText.target = self; copyText.action = #selector(copyTextRequested)
        copyText.identifier = NSUserInterfaceItemIdentifier("feedback.copyText")
        for button in [retrySave, copyText] { RiftVisualStyle.style(button); recoveryActions.addArrangedSubview(button) }
        recoveryActions.spacing = 8; recoveryActions.isHidden = true
        // Neither button is the Return default: Return and IME stay in the editor.
        let actions = NSStackView(views: [NSView(), close, send]); actions.spacing = 8
        let divider = NSBox(); divider.boxType = .separator
        let footer = RiftVisualStyle.vertical([divider, service, status, recoveryActions, actions], spacing: 5)
        recordsDisclosure.setButtonType(.onOff); recordsDisclosure.bezelStyle = .inline
        recordsDisclosure.identifier = NSUserInterfaceItemIdentifier("feedback.recordsDisclosure")
        recordsDisclosure.font = RiftVisualStyle.bodyFont; recordsDisclosure.contentTintColor = RiftVisualStyle.ink
        recordsDisclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        recordsDisclosure.imagePosition = .imageLeading
        recordsDisclosure.target = self; recordsDisclosure.action = #selector(toggleRecords)
        recordsDisclosure.setAccessibilityLabel(copy.text("展开本机反馈记录", "Show feedback on this Mac"))
        recordsBody.orientation = .vertical; recordsBody.alignment = .leading; recordsBody.spacing = 8
        rebuildRecords()
        recordsBody.isHidden = true
        let headline = NSStackView(views: [heading, NSView(), kind])
        headline.alignment = .centerY
        for view in [headline, introduction, scroll, characterCount, diagnosticsRow, privacy, recordsDisclosure, recordsBody] {
            stack.addArrangedSubview(view)
            if view !== recordsDisclosure { view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true }
        }
        for view in [scroller, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        for view in [divider, service, status, actions] { view.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true }
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
        recordsDisclosure.setAccessibilityLabel(recordsExpanded ? copy.text("收起本机反馈记录", "Hide feedback on this Mac") : copy.text("展开本机反馈记录", "Show feedback on this Mac"))
    }
    private func updateCharacterCount() {
        characterCount.stringValue = copy.text("\(text.string.unicodeScalars.count) / 4,000 字符", "\(text.string.unicodeScalars.count) / 4,000 characters")
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
            draft = try await engine.store.draft()
            cleanDraft = draft
            draftReadFailed = false
            applyDraft(); loaded = true; controlsEnabled(true)
            status.stringValue = copy.text("草稿保存在这台 Mac；关闭不会发送。", "Your draft stays on this Mac when you close this window.")
            await refreshRecords()
        } catch {
            // A missing baseline cannot supply a revision for editing or submission.
            loaded = true
            draftReadFailed = true
            controlsEnabled(false)
            presentError(copy.text("未能读取已有反馈草稿。可关闭窗口，重新打开时会再次读取。", "Your draft could not be read. Close and reopen this window to try again."))
        }
    }
    public func show() {
        if draftReadFailed, loaded, !busy {
            loaded = false
            loading = Task { [weak self] in await self?.load() }
        }
        if let window {
            let size = hasPresented ? window.frame.size : NSSize(width: 506, height: 464)
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
    private var selectedKind: FeedbackKind { kind.indexOfSelectedItem == 0 ? .problem : .suggestion }
    private func nextDraft() -> FeedbackDraft {
        draft.revision += 1; draft.text = text.string
        draft.kind = selectedKind
        return draft
    }
    public func textDidChange(_ notification: Notification) { updateCharacterCount(); saveEdited() }
    @objc private func changedKind() { saveEdited() }
    @objc private func changedConsent() {
        guard loaded, !busy, !draftReadFailed else { return }
        draft.diagnostic = consent.state == .on ? diagnostics.snapshot() : nil
        saveEdited()
    }
    private func saveEdited() {
        guard loaded, !busy, !draftReadFailed else { return }
        let value = nextDraft()
        autosave?.cancel()
        autosave = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                // A cancelled debounce must not forget an older write that the
                // store has already accepted. Keep at most one active writer.
                await autosaveWriting?.value
                try Task.checkCancellation()
                guard let persistDraft else {
                    draftSaveFailed(closeAttempt: false)
                    return
                }
                autosaveWriting = Task {
                    do {
                        try await persistDraft(value)
                        cleanDraft = value
                        if draft.revision == value.revision { draftSaved() }
                    } catch {
                        if draft.revision == value.revision { draftSaveFailed(closeAttempt: false) }
                    }
                }
            } catch { return }
        }
    }
    private func finishAutosave() async {
        autosave?.cancel()
        autosave = nil
        await autosaveWriting?.value
        autosaveWriting = nil
    }

    private func presentError(_ message: String) {
        let changed = status.stringValue != message
        status.stringValue = message
        if changed && isVisible {
            NSAccessibility.post(element: status, notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
    private func failure() {
        presentError(copy.text("未能可靠保存或处理反馈；文字仍在这里。请保留窗口或复制正文，不会报告发送成功。", "Your feedback could not be saved or processed. Keep this window open or copy your text."))
    }
    private func draftSaved() {
        recoveryActions.isHidden = true; retryClosesWindow = false
        status.stringValue = copy.text("草稿已保存在本机；没有发送。", "Draft saved on this Mac.")
    }
    private func draftSaveFailed(closeAttempt: Bool) {
        retryClosesWindow = closeAttempt
        retrySave.title = closeAttempt ? copy.text("重试保存并关闭", "Retry Save and Close") : copy.text("重试保存", "Retry Save")
        retrySave.isHidden = persistDraft == nil
        recoveryActions.isHidden = false
        presentError(persistDraft == nil
            ? copy.text("反馈存储暂不可用。文字仍在此窗口；关闭前请复制正文保存。", "Feedback storage is unavailable. Copy your text before closing this window.")
            : copy.text("未能可靠保存草稿；文字仍在此窗口。可重试保存或复制正文，没有发送。", "Your draft could not be saved. Retry or copy your text before closing this window."))
        updateSendAvailability()
    }
    public func saveBeforeClosing(lockOnSuccess: Bool = false) async -> Bool {
        await saveCurrentDraft(lockOnSuccess: lockOnSuccess, closeAttempt: true)
    }
    private func saveCurrentDraft(lockOnSuccess: Bool, closeAttempt: Bool) async -> Bool {
        guard loaded else { status.stringValue = copy.text("正在打开本地草稿，请稍候再关闭。", "Opening your draft. Wait for it to load before closing."); return false }
        guard !busy else { status.stringValue = copy.text("正在保存或处理反馈，请稍候再关闭。", "Wait for feedback processing to finish before closing."); return false }
        guard !text.hasMarkedText() else {
            status.stringValue = copy.text("请先完成当前文字输入，再保存并关闭。", "Finish composing the current text before saving and closing."); return false
        }
        busy = true; controlsEnabled(false)
        await finishAutosave()
        var saved = false
        defer {
            // App termination still awaits outbox stop and clean-exit persistence.
            // No new editing may enter between this save and the final quit reply.
            if !lockOnSuccess || !saved { busy = false; controlsEnabled(!draftReadFailed) }
        }
        if draftReadFailed {
            // The editor never opened. Closing cannot discard an edit or alter the stored draft.
            saved = true
            return true
        }
        if let cleanDraft, cleanDraft.text == text.string, cleanDraft.kind == selectedKind,
           cleanDraft.diagnostic == draft.diagnostic {
            if !recoveryActions.isHidden {
                recoveryActions.isHidden = true
                retryClosesWindow = false
                status.stringValue = copy.text("当前没有待保存的更改。", "All changes are saved.")
            }
            saved = true
            return true
        }
        guard let persistDraft else {
            draftSaveFailed(closeAttempt: closeAttempt)
            return false
        }
        status.stringValue = closeAttempt ? copy.text("正在保存草稿；保存完成后才能关闭。", "Saving your draft before closing…") : copy.text("正在保存草稿；不会发送。", "Saving your draft…")
        let value = nextDraft()
        do {
            try await persistDraft(value)
            cleanDraft = value
            saved = true
            draftSaved()
            return true
        }
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
            ? copy.text("正文已复制；没有发送或关闭反馈。", "Text copied. Your draft is still open.")
            : copy.text("无法复制正文，请选择文字后手动复制。", "Could not copy. Select the text and copy it manually.")
    }
    @objc private func showPreview() {
        let value = (try? draft.diagnostic?.preview()) ?? copy.text("未附带诊断。勾选后会冻结当时的白名单快照；之后的新事件不会加入本次提交。", "No diagnostics selected. Selecting the checkbox takes a snapshot of the allowed events at that moment.")
        showText(value, title: copy.text("本次诊断预览", "Diagnostics Preview"), monospaced: true)
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
        guard loaded, !busy, !draftReadFailed, let engine else { failure(); return }
        guard !text.hasMarkedText() else { return }
        let value = nextDraft(); busy = true; controlsEnabled(false)
        await finishAutosave()
        do {
            let id = try await engine.enqueue(value, appVersion: appVersion)
            draft = FeedbackDraft(revision: value.revision + 1)
            cleanDraft = draft
            applyDraft()
            status.stringValue = copy.text("已保存在本机，等待接收。编号 RF-\(id)", "Saved on this Mac, awaiting delivery. RF-\(id)")
            busy = false; controlsEnabled(true)
            await refreshRecords()
            await engine.pump(); await refreshRecords()
            if draft.revision == value.revision + 1, let record = records.first(where: { $0.id == id }) {
                status.stringValue = "\(statusLabel(record)) · RF-\(id)"
            }
        } catch {
            // Enqueue can persist the draft and then fail to create the report.
            cleanDraft = try? await engine.store.draft()
            busy = false; controlsEnabled(true)
            switch error {
            case FeedbackFailure.invalidText:
                status.stringValue = copy.text("请输入文字，最多 4,000 个 Unicode 字符且 16 KiB；原文仍在草稿中。", "Enter up to 4,000 Unicode scalars and 16 KiB. Your draft is still here.")
            case FeedbackFailure.capacity:
                status.stringValue = copy.text("待发送或本机记录已满；没有覆盖旧反馈，当前草稿保留。", "Your local feedback queue is full. Your draft and previous reports are saved.")
            case FeedbackFailure.secretUnavailable:
                status.stringValue = copy.text("无法保存反馈访问凭证。请检查钥匙串；原文已保留为草稿。", "The feedback credential could not be saved. Check Keychain. Your draft is preserved.")
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
            recordsDisclosure.title = copy.text("本机反馈记录 · \(records.count)", "Feedback on This Mac · \(records.count)")
            rebuildRecords()
        } catch { failure() }
    }

    private func statusLabel(_ record: FeedbackRecord) -> String {
        let prefix = demo ? copy.text("离线演示（非云端）：", "Offline demo: ") : ""
        let english: String
        switch record.state {
        case .queued: english = "Saved locally, awaiting delivery"
        case .received: english = "Received and stored by the service"
        case .delivered: english = "Delivered to the private feedback center"
        case .cancelled: english = "Cancelled before sending"
        case .blocked: english = "Needs attention. Your text is saved on this Mac."
        case .deletionQueued: english = "Deletion queued. The report text will not be resent."
        case .deletionBlocked: english = "Check the access credential and retry deletion. The text will not be resent."
        case .deletionPending: english = "Deleting the report and its private maintenance copy"
        case .deleted: english = "Deletion confirmed by the service"
        case .expired: english = "Delivery expired. Your text is saved on this Mac."
        }
        return prefix + copy.text(record.label, english)
    }

    private func recordButton(_ title: String, record: FeedbackRecord, action: Selector) -> NSButton {
        let button = FeedbackRecordButton(title: title, recordID: record.id, target: self, action: action)
        RiftVisualStyle.style(button); button.font = RiftVisualStyle.secondaryFont; button.controlSize = .small
        button.setAccessibilityLabel(copy.text("\(title)，反馈 RF-\(record.id.prefix(8))", "\(title), feedback RF-\(record.id.prefix(8))"))
        return button
    }
    private func rebuildRecords() {
        // Replace only this folded region. The editor, first responder, marked
        // text, selection and draft controls stay alive during every refresh.
        for view in recordsBody.arrangedSubviews { recordsBody.removeArrangedSubview(view); view.removeFromSuperview() }
        if records.isEmpty {
            let empty = RiftVisualStyle.label(copy.text("尚无已提交反馈。保存草稿不会生成待发送记录。", "No feedback submitted yet. Drafts appear here after submission."), role: "secondary")
            recordsBody.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: recordsBody.widthAnchor).isActive = true
            return
        }
        for record in records {
            let identifier = RiftVisualStyle.label("RF-\(record.id.prefix(8))", role: "heading")
            identifier.toolTip = "RF-\(record.id)"
            let state = RiftVisualStyle.label(statusLabel(record), role: "secondary")
            state.identifier = NSUserInterfaceItemIdentifier("feedback.record.status.\(record.id)")
            let body = FeedbackRecordBodyView(text: record.envelope.text, recordID: record.id)
            let actions = NSStackView(views: [recordButton(copy.text("查看完整正文", "Read Full Text"), record: record, action: #selector(showSaved(_:)))])
            actions.spacing = 8; actions.alignment = .centerY
            if record.state != .cancelled && record.state != .deleted {
                actions.addArrangedSubview(recordButton(copy.text("刷新状态", "Refresh Status"), record: record, action: #selector(refreshRecord(_:))))
            }
            switch record.state {
            case .cancelled, .deleted:
                actions.addArrangedSubview(recordButton(copy.text("移除本机正文与凭证…", "Remove Local Copy…"), record: record, action: #selector(forgetRecord(_:))))
            case .deletionQueued, .deletionPending:
                actions.addArrangedSubview(RiftVisualStyle.label(copy.text("等待删除确认", "Awaiting deletion confirmation"), role: "secondary"))
            default:
                let canCancelLocally = record.attempts == 0 && [.queued, .blocked, .deletionBlocked].contains(record.state)
                let title = canCancelLocally ? copy.text("取消待发送", "Cancel Queued Report") : record.state == .deletionBlocked ? copy.text("重新申请删除", "Retry Deletion") : copy.text("申请删除", "Request Deletion")
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
        if let record = record(for: sender) { showText(record.envelope.text, title: copy.text("本机保存的反馈 RF-\(record.id)", "Local Feedback RF-\(record.id)")) }
    }
    @objc private func refreshRecord(_ sender: FeedbackRecordButton) {
        guard let record = record(for: sender), let engine else { return }
        Task {
            do {
                if record.state == .queued || record.state == .deletionQueued { await engine.pump() }
                else { try await engine.refresh(id: record.id) }
                await refreshRecords()
            } catch { status.stringValue = copy.text("服务暂不可用；本机正文和反馈编号保留。", "The service is unavailable. The text and report ID are saved on this Mac.") }
        }
    }
    @objc private func forgetRecord(_ sender: FeedbackRecordButton) {
        guard let record = record(for: sender), let engine else { return }
        guard record.state == .cancelled || record.state == .deleted else {
            status.stringValue = copy.text("先取消未发送反馈或等待服务确认删除，再移除本机正文。", "Cancel the queued report or wait for deletion confirmation before removing the local copy."); return
        }
        confirmRecordAction(title: copy.text("移除这条本机反馈正文及访问凭证？", "Remove the local text and access credential?"),
            message: copy.text("只移除反馈 RF-\(record.id.prefix(8)) 的已取消或已确认删除的本机正文和钥匙串凭证。不改变其他反馈或任何截图。", "This removes the local copy and Keychain credential for resolved report RF-\(record.id.prefix(8)). Other reports and screenshots are unaffected."),
            button: copy.text("移除", "Remove")) { [weak self] in
                do { try await engine.forgetResolved(id: record.id); await self?.refreshRecords() }
                catch { self?.failure() }
            }
    }
    @objc private func deleteRecord(_ sender: FeedbackRecordButton) {
        guard let record = record(for: sender), let engine else { return }
        confirmRecordAction(title: sender.title == copy.text("取消待发送", "Cancel Queued Report") ? copy.text("取消这条待发送反馈？", "Cancel this queued report?") : copy.text("申请删除这条反馈？", "Request deletion of this report?"),
            message: copy.text("反馈 RF-\(record.id.prefix(8)) 如果还没发出，将取消发送。如果已经尝试发送，Riftlet 会申请删除云端记录及其维护副本。本机仍保留这条反馈。", "If RF-\(record.id.prefix(8)) has not been sent, delivery will be cancelled. Otherwise, Riftlet will request deletion of the service record and its maintenance copy. The local copy stays on this Mac."),
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
        let keep = alert.addButton(withTitle: copy.text("保留", "Keep"))
        destructive.keyEquivalent = ""
        keep.keyEquivalent = "\r"; keep.keyEquivalentModifierMask = []
        alert.layout()
        let sheet = alert.window
        sheet.initialFirstResponder = keep
        let cancellation = FeedbackSheetCancellationResponder()
        // nextResponder is unowned. The completion retains this responder until
        // it has restored the sheet's original chain on every dismissal path.
        alert.beginSheetModal(for: window) { [cancellation] response in
            cancellation.detach()
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in await operation() }
        }
        // NSWindow sets the default cell's key equivalent to Return. Escape
        // therefore uses this sheet's cancelOperation chain, not a second key
        // equivalent on the same button. All setup finishes synchronously.
        sheet.defaultButtonCell = keep.cell as? NSButtonCell
        sheet.makeFirstResponder(keep)
        cancellation.install(on: sheet)
    }
}

@MainActor
private final class FeedbackSheetCancellationResponder: NSResponder {
    private weak var sheet: NSWindow?
    private weak var content: NSView?
    private var originalNextResponder: NSResponder?

    func install(on sheet: NSWindow) {
        guard let content = sheet.contentView else { return }
        self.sheet = sheet; self.content = content
        originalNextResponder = content.nextResponder
        nextResponder = originalNextResponder
        content.nextResponder = self
    }

    func detach() {
        if let content, content.nextResponder === self {
            content.nextResponder = originalNextResponder
        }
        nextResponder = nil; originalNextResponder = nil
        content = nil; sheet = nil
    }

    override func cancelOperation(_ sender: Any?) {
        guard let sheet, let parent = sheet.sheetParent, parent.attachedSheet === sheet else { return }
        parent.endSheet(sheet, returnCode: .alertSecondButtonReturn)
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
