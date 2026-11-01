import Foundation
import XCTest
@testable import RiftletAdapters

final class CaptureReadPriorityTests: XCTestCase {
    private func envelope() -> MainWorldCommandEnvelope {
        .init(function: "function(){return {valid:true}}", commandJSON: "{}", contextJSON: "{}")
    }

    func testEnqueuedOldCaptureCannotStartOrPublishAfterClickButFreshDiscoveryCan() throws {
        let priority = CaptureReadPriority(), old = priority.ticket()
        priority.supersede()
        var published = false
        XCTAssertThrowsError(try old.check()) { XCTAssertEqual($0 as? WebAdapterError, .captureSuperseded) }
        XCTAssertThrowsError(try old.whileCurrent { published = true })
        XCTAssertFalse(published)
        let fresh = priority.ticket()
        try fresh.whileCurrent { published = true }
        XCTAssertTrue(published)
    }

    func testClickEndsEmptyCapturePollingBeforeOneSecondWithoutAnotherSend() throws {
        let priority = CaptureReadPriority(), ticket = priority.ticket()
        var now: TimeInterval = 10, reads = 0
        XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { now }, sleep: {
            now += $0; priority.supersede()
        }, checkContinuation: { try ticket.check() }) { _ in reads += 1; return "" }) {
            XCTAssertEqual($0 as? WebAdapterError, .captureSuperseded)
        }
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(now, 10.02, accuracy: 0.000001)
    }

    func testLateValidCaptureReplyCannotPublishAfterClick() throws {
        let priority = CaptureReadPriority(), ticket = priority.ticket(), e = envelope()
        var now: TimeInterval = 20, reads = 0
        let reply = "{\"nonce\":\"\(e.nonce)\",\"ok\":true,\"result\":{\"valid\":true}}"
        XCTAssertThrowsError(try MainWorldReceiptReader.read(e, clock: { now },
            checkContinuation: { try ticket.check() }) { _ in
            reads += 1; priority.supersede(); now += 0.2; return reply
        }) { XCTAssertEqual($0 as? WebAdapterError, .captureSuperseded) }
        XCTAssertEqual(reads, 1)
    }

    func testInFlightReadTimeoutReturnsWithoutRetryAfterSupersession() throws {
        let priority = CaptureReadPriority(), ticket = priority.ticket()
        var now: TimeInterval = 30, reads = 0
        XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { now },
            checkContinuation: { try ticket.check() }) { budget in
            reads += 1; priority.supersede(); now += try budget.timeout(at: now)
            throw WebAdapterError.nativeEventFailed(-1712)
        }) { XCTAssertEqual($0 as? WebAdapterError, .captureSuperseded) }
        XCTAssertEqual(reads, 1); XCTAssertEqual(now, 30.25)
    }

    func testInputReceiptIsUnaffectedAndNeverResubmittedByCapturePriority() throws {
        let priority = CaptureReadPriority(), e = envelope()
        var now: TimeInterval = 40, reads = 0
        let reply = "{\"nonce\":\"\(e.nonce)\",\"ok\":true,\"result\":{\"inputCount\":1}}"
        let receipt = try MainWorldReceiptReader.read(e, clock: { now }, sleep: { now += $0 }) { _ in
            reads += 1; priority.supersede()
            return reads == 1 ? "" : reply
        }
        XCTAssertEqual(reads, 2)
        XCTAssertTrue(receipt.text.contains("inputCount"))
    }

    func testSerialQueueSkipsObsoleteCapturesBeforePinnedInputWithoutParallelInput() throws {
        let priority = CaptureReadPriority(), queue = DispatchQueue(label: "capture-priority-test")
        let reading = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let done = expectation(description: "serial queue drained")
        let first = priority.ticket()
        // Events are written/read only on this serial queue.
        var events: [String] = []
        queue.async {
            reading.signal(); release.wait()
            do { try first.check(); events.append("stale-published") }
            catch { events.append("stale-stopped") }
        }
        XCTAssertEqual(reading.wait(timeout: .now()+2), .success)
        let queued = priority.ticket()
        queue.async {
            do { try queued.check(); events.append("obsolete-started") }
            catch { events.append("queued-skipped") }
        }
        priority.supersede() // Original pinned input is about to enqueue.
        queue.async { events.append("input-once") }
        let fresh = priority.ticket()
        queue.async {
            do { try fresh.check(); events.append("fresh-capture") } catch { events.append("fresh-failed") }
            XCTAssertEqual(events, ["stale-stopped", "queued-skipped", "input-once", "fresh-capture"])
            done.fulfill()
        }
        release.signal()
        wait(for: [done], timeout: 3)
    }
}
