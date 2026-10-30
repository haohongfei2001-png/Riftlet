import Foundation
import XCTest
@testable import RiftletCore

final class DispatchLifecycleTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dispatch-lifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func store() throws -> QueueStore { try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite")) }
    private func target(_ draft: String = "00000000-0000-0000-0000-000000000001", epoch: String = "1") -> TargetLease {
        TargetLease(adapterID: "lifecycle-fixture", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "fixture-process", windowID: "1", tabID: "1", documentID: "doc", composerID: "composer",
            draftGeneration: epoch, logicalDraftIdentity: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1", id: draft))
    }
    private var policy: ReceiptPolicy {
        .init(syntheticAcceptanceProfiles: ["fixture-ready": .webChat],
              syntheticUploadStartProfiles: ["fixture-start": .webChat],
              syntheticContinuationProfiles: ["fixture-independent": .webChat])
    }
    private func asset(_ db: QueueStore) async throws -> ImportedAsset {
        let id = UUID(), bytes = Data("local fixture".utf8)
        let a = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1,
            mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: directory.appendingPathComponent(a.fileName)); _ = try await db.importAsset(a); return a
    }
    private func selection(_ a: ImportedAsset, target: TargetLease) -> AcceptedSelection {
        let now = ProcessInfo.processInfo.systemUptime
        return .init(assetID: a.id, target: target, hostEpoch: UUID(), acknowledgedUptime: now - 0.02,
            eventUptime: now - 0.01, acceptedUptime: now, visibilityRevision: 0, deadlineUptime: now + 30)
    }
    private func receipt(_ op: TransferOperation, _ a: ImportedAsset, _ nonce: UUID,
                         outcome: ReceiptOutcome = .uploadStarted, continuation: Bool = true,
                         attachment: String? = nil) -> TransferReceipt {
        .init(operationID: op.id, assetID: a.id, attempt: op.attempt, assetSHA256: a.sha256, target: op.target,
            outcome: outcome, profileID: "fixture-ready", attachmentID: attachment ?? "attachment-\(op.id)",
            positiveReady: outcome == .verifiedReady, belongsToOriginalDraft: true,
            hasError: outcome == .definitiveFailure, isUploading: outcome == .uploadStarted,
            uploadStartEvidence: outcome == .uploadStarted ? .init(profileID: "fixture-start", signal: .correlatedProgress, evidenceID: "start-\(op.id)") : nil,
            continuationEvidence: continuation && outcome == .uploadStarted ? .init(profileID: "fixture-independent", evidenceID: "isolation-\(op.id)", invocationID: nonce) : nil)
    }
    private func started(_ db: QueueStore, owner: UUID, continuation: Bool = true, returned: Bool = true) async throws -> (ImportedAsset, TransferOperation, UUID) {
        let a = try await asset(db), t = target()
        let op = try await db.prepare(assetID: a.id, target: t)
        let nonce = try await db.markDispatchIntent(op.id, ownerID: owner)
        let r = receipt(op, a, nonce, continuation: continuation)
        _ = try await db.apply(r, policy: policy)
        if returned { try await db.recordAppendReturned(r, invocationID: nonce, ownerID: owner) }
        try await db.markUnknown(op.id, reason: "fixture only")
        return (a, op, nonce)
    }
    private func expectBusy(_ db: QueueStore, owner: UUID, t: TargetLease? = nil, p: ReceiptPolicy? = nil) async throws {
        let a = try await asset(db), target = t ?? target()
        let b = try await db.prepare(assetID: a.id, target: target)
        do { try await db.markDispatchIntent(b.id, selection: selection(a, target: target), ownerID: owner, policy: p ?? policy); XCTFail("must retain original conflict") }
        catch RiftletError.targetBusy {}
    }

    func testFortyEightIndependentStartedOperationsRetainOriginalIdentities() async throws {
        let db = try store(), owner = UUID(), t = target()
        var ids = Set<UUID>(), attachments = Set<String>()
        for _ in 0..<48 {
            let a = try await asset(db), op = try await db.prepare(assetID: a.id, target: t)
            let nonce = try await db.markDispatchIntent(op.id, selection: selection(a, target: t), ownerID: owner, policy: policy)
            let r = receipt(op, a, nonce); _ = try await db.apply(r, policy: policy)
            try await db.recordAppendReturned(r, invocationID: nonce, ownerID: owner)
            try await db.markUnknown(op.id, reason: "independently observed fixture remains pending")
            ids.insert(op.id); attachments.insert(r.attachmentID!)
        }
        let unresolved = try await db.unresolvedOperations()
        XCTAssertEqual(ids.count, 48); XCTAssertEqual(attachments.count, 48); XCTAssertEqual(unresolved.count, 48)
        for op in unresolved { let start = try await db.uploadStartReceipt(for: op.id); XCTAssertNotNil(start); XCTAssertEqual(op.phase, .unknown) }
    }

