import Foundation
import CSQLite

/// Confined to QueueStore's actor; no ORM and no third-party runtime.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw RiftletError.database("Database path must not be a symbolic link")
        }
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle { sqlite3_close(handle) }; handle = nil
            throw RiftletError.database(message)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = FULL")
        let version = try rows("PRAGMA user_version").first?[0] ?? "0"
        guard ["0", "1", "2", "3"].contains(version) else {
            throw RiftletError.database("Unsupported schema version \(version); database preserved")
        }
        if version != "3" {
            // All pending migrations commit together. A v3 failure must not
            // leave a v1 store half-upgraded or rewrite its receipt history.
            try transaction {
                if version == "0" { try migrate() }
                if version == "0" || version == "1" { try migrateCompensation() }
                try migrateVisibility()
            }
        }
        guard try rows("PRAGMA quick_check").first?.first == "ok" else {
            throw RiftletError.database("Integrity check failed; database preserved")
        }
    }

    deinit { if let handle { sqlite3_close(handle) } }

    private func migrate() throws {
        try execute("""
            CREATE TABLE assets (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL UNIQUE,
                source_key TEXT NOT NULL UNIQUE,
                file_name TEXT NOT NULL UNIQUE,
                sort_at REAL NOT NULL,
                image_json TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('pending','transferring','unknown','failed','used','missing')),
                active_operation_id TEXT
            )
            """)
        try execute("""
            CREATE TABLE operations (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL UNIQUE,
                asset_id TEXT NOT NULL REFERENCES assets(id),
                attempt INTEGER NOT NULL CHECK(attempt > 0),
                target_key TEXT NOT NULL,
                target_json TEXT NOT NULL,
                phase TEXT NOT NULL CHECK(phase IN ('prepared','dispatchIntent','inputTriggered','attachmentPresent','unknown','failed','succeeded')),
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                receipt_json TEXT,
                reason TEXT NOT NULL DEFAULT '',
                UNIQUE(asset_id, attempt)
            )
            """)
        try execute("CREATE UNIQUE INDEX one_unresolved_per_asset ON operations(asset_id) WHERE phase NOT IN ('failed','succeeded')")
        try execute("CREATE UNIQUE INDEX one_dispatched_per_target ON operations(target_key) WHERE phase IN ('dispatchIntent','inputTriggered','attachmentPresent','unknown')")
        try execute("CREATE INDEX pending_order ON assets(status,sort_at,sequence)")
        try execute("CREATE TABLE checkpoints (key TEXT PRIMARY KEY, value BLOB NOT NULL)")
        try execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try execute("PRAGMA user_version = 1")
    }

    private func migrateCompensation() throws {
        // Add one phase to the existing state machine without rewriting assets,
        // receipt bytes, operation IDs, timestamps, or attempt ordering.
        try execute("""
            CREATE TABLE operations_v2 (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL UNIQUE,
                asset_id TEXT NOT NULL REFERENCES assets(id),
                attempt INTEGER NOT NULL CHECK(attempt > 0),
                target_key TEXT NOT NULL,
                target_json TEXT NOT NULL,
                phase TEXT NOT NULL CHECK(phase IN ('prepared','dispatchIntent','inputTriggered','attachmentPresent','unknown','compensated','failed','succeeded')),
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                receipt_json TEXT,
                reason TEXT NOT NULL DEFAULT '',
                UNIQUE(asset_id, attempt)
            )
            """)
        try execute("INSERT INTO operations_v2 SELECT * FROM operations")
        try execute("DROP TABLE operations")
        try execute("ALTER TABLE operations_v2 RENAME TO operations")
        try execute("CREATE UNIQUE INDEX one_unresolved_per_asset ON operations(asset_id) WHERE phase NOT IN ('failed','succeeded')")
        // A late failure can coexist with a newer in-flight image in this draft.
        // Compensated operations are checked by the dispatch guard, not this index.
        try execute("CREATE UNIQUE INDEX one_dispatched_per_target ON operations(target_key) WHERE phase IN ('dispatchIntent','inputTriggered','attachmentPresent','unknown')")
        try execute("""
            CREATE TABLE compensations (
                operation_id TEXT PRIMARY KEY REFERENCES operations(id),
                evidence_json TEXT NOT NULL
            )
            """)
        try execute("PRAGMA user_version = 2")
    }

    private func migrateVisibility() throws {
        try execute("ALTER TABLE assets ADD COLUMN visibility TEXT NOT NULL DEFAULT 'visible' CHECK(visibility IN ('visible','swallowed','archived','removed'))")
        try execute("ALTER TABLE assets ADD COLUMN visibility_revision INTEGER NOT NULL DEFAULT 0")
        try execute("ALTER TABLE assets ADD COLUMN visibility_reason TEXT NOT NULL DEFAULT 'capture'")
        try execute("ALTER TABLE assets ADD COLUMN last_interaction_at REAL NOT NULL DEFAULT 0")
        // Completion/compensation history already proves these images left the
        // old queue. Do not invent a start event for any legacy operation.
        try execute("""
            UPDATE assets SET visibility='swallowed',visibility_reason='legacyCompletion'
            WHERE status='used' OR active_operation_id IN (SELECT id FROM operations WHERE phase='compensated')
            """)
        for row in try rows("SELECT id,image_json FROM assets") {
            guard let id = row[0], let raw = row[1] else { throw RiftletError.database("Invalid legacy asset") }
            let image = try JSONDecoder().decode(ImportedAsset.self, from: Data(raw.utf8))
            try execute("UPDATE assets SET last_interaction_at=? WHERE id=?", [String(image.importedAt.timeIntervalSince1970), id])
        }
        try execute("CREATE INDEX visible_queue_order ON assets(visibility,sort_at,sequence)")
        try execute("""
            CREATE TABLE upload_starts (
                operation_id TEXT PRIMARY KEY REFERENCES operations(id),
                receipt_json TEXT NOT NULL,
                started_at REAL NOT NULL
            )
            """)
        try execute("PRAGMA user_version = 3")
    }

    func execute(_ sql: String, _ parameters: [String?] = []) throws {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        // PRAGMAs may produce a row before DONE.
        while status == SQLITE_ROW { status = sqlite3_step(statement) }
        guard status == SQLITE_DONE else { throw failure() }
    }

    func rows(_ sql: String, _ parameters: [String?] = []) throws -> [[String?]] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        var output: [[String?]] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            output.append((0..<sqlite3_column_count(statement)).map { index in
                guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                      let value = sqlite3_column_text(statement, index) else { return nil }
                return String(cString: value)
            })
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure() }
        return output
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ parameters: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (offset, parameter) in parameters.enumerated() {
            let status: Int32
            if let parameter { status = sqlite3_bind_text(statement, Int32(offset + 1), parameter, -1, transient) }
            else { status = sqlite3_bind_null(statement, Int32(offset + 1)) }
            guard status == SQLITE_OK else { sqlite3_finalize(statement); throw failure() }
        }
        return statement
    }

    private func failure() -> RiftletError {
        .database(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Database closed")
    }
}
