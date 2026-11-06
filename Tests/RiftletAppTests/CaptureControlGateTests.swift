import XCTest
@testable import RiftletApp

final class CaptureControlGateTests: XCTestCase {
    func testRecheckCannotRestartSourceAcrossAcceptedPause() throws {
        var gate = CaptureControlGate()
        let recheck = try XCTUnwrap(gate.begin(.recheck))
        XCTAssertTrue(gate.acceptsCollectionIntent, "A native click must not be cancelled by a read-only activation recheck")
        XCTAssertNil(gate.begin(.changeCollection), "The accepted intent waits; execution still cannot overlap recheck")
        XCTAssertEqual(gate.action, .recheck)
        gate.finish(recheck)
        let pause = try XCTUnwrap(gate.begin(.changeCollection))
        XCTAssertFalse(gate.acceptsCollectionIntent, "An executing change must not accept another collection command")
        XCTAssertNil(gate.begin(.recheck), "No new check can restart a source while Pause stops/persists it")
        XCTAssertEqual(gate.action, .changeCollection)
        gate.finish(pause)
        XCTAssertFalse(gate.isBusy)
        XCTAssertTrue(gate.acceptsCollectionIntent)
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
