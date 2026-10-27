import Foundation
import XCTest
@testable import RiftletCore

/// SQLite round trips and contradictory late observations, not a second state machine.
final class RecoveryBoundaryTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-recovery-boundary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func store() throws -> QueueStore { try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite")) }
    private func image() -> ImportedAsset {
        let id = UUID()
        return ImportedAsset(id: id, sourceKey: "boundary-\(id)", fileName: "\(id).png",
            sha256: String(repeating: "c", count: 64), byteCount: 100, pixelWidth: 8,
            pixelHeight: 8, mediaType: "image/png", origin: .synthetic)
    }
    private func target(_ draft: String = "1") -> TargetLease {
        TargetLease(adapterID: "recovery-fixture", surface: .webChat, applicationID: "fixture.browser",
            sessionID: "fixture-session", windowID: "window", tabID: "tab", documentID: "document",
            composerID: "composer", draftGeneration: draft)
    }
    private func evidence(_ op: TransferOperation, _ image: ImportedAsset,
                          outcome: ReceiptOutcome = .verifiedReady, attempt: Int? = nil,
                          hash: String? = nil, assetID: UUID? = nil, target: TargetLease? = nil) -> TransferReceipt {
        TransferReceipt(operationID: op.id, assetID: assetID ?? image.id, attempt: attempt ?? op.attempt,
            assetSHA256: hash ?? image.sha256, target: target ?? op.target, outcome: outcome,
            profileID: "boundary-synthetic-v1", attachmentID: "synthetic-\(op.id)",
            positiveReady: outcome == .verifiedReady, belongsToOriginalDraft: true,
            hasError: outcome == .definitiveFailure, safeToRetry: outcome == .definitiveFailure,
            reason: "Synthetic boundary fixture; no browser input")
    }
    private var policy: ReceiptPolicy {
        ReceiptPolicy(admittedProfiles: ["boundary-synthetic-v1": .webChat],
                      retrySafeProfiles: ["boundary-synthetic-v1": .webChat])
    }

    func testReceiptBeforeIntentRollsBackWithoutSavingEvidence() async throws {
        let db = try store(); let a = image(); _ = try await db.importAsset(a)
        let op = try await db.prepare(assetID: a.id, target: target())
        do { _ = try await db.apply(evidence(op, a), policy: policy); XCTFail("No durable input intent") }
        catch RiftletError.invalidTransition {}
        let saved = try await db.receipt(for: op.id)
        let actual = try await db.operation(id: op.id)
        XCTAssertNil(saved); XCTAssertEqual(actual?.phase, .prepared)
    }

    func testEveryIdentityMismatchLeavesOriginalOperationAndEvidenceUntouched() async throws {
        let db = try store(); let a = image(); _ = try await db.importAsset(a)
        let op = try await db.prepare(assetID: a.id, target: target()); try await db.markDispatchIntent(op.id)
        let original = evidence(op, a, outcome: .unknown)
        _ = try await db.apply(original, policy: policy)
        let wrong = [evidence(op, a, attempt: 2), evidence(op, a, hash: String(repeating: "d", count: 64)),
                     evidence(op, a, assetID: UUID()), evidence(op, a, target: target("other-draft"))]
        for receipt in wrong {
            do { _ = try await db.apply(receipt, policy: policy); XCTFail("Mismatched identity was consumed") }
            catch RiftletError.mismatchedReceipt {}
        }
        let reopened = try store()
        let saved = try await reopened.receipt(for: op.id)
        let record = try await reopened.asset(id: a.id)
        XCTAssertEqual(saved, original); XCTAssertEqual(record?.status, .unknown)
        XCTAssertEqual(record?.activeOperationID, op.id)
    }

    func testTerminalSuccessCannotBeReversedByUncorrelatedLateObservation() async throws {
        let db = try store(); let a = image(); _ = try await db.importAsset(a)
        let op = try await db.prepare(assetID: a.id, target: target()); try await db.markDispatchIntent(op.id)
        let success = evidence(op, a)
        _ = try await db.apply(success, policy: policy)
        for outcome in [ReceiptOutcome.unknown, .attachedCandidate] {
            let result = try await db.apply(evidence(op, a, outcome: outcome), policy: policy)
            XCTAssertEqual(result.status, .used)
        }
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        let saved = try await reopened.receipt(for: op.id)
        let operation = try await reopened.operation(id: op.id)
        XCTAssertEqual(saved, success); XCTAssertEqual(operation?.phase, .succeeded)
    }

