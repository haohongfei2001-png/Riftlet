import AppKit
import XCTest
import RiftletFeedback
@testable import RiftletFeedbackUI

final class FeedbackVisualCandidateTests: XCTestCase {
    @MainActor private func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor func testFeedbackReopenPreservesValidPositionAndUsesTopAlignedDocument() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { throw XCTSkip("AppKit window server unavailable") }
        let controller = FeedbackWindowController(engine: nil, diagnostics: FeedbackDiagnostics(), appVersion: "test")
        await controller.waitUntilLoaded()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.show()
        let origin = CGPoint(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.minY + 24)
        window.setFrameOrigin(origin)
        window.close(); controller.show()
        XCTAssertEqual(window.frame.origin, origin)
        let content = try XCTUnwrap(window.contentView)
        let scrollers = views(content).compactMap { $0 as? NSScrollView }
        let document = try XCTUnwrap(scrollers.first { $0.documentView is NSStackView })
        XCTAssertTrue(document.contentView.isFlipped)
        XCTAssertTrue(try XCTUnwrap(document.documentView).isFlipped)
        XCTAssertTrue(views(content).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("开发者的私有反馈中心") })
    }
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
