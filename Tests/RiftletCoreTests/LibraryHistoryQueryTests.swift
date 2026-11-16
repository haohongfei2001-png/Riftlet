import Foundation
import XCTest
@testable import RiftletCore

final class LibraryHistoryQueryTests: XCTestCase {
    func testCrossPageSearchDateLiteralEscapesAndStableSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let store = try QueueStore(databaseURL: url, mode: .simulation)
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        var ids = [UUID]()
        for n in 1...401 {
            let name = n == 1 ? "边界-%_1.png" : "截图-\(n).png"
            let asset = ImportedAsset(sourceKey: "test-\(n)", fileName: name, sha256: String(repeating: "1", count: 64),
                byteCount: 4, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png",
                capturedAt: n <= 2 ? start : start.addingTimeInterval(1), origin: .synthetic)
            ids.append(asset.id); _ = try await store.importAsset(asset)
        }
        for text in ["边界", "%_", "#1", "编号 1", "Screenshot #1"] {
            let result = try await store.historyPage(query: .init(text: text), offset: 0, throughSequence: nil)
            XCTAssertEqual(result.records.map(\.record.id), [ids[0]], text)
        }
        let middle = try await store.historyPage(query: .init(text: "#201"), offset: 0, throughSequence: nil)
        XCTAssertEqual(middle.records.first?.record.id, ids[200])
        let split = try await store.historyPage(query: .init(dateRange: .init(start: start, duration: 1)), offset: 0, throughSequence: nil)
        XCTAssertEqual(split.records.map(\.record.id), [ids[1], ids[0]])
        let first = try await store.historyPage(query: .init(), offset: 0, throughSequence: nil)
        XCTAssertEqual(first.records.count, 200); XCTAssertTrue(first.hasNext)
        let newAsset = ImportedAsset(sourceKey: "new", fileName: "new.png", sha256: String(repeating: "2", count: 64),
            byteCount: 4, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        _ = try await store.importAsset(newAsset)
        let second = try await store.historyPage(query: .init(), offset: 200, throughSequence: first.throughSequence)
        let third = try await store.historyPage(query: .init(), offset: 400, throughSequence: first.throughSequence)
        XCTAssertTrue(second.hasNewCaptures); XCTAssertTrue(second.hasNext); XCTAssertFalse(third.hasNext)
        XCTAssertEqual((first.records + second.records + third.records).map(\.record.id), Array(ids.reversed()))
        try await store.removeFromQueue(ids[0])
        let removed = try await store.historyPage(query: .init(filter: .removed), offset: 0, throughSequence: nil)
        XCTAssertEqual(removed.records.first?.record.id, ids[0]); XCTAssertTrue(removed.records.first?.canRestore == true)
        try await store.restoreToQueue(ids[0])
        let reopened = try QueueStore(databaseURL: url, mode: .simulation)
        let persisted = try await reopened.historyPage(query: .init(text: "%_"), offset: 0, throughSequence: nil)
        XCTAssertEqual(persisted.records.first?.record.visibility, .visible)
    }
}
