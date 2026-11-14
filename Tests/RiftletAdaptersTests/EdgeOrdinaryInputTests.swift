import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Generated PNGs, a disposable production-mode store and a controlled bridge.
/// These are input/scope regressions, never evidence of a real Edge upload.
final class EdgeOrdinaryInputTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-edge-input-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func target(application: String = "com.microsoft.edgemac") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: application,
            sessionID: "owned-edge-session", windowID: "11", tabID: "12", documentID: "owned-document",
            composerID: "owned-editor", draftGeneration: "owned-draft", clickBindingID: UUID())
    }

    private func prepare(root: URL, store: QueueStore, gray: CGFloat, origin: AssetOrigin = .systemScreenshot)
        async throws -> (TransferRequest, Data, UUID) {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: gray, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(context.makeImage()), encoded = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let bytes = encoded as Data, file = root.appendingPathComponent(UUID().uuidString + ".png")
        try bytes.write(to: file)
        let asset = ImportedAsset(sourceKey: "owned-generated-" + UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(bytes.count),
            pixelWidth: 4, pixelHeight: 4, mediaType: "image/png", origin: origin)
        _ = try await store.importAsset(asset)
        let prepared = try await store.prepare(assetID: asset.id, target: target()), owner = UUID()
        let invocation = try await store.markIndependentFileInputIntent(prepared.id, ownerID: owner)
        let saved = try await store.operation(id: prepared.id)
        return (TransferRequest(operation: try XCTUnwrap(saved), asset: asset, fileURL: file, invocationID: invocation), bytes, owner)
    }

    private func adapter(root: URL, store: QueueStore, bridge: EdgeInputBridge) throws -> WebAttachmentAdapter {
        WebAttachmentAdapter(mediaDirectory: root, executor: bridge, program: try ChatGPTWebPageProgram.load(),
            mode: .ordinaryProduct, profile: OrdinaryProductScreenshotScope.systemProfile, polling: .disabled,
            productStore: store, productOrigins: [.systemScreenshot, .applicationScreenshot],
            applicationIDs: ["com.google.Chrome", "com.microsoft.edgemac"])
    }

    private func refreshed(_ request: TransferRequest, store: QueueStore) async throws -> TransferRequest {
        let operation = try await store.operation(id: request.operation.id)
        return TransferRequest(operation: try XCTUnwrap(operation), asset: request.asset, fileURL: request.fileURL,
            invocationID: request.invocationID)
    }

    func testTwoDifferentPNGsEnterOriginalEdgeDraftOnceWithoutInventingStartOrCompletion() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite")), bridge = EdgeInputBridge()
        let client = try adapter(root: root, store: store, bridge: bridge), confirmations = EdgeInputConfirmations()
        var requests: [TransferRequest] = [], originals: [Data] = []
        for (gray, origin) in [(CGFloat(0.2), AssetOrigin.systemScreenshot), (CGFloat(0.8), AssetOrigin.applicationScreenshot)] {
            let (request, bytes, owner) = try await prepare(root: root, store: store, gray: gray, origin: origin)
            try await client.preflight(asset: request.asset, fileURL: request.fileURL)
            let receipt = try await client.append(request, onInputConfirmed: { await confirmations.record($0) })
            XCTAssertEqual(receipt.outcome, .inputTriggered)
            XCTAssertEqual(receipt.target, request.operation.target)
            XCTAssertNil(receipt.uploadStartEvidence); XCTAssertNil(receipt.completionEvidence)
            XCTAssertFalse(receipt.positiveReady); XCTAssertFalse(receipt.safeToRetry)
            try await store.recordAppendReturned(receipt, invocationID: try XCTUnwrap(request.invocationID), ownerID: owner)
            let row = try await store.apply(receipt)
            XCTAssertEqual(row.visibility, .visible)
            let start = try await store.uploadStartReceipt(for: request.operation.id)
            let operation = try await store.operation(id: request.operation.id)
            XCTAssertNil(start); XCTAssertEqual(operation?.phase, .inputTriggered)
            let scope: SystemScreenshotAdmissionScope = origin == .systemScreenshot ? .productSystem : .productApplication
            let registered = try await store.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: scope))
            XCTAssertNotNil(registered)
            requests.append(request); originals.append(bytes)
        }
        XCTAssertNotEqual(requests[0].asset.sha256, requests[1].asset.sha256)
        XCTAssertNotEqual(requests[0].operation.target.clickBindingID, requests[1].operation.target.clickBindingID)
        let recorded = await bridge.records(), confirmed = await confirmations.receipts
        XCTAssertEqual(recorded.commands.map(\.action), [.begin, .chunk, .commit, .begin, .chunk, .commit])
        XCTAssertEqual(confirmed.map(\.operationID), requests.map { $0.operation.id })
        XCTAssertTrue(confirmed.allSatisfy { $0.outcome == .inputTriggered && $0.uploadStartEvidence == nil })
        for (index, request) in requests.enumerated() {
            XCTAssertEqual(recorded.bytes[request.operation.id], originals[index])
            XCTAssertEqual(try Data(contentsOf: request.fileURL), originals[index])
            let commands = recorded.commands.filter { $0.identity?.operationID == request.operation.id }
            XCTAssertEqual(commands.map(\.action), [.begin, .chunk, .commit])
            XCTAssertTrue(commands.allSatisfy { $0.target == request.operation.target && $0.identity?.assetSHA256 == request.asset.sha256
                && $0.invocationID == request.invocationID })
            XCTAssertEqual(commands.first?.byteCount, request.asset.byteCount)
        }
    }

    func testChromeStartReadyAndFailureEvidenceCannotAuthorizeEdgeAndIsNeverRetried() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        for (index, state) in [AttachmentObservedState.uploadStarted, .attached, .ready, .failed].enumerated() {
            let bridge = EdgeInputBridge(state: state), client = try adapter(root: root, store: store, bridge: bridge)
            let (request, bytes, _) = try await prepare(root: root, store: store, gray: CGFloat(index + 1) / 6)
            do { _ = try await client.append(request); XCTFail("Chrome-calibrated observation cannot authorize Edge") }
            catch { XCTAssertEqual(error as? WebAdapterError, .invalidReply) }
            let after = await bridge.records()
            XCTAssertEqual(after.commands.map(\.action), [.begin, .chunk, .commit])
            let start = try await store.uploadStartReceipt(for: request.operation.id)
            let row = try await store.asset(id: request.asset.id)
            XCTAssertNil(start); XCTAssertEqual(row?.visibility, .visible)
            try await store.markUnknown(request.operation.id, reason: "owned unadmitted host receipt")
            do { _ = try await client.append(request); XCTFail("Uncertain input must not run again") }
            catch { XCTAssertEqual(error as? WebAdapterError, .invalidRequest) }
            await bridge.setState(.unknown)
            let receipt = try await client.reconcile(refreshed(request, store: store))
            XCTAssertEqual(receipt.outcome, .unknown)
            XCTAssertFalse(receipt.positiveReady); XCTAssertFalse(receipt.safeToRetry)
            XCTAssertNil(receipt.uploadStartEvidence); XCTAssertNil(receipt.completionEvidence)
            let final = await bridge.records()
            XCTAssertEqual(final.commands.map(\.action), [.begin, .chunk, .commit, .observe])
            XCTAssertEqual(final.bytes[request.operation.id], bytes)
            XCTAssertEqual(try Data(contentsOf: request.fileURL), bytes)
        }
    }

    func testLostCommitReplyObservesOriginalUnknownWhileDistinctNextImageCanEnter() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let bridge = EdgeInputBridge(state: .unknown, loseCommitReply: true)
        let client = try adapter(root: root, store: store, bridge: bridge)
        let (first, firstBytes, firstOwner) = try await prepare(root: root, store: store, gray: 0.3)
        let unknown = try await client.append(first)
        XCTAssertEqual(unknown.outcome, .unknown)
        XCTAssertNil(unknown.uploadStartEvidence); XCTAssertFalse(unknown.safeToRetry)
        try await store.recordAppendReturned(unknown, invocationID: try XCTUnwrap(first.invocationID), ownerID: firstOwner)
        _ = try await store.apply(unknown)
        await bridge.setState(.inputTriggered)
        let (second, secondBytes, _) = try await prepare(root: root, store: store, gray: 0.7)
        let entered = try await client.append(second)
        XCTAssertEqual(entered.outcome, .inputTriggered)
        do { _ = try await client.append(first); XCTFail("Lost reply must never repeat commit") }
        catch { XCTAssertEqual(error as? WebAdapterError, .invalidRequest) }
        await bridge.setState(.unknown)
        let observed = try await client.reconcile(refreshed(first, store: store))
        XCTAssertEqual(observed.outcome, .unknown)
        let records = await bridge.records()
        XCTAssertEqual(records.commands.filter { $0.identity?.operationID == first.operation.id }.map(\.action),
            [.begin, .chunk, .commit, .observe, .observe])
        XCTAssertEqual(records.commands.filter { $0.identity?.operationID == second.operation.id }.map(\.action),
            [.begin, .chunk, .commit])
        XCTAssertEqual(records.bytes[first.operation.id], firstBytes)
        XCTAssertEqual(records.bytes[second.operation.id], secondBytes)
        XCTAssertNotEqual(first.asset.sha256, second.asset.sha256)
        for request in [first, second] {
            let start = try await store.uploadStartReceipt(for: request.operation.id)
            XCTAssertNil(start)
        }
    }

    func testProductAllowsEdgeInputScopeWhileOriginalInternalScopeStaysChromeOnly() throws {
        let edge = target(), chrome = target(application: "com.google.Chrome")
        for scope in [SystemScreenshotAdmissionScope.productSystem, .productApplication] {
            XCTAssertNoThrow(try scope.validateTarget(edge))
            XCTAssertNoThrow(try scope.validateTarget(chrome))
        }
        XCTAssertNoThrow(try SystemScreenshotAdmissionScope.ordinaryCurrentDraftInternal.validateTarget(chrome))
        XCTAssertThrowsError(try SystemScreenshotAdmissionScope.ordinaryCurrentDraftInternal.validateTarget(edge)) {
            XCTAssertEqual($0 as? WebAdapterError, .invalidTarget)
        }
        for scope in [SystemScreenshotAdmissionScope.productSystem, .productApplication, .ordinaryCurrentDraftInternal] {
            XCTAssertThrowsError(try scope.validateTarget(target(application: "unregistered.application"))) {
                XCTAssertEqual($0 as? WebAdapterError, .invalidTarget)
            }
        }
    }
}

