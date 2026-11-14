import Foundation
import XCTest
@testable import RiftletCore

/// Backward-compatible receipt/history tests. The synthetic historical proof
/// payloads do not authorize or veto the new independent file-input path.
final class IndependentAttachmentLifecycleTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("independent-attachments-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private var policy: ReceiptPolicy {
        .init(syntheticAcceptanceProfiles: [IndependentLifecycleAdapter.readyProfile: .webChat],
              syntheticUploadStartProfiles: [IndependentLifecycleAdapter.startProfile: .webChat],
              syntheticRetrySafeProfiles: [IndependentLifecycleAdapter.readyProfile: .webChat],
              syntheticContinuationProfiles: [IndependentLifecycleAdapter.continuationProfile: .webChat],
              requiredCompletionEvidenceProfiles: [IndependentLifecycleAdapter.readyProfile],
              requiredTerminationEvidenceProfiles: [IndependentLifecycleAdapter.readyProfile],
              terminationProfiles: [IndependentLifecycleAdapter.terminationProfile: .webChat],
              requiredInputIsolationProfiles: [IndependentLifecycleAdapter.continuationProfile])
    }
    private func store() throws -> QueueStore {
        try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
    }
    private func asset(_ store: QueueStore) async throws -> ImportedAsset {
        let id = UUID(), bytes = Data("isolated lifecycle fixture".utf8)
        let asset = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count),
            pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: directory.appendingPathComponent(asset.fileName))
        _ = try await store.importAsset(asset); return asset
    }
    private func target(draft: Int = 1, document: String = "original-document", tab: String = "1") -> TargetLease {
        .init(adapterID: "independent-lifecycle-fixture", surface: .webChat, applicationID: "com.google.Chrome",
              sessionID: "fixture-session", windowID: "1", tabID: tab, documentID: document,
              composerID: "composer-\(document)", draftGeneration: "generation-\(document)",
              logicalDraftIdentity: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                  id: "00000000-0000-0000-0000-" + String(format: "%012d", draft)), clickBindingID: UUID())
    }
    private func selection(_ asset: ImportedAsset, _ store: QueueStore,
                           target: TargetLease? = nil) async throws -> AcceptedSelection {
        let record = try await store.asset(id: asset.id), now = ProcessInfo.processInfo.systemUptime
        return .init(assetID: asset.id, target: target ?? self.target(), hostEpoch: UUID(),
              acknowledgedUptime: now - 0.005, eventUptime: now - 0.01, acceptedUptime: now,
              visibilityRevision: try XCTUnwrap(record?.visibilityRevision), deadlineUptime: now + 30,
              authorization: .nativeClickPin)
    }
    private func coordinator(_ store: QueueStore, _ adapter: IndependentLifecycleAdapter) -> TransferCoordinator {
        TransferCoordinator(store: store, adapter: adapter, mediaDirectory: directory, policy: policy,
                            validateAcceptedSelection: { $0.isValid() })
    }
    private func operation(_ asset: ImportedAsset, _ store: QueueStore) async throws -> TransferOperation {
        let record = try await store.asset(id: asset.id)
        let id = try XCTUnwrap(record?.activeOperationID)
        let op = try await store.operation(id: id); return try XCTUnwrap(op)
    }

    private func returnedDispatchCall(_ operationID: UUID, _ store: QueueStore) async throws -> DispatchCallRecord {
        // select() releases the input boundary before the original append task
        // records its return. Await that durable fact, not a scheduler ordering.
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var observed: DispatchCallRecord?
        repeat {
            if let data = try await store.checkpoint(for: "transfer-dispatch-call-v1:" + operationID.uuidString) {
                observed = try JSONDecoder().decode(DispatchCallRecord.self, from: data)
                if observed?.returnedReceipt != nil { return try XCTUnwrap(observed) }
            }
            await Task.yield()
        } while ProcessInfo.processInfo.systemUptime < deadline
        XCTFail("Original append did not durably record its returned receipt within five seconds")
        return try XCTUnwrap(observed)
    }

    func testRelaunchReleasesOnlyUndispatchedPreparationAndNewClickUsesItsOwnTarget() async throws {
        let path = directory.appendingPathComponent("restart.sqlite")
        let first = try QueueStore(databaseURL: path)
        let a = try await asset(first), missing = try await asset(first), dispatched = try await asset(first)
        let prepared = try await first.prepare(assetID: a.id, target: target())
        let preparedMissing = try await first.prepare(assetID: missing.id, target: target())
        try await first.markMissingAsset(missing.id)
        let sent = try await first.prepare(assetID: dispatched.id, target: target())
        let invocation = try await first.markIndependentFileInputIntent(sent.id, ownerID: UUID())
        let originalDispatch = try await first.operation(id: sent.id)
        let ambiguous = try await asset(first)
        let ambiguousOp = try await first.prepare(assetID: ambiguous.id, target: target())
        let witnessKey = "transfer-dispatch-call-v1:" + ambiguousOp.id.uuidString
        try await first.saveCheckpoint(Data([1]), for: witnessKey)

        let reopened = try QueueStore(databaseURL: path), adapter = IndependentLifecycleAdapter()
        let owner = coordinator(reopened, adapter)
        try await owner.recover()
        let recovered = try await reopened.operation(id: prepared.id)
        let missingPhase = try await reopened.operation(id: preparedMissing.id)?.phase
        let missingState = try await reopened.asset(id: missing.id)?.status
        let dispatchAfter = try await reopened.operation(id: sent.id)
        let callAfter = try await reopened.dispatchInvocationID(for: sent.id)
        let ambiguousAfter = try await reopened.operation(id: ambiguousOp.id)
        let witness = try await reopened.checkpoint(for: witnessKey)
        let beforeClick = await adapter.inputs()
        XCTAssertEqual(recovered?.phase, .failed)
        XCTAssertEqual(missingPhase, .failed)
        XCTAssertEqual(missingState, .missing)
        XCTAssertEqual(dispatchAfter, originalDispatch)
        XCTAssertEqual(callAfter, invocation)
        XCTAssertEqual(ambiguousAfter, ambiguousOp)
        XCTAssertEqual(witness, Data([1]))
        XCTAssertTrue(beforeClick.isEmpty)

        try await owner.recover()
        let secondRecovery = try await reopened.operation(id: prepared.id)
        XCTAssertEqual(secondRecovery, recovered)
        let newTarget = target(draft: 2, document: "new-document")
        try await owner.select(try await selection(a, reopened, target: newTarget))
        let newOp = try await operation(a, reopened)
        _ = try await returnedDispatchCall(newOp.id, reopened)
        let afterClick = await adapter.inputs()
        XCTAssertEqual(afterClick, [a.id])
        XCTAssertNotEqual(newOp.id, prepared.id)
        XCTAssertEqual(newOp.attempt, 2)
        XCTAssertEqual(newOp.target, newTarget)
    }

    func testRestartLeavesOriginalStartedUnknownAndCompensatedRowsByteIdentical() async throws {
        let path = directory.appendingPathComponent("history.sqlite")
        let oldStore = try QueueStore(databaseURL: path), oldAdapter = IndependentLifecycleAdapter()
        let oldOwner = coordinator(oldStore, oldAdapter)
        let database = try SQLiteDatabase(url: path)
        for state in ["started", "unknown", "compensated"] {
            let a = try await asset(oldStore)
            try await oldOwner.select(try await selection(a, oldStore))
            let op = try await operation(a, oldStore)
            _ = try await returnedDispatchCall(op.id, oldStore)
            if state == "unknown" {
                try await oldStore.markUnknown(op.id, reason: "Original unresolved input")
            } else if state == "compensated" {
                let requests = await oldAdapter.requests(for: a.id)
                let request = try XCTUnwrap(requests.last)
                _ = try await oldStore.apply(IndependentLifecycleAdapter.receipt(request, state: .complete), policy: policy)
                _ = try await oldStore.apply(IndependentLifecycleAdapter.receipt(request, state: .compensated), policy: policy)
            }
        }
        func rows() throws -> [[String?]] {
            try ["assets", "operations", "checkpoints", "upload_starts", "compensations"].flatMap {
                try database.rows("SELECT * FROM " + $0 + " ORDER BY rowid")
            }
        }
        let before = try rows()
        XCTAssertEqual(try database.rows("SELECT phase FROM operations ORDER BY sequence").compactMap { $0[0] },
                       ["inputTriggered", "unknown", "compensated"])
        XCTAssertEqual(try database.rows("SELECT operation_id FROM upload_starts").count, 3)
        let reopened = try QueueStore(databaseURL: path), adapter = IndependentLifecycleAdapter()
        try await coordinator(reopened, adapter).recover()
        XCTAssertEqual(try rows(), before)
        let inputs = await adapter.inputs()
        XCTAssertTrue(inputs.isEmpty)
    }

    func testLateReceiptsCannotBorrowSiblingPinAttachmentOrInvocation() async throws {
        let store = try store(), adapter = IndependentLifecycleAdapter(), coordinator = coordinator(store, adapter)
        let a = try await asset(store), b = try await asset(store)
        try await coordinator.select(try await selection(a, store))
        try await coordinator.select(try await selection(b, store))
        let aRequests = await adapter.requests(for: a.id), bRequests = await adapter.requests(for: b.id)
        let ar = try XCTUnwrap(aRequests.last), br = try XCTUnwrap(bRequests.last)
        let beforeA = try await operation(a, store), beforeB = try await operation(b, store)
        let originalBStart = try await store.uploadStartReceipt(for: beforeB.id)
        for wrong in ["pin", "invocation", "attachment"] {
            let good = IndependentLifecycleAdapter.receipt(ar, state: .complete)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(good)) as? [String: Any])
            var proof = json["completionEvidence"] as! [String: Any]
            var binding = proof["binding"] as! [String: Any]
            if wrong == "pin" {
                let target = try JSONSerialization.jsonObject(with: JSONEncoder().encode(br.operation.target))
                json["target"] = target; binding["target"] = target
            } else if wrong == "invocation" { binding["invocationID"] = br.invocationID!.uuidString }
            else {
                let sibling = "attachment-\(br.operation.id)"
                json["attachmentID"] = sibling; binding["attachmentID"] = sibling
            }
            proof["binding"] = binding; json["completionEvidence"] = proof
            let bad = try JSONDecoder().decode(TransferReceipt.self, from: JSONSerialization.data(withJSONObject: json))
            do { _ = try await store.apply(bad, policy: policy); XCTFail("Borrowed \(wrong) accepted") }
            catch RiftletError.mismatchedReceipt {}
        }
        _ = try await store.apply(IndependentLifecycleAdapter.receipt(br, state: .complete), policy: policy)
        let onlyB = try await operation(b, store), stillA = try await operation(a, store)
        XCTAssertEqual(onlyB.phase, .succeeded); XCTAssertEqual(stillA, beforeA)
        _ = try await store.apply(IndependentLifecycleAdapter.receipt(ar, state: .unknown), policy: policy)
        _ = try await store.apply(IndependentLifecycleAdapter.receipt(ar, state: .complete), policy: policy)
        _ = try await store.apply(IndependentLifecycleAdapter.receipt(ar, state: .compensated), policy: policy)
        let afterA = try await operation(a, store), afterB = try await operation(b, store)
        let preservedBStart = try await store.uploadStartReceipt(for: beforeB.id)
        XCTAssertEqual(afterA.phase, .compensated); XCTAssertEqual(afterB, onlyB)
        XCTAssertEqual(preservedBStart, originalBStart)
        let c = try await asset(store); try await coordinator.select(try await selection(c, store))
        let inputs = await adapter.inputs(); XCTAssertEqual(inputs, [a.id, b.id, c.id])
    }

    func testBrowserOwnershipPersistsAndRejectsRequestOrOwnershipAliasAcrossPins() async throws {
        for field in ["requestID", "ownershipID"] {
            let url = directory.appendingPathComponent("\(UUID()).sqlite")
            let store = try QueueStore(databaseURL: url), adapter = IndependentLifecycleAdapter()
            let coordinator = coordinator(store, adapter), a = try await asset(store), b = try await asset(store)
            try await coordinator.select(try await selection(a, store))
            let ao = try await operation(a, store)
            let call = try await returnedDispatchCall(ao.id, store)
            let owner = try XCTUnwrap(call.ownerID)
            let originalStart = try XCTUnwrap(call.returnedReceipt)
            XCTAssertEqual(originalStart.continuationEvidence?.version, 3)
            XCTAssertNil(originalStart.continuationEvidence?.taskIsolation, "Browser proof cannot pretend to be a platform task")
            let aKey = "transfer-input-isolation-v1:" + ao.id.uuidString
            let savedOwnership = try await store.checkpoint(for: aKey)
            XCTAssertNotNil(savedOwnership)
            let reopened = try QueueStore(databaseURL: url)
            let persistedOwnership = try await reopened.checkpoint(for: aKey)
            XCTAssertEqual(persistedOwnership, savedOwnership)

            let bt = target(), bo = try await store.prepare(assetID: b.id, target: bt)
            let invocation = try await store.markIndependentFileInputIntent(bo.id,
                selection: try await selection(b, store, target: bt), ownerID: owner)
            let request = TransferRequest(operation: bo, asset: b,
                fileURL: directory.appendingPathComponent(b.fileName), invocationID: invocation)
            let good = IndependentLifecycleAdapter.receipt(request, state: .started, requestID: 2)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(good)) as? [String: Any])
            var proof = json["continuationEvidence"] as! [String: Any]
            var isolation = proof["inputIsolation"] as! [String: Any]
            if field == "requestID" { isolation[field] = 1 }
            else { isolation[field] = "ownership-\(ao.id)" }
            proof["inputIsolation"] = isolation; json["continuationEvidence"] = proof
            let alias = try JSONDecoder().decode(TransferReceipt.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertTrue(policy.allowsContinuation(receipt: alias, asset: b, mode: .production),
                          "Shape is valid; cross-operation ownership must reject the alias")
            do { _ = try await store.apply(alias, policy: policy); XCTFail("Borrowed \(field) accepted") }
            catch RiftletError.mismatchedReceipt {}
            let bStart = try await store.uploadStartReceipt(for: bo.id)
            let bCheckpoint = try await store.checkpoint(for: "transfer-input-isolation-v1:" + bo.id.uuidString)
            let unchanged = try await store.checkpoint(for: aKey)
            XCTAssertNil(bStart); XCTAssertNil(bCheckpoint); XCTAssertEqual(unchanged, savedOwnership)
            _ = try await store.apply(good, policy: policy)
            try await store.recordAppendReturned(good, invocationID: invocation, ownerID: owner)
            let independent = try await store.uploadStartReceipt(for: bo.id)
            XCTAssertEqual(independent, good)
        }
    }

    func testLaterPolicyOrProofCannotPromoteAnOldStartIntoBrowserInputOwnership() async throws {
        for originalHasProof in [false, true] {
            let store = try store(), a = try await asset(store), b = try await asset(store), owner = UUID()
            let at = target(), ao = try await store.prepare(assetID: a.id, target: at)
            let invocation = try await store.markDispatchIntent(ao.id,
                selection: try await selection(a, store, target: at), ownerID: owner, policy: policy)
            let request = TransferRequest(operation: ao, asset: a,
                fileURL: directory.appendingPathComponent(a.fileName), invocationID: invocation)
            let original = IndependentLifecycleAdapter.receipt(request, state: .started, continuation: originalHasProof)
            let startOnly = ReceiptPolicy(syntheticUploadStartProfiles: [IndependentLifecycleAdapter.startProfile: .webChat])
            _ = try await store.apply(original, policy: startOnly)
            try await store.recordAppendReturned(original, invocationID: invocation, ownerID: owner)
            try await store.markUnknown(ao.id, reason: "Original observation lost without admitted input ownership")
            let later = IndependentLifecycleAdapter.receipt(request, state: .started)
            _ = try await store.apply(later, policy: policy)
            let key = "transfer-input-isolation-v1:" + ao.id.uuidString
            let checkpoint = try await store.checkpoint(for: key), preservedStart = try await store.uploadStartReceipt(for: ao.id)
            XCTAssertNil(checkpoint); XCTAssertEqual(preservedStart, original)
            let bt = target(), bo = try await store.prepare(assetID: b.id, target: bt)
            do {
                _ = try await store.markDispatchIntent(bo.id,
                    selection: try await selection(b, store, target: bt), ownerID: owner, policy: policy)
                XCTFail("Later policy/proof upgraded an old START")
            } catch RiftletError.targetBusy {}
            let bInvocation = try await store.dispatchInvocationID(for: bo.id)
            XCTAssertNil(bInvocation)
        }
    }

    func testNewDocumentAndOwnerIgnoreOldContinuationWithoutReinputtingOldUnknown() async throws {
        for restart in [false, true] {
            let store = try store(), adapter = IndependentLifecycleAdapter(), firstOwner = coordinator(store, adapter)
            let a = try await asset(store), b = try await asset(store)
            try await firstOwner.select(try await selection(a, store))
            let ao = try await operation(a, store)
            _ = try await returnedDispatchCall(ao.id, store)
            try await store.markUnknown(ao.id, reason: "Controlled historical UNKNOWN")
            let before = try await operation(a, store), beforeRecord = try await store.asset(id: a.id)
            let next = restart ? coordinator(store, adapter) : firstOwner
            let nextTarget = restart ? target() : target(document: "refreshed-document")
            try await next.select(try await selection(b, store, target: nextTarget))
            let dispatched = try await operation(b, store)
            _ = try await returnedDispatchCall(dispatched.id, store)
            let bOp = try await operation(b, store), invocation = try await store.dispatchInvocationID(for: dispatched.id)
            XCTAssertEqual(bOp.id, dispatched.id)
            let after = try await operation(a, store), afterRecord = try await store.asset(id: a.id)
            let inputs = await adapter.inputs()
            XCTAssertEqual(bOp.phase, .inputTriggered); XCTAssertNotNil(invocation); XCTAssertEqual(inputs, [a.id, b.id])
            XCTAssertEqual(after, before); XCTAssertEqual(afterRecord, beforeRecord)
        }
    }
}

