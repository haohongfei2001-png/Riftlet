import XCTest
@testable import RiftletApp

final class SelectionSubmissionQueueTests: XCTestCase {
    @MainActor func testSuspendedFirstPermissionCannotLetLaterSelectionOvertake() async {
        let queue = SelectionSubmissionQueue()
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
        let b = queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            events.append("B.begin"); finished.fulfill()
        }
        XCTAssertEqual(a, 0); XCTAssertEqual(b, 1)
        await fulfillment(of: [entered], timeout: 5)
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
}
