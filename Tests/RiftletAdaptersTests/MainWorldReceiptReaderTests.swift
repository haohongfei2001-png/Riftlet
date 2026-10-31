import Foundation
import XCTest
@testable import RiftletAdapters

final class MainWorldReceiptReaderTests: XCTestCase {
    private func envelope() -> MainWorldCommandEnvelope {
        MainWorldCommandEnvelope(function: "function(){return {valid:true}}", commandJSON: "{}", contextJSON: "{}")
    }

    private func reply(_ envelope: MainWorldCommandEnvelope) throws -> String {
        let value: [String: Any] = ["nonce": envelope.nonce, "ok": true, "result": ["valid": true]]
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    func testImmediateReplyPreservesReceiveTimeWithoutPolling() throws {
        let command = envelope(), raw = try reply(command)
        var now: TimeInterval = 10, reads = 0, sleeps = 0
        let received = try MainWorldReceiptReader.read(command, clock: { now }, sleep: { _ in sleeps += 1 }) { budget in
            reads += 1
            XCTAssertEqual(budget.deadlineUptime, 11)
            XCTAssertEqual(try budget.timeout(at: now), 0.25)
            now += 0.04
            return raw
        }
        XCTAssertEqual(received.text, try command.decode(raw))
        XCTAssertEqual(received.receivedUptime, 10.04, accuracy: 0.000001)
        XCTAssertEqual(reads, 1); XCTAssertEqual(sleeps, 0)
    }

    func testEmptyReceiptPollsWithinOriginalBudget() throws {
        let command = envelope(), raw = try reply(command)
        var now: TimeInterval = 10, reads = 0, sleeps: [TimeInterval] = []
        let received = try MainWorldReceiptReader.read(command, clock: { now }, sleep: { sleeps.append($0); now += $0 }) { budget in
            reads += 1
            XCTAssertEqual(budget.deadlineUptime, 11)
            XCTAssertEqual(try budget.timeout(at: now), 0.25)
            return reads == 1 ? "" : raw
        }
        XCTAssertEqual(received.text, try command.decode(raw))
        XCTAssertEqual(received.receivedUptime, 10.02, accuracy: 0.000001)
        XCTAssertEqual(reads, 2); XCTAssertEqual(sleeps, [0.02])
    }

    func testRepeatedReadTimeoutsCannotExtendOneSecondOrStartAFifthRead() throws {
        let command = envelope()
        var now: TimeInterval = 10, timeouts: [TimeInterval] = [], sleeps: [TimeInterval] = []
        XCTAssertThrowsError(try MainWorldReceiptReader.read(command, clock: { now }, sleep: { sleeps.append($0); now += $0 }) { budget in
            let timeout = try budget.timeout(at: now)
            timeouts.append(timeout); now += timeout
            throw WebAdapterError.nativeEventFailed(-1712)
        }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
        XCTAssertEqual(timeouts.count, 4); XCTAssertEqual(sleeps, [0.02, 0.02, 0.02])
        for timeout in timeouts.prefix(3) { XCTAssertEqual(timeout, 0.25) }
        XCTAssertEqual(try XCTUnwrap(timeouts.last), 0.19, accuracy: 0.000001)
        XCTAssertEqual(now, 11, accuracy: 0.000001)
    }

    func testOnlyReadTimeoutIsRecoverableAndOtherErrorsLeaveImmediately() {
        let errors: [WebAdapterError] = [
            .nativeEventFailed(-1743), // Automation permission denied.
            .nativeEventFailed(-1708), // Event unsupported.
            .nativeEventFailed(-1728), // Original target object missing.
            .nativeEventFailed(-609), .nativeEventFailed(-1711),
            .nativeSelectionChanged, .browserNotFrontmost, .invalidTarget,
            .nativeExecutionFailed, .invalidReply, .pageRejected(.unsupportedSurface)
        ]
        for expected in errors {
            var reads = 0, sleeps = 0
            XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { 10 }, sleep: { _ in sleeps += 1 }) { _ in
                reads += 1; throw expected
            }) { XCTAssertEqual($0 as? WebAdapterError, expected) }
            XCTAssertEqual(reads, 1); XCTAssertEqual(sleeps, 0)
        }
    }

