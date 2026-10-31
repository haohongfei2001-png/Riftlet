import CryptoKit
import Darwin
import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class MacCoordinatedAdapterTests: XCTestCase {
    private var root: URL!
    private var scope: URL { root.appendingPathComponent("shared-coordination") }
    private let profileID = "mac-coordinated-synthetic-v1"
    private var policy: ReceiptPolicy { .init(syntheticAcceptanceProfiles: [profileID: .macChat]) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-m1-flow-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture(databaseName: String = "\(UUID()).sqlite") async throws -> (QueueStore, TransferRequest, MacTargetSession) {
        let bytes = Data([1, 2, 3, 4]) // Identity only; no codec or client claim.
        let file = root.appendingPathComponent("\(UUID()).png"); try bytes.write(to: file)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), byteCount: 4,
            pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        let launch = Date(timeIntervalSince1970: 2_000)
        let target = TargetLease(adapterID: "mac-coordinated-test", surface: .macChat, applicationID: "fixture.mac",
            sessionID: MacTargetSession.sessionID(processID: 23, launchedAt: launch), windowID: "window",
            documentID: "document", composerID: "composer", draftGeneration: "1")
        let session = try MacTargetSession(processID: 23, launchedAt: launch, target: target)
        let store = try QueueStore(databaseURL: root.appendingPathComponent(databaseName))
        _ = try await store.importAsset(asset)
        let operation = try await store.prepare(assetID: asset.id, target: target)
        try await store.markDispatchIntent(operation.id)
        let saved = try await store.operation(id: operation.id)
        return (store, TransferRequest(operation: try XCTUnwrap(saved), asset: asset, fileURL: file), session)
    }

    private func adapter(_ executor: CoordinatedFixtureExecutor, _ board: CoordinatedFixtureBoard,
                         coordinator: MacClipboardCoordinator?) -> MacAttachmentAdapter {
        MacAttachmentAdapter(applicationID: "fixture.mac", executor: executor, clipboard: board,
            profile: .init(adapterID: "mac-coordinated-test", surface: .macChat, profileID: profileID,
                           completionSignal: .attached), policy: policy, mode: .syntheticDevelopment,
            coordinator: coordinator)
    }

    func testNativeCompositionMustShareExactCoordinatorBeforeAnyClipboardRead() async throws {
        let (_, request, session) = try await fixture()
        let one = try MacClipboardCoordinator(directoryURL: scope)
        let two = try MacClipboardCoordinator(directoryURL: scope)
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: one)
        let board = try CoordinatedFixtureBoard()
        for coordinator in [nil, Optional(two)] {
            let client = adapter(executor, board, coordinator: coordinator)
            do { _ = try await client.append(request); XCTFail("Mismatched native coordination") }
            catch MacAdapterError.invalidRequest {}
        }
        let captures = await board.captures
        let pastes = await executor.pastes
        XCTAssertEqual(captures, 0); XCTAssertEqual(pastes, 0)
        XCTAssertTrue(try one.canReserve())
    }

    func testResolvedBeforeCoreCommitReopensAndSettlesQueueWithoutClipboardOrPaste() async throws {
        let (store, request, session) = try await fixture()
        try await performFirstProcess(request, session: session, state: .attached)
        // Deliberately never applied the first receipt: models the adapter/Core
        // transaction crash boundary, not a real OS crash or a real client test.
        let before = try await store.operation(id: request.operation.id)
        XCTAssertEqual(before?.phase, .dispatchIntent)
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: coordinator, state: .attached)
        let board = try CoordinatedFixtureBoard()
        let client = adapter(executor, board, coordinator: coordinator)
        let receipt = try await client.reconcile(request)
        let settled = try await store.apply(receipt, policy: policy)
        XCTAssertEqual(settled.status, .used)
        let pastes = await executor.pastes, observations = await executor.observations
        let captures = await board.captures, restores = await board.restores
        XCTAssertEqual(pastes, 0); XCTAssertEqual(observations, 1)
        XCTAssertEqual(captures, 0); XCTAssertEqual(restores, 0)
        XCTAssertTrue(try coordinator.canReserve())
        do { _ = try await client.append(request); XCTFail("Resolved operation replay") }
        catch MacClipboardCoordinationError.duplicateOperation {}
    }

    func testUnknownRestartObservesOriginalAndDoesNotReconstructOldClipboard() async throws {
        let (store, request, session) = try await fixture()
        try await performFirstProcess(request, session: session, state: .unknown)
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        let board = try CoordinatedFixtureBoard(text: "COPY AFTER RESTART")
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: coordinator, state: .attached)
        let client = adapter(executor, board, coordinator: coordinator)
        let receipt = try await client.reconcile(request)
        let settled = try await store.apply(receipt, policy: policy)
        XCTAssertEqual(settled.status, .used)
        let text = await board.text(), pastes = await executor.pastes, restores = await board.restores
        XCTAssertEqual(text, "COPY AFTER RESTART"); XCTAssertEqual(pastes, 0); XCTAssertEqual(restores, 0)
    }

    func testClipboardMutationErrorPersistsUnknownAndCannotBorrowRemoteProof() async throws {
        let (store, request, session) = try await fixture()
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        let board = try CoordinatedFixtureBoard(throwAfterWrite: true)
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: coordinator, state: .attached)
        let client = adapter(executor, board, coordinator: coordinator)
        do { _ = try await client.append(request); XCTFail("Uncertain native write ignored") }
        catch NativePasteboardError.writeUncertain {}
        XCTAssertFalse(try coordinator.canReserve())
        let receipt = try await client.reconcile(request)
        XCTAssertEqual(receipt.outcome, .unknown)
        let saved = try await store.apply(receipt, policy: policy)
        XCTAssertEqual(saved.status, .unknown)
        let pastes = await executor.pastes, observations = await executor.observations, restores = await board.restores
        XCTAssertEqual(pastes, 0); XCTAssertEqual(observations, 0); XCTAssertEqual(restores, 0)
        let journal = try String(contentsOf: scope.appendingPathComponent("journal.json"), encoding: .utf8)
        XCTAssertFalse(journal.contains("ORIGINAL-COPY-DO-NOT-PERSIST"))
        XCTAssertFalse(journal.contains(root.path))
    }

    func testCopyBeforeWriteCancelsReservationAndDoesNotLockUnrelatedWork() async throws {
        let (_, request, session) = try await fixture()
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        let board = try CoordinatedFixtureBoard(copyBeforeWrite: true)
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: coordinator)
        let client = adapter(executor, board, coordinator: coordinator)
        do { _ = try await client.append(request); XCTFail("Later user copy overwritten") }
        catch MacAdapterError.clipboardChanged {}
        let text = await board.text(), pastes = await executor.pastes
        XCTAssertEqual(text, "LATER USER COPY"); XCTAssertEqual(pastes, 0)
        XCTAssertTrue(try coordinator.canReserve())
        XCTAssertThrowsError(try coordinator.reserve(request))
    }

    func testResolutionIOFailureReturnsUnknownUntilOriginalProofCanBeReobserved() async throws {
        let (store, request, session) = try await fixture()
        let uncertain = try await performResolutionFault(request, session: session)
        XCTAssertEqual(uncertain.outcome, .unknown)
        XCTAssertFalse(uncertain.positiveReady); XCTAssertFalse(uncertain.safeToRetry)
        let retained = try await store.apply(uncertain, policy: policy)
        XCTAssertEqual(retained.status, .unknown)
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: coordinator, state: .attached)
        let board = try CoordinatedFixtureBoard(text: "NEW USER COPY")
        let receipt = try await adapter(executor, board, coordinator: coordinator).reconcile(request)
        let settled = try await store.apply(receipt, policy: policy)
        XCTAssertEqual(settled.status, .used)
        let pastes = await executor.pastes, restores = await board.restores
        XCTAssertEqual(pastes, 0); XCTAssertEqual(restores, 0)
    }

    func testCompletedMacObservationCompensatesAndRecoversWithoutReacquiringClipboard() async throws {
        let databaseName = "completed-watch.sqlite"
        let (store, request, session) = try await fixture(databaseName: databaseName)
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: coordinator, state: .attached)
        let board = try CoordinatedFixtureBoard()
        let client = adapter(executor, board, coordinator: coordinator)
        let receipt = try await client.append(request)
        let used = try await store.apply(receipt, policy: policy)
        XCTAssertEqual(used.status, .used)
        XCTAssertTrue(try coordinator.canReserve())
        let journalBefore = try Data(contentsOf: scope.appendingPathComponent("journal.json"))
        try await board.copy("USER COPY AFTER SUCCESS")
        let transfer = TransferCoordinator(store: store, adapter: client, mediaDirectory: root, policy: policy)

        await executor.setState(.unknown)
        let watchContinues = try await transfer.observeCompleted(operationID: request.operation.id)
        XCTAssertTrue(watchContinues)
        XCTAssertTrue(try coordinator.canReserve(), "UNKNOWN observation must not reclaim input ownership")
        await executor.setState(.failed)
        let watchAfterError = try await transfer.observeCompleted(operationID: request.operation.id)
        XCTAssertFalse(watchAfterError)
        let compensated = try await store.operation(id: request.operation.id)
        let restored = try await store.asset(id: request.asset.id)
        let audit = try await store.compensation(for: request.operation.id)
        XCTAssertEqual(compensated?.phase, .compensated)
        XCTAssertEqual(restored?.status, .unknown)
        XCTAssertEqual(audit?.originalSuccess, receipt)
        XCTAssertEqual(audit?.failure.attachmentID, receipt.attachmentID)
        let pastes = await executor.pastes, captures = await board.captures, restores = await board.restores
        let copiedText = await board.text()
        XCTAssertEqual(pastes, 1); XCTAssertEqual(captures, 1); XCTAssertEqual(restores, 1)
        XCTAssertEqual(copiedText, "USER COPY AFTER SUCCESS")
        XCTAssertTrue(try coordinator.canReserve())

        // New SQLite connection/coordinator/adapter have no previous clipboard
        // snapshot. A stale success must not reswallow or rewrite the tombstone.
        let reopenedStore = try QueueStore(databaseURL: root.appendingPathComponent(databaseName))
        let reopenedCoordinator = try MacClipboardCoordinator(directoryURL: scope)
        let reopenedExecutor = CoordinatedFixtureExecutor(session: session, coordinator: reopenedCoordinator, state: .attached)
        let reopenedBoard = try CoordinatedFixtureBoard(text: "COPY AFTER REOPEN")
        let reopened = adapter(reopenedExecutor, reopenedBoard, coordinator: reopenedCoordinator)
        let recovery = TransferCoordinator(store: reopenedStore, adapter: reopened, mediaDirectory: root, policy: policy)
        try await recovery.recover()
        let final = try await reopenedStore.operation(id: request.operation.id)
        let retained = try await reopenedStore.asset(id: request.asset.id)
        let preservedAudit = try await reopenedStore.compensation(for: request.operation.id)
        XCTAssertEqual(final?.phase, .compensated); XCTAssertEqual(final?.attempt, 1)
        XCTAssertEqual(retained?.status, .unknown); XCTAssertEqual(preservedAudit, audit)
        let replayed = await reopenedExecutor.pastes, observations = await reopenedExecutor.observations
        let reopenedCaptures = await reopenedBoard.captures, reopenedRestores = await reopenedBoard.restores
        XCTAssertEqual(replayed, 0); XCTAssertEqual(observations, 1)
        XCTAssertEqual(reopenedCaptures, 0); XCTAssertEqual(reopenedRestores, 0)
        XCTAssertTrue(try reopenedCoordinator.canReserve())
        XCTAssertEqual(try Data(contentsOf: scope.appendingPathComponent("journal.json")), journalBefore)
    }

    private func performResolutionFault(_ request: TransferRequest, session: MacTargetSession) async throws -> TransferReceipt {
        let probe = ResolutionWriteFault()
        let coordinator = try MacClipboardCoordinator(directoryURL: scope, maximumEntries: 256,
            fault: { try probe.check($0) })
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: coordinator, state: .attached)
        let board = try CoordinatedFixtureBoard()
        let receipt = try await adapter(executor, board, coordinator: coordinator).append(request)
        let pastes = await executor.pastes, restores = await board.restores
        XCTAssertEqual(pastes, 1); XCTAssertEqual(restores, 0)
        return receipt
    }

    /// Separate lexical lifetime drops adapter, executor and lock; no old
    /// ClipboardOwnershipLease/snapshot is available to the reopened process.
    private func performFirstProcess(_ request: TransferRequest, session: MacTargetSession,
                                     state: AttachmentObservedState) async throws {
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        let executor = CoordinatedFixtureExecutor(session: session, coordinator: coordinator, state: state)
        let board = try CoordinatedFixtureBoard()
        let client = adapter(executor, board, coordinator: coordinator)
        _ = try await client.append(request)
        let pastes = await executor.pastes
        XCTAssertEqual(pastes, 1)
    }
}

