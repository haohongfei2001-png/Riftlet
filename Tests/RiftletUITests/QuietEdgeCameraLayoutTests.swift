import XCTest
@testable import RiftletUI

final class QuietEdgeCameraLayoutTests: XCTestCase {
    func testRailAvoidsQueueAtEitherEdgeWithoutMovingInputs() throws {
        for left in [true, false] {
            let screen = CGRect(x: -800, y: -200, width: 800, height: 700)
            let x: CGFloat = left ? -794 : -6
            let input = CGRect(x: left ? x : x - 90, y: 300, width: 90, height: 56)
            let original = input
            let layout = try XCTUnwrap(ScreenshotEntryLayout.avoidingInputs(
                screenFrame: screen, visibleFrame: screen,
                anchor: CGPoint(x: x, y: 330), inputs: [input]))
            XCTAssertFalse(layout.railFrame.insetBy(dx: -12, dy: -12).intersects(input))
            XCTAssertTrue(screen.contains(layout.railFrame))
            XCTAssertEqual(input, original)
            XCTAssertEqual(layout.controlFrames.count, 4)
        }
    }
    func testFoldedTopCameraDoesNotReserveExpandedRail() throws {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = CGPoint(x: 24, y: 770)
        let folded = try XCTUnwrap(ScreenshotEntryLayout.avoidingInputs(screenFrame: frame,
            visibleFrame: frame, anchor: anchor, inputs: [], expanded: false))
        XCTAssertEqual(folded.anchor.y, anchor.y)
        XCTAssertEqual(folded.entryFrame.minX, ScreenshotEntryConfiguration().screenPadding)
        XCTAssertEqual(folded.railFrame.height, 36)
        let expanded = try XCTUnwrap(ScreenshotEntryLayout.avoidingInputs(screenFrame: frame,
            visibleFrame: frame, anchor: anchor, inputs: [], expanded: true))
        XCTAssertTrue(frame.contains(expanded.railFrame))
        XCTAssertEqual(expanded.railFrame.height, 132)
    }
    func testNoSpaceKeepsQueueAndReturnsNoCamera() {
        let frame = CGRect(x: 0, y: 0, width: 90, height: 180)
        XCTAssertNil(ScreenshotEntryLayout.avoidingInputs(screenFrame: frame, visibleFrame: frame,
            anchor: CGPoint(x: 45, y: 80), inputs: [frame]))
    }
    func testArrowAndNumberAreCollisionObstacles() throws {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let inputs = [CGRect(x: 6, y: 500, width: 24, height: 24),
                      CGRect(x: 10, y: 400, width: 22, height: 24)]
        let l = try XCTUnwrap(ScreenshotEntryLayout.avoidingInputs(screenFrame: frame,
            visibleFrame: frame, anchor: CGPoint(x: 24, y: 480), inputs: inputs))
        XCTAssertTrue(inputs.allSatisfy { !l.railFrame.insetBy(dx: -12, dy: -12).intersects($0) })
    }
}
