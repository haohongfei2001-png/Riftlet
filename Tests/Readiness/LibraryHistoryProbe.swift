import Foundation
@testable import RiftletCore

/// Compile against either release on the same host. Use -D LIBRARY_104 only
/// for the candidate. "seed" creates a new, metadata-only simulation database.
@main
enum LibraryHistoryProbe {
    enum Failure: Error { case arguments, wrongResult(String) }

    static func require(_ condition: Bool, _ detail: String) throws {
        if !condition { throw Failure.wrongResult(detail) }
    }

    static let origin = Date(timeIntervalSince1970: 1_750_000_000)
    static func timestamp(_ n: Int) -> Date { origin.addingTimeInterval(Double(n / 2)) }

    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3, let count = Int(args[2]), [200, 2000, 10000].contains(count) else { throw Failure.arguments }
        let url = URL(fileURLWithPath: args[1])
        if args[0] == "seed" {
            try require(!FileManager.default.fileExists(atPath: url.path), "fixture already exists")
            let db = try SQLiteDatabase(url: url, mode: .simulation)
            let encoder = JSONEncoder()
            try db.transaction {
                for n in 1...count {
                    let id = UUID(uuidString: String(format: "679A916B-0428-4B0B-A023-%012d", n))!
                    let asset = ImportedAsset(id: id, sourceKey: "fixture-\(n)",
                        fileName: n == 1 ? "跨页-%_needle.png" : "screenshot-\(n).png",
                        sha256: String(repeating: "f", count: 64), byteCount: 4, pixelWidth: 1, pixelHeight: 1,
                        mediaType: "image/png", capturedAt: timestamp(n), firstSeenAt: timestamp(n),
                        importedAt: timestamp(n), origin: .synthetic)
                    let status: QueueStatus = n == 7 ? .unknown : n == 8 ? .missing : .pending
                    try db.execute("""
                        INSERT INTO assets(id,source_key,file_name,sort_at,image_json,status,visibility,last_interaction_at)
                        VALUES(?,?,?,?,?,?,?,?)
                        """, [id.uuidString, asset.sourceKey, asset.fileName, String(timestamp(n).timeIntervalSince1970),
                              String(decoding: try encoder.encode(asset), as: UTF8.self), status.rawValue,
                              n == 3 ? "archived" : "visible", String(timestamp(n).timeIntervalSince1970)])
                }
            }
            return
        }
        guard args[0] == "run", FileManager.default.fileExists(atPath: url.path) else { throw Failure.arguments }
        let store = try QueueStore(databaseURL: url, mode: .simulation)
        func sample(_ label: String, _ operation: () async throws -> Void) async throws {
            for repetition in 1...3 {
                let start = DispatchTime.now().uptimeNanoseconds
                try await operation()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                print("\(count)\t\(label)\t\(repetition)\t\(String(format: "%.3f", ms))")
            }
        }
        try await sample("firstPage") {
            #if LIBRARY_104
            let page = try await store.historyPage(query: .init(), offset: 0, throughSequence: nil)
            try require(page.records.count == 200 && page.records.first?.record.sequence == Int64(count), "new first page")
            #else
            let page = try await store.historySnapshot(limit: 201)
            try require(page.count == min(count, 201) && page.first?.record.sequence == Int64(count), "old first page")
            #endif
        }
        try await sample("findOldest") {
            #if LIBRARY_104
            let page = try await store.historyPage(query: .init(text: "%_needle"), offset: 0, throughSequence: nil)
            try require(page.records.map(\.record.sequence) == [1], "literal full-library search")
            #else
            // 1.0.3 searched only the current page. Count the cost of its native
            // read path if a person manually checked every page for this filename.
            for offset in stride(from: 0, to: count, by: 200) {
                let page = try await store.historySnapshot(limit: 201, offset: offset)
                if page.prefix(200).contains(where: { $0.record.image.fileName.contains("%_needle") }) { return }
            }
            throw Failure.wrongResult("oldest record missing")
            #endif
        }
        #if LIBRARY_104
        try await sample("needsVerification") {
            let result = try await store.historyPage(query: .init(filter: .needsVerification), offset: 0, throughSequence: nil)
            try require(result.records.map(\.record.sequence) == [7], "unknown state")
        }
        let first = try await store.historyPage(query: .init(), offset: 0, throughSequence: nil)
        for (term, wanted) in [("截图", 0), ("#201", 201), ("编号 1", 1), ("Screenshot #1", 1), ("跨页", 1)] {
            let page = try await store.historyPage(query: .init(text: term), offset: 0, throughSequence: nil)
            let expected: [Int64] = wanted > 0 && wanted <= count ? [Int64(wanted)] : []
            try require(page.records.map(\.record.sequence) == expected, term)
        }
        let range = DateInterval(start: timestamp(2), duration: 1)
        let dates = try await store.historyPage(query: .init(dateRange: range), offset: 0, throughSequence: nil)
        try require(dates.records.map(\.record.sequence) == [3, 2], "half-open dates")
        let item = ImportedAsset(sourceKey: "new", fileName: "new.png", sha256: String(repeating: "e", count: 64),
            byteCount: 4, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        _ = try await store.importAsset(item)
        var sequences = [Int64]()
        for offset in stride(from: 0, to: count, by: 200) {
            let page = try await store.historyPage(query: .init(), offset: offset, throughSequence: first.throughSequence)
            try require(page.hasNewCaptures && page.hasNext == (offset + 200 < count), "watermark or next")
            sequences.append(contentsOf: page.records.map(\.record.sequence))
        }
        try require(sequences == (1...Int64(count)).reversed().map { $0 }, "pagination")
        let archived = try await store.historyPage(query: .init(filter: .archived), offset: 0, throughSequence: nil)
        try require(archived.records.map(\.record.sequence) == [3] && archived.records[0].canRestore, "archived")
        try await store.restoreToQueue(archived.records[0].record.id)
        let reopened = try QueueStore(databaseURL: url, mode: .simulation)
        let restored = try await reopened.historyPage(query: .init(text: "#3"), offset: 0, throughSequence: nil)
        try require(restored.records.first?.record.visibility == .visible, "restore and reopen")
        #endif
    }
}
