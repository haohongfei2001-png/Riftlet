import AppKit
import XCTest
import RiftletFeedback
@testable import RiftletFeedbackUI

final class FeedbackTextLimitTests: XCTestCase {
    @MainActor private func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor private func fixture() async throws -> (FeedbackStore, FeedbackEngine, FeedbackWindowController) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-text-limit-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try FeedbackStore(directory: root)
        let engine = FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: DisabledFeedbackTransport())
        let controller = FeedbackWindowController(engine: engine, diagnostics: FeedbackDiagnostics(), appVersion: "0.1.0")
        await controller.waitUntilLoaded()
        return (store, engine, controller)
    }
    @MainActor private func controls(_ controller: FeedbackWindowController) throws -> (NSTextView, NSTextField, NSButton) {
        let all = views(try XCTUnwrap(controller.window?.contentView))
        let editor = try XCTUnwrap(all.compactMap { $0 as? NSTextView }.first)
        let count = try XCTUnwrap(all.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "feedback.characterCount" })
        let send = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.title == "保存待发送" })
        return (editor, count, send)
    }
    @MainActor private func edit(_ value: String, in editor: NSTextView, controller: FeedbackWindowController) {
        editor.string = value
        controller.textDidChange(Notification(name: NSText.didChangeNotification))
    }

    @MainActor func testPlainChineseAndScalarBoundaryKeepReadableAccurateCount() async throws {
        let (_, engine, controller) = try await fixture()
        let (editor, count, send) = try controls(controller)
        XCTAssertFalse(send.isEnabled, "An empty draft is not sendable")
        edit("普通中文", in: editor, controller: controller)
        XCTAssertEqual(count.stringValue, "4 / 4,000 字符"); XCTAssertTrue(send.isEnabled)
        edit(String(repeating: "界", count: 4_000), in: editor, controller: controller)
        XCTAssertEqual(count.stringValue, "4000 / 4,000 字符"); XCTAssertTrue(send.isEnabled)
        edit(String(repeating: "界", count: 4_001), in: editor, controller: controller)
        XCTAssertEqual(count.stringValue, "4001 / 4,000 字符"); XCTAssertFalse(send.isEnabled)
        edit(" \n\t", in: editor, controller: controller); XCTAssertFalse(send.isEnabled)
        _ = await controller.saveBeforeClosing(); await engine.stop(); controller.window?.close()
    }

    @MainActor func testCombiningGlyphsUseEnvelopeScalarsAndInvalidDraftIsPreserved() async throws {
        let (store, engine, controller) = try await fixture()
        let (editor, count, send) = try controls(controller)
        let accepted = String(repeating: "e\u{301}", count: 2_000)
        XCTAssertEqual(accepted.count, 2_000); XCTAssertEqual(accepted.unicodeScalars.count, 4_000)
        edit(accepted, in: editor, controller: controller)
        XCTAssertEqual(count.stringValue, "4000 / 4,000 字符"); XCTAssertTrue(send.isEnabled)
        XCTAssertNoThrow(try FeedbackEnvelope(draft: FeedbackDraft(text: editor.string), appVersion: "0.1.0"))
        let rejected = accepted + "e\u{301}"
        edit(rejected, in: editor, controller: controller)
        XCTAssertEqual(count.stringValue, "4002 / 4,000 字符"); XCTAssertFalse(send.isEnabled)
        await controller.submitCurrentDraft()
        let records = try await store.records(); let draft = try await store.draft()
        XCTAssertTrue(records.isEmpty); XCTAssertEqual(draft.text, rejected)
        XCTAssertEqual(controller.currentText, rejected); XCTAssertTrue(controller.statusText.contains("4,000"))
        _ = await controller.saveBeforeClosing(); await engine.stop(); controller.window?.close()
    }

    @MainActor func testUTF8BoundaryUsesSameEnvelopeAdmissionWithoutTruncation() async throws {
        let (_, engine, controller) = try await fixture()
        let (editor, count, send) = try controls(controller)
        for (characters, allowed) in [(4_000, true), (4_096, false), (4_097, false)] {
            let value = String(repeating: "😀", count: characters)
            XCTAssertEqual(value.utf8.count, characters * 4)
            edit(value, in: editor, controller: controller)
            XCTAssertEqual(send.isEnabled, allowed)
            XCTAssertEqual((try? FeedbackEnvelope(draft: FeedbackDraft(text: value), appVersion: "0.1.0")) != nil, allowed)
            XCTAssertEqual(count.stringValue, "\(characters) / 4,000 字符")
            XCTAssertEqual(controller.currentText, value)
        }
        _ = await controller.saveBeforeClosing(); await engine.stop(); controller.window?.close()
    }
}
