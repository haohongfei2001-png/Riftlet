import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CSQLite
import RiftletCore
@testable import RiftletCapture

private enum ProbeFailure: Error { case failed(String) }
private func require(_ value: Bool, _ message: String) throws {
    if !value { throw ProbeFailure.failed(message) }
}
private func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
private func json<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return try encoder.encode(value)
}
private func writeJSON(_ object: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        .write(to: url, options: .withoutOverwriting)
}

private struct DatabaseSnapshot: Codable, Equatable {
    let schema: [[String]]
    let tables: [String: [[String]]]
}

/// Reads every SQLite cell with its storage type; no string-only row comparison.
private func databaseSnapshot(_ url: URL) throws -> DatabaseSnapshot {
    var handle: OpaquePointer?
    try require(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
                "Cannot open own database read-only")
    defer { sqlite3_close(handle) }
    sqlite3_busy_timeout(handle, 3_000)
    func query(_ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        try require(sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, "Read-only query could not prepare")
        defer { sqlite3_finalize(statement) }
        var rows: [[String]] = [], result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_NULL: return "null"
                case SQLITE_INTEGER: return "integer:" + String(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: return "realBits:" + String(sqlite3_column_double(statement, column).bitPattern, radix: 16)
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    let bytes = sqlite3_column_blob(statement, column)
                    return "blob:" + (count == 0 ? "" : Data(bytes: bytes!, count: count).base64EncodedString())
                default:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    return "text:" + String(decoding: UnsafeBufferPointer(start: sqlite3_column_text(statement, column), count: count), as: UTF8.self)
                }
            })
            result = sqlite3_step(statement)
        }
        try require(result == SQLITE_DONE, "Read-only query failed")
        return rows
    }
    try require(sqlite3_exec(handle, "BEGIN", nil, nil, nil) == SQLITE_OK, "Cannot begin consistent read")
    defer { sqlite3_exec(handle, "ROLLBACK", nil, nil, nil) }
    try require(try query("PRAGMA quick_check") == [["text:ok"]], "SQLite quick_check failed")
    try require(try query("PRAGMA foreign_key_check").isEmpty, "SQLite foreign-key failure")
    let schema = try query("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name")
    let names = try query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    var tables: [String: [[String]]] = [:]
    for row in names {
        let name = String(row[0].dropFirst(5))
        tables[name] = try query("SELECT * FROM \"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
            .sorted { $0.lexicographicallyPrecedes($1) }
    }
    return DatabaseSnapshot(schema: schema, tables: tables)
}

/// Checkpoint only our test database, so the subsequent real transaction must grow its WAL.
private func truncateOwnWAL(_ url: URL, evidence: URL) throws -> [String: Any] {
    var handle: OpaquePointer?
    try require(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
                "Cannot open own checkpoint connection")
    defer { sqlite3_close(handle) }
    sqlite3_busy_timeout(handle, 3_000)
    func walBytes() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path + "-wal")[.size] as? NSNumber)?.int64Value ?? 0
    }
    let before = walBytes()
    // A just-opened connection has not necessarily read the pager/WAL state.
    let initialized = sqlite3_exec(handle, "SELECT count(*) FROM sqlite_master", nil, nil, nil)
    var logFrames: Int32 = -999, checkpointFrames: Int32 = -999
    let code = sqlite3_wal_checkpoint_v2(handle, "main", SQLITE_CHECKPOINT_TRUNCATE, &logFrames, &checkpointFrames)
    let after = walBytes()
    let report: [String: Any] = ["schemaReadCode": initialized, "checkpointCode": code,
                                "nLog": logFrames, "nCheckpoint": checkpointFrames,
                                "walBytesBefore": before, "walBytesAfter": after]
    try writeJSON(report, to: evidence)
    try require(initialized == SQLITE_OK && code == SQLITE_OK && logFrames == 0 && checkpointFrames == 0 && after == 0,
                "Own WAL was not fully initialized and truncated; see checkpoint evidence")
    return report
}

