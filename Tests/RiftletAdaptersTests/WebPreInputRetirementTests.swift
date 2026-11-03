import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Exercises the real adapter file/commit/observation boundary with deterministic
/// page replies. It neither executes JavaScript nor claims platform evidence.
private actor PreInputRetirementBridge: WebBridgeExecutor {
    enum CommitReply: Sendable { case packet, lost }
    private let request: TransferRequest
    private let packet: Data
    private let expectedBytes: Data
    private let commitReply: CommitReply
    private var recorded: [WebBridgeAction] = []
    private var bytes = Data()

    init(request: TransferRequest, packet: Data, expectedBytes: Data, commitReply: CommitReply = .packet) {
        self.request = request; self.packet = packet; self.expectedBytes = expectedBytes; self.commitReply = commitReply
    }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        recorded.append(command.action)
        let expected = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        guard command.identity == expected, command.target == request.operation.target else {
            throw WebAdapterError.invalidRequest
        }
        if command.action != .observe {
            guard command.invocationID == request.invocationID else { throw WebAdapterError.invalidRequest }
        }
        switch command.action {
        case .begin, .chunk:
            if command.action == .chunk {
                guard let encoded = command.chunkBase64, let chunk = Data(base64Encoded: encoded) else {
                    throw WebAdapterError.invalidRequest
                }
                bytes.append(chunk)
            }
            return try JSONSerialization.data(withJSONObject: [
                "operationID": expected.operationID.uuidString, "attempt": expected.attempt,
                "nextChunk": command.action == .begin ? 0 : (command.chunkIndex ?? -1) + 1
            ])
        case .commit:
            guard bytes == expectedBytes else { throw WebAdapterError.invalidPrivateFile }
            if case .lost = commitReply { throw WebAdapterError.nativeExecutionFailed }
            return packet
        case .observe: return packet
        default: throw WebAdapterError.invalidRequest
        }
    }

    func actions() -> [WebBridgeAction] { recorded }
    func receivedBytes() -> Data { bytes }
}

