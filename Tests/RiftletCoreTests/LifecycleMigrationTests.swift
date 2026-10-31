import Foundation
import XCTest
import CSQLite
@testable import RiftletCore

/// Frozen pre-lifecycle schemas are created directly with system SQLite. The
/// current migration is never used to manufacture its own legacy input.
final class LifecycleMigrationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftlet-lifecycle-migration-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private var databaseURL: URL { directory.appendingPathComponent("queue.sqlite") }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }

    private func makeLegacy(version: Int) throws -> LegacyFixture {
        let sql = try RawLifecycleSQLite(databaseURL)
        try sql.execute("PRAGMA foreign_keys=ON")
        try sql.execute("""
            CREATE TABLE assets (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL UNIQUE, source_key TEXT NOT NULL UNIQUE,
                file_name TEXT NOT NULL UNIQUE, sort_at REAL NOT NULL,
                image_json TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('pending','transferring','unknown','failed','used','missing')),
                active_operation_id TEXT
            )
            """)
        let phases = version == 1
            ? "'prepared','dispatchIntent','inputTriggered','attachmentPresent','unknown','failed','succeeded'"
            : "'prepared','dispatchIntent','inputTriggered','attachmentPresent','unknown','compensated','failed','succeeded'"
        try sql.execute("""
            CREATE TABLE operations (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
                asset_id TEXT NOT NULL REFERENCES assets(id), attempt INTEGER NOT NULL CHECK(attempt > 0),
                target_key TEXT NOT NULL, target_json TEXT NOT NULL,
                phase TEXT NOT NULL CHECK(phase IN (\(phases))),
                created_at REAL NOT NULL, updated_at REAL NOT NULL, receipt_json TEXT,
                reason TEXT NOT NULL DEFAULT '', UNIQUE(asset_id, attempt)
            )
            """)
        try sql.execute("CREATE UNIQUE INDEX one_unresolved_per_asset ON operations(asset_id) WHERE phase NOT IN ('failed','succeeded')")
        try sql.execute("CREATE UNIQUE INDEX one_dispatched_per_target ON operations(target_key) WHERE phase IN ('dispatchIntent','inputTriggered','attachmentPresent','unknown')")
        try sql.execute("CREATE INDEX pending_order ON assets(status,sort_at,sequence)")
        try sql.execute("CREATE TABLE checkpoints (key TEXT PRIMARY KEY, value BLOB NOT NULL)")
        try sql.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try sql.execute("INSERT INTO metadata VALUES('mode','production')")
        try sql.execute("INSERT INTO checkpoints VALUES('fixture-checkpoint','AQID')")
        if version == 2 {
            try sql.execute("CREATE TABLE compensations (operation_id TEXT PRIMARY KEY REFERENCES operations(id), evidence_json TEXT NOT NULL)")
        }
        try sql.execute("PRAGMA user_version=\(version)")

        var images: [ImportedAsset] = []
        var operationIDs: [UUID] = []
        for index in 0..<(version == 2 ? 4 : 3) {
            let id = UUID(), operationID = UUID()
            let image = ImportedAsset(id: id, sourceKey: "legacy-source-\(index)",
                fileName: "\(id).png", sha256: String(repeating: "a", count: 64),
                byteCount: 32, pixelWidth: 2, pixelHeight: 2, mediaType: "image/png",
                capturedAt: Date(timeIntervalSince1970: Double(index + 1)),
                firstSeenAt: Date(timeIntervalSince1970: 100),
                importedAt: Date(timeIntervalSince1970: 101), origin: .synthetic)
            images.append(image)
            let status = index == 0 ? "used" : (index == 2 ? "pending" : "unknown")
            try sql.execute("INSERT INTO assets(id,source_key,file_name,sort_at,image_json,status,active_operation_id) VALUES(?,?,?,?,?,?,?)",
                [id.uuidString, image.sourceKey, image.fileName, String(index + 1), try json(image), status,
                 index == 2 ? nil : operationID.uuidString])
            guard index != 2 else { continue }
            operationIDs.append(operationID)
            let target = TargetLease(adapterID: "legacy-fixture", surface: .webChat,
                applicationID: "com.google.Chrome", sessionID: "original-session",
                windowID: "original-window", tabID: "original-tab-\(index)", documentID: "original-document",
                composerID: "original-composer", draftGeneration: "original-generation")
            let success = TransferReceipt(operationID: operationID, assetID: id, attempt: 1,
                assetSHA256: image.sha256, target: target, outcome: .verifiedReady,
                profileID: "legacy-fixture", attachmentID: "attachment-\(operationID)",
                positiveReady: true, belongsToOriginalDraft: true)
            let unknown = TransferReceipt(operationID: operationID, assetID: id, attempt: 1,
                assetSHA256: image.sha256, target: target, outcome: .unknown,
                profileID: "legacy-fixture", attachmentID: "attachment-\(operationID)",
                belongsToOriginalDraft: true, hasError: index == 3,
                reason: "Original observation is uncertain")
            let phase = index == 0 ? "succeeded" : (index == 3 ? "compensated" : "unknown")
            try sql.execute("INSERT INTO operations(id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason) VALUES(?,?,?,?,?,?,?,?,?,?)",
                [operationID.uuidString, id.uuidString, "1", target.stableKey, try json(target), phase,
                 "120", "121", try json(index == 0 ? success : unknown), "original-reason"])
            if index == 3 {
                let compensation = TransferCompensation(originalSuccess: success, failure: unknown,
                    createdAt: Date(timeIntervalSince1970: 122))
                try sql.execute("INSERT INTO compensations VALUES(?,?)", [operationID.uuidString, try json(compensation)])
            }
        }
        return LegacyFixture(sql: sql, images: images, operationIDs: operationIDs)
    }

    private func makeFrozenVersionThree() throws -> LegacyFixture {
        let legacy = try makeLegacy(version: 2)
        // Frozen v3 additions, created without invoking the current migrator.
        try legacy.sql.execute("ALTER TABLE assets ADD COLUMN visibility TEXT NOT NULL DEFAULT 'visible'")
        try legacy.sql.execute("ALTER TABLE assets ADD COLUMN visibility_revision INTEGER NOT NULL DEFAULT 0")
        try legacy.sql.execute("ALTER TABLE assets ADD COLUMN visibility_reason TEXT NOT NULL DEFAULT 'capture'")
        try legacy.sql.execute("ALTER TABLE assets ADD COLUMN last_interaction_at REAL NOT NULL DEFAULT 0")
        try legacy.sql.execute("CREATE INDEX visible_queue_order ON assets(visibility,sort_at,sequence)")
        try legacy.sql.execute("CREATE TABLE upload_starts(operation_id TEXT PRIMARY KEY REFERENCES operations(id), receipt_json TEXT NOT NULL, started_at REAL NOT NULL)")
        try legacy.sql.execute("PRAGMA user_version=3")
        return legacy
    }

    func testFrozenVersionThreeUnknownKeepsExclusiveSlotAndOriginalRows() async throws {
        let legacy = try makeFrozenVersionThree()
        let before = try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence")
        let url = databaseURL
        let firstOpen = Task.detached { try QueueStore(databaseURL: url) }
        let secondOpen = Task.detached { try QueueStore(databaseURL: url) }
        let one = try await firstOpen.value
        _ = try await secondOpen.value // concurrent migration rechecks after BEGIN
        _ = try QueueStore(databaseURL: databaseURL) // extension is idempotent
        XCTAssertEqual(try legacy.sql.rows("PRAGMA user_version"), [["3"]])
        XCTAssertEqual(try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence"), before)
        XCTAssertEqual(try legacy.sql.rows("SELECT DISTINCT dispatch_exclusive FROM operations"), [["1"]])
        let old = try await one.operation(id: legacy.operationIDs[1])!
        let nonce = try await one.dispatchInvocationID(for: old.id); XCTAssertNil(nonce)
        let fresh = ImportedAsset(sourceKey: UUID().uuidString, fileName: "new.png", sha256: String(repeating: "a", count: 64), byteCount: 10, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        _ = try await one.importAsset(fresh)
        let next = try await one.prepare(assetID: fresh.id, target: old.target)
        do { try await one.markDispatchIntent(next.id); XCTFail("legacy UNKNOWN must remain locked") }
        catch RiftletError.targetBusy {}
    }

    func testDispatchExtensionFailureRollsBackColumnAndIndexTogether() throws {
        let legacy = try makeFrozenVersionThree()
        try legacy.sql.execute("INSERT INTO metadata VALUES('transfer-dispatch-slots-v1','unexpected')")
        let beforeIndex = try legacy.sql.rows("SELECT sql FROM sqlite_master WHERE name='one_dispatched_per_target'")
        XCTAssertThrowsError(try QueueStore(databaseURL: databaseURL))
        XCTAssertFalse(try legacy.sql.rows("PRAGMA table_info(operations)").contains { $0[1] == "dispatch_exclusive" })
        XCTAssertEqual(try legacy.sql.rows("SELECT sql FROM sqlite_master WHERE name='one_dispatched_per_target'"), beforeIndex)
        XCTAssertEqual(try legacy.sql.rows("PRAGMA user_version"), [["3"]])
    }

    func testFrozenVersionTwoMigratesVisibilityWithoutInventingStartOrRewritingFacts() async throws {
        let legacy = try makeLegacy(version: 2)
        let beforeOperations = try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence")
        let beforeCompensations = try legacy.sql.rows("SELECT * FROM compensations")
        let beforeAssets = try legacy.sql.rows("SELECT sequence,id,source_key,file_name,sort_at,image_json,status,active_operation_id FROM assets ORDER BY sequence")

        let store = try QueueStore(databaseURL: databaseURL)
        let all = try await store.assets(includeUsed: true)
        XCTAssertEqual(all.map(\.id), legacy.images.map(\.id))
        XCTAssertEqual(all.map(\.visibility), [.swallowed, .visible, .visible, .swallowed])
        XCTAssertEqual(all.map(\.status), [.used, .unknown, .pending, .unknown])
        XCTAssertEqual(try legacy.sql.rows("PRAGMA user_version"), [["3"]])
        XCTAssertEqual(try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence"), beforeOperations)
        XCTAssertEqual(try legacy.sql.rows("SELECT * FROM compensations"), beforeCompensations)
        XCTAssertEqual(try legacy.sql.rows("SELECT sequence,id,source_key,file_name,sort_at,image_json,status,active_operation_id FROM assets ORDER BY sequence"), beforeAssets)
        let checkpoint = try await store.checkpoint(for: "fixture-checkpoint")
        XCTAssertEqual(checkpoint, Data([1, 2, 3]))
        for operationID in legacy.operationIDs {
            let op = try await store.operation(id: operationID)
            XCTAssertNil(op?.target.logicalDraftIdentity)
        }
    }

    func testFrozenVersionOneMigratesAllTheWayAndKeepsUnstartedUnknownVisible() async throws {
        let legacy = try makeLegacy(version: 1)
        let before = try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence")
        let store = try QueueStore(databaseURL: databaseURL)
        let all = try await store.assets(includeUsed: true)
        XCTAssertEqual(all.map(\.visibility), [.swallowed, .visible, .visible])
        XCTAssertEqual(try legacy.sql.rows("PRAGMA user_version"), [["3"]])
        XCTAssertEqual(try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence"), before)
        XCTAssertTrue(try legacy.sql.rows("SELECT * FROM compensations").isEmpty)
        let reopened = try QueueStore(databaseURL: databaseURL)
        let reopenedRecords = try await reopened.assets(includeUsed: true)
        XCTAssertEqual(reopenedRecords, all)
        XCTAssertEqual(try legacy.sql.rows("PRAGMA foreign_key_check"), [])
        XCTAssertEqual(try legacy.sql.rows("PRAGMA quick_check"), [["ok"]])
    }

    func testUnsupportedFutureVersionPreservesLegacyRows() throws {
        let legacy = try makeLegacy(version: 2)
        let assets = try legacy.sql.rows("SELECT * FROM assets ORDER BY sequence")
        let operations = try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence")
        try legacy.sql.execute("PRAGMA user_version=99")
        XCTAssertThrowsError(try QueueStore(databaseURL: databaseURL))
        XCTAssertEqual(try legacy.sql.rows("PRAGMA user_version"), [["99"]])
        XCTAssertEqual(try legacy.sql.rows("SELECT * FROM assets ORDER BY sequence"), assets)
        XCTAssertEqual(try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence"), operations)
    }

    func testLifecycleMigrationFailureRollsBackLegacySchemaAndEveryOriginalFact() throws {
        let legacy = try makeLegacy(version: 1)
        let assetSchema = try legacy.sql.rows("PRAGMA table_info(assets)")
        let operationSchema = try legacy.sql.rows("PRAGMA table_info(operations)")
        let assets = try legacy.sql.rows("SELECT * FROM assets ORDER BY sequence")
        let operations = try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence")
        // This unexpected preexisting object forces the lifecycle migration to
        // fail after any prior migration steps. None may partially commit.
        try legacy.sql.execute("CREATE TABLE upload_starts (untouched TEXT)")
        try legacy.sql.execute("INSERT INTO upload_starts VALUES('preserve-existing-data')")
        XCTAssertThrowsError(try QueueStore(databaseURL: databaseURL))
        XCTAssertEqual(try legacy.sql.rows("PRAGMA user_version"), [["1"]])
        XCTAssertEqual(try legacy.sql.rows("PRAGMA table_info(assets)"), assetSchema)
        XCTAssertEqual(try legacy.sql.rows("PRAGMA table_info(operations)"), operationSchema)
        XCTAssertEqual(try legacy.sql.rows("SELECT * FROM assets ORDER BY sequence"), assets)
        XCTAssertEqual(try legacy.sql.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence"), operations)
        XCTAssertEqual(try legacy.sql.rows("SELECT * FROM upload_starts"), [["preserve-existing-data"]])
        XCTAssertTrue(try legacy.sql.rows("SELECT name FROM sqlite_master WHERE name IN ('operations_v2','compensations')").isEmpty)
    }
}

private struct LegacyFixture {
    let sql: RawLifecycleSQLite
    let images: [ImportedAsset]
    let operationIDs: [UUID]
}

private final class RawLifecycleSQLite {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(_ url: URL) throws {
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw error() }
    }
    deinit { if let handle { sqlite3_close(handle) } }

    private func error() -> NSError {
        NSError(domain: "RawLifecycleSQLite", code: Int(sqlite3_errcode(handle)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
    }

    private func statement(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw error() }
        do {
            for (offset, value) in values.enumerated() {
                let status = value.map { sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, transient) }
                    ?? sqlite3_bind_null(statement, Int32(offset + 1))
                guard status == SQLITE_OK else { throw error() }
            }
        } catch { sqlite3_finalize(statement); throw error }
        return statement
    }

    func execute(_ sql: String, _ values: [String?] = []) throws {
        let statement = try statement(sql, values)
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW { status = sqlite3_step(statement) }
        guard status == SQLITE_DONE else { throw error() }
    }

    func rows(_ sql: String) throws -> [[String?]] {
        let statement = try statement(sql, [])
        defer { sqlite3_finalize(statement) }
        var result: [[String?]] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            result.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_type(statement, column) == SQLITE_NULL ? nil
                    : sqlite3_column_text(statement, column).map { String(cString: $0) }
            })
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw error() }
        return result
    }
}
