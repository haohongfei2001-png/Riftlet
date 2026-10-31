import XCTest
@testable import RiftletCore

/// Scheduling-contract regression for a permission loss between completion and
/// the App's fallback timer. No browser, permission prompt or input is involved.
/// App must consume a returned wake; these tests do not execute AppKit wiring.
final class TargetArmPermissionWakeTests: XCTestCase {
    func testDiscardedPermissionLossWakeCannotBeRecoveredByAnotherRequest() throws {
        var scheduler = TargetArmScheduler()
        scheduler.start()
        let finished = try XCTUnwrap(scheduler.begin())
        XCTAssertFalse(try XCTUnwrap(scheduler.complete(finished)).shouldWake)

        // The former App path discarded this true result while fallback slept.
        XCTAssertTrue(scheduler.request(invalidateEpoch: true))
        XCTAssertNil(scheduler.inFlight)
        XCTAssertTrue(scheduler.hasPendingRequest)
        for _ in 0..<100 {
            XCTAssertFalse(scheduler.request(), "Fallback, activation and new-image requests coalesce with the unconsumed wake")
        }
        XCTAssertNil(scheduler.inFlight, "This is a lost wake, not a stuck transport")
        XCTAssertTrue(scheduler.hasPendingRequest)
    }

    func testConsumingIdlePermissionLossWakeRestoresLaterForegroundDemand() throws {
        var scheduler = TargetArmScheduler()
        scheduler.start()
        let previous = try XCTUnwrap(scheduler.begin())
        _ = scheduler.complete(previous)
        let wake = scheduler.request(invalidateEpoch: true)
        XCTAssertTrue(wake)
        let replacement = try XCTUnwrap(wake ? scheduler.begin() : nil)
        XCTAssertNotEqual(replacement.epoch, previous.epoch)
        XCTAssertNil(scheduler.begin(), "Duplicate wakes cannot create parallel capture")
        let completed = try XCTUnwrap(scheduler.complete(replacement))
        XCTAssertTrue(completed.acceptsAcknowledgement)
        XCTAssertFalse(completed.shouldWake)
        XCTAssertTrue(scheduler.request(), "Returning to Chrome can request a fresh capture")
        XCTAssertNotNil(scheduler.begin())
    }

    func testInflightPermissionLossWaitsForDrainAndCannotPublishEarlierACK() throws {
        var scheduler = TargetArmScheduler()
        scheduler.start()
        let active = try XCTUnwrap(scheduler.begin())
        XCTAssertFalse(scheduler.request(invalidateEpoch: true))
        XCTAssertEqual(scheduler.inFlight, active)
        XCTAssertNil(scheduler.begin())
        let drained = try XCTUnwrap(scheduler.complete(active))
        XCTAssertFalse(drained.acceptsAcknowledgement)
        XCTAssertTrue(drained.shouldWake)
        let replacement = try XCTUnwrap(scheduler.begin())
        XCTAssertNotEqual(replacement.epoch, active.epoch)
        XCTAssertNil(scheduler.complete(active), "Late duplicate completion cannot release replacement")
        XCTAssertEqual(scheduler.inFlight, replacement)
    }
}