    func testStartAloneAndAppendStillRunningCannotReleaseConflict() async throws {
        let db = try store(), owner = UUID(); _ = try await started(db, owner: owner, returned: false)
        try await expectBusy(db, owner: owner)
    }
    func testNoIndependentProfileAndWrongOwnerAndNewEpochRemainLocked() async throws {
        let db = try store(), owner = UUID(); _ = try await started(db, owner: owner)
        try await expectBusy(db, owner: UUID()) // restarted coordinator cannot inherit authority
        try await expectBusy(db, owner: owner, t: target(epoch: "2"))
        try await expectBusy(db, owner: owner, p: .init(syntheticUploadStartProfiles: ["fixture-start": .webChat]))
    }
    func testNoContinuationEvidenceRemainsLocked() async throws {
        let db = try store(), owner = UUID(); _ = try await started(db, owner: owner, continuation: false)
        try await expectBusy(db, owner: owner)
    }
    func testUnownedInvocationAndUnknownCommitRemainLocked() async throws {
        let db = try store(), owner = UUID(), a = try await asset(db)
        let op = try await db.prepare(assetID: a.id, target: target())
        _ = try await db.markDispatchIntent(op.id) // no continuing runtime owner, no start
        try await db.markUnknown(op.id, reason: "commit reply lost")
        try await expectBusy(db, owner: owner)
        try await db.recoverInterruptedOperations()
        try await expectBusy(db, owner: UUID())
    }
    func testLegacyV3OperationWithoutCallCheckpointStaysLocked() async throws {
        let db = try store(), a = try await asset(db)
        let op = try await db.prepare(assetID: a.id, target: target())
        // Construct an isolated historical v3 row without calling the new intent
        // writer. No current or user operation/checkpoint is removed.
        let legacy = try SQLiteDatabase(url: directory.appendingPathComponent("queue.sqlite"))
        try legacy.execute("UPDATE operations SET phase='unknown' WHERE id=?", [op.id.uuidString])
        try legacy.execute("UPDATE assets SET status='unknown' WHERE id=?", [a.id.uuidString])
        let nonce = try await db.dispatchInvocationID(for: op.id); XCTAssertNil(nonce)
        try await expectBusy(db, owner: UUID())
        try await db.recoverInterruptedOperations()
        let after = try await db.dispatchInvocationID(for: op.id); XCTAssertNil(after)
    }

