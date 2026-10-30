import Foundation
import XCTest
@testable import RiftletCore

final class LateFailureCompensationTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-late-failure-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func store() throws -> QueueStore { try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite")) }
    private let policy = ReceiptPolicy(syntheticAcceptanceProfiles: ["late-fixture": .webChat])
    private func asset(_ time: TimeInterval) -> ImportedAsset {
        let id = UUID()
        return ImportedAsset(id: id, sourceKey: "late-\(id)", fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: 100, pixelWidth: 8, pixelHeight: 8,
            mediaType: "image/png", capturedAt: Date(timeIntervalSince1970: time), origin: .synthetic)
    }
    private func target(_ draft: String = "draft") -> TargetLease {
        TargetLease(adapterID: "late-fixture", surface: .webChat, applicationID: "fixture.browser",
            sessionID: "session", windowID: "window", tabID: "tab", documentID: "document",
            composerID: "composer", draftGeneration: draft)
    }
    private func receipt(_ op: TransferOperation, _ asset: ImportedAsset, success: Bool = false,
                         attachment: String? = "attachment", profile: String = "late-fixture",
                         error: Bool = true, belongs: Bool = true, target: TargetLease? = nil) -> TransferReceipt {
        TransferReceipt(operationID: op.id, assetID: asset.id, attempt: op.attempt, assetSHA256: asset.sha256,
            target: target ?? op.target, outcome: success ? .verifiedReady : .unknown,
            profileID: profile, attachmentID: attachment, positiveReady: success,
            belongsToOriginalDraft: belongs, hasError: success ? false : error,
            reason: "Synthetic late-failure fixture")
    }
    private func consume(_ db: QueueStore, _ asset: ImportedAsset) async throws -> TransferOperation {
        _ = try await db.importAsset(asset)
        let op = try await db.prepare(assetID: asset.id, target: target())
        try await db.markDispatchIntent(op.id)
        _ = try await db.apply(receipt(op, asset, success: true), policy: policy)
        return op
    }

    func testCorrelatedLateErrorStaysInternalAndPersistsOriginalOrderAndBothFacts() async throws {
        let db = try store(); let first = asset(1); let middle = asset(2); let last = asset(3)
        _ = try await db.importAsset(first)
        let op = try await consume(db, middle)
        _ = try await db.importAsset(last)
        let before = try await db.asset(id: middle.id)
        let failure = receipt(op, middle)
        let restored = try await db.apply(failure, policy: policy)
        XCTAssertEqual(restored.status, .unknown)
        XCTAssertEqual(restored.sequence, before?.sequence)
        XCTAssertEqual(restored.activeOperationID, op.id)
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        let queue = try await reopened.assets()
        let saved = try await reopened.compensation(for: op.id)
        let current = try await reopened.operation(id: op.id)
        XCTAssertEqual(queue.map(\.id), [first.id, last.id])
        XCTAssertEqual(restored.visibility, .swallowed)
        XCTAssertEqual(saved?.originalSuccess, receipt(op, middle, success: true))
        XCTAssertEqual(saved?.failure, failure)
        XCTAssertEqual(current?.phase, .compensated)
        let same = try await reopened.prepare(assetID: middle.id, target: target("new"))
        XCTAssertEqual(same.id, op.id); XCTAssertEqual(same.attempt, 1)
    }

    func testRepeatedFailureAndStaleSuccessCannotConsumeCompensationOrReplaceAudit() async throws {
        let db = try store(); let image = asset(1); let op = try await consume(db, image)
        _ = try await db.apply(receipt(op, image), policy: policy)
        let audit = try await db.compensation(for: op.id)
        for evidence in [receipt(op, image), receipt(op, image, success: true), receipt(op, image, error: false)] {
            let result = try await db.apply(evidence, policy: policy)
            XCTAssertEqual(result.status, .unknown)
        }
        let reopened = try store()
        let persisted = try await reopened.compensation(for: op.id)
        XCTAssertEqual(persisted, audit)
        let operations = try await reopened.unresolvedOperations()
        XCTAssertEqual(operations.map(\.id), [op.id])
    }

    func testWrongAttachmentProfileDraftAndNonErrorCannotRestoreUsedImage() async throws {
        let db = try store(); let image = asset(1); let op = try await consume(db, image)
        for evidence in [receipt(op, image, attachment: "other"), receipt(op, image, attachment: nil),
                         receipt(op, image, profile: "other"), receipt(op, image, error: false),
                         receipt(op, image, belongs: false)] {
            let result = try await db.apply(evidence, policy: policy)
            XCTAssertEqual(result.status, .used)
        }
        do {
            _ = try await db.apply(receipt(op, image, target: target("other")), policy: policy)
            XCTFail("Wrong target accepted")
        } catch RiftletError.mismatchedReceipt {}
        let audit = try await db.compensation(for: op.id)
        XCTAssertNil(audit)
    }

