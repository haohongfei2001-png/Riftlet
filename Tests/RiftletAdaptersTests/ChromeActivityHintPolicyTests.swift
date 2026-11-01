import XCTest
@testable import RiftletAdapters

final class ChromeActivityHintPolicyTests: XCTestCase {
    func testFocusedWindowChangeRevokesOldACKButAmbiguousTitleOnlyRearms() {
        XCTAssertTrue(ChromeActivityHintPolicy.invalidatesTarget("chromeWindow"))
        XCTAssertFalse(ChromeActivityHintPolicy.invalidatesTarget("chromeTitle"))
        XCTAssertFalse(ChromeActivityHintPolicy.invalidatesTarget("chromeFocus"))
        XCTAssertFalse(ChromeActivityHintPolicy.invalidatesTarget("chromeWindowCreated"))
    }

    func testCoalescedFocusCannotEraseWindowChangeBeforeInvalidation() {
        let notice = ChromeActivityHintPolicy.coalesce(
            previous: ChromeActivityHintPolicy.coalesce(previous: nil, incoming: "chromeWindow"),
            incoming: "chromeFocus")
        XCTAssertEqual(notice, "chromeWindow")
        XCTAssertTrue(ChromeActivityHintPolicy.invalidatesTarget(notice))
    }

    func testWindowChangeSurvivesTitleFocusAndWindowCreatedBurst() {
        let first = ChromeActivityHintPolicy.coalesce(previous: nil, incoming: "chromeWindow")
        let second = ChromeActivityHintPolicy.coalesce(previous: first, incoming: "chromeTitle")
        let third = ChromeActivityHintPolicy.coalesce(previous: second, incoming: "chromeFocus")
        let fourth = ChromeActivityHintPolicy.coalesce(previous: third, incoming: "chromeWindowCreated")
        XCTAssertEqual(fourth, "chromeWindow")
        XCTAssertTrue(ChromeActivityHintPolicy.invalidatesTarget(fourth))
    }

    func testOrdinaryEditorFocusDoesNotDiscardUnchangedTarget() {
        let note = ChromeActivityHintPolicy.coalesce(previous: "chromeWindowCreated", incoming: "chromeFocus")
        XCTAssertEqual(note, "chromeFocus")
        XCTAssertFalse(ChromeActivityHintPolicy.invalidatesTarget(note))
    }

    func testTwoDistinctTargetChangesCannotBeLostToFocusBurst() {
        let initial = ChromeActivityHintPolicy.coalesce(previous: "chromeWindow", incoming: "chromeFocus")
        let latest = ChromeActivityHintPolicy.coalesce(previous: initial, incoming: "chromeTitle")
        XCTAssertEqual(latest, "chromeWindow")
        XCTAssertTrue(ChromeActivityHintPolicy.invalidatesTarget(latest))
    }
}
