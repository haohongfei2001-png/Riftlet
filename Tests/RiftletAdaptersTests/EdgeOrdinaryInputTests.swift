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

    private func target(application: String = "com.microsoft.edgemac", route: WebDraftRoute? = .chatGPTTemporaryHome) -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: application,
            sessionID: "owned-edge-session", windowID: "11", tabID: "12", documentID: "owned-document",
            composerID: "owned-editor", draftGeneration: "owned-draft", clickBindingID: UUID(), webDraftRoute: route)
    }

    private func prepare(root: URL, store: QueueStore, gray: CGFloat, origin: AssetOrigin = .systemScreenshot,
                         route: WebDraftRoute? = .chatGPTTemporaryHome, application: String = "com.microsoft.edgemac")
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
        let prepared = try await store.prepare(assetID: asset.id, target: target(application: application, route: route)), owner = UUID()
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

    func testNewSystemPNGUsesOriginalEdgeOnlyStartWithNoOtherCapability() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let bridge = EdgeInputBridge(signal: .correlatedProgress)
        let client = try adapter(root: root, store: store, bridge: bridge)
        let (request, _, owner) = try await prepare(root: root, store: store, gray: 0.41)
        let entered = try await client.append(request)
        XCTAssertEqual(entered.outcome, .inputTriggered)
        try await store.recordAppendReturned(entered, invocationID: try XCTUnwrap(request.invocationID), ownerID: owner)
        _ = try await store.apply(entered)
        await bridge.setState(.uploadStarted)
        let receipt = try await client.reconcile(refreshed(request, store: store))
        let profile = OrdinaryProductScreenshotScope.edgeProgressProfile
        let id = try XCTUnwrap(profile.uploadStartProfileID)
        XCTAssertEqual(receipt.profileID, profile.profileID); XCTAssertEqual(receipt.uploadStartEvidence?.profileID, id)
        XCTAssertEqual(receipt.uploadStartEvidence?.signal, .correlatedProgress); XCTAssertEqual(receipt.outcome, .uploadStarted)
        XCTAssertTrue(receipt.isUploading); XCTAssertFalse(receipt.safeToRetry); XCTAssertFalse(receipt.positiveReady)
        XCTAssertNil(receipt.completionEvidence); XCTAssertNil(receipt.terminationEvidence); XCTAssertNil(receipt.continuationEvidence)
        let policy = ReceiptPolicy(uploadStartProfiles: [id: .webChat], profileOrigins: [id: [.systemScreenshot]],
            startOnlyApplications: ["com.microsoft.edgemac": .init(adapterID: profile.adapterID, receiptProfileID: profile.profileID, startProfileID: id,
                signal: .correlatedProgress, mediaType: "image/png", route: .chatGPTTemporaryHome)])
        let row = try await store.apply(receipt, policy: policy)
        XCTAssertEqual(row.visibility, .swallowed)
        let start = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertEqual(start, receipt); XCTAssertFalse(policy.allowsConsumption(receipt: receipt, asset: request.asset, mode: .production))
        XCTAssertFalse(policy.allowsRetry(receipt: receipt, asset: request.asset, mode: .production))
        let records = await bridge.records()
        XCTAssertEqual(records.commands.map(\.action), [.begin, .chunk, .commit, .observe])
        XCTAssertEqual(records.commands.first?.edgeProgressCandidate, true)
        XCTAssertTrue(records.commands.dropFirst().allSatisfy { $0.edgeProgressCandidate == nil })
    }

    private func seedEdgeRegistration(_ request: TransferRequest, profile: ObservationProfile,
                                      source: String, store: QueueStore) async throws -> ObservationIdentity {
        let op = request.operation
        let identity = ObservationIdentity(operationID: op.id, assetID: request.asset.id, attempt: op.attempt,
            assetSHA256: request.asset.sha256, target: op.target)
        let registration: [String: Any] = ["version": 2, "sourceID": source,
            "startProfileID": try XCTUnwrap(profile.uploadStartProfileID), "completionProfileID": profile.profileID,
            "enrollmentID": UUID().uuidString, "assetOrigin": AssetOrigin.systemScreenshot.rawValue,
            "identity": try JSONSerialization.jsonObject(with: JSONEncoder().encode(identity))]
        let bytes = try JSONSerialization.data(withJSONObject: registration, options: [.sortedKeys])
        for scope in [SystemScreenshotAdmissionScope.candidate, .productSystem] {
            _ = try await store.claimDispatchCheckpoint(bytes, for: SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: scope),
                operation: op, asset: request.asset)
        }
        return identity
    }

    func testRestartPreservesV21EdgeStartAndUnknownAndReadsOnlyTheOriginalObserver() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("queue.sqlite"), store = try QueueStore(databaseURL: url)
        let profile = OrdinaryProductScreenshotScope.edgeProgressProfile, id = try XCTUnwrap(profile.uploadStartProfileID)
        let policy = ReceiptPolicy(uploadStartProfiles: [id: .webChat], profileOrigins: [id: [.systemScreenshot]],
            startOnlyApplications: ["com.microsoft.edgemac": .init(adapterID: profile.adapterID, receiptProfileID: profile.profileID,
                startProfileID: id, signal: .correlatedProgress, mediaType: "image/png", route: .chatGPTTemporaryHome)])
        let frozen = try XCTUnwrap(ChatGPTWebPageProgram.originalObservationProgram(sourceID: ChatGPTWebPageProgram.priorLabelSource))
        let first = try await prepare(root: root, store: store, gray: 0.31).0
        let identity = try await seedEdgeRegistration(first, profile: profile, source: frozen.sourceID, store: store)
        let original = EdgeInputBridge(state: .uploadStarted, signal: .correlatedProgress, provenanceID: "click-document-witness-20261117-v21")
        let raw = try await original.execute(.init(action: .observe, target: identity.target, identity: identity), program: frozen)
        let receipt = try ObservationNormalizer(profile: profile, developmentScope: .ordinarySystemScreenshot)
            .receipt(from: ObservationDecoder.decode(raw), for: first)
        _ = try await store.apply(receipt, policy: policy)
        let second = try await prepare(root: root, store: store, gray: 0.73).0
        _ = try await seedEdgeRegistration(second, profile: profile, source: frozen.sourceID, store: store)
        try await store.markUnknown(second.operation.id, reason: "original input uncertain")
        let key = SystemScreenshotCandidateAdmission.checkpointKey(for: second, scope: .productSystem)
        let registration = try await store.checkpoint(for: key)

        let reopened = try QueueStore(databaseURL: url)
        let bridge = EdgeInputBridge(state: .unknown, provenanceID: "click-document-witness-20261117-v21")
        let client = try adapter(root: root, store: reopened, bridge: bridge)
        try await TransferCoordinator(store: reopened, adapter: client, mediaDirectory: root, policy: policy).recover()
        let result = try await client.reconcile(refreshed(second, store: reopened))
        XCTAssertEqual(result.outcome, .unknown); XCTAssertNil(result.uploadStartEvidence); XCTAssertFalse(result.safeToRetry)
        let after = try await reopened.uploadStartReceipt(for: first.operation.id), firstRow = try await reopened.asset(id: first.asset.id)
        let secondStart = try await reopened.uploadStartReceipt(for: second.operation.id), secondRow = try await reopened.asset(id: second.asset.id)
        let saved = try await reopened.checkpoint(for: key), executed = await bridge.records(), sources = await bridge.programIDs
        XCTAssertEqual(after, receipt); XCTAssertEqual(firstRow?.visibility, .swallowed)
        XCTAssertNil(secondStart); XCTAssertEqual(secondRow?.visibility, .visible); XCTAssertEqual(saved, registration)
        XCTAssertEqual(executed.commands.map(\.action), [.observe]); XCTAssertEqual(sources, [frozen.sourceID])
    }

    func testOriginalDraftContentPersistsThroughOrdinaryObservationWithoutStartOrCompletion() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent("queue.sqlite"), store = try QueueStore(databaseURL: db)
        let request = try await prepare(root: root, store: store, gray: 0.51).0
        _ = try await seedEdgeRegistration(request, profile: OrdinaryProductScreenshotScope.edgeProgressProfile,
            source: ChatGPTWebPageProgram.edgeSourceID, store: store)
        try await store.markUnknown(request.operation.id, reason: "Input returned without an upload receipt")
        let original = try await refreshed(request, store: store)
        let bridge = EdgeInputBridge(), client = try adapter(root: root, store: store, bridge: bridge)
        let key = SystemScreenshotObservationJournal.checkpointKey(request, slot: .originalDraftContent, scope: .productSystem)
        func content(_ invocation: UUID) -> ObservedDraftImage {
            .init(version: 1, invocationID: invocation, evidenceID: UUID(), inputSequence: 3, observedSequence: 8,
                  encodedSHA256: String(repeating: "b", count: 64), encodedByteCount: 187)
        }
        let proof = content(try XCTUnwrap(request.invocationID))
        await bridge.setContent(content(UUID()))
        do { _ = try await client.reconcile(original); XCTFail("Foreign invocation wrote content") }
        catch SystemScreenshotObservationJournalError.persistentIdentityMismatch {}
        let absent = try await store.checkpoint(for: key)
        XCTAssertNil(absent)
        await bridge.setContent(proof)
        let receipt = try await client.reconcile(original)
        XCTAssertEqual(receipt.outcome, .inputTriggered)
        XCTAssertNil(receipt.uploadStartEvidence); XCTAssertNil(receipt.completionEvidence)
        _ = try await store.apply(receipt)
        let reopened = try QueueStore(databaseURL: db)
        let raw = try await reopened.checkpoint(for: key)
        let saved = try JSONDecoder().decode(SystemScreenshotObservationJournal.Entry.self, from: XCTUnwrap(raw))
        XCTAssertEqual(saved.envelope.observation.originalDraftContent, proof)
        await bridge.setContent(content(proof.invocationID))
        do { _ = try await client.reconcile(original); XCTFail("Different content replaced first proof") }
        catch SystemScreenshotObservationJournalError.conflictingCheckpoint {}
        let retained = try await reopened.checkpoint(for: key), start = try await reopened.uploadStartReceipt(for: request.operation.id)
        let op = try await reopened.operation(id: request.operation.id), image = try await reopened.asset(id: request.asset.id)
        XCTAssertEqual(retained, raw); XCTAssertNil(start); XCTAssertEqual(op?.phase, .unknown)
        XCTAssertEqual(image?.visibility, .visible)
        let commands = await bridge.records().commands
        XCTAssertEqual(commands.map(\.action), [.observe, .observe, .observe])
    }

    func testNeitherHostCanUseTheOtherHostsExclusiveRegistration() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        for (host, foreign) in [("com.google.Chrome", ChatGPTWebPageProgram.edgeSourceID),
                                ("com.google.Chrome", ChatGPTWebPageProgram.priorEncodedSource),
                                ("com.google.Chrome", ChatGPTWebPageProgram.priorStagedSource),
                                ("com.google.Chrome", ChatGPTWebPageProgram.priorDraftContentSource),
                                ("com.microsoft.edgemac", ChatGPTWebPageProgram.sourceID)] {
            let (request, _, _) = try await prepare(root: root, store: store, gray: 0.4, application: host)
            _ = try await seedEdgeRegistration(request, profile: OrdinaryProductScreenshotScope.admittedSystemProfile,
                                               source: foreign, store: store)
            let admission = SystemScreenshotCandidateAdmission(store: store, scope: .productSystem)
            do { _ = try await admission.originalObservationProgram(for: request); XCTFail("foreign host registration") }
            catch { XCTAssertEqual(error as? WebAdapterError, .invalidRequest) }
        }
    }

    func testEdgeProgressVersionsKeepTheirOwnProgramAndJournalOnRestart() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("queue.sqlite")
        for source in [ChatGPTWebPageProgram.priorEdgeSource, ChatGPTWebPageProgram.priorEncodedSource, ChatGPTWebPageProgram.priorStagedSource, ChatGPTWebPageProgram.priorDraftContentSource, ChatGPTWebPageProgram.edgeSourceID] {
            let store = try QueueStore(databaseURL: url)
            let (request, _, _) = try await prepare(root: root, store: store, gray: 0.4)
            let identity = try await seedEdgeRegistration(request, profile: OrdinaryProductScreenshotScope.edgeProgressProfile,
                                                          source: source, store: store)
            try await store.markUnknown(request.operation.id, reason: "original one-shot input")
            let evidence = try XCTUnwrap(ChatGPTWebPageProgram.edgeEvidence(for: source))
            let reopened = try QueueStore(databaseURL: url)
            let original = try await refreshed(request, store: reopened)
            let journal = SystemScreenshotObservationJournal(store: reopened, scope: .productSystem)
            let key = SystemScreenshotObservationJournal.checkpointKey(original, slot: .unknown, scope: .productSystem)
            func packet(_ provenance: String) -> AttachmentObservationEnvelope {
                .init(provenance: .init(source: .integratedDevelopment, evidenceID: provenance),
                      observation: .init(identity: identity, state: .unknown, belongsToOriginalDraft: true))
            }
            for conflicting in [ChatGPTWebPageProgram.draftContentEvidenceV27, ChatGPTWebPageProgram.priorStagedEvidence, ChatGPTWebPageProgram.priorEncodedEvidence, "click-document-witness-20261118-v25", "click-document-witness-20261118-v23", "click-document-witness-20261117-v22", ChatGPTWebPageProgram.edgeEvidenceID] where conflicting != evidence {
                do { try await journal.record(packet(conflicting), for: original, readOnly: true); XCTFail("unregistered provenance") }
                catch { XCTAssertEqual(error as? SystemScreenshotObservationJournalError, .invalidProvenance) }
            }
            let before = try await reopened.checkpoint(for: key)
            XCTAssertNil(before)
            let bridge = EdgeInputBridge(state: .unknown, provenanceID: evidence)
            let client = try adapter(root: root, store: reopened, bridge: bridge)
            _ = try await client.reconcile(original)
            let first = try await reopened.checkpoint(for: key)
            _ = try await client.reconcile(original)
            let retained = try await reopened.checkpoint(for: key)
            let ids = await bridge.programIDs, commands = await bridge.records().commands
            XCTAssertEqual(ids, [source, source]); XCTAssertEqual(commands.map(\.action), [.observe, .observe])
            XCTAssertNotNil(first); XCTAssertEqual(retained, first)
            let stored = try await reopened.operation(id: original.operation.id)
            XCTAssertEqual(stored?.phase, .unknown)
        }
    }

    func testEdgeProgressCannotPromoteOldRegistrationOrBuiltInOriginOrZeroStartingValue() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        for scenario in ["old-v18", "old-v19", "old-v20", "old-v21", "old-v22", "v19-new-route", "ordinary-draft", "built-in", "zero", "old-provenance"] {
            let historical = ["old-v18", "old-v19", "old-v20", "old-v21", "old-v22", "v19-new-route"].contains(scenario)
            let (request, _, _) = try await prepare(root: root, store: store, gray: 0.2,
                origin: scenario == "built-in" ? .applicationScreenshot : .systemScreenshot,
                route: ["old-v18", "old-v19", "ordinary-draft"].contains(scenario) ? nil : .chatGPTTemporaryHome)
            let bridge = EdgeInputBridge(state: .uploadStarted, signal: .correlatedProgress,
                previousProgress: scenario == "zero" ? 0 : 4,
                provenanceID: scenario == "old-provenance" ? "click-document-witness-20261117-v22" : ChatGPTWebPageProgram.edgeEvidenceID)
            let client = try adapter(root: root, store: store, bridge: bridge)
            if historical {
                let old = ["old-v20", "old-v21", "old-v22"].contains(scenario) ? OrdinaryProductScreenshotScope.edgeProgressProfile : OrdinaryProductScreenshotScope.admittedSystemProfile
                let source: String
                switch scenario {
                case "old-v18": source = ChatGPTWebPageProgram.priorClickSource
                case "old-v20": source = ChatGPTWebPageProgram.priorProgressSource
                case "old-v21": source = ChatGPTWebPageProgram.priorLabelSource
                case "old-v22": source = ChatGPTWebPageProgram.priorEdgeSource
                default: source = ChatGPTWebPageProgram.priorOriginSource
                }
                _ = try await seedEdgeRegistration(request, profile: old, source: source, store: store)
                try await store.markUnknown(request.operation.id, reason: "original old input permanently uncertain")
            }
            do {
                if historical { _ = try await client.reconcile(refreshed(request, store: store)) }
                else { _ = try await client.append(request) }
                XCTFail(scenario)
            } catch { XCTAssertEqual(error as? WebAdapterError, .invalidReply, scenario) }
            let start = try await store.uploadStartReceipt(for: request.operation.id)
            let row = try await store.asset(id: request.asset.id)
            XCTAssertNil(start); XCTAssertEqual(row?.visibility, .visible)
            let sent = await bridge.records()
            XCTAssertEqual(sent.commands.map(\.action), historical ? [.observe] : [.begin, .chunk, .commit])
            if ["built-in", "ordinary-draft"].contains(scenario) { XCTAssertNil(sent.commands.first?.edgeProgressCandidate) }
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

    func testHistoricalLeaseStableKeyRemainsByteIdenticalWithoutRouteClassification() throws {
        let original: [String: String] = ["adapterID": "chatgpt-web", "surface": "webChat", "applicationID": "com.microsoft.edgemac",
            "sessionID": "s", "windowID": "1", "tabID": "2", "documentID": "d", "composerID": "c", "draftGeneration": "g",
            "clickBindingID": UUID().uuidString]
        let bytes = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
        let restored = try JSONDecoder().decode(TargetLease.self, from: bytes)
        XCTAssertNil(restored.webDraftRoute); XCTAssertEqual(Data(restored.stableKey.utf8), bytes)
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
    private(set) var programIDs: [String] = []
    private var bytes: [UUID: Data] = [:]
    private let signal: UploadStartSignal
    private let previousProgress: Double
    private let provenanceID: String
    private var content: ObservedDraftImage?
    init(state: AttachmentObservedState = .inputTriggered, loseCommitReply: Bool = false,
         signal: UploadStartSignal = .attachmentAccepted, previousProgress: Double = 4,
         provenanceID: String = ChatGPTWebPageProgram.edgeEvidenceID) {
        self.state = state; self.loseCommitReply = loseCommitReply; self.signal = signal
        self.previousProgress = previousProgress; self.provenanceID = provenanceID
    }
    func setState(_ value: AttachmentObservedState) { state = value }
    func setContent(_ value: ObservedDraftImage) { content = value }
    func records() -> (commands: [WebBridgeCommand], bytes: [UUID: Data]) { (commands, bytes) }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        commands.append(command); programIDs.append(program.sourceID)
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
            let start = state == .uploadStarted ? ObservedUploadStart(version: 1, signal: signal,
                evidenceID: "00000000-0000-4000-8000-000000000001", inputCount: 1, inputSequence: 1, startSequence: 2,
                previousProgress: signal == .correlatedProgress ? previousProgress : 0, currentProgress: signal == .correlatedProgress ? 18 : 0, inputObservedAtMS: 10, startObservedAtMS: 11) : nil
            return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 2,
                provenance: .init(source: .integratedDevelopment, evidenceID: provenanceID),
                observation: .init(identity: identity, state: state,
                    attachmentID: [.uploadStarted, .attached, .ready].contains(state) ? "owned-fixture-attachment" : nil,
                    exactImageIdentity: content == nil, belongsToOriginalDraft: true,
                    hasError: state == .failed, isUploading: state == .uploadStarted && signal == .correlatedProgress, attachmentAbsent: state == .failed,
                    automaticRetryExcluded: state == .failed, uploadStart: start, inputExecutionPending: false,
                    originalDraftContent: content)))
        default: throw WebAdapterError.invalidRequest
        }
    }
}