private final class ResolutionWriteFault: @unchecked Sendable {
    private let lock = NSLock()
    private var renames = 0
    func check(_ point: MacClipboardCoordinator.Checkpoint) throws {
        lock.lock(); defer { lock.unlock() }
        if case .journalRenamed = point {
            renames += 1
            // reserve, write intent, owner, input intent, then resolution.
            if renames == 5 { throw MacClipboardCoordinationError.storageFailure(EIO) }
        }
    }
}

private actor CoordinatedFixtureExecutor: CoordinatedMacAttachmentExecutor {
    nonisolated let clipboardCoordinator: MacClipboardCoordinator
    let session: MacTargetSession
    private var state: AttachmentObservedState
    private(set) var pastes = 0
    private(set) var observations = 0
    init(session: MacTargetSession, coordinator: MacClipboardCoordinator, state: AttachmentObservedState = .unknown) {
        self.session = session; clipboardCoordinator = coordinator; self.state = state
    }
    func captureTarget() async throws -> MacTargetSession { session }
    func setState(_ state: AttachmentObservedState) { self.state = state }
    func inspectTarget(_ original: TargetLease) async throws -> MacTargetSession? { original == session.target ? session : nil }
    func paste(_ request: TransferRequest, owner: ClipboardOwnerState) async throws -> Data {
        try clipboardCoordinator.markInputIntent(for: request, owner: owner)
        pastes += 1; return try envelope(request)
    }
    func observe(_ request: TransferRequest) async throws -> Data { observations += 1; return try envelope(request) }
    private func envelope(_ request: TransferRequest) throws -> Data {
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        return try JSONEncoder().encode(AttachmentObservationEnvelope(
            provenance: .init(source: .syntheticFixture, evidenceID: "M1-recovery-orchestration-only"),
            observation: .init(identity: identity, state: state,
                attachmentID: state == .attached || state == .failed ? "synthetic-attachment" : nil,
                exactImageIdentity: state == .attached || state == .failed,
                belongsToOriginalDraft: true, hasError: state == .failed)))
    }
}

