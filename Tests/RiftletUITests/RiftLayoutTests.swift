import XCTest
import RiftletCore
@testable import RiftletUI

final class RiftLayoutTests: XCTestCase {
    func testObservedClearPaddingCannotBeginOrCompleteSelection() {
        // Actual helper CLEAR local point (1.5, 2) in the first 44-point row.
        let row = RiftRowLayout(assetID: UUID(), ordinal: 1,
            frame: CGRect(x: 1840, y: 878, width: 71.15, height: 44),
            imageFrame: CGRect(x: 17.15, y: 0, width: 72, height: 44),
            imageClipFrame: CGRect(x: 17.15, y: 0, width: 54, height: 44),
            numberFrame: CGRect(x: 4, y: 15.5, width: 7.15, height: 13))
        let clear = CGPoint(x: 1.5, y: 2)
        let image = CGPoint(x: 44.15, y: 22)
        let number = CGPoint(x: 7.575, y: 22)
        XCTAssertFalse(row.containsSelectionPoint(clear))
        XCTAssertFalse(row.containsSelectionPoint(CGPoint(x: 14, y: 22)), "Number/image gap is not a selection")
        XCTAssertFalse(row.containsSelectionPoint(CGPoint(x: 80, y: 22)), "Clipped image remainder is not a selection")
        var gate = PointerSelectionGate()
        XCTAssertFalse(gate.begin(assetID: row.assetID, screenPoint: clear, timestamp: 1,
            clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: row.containsSelectionPoint(clear)))
        XCTAssertNil(gate.end(inside: row.containsSelectionPoint(image)), "Padding down cannot become a click on release")
        for (index, point) in [image, number].enumerated() {
            XCTAssertTrue(row.containsSelectionPoint(point))
            XCTAssertTrue(gate.begin(assetID: row.assetID, screenPoint: point, timestamp: Double(index + 3),
                clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: row.containsSelectionPoint(point)))
            XCTAssertEqual(gate.end(inside: row.containsSelectionPoint(point)), row.assetID)
        }
        XCTAssertTrue(gate.begin(assetID: row.assetID, screenPoint: image, timestamp: 6,
            clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: row.containsSelectionPoint(image)))
        XCTAssertNil(gate.end(inside: row.containsSelectionPoint(clear)), "Release in padding must cancel the original hold")
        XCTAssertFalse(gate.isHolding)
    }

    private func records(_ count: Int, width: Int = 900, height: Int = 1_200) -> [AssetRecord] {
        (0..<count).map { index in
            let id = UUID()
            return AssetRecord(image: ImportedAsset(
                id: id, sourceKey: "synthetic-\(index)", fileName: "\(id.uuidString).png",
                sha256: String(repeating: "a", count: 64), byteCount: 100,
                pixelWidth: width, pixelHeight: height, mediaType: "image/png", origin: .synthetic),
                sequence: Int64(index + 1))
        }
    }

    func testAspectRatioAndOcclusionDoNotStretchImage() {
        let result = RiftLayout.make(records: records(1, width: 1_920, height: 1_080),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                     configuration: .init())
        let row = result.rows[0]
        XCTAssertEqual(row.imageFrame.width / row.imageFrame.height, 1_920.0 / 1_080.0, accuracy: 0.0001)
        XCTAssertEqual(row.imageClipFrame.width, row.imageFrame.width * 0.75, accuracy: 0.0001)
        XCTAssertEqual(row.frame.maxX, 1_426)
        XCTAssertEqual(row.imageClipFrame.maxX, row.frame.width)
    }

    func testTwelvePortraitsPageBelowStableFirstSlotWithWindowFreeGaps() {
        let viewport = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let result = RiftLayout.make(records: records(12), visibleFrame: viewport, configuration: .init())
        XCTAssertEqual(result.rows.count, 11)
        XCTAssertEqual(result.rows.map(\.ordinal), Array(1...11))
        XCTAssertTrue(result.hasLater)
        XCTAssertTrue(viewport.contains(result.pagerFrame))
        XCTAssertEqual(result.rows.first?.frame.midY, viewport.maxY - 202)
        let shortQueue = RiftLayout.make(records: records(2), visibleFrame: viewport, configuration: .init())
        XCTAssertEqual(result.rows.first?.frame.midY, shortQueue.rows.first?.frame.midY)
        for row in result.rows { XCTAssertTrue(viewport.contains(row.frame)) }
        for pair in zip(result.rows, result.rows.dropFirst()) {
            XCTAssertGreaterThan(pair.0.frame.minY - pair.1.frame.maxY, 0)
        }
        XCTAssertTrue(viewport.contains(result.lineFrame))
    }