private actor EdgeInputConfirmations {
    private(set) var receipts: [TransferReceipt] = []
    func record(_ receipt: TransferReceipt) { receipts.append(receipt) }
}

private actor EdgeInputBridge: WebBridgeExecutor {
    private var state: AttachmentObservedState
    private var loseCommitReply: Bool
    private var commands: [WebBridgeCommand] = []
    private var bytes: [UUID: Data] = [:]
    init(state: AttachmentObservedState = .inputTriggered, loseCommitReply: Bool = false) {
        self.state = state; self.loseCommitReply = loseCommitReply
    }
    func setState(_ value: AttachmentObservedState) { state = value }
    func records() -> (commands: [WebBridgeCommand], bytes: [UUID: Data]) { (commands, bytes) }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        commands.append(command)
        let identity = try XCTUnwrap(command.identity)
        switch command.action {
        case .begin, .chunk:
            if command.action == .begin { bytes[identity.operationID] = Data() }
            if let chunk = command.chunkBase64 { bytes[identity.operationID, default: Data()].append(try XCTUnwrap(Data(base64Encoded: chunk))) }
            return try JSONSerialization.data(withJSONObject: ["operationID": identity.operationID.uuidString,
                "attempt": identity.attempt, "nextChunk": command.action == .begin ? 0 : (command.chunkIndex ?? -1) + 1])
        case .commit, .observe:
            if command.action == .commit, loseCommitReply {
                loseCommitReply = false
                throw WebAdapterError.nativeEventFailed(-1712)
            }
            let start = state == .uploadStarted ? ObservedUploadStart(version: 1, signal: .attachmentAccepted,
                evidenceID: "00000000-0000-4000-8000-000000000001", inputCount: 1, inputSequence: 1, startSequence: 2,
                previousProgress: 0, currentProgress: 0, inputObservedAtMS: 10, startObservedAtMS: 11) : nil
            return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 2,
                provenance: .init(source: .integratedDevelopment, evidenceID: "click-document-witness-20261114-v18"),
                observation: .init(identity: identity, state: state,
                    attachmentID: [.uploadStarted, .attached, .ready].contains(state) ? "owned-fixture-attachment" : nil,
                    exactImageIdentity: true, belongsToOriginalDraft: true,
                    hasError: state == .failed, attachmentAbsent: state == .failed,
                    automaticRetryExcluded: state == .failed, uploadStart: start, inputExecutionPending: false)))
        default: throw WebAdapterError.invalidRequest
        }
    }
}
