import XCTest
@testable import RiftletUI

final class RiftPeekGeometryTests: XCTestCase {
    func testPortraitPreviewClearsWiderNeighborWithoutChangingOwnerCenter() throws {
        // The independently observed portrait case covered a neighboring number
        // pad at x=926 even though the hovered portrait began farther right.
        let owner = CGRect(x: 966, y: 360, width: 44, height: 56)
        let frame = try XCTUnwrap(RiftPeekGeometry.frame(imageSize: CGSize(width: 120, height: 1000),
            owner: owner, visible: CGRect(x: 0, y: 59, width: 1024, height: 684), leadingInputEdge: 926))
        XCTAssertEqual(frame.maxX, 914, accuracy: 0.001)
        XCTAssertEqual(frame.midY, owner.midY, accuracy: 0.001)
        XCTAssertFalse(frame.intersects(CGRect(x: 926, y: 316, width: 22, height: 24)))
        XCTAssertEqual((frame.width - 16) / (frame.height - 16), 0.12, accuracy: 0.00001)
    }

    func testNegativeDisplayOriginKeepsFullPreviewInsideScreenAndAwayFromAllInputs() throws {
        let visible = CGRect(x: -1200, y: -200, width: 1200, height: 900)
        let owner = CGRect(x: -60, y: 600, width: 46, height: 56)
        let frame = try XCTUnwrap(RiftPeekGeometry.frame(imageSize: CGSize(width: 1800, height: 160),
            owner: owner, visible: visible, leadingInputEdge: -100))
        XCTAssertEqual(frame.maxX, -112, accuracy: 0.001)
        XCTAssertTrue(visible.insetBy(dx: 12, dy: 12).contains(frame))
        XCTAssertEqual((frame.width - 16) / (frame.height - 16), 11.25, accuracy: 0.00001)
    }

    func testNarrowScreenFitsFullAspectRatioAndNoSpaceCancelsWithoutCoveringInputs() throws {
        let visible = CGRect(x: 0, y: 0, width: 360, height: 700)
        let owner = CGRect(x: 300, y: 300, width: 46, height: 56)
        let frame = try XCTUnwrap(RiftPeekGeometry.frame(imageSize: CGSize(width: 1800, height: 160),
            owner: owner, visible: visible, leadingInputEdge: 110))
        XCTAssertEqual(frame.minX, 12, accuracy: 0.001)
        XCTAssertEqual(frame.maxX, 98, accuracy: 0.001)
        XCTAssertEqual(frame.midY, owner.midY, accuracy: 0.001)
        XCTAssertEqual((frame.width - 16) / (frame.height - 16), 11.25, accuracy: 0.00001)
        XCTAssertNil(RiftPeekGeometry.frame(imageSize: CGSize(width: 1800, height: 160),
            owner: owner, visible: visible, leadingInputEdge: 40))
        XCTAssertNil(RiftPeekGeometry.frame(imageSize: .zero, owner: owner,
            visible: visible, leadingInputEdge: 110))
    }
}