    func testExtremeAspectRatiosUseVisibleNumberPadsAndExactRetinaPlane() {
        let frame = CGRect(x: -800, y: -200, width: 800, height: 1280)
        for size in [(100, 800), (800, 100)] {
            let result = RiftLayout.make(records: records(1, width: size.0, height: size.1),
                visibleFrame: frame, configuration: .init(), backingScale: 2)
            let row = result.rows[0]
            XCTAssertTrue(row.numberIsPad)
            XCTAssertGreaterThanOrEqual(row.numberFrame.width, 22)
            XCTAssertEqual(row.numberFrame.height, 24)
            XCTAssertEqual(row.imageFrame.width / row.imageFrame.height, Double(size.0) / Double(size.1), accuracy: 0.00001)
            XCTAssertEqual(result.lineFrame.width, 0.5)
            XCTAssertEqual(row.frame.maxX, frame.maxX - 14)
            XCTAssertFalse(row.numberFrame.intersects(row.imageClipFrame))
        }
        let highContrast = RiftLayout.make(records: records(1), visibleFrame: frame,
            configuration: .init(), backingScale: 2, highContrast: true)
        XCTAssertEqual(highContrast.lineFrame.width, 1)
    }

    func testPagerCapacityAndPlaneDoNotMoveWhenSelectingLastPage() throws {
        let input = records(26), frame = CGRect(x: 1920, y: 0, width: 900, height: 740)
        let first = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init())
        let last = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init(), firstVisibleIndex: 999)
        let firstRow = try XCTUnwrap(first.rows.first)
        let lastPageRow = try XCTUnwrap(last.rows.first)
        // A two-digit ordinal extends its visible input island to the left.
        // The image and fixed plane must not move with that envelope change.
        XCTAssertGreaterThan(lastPageRow.numberFrame.width, firstRow.numberFrame.width)
        XCTAssertEqual(firstRow.frame.maxX, lastPageRow.frame.maxX)
        XCTAssertEqual(firstRow.frame.midY, lastPageRow.frame.midY)
        XCTAssertEqual(firstRow.imageClipFrame.offsetBy(dx: firstRow.frame.minX, dy: firstRow.frame.minY),
                       lastPageRow.imageClipFrame.offsetBy(dx: lastPageRow.frame.minX, dy: lastPageRow.frame.minY))
        XCTAssertEqual(first.lineFrame, last.lineFrame)
        XCTAssertEqual(first.capacity, last.capacity)
        XCTAssertEqual(lastPageRow.assetID, input[last.firstVisibleIndex].id)
        for row in first.rows + last.rows {
            XCTAssertTrue(frame.contains(row.frame))
            XCTAssertTrue(CGRect(origin: .zero, size: row.frame.size).contains(row.numberFrame))
            XCTAssertEqual(row.assetID, input[row.ordinal - 1].id)
        }
        XCTAssertEqual(last.rows.last?.ordinal, 26)
        XCTAssertFalse(last.hasLater)
        XCTAssertEqual(first.pagerFrame, last.pagerFrame)
        XCTAssertTrue(frame.contains(first.pagerFrame))
        XCTAssertLessThanOrEqual(first.pagerFrame.maxY + 8, first.rows.last!.frame.minY)
    }

    func testSmallDisplayKeepsAllItemsReachableWithoutOffscreenWindows() {
        let input = records(15)
        let viewport = CGRect(x: -1_280, y: 90, width: 1_280, height: 480)
        let first = RiftLayout.make(records: input, visibleFrame: viewport, configuration: .init())
        XCTAssertLessThan(first.capacity, input.count)
        XCTAssertTrue(first.hasLater)
        XCTAssertEqual(first.rows.first?.assetID, input.first?.id)
        let latest = RiftLayout.make(records: input, visibleFrame: viewport, configuration: .init(), firstVisibleIndex: 99)
        XCTAssertEqual(latest.rows.last?.assetID, input.last?.id)
        XCTAssertTrue(latest.hasEarlier)
        XCTAssertFalse(latest.hasLater)
        for row in first.rows + latest.rows { XCTAssertTrue(viewport.contains(row.frame)) }
        XCTAssertEqual(latest.totalCount, 15)
    }

    func testLegacyUsedFixtureDefaultsToSwallowedAndOrdinalsAreCurrentPositions() {
        let input = records(4)
        let changed = [input[0],
                       AssetRecord(image: input[1].image, sequence: input[1].sequence, status: .used),
                       AssetRecord(image: input[2].image, sequence: input[2].sequence, status: .unknown),
                       AssetRecord(image: input[3].image, sequence: input[3].sequence, status: .failed)]
        let result = RiftLayout.make(records: changed,
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                     configuration: .init())
        XCTAssertEqual(result.rows.map(\.assetID), [input[0].id, input[2].id, input[3].id])
        XCTAssertEqual(result.rows.map(\.ordinal), [1, 2, 3])
        XCTAssertEqual(changed[2].sequence, 3)
    }

    func testVisibleFailureUnknownAndTransferKeepOriginalGeometry() {
        let original = records(3)
        let viewport = CGRect(x: 1_920, y: -200, width: 1_440, height: 900)
        let baseline = RiftLayout.make(records: original, visibleFrame: viewport, configuration: .init())
        for status in [QueueStatus.transferring, .unknown, .failed, .missing] {
            let changed = original.map { AssetRecord(image: $0.image, sequence: $0.sequence, status: status) }
            XCTAssertEqual(RiftLayout.make(records: changed, visibleFrame: viewport, configuration: .init()), baseline)
        }
    }

    func testConfiguredDimensionsRemainAdjustableAndNeverOverlapRows() throws {
        var config = RiftConfiguration()
        config.fitWidth = 90; config.fitHeight = 70
        config.hiddenFraction = 0.35; config.rowPitch = 40
        try config.validate()
        let result = RiftLayout.make(records: records(12),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                     configuration: config)
        for pair in zip(result.rows, result.rows.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.frame.minY - pair.1.frame.maxY, 4)
        }
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(RiftConfiguration.self, from: data), config)
    }

    func testInvalidConfigurationRejected() {
        var config = RiftConfiguration(); config.hiddenFraction = 1
        XCTAssertThrowsError(try config.validate())
        config = RiftConfiguration(); config.fitWidth = .nan
        XCTAssertThrowsError(try config.validate())
        config = RiftConfiguration(); config.swallowDuration = -1
        XCTAssertThrowsError(try config.validate())
    }

    func testMouseUpReturnsIdentityCapturedAtMouseDown() {
        var gate = PointerSelectionGate()
        let first = UUID(), replacement = UUID()
        XCTAssertTrue(gate.begin(assetID: first, screenPoint: CGPoint(x: 1_410, y: 720),
                                 timestamp: 1, clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: true))
        XCTAssertFalse(gate.begin(assetID: replacement, screenPoint: CGPoint(x: 1_410, y: 720),
                                  timestamp: 1.1, clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: true))
        XCTAssertEqual(gate.end(inside: true), first)
        XCTAssertFalse(gate.isHolding)
    }

    func testDoubleClickCannotContinueOntoReplacementWindow() {
        var gate = PointerSelectionGate()
        let location = CGPoint(x: 1_410, y: 720)
        XCTAssertTrue(gate.begin(assetID: UUID(), screenPoint: location,
                                 timestamp: 1, clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: true))
        XCTAssertNotNil(gate.end(inside: true))
        // WindowServer may reset clickCount after the old row window is removed.
        XCTAssertFalse(gate.begin(assetID: UUID(), screenPoint: location,
                                  timestamp: 1.2, clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: true))
        XCTAssertFalse(gate.begin(assetID: UUID(), screenPoint: location,
                                  timestamp: 1.2, clickCount: 2, doubleClickInterval: 0.5, acceptsSelection: true))
        // A different row is still immediately usable.
        XCTAssertTrue(gate.begin(assetID: UUID(), screenPoint: CGPoint(x: 1_410, y: 660),
                                 timestamp: 1.2, clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: true))
    }

    func testOutsideMouseUpAndUnavailableRowsDoNotSelect() {
        var gate = PointerSelectionGate()
        XCTAssertFalse(gate.begin(assetID: UUID(), screenPoint: .zero,
                                  timestamp: 1, clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: false))
        XCTAssertNil(gate.end(inside: true))
        XCTAssertTrue(gate.begin(assetID: UUID(), screenPoint: .zero,
                                 timestamp: 2, clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: true))
        XCTAssertNil(gate.end(inside: false))
    }
}
