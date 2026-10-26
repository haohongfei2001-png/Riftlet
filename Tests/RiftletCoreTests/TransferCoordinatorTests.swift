import Foundation
import XCTest
@testable import RiftletCore

/// Exercises the coordinator against real temporary SQLite/files and a controlled,
/// in-memory adapter. No browser, system screenshot, clipboard or network is used.
final class TransferCoordinatorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftlet-coordinator-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> QueueStore {
        try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
    }

    private func makeAsset(in store: QueueStore) async throws -> ImportedAsset {
        let id = UUID()
        // These deliberate non-image bytes are only a file-existence fixture for
        // the transport boundary; image validation has separate capture tests.
        let bytes = Data("synthetic coordinator fixture".utf8)
        let image = ImportedAsset(id: id, sourceKey: "fixture-\(id)",
            fileName: "\(id).fixture", sha256: String(repeating: "a", count: 64),
            byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1,
            mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: directory.appendingPathComponent(image.fileName), options: .atomic)
        _ = try await store.importAsset(image)
        return image
    }

    private func makeCoordinator(store: QueueStore, adapter: CoordinatorFixtureAdapter) -> TransferCoordinator {
        TransferCoordinator(store: store, adapter: adapter, mediaDirectory: directory,
            policy: ReceiptPolicy(admittedProfiles: ["coordinator-fixture-ready-v1": .webChat]))
    }

    func testConcurrentSameAssetSelectionAppendsOnlyOnce() async throws {
        let store = try makeStore()
        let asset = try await makeAsset(in: store)
        let started = expectation(description: "First append reached controlled gate")
        let adapter = CoordinatorFixtureAdapter(holdFirstAppend: true, appendStarted: started)
        let coordinator = makeCoordinator(store: store, adapter: adapter)
        let first = Task { try await coordinator.select(asset.id) }

        await fulfillment(of: [started], timeout: 3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try await coordinator.select(asset.id) }
            }
            try await group.waitForAll()
        }
        let whileHeld = await adapter.snapshot()
        XCTAssertEqual(whileHeld.appendedAssets, [asset.id])
        XCTAssertEqual(whileHeld.captureCount, 1)

        await adapter.releaseFirstAppend()
        try await first.value
        let final = await adapter.snapshot()
        let record = try await store.asset(id: asset.id)
        XCTAssertEqual(final.appendedAssets, [asset.id])
        XCTAssertEqual(record?.status, .used)
    }

    func testAppendExceptionBecomesUnknownAndNextClickOnlyReconciles() async throws {
        let store = try makeStore()
        let asset = try await makeAsset(in: store)
        let adapter = CoordinatorFixtureAdapter(appendThrows: true)
        let coordinator = makeCoordinator(store: store, adapter: adapter)

        try await coordinator.select(asset.id)
        let before = try await store.asset(id: asset.id)
        XCTAssertEqual(before?.status, .unknown)
        let operationID = try XCTUnwrap(before?.activeOperationID)

        try await coordinator.select(asset.id)
        let after = try await store.asset(id: asset.id)
        let calls = await adapter.snapshot()
        let operation = try await store.operation(id: operationID)
        XCTAssertEqual(calls.appendedAssets, [asset.id])
        XCTAssertEqual(calls.reconciledAssets, [asset.id])
        XCTAssertEqual(calls.captureCount, 1, "UNKNOWN must retain its original target")
        XCTAssertEqual(after?.activeOperationID, operationID)
        XCTAssertEqual(after?.status, .unknown)
        XCTAssertEqual(operation?.attempt, 1)
    }

    func testChangedTargetBeforeDispatchNeverAppends() async throws {
        let store = try makeStore()
        let asset = try await makeAsset(in: store)
        let adapter = CoordinatorFixtureAdapter(targetStillValid: false)
        let coordinator = makeCoordinator(store: store, adapter: adapter)

        try await coordinator.select(asset.id)
        let calls = await adapter.snapshot()
        let record = try await store.asset(id: asset.id)
        let operationID = try XCTUnwrap(record?.activeOperationID)
        let operation = try await store.operation(id: operationID)
        XCTAssertTrue(calls.appendedAssets.isEmpty)
        XCTAssertTrue(calls.reconciledAssets.isEmpty)
        XCTAssertEqual(calls.validationCount, 1)
        XCTAssertEqual(record?.status, .failed)
        XCTAssertEqual(operation?.phase, .failed)
    }

    func testSameTargetWaitingQueueAppendsABCInClickOrder() async throws {
        let store = try makeStore()
        let a = try await makeAsset(in: store)
        let b = try await makeAsset(in: store)
        let c = try await makeAsset(in: store)
        let started = expectation(description: "A append reached controlled gate")
        let adapter = CoordinatorFixtureAdapter(holdFirstAppend: true, appendStarted: started)
        let coordinator = makeCoordinator(store: store, adapter: adapter)
        let first = Task { try await coordinator.select(a.id) }

        await fulfillment(of: [started], timeout: 3)
        // A's adapter call remains suspended while subsequent clicks are queued.
        // These explicit awaits establish the click order without timing sleeps.
        try await coordinator.select(b.id)
        try await coordinator.select(c.id)
        let whileHeld = await adapter.snapshot()
        XCTAssertEqual(whileHeld.appendedAssets, [a.id])

        await adapter.releaseFirstAppend()
        try await first.value
        let calls = await adapter.snapshot()
        let records = try await store.assets(includeUsed: true)
        XCTAssertEqual(calls.appendedAssets, [a.id, b.id, c.id])
        XCTAssertEqual(calls.appendPhases, [.dispatchIntent, .dispatchIntent, .dispatchIntent])
        XCTAssertEqual(Set(calls.appendTargets).count, 1)
        XCTAssertEqual(records.filter { $0.status == .used }.count, 3)
    }

    func testSlowerFirstTargetResolutionCannotReorderClicks() async throws {
        let store = try makeStore()
        let a = try await makeAsset(in: store)
        let b = try await makeAsset(in: store)
        let started = expectation(description: "A target capture reached controlled gate")
        let adapter = CoordinatorFixtureAdapter(holdFirstCapture: true, captureStarted: started)
        let coordinator = makeCoordinator(store: store, adapter: adapter)
        let first = Task { try await coordinator.select(a.id) }

        await fulfillment(of: [started], timeout: 3)
        // B resolves first. The earlier unresolved click must reserve its place
        // before any async target resolution, so neither image can dispatch yet.
        try await coordinator.select(b.id)
        let whileHeld = await adapter.snapshot()
        XCTAssertEqual(whileHeld.captureCount, 2)
        XCTAssertTrue(whileHeld.appendedAssets.isEmpty)

        await adapter.releaseFirstCapture()
        try await first.value
        let calls = await adapter.snapshot()
        let records = try await store.assets(includeUsed: true)
        XCTAssertEqual(calls.appendedAssets, [a.id, b.id])
        XCTAssertEqual(calls.appendPhases, [.dispatchIntent, .dispatchIntent])
        XCTAssertEqual(records.filter { $0.status == .used }.count, 2)
    }

    func testAdapterReceivesCommittedDispatchIntentAndExistingPrivateFile() async throws {
        let store = try makeStore()
        let asset = try await makeAsset(in: store)
        let adapter = CoordinatorFixtureAdapter()
        let coordinator = makeCoordinator(store: store, adapter: adapter)

        try await coordinator.select(asset.id)
        let calls = await adapter.snapshot()
        let record = try await store.asset(id: asset.id)
        let operationID = try XCTUnwrap(record?.activeOperationID)
        let operation = try await store.operation(id: operationID)
        XCTAssertEqual(calls.appendPhases, [.dispatchIntent])
        XCTAssertEqual(calls.privateFileExists, [true])
        XCTAssertEqual(operation?.phase, .succeeded)
        XCTAssertEqual(record?.status, .used)
    }

    func testStartupReconcilesOnlyDispatchedOriginalOperationWithoutCapturingNewTarget() async throws {
        let store = try makeStore()
        let a = try await makeAsset(in: store)
        let b = try await makeAsset(in: store)
        let adapter = CoordinatorFixtureAdapter()
        let original = try await adapter.captureTarget()
        let dispatched = try await store.prepare(assetID: a.id, target: original)
        try await store.markDispatchIntent(dispatched.id)
        let prepared = try await store.prepare(assetID: b.id, target: original)
        let before = await adapter.snapshot()
        let coordinator = makeCoordinator(store: store, adapter: adapter)

        try await coordinator.recover()

        let calls = await adapter.snapshot()
        let recovered = try await store.operation(id: dispatched.id)
        let cancelled = try await store.operation(id: prepared.id)
        let saved = try await store.receipt(for: dispatched.id)
        XCTAssertEqual(calls.captureCount, before.captureCount)
        XCTAssertTrue(calls.appendedAssets.isEmpty)
        XCTAssertEqual(calls.reconciledAssets, [a.id])
        XCTAssertEqual(recovered?.phase, .unknown)
        XCTAssertEqual(cancelled?.phase, .failed)
        XCTAssertEqual(saved?.target, original)
        XCTAssertEqual(saved?.operationID, dispatched.id)
    }

    func testRecoveryDoesNotFallbackToDifferentAdapter() async throws {
        let store = try makeStore()
        let asset = try await makeAsset(in: store)
        let oldTarget = TargetLease(adapterID: "old-adapter", surface: .webChat,
            applicationID: "original.browser", sessionID: "old-session", windowID: "old-window",
            tabID: "old-tab", documentID: "old-document", composerID: "old-composer", draftGeneration: "1")
        let op = try await store.prepare(assetID: asset.id, target: oldTarget)
        try await store.markDispatchIntent(op.id)
        let adapter = CoordinatorFixtureAdapter()
        let coordinator = makeCoordinator(store: store, adapter: adapter)

        try await coordinator.recover()

        let calls = await adapter.snapshot()
        let record = try await store.asset(id: asset.id)
        let unresolved = try await store.unresolvedOperations()
        XCTAssertEqual(calls.captureCount, 0)
        XCTAssertTrue(calls.appendedAssets.isEmpty)
        XCTAssertTrue(calls.reconciledAssets.isEmpty)
        XCTAssertEqual(record?.status, .unknown)
        XCTAssertEqual(unresolved.map(\.target), [oldTarget])
    }
}

