import Foundation
import XCTest
@testable import RiftletCore

/// Controlled coordinator/SQLite tests. Native FileList append and START are
/// covered separately by the browser tests; these fixtures never contact ChatGPT.
final class LegacyUnknownInputLeaseTests: XCTestCase {
    private var directory: URL!
    private var policy: ReceiptPolicy {
        .init(syntheticUploadStartProfiles: ["independent-file-start": .webChat])
    }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("file-input-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func target(document: String = "same-document") -> TargetLease {
        // No React-derived logical identity is necessary for normal file input.
        .init(adapterID: "independent-file-fixture", surface: .webChat, applicationID: "com.google.Chrome",
              sessionID: "fixture-process", windowID: "1", tabID: "1", documentID: document,
              composerID: "composer", draftGeneration: "1", clickBindingID: UUID())
    }
    private func store() throws -> QueueStore {
        try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
    }
    private func image(_ store: QueueStore) async throws -> ImportedAsset {
        let id = UUID(), bytes = Data("controlled file input fixture".utf8)
        let asset = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count),
            pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: directory.appendingPathComponent(asset.fileName))
        _ = try await store.importAsset(asset); return asset
    }
    private func select(_ asset: ImportedAsset, in store: QueueStore, target: TargetLease? = nil) async throws -> AcceptedSelection {
        let record = try await store.asset(id: asset.id), now = ProcessInfo.processInfo.systemUptime
        return .init(assetID: asset.id, target: target ?? self.target(), hostEpoch: UUID(),
            acknowledgedUptime: now - 0.005, eventUptime: now - 0.01, acceptedUptime: now,
            visibilityRevision: try XCTUnwrap(record?.visibilityRevision), deadlineUptime: now + 30,
            authorization: .nativeClickPin)
    }
    private func coordinator(_ store: QueueStore, _ adapter: IndependentFileFixtureAdapter,
                             capacity: Int = 12) -> TransferCoordinator {
        .init(store: store, adapter: adapter, mediaDirectory: directory, policy: policy,
              maximumPendingSelections: capacity, validateAcceptedSelection: { $0.isValid() })
    }
    private func operation(_ asset: ImportedAsset, _ store: QueueStore) async throws -> TransferOperation {
        let record = try await store.asset(id: asset.id)
        let op = try await store.operation(id: XCTUnwrap(record?.activeOperationID))
        return try XCTUnwrap(op)
    }
    private func waitForStart(_ asset: ImportedAsset, _ store: QueueStore) async throws -> TransferOperation {
        for _ in 0..<500 {
            let op = try await operation(asset, store)
            if try await store.uploadStartReceipt(for: op.id) != nil { return op }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Current input never reached START")
        return try await operation(asset, store)
    }

    func testTwoThreeAndFiveInputsNeedNoPriorContinuationOrComplete() async throws {
        for count in [2, 3, 5] {
            for firstUnknown in [false, true] {
                let store = try store(), adapter = IndependentFileFixtureAdapter()
                let coordinator = coordinator(store, adapter), first = try await image(store)
                try await coordinator.select(try await select(first, in: store))
                let original = try await waitForStart(first, store)
                let start = try await store.uploadStartReceipt(for: original.id)
                XCTAssertNil(start?.continuationEvidence)
                if firstUnknown { try await store.markUnknown(original.id, reason: "Controlled old upload result") }
                let before = try await operation(first, store), beforeImage = try await store.asset(id: first.id)
                var inputs = [first.id]
                for _ in 1..<count {
                    let next = try await image(store); inputs.append(next.id)
                    try await coordinator.select(try await select(next, in: store))
                    _ = try await waitForStart(next, store)
                    let record = try await store.asset(id: next.id)
                    XCTAssertEqual(record?.visibility, .swallowed)
                }
                try await coordinator.observePending()
                let calls = await adapter.inputs(), observations = await adapter.observations()
                let after = try await operation(first, store), afterImage = try await store.asset(id: first.id)
                XCTAssertEqual(calls, inputs); XCTAssertEqual(observations, [])
                XCTAssertEqual(after, before); XCTAssertEqual(afterImage, beforeImage)
                XCTAssertEqual(before.phase, firstUnknown ? .unknown : .inputTriggered)
            }
        }
    }

    func testLegacyRowsAndOldReservationDecodeStayUnchangedAcrossStartupAndNewInputs() async throws {
        for hasOldCall in [false, true] {
            let url = directory.appendingPathComponent("legacy-\(hasOldCall).sqlite")
            let store = try QueueStore(databaseURL: url), asset = try await image(store)
            let old = try await store.prepare(assetID: asset.id, target: target())
            let sql = try SQLiteDatabase(url: url)
            try sql.execute("UPDATE operations SET phase='unknown',reason='historical UNKNOWN' WHERE id=?", [old.id.uuidString])
            try sql.execute("UPDATE assets SET status='unknown' WHERE id=?", [asset.id.uuidString])
            if hasOldCall {
                let reservation = PreparedInputResource(operationID: old.id, assetID: asset.id, attempt: old.attempt,
                    assetSHA256: asset.sha256, target: old.target, invocationID: UUID(), resourceID: UUID(),
                    inputElementID: "old-retained-file")
                let record = DispatchCallRecord(version: 1, operationID: old.id, assetID: asset.id, attempt: old.attempt,
                    assetSHA256: asset.sha256, target: old.target, invocationID: reservation.invocationID,
                    ownerID: UUID(), returnedReceipt: nil, inputResource: reservation)
                try await store.saveCheckpoint(JSONEncoder().encode(record), for: "transfer-dispatch-call-v1:" + old.id.uuidString)
            }
            func snapshot() throws -> [[[String?]]] {
                [try sql.rows("SELECT * FROM operations WHERE id=?", [old.id.uuidString]),
                 try sql.rows("SELECT * FROM assets WHERE id=?", [asset.id.uuidString]),
                 try sql.rows("SELECT * FROM checkpoints WHERE key LIKE ? ORDER BY key", ["%" + old.id.uuidString])]
            }
            let before = try snapshot(), reopened = try QueueStore(databaseURL: url)
            let adapter = IndependentFileFixtureAdapter(), coordinator = coordinator(reopened, adapter)
            try await coordinator.recover()
            try await coordinator.recoverOriginalObservations(operationIDs: [old.id])
            try await coordinator.observePending()
            try await coordinator.select(try await select(asset, in: reopened))
            for _ in 0..<2 {
                let next = try await image(reopened)
                try await coordinator.select(try await select(next, in: reopened))
                _ = try await waitForStart(next, reopened)
            }
            XCTAssertEqual(try snapshot(), before)
            let inputs = await adapter.inputs(), observed = await adapter.observations()
            XCTAssertEqual(inputs.count, 2); XCTAssertFalse(inputs.contains(asset.id)); XCTAssertEqual(observed, [])
        }
    }

    func testSynchronousExecutionBlocksSecondButPendingStartDoesNot() async throws {
        let store = try store(), a = try await image(store), b = try await image(store)
        let inputGate = FileInputTestGate(), startGate = FileInputTestGate()
        let entered = expectation(description: "First setter entered")
        let adapter = IndependentFileFixtureAdapter()
        await adapter.configure(a.id, inputGate: inputGate, startGate: startGate, entered: entered)
        let coordinator = coordinator(store, adapter)
        let first = Task { try await coordinator.select(try await select(a, in: store)) }
        await fulfillment(of: [entered], timeout: 5)
        try await coordinator.select(try await select(b, in: store))
        let blocked = await adapter.inputs(), preparedB = try await operation(b, store)
        XCTAssertEqual(blocked, []); XCTAssertEqual(preparedB.phase, .prepared)
        await inputGate.open()
        try await first.value
        _ = try await waitForStart(b, store)
        let currentA = try await operation(a, store), pendingStart = try await store.uploadStartReceipt(for: currentA.id)
        let calls = await adapter.inputs()
        XCTAssertEqual(calls, [a.id, b.id]); XCTAssertNil(pendingStart)
        await startGate.open()
        _ = try await waitForStart(a, store)
    }

    func testPendingStartObserversDoNotConsumeInputCapacity() async throws {
        let store = try store(), adapter = IndependentFileFixtureAdapter(), startGate = FileInputTestGate()
        // A one-selection UI capacity must not become a one-upload limit.
        let coordinator = coordinator(store, adapter, capacity: 1)
        var selected: [ImportedAsset] = []
        for _ in 0..<5 {
            let asset = try await image(store); selected.append(asset)
            await adapter.configure(asset.id, startGate: startGate)
            try await coordinator.select(try await select(asset, in: store))
        }
        let inputs = await adapter.inputs(); XCTAssertEqual(inputs, selected.map(\.id))
        for asset in selected {
            let op = try await operation(asset, store), start = try await store.uploadStartReceipt(for: op.id)
            XCTAssertNil(start)
        }
        await startGate.open()
        for asset in selected { _ = try await waitForStart(asset, store) }
    }

    func testLostCommitReplyObservesOriginalWithoutResubmittingAndAllowsNextFile() async throws {
        let store = try store(), a = try await image(store), b = try await image(store)
        let adapter = IndependentFileFixtureAdapter()
        await adapter.configure(a.id, loseReply: true)
        let coordinator = coordinator(store, adapter)
        try await coordinator.select(try await select(a, in: store))
        let unknown = try await operation(a, store), retained = try await store.asset(id: a.id)
        XCTAssertEqual(unknown.phase, .unknown); XCTAssertEqual(retained?.visibility, .visible)
        try await coordinator.select(try await select(b, in: store))
        _ = try await waitForStart(b, store)
        try await coordinator.select(try await select(a, in: store))
        let inputs = await adapter.inputs(), observations = await adapter.observations()
        XCTAssertEqual(inputs, [a.id, b.id]); XCTAssertEqual(observations, [a.id])
        let same = try await operation(a, store)
        XCTAssertEqual(same.id, unknown.id); XCTAssertEqual(same.attempt, 1)
        await adapter.reportStart(for: a.id)
        try await coordinator.observePending()
        _ = try await waitForStart(a, store)
        let finalInputs = await adapter.inputs(); XCTAssertEqual(finalInputs, [a.id, b.id])
    }

    func testTargetChangedBeforeInputKeepsThumbnailAndSubmitsNothing() async throws {
        let store = try store(), asset = try await image(store), adapter = IndependentFileFixtureAdapter()
        await adapter.invalidateTarget()
        let coordinator = coordinator(store, adapter)
        try await coordinator.select(try await select(asset, in: store))
        let op = try await operation(asset, store), record = try await store.asset(id: asset.id)
        let invocation = try await store.dispatchInvocationID(for: op.id), inputs = await adapter.inputs()
        XCTAssertEqual(op.phase, .failed); XCTAssertEqual(record?.visibility, .visible)
        XCTAssertNil(invocation); XCTAssertEqual(inputs, [])
    }

    func testAnIndependentIntentStillCannotReuseTheSameOperation() async throws {
        let store = try store(), asset = try await image(store), t = target(), owner = UUID()
        let op = try await store.prepare(assetID: asset.id, target: t)
        let first = try await store.markIndependentFileInputIntent(op.id,
            selection: try await select(asset, in: store, target: t), ownerID: owner)
        do {
            _ = try await store.markIndependentFileInputIntent(op.id,
                selection: try await select(asset, in: store, target: t), ownerID: owner)
            XCTFail("A duplicate click dispatched the same operation twice")
        } catch RiftletError.invalidTransition {}
        let preserved = try await store.dispatchInvocationID(for: op.id); XCTAssertEqual(preserved, first)
    }
}

