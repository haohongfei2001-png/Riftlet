import XCTest
@testable import RiftletCore

final class TargetArmSchedulerTests: XCTestCase {
    func testStoppedRequestsCannotStartWorkAndStartWakesOnce() throws {
        var scheduler = TargetArmScheduler()
        XCTAssertFalse(scheduler.request()); XCTAssertNil(scheduler.begin())
        XCTAssertTrue(scheduler.start()); XCTAssertFalse(scheduler.start())
        for _ in 0..<20 { XCTAssertFalse(scheduler.request()) }
        let attempt = try XCTUnwrap(scheduler.begin())
        XCTAssertNil(scheduler.begin()); XCTAssertFalse(scheduler.hasPendingRequest)
        let completion = try XCTUnwrap(scheduler.complete(attempt))
        XCTAssertTrue(completion.acceptsAcknowledgement); XCTAssertFalse(completion.shouldWake)
        XCTAssertNil(scheduler.begin()); XCTAssertNil(scheduler.complete(attempt))
    }

    func testBurstDuringInflightCoalescesOneFollowupWithoutParallelWork() throws {
        var scheduler = TargetArmScheduler(); scheduler.start()
        let first = try XCTUnwrap(scheduler.begin())
        for _ in 0..<100 {
            XCTAssertFalse(scheduler.request())
            XCTAssertNil(scheduler.begin())
            XCTAssertEqual(scheduler.inFlight, first)
        }
        let completed = try XCTUnwrap(scheduler.complete(first))
        XCTAssertTrue(completed.acceptsAcknowledgement); XCTAssertTrue(completed.shouldWake)
        XCTAssertFalse(scheduler.request(), "The completion already supplied the one wake")
        let second = try XCTUnwrap(scheduler.begin())
        XCTAssertNotEqual(second.id, first.id); XCTAssertEqual(second.epoch, first.epoch)
        XCTAssertNil(scheduler.complete(first), "Duplicate old completion cannot release a newer flight")
        XCTAssertEqual(scheduler.inFlight, second)
        let done = try XCTUnwrap(scheduler.complete(second))
        XCTAssertFalse(done.shouldWake); XCTAssertNil(scheduler.begin())
    }

    func testInvalidatingInflightEpochRejectsACKAndWakesOnlyOneReplacement() throws {
        var scheduler = TargetArmScheduler(); scheduler.start()
        let first = try XCTUnwrap(scheduler.begin())
        for _ in 0..<10 { XCTAssertFalse(scheduler.request(invalidateEpoch: true)) }
        XCTAssertEqual(scheduler.inFlight, first, "Invalidation must not cancel an active transport")
        XCTAssertNil(scheduler.begin())
        let completed = try XCTUnwrap(scheduler.complete(first))
        XCTAssertFalse(completed.acceptsAcknowledgement); XCTAssertTrue(completed.shouldWake)
        let replacement = try XCTUnwrap(scheduler.begin())
        XCTAssertNotEqual(replacement.epoch, first.epoch)
        XCTAssertNil(scheduler.begin())
        let done = try XCTUnwrap(scheduler.complete(replacement))
        XCTAssertTrue(done.acceptsAcknowledgement); XCTAssertFalse(done.shouldWake)
    }

    func testInvalidationBeforeBeginRetainsSingleWakeAndUsesNewestEpoch() throws {
        var scheduler = TargetArmScheduler(); XCTAssertTrue(scheduler.start())
        let old = scheduler.epoch
        XCTAssertFalse(scheduler.request(invalidateEpoch: true))
        XCTAssertNotEqual(old, scheduler.epoch)
        let attempt = try XCTUnwrap(scheduler.begin())
        XCTAssertEqual(attempt.epoch, scheduler.epoch)
        XCTAssertTrue(try XCTUnwrap(scheduler.complete(attempt)).acceptsAcknowledgement)
    }

    func testStopRejectsACKWithoutCancelingOrRearming() throws {
        var scheduler = TargetArmScheduler(); scheduler.start()
        let first = try XCTUnwrap(scheduler.begin()); scheduler.request()
        scheduler.stop()
        XCTAssertEqual(scheduler.inFlight, first)
        XCTAssertFalse(scheduler.hasPendingRequest); XCTAssertNil(scheduler.begin())
        XCTAssertFalse(scheduler.request(invalidateEpoch: true))
        let completed = try XCTUnwrap(scheduler.complete(first))
        XCTAssertFalse(completed.acceptsAcknowledgement); XCTAssertFalse(completed.shouldWake)
        XCTAssertNil(scheduler.begin())
    }

    func testRestartWaitsForOldTransportAndRejectsItsACK() throws {
        var scheduler = TargetArmScheduler(); scheduler.start()
        let old = try XCTUnwrap(scheduler.begin())
        scheduler.stop()
        XCTAssertFalse(scheduler.start(), "Old transport owns the slot until it finishes")
        XCTAssertNil(scheduler.begin()); XCTAssertFalse(scheduler.request())
        let drained = try XCTUnwrap(scheduler.complete(old))
        XCTAssertFalse(drained.acceptsAcknowledgement); XCTAssertTrue(drained.shouldWake)
        let current = try XCTUnwrap(scheduler.begin())
        XCTAssertNotEqual(current.epoch, old.epoch)
        XCTAssertTrue(try XCTUnwrap(scheduler.complete(current)).acceptsAcknowledgement)
    }

    func testCompletionFromAnotherSchedulerCannotReleaseOwnFlight() throws {
        var first = TargetArmScheduler(), second = TargetArmScheduler()
        first.start(); second.start()
        let owned = try XCTUnwrap(first.begin()), unrelated = try XCTUnwrap(second.begin())
        XCTAssertNil(first.complete(unrelated)); XCTAssertEqual(first.inFlight, owned)
        XCTAssertNil(first.begin())
        XCTAssertTrue(try XCTUnwrap(first.complete(owned)).acceptsAcknowledgement)
    }

    func testNoAutomaticRetryAfterCompletedAttemptWithoutNewDemand() throws {
        var scheduler = TargetArmScheduler(); scheduler.start()
        let failedTransport = try XCTUnwrap(scheduler.begin())
        // Completion ends scheduling even if the caller has no ACK to publish.
        let completed = try XCTUnwrap(scheduler.complete(failedTransport))
        XCTAssertFalse(completed.shouldWake); XCTAssertNil(scheduler.begin())
        XCTAssertTrue(scheduler.request())
        XCTAssertFalse(scheduler.request())
        XCTAssertNotNil(scheduler.begin())
    }
}
