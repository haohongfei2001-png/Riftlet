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

    func testDeletedAnchorAndEarlierRemovalRetainFirstSurvivingDisplayedIdentity() {
        let ids = (0..<8).map { _ in UUID() }
        // Displayed D E F; A and D disappear in the same durable refresh.
        let current = [ids[1],ids[2],ids[4],ids[5],ids[6],ids[7]]
        XCTAssertEqual(RiftLayout.survivingAnchorIndex(previous:Array(ids[3...5]),current:current,fallback:3),2)
        XCTAssertEqual(current[2],ids[4])
        XCTAssertEqual(RiftLayout.pageStart(from:2,direction:1,totalCount:8,capacity:3),5)
    }

    func testPageMotionMovesOnlyVerticalGeometryAndRespectsReducedMotion() {
        let final = CGRect(x: -400, y: 200, width: 72, height: 56)
        let down = RiftPageTransition(direction: 1, reduceMotion: false)
        let up = RiftPageTransition(direction: -1, reduceMotion: false)
        XCTAssertEqual(down.duration,0.18)
        XCTAssertEqual(down.initialFrame(for:final),final.offsetBy(dx:0,dy:-24))
        XCTAssertEqual(up.initialFrame(for:final),final.offsetBy(dx:0,dy:24))
        let reduced=RiftPageTransition(direction:1,reduceMotion:true)
        XCTAssertEqual(reduced.duration,0.08)
        XCTAssertEqual(reduced.initialFrame(for:final),final)
    }

    func testAspectRatioAndOcclusionDoNotStretchImage() {
        let result = RiftLayout.make(records: records(1, width: 1_920, height: 1_080),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                     configuration: .init())
        let row = result.rows[0]
        XCTAssertEqual(row.imageFrame.width / row.imageFrame.height, 1_920.0 / 1_080.0, accuracy: 0.0001)
        XCTAssertEqual(row.imageClipFrame.width, row.imageFrame.width * 0.75, accuracy: 0.0001)
        XCTAssertEqual(row.frame.minX, 6)
        XCTAssertEqual(row.imageClipFrame.minX, 0)
    }

    func testTwelvePortraitsPageBelowStableFirstSlotWithWindowFreeGaps() {
        let viewport = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let result = RiftLayout.make(records: records(12), visibleFrame: viewport, configuration: .init())
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.rows.map(\.ordinal), Array(1...3))
        XCTAssertTrue(result.hasLater)
        XCTAssertTrue(viewport.contains(result.laterArrowFrame))
        XCTAssertEqual(result.rows.first?.frame.midY, viewport.midY + 60)
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
            XCTAssertEqual(row.frame.minX, frame.minX + 6)
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
        XCTAssertEqual(firstRow.frame.minX, lastPageRow.frame.minX)
        XCTAssertEqual(firstRow.frame.midY, lastPageRow.frame.midY)
        XCTAssertEqual(firstRow.imageClipFrame.offsetBy(dx: firstRow.frame.minX, dy: firstRow.frame.minY),
                       lastPageRow.imageClipFrame.offsetBy(dx: lastPageRow.frame.minX, dy: lastPageRow.frame.minY))
        XCTAssertEqual(first.lineFrame.minX, last.lineFrame.minX)
        XCTAssertEqual(first.lineFrame.width, last.lineFrame.width)
        XCTAssertEqual(first.lineFrame.maxY, last.lineFrame.maxY)
        XCTAssertEqual(last.lineFrame.minY, last.rows.last!.frame.minY + last.rows.last!.imageFrame.minY)
        XCTAssertEqual(last.firstVisibleIndex, ((input.count - 1) / first.capacity) * first.capacity)
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
        XCTAssertTrue(frame.contains(first.laterArrowFrame))
        XCTAssertLessThanOrEqual(first.laterArrowFrame.maxY + 8, first.rows.last!.frame.minY)
    }

    func testArrowPagesNeverRepeatItemsAndPartialLastPageReturnsToPreviousPage() {
        let input = records(8), frame = CGRect(x: 0, y: 0, width: 1440, height: 1080)
        let first = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init())
        let middle = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init(), firstVisibleIndex: 3)
        let last = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init(), firstVisibleIndex: 6)
        XCTAssertEqual(first.rows.map(\.ordinal), [1,2,3])
        XCTAssertEqual(middle.rows.map(\.ordinal), [4,5,6])
        XCTAssertEqual(last.rows.map(\.ordinal), [7,8])
        XCTAssertTrue(first.earlierArrowFrame.isEmpty); XCTAssertFalse(first.laterArrowFrame.isEmpty)
        XCTAssertFalse(middle.earlierArrowFrame.isEmpty); XCTAssertFalse(middle.laterArrowFrame.isEmpty)
        XCTAssertFalse(last.earlierArrowFrame.isEmpty); XCTAssertTrue(last.laterArrowFrame.isEmpty)
        XCTAssertEqual(first.laterArrowFrame, middle.laterArrowFrame)
        XCTAssertEqual(first.cameraAnchor, last.cameraAnchor)
        XCTAssertEqual(RiftLayout.pageStart(from:6,direction:-1,totalCount:8,capacity:3),3)
    }

    func testWheelOffsetRemainsAvailableAndArrowReturnsToPageBoundary() {
        let input = records(40), frame = CGRect(x: 0, y: 0, width: 1440, height: 1080)
        let wheel = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init(), firstVisibleIndex: 3)
        XCTAssertEqual(wheel.firstVisibleIndex, 3)
        XCTAssertEqual(wheel.rows.first?.ordinal, 4)
        XCTAssertEqual(RiftLayout.pageStart(from: 3, direction: -1, totalCount: 40, capacity: wheel.capacity), 0)
        XCTAssertEqual(RiftLayout.pageStart(from: 3, direction: 1, totalCount: 40, capacity: wheel.capacity), 6)
        XCTAssertEqual(RiftLayout.lastPageStart(totalCount: 0, capacity: 0), 0)
        XCTAssertEqual(RiftLayout.pageStart(from: 8, direction: 1, totalCount: 40, capacity: 0), 0)
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
    func testR2GeometryMatrixPreservesVisibleIslandsAndIndependentCamera() {
        let input = records(31, width: 1600, height: 900)
        for placement in RiftPlacement.allCases {
            for hidden in [0.0, 0.25, 0.75, 0.9] {
                for inset in [0.0, 6, 256] {
                    for count in [1,3,10] {
                        var c = RiftConfiguration(); c.placement = placement
                        c.hiddenFraction = hidden; c.outerInset = inset; c.visibleCountPreference = count
                        let frame = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
                        for index in [0,count,count*3] {
                            let l = RiftLayout.make(records: input, visibleFrame: frame, configuration:c, firstVisibleIndex:index, backingScale:2)
                            XCTAssertEqual(l.capacity,count); XCTAssertEqual(l.rows.count,min(count,31-index))
                            for r in l.rows {
                                XCTAssertTrue(frame.contains(r.frame))
                                XCTAssertFalse(r.imageClipFrame.intersects(r.numberFrame))
                                XCTAssertEqual(r.imageFrame.width/r.imageFrame.height,1600.0/900,accuracy:0.0001)
                                if hidden >= 0.75 { XCTAssertTrue(r.numberIsPad) }
                            }
                            let camera = CGRect(x:l.cameraAnchor.x-18,y:l.cameraAnchor.y-18,width:36,height:36)
                            XCTAssertTrue(frame.contains(camera))
                            XCTAssertFalse(camera.intersects(l.earlierArrowFrame))
                            XCTAssertEqual(l.lineFrame.maxY,l.rows.first!.frame.minY+l.rows.first!.imageFrame.maxY,accuracy:0.001)
                            XCTAssertEqual(l.lineFrame.minY,l.rows.last!.frame.minY+l.rows.last!.imageFrame.minY,accuracy:0.001)
                        }
                    }
                }
            }
        }
    }
}
