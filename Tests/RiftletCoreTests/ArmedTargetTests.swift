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
}
