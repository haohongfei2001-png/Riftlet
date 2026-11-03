import Foundation
import XCTest
@testable import RiftletCore

/// SQLite/coordinator regressions with explicitly synthetic browser ownership evidence.
/// These tests never establish or enable a ChatGPT platform capability.
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

    func testTwoThreeAndFiveScreenshotsContinueAcrossEveryIndependentPriorState() async throws {
        for count in [2, 3, 5] {
            for state in IndependentLifecycleAdapter.State.allCases {
                let store = try store(), adapter = IndependentLifecycleAdapter(), coordinator = coordinator(store, adapter)
                let first = try await asset(store)
                try await coordinator.select(try await selection(first, store))
                let original = try await operation(first, store)
                let originalStart = try await store.uploadStartReceipt(for: original.id)
                let swallowed = try await store.asset(id: first.id)
                XCTAssertEqual(swallowed?.visibility, .swallowed, "START must swallow before any completion")
                XCTAssertNotNil(originalStart?.continuationEvidence)
                if state == .compensated {
                    await adapter.set(.complete, for: first.id)
                    try await coordinator.observePending()
                    await adapter.set(.compensated, for: first.id)
                    _ = try await coordinator.observeCompleted(operationID: original.id)
                } else if state != .started {
                    await adapter.set(state, for: first.id)
                    try await coordinator.observePending()
                }
                let priorState = try await operation(first, store)
                let expected: OperationPhase = state == .complete ? .succeeded
                    : state == .failed ? .failed : state == .compensated ? .compensated
                    : state == .unknown ? .unknown : .inputTriggered
                XCTAssertEqual(priorState.phase, expected, "\(count)/\(state)")
                let beforeNext = try await store.asset(id: first.id)
                XCTAssertEqual(beforeNext?.visibility, state == .failed ? .visible : .swallowed)

                var images = [first]
                for _ in 1..<count {
                    let next = try await asset(store); images.append(next)
                    try await coordinator.select(try await selection(next, store))
                    let op = try await operation(next, store), record = try await store.asset(id: next.id)
                    XCTAssertEqual(op.phase, .inputTriggered, "\(count)/\(state)")
                    XCTAssertEqual(record?.visibility, .swallowed)
                }
                let inputs = await adapter.inputs(), afterFirst = try await operation(first, store)
                XCTAssertEqual(inputs, images.map(\.id)); XCTAssertEqual(afterFirst, priorState)
                let preservedStart = try await store.uploadStartReceipt(for: original.id)
                XCTAssertEqual(preservedStart, originalStart)
                if state == .failed {
                    // Rebirth does not input anything until another explicit user click.
                    let beforeReclick = await adapter.inputs(); XCTAssertEqual(beforeReclick.count, count)
                    try await coordinator.select(try await selection(first, store))
                    let retry = try await operation(first, store), afterReclick = await adapter.inputs()
                    XCTAssertEqual(retry.attempt, 2); XCTAssertNotEqual(retry.id, original.id)
                    XCTAssertEqual(afterReclick, images.map(\.id) + [first.id])
                }
            }
        }
    }

    func testFourClicksAfterUnprovenStartFailBeforeIntentWithoutDeadlineOrCrossChatStarvation() async throws {
        let store = try store(), adapter = IndependentLifecycleAdapter(continuation: false)
        let coordinator = coordinator(store, adapter), first = try await asset(store)
        try await coordinator.select(try await selection(first, store))
        await adapter.set(.unknown, for: first.id); try await coordinator.observePending()
        let original = try await operation(first, store), originalRecord = try await store.asset(id: first.id)
        var rejected: [UUID] = []
        for _ in 0..<4 {
            let image = try await asset(store), click = try await selection(image, store)
            try await coordinator.select(click)
            let op = try await operation(image, store), record = try await store.asset(id: image.id)
            let invocation = try await store.dispatchInvocationID(for: op.id)
            let reason = try await store.operationReason(for: op.id)
            XCTAssertEqual(op.phase, .failed); XCTAssertEqual(record?.visibility, .visible); XCTAssertNil(invocation)
            XCTAssertEqual(reason, "Independent attachment input is unproven for this draft; no input occurred")
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime, click.deadlineUptime,
                              "Refusal must not depend on original 30-second selection expiry")
            XCTAssertFalse(click.isValid()); rejected.append(image.id)
        }
        let nextChat = try await asset(store)
        try await coordinator.select(try await selection(nextChat, store,
            target: target(draft: 2, document: "other-document", tab: "2")))
        let inputs = await adapter.inputs(), unchanged = try await operation(first, store)
        let retained = try await store.asset(id: first.id)
        XCTAssertEqual(inputs, [first.id, nextChat.id]); XCTAssertEqual(unchanged, original)
        XCTAssertEqual(retained, originalRecord); XCTAssertEqual(original.phase, .unknown)
        XCTAssertEqual(retained?.visibility, .swallowed)
        for id in rejected { XCTAssertFalse(inputs.contains(id)) }
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
            let storedCall = try await store.checkpoint(for: "transfer-dispatch-call-v1:" + ao.id.uuidString)
            let call = try JSONDecoder().decode(DispatchCallRecord.self, from: XCTUnwrap(storedCall))
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
            let invocation = try await store.markDispatchIntent(bo.id,
                selection: try await selection(b, store, target: bt), ownerID: owner, policy: policy)
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

    func testNewDocumentOrOwnerCannotReuseOldContinuationAndNeverReinputsOldUnknown() async throws {
        for restart in [false, true] {
            let store = try store(), adapter = IndependentLifecycleAdapter(), firstOwner = coordinator(store, adapter)
            let a = try await asset(store), b = try await asset(store)
            try await firstOwner.select(try await selection(a, store))
            await adapter.set(.unknown, for: a.id); try await firstOwner.observePending()
            let before = try await operation(a, store), beforeRecord = try await store.asset(id: a.id)
            let next = restart ? coordinator(store, adapter) : firstOwner
            let nextTarget = restart ? target() : target(document: "refreshed-document")
            try await next.select(try await selection(b, store, target: nextTarget))
            let bOp = try await operation(b, store), invocation = try await store.dispatchInvocationID(for: bOp.id)
            let after = try await operation(a, store), afterRecord = try await store.asset(id: a.id)
            let inputs = await adapter.inputs()
            XCTAssertEqual(bOp.phase, .failed); XCTAssertNil(invocation); XCTAssertEqual(inputs, [a.id])
            XCTAssertEqual(after, before); XCTAssertEqual(afterRecord, beforeRecord)
        }
    }
}

private actor IndependentLifecycleAdapter: AttachmentAdapter {
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