/// The only removable file. Bound to an exclusive inode on the already verified test volume.
/// A hook owns one instance and runs synchronously; the caller reads it after awaiting import.
private final class OwnedFiller: @unchecked Sendable {
    let url: URL
    private let device: dev_t
    private var inode: ino_t?
    private(set) var bytes: Int64 = 0
    private(set) var writeErrno: Int32 = 0
    private(set) var syncErrno: Int32 = 0
    private(set) var removed = false
    private var writeCalls = 0
    private var exhaustedRequests: [[String: UInt64]] = []
    private var finalAvailableBytes: UInt64?

    init(directory: URL, device: dev_t) {
        self.url = directory.appendingPathComponent("disposable-filler-" + UUID().uuidString.lowercased() + ".bin")
        self.device = device
    }

    func fill() throws {
        try require(inode == nil, "Filler is single use")
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        try require(descriptor >= 0, "Cannot create exclusive filler")
        defer { Darwin.close(descriptor) }
        var file = stat(), volume = statfs()
        try require(fstat(descriptor, &file) == 0 && file.st_dev == device && file.st_uid == getuid(), "Filler volume changed")
        try require(fstatfs(descriptor, &volume) == 0 && UInt64(volume.f_blocks) * UInt64(volume.f_bsize) <= 256 * 1_024 * 1_024,
                    "Refuse to fill a volume larger than 256 MiB")
        inode = file.st_ino
        let buffer = [UInt8](repeating: 0x5a, count: 1_024 * 1_024)
        let requests = [1_024 * 1_024, 64 * 1_024, 4 * 1_024, 1]
        var requestIndex = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while bytes < 256 * 1_024 * 1_024 && ProcessInfo.processInfo.systemUptime < deadline {
            writeCalls += 1
            let count = buffer.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, requests[requestIndex]) }
            if count < 0 {
                if errno == EINTR { continue }
                writeErrno = errno
                if writeErrno != ENOSPC { break }
                try require(fstatfs(descriptor, &volume) == 0, "Cannot read capacity after filler failure")
                let available = UInt64(volume.f_bavail) * UInt64(volume.f_bsize)
                exhaustedRequests.append(["requestBytes": UInt64(requests[requestIndex]), "availableBytes": available, "errno": UInt64(writeErrno)])
                if requestIndex == requests.count - 1 { finalAvailableBytes = available; break }
                // A rejected large allocation may leave enough space for a small product write.
                requestIndex += 1
                continue
            }
            try require(count > 0, "Filler write made no progress")
            bytes += Int64(count)
        }
        if fsync(descriptor) != 0 { syncErrno = errno }
        try require(writeErrno == ENOSPC && finalAvailableBytes != nil,
                    "Filler did not reach a real one-byte ENOSPC within its byte/time bounds")
    }

    func removeDisposableFile() throws {
        var file = stat()
        try require(!removed && inode != nil && lstat(url.path, &file) == 0 && file.st_dev == device &&
                    file.st_ino == inode && file.st_uid == getuid() && file.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                    "Filler identity changed; do not remove")
        try require(Darwin.unlink(url.path) == 0, "Cannot remove own disposable filler")
        removed = true
    }

    var record: [String: Any] {
        ["basename": url.lastPathComponent, "device": Int64(device), "inode": inode.map { UInt64($0) } as Any? ?? NSNull(),
         "bytesWritten": bytes, "writeErrno": writeErrno, "syncErrno": syncErrno, "removed": removed,
         "writeCalls": writeCalls, "exhaustedRequests": exhaustedRequests,
         "finalAvailableBytes": finalAvailableBytes as Any? ?? NSNull()]
    }
}

private struct FileFact: Codable, Equatable {
    let sha256: String
    let bytes: UInt64
    let mode: UInt32
}

