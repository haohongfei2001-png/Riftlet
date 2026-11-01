import XCTest
@testable import RiftletCore

final class ArmedTargetTests: XCTestCase {
    func testOnlyPreexistingSameSessionAcknowledgementCanFreeze() {
        let session = UUID()
        let target = TargetLease(adapterID: "test", surface: .webChat, applicationID: "chrome",
            sessionID: "process:launch", windowID: "w", tabID: "t", documentID: "d", composerID: "c", draftGeneration: "g")
        let arm = ArmedTarget(target: target, acknowledgedUptime: 10, hostSession: session)
        func freeze(_ event: Double, now: Double = 12, host: UUID? = nil, foreground: String? = "process:launch") -> TargetLease? {
            arm.freeze(eventUptime: event, nowUptime: now, hostSession: host ?? session, foregroundSession: foreground)
        }
        XCTAssertEqual(freeze(11), target)
        XCTAssertNil(freeze(9), "An ACK delivered after the original event cannot bind that click")
        XCTAssertNil(freeze(10))
        XCTAssertNil(freeze(13))
        XCTAssertNil(freeze(.nan)); XCTAssertNil(freeze(.infinity))
        XCTAssertNil(freeze(11, now: .nan))
        XCTAssertNil(freeze(11, host: UUID()))
        XCTAssertNil(freeze(11, foreground: nil))
        XCTAssertNil(freeze(11, foreground: "another:session"))
    }
    func testWindowSwitchDuringCaptureCannotPublishLateACKForOriginalClick() throws {
        var scheduler = TargetArmScheduler()
        scheduler.start()
        let a = try XCTUnwrap(scheduler.begin())
        let target = TargetLease(adapterID: "test", surface: .webChat, applicationID: "chrome",
            sessionID: "same-process", windowID: "A", tabID: "A", documentID: "doc-A",
            composerID: "editor-A", draftGeneration: "draft-A")
        // Same browser PID does not preserve a revoked host epoch. An old
        // capture returning after a switch must not bind an intervening click.
        scheduler.request(invalidateEpoch: true)
        XCTAssertFalse(try XCTUnwrap(scheduler.complete(a)).acceptsAcknowledgement)
        let late = ArmedTarget(target: target, acknowledgedUptime: 12, hostSession: a.epoch)
        XCTAssertNil(late.freeze(eventUptime: 11, nowUptime: 13,
            hostSession: scheduler.epoch, foregroundSession: "same-process"))
        let b = try XCTUnwrap(scheduler.begin())
        scheduler.request(invalidateEpoch: true) // A -> B -> A is not continuity.
        XCTAssertFalse(try XCTUnwrap(scheduler.complete(b)).acceptsAcknowledgement)
        XCTAssertNil(late.freeze(eventUptime: 14, nowUptime: 15,
            hostSession: scheduler.epoch, foregroundSession: "same-process"))
        let current = try XCTUnwrap(scheduler.begin())
        XCTAssertTrue(try XCTUnwrap(scheduler.complete(current)).acceptsAcknowledgement)
        let fresh = ArmedTarget(target: target, acknowledgedUptime: 16, hostSession: current.epoch)
        XCTAssertNil(fresh.freeze(eventUptime: 14, nowUptime: 17,
            hostSession: scheduler.epoch, foregroundSession: "same-process"), "No replay of old click")
        XCTAssertEqual(fresh.freeze(eventUptime: 17, nowUptime: 18,
            hostSession: scheduler.epoch, foregroundSession: "same-process"), target)
    }

}
