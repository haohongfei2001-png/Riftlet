import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters
@testable import RiftletApp

/// Component integration with an injected bridge and permission driver only.
/// No Chrome, TCC, real screenshot, rendered pixel or network evidence is created.
final class WebAcceptanceIntegrationTests: XCTestCase {
    private var root: URL!
    private var settlement: IntegrationReceiptSettlement!
    private let policy = WebAcceptanceConfiguration.receiptPolicy
    private let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
        applicationID: "com.google.Chrome", sessionID: "fixture-session", windowID: "1", tabID: "1",
        documentID: "fixture-document", composerID: "fixture-composer", draftGeneration: "original")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-web-composition-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        settlement = IntegrationReceiptSettlement()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture(initial: AttachmentObservedState = .uploadStarted) async throws
        -> (QueueStore, ImportedAsset, IntegratedWebBridge, TransferCoordinator) {
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let asset = try await image(in: store)
        let bridge = IntegratedWebBridge(target: target, state: initial)
        return (store, asset, bridge, coordinator(store, bridge))
    }

    private func image(in store: QueueStore) async throws -> ImportedAsset {
        // Transport bytes, deliberately not a claim of a real page/image observation.
        let id = UUID(), bytes = Data("isolated generated transport fixture \(UUID())".utf8)
        let asset = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: root.appendingPathComponent(asset.fileName))
        _ = try await store.importAsset(asset)
        return asset
    }

    private func coordinator(_ store: QueueStore, _ bridge: IntegratedWebBridge) -> TransferCoordinator {
        let adapter = WebAttachmentAdapter(mediaDirectory: root, executor: bridge,
            program: WebPageProgram(sourceID: "synthetic-component-fixture", functionSource: "function(){return null;}"),
            mode: .syntheticDevelopment, profile: ChatGPTWebPageProgram.acceptanceProfile, polling: .disabled)
        let settlement = self.settlement!
        return TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root, policy: policy,
            onChange: { await settlement.recordSettledReceipts(in: store) })
    }

    private func start(_ asset: ImportedAsset, profile: String? = nil) -> TransferReceipt {
        TransferReceipt(operationID: UUID(), assetID: asset.id, attempt: 1, assetSHA256: asset.sha256,
            target: target, outcome: .uploadStarted, profileID: ChatGPTWebPageProgram.acceptanceProfile.profileID,
            attachmentID: "fixture-original-card", belongsToOriginalDraft: true, isUploading: true,
            uploadStartEvidence: UploadStartEvidence(
                profileID: profile ?? ChatGPTWebPageProgram.acceptanceUploadStartProfileID,
                signal: .correlatedProgress, evidenceID: UUID().uuidString, inputCount: 1))
    }

    func testConfiguredPolicyIsSyntheticOnlyAndNeverAdmitsRetry() {
        XCTAssertTrue(policy.admittedProfiles.isEmpty); XCTAssertTrue(policy.uploadStartProfiles.isEmpty)
        XCTAssertTrue(policy.retrySafeProfiles.isEmpty); XCTAssertTrue(policy.syntheticRetrySafeProfiles.isEmpty)
        XCTAssertEqual(policy.syntheticUploadStartProfiles,
                       [ChatGPTWebPageProgram.acceptanceUploadStartProfileID: .webChat])
        for origin in [AssetOrigin.synthetic, .systemScreenshot] {
            let image = ImportedAsset(sourceKey: origin.rawValue, fileName: "policy.png",
                sha256: String(repeating: "a", count: 64), byteCount: 1,
                pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: origin)
            let receipt = start(image)
            XCTAssertEqual(policy.allowsUploadStart(receipt: receipt, asset: image, mode: .production), origin == .synthetic)
            XCTAssertFalse(ReceiptPolicy().allowsUploadStart(receipt: receipt, asset: image, mode: .production))
            XCTAssertFalse(policy.allowsUploadStart(receipt: start(image, profile: "unreviewed-start"), asset: image, mode: .production))
            let failure = TransferReceipt(operationID: receipt.operationID, assetID: image.id, attempt: 1,
                assetSHA256: image.sha256, target: target, outcome: .definitiveFailure,
                profileID: receipt.profileID, attachmentID: receipt.attachmentID,
                belongsToOriginalDraft: true, hasError: true, safeToRetry: true)
            XCTAssertFalse(policy.allowsRetry(receipt: failure, asset: image, mode: .production))
        }
    }

    func testInputStartStaysUnchangedAcrossRestartAndNewIndependentInput() async throws {
        let (store, asset, bridge, transfer) = try await fixture(initial: .inputTriggered)
        try await transfer.select(asset.id, frozenTarget: target)
        try await settlement.waitForReceipt(assetID: asset.id)
        let first = try await store.asset(id: asset.id)
        let operationID = try XCTUnwrap(first?.activeOperationID)
        let noStart = try await store.uploadStartReceipt(for: operationID)
        XCTAssertEqual(first?.visibility, .visible); XCTAssertNil(noStart)

        await bridge.setObservation(.uploadStarted)
        try await transfer.observePending()
        let started = try await store.asset(id: asset.id)
        let audit = try await store.uploadStartReceipt(for: operationID)
        XCTAssertEqual(started?.visibility, .swallowed); XCTAssertNotEqual(started?.status, .used)
        XCTAssertEqual(audit?.outcome, .uploadStarted); XCTAssertEqual(audit?.target, target)
        XCTAssertEqual(audit?.uploadStartEvidence?.signal, .attachmentAccepted)
        let firstOperation = try await store.operation(id: operationID)
        let firstReceipt = try await store.receipt(for: operationID)
        let afterStart = await bridge.recordedCommands()

        await bridge.setObservation(.unknown)
        let reopened = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let recovered = coordinator(reopened, bridge)
        try await recovered.recover()
        try await recovered.recoverOriginalObservations(operationIDs: [operationID])
        try await recovered.observePending()
        let afterRestart = try await reopened.asset(id: asset.id)
        let recoveredAudit = try await reopened.uploadStartReceipt(for: operationID)
        XCTAssertEqual(afterRestart, started)
        XCTAssertEqual(recoveredAudit, audit)
        // Old operations are history; selecting them never replays or resumes
        // their upload lifecycle after a restart.
        try await recovered.select(asset.id, frozenTarget: nil)
        await bridge.setObservation(.attached)
        try await recovered.observePending()
        let completed = try await recovered.observeCompleted(operationID: operationID)
        let final = try await reopened.asset(id: asset.id)
        let operation = try await reopened.operation(id: operationID)
        let finalAudit = try await reopened.uploadStartReceipt(for: operationID)
        let finalReceipt = try await reopened.receipt(for: operationID)
        XCTAssertFalse(completed)
        XCTAssertEqual(final, started); XCTAssertEqual(operation, firstOperation)
        XCTAssertEqual(finalReceipt, firstReceipt)
        XCTAssertEqual(finalAudit, audit)
        let afterRecovery = await bridge.recordedCommands()
        XCTAssertEqual(afterRecovery.count, afterStart.count, "Recovery must not ask the page about historical uploads")

        let second = try await image(in: reopened)
        await bridge.setObservation(.uploadStarted)
        try await recovered.select(second.id, frozenTarget: target)
        try await settlement.waitForReceipt(assetID: second.id)
        let secondRecord = try await reopened.asset(id: second.id)
        let secondID = try XCTUnwrap(secondRecord?.activeOperationID)
        let secondStart = try await reopened.uploadStartReceipt(for: secondID)
        let preservedFirst = try await reopened.asset(id: asset.id)
        let preservedOperation = try await reopened.operation(id: operationID)
        XCTAssertNotEqual(secondID, operationID)
        XCTAssertEqual(secondRecord?.visibility, .swallowed)
        XCTAssertEqual(secondStart?.assetID, second.id)
        XCTAssertEqual(secondStart?.uploadStartEvidence?.signal, .attachmentAccepted)
        XCTAssertEqual(preservedFirst, started); XCTAssertEqual(preservedOperation, firstOperation)
        let commands = await bridge.recordedCommands()
        XCTAssertEqual(commands.filter { $0.action == .begin }.compactMap { $0.identity?.assetID }, [asset.id, second.id])
        XCTAssertEqual(commands.filter { $0.action == .commit }.compactMap { $0.identity?.assetID }, [asset.id, second.id])
        XCTAssertFalse(commands.contains { $0.action == .captureTarget })
        XCTAssertTrue(commands.compactMap(\.identity).allSatisfy { [operationID, secondID].contains($0.operationID) && $0.target == target })
        let bytes = try Data(contentsOf: root.appendingPathComponent(asset.fileName))
        let secondBytes = try Data(contentsOf: root.appendingPathComponent(second.fileName))
        let transferred = await bridge.transferredBytes()
        XCTAssertEqual(transferred, [operationID: bytes, secondID: secondBytes])
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), asset.sha256)
        XCTAssertEqual(SHA256.hash(data: secondBytes).map { String(format: "%02x", $0) }.joined(), second.sha256)
    }

    func testCompletionAndLatePageErrorDoNotResumeAnAcceptedUploadLifecycle() async throws {
        let (store, asset, bridge, transfer) = try await fixture()
        try await transfer.select(asset.id, frozenTarget: target)
        try await settlement.waitForReceipt(assetID: asset.id)
        let started = try await store.asset(id: asset.id)
        let operationID = try XCTUnwrap(started?.activeOperationID)
        let audit = try await store.uploadStartReceipt(for: operationID)
        let firstOperation = try await store.operation(id: operationID)
        let firstReceipt = try await store.receipt(for: operationID)
        let afterStart = await bridge.recordedCommands()
        XCTAssertEqual(afterStart.map(\.action), [.validate, .begin, .chunk, .commit],
                       "Positive start returns without a query for final completion")
        await bridge.setObservation(.attached)
        try await transfer.observePending()
        await bridge.setObservation(.attached, error: true)
        let observedCompletion = try await transfer.observeCompleted(operationID: operationID)
        let retainedOperation = try await store.operation(id: operationID)
        let hidden = try await store.asset(id: asset.id)
        let compensation = try await store.compensation(for: operationID)
        let retainedReceipt = try await store.receipt(for: operationID)
        XCTAssertFalse(observedCompletion)
        XCTAssertEqual(retainedOperation, firstOperation); XCTAssertEqual(hidden, started)
        XCTAssertEqual(retainedReceipt, firstReceipt); XCTAssertNil(compensation)
        try await transfer.select(asset.id, frozenTarget: target)
        let retained = try await store.uploadStartReceipt(for: operationID)
        let commands = await bridge.recordedCommands()
        XCTAssertEqual(retained, audit); XCTAssertEqual(commands.map(\.action), afterStart.map(\.action))
    }

    func testPermissionAwaitKeepsOriginalTargetAndRejectsChangedDraft() async throws {
        let (store, asset, bridge, transfer) = try await fixture()
        let permission = DelayedIntegrationPermission()
        let gate = AutomationPermissionGate(requiresChrome: true, checker: permission)
        let frozen = target
        let selection = Task {
            let state = await gate.inspect()
            guard state == .granted else { return }
            try await transfer.select(asset.id, frozenTarget: frozen)
        }
        defer { selection.cancel() }
        try await permission.waitForCheck()
        let waiting = try await store.asset(id: asset.id)
        XCTAssertNil(waiting?.activeOperationID); XCTAssertEqual(waiting?.visibility, .visible)
        let changed = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: target.sessionID, windowID: "1", tabID: "2",
            documentID: "later-document", composerID: "later-composer", draftGeneration: "later")
        await bridge.setCurrentTarget(changed)
        await permission.finish(.granted)
        try await selection.value
        let commands = await bridge.recordedCommands()
        XCTAssertEqual(commands.map(\.action), [.validate])
        XCTAssertEqual(commands.first?.target, frozen, "A late permission grant must not choose the new draft")
        let retained = try await store.asset(id: asset.id)
        XCTAssertEqual(retained?.visibility, .visible)
        let requests = await permission.requests()
        XCTAssertEqual(requests, [false])
    }

    func testDeniedPermissionAndMissingFrozenTargetNeverAppend() async throws {
        let (store, asset, bridge, transfer) = try await fixture()
        let permission = ImmediateIntegrationPermission(state: .denied)
        let state = await AutomationPermissionGate(requiresChrome: true, checker: permission).inspect()
        if state == .granted { try await transfer.select(asset.id, frozenTarget: target) }
        let untouched = try await store.asset(id: asset.id)
        XCTAssertNil(untouched?.activeOperationID)
        do {
            try await transfer.select(asset.id, frozenTarget: nil)
            XCTFail("Missing click-time ACK was replaced by a later capture")
        } catch RiftletError.adapterUnavailable {}
        let commands = await bridge.recordedCommands()
        XCTAssertTrue(commands.isEmpty)
        let retained = try await store.asset(id: asset.id)
        XCTAssertEqual(retained?.visibility, .visible); XCTAssertNil(retained?.activeOperationID)
    }
}

