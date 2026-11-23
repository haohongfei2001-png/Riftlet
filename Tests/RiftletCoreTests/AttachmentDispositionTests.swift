import Foundation
import XCTest
@testable import RiftletCore

final class AttachmentDispositionTests: XCTestCase {
    func testNamedDraftFailureWithoutStartSurvivesRestartAndOnlyExplicitDispositionUnlocksCleanup() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("queue.sqlite")
        let store = try QueueStore(databaseURL: path)
        let asset = ImportedAsset(sourceKey: "failed-card", fileName: "image.png", sha256: String(repeating: "a", count: 64),
            byteCount: 1, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .systemScreenshot)
        _ = try await store.importAsset(asset)
        let op = try await store.prepare(assetID: asset.id, target: DispositionAdapter().target)
        let owner = UUID()
        let invocation = try await store.markIndependentFileInputIntent(op.id, ownerID: owner)
        func report(_ call: UUID?, card: String? = "original") -> TransferReceipt {
            .init(operationID: op.id, assetID: asset.id, attempt: op.attempt, assetSHA256: asset.sha256,
                  target: op.target, outcome: .unknown, profileID: "test", attachmentID: card,
                  belongsToOriginalDraft: true, hasError: call != nil, originalCardFailureInvocationID: call)
        }
        do { _ = try await store.apply(report(UUID())); XCTFail("Wrong invocation accepted") }
        catch RiftletError.mismatchedReceipt {}
        let kept = try await store.apply(report(invocation))
        XCTAssertEqual(kept.visibility, .visible)
        try await store.recordInputExecutionReturned(operationID: op.id, invocationID: invocation, ownerID: owner)
        do { _ = try await store.apply(report(invocation, card: "other")); XCTFail("Different card accepted") }
        catch RiftletError.mismatchedReceipt {}
        _ = try await store.apply(report(nil, card: nil))
        let reopened = try QueueStore(databaseURL: path)
        for filter: HistoryQuery.Filter in [.failed, .needsVerification, .needsAttention] {
            let page = try await reopened.historyPage(query: .init(filter: filter), offset: 0, throughSequence: nil)
            XCTAssertEqual(page.records.map(\.attachmentState), [.originalCardFailed])
        }
        let start = try await reopened.uploadStartReceipt(for: op.id)
        XCTAssertNil(start)
        let state = try await reopened.operation(id: op.id)
        XCTAssertEqual(state?.phase, .unknown)
        XCTAssertEqual(state?.attempt, 1)
        let staged = try await reopened.stageAttachmentForReattach(operationID: op.id)
        XCTAssertEqual(staged.activeOperationID, op.id)
        try await reopened.removeFromQueue(asset.id)
        let protected = try await reopened.cleanableMedia()
        XCTAssertTrue(protected.isEmpty)
        try await reopened.markAttachmentHandled(operationID: op.id)
        let cleanable = try await reopened.cleanableMedia()
        XCTAssertEqual(cleanable.map(\.id), [asset.id])
        let persisted = try await reopened.receipt(for: op.id)
        XCTAssertEqual(persisted, report(invocation))
    }

    func testOriginalStartLocalCleanupAndExplicitNewIntentAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.sqlite")
        let store = try QueueStore(databaseURL: url)
        let adapter = DispositionAdapter()
        let asset = ImportedAsset(sourceKey: "one", fileName: "one.png", sha256: String(repeating: "a", count: 64),
            byteCount: 1, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try Data([1]).write(to: directory.appendingPathComponent(asset.fileName))
        _ = try await store.importAsset(asset)
        let first = try await store.prepare(assetID: asset.id, target: adapter.target)
        let owner = UUID()
        let invocation = try await store.markIndependentFileInputIntent(first.id, ownerID: owner)
        let accepted = adapter.start(first, asset)
        let policy = ReceiptPolicy(syntheticUploadStartProfiles: ["fixture-start": .webChat])
        let swallowed = try await store.apply(accepted, policy: policy)
        XCTAssertEqual(swallowed.visibility, .swallowed)
        let active = try await store.cleanableMedia()
        XCTAssertTrue(active.isEmpty)
        try await store.recordInputExecutionReturned(operationID: first.id, invocationID: invocation, ownerID: owner)
        let cleanable = try await store.cleanableMedia()
        XCTAssertEqual(cleanable.map(\.id), [asset.id])
        try await store.retireMedia(asset.id, revision: swallowed.visibilityRevision, batch: UUID())
        let reopened = try QueueStore(databaseURL: url)
        let core = TransferCoordinator(store: reopened, adapter: adapter, mediaDirectory: directory, policy: policy,
                                       validateAcceptedSelection: { $0.isValid() })
        try await core.recover()
        let denied = try await core.recheckOriginal(operationID: first.id, authorize: { _ in false })
        XCTAssertEqual(denied, .permissionDenied)
        let missingReceiver = try await core.recheckOriginal(operationID: first.id, inspectAccess: { _ in .unavailable })
        XCTAssertEqual(missingReceiver, .unavailable)
        let observed = try await core.recheckOriginal(operationID: first.id, authorize: { $0 == adapter.target })
        XCTAssertEqual(observed, .observed)
        let failing = try await reopened.historyPage(query: .init(filter: .needsAttention), offset: 0, throughSequence: nil)
        XCTAssertEqual(failing.records.first?.attachmentState, .checkDraft)
        let visibleWhileRetired = try await reopened.isRetiredMedia(asset.id)
        XCTAssertTrue(visibleWhileRetired)
        try await reopened.reinstateMedia(asset.id, restoredByUserAt: Date())
        let errorProtected = try await reopened.cleanableMedia()
        XCTAssertTrue(errorProtected.isEmpty)
        try await reopened.markAttachmentHandled(operationID: first.id)
        let acknowledged = try await reopened.cleanableMedia()
        XCTAssertEqual(acknowledged.map(\.id), [asset.id])
        let count = try await reopened.pendingAttachmentReviewCount()
        XCTAssertEqual(count, 0)
        let attention = try await reopened.historyPage(query: .init(filter: .needsVerification), offset: 0, throughSequence: nil)
        XCTAssertTrue(attention.records.isEmpty)
        let callsBefore = await adapter.observedInvocations
        XCTAssertEqual(callsBefore, [invocation])
        let staged = try await reopened.stageAttachmentForReattach(operationID: first.id)
        let original = try await reopened.operation(id: first.id)
        XCTAssertEqual(staged.visibility, .visible)
        XCTAssertEqual(original?.phase, .unknown)
        let selection = AcceptedSelection(assetID: asset.id, target: adapter.freshTarget(), visibilityRevision: staged.visibilityRevision)
        try await core.reattach(selection, replacing: first.id)
        for _ in 0..<100 where await core.hasInFlightAttachmentWork { try await Task.sleep(nanoseconds: 2_000_000) }
        let attempts = await adapter.attempts
        XCTAssertEqual(attempts, [2])
        let appendedSources = await adapter.appendedSources
        XCTAssertEqual(appendedSources.map(\.invocationID), [invocation])
        XCTAssertEqual(appendedSources.first?.originalStart, accepted)
        let previousReceipt = try await reopened.uploadStartReceipt(for: first.id)
        let previousCall = try await reopened.dispatchInvocationID(for: first.id)
        let previousOperation = try await reopened.operation(id: first.id)
        XCTAssertEqual(previousReceipt, accepted)
        XCTAssertEqual(previousCall, invocation)
        XCTAssertEqual(previousOperation, original)
        let after = try QueueStore(databaseURL: url)
        let newAsset = try await after.asset(id: asset.id)
        XCTAssertNotEqual(newAsset?.activeOperationID, first.id)
    }

    func testCrashedIntentDoesNotUnlockCleanupOrPermanentlyBlockExplicitNewIntent() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.sqlite")
        let store = try QueueStore(databaseURL: path)
        let adapter = DispositionAdapter()
        let asset = ImportedAsset(sourceKey: "unknown", fileName: "old.png", sha256: String(repeating: "b", count: 64),
                                  byteCount: 1, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try Data([2]).write(to: dir.appendingPathComponent(asset.fileName))
        _ = try await store.importAsset(asset)
        let old = try await store.prepare(assetID: asset.id, target: adapter.target)
        let invocation = try await store.markIndependentFileInputIntent(old.id, ownerID: UUID())
        try await store.removeFromQueue(asset.id)
        let reopened = try QueueStore(databaseURL: path)
        let core = TransferCoordinator(store: reopened, adapter: adapter, mediaDirectory: dir,
            policy: .init(syntheticUploadStartProfiles: ["fixture-start": .webChat]), validateAcceptedSelection: { $0.isValid() })
        try await core.recover()
        let candidates = try await reopened.cleanableMedia()
        XCTAssertTrue(candidates.isEmpty)
        try await reopened.markAttachmentHandled(operationID: old.id)
        let stillProtected = try await reopened.cleanableMedia()
        XCTAssertTrue(stillProtected.isEmpty)
        let staged = try await reopened.stageAttachmentForReattach(operationID: old.id)
        let wrong = AcceptedSelection(assetID: asset.id, target: adapter.freshTarget(), visibilityRevision: staged.visibilityRevision - 1)
        do {
            try await core.reattach(wrong, replacing: old.id)
            XCTFail("A stale click initiated a replacement")
        } catch RiftletError.invalidTransition {}
        let unchanged = try await reopened.operation(id: old.id)
        XCTAssertEqual(unchanged?.phase, .dispatchIntent)
        let click = AcceptedSelection(assetID: asset.id, target: adapter.freshTarget(), visibilityRevision: staged.visibilityRevision)
        try await core.reattach(click, replacing: old.id)
        for _ in 0..<100 where await core.hasInFlightAttachmentWork { try await Task.sleep(nanoseconds: 2_000_000) }
        let attempts = await adapter.attempts
        XCTAssertEqual(attempts, [2])
        let preserved = try await reopened.dispatchInvocationID(for: old.id)
        XCTAssertEqual(preserved, invocation)
        let previousStart = try await reopened.uploadStartReceipt(for: old.id)
        XCTAssertEqual(previousStart, nil)
        let returned = try await reopened.inputExecutionIsActive(for: old.id)
        XCTAssertTrue(returned) // historical missing return remains a fact
        let nowCleanable = try await reopened.cleanableMedia()
        XCTAssertEqual(nowCleanable.map(\.id), [asset.id])
    }

    func testUnknownReselectionRequiresNewPinSameDraftAndLivePermission() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("queue.sqlite")
        let store = try QueueStore(databaseURL: url)
        let adapter = DispositionAdapter()
        let image = ImportedAsset(sourceKey: "unknown", fileName: "original.png", sha256: String(repeating: "1", count: 64),
            byteCount: 1, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try Data([1]).write(to: dir.appendingPathComponent(image.fileName))
        _ = try await store.importAsset(image)
        let old = try await store.prepare(assetID: image.id, target: adapter.target)
        let owner = UUID()
        let invocation = try await store.markIndependentFileInputIntent(old.id, ownerID: owner)
        let policy = ReceiptPolicy(syntheticUploadStartProfiles: ["fixture-start": .webChat])
        let start = adapter.start(old, image)
        _ = try await store.apply(start, policy: policy)
        try await store.recordAppendReturned(start, invocationID: invocation, ownerID: owner)
        try await store.markUnknown(old.id, reason: "Original result uncertain")
        let sql = try SQLiteDatabase(url: url)
        func originalLedger() throws -> [[String?]] {
            try sql.rows("SELECT * FROM operations WHERE id=?", [old.id.uuidString]) +
                sql.rows("SELECT * FROM upload_starts WHERE operation_id=?", [old.id.uuidString]) +
                sql.rows("SELECT * FROM checkpoints WHERE key=?", ["transfer-dispatch-call-v1:" + old.id.uuidString])
        }
        let before = try originalLedger()
        let staged = try await store.stageAttachmentForReattach(operationID: old.id)
        let core = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: dir, policy: policy,
            validateAcceptedSelection: { $0.isValid() })
        func click(_ target: TargetLease) -> AcceptedSelection {
            AcceptedSelection(assetID: image.id, target: target, visibilityRevision: staged.visibilityRevision)
        }
        for denied in [old.target, adapter.freshTarget(document: "another"), adapter.freshTarget(epoch: "renewed")] {
            do { try await core.reattach(click(denied), replacing: old.id); XCTFail("Stale or different draft accepted") }
            catch RiftletError.invalidTransition {}
        }
        await adapter.setCanRecover(false)
        do { try await core.reattach(click(adapter.freshTarget()), replacing: old.id); XCTFail("Original card still present") }
        catch RiftletError.invalidTransition {}
        XCTAssertEqual(try originalLedger(), before)
        XCTAssertEqual(try sql.rows("SELECT COUNT(*) FROM operations"), [["1"]])
        await adapter.setCanRecover(true)
        let first = click(adapter.freshTarget()), second = click(adapter.freshTarget())
        async let selectionOne: Void? = try? core.reattach(first, replacing: old.id)
        async let selectionTwo: Void? = try? core.reattach(second, replacing: old.id)
        _ = await (selectionOne, selectionTwo)
        for _ in 0..<100 where await core.hasInFlightAttachmentWork { try await Task.sleep(nanoseconds: 2_000_000) }
        let asset = try await store.asset(id: image.id)
        let newID = try XCTUnwrap(asset?.activeOperationID)
        XCTAssertNotEqual(newID, old.id)
        let newInvocation = try await store.dispatchInvocationID(for: newID)
        XCTAssertNotNil(newInvocation)
        XCTAssertNotEqual(invocation, newInvocation)
        XCTAssertEqual(try originalLedger(), before)
        XCTAssertEqual(try sql.rows("SELECT successor_id,predecessor_id FROM attachment_reselections"), [[newID.uuidString, old.id.uuidString]])
        XCTAssertEqual(try sql.rows("SELECT COUNT(*) FROM upload_starts"), [["2"]])
        let attempts = await adapter.attempts
        XCTAssertEqual(attempts, [2])
        let reopened = try QueueStore(databaseURL: url)
        let nextCoordinator = TransferCoordinator(store: reopened, adapter: adapter, mediaDirectory: dir)
        try await nextCoordinator.recover()
        XCTAssertEqual(try originalLedger(), before)
        XCTAssertEqual(try sql.rows("SELECT COUNT(*) FROM operations"), [["2"]])
    }

    func testPreInputCancellationRestoresOriginalGuardAndConcurrentStoresCannotSpendSameRecovery() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("queue.sqlite")
        let left = try QueueStore(databaseURL: path)
        let right = try QueueStore(databaseURL: path)
        let adapter = DispositionAdapter()
        let image = ImportedAsset(sourceKey: "original", fileName: "original.png", sha256: String(repeating: "a", count: 64),
            byteCount: 10, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .systemScreenshot)
        _ = try await left.importAsset(image)
        let old = try await left.prepare(assetID: image.id, target: adapter.target)
        let owner = UUID()
        let invocation = try await left.markIndependentFileInputIntent(old.id, ownerID: owner)
        let sql = try SQLiteDatabase(url: path)
        func originalLedger() throws -> [[String?]] {
            try sql.rows("SELECT * FROM operations WHERE id=?", [old.id.uuidString]) +
                sql.rows("SELECT * FROM upload_starts WHERE operation_id=?", [old.id.uuidString]) +
                sql.rows("SELECT * FROM checkpoints WHERE key LIKE ?", ["%" + old.id.uuidString])
        }
        let before = try originalLedger()
        let source = try await left.attachmentRecoverySource(operationID: old.id)
        let a = adapter.freshTarget(), b = adapter.freshTarget()
        async let first: TransferOperation? = try? left.prepare(assetID: image.id, target: a, replacing: source)
        async let other: TransferOperation? = try? right.prepare(assetID: image.id, target: b, replacing: source)
        let attempts = await [first, other].compactMap { $0 }
        XCTAssertEqual(attempts.count, 1)
        let tentative = try XCTUnwrap(attempts.first)
        try await right.recoverUndispatchedPreparations()
        let restored = try await right.asset(id: image.id)
        XCTAssertEqual(restored?.activeOperationID, old.id)
        let noBypass = try await right.prepare(assetID: image.id, target: adapter.freshTarget(document: "different"))
        XCTAssertEqual(noBypass.id, old.id)
        let retained = try await right.operation(id: tentative.id)
        XCTAssertEqual(retained?.phase, .failed)
        // A different writer still holding the old invocation can deliver these
        // callbacks after the original becomes the active recovery source again.
        try await left.markUnknown(old.id, reason: "Late fallback")
        let late = adapter.start(old, image)
        _ = try await left.apply(late)
        do { try await left.recordAppendReturned(late, invocationID: invocation, ownerID: owner); XCTFail("Changed old return") }
        catch RiftletError.mismatchedReceipt {}
        do { try await left.recordInputExecutionReturned(operationID: old.id, invocationID: invocation, ownerID: owner); XCTFail("Changed old call") }
        catch RiftletError.mismatchedReceipt {}
        let noInput = PreInputRejection(operationID: old.id, assetID: image.id, attempt: old.attempt,
            assetSHA256: image.sha256, target: old.target, invocationID: invocation, stage: .pageRetiredBeforeCommit)
        do { try await left.recordPreInputRejection(noInput); XCTFail("Reclassified old invocation") }
        catch RiftletError.mismatchedReceipt {}
        do { try await left.saveCheckpoint(Data([0]), for: "transfer-dispatch-call-v1:" + old.id.uuidString); XCTFail("Overwrote original invocation") }
        catch RiftletError.database {}
        do { _ = try await left.claimDispatchCheckpoint(Data([1]), for: "late-registration", operation: source.operation, asset: image); XCTFail("Enrolled old dispatch") }
        catch RiftletError.invalidTransition {}
        try await left.recoverInterruptedOperations()
        XCTAssertEqual(try originalLedger(), before)
        let again = try await right.prepare(assetID: image.id, target: adapter.freshTarget(), replacing: source)
        XCTAssertEqual(again.attempt, 3)
        XCTAssertEqual(try sql.rows("SELECT COUNT(*) FROM attachment_reselections"), [["2"]])
        XCTAssertEqual(try sql.rows("PRAGMA foreign_key_check"), [])
    }

}

