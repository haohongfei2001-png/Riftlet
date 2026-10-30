import Foundation
import XCTest
import CSQLite
@testable import RiftletCore

final class SQLiteWALInitializationTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-wal-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func fixture(_ suffix: String) throws -> (URL, OpaquePointer) {
        let url = directory.appendingPathComponent("\(suffix).sqlite")
        var raw: OpaquePointer?
        guard sqlite3_open(url.path, &raw) == SQLITE_OK, let raw else { throw RiftletError.database("fixture open") }
        // Already-extended v3 isolates journal initialization from migration.
        // Deliberately retain DELETE mode to exercise the formerly failing path.
        guard sqlite3_exec(raw, "CREATE TABLE operations(dispatch_exclusive INTEGER); INSERT INTO operations VALUES(1); PRAGMA user_version=3", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(raw); throw RiftletError.database("fixture schema")
        }
        return (url, raw)
    }

    private final class OpenResults: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Result<SQLiteDatabase, Error>] = []
        func append(_ value: Result<SQLiteDatabase, Error>) {
            lock.lock(); defer { lock.unlock() }; values.append(value)
        }
        func get() throws -> [SQLiteDatabase] {
            lock.lock(); defer { lock.unlock() }; return try values.map { try $0.get() }
        }
    }

    func testConcurrentRollbackJournalOpenersKeepOriginalRows() throws {
        for iteration in 0..<10 {
            let (url, raw) = try fixture("concurrent-\(iteration)")
            defer { sqlite3_close(raw) }
            let ready = DispatchSemaphore(value: 0), go = DispatchSemaphore(value: 0)
            let finished = DispatchGroup(), results = OpenResults()
            for _ in 0..<2 {
                finished.enter()
                Thread {
                    ready.signal(); go.wait()
                    results.append(Result { try SQLiteDatabase(url: url) })
                    finished.leave()
                }.start()
            }
            ready.wait(); ready.wait(); go.signal(); go.signal(); finished.wait()
            let opened = try results.get()
            XCTAssertEqual(opened.count, 2)
            XCTAssertEqual(try opened[0].rows("PRAGMA journal_mode"), [["wal"]])
            XCTAssertEqual(try opened[1].rows("SELECT dispatch_exclusive FROM operations"), [["1"]])
            XCTAssertEqual(try opened[1].rows("PRAGMA busy_timeout"), [["3000"]])
        }
    }

    func testHeldReaderBoundsBusyInitializationAndPreservesOriginalDatabase() throws {
        let (url, raw) = try fixture("held-reader")
        defer { sqlite3_exec(raw, "ROLLBACK", nil, nil, nil); sqlite3_close(raw) }
        XCTAssertEqual(sqlite3_exec(raw, "BEGIN; SELECT * FROM operations", nil, nil, nil), SQLITE_OK)
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try SQLiteDatabase(url: url)) { error in
            guard case RiftletError.database(let message) = error else { return XCTFail("Unexpected \(error)") }
            XCTAssertTrue(message.contains("WAL initialization failed (SQLite 5)"), message)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertGreaterThanOrEqual(elapsed, 2.5)
        XCTAssertLessThan(elapsed, 5)
        XCTAssertEqual(sqlite3_exec(raw, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        let recovered = try SQLiteDatabase(url: url)
        XCTAssertEqual(try recovered.rows("SELECT dispatch_exclusive FROM operations"), [["1"]])
        XCTAssertEqual(try recovered.rows("PRAGMA busy_timeout"), [["3000"]])
    }

    func testNonBusyCorruptionFailsPromptlyWithStageAndNoRewrite() throws {
        let url = directory.appendingPathComponent("corrupt.sqlite")
        let original = Data(repeating: 0x73, count: 4096)
        try original.write(to: url)
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try SQLiteDatabase(url: url)) { error in
            guard case RiftletError.database(let message) = error else { return XCTFail("Unexpected \(error)") }
            XCTAssertTrue(message.contains("WAL initialization failed (SQLite 26)"), message)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