@MainActor private final class DiskFullProbe {
    private let root: URL, output: URL, source: URL, storage: URL, database: URL
    private let device: dev_t
    private var cases: [[String: Any]] = []
    private var fillers: [OwnedFiller] = []
    private let started = ProcessInfo.processInfo.systemUptime

    init(root: URL, output: URL, uuid: String) throws {
        self.root = root; self.output = output
        source = root.appendingPathComponent("source"); storage = root.appendingPathComponent("private")
        database = storage.appendingPathComponent("queue.sqlite")
        try require(UUID(uuidString: uuid) != nil && root.lastPathComponent == "riftlet-diskfull-" + uuid &&
                    root.standardizedFileURL == root.resolvingSymlinksInPath(), "Invalid isolated root")
        let marker = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("root-marker.json"))) as? [String: Any]
        try require(marker?["kind"] as? String == "synthetic-disk-full-recovery" && marker?["uuid"] as? String == uuid,
                    "Invalid root marker")
        var here = stat(), parent = stat(), volume = statfs()
        try require(lstat(root.path, &here) == 0 && lstat(output.path, &parent) == 0 && here.st_dev != parent.st_dev,
                    "Test root must be on a separate mounted volume")
        try require((marker?["deviceNumber"] as? NSNumber)?.int64Value == Int64(here.st_dev), "Device differs from verified marker")
        try require(statfs(root.path, &volume) == 0 && UInt64(volume.f_blocks) * UInt64(volume.f_bsize) <= 256 * 1_024 * 1_024,
                    "Test volume exceeds 256 MiB")
        device = here.st_dev
        for directory in [source, storage] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
    }

    private func files(_ directories: [String]) throws -> [String: FileFact] {
        var result: [String: FileFact] = [:]
        for name in directories {
            let directory = root.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            for path in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                var info = stat()
                try require(lstat(path.path, &info) == 0 && info.st_dev == device && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                            "Unexpected entry in own data")
                result[name + "/" + path.lastPathComponent] = FileFact(sha256: digest(try Data(contentsOf: path)), bytes: UInt64(info.st_size), mode: UInt32(info.st_mode & 0o7777))
            }
        }
        return result
    }

    private func saveSnapshot(_ name: String) throws -> DatabaseSnapshot {
        let snapshot = try databaseSnapshot(database)
        try json(snapshot).write(to: output.appendingPathComponent(name + ".json"), options: .withoutOverwriting)
        return snapshot
    }

    private func captureFailure(_ error: Error) -> [String: Any] {
        if case CaptureError.io(let stage, let code) = error {
            return ["type": "CaptureError.io", "stage": stage, "errno": code,
                    "diagnostic": CaptureDiagnostic.classify(error, context: .privateStorage).code.rawValue]
        }
        if case RiftletError.database(let message) = error {
            return ["type": "RiftletError.database", "message": message, "sqliteNumericCodeExposed": false,
                    "diagnostic": CaptureDiagnostic.classify(error, context: .privateStorage).code.rawValue]
        }
        return ["type": String(describing: error), "diagnostic": CaptureDiagnostic.classify(error, context: .privateStorage).code.rawValue]
    }

    private func pattern() throws -> Data {
        guard let context = CGContext(data: nil, width: 512, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ProbeFailure.failed("Cannot make synthetic image")
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 512, height: 320))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.4, alpha: 1)); context.fill(CGRect(x: 40, y: 30, width: 260, height: 140))
        let output = NSMutableData()
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ProbeFailure.failed("Cannot encode synthetic image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        try require(CGImageDestinationFinalize(destination), "PNG encode failed")
        return output as Data
    }

    func run() async throws {
        do {
            let store = try QueueStore(databaseURL: database)
            let normal = PrivateAssetImporter(privateRoot: storage, store: store)
            let bytes = try pattern()
            let inputs = (0..<4).map { source.appendingPathComponent("synthetic-\($0).png") }
            for input in inputs { try bytes.write(to: input, options: .withoutOverwriting) }
            let originals = try files(["source"])
            let first = try await normal.importFile(at: inputs[0], origin: .synthetic)
            _ = try await normal.importFile(at: inputs[1], origin: .synthetic)
            let target = TargetLease(adapterID: "disk-full-readiness", surface: .webChat, applicationID: "isolated.synthetic",
                                     sessionID: "session", windowID: "window", tabID: "tab", documentID: "doc", composerID: "composer", draftGeneration: "draft")
            let operation = try await store.prepare(assetID: first.id, target: target)
            try await store.markDispatchIntent(operation.id)
            try await store.markUnknown(operation.id, reason: "Synthetic disk-full preservation fixture; no external input")
            let unknown = try await store.operation(id: operation.id)
            let baseline = try saveSnapshot("baseline-database")
            let oldFiles = try files(["private/media", "private/journal"])

            let preflight = OwnedFiller(directory: root, device: device); fillers.append(preflight)
            try preflight.fill()
            do { _ = try await normal.importFile(at: inputs[2], origin: .synthetic); throw ProbeFailure.failed("Full-volume preflight unexpectedly imported") }
            catch CaptureError.insufficientStorage {
                cases.append(["name": "real-full-volume-default-preflight", "result": "PASS", "error": "CaptureError.insufficientStorage",
                              "headroomBytes": PrivateStorageCapacity.metadataHeadroom, "scope": "Preflight refusal; not a failed product write"])
            }
            try require(try saveSnapshot("preflight-full-database") == baseline, "Preflight failure changed typed rows")
            try require(try files(["source"]) == originals && files(["private/media", "private/journal"]) == oldFiles,
                        "Preflight failure changed original or historical bytes")
            try preflight.removeDisposableFile()

            let copying = OwnedFiller(directory: root, device: device); fillers.append(copying)
            let copyImporter = PrivateAssetImporter(privateRoot: storage, store: store, fault: { context in
                if context.boundary == .stageOpened { try copying.fill() }
            })
            do { _ = try await copyImporter.importFile(at: inputs[2], origin: .synthetic); throw ProbeFailure.failed("Mid-copy ENOSPC did not occur") }
            catch CaptureError.io(let stage, let code) where code == ENOSPC {
                cases.append(["name": "real-write-enospc-after-passed-preflight", "result": "PASS",
                              "error": captureFailure(CaptureError.io(stage, code)),
                              "seam": "Existing stageOpened boundary fills only the verified volume; the unchanged product write reports real errno"])
            }
            try require(try saveSnapshot("copy-full-database") == baseline, "Copy failure changed typed rows")
            try require(try files(["source"]) == originals && files(["private/media", "private/journal"]) == oldFiles,
                        "Copy failure changed original or historical bytes")
            try copying.removeDisposableFile()
            let copied = try await normal.importFile(at: inputs[2], origin: .synthetic)
            try require(try await store.assets(includeUsed: true).count == 3, "Explicit copy retry duplicated an asset")
            cases.append(["name": "explicit-original-input-retry-after-free-space", "result": "PASS", "retryCount": 1, "assetCount": 3])

            let checkpoint = try truncateOwnWAL(database, evidence: output.appendingPathComponent("wal-checkpoint.json"))
            let beforeSQL = try saveSnapshot("before-database-write-failure")
            let beforeSQLFiles = try files(["private/media", "private/journal"])
            let committing = OwnedFiller(directory: root, device: device); fillers.append(committing)
            let sqlImporter = PrivateAssetImporter(privateRoot: storage, store: store, fault: { context in
                if context.boundary == .mediaSynced { try committing.fill() }
            })
            do { _ = try await sqlImporter.importFile(at: inputs[3], origin: .synthetic); throw ProbeFailure.failed("Full-volume database write unexpectedly committed") }
            catch RiftletError.database(let message) {
                try require(message == "database or disk is full", "Different database failure; do not misclassify")
                cases.append(["name": "database-write-failure-after-durable-media", "result": "PASS",
                              "error": captureFailure(RiftletError.database(message)), "walCheckpoint": checkpoint,
                              "seam": "Existing mediaSynced boundary fills only the verified volume before actual store.importAsset"])
            }
            try require(try saveSnapshot("database-write-full-database") == beforeSQL, "Failed database transaction changed typed rows")
            let afterSQLFiles = try files(["private/media", "private/journal"])
            try require(beforeSQLFiles.allSatisfy { afterSQLFiles[$0.key] == $0.value } && afterSQLFiles.count == beforeSQLFiles.count + 2,
                        "Durable journal/media ownership was lost or duplicated")
            try require(try files(["source"]) == originals, "Full database changed original input")
            try committing.removeDisposableFile()
            let recovered = try await sqlImporter.importFile(at: inputs[3], origin: .synthetic)
            try require(try files(["private/media", "private/journal"]) == afterSQLFiles, "Recovery allocated a duplicate private copy")
            let finalAssets = try await store.assets(includeUsed: true)
            let finalUnknown = try await store.operation(id: operation.id)
            let finalStart = try await store.uploadStartReceipt(for: operation.id)
            try require(recovered.id != copied.id && finalAssets.count == 4, "Recovery duplicate or missing asset")
            try require(finalUnknown == unknown && finalStart == nil,
                        "UNKNOWN changed or invented START")
            let final = try saveSnapshot("final-database")
            for (table, rows) in baseline.tables where table != "assets" && table != "sqlite_sequence" {
                try require(final.tables[table] == rows, "Historical typed rows changed in " + table)
            }
            try require((baseline.tables["assets"] ?? []).allSatisfy { final.tables["assets"]?.contains($0) == true },
                        "Historical full asset rows changed")
            for record in try await store.assets(includeUsed: true) {
                let path = storage.appendingPathComponent("media/" + record.image.fileName)
                try require(digest(Data(contentsOf: path)) == record.image.sha256, "Final media SHA mismatch")
            }
            try require(try files(["source"]) == originals, "Original source bytes changed")
            cases.append(["name": "durable-journal-retry-and-original-unknown-preserved", "result": "PASS",
                          "retryCount": 1, "assets": 4, "operations": 1, "uploadStarts": 0, "newPrivateCopyDuringRecovery": false])
            try saveReport(result: "PASS_SCOPED_REAL_DISK_FULL_RECOVERY", failure: nil)
        } catch {
            try? saveReport(result: "FAIL_SCOPED_REAL_DISK_FULL_RECOVERY", failure: String(describing: error))
            throw error
        }
    }

    private func saveReport(result: String, failure: String?) throws {
        try writeJSON(["schema": 1, "result": result, "completed": result.hasPrefix("PASS"),
                       "failure": failure as Any? ?? NSNull(), "cases": cases, "fillers": fillers.map(\.record),
                       "actualSeconds": ProcessInfo.processInfo.systemUptime - started,
                       "scope": ["actualMountedLimitedVolume": true, "maximumVolumeBytes": 256 * 1_024 * 1_024,
                                 "productionDataAccess": false, "appOrGUI": false, "network": false,
                                 "faultSeamsOnlyScheduleRealDiskExhaustion": true, "syntheticOriginalsRetained": true,
                                 "powerLossTest": false, "installedAppRestartTest": false]], to: output.appendingPathComponent("native-report.json"))
    }
}

@main private struct NativeDiskFullRecovery {
    @MainActor static func main() async {
        do {
            let arguments = CommandLine.arguments
            try require(arguments.count == 4, "Expected verified volume root, evidence directory and UUID")
            try await DiskFullProbe(root: URL(fileURLWithPath: arguments[1]), output: URL(fileURLWithPath: arguments[2]), uuid: arguments[3]).run()
            print("DISK_FULL_RECOVERY_PASS")
        } catch {
            fputs("DISK_FULL_RECOVERY_FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