private actor DispositionAdapter: OriginalAttachmentRecoveryChecking {
    nonisolated let id = "test-adapter"
    nonisolated let supportsOriginalHandoffChecks = true
    nonisolated let target = TargetLease(adapterID: "test-adapter", surface: .webChat, applicationID: "com.google.Chrome",
        sessionID: "fixture", windowID: "1", tabID: "1", documentID: "doc", composerID: "composer", draftGeneration: "1", clickBindingID: UUID())
    nonisolated func freshTarget(document: String = "doc", epoch: String = "1") -> TargetLease {
        TargetLease(adapterID: id, surface: .webChat, applicationID: target.applicationID,
                    sessionID: target.sessionID, windowID: target.windowID, tabID: target.tabID,
                    documentID: document, composerID: target.composerID, draftGeneration: epoch, clickBindingID: UUID())
    }
    var canRecover = true
    func setCanRecover(_ value: Bool) { canRecover = value }
    func checkRecovery(_ original: TransferRequest, destination: TargetLease) -> Bool {
        guard let source = original.recoverySource else { return false }
        return canRecover && original.requireLiveOriginal && original.operation == source.operation &&
            original.invocationID == source.invocationID && source.permitsDestination(destination)
    }
    var appendedSources = [AttachmentRecoverySource]()
    var attempts = [Int]()
    var observedInvocations = [UUID]()
    nonisolated func start(_ op: TransferOperation, _ asset: ImportedAsset) -> TransferReceipt {
        TransferReceipt(operationID: op.id, assetID: asset.id, attempt: op.attempt, assetSHA256: asset.sha256,
            target: op.target, outcome: .uploadStarted, profileID: "fixture", attachmentID: op.id.uuidString,
            belongsToOriginalDraft: true, uploadStartEvidence: .init(profileID: "fixture-start", signal: .attachmentAccepted,
                evidenceID: "fixture", inputCount: 1))
    }
    func captureTarget() throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { target.documentID == self.target.documentID && target.draftGeneration == self.target.draftGeneration }
    func append(_ request: TransferRequest) -> TransferReceipt {
        if let original = request.recoverySource { appendedSources.append(original) }
        attempts.append(request.operation.attempt)
        return start(request.operation, request.asset)
    }
    func append(_ request: TransferRequest, onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) -> TransferReceipt {
        append(request)
    }
    func reconcile(_ request: TransferRequest) throws -> TransferReceipt {
        guard request.requireLiveOriginal, let invocation = request.invocationID else { throw RiftletError.invalidTransition }
        observedInvocations.append(invocation)
        let op = request.operation
        return TransferReceipt(operationID: op.id, assetID: op.assetID, attempt: op.attempt, assetSHA256: request.asset.sha256,
            target: op.target, outcome: .unknown, profileID: "fixture", attachmentID: op.id.uuidString,
            belongsToOriginalDraft: true, hasError: true)
    }
}