    func testCompensationCoexistsWithNewerInFlightImageAndBlocksFurtherDispatch() async throws {
        let db = try store(); let a = asset(1); let b = asset(2); let c = asset(3)
        let first = try await consume(db, a)
        _ = try await db.importAsset(b); _ = try await db.importAsset(c)
        let second = try await db.prepare(assetID: b.id, target: target())
        try await db.markDispatchIntent(second.id)
        _ = try await db.apply(receipt(first, a), policy: policy)
        _ = try await db.apply(receipt(second, b, success: true), policy: policy)
        let third = try await db.prepare(assetID: c.id, target: target())
        do { try await db.markDispatchIntent(third.id); XCTFail("Compensation unlocked draft") }
        catch RiftletError.targetBusy {}
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        let aRecord = try await reopened.asset(id: a.id)
        let bRecord = try await reopened.asset(id: b.id)
        XCTAssertEqual(aRecord?.status, .unknown); XCTAssertEqual(bRecord?.status, .used)
    }

    func testCompensationTransactionFailurePreservesSuccessAndCanBeRetriedOnce() async throws {
        let db = try store(); let image = asset(1); let op = try await consume(db, image)
        let fault = try SQLiteDatabase(url: root.appendingPathComponent("queue.sqlite"))
        try fault.execute("CREATE TRIGGER reject_compensation BEFORE UPDATE ON assets BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        do { _ = try await db.apply(receipt(op, image), policy: policy); XCTFail("Fault did not abort") }
        catch RiftletError.database {}
        let reopened = try store()
        let saved = try await reopened.receipt(for: op.id)
        let audit = try await reopened.compensation(for: op.id)
        let record = try await reopened.asset(id: image.id)
        XCTAssertEqual(record?.status, .used); XCTAssertNil(audit)
        XCTAssertEqual(saved, receipt(op, image, success: true))
        try fault.execute("DROP TRIGGER reject_compensation")
        let restored = try await reopened.apply(receipt(op, image), policy: policy)
        XCTAssertEqual(restored.status, .unknown)
    }

    func testMissingRestoredBytesStayMissingAcrossObservationAndRestart() async throws {
        let db = try store(); let image = asset(1); let op = try await consume(db, image)
        _ = try await db.apply(receipt(op, image), policy: policy)
        try await db.markMissingAsset(image.id)
        try await db.markUnknown(op.id, reason: "Observer unavailable")
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        let missing = try await reopened.asset(id: image.id)
        XCTAssertEqual(missing?.status, .missing)
        try await reopened.restoreMissingAsset(image.id)
        let restored = try await reopened.asset(id: image.id)
        let operation = try await reopened.operation(id: op.id)
        XCTAssertEqual(restored?.status, .unknown); XCTAssertEqual(operation?.phase, .compensated)
    }

    /// Build the exact version-1 operations schema around durable fixture data.
    /// This exercises the real on-disk migration, not only changing user_version.
    private func restoreLegacyOperationsSchema() throws -> SQLiteDatabase {
        let legacy = try SQLiteDatabase(url: root.appendingPathComponent("queue.sqlite"))
        try legacy.transaction {
            // This isolated fixture is reconstructing v1, before this extension existed.
            try legacy.execute("DELETE FROM metadata WHERE key='transfer-dispatch-slots-v1'")
            try legacy.execute("DROP TABLE upload_starts")
            try legacy.execute("DROP INDEX visible_queue_order")
            for column in ["visibility", "visibility_revision", "visibility_reason", "last_interaction_at"] {
                try legacy.execute("ALTER TABLE assets DROP COLUMN \(column)")
            }
            try legacy.execute("DROP TABLE compensations")
            try legacy.execute("CREATE TEMP TABLE legacy_rows AS SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations")
            try legacy.execute("DROP TABLE operations")
            try legacy.execute("""
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
            try legacy.execute("INSERT INTO operations SELECT * FROM legacy_rows")
            try legacy.execute("DROP TABLE legacy_rows")
            try legacy.execute("CREATE UNIQUE INDEX one_unresolved_per_asset ON operations(asset_id) WHERE phase NOT IN ('failed','succeeded')")
            try legacy.execute("CREATE UNIQUE INDEX one_dispatched_per_target ON operations(target_key) WHERE phase IN ('dispatchIntent','inputTriggered','attachmentPresent','unknown')")
            try legacy.execute("PRAGMA user_version = 1")
        }
        return legacy
    }

    func testVersionOneMigrationPreservesReceiptsOrderAndLocks() async throws {
        let db = try store(); let a = asset(1); let b = asset(2); let c = asset(3)
        let success = try await consume(db, a)
        _ = try await db.importAsset(b); _ = try await db.importAsset(c)
        let inFlight = try await db.prepare(assetID: b.id, target: target())
        try await db.markDispatchIntent(inFlight.id)
        let before = try await db.assets(includeUsed: true)
        let legacy = try restoreLegacyOperationsSchema()
        let oldRows = try legacy.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence")
        let reopened = try store()
        XCTAssertEqual(try legacy.rows("PRAGMA user_version").first?.first, "3")
        XCTAssertEqual(try legacy.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations ORDER BY sequence"), oldRows)
        let after = try await reopened.assets(includeUsed: true)
        let saved = try await reopened.receipt(for: success.id)
        XCTAssertEqual(after.map(\.image), before.map(\.image))
        XCTAssertEqual(after.map(\.sequence), before.map(\.sequence))
        XCTAssertEqual(after.map(\.status), before.map(\.status))
        XCTAssertEqual(after.map(\.activeOperationID), before.map(\.activeOperationID))
        XCTAssertEqual(after.map(\.visibility), before.map(\.visibility))
        XCTAssertEqual(saved, receipt(success, a, success: true))
        let next = try await reopened.prepare(assetID: c.id, target: target())
        do { try await reopened.markDispatchIntent(next.id); XCTFail("Migration dropped draft lock") }
        catch RiftletError.targetBusy {}
        _ = try await reopened.apply(receipt(success, a), policy: policy)
        let restored = try await reopened.asset(id: a.id)
        XCTAssertEqual(restored?.status, .unknown)
        XCTAssertEqual(restored?.sequence, before.first?.sequence)
        let indexes = try legacy.rows("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'one_%' ORDER BY name")
        XCTAssertEqual(indexes, [["one_dispatched_per_target"], ["one_unresolved_per_asset"]])
    }

    func testMigrationFailureRollsBackSchemaReceiptsAndVersion() async throws {
        let db = try store(); let a = asset(1); let success = try await consume(db, a)
        let legacy = try restoreLegacyOperationsSchema()
        // An unexpected existing object makes the final migration CREATE fail
        // after operations were copied/dropped. SQLite must restore all old data.
        try legacy.execute("CREATE TABLE compensations (untouched TEXT)")
        try legacy.execute("INSERT INTO compensations VALUES('preserve-existing-data')")
        let oldRows = try legacy.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations")
        do { _ = try store(); XCTFail("Conflicting object did not fail migration") }
        catch RiftletError.database {}
        XCTAssertEqual(try legacy.rows("PRAGMA user_version").first?.first, "1")
        XCTAssertEqual(try legacy.rows("SELECT sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason FROM operations"), oldRows)
        XCTAssertEqual(try legacy.rows("SELECT * FROM compensations"), [["preserve-existing-data"]])
        XCTAssertTrue(try legacy.rows("SELECT name FROM sqlite_master WHERE name='operations_v2'").isEmpty)
        try legacy.execute("DROP TABLE compensations")
        let reopened = try store()
        let saved = try await reopened.receipt(for: success.id)
        XCTAssertEqual(saved, receipt(success, a, success: true))
    }


    func testCompletedObservationCompensatesOnlyMatchingAssetWithoutNewInput() async throws {
        let db = try store(); let a = asset(1); let b = asset(2)
        let first = try await consume(db, a); let second = try await consume(db, b)
        let adapter = LateFailureObserverFixture(success: receipt(first, a))
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: root, policy: policy)
        let continueWatching = try await coordinator.observeCompleted(operationID: first.id)
        let repeated = try await coordinator.observeCompleted(operationID: first.id)
        let restored = try await db.asset(id: a.id); let untouched = try await db.asset(id: b.id)
        let calls = await adapter.counts()
        let watch = try await db.successfulOperations()
        XCTAssertFalse(continueWatching); XCTAssertFalse(repeated)
        XCTAssertEqual(restored?.status, .unknown); XCTAssertEqual(restored?.activeOperationID, first.id)
        XCTAssertEqual(untouched?.status, .used); XCTAssertEqual(untouched?.activeOperationID, second.id)
        XCTAssertEqual(watch.map(\.id), [second.id])
        XCTAssertEqual(calls.captures, 0); XCTAssertEqual(calls.appends, 0)
        XCTAssertEqual(calls.observations, [first.id])
    }

    func testCompletedObservationWithoutOriginalDraftMembershipDoesNotRevive() async throws {
        let db = try store(); let image = asset(1); let op = try await consume(db, image)
        let adapter = LateFailureObserverFixture(success: receipt(op, image, belongs: false))
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: root, policy: policy)
        let continueWatching = try await coordinator.observeCompleted(operationID: op.id)
        let record = try await db.asset(id: image.id)
        let saved = try await db.receipt(for: op.id)
        let audit = try await db.compensation(for: op.id)
        let calls = await adapter.counts()
        XCTAssertFalse(continueWatching); XCTAssertEqual(record?.status, .used)
        XCTAssertEqual(saved, receipt(op, image, success: true)); XCTAssertNil(audit)
        XCTAssertEqual(calls.captures, 0); XCTAssertEqual(calls.appends, 0)
        XCTAssertEqual(calls.observations, [op.id])
    }

    func testCompletedObservationTransportFailurePreservesTerminalSuccess() async throws {
        let db = try store(); let image = asset(1); let op = try await consume(db, image)
        let adapter = LateFailureObserverFixture(success: receipt(op, image), observationUnavailable: true)
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: root, policy: policy)
        do { _ = try await coordinator.observeCompleted(operationID: op.id); XCTFail("Missing transport error") }
        catch RiftletError.adapterUnavailable {}
        let record = try await db.asset(id: image.id)
        let operation = try await db.operation(id: op.id)
        let saved = try await db.receipt(for: op.id)
        let calls = await adapter.counts()
        XCTAssertEqual(record?.status, .used); XCTAssertEqual(operation?.phase, .succeeded)
        XCTAssertEqual(saved, receipt(op, image, success: true))
        XCTAssertEqual(calls.captures, 0); XCTAssertEqual(calls.appends, 0)
    }

    func testRestartWatchQueryIsBoundedAndExcludesInactiveSuccesses() async throws {
        let db = try store(); let a = asset(1); let b = asset(2); let c = asset(3)
        let first = try await consume(db, a); let second = try await consume(db, b)
        let third = try await consume(db, c)
        let raw = try SQLiteDatabase(url: root.appendingPathComponent("queue.sqlite"))
        try raw.execute("UPDATE assets SET active_operation_id=NULL WHERE id=?", [b.id.uuidString])
        let reopened = try store()
        let all = try await reopened.successfulOperations()
        let one = try await reopened.successfulOperations(limit: 1)
        let none = try await reopened.successfulOperations(limit: 0)
        let negative = try await reopened.successfulOperations(limit: -1)
        XCTAssertEqual(all.map(\.id), [third.id, first.id])
        XCTAssertFalse(all.contains { $0.id == second.id })
        XCTAssertEqual(one.map(\.id), [third.id]); XCTAssertTrue(none.isEmpty); XCTAssertTrue(negative.isEmpty)
    }

    func testRestartWatchCapsCallerRequestedLimitAt64() async throws {
        let db = try store()
        var operations: [UUID] = []
        for index in 1...65 {
            let op = try await consume(db, asset(TimeInterval(index)))
            operations.append(op.id)
        }
        let defaultWatch = try await db.successfulOperations()
        let largeWatch = try await db.successfulOperations(limit: Int.max)
        XCTAssertEqual(defaultWatch.count, 64); XCTAssertEqual(largeWatch, defaultWatch)
        XCTAssertEqual(defaultWatch.first?.id, operations.last)
        XCTAssertFalse(defaultWatch.contains { $0.id == operations.first })
    }

    func testSelectingAndRecoveringCompensationOnlyObservesOriginalOperation() async throws {
        let db = try store(); let image = asset(1); let op = try await consume(db, image)
        _ = try await db.apply(receipt(op, image), policy: policy)
        let adapter = LateFailureObserverFixture(success: receipt(op, image, success: true))
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: root, policy: policy)
        try await coordinator.select(image.id)
        try await coordinator.recover()
        let counts = await adapter.counts()
        let restored = try await db.asset(id: image.id)
        XCTAssertEqual(counts.captures, 0); XCTAssertEqual(counts.appends, 0)
        XCTAssertEqual(counts.observations, [op.id, op.id])
        XCTAssertEqual(restored?.status, .unknown)
        XCTAssertEqual(restored?.activeOperationID, op.id)
    }

}


private actor LateFailureObserverFixture: AttachmentAdapter {
    nonisolated let id = "late-fixture"
    private let success: TransferReceipt
    private let observationUnavailable: Bool
    private var captures = 0
    private var appends = 0
    private var observations: [UUID] = []
    init(success: TransferReceipt, observationUnavailable: Bool = false) {
        self.success = success; self.observationUnavailable = observationUnavailable
    }
    func captureTarget() async throws -> TargetLease { captures += 1; return success.target }
    func validate(_ target: TargetLease) async throws -> Bool { true }
    func append(_ request: TransferRequest) async throws -> TransferReceipt { appends += 1; return success }
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        observations.append(request.operation.id)
        if observationUnavailable { throw RiftletError.adapterUnavailable("Synthetic observation unavailable") }
        return success
    }
    func counts() -> (captures: Int, appends: Int, observations: [UUID]) { (captures, appends, observations) }
}
