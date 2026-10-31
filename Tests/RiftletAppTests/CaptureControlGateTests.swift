import XCTest
@testable import RiftletApp

final class CaptureControlGateTests: XCTestCase {
    func testRecheckCannotRestartSourceAcrossAcceptedPause() throws {
        var gate = CaptureControlGate()
        let recheck = try XCTUnwrap(gate.begin(.recheck))
        XCTAssertNil(gate.begin(.changeCollection), "Pause is disabled until the existing source recheck ends")
        XCTAssertEqual(gate.action, .recheck)
        gate.finish(recheck)
        let pause = try XCTUnwrap(gate.begin(.changeCollection))
        XCTAssertNil(gate.begin(.recheck), "No new check can restart a source while Pause stops/persists it")
        XCTAssertEqual(gate.action, .changeCollection)
        gate.finish(pause)
        XCTAssertFalse(gate.isBusy)
    }

    func testStaleCompletionCannotUnlockLaterSourceControl() throws {
        var gate = CaptureControlGate()
        let old = try XCTUnwrap(gate.begin(.recheck))
        gate.finish(old)
        let current = try XCTUnwrap(gate.begin(.changeCollection))
        gate.finish(old)
        XCTAssertTrue(gate.isBusy)
        XCTAssertNil(gate.begin(.recheck))
        gate.finish(current)
        XCTAssertNotNil(gate.begin(.recheck))
    }
}
