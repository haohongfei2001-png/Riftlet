import AppKit
import XCTest
import RiftletFeedback
@testable import RiftletFeedbackUI

private actor HeldDraftWrite {
    private var value: FeedbackDraft?
    private var entered: CheckedContinuation<FeedbackDraft, Never>?
    private var completion: CheckedContinuation<Void, Error>?
    func save(_ draft: FeedbackDraft) async throws {
        value = draft
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation; entered?.resume(returning: draft); entered = nil
        }
    }
    func waitUntilEntered() async -> FeedbackDraft {
        if let value { return value }
        return await withCheckedContinuation { entered = $0 }
    }
    func finish(failed: Bool) {
        let c = completion; completion = nil
        if failed { c?.resume(throwing: FeedbackFailure.storageUnavailable) } else { c?.resume() }
    }
}
final class FeedbackWindowTests: XCTestCase {
    @MainActor private func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor private func fixture() throws -> (FeedbackStore, FeedbackEngine, FeedbackDiagnostics, FeedbackWindowController) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-ui-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try FeedbackStore(directory: root)
        let engine = FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: DisabledFeedbackTransport())
        let diagnostics = FeedbackDiagnostics()
        return (store, engine, diagnostics, FeedbackWindowController(engine: engine, diagnostics: diagnostics, appVersion: "0.1.0"))
    }
    @MainActor private func editor(_ controller: FeedbackWindowController) throws -> NSTextView {
        try XCTUnwrap(views(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSTextView }.first)
    }
    @MainActor func testNativeWindowHasEditableTextAndConsentOffWithoutNetwork() async throws {
        let (store, engine, _, controller) = try fixture(); await controller.waitUntilLoaded()
        XCTAssertEqual(controller.window?.title, "反馈与建议")
        XCTAssertFalse(controller.diagnosticSelected); XCTAssertEqual(controller.currentText, "")
        XCTAssertFalse(controller.isVisible); XCTAssertTrue(controller.isEditingEnabled)
        let records = try await store.records(); XCTAssertTrue(records.isEmpty)
        let service = try XCTUnwrap(views(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "feedback.serviceCapability" })
        XCTAssertTrue(service.stringValue.contains("尚未配置"))
        XCTAssertTrue(service.stringValue.contains("当前不会上传"))
        await engine.stop()
    }
    @MainActor func testServiceCapabilityRemainsVisibleAfterAutosaveAndLocalSubmission() async throws {
        let (store, engine, _, controller) = try fixture(); await controller.waitUntilLoaded()
        let content = try XCTUnwrap(controller.window?.contentView)
        let service = try XCTUnwrap(views(content).compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "feedback.serviceCapability" })
        let originalCapability = service.stringValue
        XCTAssertTrue(originalCapability.contains("当前不会上传"))
        XCTAssertFalse(service.isHidden)
        let body = "自动保存以后，未配置服务的提示仍要保留"
        try editor(controller).string = body
        controller.textDidChange(Notification(name: NSText.didChangeNotification))
        for _ in 0..<100 {
            if try await store.draft().text == body { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let saved = try await store.draft(); XCTAssertEqual(saved.text, body)
        XCTAssertEqual(service.stringValue, originalCapability)
        XCTAssertTrue(controller.statusText.contains("已保存在本机"))
        await controller.submitCurrentDraft()
        let records = try await store.records()
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records.first?.attempts, 0)
        XCTAssertEqual(records.first?.state, .queued)
        XCTAssertEqual(service.stringValue, originalCapability); XCTAssertFalse(service.isHidden)
        await engine.stop()
    }
    @MainActor func testCloseFreezesTextKindAndConsentBeforeAsyncSaveAndRestoresOnFailure() async throws {
        for failed in [false, true] {
            let (_, engine, _, controller) = try fixture(); await controller.waitUntilLoaded()
            let editor = try editor(controller); editor.string = "最后一次编辑\n不能丢失"
            controller.textDidChange(Notification(name: NSText.didChangeNotification))
            let gate = HeldDraftWrite(); controller.persistDraft = { try await gate.save($0) }
            let closing = Task { @MainActor in await controller.saveBeforeClosing() }
            let frozen = await gate.waitUntilEntered()
            XCTAssertFalse(controller.isEditingEnabled)
            XCTAssertEqual(frozen.text, editor.string)
            let repeated = await controller.saveBeforeClosing()
            XCTAssertFalse(repeated); XCTAssertTrue(controller.statusText.contains("正在保存"))
            await gate.finish(failed: failed)
            let accepted = await closing.value
            XCTAssertEqual(accepted, !failed); XCTAssertTrue(controller.isEditingEnabled)
            XCTAssertEqual(controller.currentText, frozen.text)
            if failed { XCTAssertTrue(controller.statusText.contains("未能可靠保存")) }
            await engine.stop()
        }
    }
    @MainActor func testConsentFreezesExactPreviewAndFreshDraftResetsIt() async throws {
        let (store, engine, diagnostics, controller) = try fixture(); await controller.waitUntilLoaded()
        diagnostics.record(.queueUnknown); diagnostics.record(.visibilitySwallowed)
        let button = try XCTUnwrap(views(try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSButton }.first { $0.title.hasPrefix("附带最近") })
        button.performClick(nil)
        let preview = try XCTUnwrap(controller.draftForTesting.diagnostic).preview()
        diagnostics.record(.phaseSucceeded)
        try editor(controller).string = "只附带已预览的快照"
        controller.textDidChange(Notification(name: NSText.didChangeNotification))
        await controller.submitCurrentDraft()
        let records = try await store.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(try records.first?.envelope.diagnostic?.preview(), preview)
        XCTAssertFalse(preview.contains("phaseSucceeded"))
        XCTAssertEqual(controller.currentText, ""); XCTAssertFalse(controller.diagnosticSelected)
        XCTAssertEqual(records.first?.attempts, 0); XCTAssertEqual(records.first?.state, .queued)
        await engine.stop()
    }
    @MainActor func testTextOnlySubmissionNeverBorrowsAvailableDiagnostics() async throws {
        let (store, engine, diagnostics, controller) = try fixture(); await controller.waitUntilLoaded()
        diagnostics.record(.phaseUnknown)
        try editor(controller).string = "不要附带诊断"
        controller.textDidChange(Notification(name: NSText.didChangeNotification))
        await controller.submitCurrentDraft()
        let records = try await store.records()
        XCTAssertNil(records.first?.envelope.diagnostic)
        XCTAssertFalse(controller.statusText.contains("云端已持久接收"))
        await engine.stop()
    }
    @MainActor func testUnavailableStoreCannotCloseAndLoseUnsavedText() async throws {
        _ = NSApplication.shared
        let controller = FeedbackWindowController(engine: nil, diagnostics: FeedbackDiagnostics(), appVersion: "0.1.0")
        await controller.waitUntilLoaded()
        try editor(controller).string = "保留在窗口中"
        let saved = await controller.saveBeforeClosing()
        XCTAssertFalse(saved); XCTAssertEqual(controller.currentText, "保留在窗口中")
        XCTAssertFalse(controller.diagnosticSelected); XCTAssertTrue(controller.isEditingEnabled)
        XCTAssertTrue(controller.statusText.contains("存储暂不可用"))
        let copy = try XCTUnwrap(views(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "feedback.copyText" })
        XCTAssertTrue(copy.isEnabled); XCTAssertFalse(try XCTUnwrap(copy.superview).isHidden)
    }
    @MainActor func testMarkedTextCannotSubmitOrCloseUntilCompositionIsCommitted() async throws {
        let (store, engine, _, controller) = try fixture(); await controller.waitUntilLoaded()
        let text = try editor(controller)
        text.setMarkedText("中文组字", selectedRange: NSRange(location: 4, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(text.hasMarkedText())
        await controller.submitCurrentDraft()
        let closed = await controller.saveBeforeClosing()
        let before = try await store.records()
        XCTAssertFalse(closed); XCTAssertTrue(before.isEmpty)
        XCTAssertEqual(controller.currentText, "中文组字")
        XCTAssertTrue(controller.statusText.contains("请先完成当前文字输入"))
        text.unmarkText()
        XCTAssertFalse(text.hasMarkedText())
        await controller.submitCurrentDraft()
        let after = try await store.records()
        XCTAssertEqual(after.count, 1); XCTAssertEqual(after.first?.envelope.text, "中文组字")
        await engine.stop()
    }
    @MainActor func testFailedCloseOffersExplicitRetryAndCopiesOnlyDraftBody() async throws {
        let (store, engine, diagnostics, controller) = try fixture(); await controller.waitUntilLoaded()
        let window = try XCTUnwrap(controller.window); controller.showWindow(nil)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        diagnostics.record(.queueUnknown)
        let consent = try XCTUnwrap(views(content).compactMap { $0 as? NSButton }.first { $0.title.hasPrefix("附带最近") })
        consent.performClick(nil)
        let body = "这是要保留的正文\n只复制这段，不附带技术诊断。"
        try editor(controller).string = body
        controller.textDidChange(Notification(name: NSText.didChangeNotification))
        let gate = HeldDraftWrite(); controller.persistDraft = { try await gate.save($0) }
        let closing = Task { @MainActor in await controller.saveBeforeClosing() }
        _ = await gate.waitUntilEntered(); await gate.finish(failed: true)
        let closed = await closing.value
        XCTAssertFalse(closed); XCTAssertTrue(window.isVisible); XCTAssertTrue(controller.isEditingEnabled)
        let retry = try XCTUnwrap(views(content).compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "feedback.retrySave" })
        XCTAssertEqual(retry.title, "重试保存并关闭")
        XCTAssertTrue(retry.isEnabled); XCTAssertFalse(try XCTUnwrap(retry.superview).isHidden)
        let board = NSPasteboard(name: NSPasteboard.Name("Riftlet.feedback-copy-test." + UUID().uuidString))
        defer { board.releaseGlobally() }
        XCTAssertTrue(controller.copyDraftText(to: board))
        XCTAssertEqual(board.string(forType: .string), body)
        // AppKit may publish its legacy NSString alias for the same plain text.
        // Permit only these two known types; URLs, files, images and diagnostics
        // still have no representation on this private pasteboard.
        let copiedTypes = Set(try XCTUnwrap(board.types))
        let plainTextTypes: Set<NSPasteboard.PasteboardType> = [.string, .init("NSStringPboardType")]
        XCTAssertTrue(copiedTypes.contains(.string))
        XCTAssertTrue(copiedTypes.isSubset(of: plainTextTypes))
        for type in copiedTypes { XCTAssertEqual(board.string(forType: type), body) }
        XCTAssertTrue(controller.diagnosticSelected)
        let before = try await store.records(); XCTAssertTrue(before.isEmpty)
        // Recovery does not run on its own. The explicit retry uses the current
        // body and the original durable save path, then closes only on success.
        controller.persistDraft = { try await store.saveDraft($0) }
        let finished = expectation(description: "explicit retry saved and closed")
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
            object: window, queue: .main) { _ in finished.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        retry.performClick(nil)
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertFalse(window.isVisible)
        let saved = try await store.draft(); XCTAssertEqual(saved.text, body); XCTAssertNotNil(saved.diagnostic)
        let after = try await store.records(); XCTAssertTrue(after.isEmpty)
        await engine.stop()
    }
}