    func testTwoConnectionsSerializeFollowingIntentAndRejectAttachmentAlias() async throws {
        let db = try store(), second = try store(), owner = UUID(); let (a, _, _) = try await started(db, owner: owner)
        let b = try await asset(db), c = try await asset(db), t = target()
        let bo = try await db.prepare(assetID: b.id, target: t), co = try await second.prepare(assetID: c.id, target: t)
        let bs = selection(b, target: t), cs = selection(c, target: t)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { do { try await db.markDispatchIntent(bo.id, selection: bs, ownerID: owner, policy: self.policy); return true } catch { return false } }
            group.addTask { do { try await second.markDispatchIntent(co.id, selection: cs, ownerID: owner, policy: self.policy); return true } catch { return false } }
            var all: [Bool] = []; for await r in group { all.append(r) }; return all
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let bop = try await db.operation(id: bo.id)!, cop = try await db.operation(id: co.id)!
        let winner = bop.phase == .dispatchIntent ? bop : cop, image = bop.phase == .dispatchIntent ? b : c
        let original = try await db.asset(id: a.id)!, start = try await db.uploadStartReceipt(for: original.activeOperationID!)!
        do { _ = try await db.apply(receipt(winner, image, UUID(), outcome: .verifiedReady, attachment: start.attachmentID), policy: policy); XCTFail("alias") }
        catch RiftletError.mismatchedReceipt {}
    }
    func testIndependentBWithoutStartStillBlocksCWhenOriginalAFinishes() async throws {
        let db = try store(), owner = UUID(); let (a, ao, an) = try await started(db, owner: owner)
        let b = try await asset(db), bo = try await db.prepare(assetID: b.id, target: target())
        _ = try await db.markDispatchIntent(bo.id, selection: selection(b, target: target()), ownerID: owner, policy: policy)
        let sql = try SQLiteDatabase(url: directory.appendingPathComponent("queue.sqlite"))
        XCTAssertEqual(try sql.rows("SELECT dispatch_exclusive FROM operations WHERE id=?", [ao.id.uuidString]), [["1"]])
        XCTAssertEqual(try sql.rows("SELECT dispatch_exclusive FROM operations WHERE id=?", [bo.id.uuidString]), [["0"]])
        try await expectBusy(db, owner: owner)
        _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy)
        try await db.markUnknown(bo.id, reason: "B commit reply lost")
        try await expectBusy(db, owner: owner)
        let reopened = try store()
        try await expectBusy(reopened, owner: UUID())
    }

    func testLateACompensationDoesNotReassignBAndBlocksNextInput() async throws {
        let db = try store(), owner = UUID(); let (a, ao, an) = try await started(db, owner: owner)
        let b = try await asset(db), bo = try await db.prepare(assetID: b.id, target: target())
        let bn = try await db.markDispatchIntent(bo.id, selection: selection(b, target: target()), ownerID: owner, policy: policy)
        _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady), policy: policy)
        _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy)
        _ = try await db.apply(receipt(ao, a, an, outcome: .definitiveFailure), policy: policy)
        let aa = try await db.operation(id: ao.id), bb = try await db.operation(id: bo.id)
        XCTAssertEqual(aa?.phase, .compensated); XCTAssertEqual(bb?.phase, .succeeded)
        try await expectBusy(db, owner: owner)
    }
    func testRejectionNeedsOriginalNonceAndCannotClearUnknown() async throws {
        let db = try store(), a = try await asset(db), op = try await db.prepare(assetID: a.id, target: target())
        let nonce = try await db.markDispatchIntent(op.id)
        func proof(_ n: UUID) -> PreInputRejection { .init(operationID: op.id, assetID: a.id, attempt: op.attempt, assetSHA256: a.sha256, target: op.target, invocationID: n, stage: .pageRetiredBeforeCommit) }
        do { try await db.recordPreInputRejection(proof(UUID())); XCTFail("nonce") } catch RiftletError.mismatchedReceipt {}
        try await db.recordPreInputRejection(proof(nonce))
        let first = try await db.operation(id: op.id); XCTAssertEqual(first?.phase, .failed)
        let next = try await db.prepare(assetID: a.id, target: target()); XCTAssertNotEqual(next.id, op.id); XCTAssertEqual(next.attempt, 2)
        let nextNonce = try await db.markDispatchIntent(next.id)
        try await db.markUnknown(next.id, reason: "commit uncertain")
        do { try await db.recordPreInputRejection(.init(operationID: next.id, assetID: a.id, attempt: next.attempt, assetSHA256: a.sha256, target: next.target, invocationID: nextNonce, stage: .localBeforeBegin)); XCTFail("unknown") }
        catch RiftletError.mismatchedReceipt {}
        let same = try await db.prepare(assetID: a.id, target: target()); XCTAssertEqual(same.id, next.id)
    }
    func testCoordinatorStartedAThenIndependentBSuccessOrFailureNeverReplaysA() async throws {
        for bFails in [false, true] {
            let root = directory.appendingPathComponent(UUID().uuidString)
            let db = try QueueStore(databaseURL: root)
            let a = try await asset(db), b = try await asset(db)
            let adapter = LifecycleContinuingAdapter(bFails: bFails)
            let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory,
                policy: policy, validateAcceptedSelection: { _ in true })
            try await coordinator.select(selection(a, target: target()))
            try await coordinator.select(selection(b, target: target()))
            let calls = await adapter.calls
            XCTAssertEqual(calls, [a.id, b.id])
            let ar = try await db.asset(id: a.id)!, br = try await db.asset(id: b.id)!
            let ao = try await db.operation(id: ar.activeOperationID!)!, bo = try await db.operation(id: br.activeOperationID!)!
            XCTAssertNotEqual(ao.id, bo.id)
            XCTAssertEqual(ao.phase, .inputTriggered)
            XCTAssertEqual(bo.phase, bFails ? .unknown : .succeeded)
            try await coordinator.observePending()
            let afterObservation = await adapter.calls; XCTAssertEqual(afterObservation, [a.id, b.id])
        }
    }

    func testCoordinatorRetiresOnlyCurrentTypedRejection() async throws {
        let db = try store(), a = try await asset(db), ao = try await db.prepare(assetID: a.id, target: target())
        let nonce = try await db.markDispatchIntent(ao.id)
        let proof = PreInputRejection(operationID: ao.id, assetID: a.id, attempt: ao.attempt, assetSHA256: a.sha256, target: ao.target, invocationID: nonce, stage: .localBeforeBegin)
        let b = try await asset(db), adapter = LifecycleRejectAdapter(other: proof)
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory)
        try await coordinator.select(b.id, frozenTarget: target("00000000-0000-0000-0000-000000000002"))
        let aFinal = try await db.operation(id: ao.id), bRecord = try await db.asset(id: b.id)!
        let bFinal = try await db.operation(id: bRecord.activeOperationID!)
        XCTAssertEqual(aFinal?.phase, .dispatchIntent); XCTAssertEqual(bFinal?.phase, .unknown)
    }
    func testCoordinatorNoInputRejectionPreservesImageAndRequiresNewClick() async throws {
        let db = try store(), a = try await asset(db), adapter = LifecycleRejectAdapter(other: nil)
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory)
        try await coordinator.select(a.id, frozenTarget: target())
        let first = try await db.asset(id: a.id)!; XCTAssertEqual(first.status, .failed); XCTAssertEqual(first.visibility, .visible)
        let firstCount = await adapter.count; XCTAssertEqual(firstCount, 1)
        try await coordinator.observePending(); let unchanged = await adapter.count; XCTAssertEqual(unchanged, 1)
        try await coordinator.select(a.id, frozenTarget: target())
        let second = try await db.asset(id: a.id)!; XCTAssertNotEqual(first.activeOperationID, second.activeOperationID)
        let secondCount = await adapter.count; XCTAssertEqual(secondCount, 2)
    }
}

