import XCTest
import RiftletCore
@testable import RiftletUI

final class RiftReconfigurationTests: XCTestCase {
    private func records(_ count: Int) -> [AssetRecord] {
        (1...count).map { index in
            let id = UUID()
            return AssetRecord(image: ImportedAsset(
                id: id, sourceKey: "reconfiguration-\(id)", fileName: "\(id.uuidString).png",
                sha256: String(repeating: "b", count: 64), byteCount: 100,
                pixelWidth: 1_920, pixelHeight: 1_080, mediaType: "image/png", origin: .synthetic),
                sequence: Int64(index))
        }
    }

    func testLargeValidInsetDoesNotPushFittingRowsOutsideNarrowDisplay() throws {
        var configuration = RiftConfiguration()
        configuration.fitWidth = 256
        configuration.fitHeight = 256
        configuration.hiddenFraction = 0
        configuration.outerInset = 256
        try configuration.validate()
        let frame = CGRect(x: -480, y: 50, width: 480, height: 900)
        let layout = RiftLayout.make(records: records(3), visibleFrame: frame, configuration: configuration)
        XCTAssertEqual(layout.rows.count, 3)
        for row in layout.rows {
            XCTAssertTrue(frame.contains(row.frame), "A valid inset must not move the hit window past the left edge")
            XCTAssertEqual(row.imageFrame.width / row.imageFrame.height, 1_920.0 / 1_080.0, accuracy: 0.0001)
            XCTAssertEqual(row.frame.maxX, layout.rows[0].frame.maxX, accuracy: 0.0001)
        }
        XCTAssertTrue(frame.contains(layout.lineFrame))
    }

    func testGeometryReconfigurationPreservesIdentityAndOcclusionRatio() throws {
        let input = records(12)
        let frame = CGRect(x: -1_440, y: -100, width: 1_440, height: 1_000)
        let original = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init())
        var configuration = RiftConfiguration()
        configuration.fitWidth = 96
        configuration.fitHeight = 72
        configuration.hiddenFraction = 0.4
        configuration.outerInset = 18
        configuration.rowPitch = 20
        try configuration.validate()
        let changed = RiftLayout.make(records: input, visibleFrame: frame, configuration: configuration)
        XCTAssertEqual(changed.rows.map(\.assetID), original.rows.map(\.assetID))
        XCTAssertEqual(changed.rows.map(\.ordinal), Array(1...12))
        for row in changed.rows {
            XCTAssertTrue(frame.contains(row.frame))
            XCTAssertEqual(row.imageClipFrame.width / row.imageFrame.width, 0.6, accuracy: 0.0001)
            XCTAssertEqual(row.imageFrame.width / row.imageFrame.height, 1_920.0 / 1_080.0, accuracy: 0.0001)
        }
        for pair in zip(changed.rows, changed.rows.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.frame.minY - pair.1.frame.maxY, 4)
        }
    }

    func testEveryRetainedItemRemainsReachableAcrossSmallDisplayWindows() {
        let input = records(12)
        let frame = CGRect(x: 1_920, y: 100, width: 700, height: 350)
        var reached = Set<UUID>()
        for start in 0...input.count {
            let layout = RiftLayout.make(records: input, visibleFrame: frame,
                                         configuration: .init(), firstVisibleIndex: start)
            XCTAssertEqual(layout.totalCount, input.count)
            for row in layout.rows {
                XCTAssertTrue(frame.contains(row.frame))
                XCTAssertEqual(row.assetID, input[row.ordinal - 1].id)
                reached.insert(row.assetID)
            }
        }
        XCTAssertEqual(reached, Set(input.map(\.id)))
    }

    func testUsedCompactionKeepsHeldSelectionBoundToOriginalAsset() {
        let input = records(12)
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let initial = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init())
        let held = initial.rows[8]
        var gate = PointerSelectionGate()
        XCTAssertTrue(gate.begin(assetID: held.assetID,
                                 screenPoint: CGPoint(x: held.frame.midX, y: held.frame.midY),
                                 timestamp: 10, clickCount: 1, doubleClickInterval: 0.5, acceptsSelection: true))
        let changed = input.enumerated().map { index, record in
            AssetRecord(image: record.image, sequence: record.sequence,
                        status: index < 2 ? .used : (index == 8 ? .unknown : .failed))
        }
        let after = RiftLayout.make(records: changed, visibleFrame: frame, configuration: .init())
        XCTAssertEqual(after.rows.map(\.ordinal), Array(1...10))
        XCTAssertEqual(gate.end(inside: true), input[8].id)
        XCTAssertEqual(after.rows.first(where: { $0.assetID == input[8].id })?.ordinal, 7)
    }

    func testPreferredDisplayDisconnectAndReconnectChangesGeometryWithoutChangingAssets() {
        let input = records(3)
        let frames: [UInt32: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            2: CGRect(x: -1_080, y: -200, width: 1_080, height: 1_920)
        ]
        let connected = RiftDisplaySelection.choose(preferred: 2, main: 1, available: [1, 2])
        let disconnected = RiftDisplaySelection.choose(preferred: 2, main: 1, available: [1])
        let reconnected = RiftDisplaySelection.choose(preferred: 2, main: 1, available: [1, 2])
        XCTAssertEqual(connected, 2)
        XCTAssertEqual(disconnected, 1)
        XCTAssertEqual(reconnected, 2)
        for id in [connected, disconnected, reconnected].compactMap({ $0 }) {
            let frame = frames[id]!
            let layout = RiftLayout.make(records: input, visibleFrame: frame, configuration: .init())
            XCTAssertEqual(layout.rows.map(\.assetID), input.map(\.id))
            XCTAssertTrue(layout.rows.allSatisfy { frame.contains($0.frame) })
        }
    }

    func testMissingPreferredAndMainDisplayUsesAvailableDisplayOrNoScreen() {
        XCTAssertEqual(RiftDisplaySelection.choose(preferred: 2, main: 1, available: [3]), 3)
        XCTAssertEqual(RiftDisplaySelection.choose(preferred: nil, main: 2, available: [1, 2]), 2)
        XCTAssertNil(RiftDisplaySelection.choose(preferred: 2, main: 1, available: []))
    }

    func testNoVerticalSpaceCreatesNoInputRowsWithoutDiscardingRecords() {
        let input = records(12)
        let layout = RiftLayout.make(records: input, visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 0),
                                     configuration: .init(), firstVisibleIndex: Int.max)
        XCTAssertEqual(layout.totalCount, 12)
        XCTAssertEqual(layout.capacity, 0)
        XCTAssertTrue(layout.rows.isEmpty)
        XCTAssertEqual(layout.lineFrame, .zero)
    }
}
