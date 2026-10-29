import XCTest
@testable import RiftletApp

final class SelectionSubmissionQueueTests: XCTestCase {
    @MainActor func testSuspendedFirstPermissionCannotLetLaterSelectionOvertake() async {
        let queue = SelectionSubmissionQueue()
        XCTAssertFalse(queue.hasOutstandingSubmission)
        var events: [String] = []
        var release: CheckedContinuation<Void, Never>?
        defer { queue.stop(); release?.resume() }
        let entered = expectation(description: "First original selection reached its permission wait")
        let finished = expectation(description: "Later selection runs after the first returned")
        let a = queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            events.append("A.begin")
            await withCheckedContinuation { release = $0; entered.fulfill() }
            events.append("A.end")
        }
        XCTAssertTrue(queue.hasOutstandingSubmission, "A queued original click is already outstanding before its task starts")
        let b = queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            events.append("B.begin"); finished.fulfill()
        }
        XCTAssertEqual(a, 0); XCTAssertEqual(b, 1)
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertTrue(queue.hasOutstandingSubmission, "A suspended active consumer still makes later clicks wait")
        XCTAssertEqual(events, ["A.begin"])
        release?.resume(); release = nil
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(events, ["A.begin", "A.end", "B.begin"])
    }

    @MainActor func testCancellationOnlyRemovesOriginalIDAndQueueHasFiniteCapacity() async {
        let queue = SelectionSubmissionQueue()
        var release: CheckedContinuation<Void, Never>?
        defer { queue.stop(); release?.resume() }
        var ran: [UUID] = [], cancelled: [UUID] = []
        let entered = expectation(description: "First submission owns the suspended slot")
        let finished = expectation(description: "All uncancelled original submissions ran")
        finished.expectedFulfillmentCount = 14
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            await withCheckedContinuation { release = $0; entered.fulfill() }
        }
        await fulfillment(of: [entered], timeout: 5)
        let ids = (0..<15).map { _ in UUID() }
        for id in ids {
            XCTAssertNotNil(queue.enqueue(selectionID: id, deadline: nil,
                cancelled: { cancelled.append(id) }, run: { _ in ran.append(id); finished.fulfill() }))
        }
        XCTAssertNil(queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}, run: { _ in XCTFail() }))
        queue.cancel(selectionIDs: [ids[0]])
        queue.cancel(selectionIDs: [ids[0]])
        XCTAssertEqual(cancelled, [ids[0]])
        release?.resume(); release = nil
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(ran, Array(ids.dropFirst()))
    }

    @MainActor func testUnsubmittedDeadlineExpiresWithoutRunningAndReleasesItsOwnReservation() async throws {
        let queue = SelectionSubmissionQueue()
        var release: CheckedContinuation<Void, Never>?
        defer { queue.stop(); release?.resume() }
        var cancelled = false, ran = false
        let entered = expectation(description: "Earlier selection blocks submission")
        let expired = expectation(description: "Actual deadline cancels the unsubmitted selection")
        let finished = expectation(description: "Earlier selection has returned")
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            await withCheckedContinuation { release = $0; entered.fulfill() }
            finished.fulfill()
        }
        await fulfillment(of: [entered], timeout: 5)
        queue.enqueue(selectionID: UUID(), deadline: ProcessInfo.processInfo.systemUptime + 0.01,
            cancelled: { cancelled = true; expired.fulfill() }, run: { _ in ran = true })
        await fulfillment(of: [expired], timeout: 5)
        XCTAssertTrue(cancelled); XCTAssertFalse(ran)
        release?.resume(); release = nil
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertFalse(ran)
    }

    @MainActor func testDelayedTimerSleepsOnlyTheOriginalRemainingInterval() async {
        let clock = SubmissionDeadlineClock()
        let queue = SelectionSubmissionQueue(uptime: { clock.now }, sleep: { await clock.sleep($0) })
        var release: CheckedContinuation<Void, Never>?
        defer { queue.stop(); release?.resume(); clock.resumeAll() }
        let entered = expectation(description: "A holds the submission consumer")
        let sleeping = expectation(description: "B timer starts after the controlled scheduling delay")
        let expired = expectation(description: "B expires at its original deadline")
        let finished = expectation(description: "A returns without submitting expired B")
        var cancellations = 0, submitted = false
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            await withCheckedContinuation { release = $0; entered.fulfill() }
            finished.fulfill()
        }
        await fulfillment(of: [entered], timeout: 5)
        clock.onSleep = { sleeping.fulfill() }
        queue.enqueue(selectionID: UUID(), deadline: 130,
            cancelled: { cancellations += 1; expired.fulfill() }, run: { _ in submitted = true })
        // No await between enqueue and advancing this clock: the MainActor
        // timer cannot have started at the original time of 100.
        clock.now = 120
        await fulfillment(of: [sleeping], timeout: 5)
        XCTAssertEqual(clock.sleepRequests, [10_000_000_000], "A late task must not sleep the original 30 seconds again")
        clock.now = 130; clock.resumeAll()
        await fulfillment(of: [expired], timeout: 5)
        XCTAssertEqual(cancellations, 1); XCTAssertFalse(submitted)
        release?.resume(); release = nil
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(cancellations, 1); XCTAssertFalse(submitted)
    }

    @MainActor func testTimerStartingAfterDeadlineCancelsWithoutAnotherSleep() async {
        let clock = SubmissionDeadlineClock()
        var sleepRequests: [UInt64] = []
        let queue = SelectionSubmissionQueue(uptime: { clock.now }, sleep: { sleepRequests.append($0) })
        var release: CheckedContinuation<Void, Never>?
        defer { queue.stop(); release?.resume() }
        let entered = expectation(description: "A holds the submission consumer")
        let expired = expectation(description: "Already expired B is removed immediately when its timer starts")
        let finished = expectation(description: "A returns after B was cancelled")
        var cancellations = 0, submitted = false
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            await withCheckedContinuation { release = $0; entered.fulfill() }
            finished.fulfill()
        }
        await fulfillment(of: [entered], timeout: 5)
        queue.enqueue(selectionID: UUID(), deadline: 110,
            cancelled: { cancellations += 1; expired.fulfill() }, run: { _ in submitted = true })
        clock.now = 111
        await fulfillment(of: [expired], timeout: 5)
        XCTAssertEqual(sleepRequests, [], "An expired absolute deadline must not acquire a fresh relative wait")
        XCTAssertEqual(cancellations, 1); XCTAssertFalse(submitted)
        release?.resume(); release = nil
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(cancellations, 1); XCTAssertFalse(submitted)
    }

    @MainActor func testDrainRejectsExpiredBWhileItsTimerIsSuspendedAndContinuesValidC() async {
        let clock = SubmissionDeadlineClock()
        let queue = SelectionSubmissionQueue(uptime: { clock.now }, sleep: { await clock.sleep($0) })
        var release: CheckedContinuation<Void, Never>?
        defer { queue.stop(); release?.resume(); clock.resumeAll() }
        let entered = expectation(description: "A holds the submission consumer")
        let sleeping = expectation(description: "B timer is suspended before its expiry callback")
        let finished = expectation(description: "Valid C runs after expired B is cancelled")
        let bID = UUID()
        var events: [String] = []
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            events.append("A.begin")
            await withCheckedContinuation { release = $0; entered.fulfill() }
            events.append("A.end")
        }
        await fulfillment(of: [entered], timeout: 5)
        clock.onSleep = { sleeping.fulfill() }
        XCTAssertEqual(queue.enqueue(selectionID: bID, deadline: 110,
            cancelled: { events.append("B.cancelled") }, run: { _ in events.append("B.run") }), 1)
        await fulfillment(of: [sleeping], timeout: 5)
        clock.onSleep = nil
        clock.now = 110 // Equality is expired, as it is in AcceptedSelection.
        XCTAssertEqual(queue.enqueue(selectionID: UUID(), deadline: 120,
            cancelled: { events.append("C.cancelled") }, run: { _ in events.append("C.run"); finished.fulfill() }), 2)
        release?.resume(); release = nil
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(events, ["A.begin", "A.end", "B.cancelled", "C.run"])
        queue.cancel(selectionIDs: [bID]) // A late cancellation cannot settle B twice.
        XCTAssertEqual(events, ["A.begin", "A.end", "B.cancelled", "C.run"])
    }
}

/// Advances only when the test says so; sleepers are released explicitly.
/// No elapsed wall time or thread blocking supplies the scheduling interleaving.
@MainActor
private final class SubmissionDeadlineClock {
    var now: TimeInterval = 100
    var onSleep: (() -> Void)?
    private(set) var sleepRequests: [UInt64] = []
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    func sleep(_ nanoseconds: UInt64) async {
        sleepRequests.append(nanoseconds)
        await withCheckedContinuation { sleepers.append($0); onSleep?() }
    }

    func resumeAll() {
        let pending = sleepers; sleepers.removeAll()
        for sleeper in pending { sleeper.resume() }
    }
}
