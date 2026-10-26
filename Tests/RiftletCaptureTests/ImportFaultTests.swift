import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
import CSQLite
@testable import RiftletCapture
import RiftletCore

private final class OncePerBoundary: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Set<ImportBoundary>
    init(_ boundaries: [ImportBoundary]) { remaining = Set(boundaries) }
    func take(_ boundary: ImportBoundary) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return remaining.remove(boundary) != nil
    }
}

/// Uses real private files and SQLite, with deterministic in-process interruptions.
/// Reopening these artifacts tests app-crash recovery semantics, not power-loss durability.
final class ImportFaultTests: XCTestCase {
    private struct Fixture: Sendable {
        let root: URL
        let source: URL
        let privateRoot: URL
        let databaseURL: URL
        let store: QueueStore
        let bytes: Data

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-import-fault-" + UUID().uuidString)
            privateRoot = root.appendingPathComponent("private", isDirectory: true)
            try FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)
            source = root.appendingPathComponent("synthetic.png")
            databaseURL = privateRoot.appendingPathComponent("queue.sqlite")
            store = try QueueStore(databaseURL: databaseURL)
            let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 14, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 14))
            let data = NSMutableData()
            let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(encoder, try XCTUnwrap(context.makeImage()), nil)
            XCTAssertTrue(CGImageDestinationFinalize(encoder))
            bytes = data as Data
            try bytes.write(to: source)
            let metadata = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            let result = metadata.withUnsafeBytes { setxattr(source.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }
            XCTAssertEqual(result, 0)
        }

        func files(_ directory: String) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: privateRoot.appendingPathComponent(directory),
                                                         includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        }
        func close() { try? FileManager.default.removeItem(at: root) }
    }

    private func importNow(_ importer: PrivateAssetImporter, from fixture: Fixture) async throws -> AssetRecord {
        // The file is constructed completely by the fixture; test the commit boundaries
        // directly instead of waiting on the unrelated collector's stability timer.
        try await importer.importStableFile(at: fixture.source,
            signature: FileSignature.read(at: fixture.source), firstSeenAt: Date())
    }

    func testEveryDurableBoundaryCanReopenWithoutDuplicateQueueOrOriginalLoss() async throws {
        for boundary in ImportBoundary.allCases {
            let f = try Fixture(); defer { f.close() }
            let interrupted = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store) { context in
                if context.boundary == boundary { throw SimulatedImportInterruption(boundary: boundary) }
            }
            do { _ = try await importNow(interrupted, from: f); XCTFail("Expected interruption at \(boundary)") }
            catch let interruption as SimulatedImportInterruption { XCTAssertEqual(interruption.boundary, boundary) }
            XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)

            let reopenedStore = try QueueStore(databaseURL: f.databaseURL)
            let reopened = PrivateAssetImporter(privateRoot: f.privateRoot, store: reopenedStore)
            let report = try await reopened.recover()
            let beforeRetry = try await reopenedStore.assets()
            switch boundary {
            case .stageOpened, .stageSynced:
                // Unjournaled stages are inert, even when their bytes happen to be complete.
                XCTAssertEqual(report.adopted, 0)
                XCTAssertTrue(beforeRetry.isEmpty)
                let seen = try await reopenedStore.containsSource(key: FileSignature.read(at: f.source).sourceKey)
                XCTAssertFalse(seen)
            case .journalRenamed, .journalSynced, .mediaRenamed, .mediaSynced:
                XCTAssertEqual(report.adopted, 1)
                XCTAssertEqual(beforeRetry.count, 1)
            case .databaseCommitted:
                XCTAssertEqual(report.adopted, 0)
                XCTAssertEqual(beforeRetry.count, 1)
            }
            let result = try await importNow(reopened, from: f)
            let retry = try await importNow(reopened, from: f)
            let afterRetry = try await reopenedStore.assets(includeUsed: true)
            XCTAssertEqual(result.id, retry.id)
            XCTAssertEqual(afterRetry.count, 1)
            XCTAssertEqual(try f.files("media").count, 1)
            XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
            let again = try await reopened.recover()
            XCTAssertEqual(again.adopted, 0)
        }
    }

    func testIOFailureBeforeJournalDoesNotMarkSeenOrRetainPartialCopy() async throws {
        for boundary in [ImportBoundary.stageOpened, .stageSynced] {
            let f = try Fixture(); defer { f.close() }
            let failing = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store) { context in
                if context.boundary == boundary { throw CaptureError.io("injected-storage-full", ENOSPC) }
            }
            do { _ = try await importNow(failing, from: f); XCTFail("Expected storage failure") }
            catch { XCTAssertEqual(error as? CaptureError, .io("injected-storage-full", ENOSPC)) }
            let seen = try await f.store.containsSource(key: FileSignature.read(at: f.source).sourceKey)
            XCTAssertFalse(seen)
            XCTAssertTrue(try f.files("staging").isEmpty)
            XCTAssertTrue(try f.files("journal").isEmpty)
            XCTAssertTrue(try f.files("media").isEmpty)
            XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
            let normal = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
            _ = try await importNow(normal, from: f)
            let records = try await f.store.assets()
            XCTAssertEqual(records.count, 1)
        }
    }

    func testJournalRenameThenSyncFailureKeepsStageOwnedByRecovery() async throws {
        let f = try Fixture(); defer { f.close() }
        let failing = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store) { context in
            if context.boundary == .journalRenamed { throw CaptureError.io("injected-directory-sync", EIO) }
        }
        do { _ = try await importNow(failing, from: f); XCTFail("Expected sync failure after journal rename") }
        catch { XCTAssertEqual(error as? CaptureError, .io("injected-directory-sync", EIO)) }
        XCTAssertEqual(try f.files("journal").count, 1)
        XCTAssertEqual(try f.files("staging").count, 1)
        XCTAssertTrue(try f.files("media").isEmpty)
        let before = try await f.store.assets()
        XCTAssertTrue(before.isEmpty)
        // Retrying on the same importer must finish its journal, not create another UUID.
        let result = try await importNow(failing, from: f)
        let all = try await f.store.assets()
        XCTAssertEqual(all.map(\.id), [result.id])
        XCTAssertEqual(try f.files("journal").count, 1)
        XCTAssertEqual(try f.files("media").count, 1)
        XCTAssertTrue(try f.files("staging").isEmpty)
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }

    func testMediaRenameThenSyncFailureRecoversWithoutRecopy() async throws {
        let f = try Fixture(); defer { f.close() }
        let failing = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store) { context in
            if context.boundary == .mediaRenamed { throw CaptureError.io("injected-media-sync", EIO) }
        }
        do { _ = try await importNow(failing, from: f); XCTFail("Expected sync failure after media rename") }
        catch { XCTAssertEqual(error as? CaptureError, .io("injected-media-sync", EIO)) }
        let existingMedia = try XCTUnwrap(f.files("media").first)
        let before = try await f.store.assets()
        XCTAssertTrue(before.isEmpty)
        _ = try await importNow(failing, from: f)
        XCTAssertEqual(try f.files("media"), [existingMedia])
        XCTAssertTrue(try f.files("staging").isEmpty)
        let all = try await f.store.assets()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }

    func testRealSQLiteWriterLockLeavesJournalAndCanResumeSameIdentity() async throws {
        let f = try Fixture(); defer { f.close() }
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(f.databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil), SQLITE_OK)
        let blocker = try XCTUnwrap(handle)
        defer { sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil); sqlite3_close(blocker) }
        XCTAssertEqual(sqlite3_exec(blocker, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        do { _ = try await importNow(importer, from: f); XCTFail("The real SQLite writer lock must prevent commit") }
        catch RiftletError.database { /* Expected SQLITE_BUSY after the configured bounded timeout. */ }
        let seen = try await f.store.containsSource(key: FileSignature.read(at: f.source).sourceKey)
        XCTAssertFalse(seen)
        let media = try XCTUnwrap(f.files("media").first)
        XCTAssertEqual(try f.files("journal").count, 1)
        // The storage failure may persist through several collection events. Recovery
        // must propagate SQLITE_BUSY without allocating a second private identity.
        do { _ = try await importNow(importer, from: f); XCTFail("A still-locked database must remain retryable") }
        catch RiftletError.database { }
        XCTAssertEqual(try f.files("media"), [media])
        XCTAssertEqual(try f.files("journal").count, 1)
        XCTAssertTrue(try f.files("staging").isEmpty)
        XCTAssertEqual(sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        _ = try await importNow(importer, from: f)
        XCTAssertEqual(try f.files("media"), [media])
        let records = try await f.store.assets()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }

    func testRecoveryIOFailureCannotAllocateAnotherPrivateIdentity() async throws {
        let f = try Fixture(); defer { f.close() }
        let failures = OncePerBoundary([.journalSynced, .mediaRenamed])
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store) { context in
            if failures.take(context.boundary) { throw CaptureError.io("injected-storage-recovery", EIO) }
        }
        do { _ = try await importNow(importer, from: f); XCTFail("Leave the journal and stage pending") }
        catch { XCTAssertEqual(error as? CaptureError, .io("injected-storage-recovery", EIO)) }
        let journal = try XCTUnwrap(f.files("journal").first)
        XCTAssertEqual(try f.files("staging").count, 1)

        // Reconciliation itself encounters an IO failure after promotion. It must
        // return that error, not fall through to a second stage/journal/UUID.
        do { _ = try await importNow(importer, from: f); XCTFail("Propagate recovery IO failure") }
        catch { XCTAssertEqual(error as? CaptureError, .io("injected-storage-recovery", EIO)) }
        let originalMedia = try XCTUnwrap(f.files("media").first)
        XCTAssertEqual(try f.files("journal"), [journal])
        XCTAssertEqual(try f.files("media").count, 1)
        XCTAssertTrue(try f.files("staging").isEmpty)
        let absent = try await f.store.assets()
        XCTAssertTrue(absent.isEmpty)

        _ = try await importNow(importer, from: f)
        XCTAssertEqual(try f.files("journal"), [journal])
        XCTAssertEqual(try f.files("media"), [originalMedia])
        let records = try await f.store.assets()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }

    func testPromotionCollisionDoesNotOverwriteUnrelatedPrivateBytes() async throws {
        let f = try Fixture(); defer { f.close() }
        let unrelated = Data("existing-unrelated-private-bytes".utf8)
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store) { context in
            if context.boundary == .journalSynced, let media = context.mediaURL {
                try unrelated.write(to: media, options: .withoutOverwriting)
            }
        }
        do { _ = try await importNow(importer, from: f); XCTFail("Promotion must refuse an existing destination") }
        catch { XCTAssertEqual(error as? CaptureError, .io("promote-private-copy", EEXIST)) }
        let collision = try XCTUnwrap(f.files("media").first)
        XCTAssertEqual(try Data(contentsOf: collision), unrelated)
        XCTAssertEqual(try f.files("staging").count, 1)
        let recovering = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        let invalid = try await recovering.recover()
        XCTAssertEqual(invalid.invalid.count, 1)
        let records = try await f.store.assets()
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: collision), unrelated)
        // Preserve the collision elsewhere in this temporary test root before retrying.
        let preserved = f.root.appendingPathComponent("preserved-collision")
        try FileManager.default.moveItem(at: collision, to: preserved)
        let recovered = try await recovering.recover()
        XCTAssertEqual(recovered.adopted, 1)
        XCTAssertEqual(try Data(contentsOf: preserved), unrelated)
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }

    func testUnreadablePendingJournalDoesNotCreateCopiesOnRepeatedRetry() async throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission-denial fixture requires an unprivileged executor") }
        let f = try Fixture(); defer { f.close() }
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store) { context in
            if context.boundary == .journalSynced { throw CaptureError.io("injected-before-promotion", EIO) }
        }
        do { _ = try await importNow(importer, from: f); XCTFail("Leave a journaled stage") }
        catch { XCTAssertEqual(error as? CaptureError, .io("injected-before-promotion", EIO)) }
        let journal = try XCTUnwrap(f.files("journal").first)
        let stage = try XCTUnwrap(f.files("staging").first)
        XCTAssertEqual(chmod(journal.path, 0), 0)
        defer { _ = chmod(journal.path, 0o600) }
        for _ in 0..<2 {
            do { _ = try await importNow(importer, from: f); XCTFail("Unreadable recovery data must remain pending") }
            catch { XCTAssertFalse(error is DecodingError) }
            XCTAssertEqual(try f.files("journal"), [journal])
            XCTAssertEqual(try f.files("staging"), [stage])
            XCTAssertTrue(try f.files("media").isEmpty)
        }
        XCTAssertEqual(chmod(journal.path, 0o600), 0)
        _ = try await importNow(importer, from: f)
        let records = try await f.store.assets()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(try f.files("journal"), [journal])
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }

    func testMalformedJournalDoesNotPreventUnrelatedValidRecovery() async throws {
        let f = try Fixture(); defer { f.close() }
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        let original = try await importNow(importer, from: f)
        let damagedID = UUID()
        let damaged = f.privateRoot.appendingPathComponent("journal").appendingPathComponent(damagedID.uuidString + ".json")
        try Data("{\"version\":1,\"image\":".utf8).write(to: damaged)
        let replacementStore = try QueueStore(databaseURL: f.root.appendingPathComponent("replacement.sqlite"))
        let recovering = PrivateAssetImporter(privateRoot: f.privateRoot, store: replacementStore)
        let report = try await recovering.recover()
        XCTAssertEqual(report.adopted, 1)
        XCTAssertTrue(report.invalid.contains(damagedID))
        let records = try await replacementStore.assets()
        XCTAssertEqual(records.map(\.id), [original.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: damaged.path))
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }

    func testRecoveryAndSourceRetryNeverResurrectUsedImage() async throws {
        let f = try Fixture(); defer { f.close() }
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        let original = try await importNow(importer, from: f)
        let target = TargetLease(adapterID: "c2-test-only", surface: .webChat, applicationID: "synthetic-browser",
            sessionID: "session", windowID: "window", tabID: "tab", documentID: "document",
            composerID: "composer", draftGeneration: "draft")
        let operation = try await f.store.prepare(assetID: original.id, target: target)
        try await f.store.markDispatchIntent(operation.id)
        let receipt = TransferReceipt(operationID: operation.id, assetID: original.id, attempt: operation.attempt,
            assetSHA256: original.image.sha256, target: target, outcome: .verifiedReady,
            profileID: "c2-synthetic-only", attachmentID: "synthetic-attachment", positiveReady: true,
            belongsToOriginalDraft: true)
        _ = try await f.store.apply(receipt, policy: .init(admittedProfiles: ["c2-synthetic-only": .webChat]))
        let media = f.privateRoot.appendingPathComponent("media").appendingPathComponent(original.image.fileName)
        try FileManager.default.removeItem(at: media)
        let reopenedStore = try QueueStore(databaseURL: f.databaseURL)
        let reopened = PrivateAssetImporter(privateRoot: f.privateRoot, store: reopenedStore)
        let report = try await reopened.recover()
        XCTAssertTrue(report.missing.contains(original.id))
        let retried = try await importNow(reopened, from: f)
        XCTAssertEqual(retried.id, original.id)
        XCTAssertEqual(retried.status, .used)
        let visible = try await reopenedStore.assets()
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }
}
