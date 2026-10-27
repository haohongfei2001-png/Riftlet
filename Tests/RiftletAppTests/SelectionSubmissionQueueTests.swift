import XCTest
@testable import RiftletApp

@MainActor
final class SelectionSubmissionQueueTests: XCTestCase {
    func testSuspendedFirstPermissionCannotLetLaterSelectionOvertake() async {
        let queue = SelectionSubmissionQueue()
        var events: [String] = []
        var release: CheckedContinuation<Void, Never>?
        let a = queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            events.append("A.begin")
            await withCheckedContinuation { release = $0 }
            events.append("A.end")
        }
        let b = queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in events.append("B.begin") }
        XCTAssertEqual(a, 0); XCTAssertEqual(b, 1)
        for _ in 0..<100 where release == nil { await Task.yield() }
        XCTAssertEqual(events, ["A.begin"])
        release?.resume()
        for _ in 0..<100 where events.count < 3 { await Task.yield() }
        XCTAssertEqual(events, ["A.begin", "A.end", "B.begin"])
    }

    func testCancellationOnlyRemovesOriginalIDAndQueueHasFiniteCapacity() async {
        let queue = SelectionSubmissionQueue()
        var release: CheckedContinuation<Void, Never>?
        var ran: [UUID] = [], cancelled: [UUID] = []
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            await withCheckedContinuation { release = $0 }
        }
        for _ in 0..<100 where release == nil { await Task.yield() }
        let ids = (0..<15).map { _ in UUID() }
        for id in ids {
            XCTAssertNotNil(queue.enqueue(selectionID: id, deadline: nil,
                cancelled: { cancelled.append(id) }, run: { _ in ran.append(id) }))
        }
        XCTAssertNil(queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}, run: { _ in XCTFail() }))
        queue.cancel(selectionIDs: [ids[0]])
        queue.cancel(selectionIDs: [ids[0]])
        XCTAssertEqual(cancelled, [ids[0]])
        release?.resume()
        for _ in 0..<100 where ran.count < 14 { await Task.yield() }
        XCTAssertEqual(ran, Array(ids.dropFirst()))
    }

    func testUnsubmittedDeadlineExpiresWithoutRunningAndReleasesItsOwnReservation() async throws {
        let queue = SelectionSubmissionQueue()
        var release: CheckedContinuation<Void, Never>?
        var cancelled = false, ran = false
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            await withCheckedContinuation { release = $0 }
        }
        for _ in 0..<100 where release == nil { await Task.yield() }
        queue.enqueue(selectionID: UUID(), deadline: ProcessInfo.processInfo.systemUptime + 0.01,
            cancelled: { cancelled = true }, run: { _ in ran = true })
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(cancelled); XCTAssertFalse(ran)
        release?.resume()
        await Task.yield()
        XCTAssertFalse(ran)
    }
}
