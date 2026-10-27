import XCTest
@testable import RiftletApp

final class DeferredChromeActivityBindingTests: XCTestCase {
    func testFirstCompletedCaptureConsumesOneBindingIndependentOfCaptureSuccess() {
        let epoch = UUID()
        var binding = DeferredChromeActivityBinding()
        binding.request(afterCaptureIn: epoch)
        // No success/permission value is accepted here: an unsuccessful capture
        // still needs later hint events, and binding grants no page authority.
        XCTAssertTrue(binding.take(afterCaptureIn: epoch, isRunning: true))
        XCTAssertFalse(binding.take(afterCaptureIn: epoch, isRunning: true))
    }

    func testForegroundChangeDuringCaptureDoesNotLetOldCompletionStealNewBinding() {
        let original = UUID(), current = UUID()
        var binding = DeferredChromeActivityBinding()
        binding.request(afterCaptureIn: original)
        binding.request(afterCaptureIn: current)
        XCTAssertFalse(binding.take(afterCaptureIn: original, isRunning: true))
        XCTAssertTrue(binding.take(afterCaptureIn: current, isRunning: true))
        XCTAssertFalse(binding.take(afterCaptureIn: current, isRunning: true))
    }

    func testRepeatedSignalsCoalesceAndStopCannotRestoreOldBinding() {
        let epoch = UUID()
        var binding = DeferredChromeActivityBinding()
        for _ in 0..<1000 { binding.request(afterCaptureIn: epoch) }
        XCTAssertFalse(binding.take(afterCaptureIn: epoch, isRunning: false))
        XCTAssertTrue(binding.take(afterCaptureIn: epoch, isRunning: true))
        XCTAssertFalse(binding.take(afterCaptureIn: epoch, isRunning: true))
        binding.request(afterCaptureIn: epoch)
        binding.cancel()
        XCTAssertFalse(binding.take(afterCaptureIn: epoch, isRunning: true))
    }
}
