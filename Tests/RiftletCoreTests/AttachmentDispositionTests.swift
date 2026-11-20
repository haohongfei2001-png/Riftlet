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
        let selection = AcceptedSelection(assetID: asset.id, target: adapter.target, visibilityRevision: staged.visibilityRevision)
        try await core.reattach(selection, replacing: first.id)
        for _ in 0..<100 where await core.hasInFlightAttachmentWork { try await Task.sleep(nanoseconds: 2_000_000) }
        let attempts = await adapter.attempts
        XCTAssertEqual(attempts, [2])
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
        let wrong = AcceptedSelection(assetID: asset.id, target: adapter.target, visibilityRevision: staged.visibilityRevision - 1)
        do {
            try await core.reattach(wrong, replacing: old.id)
            XCTFail("A stale click initiated a replacement")
        } catch RiftletError.invalidTransition {}
        let unchanged = try await reopened.operation(id: old.id)
        XCTAssertEqual(unchanged?.phase, .dispatchIntent)
        let click = AcceptedSelection(assetID: asset.id, target: adapter.target, visibilityRevision: staged.visibilityRevision)
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

}

private actor DispositionAdapter: IndependentFileInputAdapter {
    nonisolated let id = "test-adapter"
    nonisolated let supportsOriginalHandoffChecks = true
    nonisolated let target = TargetLease(adapterID: "test-adapter", surface: .webChat, applicationID: "com.google.Chrome",
        sessionID: "fixture", windowID: "1", tabID: "1", documentID: "doc", composerID: "composer", draftGeneration: "1", clickBindingID: UUID())
    var attempts = [Int]()
    var observedInvocations = [UUID]()
    nonisolated func start(_ op: TransferOperation, _ asset: ImportedAsset) -> TransferReceipt {
        TransferReceipt(operationID: op.id, assetID: asset.id, attempt: op.attempt, assetSHA256: asset.sha256,
            target: op.target, outcome: .uploadStarted, profileID: "fixture", attachmentID: op.id.uuidString,
            belongsToOriginalDraft: true, uploadStartEvidence: .init(profileID: "fixture-start", signal: .attachmentAccepted,
                evidenceID: "fixture", inputCount: 1))
    }
    func captureTarget() throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { target == self.target }
    func append(_ request: TransferRequest) -> TransferReceipt {
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
