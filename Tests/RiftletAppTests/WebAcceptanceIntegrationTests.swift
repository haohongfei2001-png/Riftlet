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
    private let policy = WebAcceptanceConfiguration.receiptPolicy
    private let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
        applicationID: "com.google.Chrome", sessionID: "fixture-session", windowID: "1", tabID: "1",
        documentID: "fixture-document", composerID: "fixture-composer", draftGeneration: "original")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-web-composition-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture(initial: AttachmentObservedState = .uploadStarted) async throws
        -> (QueueStore, ImportedAsset, IntegratedWebBridge, TransferCoordinator) {
        // Transport bytes, deliberately not a claim of a real page/image observation.
        let bytes = Data("isolated generated transport fixture".utf8)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "fixture.png",
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: root.appendingPathComponent(asset.fileName))
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        _ = try await store.importAsset(asset)
        let bridge = IntegratedWebBridge(target: target, state: initial)
        return (store, asset, bridge, coordinator(store, bridge))
    }

    private func coordinator(_ store: QueueStore, _ bridge: IntegratedWebBridge) -> TransferCoordinator {
        let adapter = WebAttachmentAdapter(mediaDirectory: root, executor: bridge,
            program: WebPageProgram(sourceID: "synthetic-component-fixture", functionSource: "function(){return null;}"),
            mode: .syntheticDevelopment, profile: ChatGPTWebPageProgram.acceptanceProfile, polling: .disabled)
        return TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root, policy: policy)
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

    func testInputStartUnknownRestartAndReadyPreserveOneOperation() async throws {
        let (store, asset, bridge, transfer) = try await fixture(initial: .inputTriggered)
        try await transfer.select(asset.id, frozenTarget: target)
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
        let revision = started?.visibilityRevision

        await bridge.setObservation(.unknown)
        let reopened = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let recovered = coordinator(reopened, bridge)
        try await recovered.recover()
        let unknown = try await reopened.asset(id: asset.id)
        let recoveredAudit = try await reopened.uploadStartReceipt(for: operationID)
        XCTAssertEqual(unknown?.status, .unknown); XCTAssertEqual(unknown?.visibility, .swallowed)
        XCTAssertEqual(recoveredAudit, audit)
        // An existing unresolved selection only observes its original operation.
        try await recovered.select(asset.id, frozenTarget: nil)
        await bridge.setObservation(.attached)
        try await recovered.observePending()
        let final = try await reopened.asset(id: asset.id)
        let operation = try await reopened.operation(id: operationID)
        let finalAudit = try await reopened.uploadStartReceipt(for: operationID)
        XCTAssertEqual(final?.status, .used); XCTAssertEqual(operation?.phase, .succeeded)
        XCTAssertEqual(final?.visibility, .swallowed); XCTAssertEqual(final?.visibilityRevision, revision)
        XCTAssertEqual(finalAudit, audit)
        let commands = await bridge.recordedCommands()
        XCTAssertEqual(commands.filter { $0.action == .begin }.count, 1)
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 1)
        XCTAssertFalse(commands.contains { $0.action == .captureTarget })
        XCTAssertTrue(commands.compactMap(\.identity).allSatisfy { $0.operationID == operationID && $0.target == target })
        let bytes = try Data(contentsOf: root.appendingPathComponent(asset.fileName))
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), asset.sha256)
    }

    func testCorrelatedLateErrorKeepsStartHiddenAndRetainsCompensation() async throws {
        let (store, asset, bridge, transfer) = try await fixture()
        try await transfer.select(asset.id, frozenTarget: target)
        let started = try await store.asset(id: asset.id)
        let operationID = try XCTUnwrap(started?.activeOperationID)
        let audit = try await store.uploadStartReceipt(for: operationID)
        let afterStart = await bridge.recordedCommands()
        XCTAssertEqual(afterStart.map(\.action), [.validate, .begin, .chunk, .commit],
                       "Positive start returns without a query for final completion")
        await bridge.setObservation(.attached)
        try await transfer.observePending()
        await bridge.setObservation(.attached, error: true)
        _ = try await transfer.observeCompleted(operationID: operationID)
        let compensated = try await store.operation(id: operationID)
        let hidden = try await store.asset(id: asset.id)
        let compensation = try await store.compensation(for: operationID)
        XCTAssertEqual(compensated?.phase, .compensated); XCTAssertEqual(hidden?.status, .unknown)
        XCTAssertEqual(hidden?.visibility, .swallowed); XCTAssertNotNil(compensation)
        try await transfer.select(asset.id, frozenTarget: target)
        let retained = try await store.uploadStartReceipt(for: operationID)
        let commands = await bridge.recordedCommands()
        XCTAssertEqual(retained, audit); XCTAssertEqual(commands.filter { $0.action == .commit }.count, 1)
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

private actor IntegratedWebBridge: WebBridgeExecutor {
    private var target: TargetLease
    private var state: AttachmentObservedState
    private var hasError = false
    private var commands: [WebBridgeCommand] = []
    private let startID = UUID().uuidString

    init(target: TargetLease, state: AttachmentObservedState) { self.target = target; self.state = state }
    func setCurrentTarget(_ target: TargetLease) { self.target = target }
    func setObservation(_ state: AttachmentObservedState, error: Bool = false) { self.state = state; hasError = error }
    func recordedCommands() -> [WebBridgeCommand] { commands }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) throws -> Data {
        commands.append(command)
        if command.action == .validate {
            return try JSONEncoder().encode(Validation(target: command.target!, valid: command.target == target))
        }
        guard let identity = command.identity, identity.target == target else { throw WebAdapterError.invalidTarget }
        if command.action == .begin || command.action == .chunk {
            return try JSONEncoder().encode(Acknowledgement(operationID: identity.operationID,
                attempt: identity.attempt, nextChunk: command.action == .begin ? 0 : (command.chunkIndex! + 1)))
        }
        guard command.action == .commit || command.action == .observe else { throw WebAdapterError.invalidRequest }
        let start = state == .uploadStarted ? ObservedUploadStart(version: 1, signal: .correlatedProgress,
            evidenceID: startID, inputCount: 1, inputSequence: 1, startSequence: 3,
            previousProgress: 4, currentProgress: 9, inputObservedAtMS: 10, startObservedAtMS: 20) : nil
        return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 2,
            provenance: .init(source: .syntheticFixture, evidenceID: "component-test-not-real-Web"),
            observation: .init(identity: identity, state: state, attachmentID: "fixture-original-card",
                exactImageIdentity: true, belongsToOriginalDraft: true, hasError: hasError,
                isUploading: state == .uploadStarted, uploadStart: start)))
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
