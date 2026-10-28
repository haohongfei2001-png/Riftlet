import AppKit
import XCTest
import RiftletFeedback
@testable import RiftletFeedbackUI

final class FeedbackVisualCandidateTests: XCTestCase {
    @MainActor private func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor func testCollapsedRecordsKeepSameEditorDraftSelectionAndNoDefaultSubmit() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit window server unavailable") }
        let controller = FeedbackWindowController(engine: nil, diagnostics: FeedbackDiagnostics(), appVersion: "test")
        await controller.waitUntilLoaded()
        let content = try XCTUnwrap(controller.window?.contentView)
        let editor = try XCTUnwrap(views(content).compactMap { $0 as? NSTextView }.first)
        let buttons = views(content).compactMap { $0 as? NSButton }
        let disclosure = try XCTUnwrap(buttons.first { $0.title.hasPrefix("本机反馈记录") })
        let send = try XCTUnwrap(buttons.first { $0.title == "保存待发送" })
        XCTAssertTrue(send.keyEquivalent.isEmpty, "Return must remain a text/IME operation")
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 600, height: 540))
        editor.string = "selection and local draft stay in the same editor"
        editor.setSelectedRange(NSRange(location: 2, length: 9))
        let before = controller.draftForTesting
        disclosure.performClick(nil); disclosure.performClick(nil)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 9))
        XCTAssertEqual(controller.currentText, editor.string)
        XCTAssertEqual(controller.draftForTesting, before, "Folding must not save or re-create a draft")
        XCTAssertFalse(controller.diagnosticSelected)
        XCTAssertEqual(views(content).compactMap { $0 as? NSTextView }.first, editor)
        controller.window?.close()
    }
}
