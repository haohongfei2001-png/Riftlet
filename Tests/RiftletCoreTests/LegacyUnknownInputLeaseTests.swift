import Foundation
import XCTest
@testable import RiftletCore

/// Anonymized incident-shape fixtures, not a replay of private production data.
/// The legacy START has no dispatch-call or request-ownership checkpoint. All
/// images, targets, receipts and subsequent adapter behavior are synthetic.
final class LegacyUnknownInputLeaseTests: XCTestCase {
    private var directory: URL!
    private let readyProfile = "legacy-input-fixture-ready"
    private let startProfile = "legacy-input-fixture-start"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-unknown-input-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private var policy: ReceiptPolicy {
        .init(syntheticAcceptanceProfiles: [readyProfile: .webChat],
              syntheticUploadStartProfiles: [startProfile: .webChat],
              syntheticRetrySafeProfiles: [readyProfile: .webChat])
    }

    private func target(document: String = "incident-document", draft: Int = 1,
                        pin: UUID? = nil) -> TargetLease {
        .init(adapterID: "legacy-input-fixture", surface: .webChat,
              applicationID: "com.google.Chrome", sessionID: "fixture-browser-session",
              windowID: "fixture-window", tabID: "fixture-tab", documentID: document,
              composerID: "composer-\(document)", draftGeneration: "generation-\(document)",
              logicalDraftIdentity: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                  id: "00000000-0000-0000-0000-" + String(format: "%012d", draft)),
              clickBindingID: pin)
    }

    private func image(_ store: QueueStore) async throws -> ImportedAsset {
        let id = UUID(), bytes = Data("synthetic incident fixture".utf8)
        let asset = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count),
            pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: directory.appendingPathComponent(asset.fileName))
        _ = try await store.importAsset(asset)
        return asset
    }

    private func receipt(_ operation: TransferOperation, image: ImportedAsset,
                         outcome: ReceiptOutcome, attachmentID: String) -> TransferReceipt {
        .init(operationID: operation.id, assetID: image.id, attempt: operation.attempt,
              assetSHA256: image.sha256, target: operation.target, outcome: outcome,
              profileID: readyProfile, attachmentID: attachmentID,
              positiveReady: outcome == .verifiedReady, belongsToOriginalDraft: true,
              hasError: outcome == .definitiveFailure, isUploading: outcome == .uploadStarted,
              safeToRetry: outcome == .definitiveFailure,
              reason: "Synthetic incident observation",
              uploadStartEvidence: outcome == .uploadStarted
                  ? .init(profileID: startProfile, signal: .correlatedProgress,
                          evidenceID: "start-\(operation.id)") : nil)
    }

    private struct Incident {
        let store: QueueStore
        let sql: SQLiteDatabase
        let databaseURL: URL
        let image: ImportedAsset
        let operation: TransferOperation
        let attachmentID: String
    }

    private func incident(state: ReceiptOutcome = .unknown, legacyCall: Bool = false) async throws -> Incident {
        let url = directory.appendingPathComponent("\(UUID()).sqlite")
        let store = try QueueStore(databaseURL: url), asset = try await image(store)
        let operation = try await store.prepare(assetID: asset.id, target: target())
        let sql = try SQLiteDatabase(url: url)
        // A frozen old invocation had no newer dispatch-call checkpoint. Seed
        // that state directly rather than creating and upgrading a modern call.
        try sql.execute("UPDATE operations SET phase='dispatchIntent' WHERE id=?", [operation.id.uuidString])
        let attachment = "legacy-attachment-\(operation.id)"
        let firstStart = receipt(operation, image: asset, outcome: .uploadStarted, attachmentID: attachment)
        _ = try await store.apply(firstStart, policy: policy)
        var historicalInvocation: UUID?
        if legacyCall {
            historicalInvocation = UUID()
            // Frozen old shape: neither new lease key is produced by a current
            // encoder, initialized, backfilled, or inferred from the old START.
            let oldCall: [String: Any] = ["version": 1, "operationID": operation.id.uuidString,
                "assetID": asset.id.uuidString, "attempt": operation.attempt, "assetSHA256": asset.sha256,
                "target": try JSONSerialization.jsonObject(with: JSONEncoder().encode(operation.target)),
                "invocationID": historicalInvocation!.uuidString, "ownerID": UUID().uuidString,
                "returnedReceipt": try JSONSerialization.jsonObject(with: JSONEncoder().encode(firstStart))]
            try await store.saveCheckpoint(JSONSerialization.data(withJSONObject: oldCall, options: [.sortedKeys]),
                for: "transfer-dispatch-call-v1:" + operation.id.uuidString)
        }
        if state != .uploadStarted {
            _ = try await store.apply(receipt(operation, image: asset, outcome: state,
                                              attachmentID: attachment), policy: policy)
        }
        let current = try await store.operation(id: operation.id)
        let record = try await store.asset(id: asset.id)
        let start = try await store.uploadStartReceipt(for: operation.id)
        let invocation = try await store.dispatchInvocationID(for: operation.id)
        XCTAssertEqual(current?.phase, state == .uploadStarted ? .inputTriggered
                       : state == .verifiedReady ? .succeeded
                       : state == .definitiveFailure ? .failed : .unknown)
        XCTAssertEqual(record?.visibility, state == .definitiveFailure ? .visible : .swallowed)
        XCTAssertEqual(invocation, historicalInvocation)
        XCTAssertNil(start?.continuationEvidence)
        let keys = try sql.rows("SELECT key FROM checkpoints WHERE key LIKE ?", ["%" + operation.id.uuidString])
        XCTAssertEqual(keys.count, legacyCall ? 1 : 0)
        return Incident(store: store, sql: sql, databaseURL: url, image: asset,
                        operation: try XCTUnwrap(current), attachmentID: attachment)
    }

    private struct History: Equatable {
        let operation: [[String?]]
        let asset: [[String?]]
        let start: [[String?]]
        let checkpoints: [[String?]]
    }

    private func history(_ incident: Incident) throws -> History {
        let id = incident.operation.id.uuidString
        return History(
            operation: try incident.sql.rows("SELECT * FROM operations WHERE id=?", [id]),
            asset: try incident.sql.rows("SELECT * FROM assets WHERE id=?", [incident.image.id.uuidString]),
            start: try incident.sql.rows("SELECT * FROM upload_starts WHERE operation_id=?", [id]),
            checkpoints: try incident.sql.rows("SELECT key,value FROM checkpoints WHERE key LIKE ? ORDER BY key", ["%" + id]))
    }

    private func selection(_ image: ImportedAsset, _ store: QueueStore,
                           target: TargetLease? = nil) async throws -> AcceptedSelection {
        let record = try await store.asset(id: image.id), now = ProcessInfo.processInfo.systemUptime
        return .init(assetID: image.id, target: target ?? self.target(pin: UUID()), hostEpoch: UUID(),
                     acknowledgedUptime: now - 0.005, eventUptime: now - 0.01, acceptedUptime: now,
                     visibilityRevision: try XCTUnwrap(record?.visibilityRevision), deadlineUptime: now + 30,
                     authorization: .nativeClickPin)
    }

    private func operation(_ image: ImportedAsset, _ store: QueueStore) async throws -> TransferOperation {
        let record = try await store.asset(id: image.id)
        let id = try XCTUnwrap(record?.activeOperationID)
        let value = try await store.operation(id: id)
        return try XCTUnwrap(value)
    }

    private func waitForStart(_ image: ImportedAsset, _ store: QueueStore) async throws -> TransferOperation {
        for _ in 0..<500 {
            let op = try await operation(image, store)
            let start = try await store.uploadStartReceipt(for: op.id)
            let raw = try await store.checkpoint(for: "transfer-dispatch-call-v1:" + op.id.uuidString)
            let returned = try raw.map { try JSONDecoder().decode(DispatchCallRecord.self, from: $0) }
            if start != nil, returned?.returnedReceipt != nil { return op }
            if op.phase == .failed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The selected screenshot never independently reached START")
        return try await operation(image, store)
    }

    private func coordinator(_ store: QueueStore, _ adapter: LegacyResourceFixtureAdapter) -> TransferCoordinator {
        .init(store: store, adapter: adapter, mediaDirectory: directory, policy: policy,
              validateAcceptedSelection: { $0.isValid() })
    }

    private func resource(_ operation: TransferOperation, _ image: ImportedAsset,
                          invocationID: UUID = UUID(), resourceID: UUID = UUID()) -> PreparedInputResource {
        .init(operationID: operation.id, assetID: image.id, attempt: operation.attempt,
              assetSHA256: image.sha256, target: operation.target, invocationID: invocationID,
              resourceID: resourceID, inputElementID: "fixture-empty-input-\(resourceID)")
    }

    func testTwoThreeFourAndFiveInputsRetainLegacyHistoryAcrossPriorStates() async throws {
        for count in [2, 3, 4, 5] {
            for state in [ReceiptOutcome.uploadStarted, .unknown, .verifiedReady, .definitiveFailure] {
                let legacy = try await incident(state: state), before = try history(legacy)
                let adapter = LegacyResourceFixtureAdapter(), coordinator = coordinator(legacy.store, adapter)
                var selected: [ImportedAsset] = [], invocations = Set<UUID>(), resources = Set<UUID>()
                for _ in 1..<count {
                    let b = try await image(legacy.store); selected.append(b)
                    try await coordinator.select(try await selection(b, legacy.store))
                    let op = try await waitForStart(b, legacy.store)
                    let record = try await legacy.store.asset(id: b.id)
                    let invocation = try await legacy.store.dispatchInvocationID(for: op.id)
                    XCTAssertTrue(invocations.insert(try XCTUnwrap(invocation)).inserted)
                    if let prepared = try await legacy.store.inputResource(for: op.id) {
                        XCTAssertEqual(prepared.operationID, op.id)
                        XCTAssertEqual(prepared.assetID, b.id)
                        XCTAssertEqual(prepared.invocationID, invocation)
                        XCTAssertTrue(resources.insert(prepared.resourceID).inserted)
                    }
                    XCTAssertEqual(record?.visibility, .swallowed)
                    XCTAssertEqual(try history(legacy), before,
                                   "New input must not rewrite A in \(count)/\(state)")
                }
                let inputs = await adapter.inputs()
                XCTAssertEqual(inputs, selected.map(\.id))
                XCTAssertFalse(inputs.contains(legacy.image.id), "A is never replayed, including safe failure")
                if state == .unknown || state == .uploadStarted {
                    XCTAssertEqual(resources.count, count - 1, "Each successor uses its own prepared resource")
                }
                for b in selected {
                    await adapter.set(.verifiedReady, for: b.id)
                }
                // Only the new fixture requests are observed. The historical
                // operation has no adapter registration and remains read-only.
                try await coordinator.observePending(authorize: { $0.clickBindingID != nil })
                for b in selected {
                    let op = try await operation(b, legacy.store)
                    XCTAssertEqual(op.phase, .succeeded)
                }
                XCTAssertEqual(try history(legacy), before)
            }
        }
    }

    func testRestartAndCurrentDocumentPreparationDoNotUpgradeLegacyA() async throws {
        for currentDocument in ["incident-document", "refreshed-document"] {
            let legacy = try await incident(), before = try history(legacy)
            let reopened = try QueueStore(databaseURL: legacy.databaseURL)
            try await reopened.recoverInterruptedOperations()
            let adapter = LegacyResourceFixtureAdapter(), coordinator = coordinator(reopened, adapter)
            let b = try await image(reopened), c = try await image(reopened)
            for next in [b, c] {
                try await coordinator.select(try await selection(next, reopened,
                    target: target(document: currentDocument, pin: UUID())))
                _ = try await waitForStart(next, reopened)
            }
            let inputs = await adapter.inputs()
            XCTAssertEqual(inputs, [b.id, c.id])
            XCTAssertEqual(try history(legacy), before)
            let oldResource = try await reopened.inputResource(for: legacy.operation.id)
            XCTAssertNil(oldResource, "Reopening must never fabricate legacy ownership")
        }
    }

    func testFrozenOldCallMissingNewLeaseKeysAllowsFreshBCWithoutAnyBackfill() async throws {
        let legacy = try await incident(legacyCall: true), before = try history(legacy)
        let key = "transfer-dispatch-call-v1:" + legacy.operation.id.uuidString
        let data = try await legacy.store.checkpoint(for: key)
        let bytes = try XCTUnwrap(data)
        let oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(oldJSON["inputExecutionReturned"])
        XCTAssertNil(oldJSON["inputResource"])
        let decoded = try JSONDecoder().decode(DispatchCallRecord.self, from: bytes)
        XCTAssertNil(decoded.inputExecutionReturned)
        XCTAssertNil(decoded.inputResource)
        XCTAssertNotNil(decoded.returnedReceipt)
        let adapter = LegacyResourceFixtureAdapter(), coordinator = coordinator(legacy.store, adapter)
        var newIDs: [UUID] = []
        for _ in 0..<2 {
            let next = try await image(legacy.store); newIDs.append(next.id)
            try await coordinator.select(try await selection(next, legacy.store))
            _ = try await waitForStart(next, legacy.store)
        }
        let inputs = await adapter.inputs(), after = try await legacy.store.checkpoint(for: key)
        XCTAssertEqual(inputs, newIDs)
        XCTAssertEqual(after, bytes)
        XCTAssertEqual(try history(legacy), before)
    }

    func testSameTabDifferentChatUsesTheNewClickTargetAndPreservesOldUnknown() async throws {
        let legacy = try await incident(), before = try history(legacy)
        let adapter = LegacyResourceFixtureAdapter(), coordinator = coordinator(legacy.store, adapter)
        let b = try await image(legacy.store), newTarget = target(document: "second-chat-document", draft: 2, pin: UUID())
        try await coordinator.select(try await selection(b, legacy.store, target: newTarget))
        let bo = try await waitForStart(b, legacy.store)
        XCTAssertEqual(bo.target, newTarget)
        XCTAssertNotEqual(bo.target.logicalDraftIdentity, legacy.operation.target.logicalDraftIdentity)
        XCTAssertEqual(try history(legacy), before)
        let inputs = await adapter.inputs()
        XCTAssertEqual(inputs, [b.id])
    }

    func testUnavailableCurrentResourceRefusesImmediatelyAndKeepsAUnchanged() async throws {
        let legacy = try await incident(), before = try history(legacy)
        let adapter = LegacyResourceFixtureAdapter(allowPreparation: false)
        let coordinator = coordinator(legacy.store, adapter)
        for _ in 0..<3 {
            let b = try await image(legacy.store), click = try await selection(b, legacy.store)
            try await coordinator.select(click)
            let op = try await operation(b, legacy.store), record = try await legacy.store.asset(id: b.id)
            let invocation = try await legacy.store.dispatchInvocationID(for: op.id)
            XCTAssertEqual(op.phase, .failed)
            XCTAssertEqual(record?.visibility, .visible)
            XCTAssertNil(invocation)
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime, click.deadlineUptime)
            XCTAssertFalse(click.isValid())
        }
        let inputs = await adapter.inputs()
        XCTAssertEqual(inputs, [])
        XCTAssertEqual(try history(legacy), before)
    }

    func testConfirmedInputReleasesOnlyTheExecutionLaneWhileStartObservationContinues() async throws {
        let legacy = try await incident(), before = try history(legacy)
        let adapter = LegacyResourceFixtureAdapter(), coordinator = coordinator(legacy.store, adapter)
        let b = try await image(legacy.store), c = try await image(legacy.store)
        await adapter.holdStart(for: b.id)
        try await coordinator.select(try await selection(b, legacy.store))
        let bo = try await operation(b, legacy.store)
        let bStart = try await legacy.store.uploadStartReceipt(for: bo.id)
        let bRecord = try await legacy.store.asset(id: b.id)
        let bActive = try await legacy.store.inputExecutionIsActive(for: bo.id)
        XCTAssertNil(bStart)
        XCTAssertEqual(bRecord?.visibility, .visible, "Execution return is not START")
        XCTAssertFalse(bActive)
        try await coordinator.select(try await selection(c, legacy.store))
        let co = try await waitForStart(c, legacy.store)
        await adapter.releaseStart(for: b.id)
        _ = try await waitForStart(b, legacy.store)
        let cStart = try await legacy.store.uploadStartReceipt(for: co.id)
        XCTAssertNotNil(cStart, "C must progress while B still observes START")
        let inputs = await adapter.inputs()
        XCTAssertEqual(inputs, [b.id, c.id])
        XCTAssertEqual(try history(legacy), before)
    }

    func testThrownOrMisboundAppendReleasesExecutionWithoutInventingAReceipt() async throws {
        for failure in [LegacyResourceFixtureAdapter.AppendFailure.thrown, .misbound] {
            let legacy = try await incident(), before = try history(legacy)
            let adapter = LegacyResourceFixtureAdapter(), coordinator = coordinator(legacy.store, adapter)
            let b = try await image(legacy.store), c = try await image(legacy.store)
            await adapter.failAppend(for: b.id, failure: failure)
            try await coordinator.select(try await selection(b, legacy.store))
            var bo = try await operation(b, legacy.store)
            for _ in 0..<500 {
                let active = try await legacy.store.inputExecutionIsActive(for: bo.id)
                bo = try await operation(b, legacy.store)
                if bo.phase == .unknown, !active { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let active = try await legacy.store.inputExecutionIsActive(for: bo.id)
            let bReceipt = try await legacy.store.receipt(for: bo.id)
            XCTAssertEqual(bo.phase, .unknown)
            XCTAssertFalse(active)
            XCTAssertNil(bReceipt)
            try await coordinator.select(try await selection(c, legacy.store))
            _ = try await waitForStart(c, legacy.store)
            let inputs = await adapter.inputs()
            XCTAssertEqual(inputs, [b.id, c.id])
            XCTAssertEqual(try history(legacy), before)
        }
    }

    func testLiveExecutionLeaseBlocksAnotherPermitUntilItsOriginalReturn() async throws {
        let legacy = try await incident(), before = try history(legacy), owner = UUID()
        let b = try await image(legacy.store), bt = target(pin: UUID())
        let bo = try await legacy.store.prepare(assetID: b.id, target: bt)
        let bResource = resource(bo, b)
        let bInvocation = try await legacy.store.markDispatchIntent(bo.id,
            selection: try await selection(b, legacy.store, target: bt), ownerID: owner,
            policy: policy, inputResource: bResource)
        let activeBefore = try await legacy.store.inputExecutionIsActive(for: bo.id)
        XCTAssertTrue(activeBefore)
        let c = try await image(legacy.store), ct = target(pin: UUID())
        let co = try await legacy.store.prepare(assetID: c.id, target: ct)
        let cResource = resource(co, c)
        do {
            _ = try await legacy.store.markDispatchIntent(co.id,
                selection: try await selection(c, legacy.store, target: ct), ownerID: owner,
                policy: policy, inputResource: cResource)
            XCTFail("A fresh permit cannot bypass B's active execution")
        } catch RiftletError.targetBusy {}
        do {
            try await legacy.store.recordInputExecutionReturned(operationID: bo.id,
                invocationID: UUID(), ownerID: owner)
            XCTFail("A different invocation released B")
        } catch RiftletError.mismatchedReceipt {}
        do {
            try await legacy.store.recordInputExecutionReturned(operationID: bo.id,
                invocationID: bInvocation, ownerID: UUID())
            XCTFail("A different owner released B")
        } catch RiftletError.mismatchedReceipt {}
        try await legacy.store.recordInputExecutionReturned(operationID: bo.id,
            invocationID: bInvocation, ownerID: owner)
        let activeAfter = try await legacy.store.inputExecutionIsActive(for: bo.id)
        XCTAssertFalse(activeAfter)
        let returned = try await legacy.store.receipt(for: bo.id)
        XCTAssertNil(returned, "Input execution release is independent of final receipt persistence")
        _ = try await legacy.store.markDispatchIntent(co.id,
            selection: try await selection(c, legacy.store, target: ct), ownerID: owner,
            policy: policy, inputResource: cResource)
        XCTAssertEqual(try history(legacy), before)
    }

    func testPreparedResourceCannotBeReboundToAnotherAssetOperationTargetOrHash() async throws {
        for field in ["operation", "asset", "attempt", "hash", "target"] {
            let legacy = try await incident(), before = try history(legacy), owner = UUID()
            let b = try await image(legacy.store), bt = target(pin: UUID())
            let bo = try await legacy.store.prepare(assetID: b.id, target: bt)
            let permit = PreparedInputResource(operationID: field == "operation" ? UUID() : bo.id,
                assetID: field == "asset" ? UUID() : b.id, attempt: field == "attempt" ? 2 : bo.attempt,
                assetSHA256: field == "hash" ? String(repeating: "b", count: 64) : b.sha256,
                target: field == "target" ? target(pin: UUID()) : bt, invocationID: UUID(),
                resourceID: UUID(), inputElementID: "fixture-current-empty-input")
            do {
                _ = try await legacy.store.markDispatchIntent(bo.id,
                    selection: try await selection(b, legacy.store, target: bt), ownerID: owner,
                    policy: policy, inputResource: permit)
                XCTFail("Mismatched \(field) permit authorized dispatch")
            } catch RiftletError.mismatchedReceipt {}
            catch RiftletError.invalidTransition {}
            let still = try await legacy.store.operation(id: bo.id)
            let invocation = try await legacy.store.dispatchInvocationID(for: bo.id)
            XCTAssertEqual(still?.phase, .prepared)
            XCTAssertNil(invocation)
            XCTAssertEqual(try history(legacy), before)
        }
    }

    func testRefreshedDocumentMayRestartRequestCounterWithoutBorrowingPriorOwnership() async throws {
        let url = directory.appendingPathComponent("\(UUID()).sqlite")
        let store = try QueueStore(databaseURL: url), sql = try SQLiteDatabase(url: url), owner = UUID()
        let continuationProfile = "refreshed-document-input-fixture"
        let admittingPolicy = ReceiptPolicy(syntheticUploadStartProfiles: [startProfile: .webChat],
            syntheticContinuationProfiles: [continuationProfile: .webChat],
            requiredInputIsolationProfiles: [continuationProfile])
        func ownedStart(_ operation: TransferOperation, _ image: ImportedAsset,
                        invocation: UUID, inputID: String) -> TransferReceipt {
            let attachment = "attachment-\(operation.id)", startID = "start-\(operation.id)"
            let binding = AttachmentOperationBinding(operationID: operation.id, assetID: image.id,
                attempt: operation.attempt, assetSHA256: image.sha256, target: operation.target,
                invocationID: invocation, attachmentID: attachment)
            return .init(operationID: operation.id, assetID: image.id, attempt: operation.attempt,
                assetSHA256: image.sha256, target: operation.target, outcome: .uploadStarted,
                profileID: readyProfile, attachmentID: attachment, belongsToOriginalDraft: true,
                isUploading: true,
                uploadStartEvidence: .init(profileID: startProfile, signal: .correlatedProgress, evidenceID: startID),
                continuationEvidence: .init(version: 3, profileID: continuationProfile,
                    evidenceID: "continuation-\(operation.id)", invocationID: invocation, binding: binding,
                    inputIsolation: .init(ownershipID: "ownership-\(operation.id)", inputElementID: inputID,
                        requestID: 1, requestSequence: 2, requestTransport: .xhr,
                        originalSHA256: image.sha256, originalByteCount: image.byteCount, startEvidenceID: startID,
                        inputSequence: 1, callSettledSequence: 3, startSequence: 4, observedSequence: 5)))
        }
        let a = try await image(store), at = target(pin: UUID())
        let ao = try await store.prepare(assetID: a.id, target: at)
        let ai = try await store.markDispatchIntent(ao.id,
            selection: try await selection(a, store, target: at), ownerID: owner, policy: admittingPolicy)
        let aStart = ownedStart(ao, a, invocation: ai, inputID: "original-document-input")
        _ = try await store.apply(aStart, policy: admittingPolicy)
        try await store.recordAppendReturned(aStart, invocationID: ai, ownerID: owner)
        try await store.markUnknown(ao.id, reason: "Synthetic old-document final observation lost")
        let original = Incident(store: store, sql: sql, databaseURL: url, image: a,
            operation: ao, attachmentID: try XCTUnwrap(aStart.attachmentID))
        let before = try history(original)

        let b = try await image(store), bt = target(document: "refreshed-document", pin: UUID())
        let bo = try await store.prepare(assetID: b.id, target: bt), prepared = resource(bo, b)
        let bi = try await store.markDispatchIntent(bo.id,
            selection: try await selection(b, store, target: bt), ownerID: UUID(),
            policy: admittingPolicy, inputResource: prepared)
        let bStart = ownedStart(bo, b, invocation: bi, inputID: prepared.inputElementID)
        XCTAssertEqual(aStart.continuationEvidence?.inputIsolation?.requestID, 1)
        XCTAssertEqual(bStart.continuationEvidence?.inputIsolation?.requestID, 1)
        XCTAssertNotEqual(aStart.continuationEvidence?.inputIsolation?.ownershipID,
                          bStart.continuationEvidence?.inputIsolation?.ownershipID)
        XCTAssertNotEqual(aStart.attachmentID, bStart.attachmentID)
        _ = try await store.apply(bStart, policy: admittingPolicy)
        let retainedStart = try await store.uploadStartReceipt(for: bo.id)
        let retainedOwnership = try await store.checkpoint(for: "transfer-input-isolation-v1:" + bo.id.uuidString)
        XCTAssertEqual(retainedStart, bStart)
        XCTAssertNotNil(retainedOwnership)
        XCTAssertEqual(try history(original), before)
    }

    func testLateLegacyCompleteFailureAndCompensationCannotChangeBOrItsOwnership() async throws {
        let legacy = try await incident(), adapter = LegacyResourceFixtureAdapter()
        let coordinator = coordinator(legacy.store, adapter), b = try await image(legacy.store)
        try await coordinator.select(try await selection(b, legacy.store))
        let bo = try await waitForStart(b, legacy.store)
        let bFixture = Incident(store: legacy.store, sql: legacy.sql, databaseURL: legacy.databaseURL,
            image: b, operation: bo, attachmentID: "attachment-\(bo.id)")
        let bHistory = try history(bFixture)
        let bResource = try await legacy.store.inputResource(for: bo.id)
        _ = try await legacy.store.apply(receipt(legacy.operation, image: legacy.image,
            outcome: .verifiedReady, attachmentID: legacy.attachmentID), policy: policy)
        let unretiredFailure = TransferReceipt(operationID: legacy.operation.id,
            assetID: legacy.image.id, attempt: legacy.operation.attempt, assetSHA256: legacy.image.sha256,
            target: legacy.operation.target, outcome: .unknown, profileID: readyProfile,
            attachmentID: legacy.attachmentID, belongsToOriginalDraft: true, hasError: true)
        _ = try await legacy.store.apply(unretiredFailure, policy: policy)
        XCTAssertEqual(try history(bFixture), bHistory)
        let retained = try await legacy.store.inputResource(for: bo.id)
        XCTAssertEqual(retained, bResource)
        let c = try await image(legacy.store)
        try await coordinator.select(try await selection(c, legacy.store))
        _ = try await waitForStart(c, legacy.store)
        let inputs = await adapter.inputs(), aRecord = try await legacy.store.asset(id: legacy.image.id)
        XCTAssertEqual(inputs, [b.id, c.id])
        XCTAssertEqual(aRecord?.visibility, .swallowed)
    }

    func testLegacyAttachmentOwnershipSurvivesANewClickPinAfterLateCompletion() async throws {
        let legacy = try await incident()
        _ = try await legacy.store.apply(receipt(legacy.operation, image: legacy.image,
            outcome: .verifiedReady, attachmentID: legacy.attachmentID), policy: policy)
        let before = try history(legacy)
        let b = try await image(legacy.store)
        let operation = try await legacy.store.prepare(assetID: b.id, target: target(pin: UUID()))
        try await legacy.store.markDispatchIntent(operation.id)
        do {
            _ = try await legacy.store.apply(receipt(operation, image: b, outcome: .uploadStarted,
                attachmentID: legacy.attachmentID), policy: policy)
            XCTFail("A new click pin must not acquire the legacy attachment ID")
        } catch RiftletError.mismatchedReceipt {}
        let bStart = try await legacy.store.uploadStartReceipt(for: operation.id)
        let bRecord = try await legacy.store.asset(id: b.id)
        XCTAssertNil(bStart)
        XCTAssertEqual(bRecord?.visibility, .visible)
        XCTAssertEqual(try history(legacy), before)
    }
}

/// Models only a target-side resource guard and independent receipts. It does
/// not model ChatGPT's DOM, networking or attachment-preservation behavior.
private actor LegacyResourceFixtureAdapter: IndependentInputResourceAdapter {
    enum AppendFailure: Equatable, Sendable { case thrown, misbound }
    nonisolated let id = "legacy-input-fixture"
    private let allowPreparation: Bool
    private var calls: [TransferRequest] = []
    private var states: [UUID: ReceiptOutcome] = [:]
    private var heldStarts = Set<UUID>()
    private var startWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var failures: [UUID: AppendFailure] = [:]

    init(allowPreparation: Bool = true) { self.allowPreparation = allowPreparation }
    func captureTarget() throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { target.adapterID == id }
    func set(_ state: ReceiptOutcome, for image: UUID) { states[image] = state }
    func inputs() -> [UUID] { calls.map { $0.asset.id } }
    func holdStart(for image: UUID) { heldStarts.insert(image) }
    func releaseStart(for image: UUID) {
        heldStarts.remove(image)
        startWaiters.removeValue(forKey: image)?.resume()
    }
    func failAppend(for image: UUID, failure: AppendFailure) { failures[image] = failure }

    func prepareInputResource(_ request: TransferRequest) throws -> PreparedInputResource {
        guard allowPreparation, let invocation = request.invocationID else {
            throw RiftletError.adapterUnavailable("Synthetic current input is occupied")
        }
        let resource = UUID()
        return .init(operationID: request.operation.id, assetID: request.asset.id,
                     attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
                     target: request.operation.target, invocationID: invocation, resourceID: resource,
                     inputElementID: "fixture-empty-input-\(resource)")
    }

    func releaseInputResource(_ resource: PreparedInputResource) async {}

    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try await append(request, onInputConfirmed: { _ in })
    }
    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt {
        calls.append(request); states[request.asset.id] = .uploadStarted
        await onInputConfirmed(receipt(request, outcome: .inputTriggered))
        if heldStarts.contains(request.asset.id) {
            await withCheckedContinuation { startWaiters[request.asset.id] = $0 }
        }
        if failures[request.asset.id] == .thrown { throw RiftletError.adapterUnavailable("Synthetic transport return failure") }
        return receipt(request, outcome: .uploadStarted, misbound: failures[request.asset.id] == .misbound)
    }
    func reconcile(_ request: TransferRequest) -> TransferReceipt {
        receipt(request, outcome: states[request.asset.id] ?? .unknown)
    }
    private func receipt(_ request: TransferRequest, outcome: ReceiptOutcome, misbound: Bool = false) -> TransferReceipt {
        .init(operationID: misbound ? UUID() : request.operation.id,
              assetID: request.asset.id, attempt: request.operation.attempt,
              assetSHA256: request.asset.sha256, target: request.operation.target, outcome: outcome,
              profileID: "legacy-input-fixture-ready", attachmentID: "attachment-\(request.operation.id)",
              positiveReady: outcome == .verifiedReady, belongsToOriginalDraft: true,
              isUploading: outcome == .uploadStarted,
              uploadStartEvidence: outcome == .uploadStarted
                  ? .init(profileID: "legacy-input-fixture-start", signal: .correlatedProgress,
                          evidenceID: "start-\(request.operation.id)") : nil)
    }
}