private actor LifecycleRejectAdapter: AttachmentAdapter {
    nonisolated let id = "lifecycle-fixture"
    let other: PreInputRejection?
    var count = 0
    init(other: PreInputRejection?) { self.other = other }
    func captureTarget() async throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) async throws -> Bool { true }
    func append(_ r: TransferRequest) async throws -> TransferReceipt {
        count += 1
        if let other { throw other }
        throw PreInputRejection(operationID: r.operation.id, assetID: r.asset.id, attempt: r.operation.attempt,
            assetSHA256: r.asset.sha256, target: r.operation.target, invocationID: r.invocationID!, stage: .localBeforeBegin)
    }
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt { throw RiftletError.invalidTransition }
}

private actor LifecycleContinuingAdapter: AttachmentAdapter {
    nonisolated let id = "lifecycle-fixture"
    let bFails: Bool
    var calls: [UUID] = []
    init(bFails: Bool) { self.bFails = bFails }
    func captureTarget() async throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) async throws -> Bool { true }
    func append(_ r: TransferRequest) async throws -> TransferReceipt {
        calls.append(r.asset.id)
        let first = calls.count == 1
        return TransferReceipt(operationID: r.operation.id, assetID: r.asset.id, attempt: r.operation.attempt,
            assetSHA256: r.asset.sha256, target: r.operation.target,
            outcome: first ? .uploadStarted : (bFails ? .definitiveFailure : .verifiedReady),
            profileID: "fixture-ready", attachmentID: "attachment-\(r.operation.id)",
            positiveReady: !first && !bFails, belongsToOriginalDraft: true,
            hasError: !first && bFails, isUploading: first,
            uploadStartEvidence: first ? .init(profileID: "fixture-start", signal: .correlatedProgress, evidenceID: "start-\(r.operation.id)") : nil,
            continuationEvidence: first ? .init(profileID: "fixture-independent", evidenceID: "independent-\(r.operation.id)", invocationID: r.invocationID!) : nil)
    }
    func reconcile(_ r: TransferRequest) async throws -> TransferReceipt {
        .init(operationID: r.operation.id, assetID: r.asset.id, attempt: r.operation.attempt,
            assetSHA256: r.asset.sha256, target: r.operation.target, outcome: .unknown,
            profileID: "fixture-ready", attachmentID: "attachment-\(r.operation.id)", belongsToOriginalDraft: true)
    }
}