final class WebPreInputRetirementTests: XCTestCase {
    private var directory: URL!
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGNQ9q5oQMYMpAsAAO8CFmEhXyLHAAAAAElFTkSuQmCC")!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-retirement-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func fixture() async throws -> (QueueStore, TransferRequest) {
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "\(UUID()).png",
            sha256: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(png.count),
            pixelWidth: 4, pixelHeight: 4, mediaType: "image/png", origin: .synthetic)
        let file = directory.appendingPathComponent(asset.fileName)
        try png.write(to: file)
        _ = try await store.importAsset(asset)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "fixture-session",
            windowID: "17", tabID: "19", documentID: "fixture-document", composerID: "fixture-composer",
            draftGeneration: "fixture-generation", clickBindingID: UUID())
        let prepared = try await store.prepare(assetID: asset.id, target: target)
        let invocationID = try await store.markDispatchIntent(prepared.id)
        let saved = try await store.operation(id: prepared.id)
        return (store, TransferRequest(operation: try XCTUnwrap(saved), asset: asset,
            fileURL: file, invocationID: invocationID))
    }

    private func adapter(_ bridge: PreInputRetirementBridge, diagnosticTrace: BoundedDiagnosticTrace? = nil) -> WebAttachmentAdapter {
        WebAttachmentAdapter(mediaDirectory: directory, executor: bridge,
            program: WebPageProgram(sourceID: "constructed-pre-input-retirement", functionSource: "function () { return null; }"),
            mode: .syntheticDevelopment, polling: .disabled, diagnosticTrace: diagnosticTrace)
    }

    private func freshTarget(_ old: TargetLease) -> TargetLease {
        TargetLease(adapterID: old.adapterID, surface: old.surface, applicationID: old.applicationID,
            sessionID: old.sessionID, windowID: old.windowID, tabID: old.tabID, documentID: old.documentID,
            composerID: old.composerID, draftGeneration: old.draftGeneration,
            logicalDraftIdentity: old.logicalDraftIdentity, clickBindingID: UUID())
    }

    private func envelope(_ request: TransferRequest) throws -> AttachmentObservationEnvelope {
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        return AttachmentObservationEnvelope(schemaVersion: 3,
            provenance: .init(source: .integratedDevelopment, evidenceID: "pre-input-retirement-fixture"),
            observation: .init(identity: identity, state: .invalidated, belongsToOriginalDraft: true,
                preInputRetirement: .init(invocationID: try XCTUnwrap(request.invocationID), commitInvoked: true,
                    commitWorkSettled: true, irreversiblyRetired: true, inputSideEffectEntered: false,
                    inputCount: 0, reason: .inputHashMismatch)))
    }

    private func mutate(_ packet: AttachmentObservationEnvelope,
                        _ body: (inout [String: Any]) -> Void) throws -> AttachmentObservationEnvelope {
        var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(packet)) as! [String: Any]
        body(&root)
        return try ObservationDecoder.decode(JSONSerialization.data(withJSONObject: root))
    }

    func testOnlyExactCurrentAppendInvocationCanProduceTypedNoInputRejection() async throws {
        let (_, request) = try await fixture(), packet = try envelope(request)
        let decoded = try ObservationDecoder.decode(JSONEncoder().encode(packet))
        XCTAssertEqual(decoded, packet)
        let proof = try XCTUnwrap(WebPreInputRetirement.rejection(from: decoded, for: request))
        XCTAssertEqual(proof.stage, .pageRetiredBeforeFileInput)
        XCTAssertEqual(proof.operationID, request.operation.id)
        XCTAssertEqual(proof.assetID, request.asset.id)
        XCTAssertEqual(proof.attempt, request.operation.attempt)
        XCTAssertEqual(proof.assetSHA256, request.asset.sha256)
        XCTAssertEqual(proof.target, request.operation.target)
        XCTAssertEqual(proof.invocationID, request.invocationID)
    }

    func testResourceRefusalDiagnosticRemainsClosedAndRequiresActualRetirement() async throws {
        let (_, request) = try await fixture(), original = try envelope(request)
        let valid = try mutate(original) { root in
            var observation = root["observation"] as! [String: Any]
            var retirement = observation["preInputRetirement"] as! [String: Any]
            retirement["reason"] = "inputPreparationFailed"
            observation["preInputRetirement"] = retirement
            observation["resourceRefusalReason"] = "INPUT_RESOURCE_TARGET_CHANGED"
            root["observation"] = observation
        }
        XCTAssertEqual(valid.observation.resourceRefusalReason, .inputResourceTargetChanged)
        XCTAssertNotNil(try WebPreInputRetirement.rejection(from: valid, for: request))
        for detail in ["private page error", "INPUT_RESOURCE_TARGET_CHANGED\n", "TARGET_INVALID"] {
            XCTAssertThrowsError(try mutate(valid) { root in
                var observation = root["observation"] as! [String: Any]
                observation["resourceRefusalReason"] = detail; root["observation"] = observation
            })
        }
        XCTAssertThrowsError(try mutate(valid) { root in
            var observation = root["observation"] as! [String: Any]
            observation.removeValue(forKey: "preInputRetirement"); root["observation"] = observation
        })
        XCTAssertThrowsError(try mutate(original) { root in
            var observation = root["observation"] as! [String: Any]
            observation["resourceRefusalReason"] = "INPUT_RESOURCE_EXECUTION_BUSY"; root["observation"] = observation
        })
    }

    func testCommitResourceRefusalPersistsItsSpecificCodeWithoutGrantingReplay() async throws {
        let (_, request) = try await fixture(), original = try envelope(request)
        let packet = try mutate(original) { root in
            var observation = root["observation"] as! [String: Any]
            var retirement = observation["preInputRetirement"] as! [String: Any]
            retirement["reason"] = "inputPreparationFailed"
            observation["preInputRetirement"] = retirement
            observation["resourceRefusalReason"] = "INPUT_RESOURCE_BASELINE_CHANGED"
            root["observation"] = observation
        }
        let log = directory.appendingPathComponent("diagnostics")
        let trace = BoundedDiagnosticTrace(enabled: true, directory: log, emitStandardError: false)
        let bridge = PreInputRetirementBridge(request: request, packet: try JSONEncoder().encode(packet), expectedBytes: png)
        let client = adapter(bridge, diagnosticTrace: trace)
        do { _ = try await client.append(request); XCTFail("Retired resource input succeeded") }
        catch let proof as PreInputRejection { XCTAssertEqual(proof.stage, .pageRetiredBeforeFileInput) }
        trace.flushForTesting()
        let text = String(decoding: try Data(contentsOf: log.appendingPathComponent("acceptance-failures.jsonl")), as: UTF8.self)
        XCTAssertTrue(text.contains("INPUT_RESOURCE_BASELINE_CHANGED"))
        let before = await bridge.actions()
        do { _ = try await client.append(request); XCTFail("Retired invocation replayed") }
        catch WebAdapterError.invalidRequest {}
        let after = await bridge.actions()
        XCTAssertEqual(before, after)
    }

    func testIncompleteOrSideEffectEnteredRetirementCannotBeDecoded() async throws {
        let (_, request) = try await fixture(), packet = try envelope(request)
        let changes: [(String, Any)] = [("version", 2), ("commitInvoked", false),
            ("commitWorkSettled", false), ("irreversiblyRetired", false),
            ("inputSideEffectEntered", true), ("inputCount", 1), ("inputCount", -1),
            ("reason", "maybe-no-input"), ("extraAuthority", true)]
        for (key, value) in changes {
            XCTAssertThrowsError(try mutate(packet) { root in
                var item = root["observation"] as! [String: Any]
                var proof = item["preInputRetirement"] as! [String: Any]
                proof[key] = value; item["preInputRetirement"] = proof; root["observation"] = item
            }, key)
        }
        for version in [1, 2] {
            XCTAssertThrowsError(try mutate(packet) { $0["schemaVersion"] = version })
        }
        XCTAssertThrowsError(try mutate(packet) { root in
            var item = root["observation"] as! [String: Any]
            item.removeValue(forKey: "preInputRetirement"); root["observation"] = item
        })
    }

    func testRetirementCannotAssertAttachmentOrUploadOrSuccessFacts() async throws {
        let (_, request) = try await fixture(), packet = try envelope(request)
        let changes: [(String, Any)] = [("state", "attached"), ("state", "inputTriggered"),
            ("attachmentID", "another-card"), ("exactImageIdentity", true),
            ("belongsToOriginalDraft", false), ("hasError", true), ("isUploading", true),
            ("attachmentAbsent", true), ("automaticRetryExcluded", true)]
        for (key, value) in changes {
            XCTAssertThrowsError(try mutate(packet) { root in
                var item = root["observation"] as! [String: Any]
                item[key] = value; root["observation"] = item
            }, key)
        }
    }

    func testWrongInvocationIdentityOrProvenanceCannotRetireCurrentOperation() async throws {
        let (_, request) = try await fixture(), packet = try envelope(request)
        let invocation = try mutate(packet) { root in
            var item = root["observation"] as! [String: Any], proof = item["preInputRetirement"] as! [String: Any]
            proof["invocationID"] = UUID().uuidString; item["preInputRetirement"] = proof; root["observation"] = item
        }
        XCTAssertThrowsError(try WebPreInputRetirement.rejection(from: invocation, for: request))
        for (key, value) in [("operationID", UUID().uuidString as Any), ("assetID", UUID().uuidString),
                             ("attempt", 2), ("assetSHA256", String(repeating: "b", count: 64))] {
            let wrong = try mutate(packet) { root in
                var item = root["observation"] as! [String: Any], identity = item["identity"] as! [String: Any]
                identity[key] = value; item["identity"] = identity; root["observation"] = item
            }
            XCTAssertThrowsError(try WebPreInputRetirement.rejection(from: wrong, for: request), key)
        }
        let pin = try mutate(packet) { root in
            var item = root["observation"] as! [String: Any], identity = item["identity"] as! [String: Any]
            var target = identity["target"] as! [String: Any]; target["clickBindingID"] = UUID().uuidString
            identity["target"] = target; item["identity"] = identity; root["observation"] = item
        }
        XCTAssertThrowsError(try WebPreInputRetirement.rejection(from: pin, for: request))
        for source in ["syntheticFixture", "sanitizedReal"] {
            let wrong = try mutate(packet) { root in
                var provenance = root["provenance"] as! [String: Any]
                provenance["source"] = source; root["provenance"] = provenance
            }
            XCTAssertThrowsError(try WebPreInputRetirement.rejection(from: wrong, for: request))
        }
    }

    func testReconcileUnknownLegacyAndMissingInvocationNeverHealOrGrantRetry() async throws {
        let (store, request) = try await fixture(), packet = try envelope(request)
        try await store.markUnknown(request.operation.id, reason: "Lost original commit result")
        let saved = try await store.operation(id: request.operation.id)
        let unknown = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset,
            fileURL: request.fileURL, invocationID: request.invocationID)
        XCTAssertNil(try WebPreInputRetirement.rejection(from: packet, for: unknown))
        let missing = TransferRequest(operation: request.operation, asset: request.asset, fileURL: request.fileURL)
        XCTAssertNil(try WebPreInputRetirement.rejection(from: packet, for: missing))
        for version in [1, 2] {
            let legacy = try mutate(packet) { root in
                root["schemaVersion"] = version
                var item = root["observation"] as! [String: Any]
                item.removeValue(forKey: "preInputRetirement"); root["observation"] = item
            }
            XCTAssertNil(try WebPreInputRetirement.rejection(from: legacy, for: request))
        }
        let receipt = try ObservationNormalizer(profile: .init(adapterID: "chatgpt-web", surface: .webChat,
            profileID: "fixture", failureSignal: .terminalErrorAndNoResidual)).receipt(from: packet, for: unknown)
        XCTAssertEqual(receipt.outcome, .unknown); XCTAssertFalse(receipt.safeToRetry)
        let retained = try await store.operation(id: request.operation.id)
        XCTAssertEqual(retained?.phase, .unknown)
    }

    func testActualAppendRetirementPersistsNoInputAndAllowsOnlyFreshClickAttempt() async throws {
        let (store, request) = try await fixture(), packet = try envelope(request)
        let bridge = PreInputRetirementBridge(request: request, packet: try JSONEncoder().encode(packet), expectedBytes: png)
        let client = adapter(bridge)
        var rejection: PreInputRejection?
        do { _ = try await client.append(request); XCTFail("Settled retirement should reject this append") }
        catch let proof as PreInputRejection { rejection = proof }
        let proof = try XCTUnwrap(rejection)
        XCTAssertEqual(proof.stage, .pageRetiredBeforeFileInput)
        XCTAssertEqual(proof.invocationID, request.invocationID)
        let before = try await store.operation(id: request.operation.id)
        XCTAssertEqual(before?.phase, .dispatchIntent)
        try await store.recordPreInputRejection(proof)
        let retired = try await store.operation(id: request.operation.id)
        let asset = try await store.asset(id: request.asset.id)
        XCTAssertEqual(retired?.phase, .failed); XCTAssertEqual(asset?.status, .failed)
        XCTAssertEqual(asset?.visibility, .visible); XCTAssertEqual(asset?.image, request.asset)
        let receipt = try await store.receipt(for: request.operation.id)
        let start = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertNil(receipt); XCTAssertNil(start)
        let audit = try await store.checkpoint(for: "transfer-no-input-v1:" + request.operation.id.uuidString)
        XCTAssertEqual(try JSONDecoder().decode(PreInputRejection.self, from: XCTUnwrap(audit)), proof)
        let received = await bridge.receivedBytes(), actions = await bridge.actions()
        XCTAssertEqual(received, png); XCTAssertEqual(actions, [.begin, .chunk, .commit])

        // The retired invocation is not replayable, even when its file remains.
        do { _ = try await client.append(request); XCTFail("Original append replayed") }
        catch WebAdapterError.invalidRequest {}
        let afterReplay = await bridge.actions(); XCTAssertEqual(afterReplay, actions)

        let target = freshTarget(request.operation.target)
        let next = try await store.prepare(assetID: request.asset.id, target: target)
        XCTAssertNotEqual(next.id, request.operation.id); XCTAssertEqual(next.attempt, request.operation.attempt + 1)
        let now = ProcessInfo.processInfo.systemUptime
        let click = AcceptedSelection(assetID: request.asset.id, target: target, hostEpoch: UUID(),
            acknowledgedUptime: now - 0.005, eventUptime: now - 0.01, acceptedUptime: now,
            visibilityRevision: try XCTUnwrap(asset).visibilityRevision, deadlineUptime: now + 30,
            authorization: .nativeClickPin)
        let nextInvocation = try await store.markDispatchIntent(next.id, selection: click, ownerID: UUID())
        XCTAssertNotEqual(nextInvocation, request.invocationID); XCTAssertFalse(click.isValid())
        let original = try await store.operation(id: request.operation.id)
        XCTAssertEqual(original, retired, "A new click cannot rewrite the original retirement")
        let finalActions = await bridge.actions(); XCTAssertEqual(finalActions, actions, "Eligibility is not automatic input")
    }

    func testActualReconcileSameProofNeverHealsEvenOriginalDispatchSnapshot() async throws {
        let (store, request) = try await fixture(), packet = try envelope(request)
        let bridge = PreInputRetirementBridge(request: request, packet: try JSONEncoder().encode(packet), expectedBytes: png)
        let client = adapter(bridge)
        // A read-only caller may retain a dispatchIntent snapshot after a lost
        // result. liveAppend, not that phase alone, owns no-input authority.
        let receipt = try await client.reconcile(request)
        XCTAssertEqual(receipt.outcome, .unknown); XCTAssertFalse(receipt.safeToRetry)
        _ = try await store.apply(receipt)
        let saved = try await store.operation(id: request.operation.id)
        let unknown = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset,
            fileURL: request.fileURL, invocationID: request.invocationID)
        XCTAssertEqual(unknown.operation.phase, .unknown)
        let late = try await client.reconcile(unknown)
        XCTAssertEqual(late.outcome, .unknown); XCTAssertFalse(late.safeToRetry)
        _ = try await store.apply(late)
        let proof = try XCTUnwrap(WebPreInputRetirement.rejection(from: packet, for: request))
        do { try await store.recordPreInputRejection(proof); XCTFail("Late proof healed UNKNOWN") }
        catch RiftletError.mismatchedReceipt {}
        let selected = try await store.prepare(assetID: request.asset.id, target: freshTarget(request.operation.target))
        XCTAssertEqual(selected.id, request.operation.id); XCTAssertEqual(selected.attempt, request.operation.attempt)
        let audit = try await store.checkpoint(for: "transfer-no-input-v1:" + request.operation.id.uuidString)
        XCTAssertNil(audit)
        let actions = await bridge.actions(); XCTAssertEqual(actions, [.observe, .observe])
        let bytes = await bridge.receivedBytes(); XCTAssertTrue(bytes.isEmpty)
    }

    func testActualLostCommitOrWrongInvocationStaysUnknownDespiteLateRetirement() async throws {
        for lostReply in [false, true] {
            let (store, request) = try await fixture(), correct = try envelope(request)
            var packet = correct
            if !lostReply {
                packet = try mutate(correct) { root in
                    var item = root["observation"] as! [String: Any], proof = item["preInputRetirement"] as! [String: Any]
                    proof["invocationID"] = UUID().uuidString; item["preInputRetirement"] = proof; root["observation"] = item
                }
            }
            let bridge = PreInputRetirementBridge(request: request, packet: try JSONEncoder().encode(packet),
                expectedBytes: png, commitReply: lostReply ? .lost : .packet)
            let client = adapter(bridge)
            do { _ = try await client.append(request); XCTFail("Uncertain or wrong-invocation commit accepted") }
            catch is PreInputRejection { XCTFail("No valid original proof reached live append") }
            catch {
                if lostReply { XCTAssertEqual(error as? WebAdapterError, .nativeExecutionFailed) }
                else { XCTAssertEqual(error as? ObservationError, .identityMismatch) }
            }
            // This is the same conservative catch action used by Coordinator.
            try await store.markUnknown(request.operation.id, reason: "Constructed uncertain commit result")
            let saved = try await store.operation(id: request.operation.id)
            let unknown = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset,
                fileURL: request.fileURL, invocationID: request.invocationID)
            let late = try await client.reconcile(unknown)
            XCTAssertEqual(late.outcome, .unknown); XCTAssertFalse(late.safeToRetry)
            _ = try await store.apply(late)
            let proof = try XCTUnwrap(WebPreInputRetirement.rejection(from: correct, for: request))
            do { try await store.recordPreInputRejection(proof); XCTFail("Late proof healed uncertain commit") }
            catch RiftletError.mismatchedReceipt {}
            let selected = try await store.prepare(assetID: request.asset.id, target: freshTarget(request.operation.target))
            XCTAssertEqual(selected.id, request.operation.id); XCTAssertEqual(selected.phase, .unknown)
            do { _ = try await client.append(request); XCTFail("Uncertain commit replayed") }
            catch WebAdapterError.invalidRequest {}
            let actions = await bridge.actions(); XCTAssertEqual(actions, [.begin, .chunk, .commit, .observe])
            let bytes = await bridge.receivedBytes(); XCTAssertEqual(bytes, png)
            let audit = try await store.checkpoint(for: "transfer-no-input-v1:" + request.operation.id.uuidString)
            let start = try await store.uploadStartReceipt(for: request.operation.id)
            XCTAssertNil(audit); XCTAssertNil(start)
        }
    }
}