    func testAssetWriteFailureRollsBackOperationAndReceiptTogether() async throws {
        let db = try store(); let a = image(); _ = try await db.importAsset(a)
        let op = try await db.prepare(assetID: a.id, target: target()); try await db.markDispatchIntent(op.id)
        // A real SQLite abort after the operation UPDATE models a later write failure.
        // This connection and trigger are confined to this temporary test database.
        let fault = try SQLiteDatabase(url: root.appendingPathComponent("queue.sqlite"))
        try fault.execute("""
            CREATE TRIGGER fail_asset_write BEFORE UPDATE ON assets
            BEGIN SELECT RAISE(ABORT, 'synthetic storage fault'); END
            """)
        let success = evidence(op, a)
        do { _ = try await db.apply(success, policy: policy); XCTFail("Fault did not abort the transaction") }
        catch RiftletError.database {}
        let reopened = try store()
        let operation = try await reopened.operation(id: op.id)
        let record = try await reopened.asset(id: a.id)
        let receipt = try await reopened.receipt(for: op.id)
        XCTAssertEqual(operation?.phase, .dispatchIntent)
        XCTAssertEqual(record?.status, .transferring)
        XCTAssertNil(receipt)

        try fault.execute("DROP TRIGGER fail_asset_write")
        let completed = try await db.apply(success, policy: policy)
        let saved = try await reopened.receipt(for: op.id)
        XCTAssertEqual(completed.status, .used); XCTAssertEqual(saved, success)
    }

    func testOldSuccessfulReceiptCannotConsumeNewAttemptAfterProvedFailure() async throws {
        let db = try store(); let a = image(); _ = try await db.importAsset(a)
        let first = try await db.prepare(assetID: a.id, target: target()); try await db.markDispatchIntent(first.id)
        let failure = evidence(first, a, outcome: .definitiveFailure)
        _ = try await db.apply(failure, policy: policy)
        let second = try await db.prepare(assetID: a.id, target: target())
        try await db.markDispatchIntent(second.id)
        do { _ = try await db.apply(evidence(first, a), policy: policy); XCTFail("Old success consumed new attempt") }
        catch RiftletError.mismatchedReceipt {}
        let savedFailure = try await db.receipt(for: first.id)
        let currentReceipt = try await db.receipt(for: second.id)
        let record = try await db.asset(id: a.id)
        XCTAssertEqual(savedFailure, failure); XCTAssertNil(currentReceipt)
        XCTAssertEqual(record?.status, .transferring); XCTAssertEqual(record?.activeOperationID, second.id)
    }

    func testRestartKeepsMissingMediaAndUnknownTargetLockUntilVerifiedRestore() async throws {
        let db = try store(); let a = image(); let b = image()
        _ = try await db.importAsset(a); _ = try await db.importAsset(b)
        let first = try await db.prepare(assetID: a.id, target: target()); try await db.markDispatchIntent(first.id)
        try await db.markMissingAsset(a.id)
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        try await reopened.recoverInterruptedOperations()
        let missing = try await reopened.asset(id: a.id)
        let operation = try await reopened.operation(id: first.id)
        XCTAssertEqual(missing?.status, .missing); XCTAssertEqual(operation?.phase, .unknown)
        let second = try await reopened.prepare(assetID: b.id, target: target())
        do { try await reopened.markDispatchIntent(second.id); XCTFail("Missing media released original target") }
        catch RiftletError.targetBusy {}
        try await reopened.restoreMissingAsset(a.id)
        let restored = try await reopened.asset(id: a.id)
        XCTAssertEqual(restored?.status, .unknown); XCTAssertEqual(restored?.activeOperationID, first.id)
    }

    func testFailedObservationKeepsMissingMediaButRemoteSuccessCanFinish() async throws {
        for outcome in [ReceiptOutcome.definitiveFailure, .verifiedReady] {
            let db = try QueueStore(databaseURL: root.appendingPathComponent("\(outcome.rawValue).sqlite"))
            let a = image(); _ = try await db.importAsset(a)
            let op = try await db.prepare(assetID: a.id, target: target()); try await db.markDispatchIntent(op.id)
            try await db.markMissingAsset(a.id)
            let result = try await db.apply(evidence(op, a, outcome: outcome), policy: policy)
            XCTAssertEqual(result.status, outcome == .verifiedReady ? .used : .missing)
            try await db.restoreMissingAsset(a.id)
            let restored = try await db.asset(id: a.id)
            XCTAssertEqual(restored?.status, outcome == .verifiedReady ? .used : .failed)
        }
    }
}
