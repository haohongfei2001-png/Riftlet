import Foundation
import XCTest
@testable import RiftletCore

final class InputExecutionBoundaryTests: XCTestCase {
    func testUnknownSynchronousReturnAllowsSecondInputWhileFirstObserverIsStillWaiting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("input-return-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        func image() async throws -> ImportedAsset {
            let id = UUID(), bytes = Data("synthetic input boundary".utf8)
            let asset = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
                sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count),
                pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
            try bytes.write(to: directory.appendingPathComponent(asset.fileName))
            _ = try await store.importAsset(asset); return asset
        }
        let a = try await image(), b = try await image(), gate = UnknownExecutionObservationGate()
        let adapter = UnknownExecutionAdapter(unknownAsset: a.id, gate: gate)
        let coordinator = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: directory,
            policy: .init(syntheticUploadStartProfiles: ["execution-return-start": .webChat]),
            validateAcceptedSelection: { $0.isValid() })
        func selection(_ asset: ImportedAsset) -> AcceptedSelection {
            let now = ProcessInfo.processInfo.systemUptime
            return .init(assetID: asset.id,
                target: .init(adapterID: adapter.id, surface: .webChat, applicationID: "com.google.Chrome",
                    sessionID: "fixture-process", windowID: "1", tabID: "1", documentID: "same-document",
                    composerID: "composer", draftGeneration: "1", clickBindingID: UUID()),
                hostEpoch: UUID(), acknowledgedUptime: now - 0.005, eventUptime: now - 0.01,
                acceptedUptime: now, visibilityRevision: 0, deadlineUptime: now + 30,
                authorization: .nativeClickPin)
        }
        let firstReturned = expectation(description: "Unknown sync execution releases the first selection")
        let first = Task {
            try await coordinator.select(selection(a))
            firstReturned.fulfill()
        }
        await fulfillment(of: [firstReturned], timeout: 5)
        try await coordinator.select(selection(b))
        let aRecord = try await store.asset(id: a.id), bRecord = try await store.asset(id: b.id)
        let aID = try XCTUnwrap(aRecord?.activeOperationID), bID = try XCTUnwrap(bRecord?.activeOperationID)
        // B can be persisted just after its independent execution callback.
        for _ in 0..<500 {
            if try await store.uploadStartReceipt(for: bID) != nil { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let bStart = try await store.uploadStartReceipt(for: bID)
        let aStart = try await store.uploadStartReceipt(for: aID)
        let beforeA = try await store.operation(id: aID), aReceipt = try await store.receipt(for: aID)
        let executionActive = try await store.inputExecutionIsActive(for: aID)
        let attempted = await adapter.executions(), inserted = await adapter.inputs()
        let legacyCalls = await adapter.legacyPhaseCalls()
        XCTAssertEqual(attempted, [a.id, b.id])
        XCTAssertEqual(inserted, [b.id], "The first simulated setter threw, but the second really performed input")
        XCTAssertEqual(legacyCalls, 0, "Independent execution cannot wait for a positive input receipt")
        XCTAssertNotNil(bStart); XCTAssertNil(aStart); XCTAssertNil(aReceipt)
        XCTAssertFalse(executionActive)
        XCTAssertEqual(beforeA?.phase, .dispatchIntent, "Execution return must not fabricate a receipt or START")
        XCTAssertEqual(aRecord?.visibility, .visible)
        await gate.open()
        try await first.value
        for _ in 0..<500 {
            if try await store.operation(id: aID)?.phase == .unknown { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let finalA = try await store.operation(id: aID), preservedB = try await store.uploadStartReceipt(for: bID)
        let finalInputs = await adapter.inputs()
        XCTAssertEqual(finalA?.phase, .unknown); XCTAssertEqual(preservedB, bStart)
        XCTAssertEqual(finalInputs, [b.id])
    }
}

private actor UnknownExecutionObservationGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let current = waiters; waiters.removeAll()
        for waiter in current { waiter.resume() }
    }
}

private actor UnknownExecutionAdapter: IndependentFileInputAdapter {
    nonisolated let id = "unknown-execution-fixture"
    private let unknownAsset: UUID
    private let gate: UnknownExecutionObservationGate
    private var attempted: [UUID] = []
    private var inserted: [UUID] = []
    private var phasedCalls = 0
    init(unknownAsset: UUID, gate: UnknownExecutionObservationGate) {
        self.unknownAsset = unknownAsset; self.gate = gate
    }
    func executions() -> [UUID] { attempted }
    func inputs() -> [UUID] { inserted }
    func legacyPhaseCalls() -> Int { phasedCalls }
    func captureTarget() throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { true }
    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try await append(request, onInputExecutionReturned: {})
    }
    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) throws -> TransferReceipt {
        phasedCalls += 1
        throw RiftletError.adapterUnavailable("Positive receipt path must not govern independent execution")
    }
    func append(_ request: TransferRequest,
                onInputExecutionReturned: @escaping @Sendable () async -> Void) async throws -> TransferReceipt {
        attempted.append(request.asset.id)
        let unknown = request.asset.id == unknownAsset
        if !unknown { inserted.append(request.asset.id) }
        await onInputExecutionReturned()
        if unknown { await gate.wait() }
        // Repeat the old callback after B has already run: idempotence must not
        // release another operation or invent a positive outcome for A.
        await onInputExecutionReturned()
        return receipt(request, outcome: unknown ? .unknown : .uploadStarted)
    }
    func reconcile(_ request: TransferRequest) -> TransferReceipt { receipt(request, outcome: .unknown) }
    private func receipt(_ request: TransferRequest, outcome: ReceiptOutcome) -> TransferReceipt {
        .init(operationID: request.operation.id, assetID: request.asset.id, attempt: request.operation.attempt,
            assetSHA256: request.asset.sha256, target: request.operation.target, outcome: outcome,
            profileID: "execution-return", attachmentID: "attachment-\(request.operation.id)",
            belongsToOriginalDraft: true, isUploading: outcome == .uploadStarted,
            uploadStartEvidence: outcome == .uploadStarted ? .init(profileID: "execution-return-start",
                signal: .attachmentAccepted, evidenceID: "start-\(request.operation.id)") : nil)
    }
}