private actor IndependentLifecycleAdapter: IndependentFileInputAdapter {
    enum State: CaseIterable { case started, unknown, complete, failed, compensated }
    nonisolated let id = "independent-lifecycle-fixture"
    static let readyProfile = "independent-fixture-ready"
    static let startProfile = "independent-fixture-start"
    static let continuationProfile = "independent-fixture-continuation"
    static let terminationProfile = "independent-fixture-retirement"
    private let continuation: Bool
    private var calls: [TransferRequest] = []
    private var states: [UUID: State] = [:]
    init(continuation: Bool = true) { self.continuation = continuation }
    func captureTarget() throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { target.adapterID == id }
    func set(_ state: State, for asset: UUID) { states[asset] = state }
    func inputs() -> [UUID] { calls.map { $0.asset.id } }
    func requests(for asset: UUID) -> [TransferRequest] { calls.filter { $0.asset.id == asset } }
    func append(_ request: TransferRequest) -> TransferReceipt {
        calls.append(request)
        // A user-initiated retry creates its own new operation and task.
        states[request.asset.id] = .started
        return Self.receipt(request, state: .started, continuation: continuation, requestID: calls.count)
    }
    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) -> TransferReceipt {
        append(request)
    }
    func reconcile(_ request: TransferRequest) -> TransferReceipt {
        Self.receipt(request, state: states[request.asset.id] ?? .unknown, continuation: continuation,
                     requestID: (calls.firstIndex { $0.operation.id == request.operation.id } ?? 0) + 1)
    }
    nonisolated static func receipt(_ request: TransferRequest, state: State, continuation: Bool = true, requestID: Int = 1) -> TransferReceipt {
        let op = request.operation, asset = request.asset
        let invocation = request.invocationID!
        let attachment = "attachment-\(op.id)", startID = "start-\(op.id)"
        let bound = AttachmentOperationBinding(operationID: op.id, assetID: asset.id, attempt: op.attempt,
            assetSHA256: asset.sha256, target: op.target, invocationID: invocation, attachmentID: attachment)
        let task = PlatformAttachmentTaskIdentity(requestID: "request-\(op.id)", taskID: "task-\(op.id)",
            attachmentReference: "platform-attachment-\(op.id)", originalSHA256: asset.sha256, originalByteCount: asset.byteCount)
        let start = state == .started, ready = state == .complete
        let failed = state == .failed || state == .compensated
        return .init(operationID: op.id, assetID: asset.id, attempt: op.attempt, assetSHA256: asset.sha256,
            target: op.target, outcome: start ? .uploadStarted : ready ? .verifiedReady : failed ? .definitiveFailure : .unknown,
            profileID: readyProfile, attachmentID: attachment, positiveReady: ready,
            belongsToOriginalDraft: true, hasError: failed, isUploading: start, safeToRetry: state == .failed,
            uploadStartEvidence: start ? .init(profileID: startProfile, signal: .correlatedProgress, evidenceID: startID) : nil,
            continuationEvidence: start && continuation ? .init(version: 3, profileID: continuationProfile,
                evidenceID: "continuation-\(op.id)", invocationID: invocation, binding: bound,
                inputIsolation: .init(ownershipID: "ownership-\(op.id)", inputElementID: "shared-composer-input",
                    requestID: requestID, requestSequence: 2, requestTransport: .xhr,
                    originalSHA256: asset.sha256, originalByteCount: asset.byteCount, startEvidenceID: startID,
                    inputSequence: 1, callSettledSequence: 3, startSequence: 4, observedSequence: 5)) : nil,
            completionEvidence: ready ? .init(evidenceID: "complete-\(op.id)", binding: bound,
                kind: .exactOriginalBytes, originalByteCount: asset.byteCount, originalSHA256: asset.sha256,
                observedByteCount: asset.byteCount, observedSHA256: asset.sha256) : nil,
            terminationEvidence: state == .failed ? .init(profileID: terminationProfile,
                evidenceID: "retired-\(op.id)", binding: bound, task: task, retirementID: "retirement-\(op.id)") : nil)
    }
}