/// Waits for the coordinator's persisted-receipt callback, not select's earlier
/// execution-return boundary. This is fixture synchronization only.
private actor IntegrationReceiptSettlement {
    private var assetsWithSettledReceipts = Set<UUID>()
    func recordSettledReceipts(in store: QueueStore) async {
        for asset in (try? await store.assets(includeUsed: true)) ?? [] {
            guard let operationID = asset.activeOperationID,
                  (try? await store.receipt(for: operationID)) != nil else { continue }
            assetsWithSettledReceipts.insert(asset.id)
        }
    }
    func waitForReceipt(assetID: UUID) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !assetsWithSettledReceipts.contains(assetID) {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                XCTFail("The original input did not persist a receipt")
                throw WebAdapterError.invalidReply
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

private actor IntegratedWebBridge: WebBridgeExecutor {
    private var target: TargetLease
    private var state: AttachmentObservedState
    private var hasError = false
    private var commands: [WebBridgeCommand] = []
    private var payloads: [UUID: Data] = [:]

    init(target: TargetLease, state: AttachmentObservedState) { self.target = target; self.state = state }
    func setCurrentTarget(_ target: TargetLease) { self.target = target }
    func setObservation(_ state: AttachmentObservedState, error: Bool = false) { self.state = state; hasError = error }
    func recordedCommands() -> [WebBridgeCommand] { commands }
    func transferredBytes() -> [UUID: Data] { payloads }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) throws -> Data {
        commands.append(command)
        if command.action == .validate {
            return try JSONEncoder().encode(Validation(target: command.target!, valid: command.target == target))
        }
        guard let identity = command.identity, identity.target == target else { throw WebAdapterError.invalidTarget }
        if command.action == .begin || command.action == .chunk {
            if command.action == .begin { payloads[identity.operationID] = Data() }
            if command.action == .chunk {
                guard let encoded = command.chunkBase64, let bytes = Data(base64Encoded: encoded) else {
                    throw WebAdapterError.invalidRequest
                }
                payloads[identity.operationID, default: Data()].append(bytes)
            }
            return try JSONEncoder().encode(Acknowledgement(operationID: identity.operationID,
                attempt: identity.attempt, nextChunk: command.action == .begin ? 0 : (command.chunkIndex! + 1)))
        }
        guard command.action == .commit || command.action == .observe else { throw WebAdapterError.invalidRequest }
        let start = state == .uploadStarted ? ObservedUploadStart(version: 1, signal: .attachmentAccepted,
            evidenceID: identity.operationID.uuidString, inputCount: 1, inputSequence: 1, startSequence: 2,
            previousProgress: 0, currentProgress: 0, inputObservedAtMS: 10, startObservedAtMS: 20) : nil
        return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 2,
            provenance: .init(source: .syntheticFixture, evidenceID: "component-test-not-real-Web"),
            observation: .init(identity: identity, state: state, attachmentID: "fixture-card-\(identity.operationID.uuidString)",
                exactImageIdentity: true, belongsToOriginalDraft: true, hasError: hasError,
                isUploading: false, uploadStart: start)))
    }
    private struct Validation: Encodable { let target: TargetLease; let valid: Bool }
    private struct Acknowledgement: Encodable { let operationID: UUID; let attempt: Int; let nextChunk: Int }
}

private actor DelayedIntegrationPermission: AutomationPermissionChecking {
    private var continuation: CheckedContinuation<AutomationPermissionState, Never>?
    private var called: [Bool] = []
    func check(askUserIfNeeded: Bool) async -> AutomationPermissionState {
        called.append(askUserIfNeeded)
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitForCheck() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while continuation == nil, ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        guard continuation != nil else { throw WebAdapterError.invalidRequest }
    }
    func finish(_ result: AutomationPermissionState) { continuation?.resume(returning: result); continuation = nil }
    func requests() -> [Bool] { called }
}

private struct ImmediateIntegrationPermission: AutomationPermissionChecking {
    let state: AutomationPermissionState
    func check(askUserIfNeeded: Bool) async -> AutomationPermissionState { state }
}