    func testPermissionFailureAfterOneTimeoutDoesNotReadAgain() {
        var now: TimeInterval = 10, reads = 0, sleeps = 0
        XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { now }, sleep: { now += $0; sleeps += 1 }) { budget in
            reads += 1
            if reads == 1 { now += try budget.timeout(at: now); throw WebAdapterError.nativeEventFailed(-1712) }
            throw WebAdapterError.nativeEventFailed(-1743)
        }) { XCTAssertEqual($0 as? WebAdapterError, .nativeEventFailed(-1743)) }
        XCTAssertEqual(reads, 2); XCTAssertEqual(sleeps, 1)
    }

    func testUnclassifiedErrorNeverBecomesRecoverableTimeout() {
        enum FixtureError: Error { case unrelated }
        var reads = 0, sleeps = 0
        XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { 10 }, sleep: { _ in sleeps += 1 }) { _ in
            reads += 1; throw FixtureError.unrelated
        }) { XCTAssertTrue($0 is FixtureError) }
        XCTAssertEqual(reads, 1); XCTAssertEqual(sleeps, 0)
    }

    func testNonemptyWrongNonceSchemaAndPageRejectionsNeverPoll() throws {
        let command = envelope(), other = envelope()
        let cases: [(String, WebAdapterError)] = [
            (try reply(other), .invalidReply), ("not-json", .invalidReply),
            ("{}", .invalidReply), ("[]", .invalidReply),
            (#"{"nonce":"\#(command.nonce)","ok":true,"result":{},"extra":1}"#, .invalidReply),
            (#"{"nonce":"\#(command.nonce)","ok":false,"rejection":"COMPOSER_UNAVAILABLE"}"#, .pageRejected(.composerUnavailable))
        ]
        for (raw, expected) in cases {
            var reads = 0, sleeps = 0
            XCTAssertThrowsError(try MainWorldReceiptReader.read(command, clock: { 10 }, sleep: { _ in sleeps += 1 }) { _ in
                reads += 1; return raw
            }) { XCTAssertEqual($0 as? WebAdapterError, expected) }
            XCTAssertEqual(reads, 1); XCTAssertEqual(sleeps, 0)
        }
    }

    func testEvenValidReplyAtOrAfterDeadlineCannotReturn() throws {
        let command = envelope(), raw = try reply(command)
        for end in [11.0, 11.001, 15] {
            var now: TimeInterval = 10, reads = 0, sleeps = 0
            XCTAssertThrowsError(try MainWorldReceiptReader.read(command, clock: { now }, sleep: { _ in sleeps += 1 }) { _ in
                reads += 1; now = end; return raw
            }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
            XCTAssertEqual(reads, 1); XCTAssertEqual(sleeps, 0)
        }
    }

    func testTimeSpentDecodingAlsoCannotReturnPastDeadline() throws {
        let command = envelope(), raw = try reply(command)
        var clockReads = 0, reads = 0, sleeps = 0
        let clock: () -> TimeInterval = {
            clockReads += 1
            // Start, before fetch, receipt arrival, then after decode.
            return [10, 10, 10.5, 11][min(clockReads - 1, 3)]
        }
        XCTAssertThrowsError(try MainWorldReceiptReader.read(command, clock: clock, sleep: { _ in sleeps += 1 }) { _ in
            reads += 1; return raw
        }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
        XCTAssertEqual(reads, 1); XCTAssertEqual(sleeps, 0)
    }

    func testFinalSleepIsClampedAndNoReadStartsAfterIt() {
        var now: TimeInterval = 10, reads = 0, sleeps: [TimeInterval] = []
        XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { now }, sleep: { sleeps.append($0); now += $0 }) { _ in
            reads += 1; now = 10.99; return ""
        }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
        XCTAssertEqual(reads, 1); XCTAssertEqual(sleeps.count, 1)
        XCTAssertEqual(sleeps.first ?? -1, 0.01, accuracy: 0.000001)
        XCTAssertEqual(now, 11)
    }

    func testSchedulerOversleepCannotStartAnotherRead() {
        var now: TimeInterval = 10, reads = 0
        XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { now }, sleep: { _ in now = 11.5 }) { _ in
            reads += 1; return ""
        }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
        XCTAssertEqual(reads, 1)
    }

    func testStoppedClockStillHasFiniteReadBound() {
        for timeout in [false, true] {
            var reads = 0, sleeps = 0
            XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { 10 }, sleep: { _ in sleeps += 1 }) { _ in
                reads += 1
                if timeout { throw WebAdapterError.nativeEventFailed(-1712) }
                return ""
            }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
            XCTAssertEqual(reads, 50); XCTAssertEqual(sleeps, 49)
        }
    }

    func testInvalidAndBackwardClocksCannotAuthorizeReply() throws {
        for start in [TimeInterval.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude] {
            var reads = 0
            XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: { start }, sleep: { _ in }) { _ in
                reads += 1; return ""
            }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
            XCTAssertEqual(reads, 0)
        }
        let command = envelope(), raw = try reply(command)
        var now: TimeInterval = 10, reads = 0
        XCTAssertThrowsError(try MainWorldReceiptReader.read(command, clock: { now }, sleep: { _ in }) { _ in
            reads += 1; now = 9; return raw
        }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
        XCTAssertEqual(reads, 1)
    }

    func testActualSendBudgetRechecksTimeAfterDescriptorConstruction() throws {
        let budget = MainWorldReceiptReadBudget(deadlineUptime: 11)
        XCTAssertEqual(try budget.timeout(at: 10), 0.25)
        XCTAssertEqual(try budget.timeout(at: 10.9), 0.1, accuracy: 0.000001)
        XCTAssertEqual(try budget.timeout(at: 10.95), 0.05, accuracy: 0.000001)
        for now in [TimeInterval.nan, .infinity, -.infinity, -1, 10.951, 10.999, 11, 11.01] {
            XCTAssertThrowsError(try budget.timeout(at: now)) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
        }
    }

    func testInsufficientPositiveBudgetRefusesBeforeCallingFetch() {
        var clockReads = 0, reads = 0, sleeps = 0
        XCTAssertThrowsError(try MainWorldReceiptReader.read(envelope(), clock: {
            clockReads += 1; return clockReads == 1 ? 10 : 10.96
        }, sleep: { _ in sleeps += 1 }) { _ in
            reads += 1; return ""
        }) { XCTAssertEqual($0 as? WebAdapterError, .invalidReply) }
        XCTAssertEqual(reads, 0); XCTAssertEqual(sleeps, 0)
    }
}
