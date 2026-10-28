import AppKit
import XCTest
import RiftletFeedback
@testable import RiftletFeedbackUI

final class FeedbackWindowTests:XCTestCase {
    @MainActor func testNativeWindowHasEditableTextAndConsentOffWithoutNetwork() async throws {
        _=NSApplication.shared
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=try FeedbackStore(directory:url)
        let engine=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:DisabledFeedbackTransport())
        let controller=FeedbackWindowController(engine:engine,diagnostics:FeedbackDiagnostics(),appVersion:"0.1.0")
        XCTAssertNotNil(controller.window);XCTAssertEqual(controller.window?.title,"反馈与建议")
        XCTAssertFalse(controller.diagnosticSelected);XCTAssertEqual(controller.currentText,"")
        XCTAssertFalse(controller.isVisible)
        let records=try await store.records();XCTAssertTrue(records.isEmpty)
        controller.close();await engine.stop()
    }
    @MainActor func testUnavailableFeedbackStoreStillOffersTextWindowNotScreenshotFailure() {
        _=NSApplication.shared
        let controller=FeedbackWindowController(engine:nil,diagnostics:FeedbackDiagnostics(),appVersion:"0.1.0")
        XCTAssertNotNil(controller.window?.contentView);XCTAssertFalse(controller.diagnosticSelected)
        XCTAssertFalse(controller.isVisible)
    }
}