private actor FileInputTestGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let ready = waiters; waiters.removeAll()
        for waiter in ready { waiter.resume() }
    }
}

private actor IndependentFileFixtureAdapter: IndependentFileInputAdapter {
    nonisolated let id = "independent-file-fixture"
    private struct Plan {
        var inputGate: FileInputTestGate?
        var startGate: FileInputTestGate?
        var entered: XCTestExpectation?
        var loseReply: Bool
    }
    private var plans: [UUID: Plan] = [:]
    private var calls: [UUID] = []
    private var observed: [UUID] = []
    private var reportedStarts = Set<UUID>()
    private var validTarget = true
    func configure(_ asset: UUID, inputGate: FileInputTestGate? = nil, startGate: FileInputTestGate? = nil,
                   entered: XCTestExpectation? = nil, loseReply: Bool = false) {
        plans[asset] = .init(inputGate: inputGate, startGate: startGate, entered: entered, loseReply: loseReply)
    }
    func invalidateTarget() { validTarget = false }
    func reportStart(for asset: UUID) { reportedStarts.insert(asset) }
    func inputs() -> [UUID] { calls }
    func observations() -> [UUID] { observed }
    func captureTarget() throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { validTarget }
    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try await append(request, onInputConfirmed: { _ in })
    }
    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt {
        let plan = plans[request.asset.id]
        plan?.entered?.fulfill()
        if let gate = plan?.inputGate { await gate.wait() }
        calls.append(request.asset.id)
        if plan?.loseReply == true { throw RiftletError.adapterUnavailable("Controlled lost commit reply") }
        if let gate = plan?.startGate {
            await onInputConfirmed(receipt(request, outcome: .inputTriggered))
            await gate.wait()
        }
        return receipt(request, outcome: .uploadStarted)
    }
    func reconcile(_ request: TransferRequest) -> TransferReceipt {
        observed.append(request.asset.id)
        return receipt(request, outcome: reportedStarts.contains(request.asset.id) ? .uploadStarted : .unknown)
    }
    private func receipt(_ request: TransferRequest, outcome: ReceiptOutcome) -> TransferReceipt {
        .init(operationID: request.operation.id, assetID: request.asset.id, attempt: request.operation.attempt,
            assetSHA256: request.asset.sha256, target: request.operation.target, outcome: outcome,
            profileID: "independent-file-observation", attachmentID: "attachment-\(request.operation.id)",
            belongsToOriginalDraft: true, isUploading: outcome == .uploadStarted,
            uploadStartEvidence: outcome == .uploadStarted ? .init(profileID: "independent-file-start",
                signal: .attachmentAccepted, evidenceID: "start-\(request.operation.id)") : nil)
    }
}