private struct CoordinatorFixtureSnapshot: Sendable {
    let captureCount: Int
    let validationCount: Int
    let appendedAssets: [UUID]
    let reconciledAssets: [UUID]
    let appendPhases: [OperationPhase]
    let appendTargets: [TargetLease]
    let privateFileExists: [Bool]
}

private actor CoordinatorFixtureAdapter: AttachmentAdapter {
    nonisolated let id = "coordinator-fixture"
    private let targetStillValid: Bool
    private let appendThrows: Bool
    private let holdFirstAppend: Bool
    private let appendStarted: XCTestExpectation?
    private let holdFirstCapture: Bool
    private let captureStarted: XCTestExpectation?
    private var appendGate: CheckedContinuation<Void, Never>?
    private var appendReleased = false
    private var captureGate: CheckedContinuation<Void, Never>?
    private var captureReleased = false
    private var captureCount = 0
    private var validationCount = 0
    private var appendedAssets: [UUID] = []
    private var reconciledAssets: [UUID] = []
    private var appendPhases: [OperationPhase] = []
    private var appendTargets: [TargetLease] = []
    private var privateFileExists: [Bool] = []

    init(targetStillValid: Bool = true, appendThrows: Bool = false,
         holdFirstAppend: Bool = false, appendStarted: XCTestExpectation? = nil,
         holdFirstCapture: Bool = false, captureStarted: XCTestExpectation? = nil) {
        self.targetStillValid = targetStillValid
        self.appendThrows = appendThrows
        self.holdFirstAppend = holdFirstAppend
        self.appendStarted = appendStarted
        self.holdFirstCapture = holdFirstCapture
        self.captureStarted = captureStarted
    }

    func captureTarget() async throws -> TargetLease {
        captureCount += 1
        if captureCount == 1 {
            captureStarted?.fulfill()
            if holdFirstCapture && !captureReleased {
                await withCheckedContinuation { captureGate = $0 }
            }
        }
        return TargetLease(adapterID: id, surface: .webChat,
            applicationID: "synthetic.fixture.browser", sessionID: "fixture-session",
            windowID: "fixture-window", tabID: "fixture-tab", documentID: "fixture-document",
            composerID: "fixture-composer", draftGeneration: "fixture-draft-1")
    }

    func validate(_ target: TargetLease) async throws -> Bool {
        validationCount += 1
        return targetStillValid
    }

    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        appendedAssets.append(request.asset.id)
        appendPhases.append(request.operation.phase)
        appendTargets.append(request.operation.target)
        privateFileExists.append(FileManager.default.fileExists(atPath: request.fileURL.path))
        if appendedAssets.count == 1 {
            appendStarted?.fulfill()
            if holdFirstAppend && !appendReleased {
                await withCheckedContinuation { appendGate = $0 }
            }
        }
        if appendThrows { throw RiftletError.adapterUnavailable("Synthetic transport interruption") }
        return receipt(request, outcome: .verifiedReady)
    }

    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        reconciledAssets.append(request.asset.id)
        return receipt(request, outcome: .unknown)
    }

    func releaseFirstAppend() {
        appendReleased = true
        appendGate?.resume()
        appendGate = nil
    }

    func releaseFirstCapture() {
        captureReleased = true
        captureGate?.resume()
        captureGate = nil
    }

    func snapshot() -> CoordinatorFixtureSnapshot {
        CoordinatorFixtureSnapshot(captureCount: captureCount, validationCount: validationCount,
            appendedAssets: appendedAssets, reconciledAssets: reconciledAssets,
            appendPhases: appendPhases, appendTargets: appendTargets,
            privateFileExists: privateFileExists)
    }

    private func receipt(_ request: TransferRequest, outcome: ReceiptOutcome) -> TransferReceipt {
        TransferReceipt(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
            target: request.operation.target, outcome: outcome,
            profileID: "coordinator-fixture-ready-v1",
            attachmentID: "fixture-\(request.operation.id)",
            positiveReady: outcome == .verifiedReady, belongsToOriginalDraft: true,
            reason: "Synthetic coordinator test; no external input")
    }
}
