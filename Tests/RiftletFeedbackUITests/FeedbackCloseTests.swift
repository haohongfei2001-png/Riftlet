import AppKit
import XCTest
import RiftletFeedback
@testable import RiftletFeedbackUI

final class FeedbackCloseTests: XCTestCase {
    @MainActor private func fixture() throws -> (FeedbackStore, FeedbackWindowController) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-close-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try FeedbackStore(directory: root)
        let engine = FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: DisabledFeedbackTransport())
        return (store, FeedbackWindowController(engine: engine, diagnostics: FeedbackDiagnostics(), appVersion: "0.1.0"))
    }
    @MainActor private func editor(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.compactMap { editor(in: $0) }.first
    }
    @MainActor func testEveryCloseAttemptFlushesEvenAfterPriorProgrammaticClose() async throws {
        let (store, controller) = try fixture(); await controller.waitUntilLoaded()
        let window = try XCTUnwrap(controller.window)
        let text = try XCTUnwrap(editor(in: try XCTUnwrap(window.contentView)))
        var previousRevision: Int64 = 0
        for value in ["first close", "reopened final edit"] {
            // Exercise a genuinely reopened window. Closing an already-closed
            // NSWindow need not produce a second willClose notification.
            controller.showWindow(nil)
            XCTAssertTrue(window.isVisible)
            text.string = value
            controller.textDidChange(Notification(name: NSText.didChangeNotification))
            let closed = expectation(description: "window closed after durable save: \(value)")
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in closed.fulfill() }
            // AppKit must call the delegate, defer closing and then close after
            // persistence. Do not replace this with a direct delegate invocation.
            window.performClose(nil)
            await fulfillment(of: [closed], timeout: 3)
            NotificationCenter.default.removeObserver(observer)
            XCTAssertFalse(window.isVisible)
            let saved = try await store.draft()
            XCTAssertEqual(saved.text, value)
            XCTAssertGreaterThan(saved.revision, previousRevision)
            previousRevision = saved.revision
        }
    }
    @MainActor func testTerminationKeepsEditorFrozenAfterSaveThroughLaterHostAwaits() async throws {
        let (_, controller) = try fixture(); await controller.waitUntilLoaded()
        let saved = await controller.saveBeforeClosing(lockOnSuccess: true)
        XCTAssertTrue(saved); XCTAssertFalse(controller.isEditingEnabled)
        await Task.yield()
        XCTAssertFalse(controller.isEditingEnabled)
        let repeated = await controller.saveBeforeClosing()
        XCTAssertFalse(repeated)
    }
}
