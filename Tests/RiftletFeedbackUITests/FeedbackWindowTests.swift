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
        XCTAssertTrue(controller.statusText.contains("尚未配置"))
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
        text.unmarkText()
        XCTAssertFalse(text.hasMarkedText())
        await controller.submitCurrentDraft()
        let after = try await store.records()
        XCTAssertEqual(after.count, 1); XCTAssertEqual(after.first?.envelope.text, "中文组字")
        await engine.stop()
    }
}
