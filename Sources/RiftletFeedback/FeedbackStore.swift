import Foundation
import CSQLite
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Independent sidecar, never opens queue.sqlite or any media directory.
/// Calls execute on its actor, not on AppKit or a Core writer.
public actor FeedbackStore {
    private var db: OpaquePointer?
    private var descriptor: Int32 = -1
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public nonisolated let wasUnclean: Bool

    public init(directory: URL) throws {
        var handle: OpaquePointer?
        var lockFD: Int32 = -1
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: directory.path), try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw FeedbackFailure.storageUnavailable
            }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard chmod(directory.path, 0o700) == 0 else { throw FeedbackFailure.storageUnavailable }
            lockFD = open(directory.appendingPathComponent("feedback.lock").path, O_CREAT | O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw FeedbackFailure.storageUnavailable }
            var lockInfo = stat()
            guard fstat(lockFD, &lockInfo) == 0, lockInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw FeedbackFailure.storageUnavailable }
            let url = directory.appendingPathComponent("feedback.sqlite")
            for suffix in ["", "-journal", "-wal", "-shm"] {
                let path = URL(fileURLWithPath: url.path + suffix)
                if fm.fileExists(atPath: path.path), try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw FeedbackFailure.storageUnavailable }
            }
            let fd = open(url.path, O_CREAT | O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw FeedbackFailure.storageUnavailable }
            var info = stat(); let regular = fstat(fd, &info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            _ = fchmod(fd, 0o600); close(fd)
            guard regular, sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
            sqlite3_busy_timeout(handle, 200)
            func exec(_ sql: String) throws {
                guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
            }
            var version: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &version, nil) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
            defer { sqlite3_finalize(version) }
            guard sqlite3_step(version) == SQLITE_ROW else { throw FeedbackFailure.storageUnavailable }
            let v = sqlite3_column_int(version, 0)
            guard v == 0 || v == 1 else { throw FeedbackFailure.storageUnavailable }
            // DELETE journal avoids a separately permissioned/unbounded WAL. This
            // private small store never shares the core's writer or schema version.
            try exec("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA trusted_schema=OFF;")
            try exec("BEGIN IMMEDIATE")
            do {
                try exec("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL); CREATE TABLE IF NOT EXISTS draft(id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL,payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,payload BLOB NOT NULL,state TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_attempt REAL NOT NULL,created REAL NOT NULL); CREATE TABLE IF NOT EXISTS submissions(revision INTEGER PRIMARY KEY,report_id TEXT NOT NULL); PRAGMA user_version=1;")
                try exec("INSERT OR IGNORE INTO draft VALUES(1,0,'{\"kind\":\"problem\",\"text\":\"\",\"revision\":0}')")
                var marker: OpaquePointer?
                guard sqlite3_prepare_v2(handle, "SELECT value FROM meta WHERE key='running'", -1, &marker, nil) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
                let unclean = sqlite3_step(marker) == SQLITE_ROW
                sqlite3_finalize(marker)
                try exec("INSERT OR REPLACE INTO meta VALUES('running','1')")
                try exec("COMMIT")
                wasUnclean = unclean
            } catch { try? exec("ROLLBACK"); throw error }
            db = handle; descriptor = lockFD
        } catch {
            if let handle { sqlite3_close(handle) }
            if lockFD >= 0 { close(lockFD) }
            throw FeedbackFailure.storageUnavailable
        }
    }
    deinit { if let db { sqlite3_close(db) }; if descriptor >= 0 { close(descriptor) } }
    private func statement(_ sql: String, _ args: [String] = []) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw FeedbackFailure.storageUnavailable }
        for (i, a) in args.enumerated() {
            let code = a.withCString { sqlite3_bind_text(s, Int32(i + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard code == SQLITE_OK else { sqlite3_finalize(s); throw FeedbackFailure.storageUnavailable }
        }
        return s
    }
    private func execute(_ sql: String, _ args: [String] = []) throws {
        let s = try statement(sql, args); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw FeedbackFailure.storageUnavailable }
    }
    private func string(_ s: OpaquePointer, _ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(s, column) else { return "" }
        return String(cString: pointer)
    }
    public func draft() throws -> FeedbackDraft {
        let s = try statement("SELECT payload FROM draft WHERE id=1"); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw FeedbackFailure.storageUnavailable }
        do { return try decoder.decode(FeedbackDraft.self, from: Data(string(s, 0).utf8)) }
        catch { throw FeedbackFailure.storageUnavailable }
    }
    public func saveDraft(_ value: FeedbackDraft) throws {
        guard value.text.utf8.count <= 131072, value.revision >= 0 else { throw FeedbackFailure.invalidText }
        try value.diagnostic?.validate()
        let existing = try draft()
        if value.revision < existing.revision { return }
        guard value.revision != existing.revision || value == existing else { throw FeedbackFailure.conflict }
        let data = try encoder.encode(value)
        try execute("UPDATE draft SET revision=?,payload=? WHERE id=1 AND revision<=?", [String(value.revision), String(decoding: data, as: UTF8.self), String(value.revision)])
    }
    public func submittedID(revision: Int64) throws -> String? {
        let s = try statement("SELECT report_id FROM submissions WHERE revision=?", [String(revision)]); defer { sqlite3_finalize(s) }
        return sqlite3_step(s) == SQLITE_ROW ? string(s, 0) : nil
    }
    /// Report and draft clearing are one transaction. No successful enqueue can
    /// leave the same visible draft eligible for an accidental second report.
    public func enqueue(_ envelope: FeedbackEnvelope, from value: FeedbackDraft) throws -> String {
        if let old = try submittedID(revision: value.revision) { return old }
        try execute("BEGIN IMMEDIATE")
        do {
            guard try draft() == value else { throw FeedbackFailure.conflict }
            let s = try statement("SELECT COUNT(*),COALESCE(SUM(length(payload)),0),SUM(CASE WHEN state IN ('queued','deletionQueued') THEN 1 ELSE 0 END) FROM reports")
            defer { sqlite3_finalize(s) }
            guard sqlite3_step(s) == SQLITE_ROW else { throw FeedbackFailure.storageUnavailable }
            guard sqlite3_column_int(s, 0) < 200, sqlite3_column_int(s, 1) < 2 * 1024 * 1024 - 32768,
                  sqlite3_column_int(s, 2) < 20 else { throw FeedbackFailure.capacity }
            let bytes = try envelope.encoded()
            try execute("INSERT INTO reports(id,payload,state,next_attempt,created) VALUES(?,?,'queued',0,?)", [envelope.id, String(decoding: bytes, as: UTF8.self), String(envelope.createdAt)])
            try execute("INSERT INTO submissions VALUES(?,?)", [String(value.revision), envelope.id])
            let fresh = FeedbackDraft(revision: value.revision + 1)
            try execute("UPDATE draft SET revision=?,payload=? WHERE id=1", [String(fresh.revision), String(decoding: try encoder.encode(fresh), as: UTF8.self)])
            try execute("COMMIT"); return envelope.id
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func records() throws -> [FeedbackRecord] {
        let s = try statement("SELECT id,payload,state,attempts,next_attempt,created FROM reports ORDER BY created DESC,id LIMIT 200")
        defer { sqlite3_finalize(s) }
        var result: [FeedbackRecord] = []
        while true {
            let step = sqlite3_step(s)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW, let state = FeedbackLocalState(rawValue: string(s, 2)) else { throw FeedbackFailure.storageUnavailable }
            let bytes = Data(string(s, 1).utf8)
            let envelope: FeedbackEnvelope
            do { envelope = try decoder.decode(FeedbackEnvelope.self, from: bytes) } catch { throw FeedbackFailure.storageUnavailable }
            result.append(FeedbackRecord(id: string(s, 0), envelope: envelope, bytes: bytes, state: state,
                attempts: Int(sqlite3_column_int(s, 3)), nextAttempt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)),
                created: Date(timeIntervalSince1970: sqlite3_column_double(s, 5))))
        }
    }
    public func beginAttempt(id: String, expected: FeedbackLocalState) throws -> Bool {
        try execute("UPDATE reports SET attempts=MIN(attempts+1,9999) WHERE id=? AND state=?", [id, expected.rawValue])
        return sqlite3_changes(db) == 1
    }
    public func reschedule(id: String, expected: FeedbackLocalState, after delay: TimeInterval, blocked: Bool = false) throws {
        try execute("UPDATE reports SET state=?,next_attempt=? WHERE id=? AND state=?", [blocked ? FeedbackLocalState.blocked.rawValue : expected.rawValue, String(Date().addingTimeInterval(max(1, min(86400, delay))).timeIntervalSince1970), id, expected.rawValue])
    }
    public func apply(_ receipt: FeedbackReceipt) throws {
        try receipt.validate(for: receipt.id)
        let newState: FeedbackLocalState
        switch receipt.state {
        case "delivered": newState = .delivered
        case "deleted": newState = .deleted
        case "deletion_pending": newState = .deletionPending
        case "delivery_expired": newState = .expired
        default: newState = .received
        }
        // A late POST acknowledgement cannot cancel a newer deletion request.
        if newState == .delivered {
            try execute("UPDATE reports SET state='delivered' WHERE id=? AND state IN ('queued','received','blocked')", [receipt.id])
        } else if newState == .received {
            try execute("UPDATE reports SET state='received' WHERE id=? AND state='queued'", [receipt.id])
        } else {
            try execute("UPDATE reports SET state=? WHERE id=?", [newState.rawValue, receipt.id])
        }
    }
    public func requestDeletion(id: String) throws {
        try execute("UPDATE reports SET state=CASE WHEN attempts=0 AND state='queued' THEN 'cancelled' ELSE 'deletionQueued' END,next_attempt=0 WHERE id=? AND state NOT IN ('deleted','cancelled','deletionPending')", [id])
    }
    public func forgetResolved(id: String) throws {
        try execute("DELETE FROM reports WHERE id=? AND state IN ('deleted','cancelled')", [id])
        guard sqlite3_changes(db) == 1 else { throw FeedbackFailure.conflict }
    }
    public func closeForTesting(clean: Bool) throws {
        if clean { try markClean() }
        if let db { guard sqlite3_close(db) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }; self.db = nil }
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
    }
    public func markClean() throws { try execute("DELETE FROM meta WHERE key='running'") }
}
