import XCTest
@testable import RiftletUI

final class RiftPointerApproachTests: XCTestCase {
    func testTrackingRebuildAndImageNumberNotificationsDoNotRepeatApproach() {
        var state = RiftPointerApproachState()
        let id = UUID()
        state.update(hovered: [id])
        XCTAssertTrue(state.enter(id))
        // Geometry refresh and duplicate enter from either island preserve one residence.
        for _ in 0..<5 {
            state.update(hovered: [id])
            XCTAssertFalse(state.enter(id))
        }
    }

    func testActualDepartureAndReentryAllowFreshApproach() {
        var state = RiftPointerApproachState()
        let id = UUID()
        state.update(hovered: [id]); XCTAssertTrue(state.enter(id))
        state.update(hovered: [])
        XCTAssertFalse(state.enter(id)) // Stale AppKit notification after departure.
        state.update(hovered: [id]); XCTAssertTrue(state.enter(id))
    }

    func testRemovalReplacementAndHiddenQueueDoNotCarryApproachToAnotherAsset() {
        var state = RiftPointerApproachState()
        let a = UUID(), b = UUID()
        state.update(hovered: [a]); XCTAssertTrue(state.enter(a))
        state.update(hovered: [b])
        XCTAssertFalse(state.enter(a)); XCTAssertTrue(state.enter(b))
        state.update(hovered: [])
        state.update(hovered: [b]); XCTAssertTrue(state.enter(b))
    }
}