private actor CoordinatedFixtureBoard: ClipboardTransactionDriver {
    private var snapshot: ClipboardSnapshot
    private var count = 0
    private let throwAfterWrite: Bool
    private let copyBeforeWrite: Bool
    private(set) var captures = 0
    private(set) var restores = 0
    init(text: String = "ORIGINAL-COPY-DO-NOT-PERSIST", throwAfterWrite: Bool = false, copyBeforeWrite: Bool = false) throws {
        snapshot = try ClipboardSnapshot(items: [["public.utf8-plain-text": Data(text.utf8)]])
        self.throwAfterWrite = throwAfterWrite; self.copyBeforeWrite = copyBeforeWrite
    }
    func text() -> String? { snapshot.items.first?["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) } }
    func copy(_ text: String) throws {
        snapshot = try ClipboardSnapshot(items: [["public.utf8-plain-text": Data(text.utf8)]]); count += 1
    }
    func capture() async throws -> ClipboardCapturedState { captures += 1; return .init(changeCount: count, snapshot: snapshot) }
    func writeIfUnchanged(_ payload: ClipboardAttachmentPayload, expectedChangeCount: Int) async throws -> ClipboardOwnerState? {
        if copyBeforeWrite { snapshot = try ClipboardSnapshot(items: [["public.utf8-plain-text": Data("LATER USER COPY".utf8)]]); count += 1 }
        guard count == expectedChangeCount else { return nil }
        snapshot = try ClipboardSnapshot(items: [payload.item]); count += 1
        if throwAfterWrite { throw NativePasteboardError.writeUncertain }
        return currentOwner()
    }
    func owner() async throws -> ClipboardOwnerState { currentOwner() }
    private func currentOwner() -> ClipboardOwnerState {
        .init(changeCount: count, marker: snapshot.items.first?[ClipboardAttachmentPayload.markerType].flatMap { String(data: $0, encoding: .utf8) })
    }
    func restoreIfOwned(_ snapshot: ClipboardSnapshot, expectedOwner: ClipboardOwnerState) async throws -> Bool {
        guard currentOwner() == expectedOwner else { return false }
        self.snapshot = snapshot; count += 1; restores += 1; return true
    }
}
