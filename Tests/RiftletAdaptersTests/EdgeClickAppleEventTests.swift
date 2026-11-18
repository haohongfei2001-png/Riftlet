import Carbon
import Foundation
import XCTest
@testable import RiftletAdapters

final class EdgeClickAppleEventTests: XCTestCase {
    func test624RemainingWindowSendsOneNoninteractiveAppleEventWithTwoWholeTicks() throws {
        let budget = EdgeClickAppleEvent(deadlineUptime: 1)
        var sent = 0
        let value = NSAppleEventDescriptor(string: "bound")
        let reply = try budget.send(.null(), uptime: { 0.9505 }) { _, reply, mode, ticks in
            sent += 1
            XCTAssertEqual(ticks, 2)
            XCTAssertEqual(mode, AESendMode(kAEWaitReply | kAENeverInteract))
            return OSStatus(AEDuplicateDesc(value.aeDesc, reply))
        }
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(reply.stringValue, "bound")
    }

    func testNoZeroSpecialOrExpiredTimeoutIsSent() {
        let budget = EdgeClickAppleEvent(deadlineUptime: 1)
        for now: TimeInterval in [0.984, 1, 2, .infinity, .nan] {
            XCTAssertThrowsError(try budget.send(.null(), uptime: { now }) { _, _, _, _ in
                XCTFail("A sub-tick or expired deadline must stop before sending")
                return noErr
            }) { XCTAssertEqual($0 as? WebAdapterError, .nativeEventFailed(OSStatus(errAETimeout))) }
        }
    }

    func testLateReplyIsRejectedAndSystemErrorsArePreservedWithoutResend() {
        let budget = EdgeClickAppleEvent(deadlineUptime: 1)
        var now = 0.9505
        var sends = 0
        XCTAssertThrowsError(try budget.send(.null(), uptime: { now }) { _, reply, _, _ in
            sends += 1
            now = 1
            return OSStatus(AEDuplicateDesc(NSAppleEventDescriptor.null().aeDesc, reply))
        }) { XCTAssertEqual($0 as? WebAdapterError, .nativeEventFailed(OSStatus(errAETimeout))) }
        XCTAssertEqual(sends, 1)
        for status: OSStatus in [-1743, -1712, -600] {
            var count = 0
            XCTAssertThrowsError(try budget.send(.null(), uptime: { 0.9505 }) { _, _, _, _ in
                count += 1
                return status
            }) { XCTAssertEqual($0 as? WebAdapterError, .nativeEventFailed(status)) }
            XCTAssertEqual(count, 1)
        }
    }
}
