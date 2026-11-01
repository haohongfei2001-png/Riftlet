import XCTest
import RiftletCore
import RiftletAdapters

/// Deterministic boundary test: an AX target-change hint never authorizes a
/// new target and cannot let the previously acknowledged page pass a click.
final class ChromeActivityInvalidationTests: XCTestCase {
    func testTargetChangeRevokesOldACKAndRejectsInflightPublication() throws {
        var scheduler = TargetArmScheduler()
        XCTAssertTrue(scheduler.start())
        let first = try XCTUnwrap(scheduler.begin())
        let target = TargetLease(
            adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "kernel-session",
            windowID: "7", tabID: "9", documentID: "doc-1",
            composerID: "composer-1", draftGeneration: "draft-1")
        let old = ArmedTarget(target: target, acknowledgedUptime: 10, hostSession: first.epoch)
        XCTAssertNotNil(old.freeze(eventUptime: 11, nowUptime: 11,
                                   hostSession: first.epoch, foregroundSession: target.sessionID))

        let notice = ChromeActivityHintPolicy.coalesce(previous: "chromeWindow", incoming: "chromeFocus")
        XCTAssertTrue(ChromeActivityHintPolicy.invalidatesTarget(notice))
        XCTAssertFalse(scheduler.request(invalidateEpoch: true))
        XCTAssertNil(old.freeze(eventUptime: 12, nowUptime: 12,
                                hostSession: scheduler.epoch, foregroundSession: target.sessionID))
        let done = try XCTUnwrap(scheduler.complete(first))
        XCTAssertFalse(done.acceptsAcknowledgement)
        XCTAssertTrue(done.shouldWake)
        let replacement = try XCTUnwrap(scheduler.begin())
        XCTAssertNotEqual(replacement.epoch, first.epoch)
    }

    func testEditorFocusAloneRetainsValidTargetWithoutAFalseEpochChange() throws {
        var scheduler = TargetArmScheduler()
        XCTAssertTrue(scheduler.start())
        let first = try XCTUnwrap(scheduler.begin())
        XCTAssertFalse(ChromeActivityHintPolicy.invalidatesTarget("chromeFocus"))
        XCTAssertFalse(scheduler.request(invalidateEpoch: false))
        XCTAssertEqual(scheduler.epoch, first.epoch)
        XCTAssertTrue(try XCTUnwrap(scheduler.complete(first)).acceptsAcknowledgement)
    }
}
