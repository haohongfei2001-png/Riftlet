import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Exercises the real adapter file/commit/observation boundary with deterministic
/// page replies. It neither executes JavaScript nor claims platform evidence.
private actor PreInputRetirementBridge: WebBridgeExecutor {
    enum CommitReply: Sendable { case packet, lostBeforeInput, lostAfterInput }
    private let request: TransferRequest
    private let packet: Data
    private let expectedBytes: Data
    private let commitReply: CommitReply
    private var recorded: [WebBridgeAction] = []
    private var bytes = Data()
    private var inputCount = 0

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
            if case .lostAfterInput = commitReply {
                // This fixture models the setter side effect before transport
                // loses its reply; subsequent observe calls never execute it.
                inputCount += 1
                throw WebAdapterError.nativeExecutionFailed
            }
            if case .lostBeforeInput = commitReply { throw WebAdapterError.nativeExecutionFailed }
            return packet
        case .observe: return packet
        default: throw WebAdapterError.invalidRequest
        }
    }

    func actions() -> [WebBridgeAction] { recorded }
    func receivedBytes() -> Data { bytes }
    func actualInputs() -> Int { inputCount }
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

    private var entrySummary: [String: Any] {
        ["version": 1, "entryCandidates": 1, "entryActivations": 1, "openedContainers": 1, "menuActivations": 1,
         "pickerClicks": 1, "pickerShows": 0, "inputSeen": true, "inputConnected": false,
         "setterEntered": false, "changeReturned": false, "stage": "handoff", "cause": "exception",
         "exceptionType": "TypeError"]
    }

    private func withEntrySummary(_ envelope: AttachmentObservationEnvelope, _ summary: Any?) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any])
        root["entryDiagnostics"] = summary
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func traceRows(_ name: String, in log: URL) throws -> [[String: Any]] {
        try Data(contentsOf: log.appendingPathComponent(name)).split(separator: 10).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }

    func testMissingMalformedAndOversizedDiagnosticSidecarsDoNotChangeReceiptOrJournal() async throws {
        let (_, request) = try await fixture(), packet = try envelope(request)
        var oversized = entrySummary, untrusted = entrySummary
        oversized["unexpectedText"] = String(repeating: "secret", count: 2_000)
        untrusted["exceptionType"] = "private custom exception"
        for sidecar in [nil, "malformed", oversized, untrusted] as [Any?] {
            let data = try withEntrySummary(packet, sidecar)
            let (decoded, diagnostics) = try ObservationDecoder.decodeResponse(data, includeDiagnostics: true)
            XCTAssertEqual(decoded, packet)
            XCTAssertNil(diagnostics)
            XCTAssertEqual(try WebPreInputRetirement.rejection(from: decoded, for: request)?.reason, "inputHashMismatch")
            XCTAssertFalse(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self).contains("entryDiagnostics"))
        }
        let valid = try withEntrySummary(packet, entrySummary)
        let (decoded, diagnostics) = try ObservationDecoder.decodeResponse(valid, includeDiagnostics: true)
        XCTAssertEqual(decoded, packet)
        XCTAssertEqual(diagnostics?.stage, .handoff)
        XCTAssertNil(try ObservationDecoder.decodeResponse(valid, includeDiagnostics: false).diagnostics)
    }

    func testInterruptedAndExceptionalPreInputResultsReachFailureRingEvenAfterLostCommitReply() async throws {
        let log = directory.appendingPathComponent("diagnostics")
        let trace = BoundedDiagnosticTrace(enabled: true, directory: log, emitStandardError: false)
        for (cause, type, reply) in [("userInterrupted", "none", PreInputRetirementBridge.CommitReply.packet),
                                      ("exception", "TypeError", .lostBeforeInput)] {
            let (_, request) = try await fixture()
            let packet = try mutate(envelope(request)) { root in
                var item = root["observation"] as! [String: Any], proof = item["preInputRetirement"] as! [String: Any]
                proof["reason"] = "attachmentEntryFailed"
                item["preInputRetirement"] = proof; root["observation"] = item
            }
            var summary = entrySummary
            summary["cause"] = cause; summary["exceptionType"] = type
            summary["startObserved"] = true // Page instrumentation cannot grant START.
            summary["chatText"] = "private-content"
            let bridge = PreInputRetirementBridge(request: request, packet: try withEntrySummary(packet, summary),
                expectedBytes: png, commitReply: reply)
            do { _ = try await adapter(bridge, diagnosticTrace: trace).append(request); XCTFail("Retirement became input") }
            catch let failure as PreInputRejection { XCTAssertEqual(failure.reason, "attachmentEntryFailed") }
            trace.flushForTesting()
            let row = try XCTUnwrap(traceRows("acceptance-failures.jsonl", in: log).last)
            let digest = SHA256.hash(data: Data(request.operation.id.uuidString.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(row["operationIDDigest"] as? String, digest)
            XCTAssertEqual(row["critical"] as? Bool, true)
            XCTAssertEqual(row["entryDiagnosticsAvailable"] as? Bool, true)
            XCTAssertEqual(row["retirementReason"] as? String, "attachmentEntryFailed")
            XCTAssertEqual(row["retirementObservationOnly"] as? Bool, false)
            XCTAssertEqual(row["entryStage"] as? String, "handoff")
            XCTAssertEqual(row["entryCause"] as? String, cause); XCTAssertEqual(row["exceptionType"] as? String, type)
            XCTAssertEqual(row["pickerClicks"] as? Int, 1); XCTAssertEqual(row["inputSeen"] as? Bool, true)
            XCTAssertEqual(row["inputConnected"] as? Bool, false); XCTAssertEqual(row["setterEntered"] as? Bool, false)
            XCTAssertEqual(row["changeReturned"] as? Bool, false); XCTAssertEqual(row["startObserved"] as? Bool, false)
            let actions = await bridge.actions()
            XCTAssertEqual(actions.filter { $0 == .commit }.count, 1)
            let bytes = try Data(contentsOf: log.appendingPathComponent("acceptance-failures.jsonl"))
            let text = String(decoding: bytes, as: UTF8.self)
            XCTAssertFalse(text.contains("private-content")); XCTAssertFalse(text.contains(request.operation.id.uuidString))
        }
        let summaries = try traceRows("acceptance-failures.jsonl", in: log).filter { $0["event"] as? String == "attachment_entry_result" }
        XCTAssertEqual(summaries.count, 2)
    }

    func testStartRecoveredByObservationIsLoggedWithOriginalInputOnlyOnce() async throws {
        let (_, request) = try await fixture()
        let identity = try envelope(request).observation.identity
        let start = ObservedUploadStart(version: 1, signal: .attachmentAccepted, evidenceID: UUID().uuidString,
            inputCount: 1, inputSequence: 1, startSequence: 2, previousProgress: 0, currentProgress: 0,
            inputObservedAtMS: 10, startObservedAtMS: 11)
        let packet = AttachmentObservationEnvelope(schemaVersion: 2,
            provenance: .init(source: .syntheticFixture, evidenceID: "controlled-entry-start"),
            observation: .init(identity: identity, state: .uploadStarted, attachmentID: "controlled-attachment",
                exactImageIdentity: true, belongsToOriginalDraft: true, uploadStart: start))
        var summary = entrySummary
        summary["setterEntered"] = true; summary["changeReturned"] = true; summary["stage"] = "observation"
        summary["cause"] = "none"; summary["exceptionType"] = "none"; summary["startObserved"] = false
        let bridge = PreInputRetirementBridge(request: request, packet: try withEntrySummary(packet, summary),
            expectedBytes: png, commitReply: .lostAfterInput)
        let log = directory.appendingPathComponent("diagnostics")
        let trace = BoundedDiagnosticTrace(enabled: true, directory: log, emitStandardError: false)
        let client = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge,
            program: .init(sourceID: "constructed-start", functionSource: "function() {}"), mode: .syntheticDevelopment,
            profile: .init(adapterID: "chatgpt-web", surface: .webChat, profileID: "controlled-entry",
                uploadStartProfileID: "controlled-entry-start"), polling: .disabled, diagnosticTrace: trace)
        let receipt = try await client.append(request), repeated = try await client.reconcile(request)
        XCTAssertEqual(receipt.outcome, .uploadStarted); XCTAssertEqual(repeated.outcome, .uploadStarted)
        let actions = await bridge.actions(), inputs = await bridge.actualInputs()
        XCTAssertEqual(actions, [.begin, .chunk, .commit, .observe, .observe]); XCTAssertEqual(inputs, 1)
        trace.flushForTesting()
        let entries = try traceRows("acceptance-recent.jsonl", in: log).filter { $0["event"] as? String == "attachment_entry_result" }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["startObserved"] as? Bool, true)
        XCTAssertEqual(entries.first?["changeReturned"] as? Bool, true)
        XCTAssertEqual(entries.first?["critical"] as? Bool, false)
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
            ("hasError", true), ("isUploading", true),
            ("attachmentAbsent", true), ("automaticRetryExcluded", true)]
        for (key, value) in changes {
            XCTAssertThrowsError(try mutate(packet) { root in
                var item = root["observation"] as! [String: Any]
                item[key] = value; root["observation"] = item
            }, key)
        }
    }

    func testChangedTargetAndSynchronousBusyRetireOnlyThisUnsubmittedInvocation() async throws {
        for reason in ["targetInvalidBeforeInput", "inputExecutionBusy"] {
            let (_, request) = try await fixture(), original = try envelope(request)
            let packet = try mutate(original) { root in
                var item = root["observation"] as! [String: Any]
                var proof = item["preInputRetirement"] as! [String: Any]
                item["belongsToOriginalDraft"] = false
                proof["reason"] = reason
                item["preInputRetirement"] = proof; root["observation"] = item
            }
            let bridge = PreInputRetirementBridge(request: request,
                packet: try JSONEncoder().encode(packet), expectedBytes: png)
            do { _ = try await adapter(bridge).append(request); XCTFail("No-input retirement was lost") }
            catch let rejection as PreInputRejection {
                XCTAssertEqual(rejection.operationID, request.operation.id)
                XCTAssertEqual(rejection.invocationID, request.invocationID)
                XCTAssertEqual(rejection.stage, .pageRetiredBeforeFileInput)
                XCTAssertEqual(rejection.reason, reason)
            }
            let actions = await bridge.actions()
            XCTAssertEqual(actions.filter { $0 == .commit }.count, 1)
        }
    }

    func testAttachmentDiscoveryFailuresRetainTheirExecutionReasonAndPermitNoReplay() async throws {
        for reason in ["attachmentEntryUnavailable", "attachmentInputNotCreated", "attachmentInputAmbiguous", "attachmentEntryFailed"] {
            let (store, request) = try await fixture(), original = try envelope(request)
            let packet = try mutate(original) { root in
                var item = root["observation"] as! [String: Any]
                var proof = item["preInputRetirement"] as! [String: Any]
                proof["reason"] = reason
                item["preInputRetirement"] = proof; root["observation"] = item
            }
            let bridge = PreInputRetirementBridge(request: request,
                packet: try JSONEncoder().encode(packet), expectedBytes: png)
            let client = adapter(bridge)
            do { _ = try await client.append(request); XCTFail("A failed discovery cannot claim an input") }
            catch let rejection as PreInputRejection {
                XCTAssertEqual(rejection.reason, reason)
                XCTAssertEqual(rejection.stage, .pageRetiredBeforeFileInput)
                try await store.recordPreInputRejection(rejection)
            }
            let record = try await store.asset(id: request.asset.id)
            let persisted = try await store.operationReason(for: request.operation.id)
            let start = try await store.uploadStartReceipt(for: request.operation.id)
            XCTAssertEqual(record?.visibility, .visible)
            XCTAssertEqual(record?.status, .failed)
            XCTAssertEqual(persisted, "Verified pre-input rejection: pageRetiredBeforeFileInput: " + reason)
            XCTAssertNil(start)
            let before = await bridge.actions()
            do { _ = try await client.append(request); XCTFail("The same invocation was submitted twice") }
            catch WebAdapterError.invalidRequest {}
            let after = await bridge.actions(), inputs = await bridge.actualInputs()
            XCTAssertEqual(before, after)
            XCTAssertEqual(inputs, 0)
            XCTAssertEqual(after.filter { $0 == .commit }.count, 1)
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
        let log = directory.appendingPathComponent("diagnostics")
        let trace = BoundedDiagnosticTrace(enabled: true, directory: log, emitStandardError: false)
        let client = adapter(bridge, diagnosticTrace: trace)
        // A read-only caller may retain a dispatchIntent snapshot after a lost
        // result. liveAppend, not that phase alone, owns no-input authority.
        let receipt = try await client.reconcile(request)
        XCTAssertEqual(receipt.outcome, .unknown); XCTAssertFalse(receipt.safeToRetry)
        _ = try await store.apply(receipt)
        let saved = try await store.operation(id: request.operation.id)
        let unknown = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset,
            fileURL: request.fileURL)
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
        trace.flushForTesting()
        let rows = try traceRows("acceptance-failures.jsonl", in: log)
        XCTAssertEqual(rows.count, 1, "The first post-restart retirement survives later read-only observations")
        XCTAssertEqual(rows.first?["retirementReason"] as? String, "inputHashMismatch")
        XCTAssertEqual(rows.first?["retirementObservationOnly"] as? Bool, true)
        XCTAssertEqual(rows.first?["entryDiagnosticsAvailable"] as? Bool, false)
        XCTAssertEqual(rows.first?["startObserved"] as? Bool, false)
        XCTAssertNil(rows.first?["setterEntered"], "Legacy replies never supplied this counter")
    }

    func testLostCommitReplyCanConfirmZeroInputDuringTheOriginalAppend() async throws {
        let (store, request) = try await fixture(), packet = try envelope(request)
        let bridge = PreInputRetirementBridge(request: request, packet: try JSONEncoder().encode(packet),
            expectedBytes: png, commitReply: .lostBeforeInput)
        let client = adapter(bridge)
        var rejection: PreInputRejection?
        do { _ = try await client.append(request); XCTFail("Current zero-input result was not reported") }
        catch let proof as PreInputRejection { rejection = proof }
        let proof = try XCTUnwrap(rejection)
        XCTAssertEqual(proof.invocationID, request.invocationID)
        XCTAssertEqual(proof.stage, .pageRetiredBeforeFileInput)
        try await store.recordPreInputRejection(proof)
        let operation = try await store.operation(id: request.operation.id)
        let asset = try await store.asset(id: request.asset.id)
        let actions = await bridge.actions(), inputs = await bridge.actualInputs()
        XCTAssertEqual(operation?.phase, .failed); XCTAssertEqual(asset?.visibility, .visible)
        XCTAssertEqual(actions, [.begin, .chunk, .commit, .observe])
        XCTAssertEqual(inputs, 0, "The commit command retired before entering the setter")
        do { _ = try await client.append(request); XCTFail("The original invocation was automatically replayed") }
        catch WebAdapterError.invalidRequest {}
        let afterReplay = await bridge.actions(), bytes = await bridge.receivedBytes()
        let start = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertEqual(afterReplay, actions); XCTAssertEqual(bytes, png); XCTAssertNil(start)
    }

    func testLostReplyAfterActualInputKeepsUnknownAndOnlyObserves() async throws {
        let (store, request) = try await fixture()
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        // The setter ran, but no current attachment START can yet be identified.
        // Such an operation never carries a zero-input retirement.
        let packet = AttachmentObservationEnvelope(schemaVersion: 1,
            provenance: .init(source: .syntheticFixture, evidenceID: "input-occurred-start-unknown"),
            observation: .init(identity: identity, state: .unknown, belongsToOriginalDraft: true))
        var summary = entrySummary
        summary["stage"] = "setter"; summary["setterEntered"] = true; summary["cause"] = "deliveryUncertain"
        let bridge = PreInputRetirementBridge(request: request, packet: try withEntrySummary(packet, summary),
            expectedBytes: png, commitReply: .lostAfterInput)
        let log = directory.appendingPathComponent("diagnostics")
        let trace = BoundedDiagnosticTrace(enabled: true, directory: log, emitStandardError: false)
        let client = adapter(bridge, diagnosticTrace: trace)
        let receipt = try await client.append(request)
        XCTAssertEqual(receipt.outcome, .unknown); XCTAssertFalse(receipt.safeToRetry)
        XCTAssertEqual(receipt.operationID, request.operation.id); XCTAssertEqual(receipt.target, request.operation.target)
        _ = try await store.apply(receipt)
        let saved = try await store.operation(id: request.operation.id)
        let unknown = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset,
            fileURL: request.fileURL, invocationID: request.invocationID)
        XCTAssertEqual(unknown.operation.phase, .unknown)
        let initialActions = await bridge.actions(), initialInputs = await bridge.actualInputs()
        XCTAssertEqual(initialActions, [.begin, .chunk, .commit, .observe]); XCTAssertEqual(initialInputs, 1)
        let observed = try await client.reconcile(unknown)
        XCTAssertEqual(observed.outcome, .unknown); XCTAssertFalse(observed.safeToRetry)
        _ = try await store.apply(observed)
        let selected = try await store.prepare(assetID: request.asset.id, target: freshTarget(request.operation.target))
        XCTAssertEqual(selected.id, request.operation.id); XCTAssertEqual(selected.phase, .unknown)
        do { _ = try await client.append(request); XCTFail("Already-entered input replayed") }
        catch WebAdapterError.invalidRequest {}
        let actions = await bridge.actions(), inputs = await bridge.actualInputs(), bytes = await bridge.receivedBytes()
        XCTAssertEqual(actions, initialActions + [.observe]); XCTAssertEqual(inputs, 1); XCTAssertEqual(bytes, png)
        let audit = try await store.checkpoint(for: "transfer-no-input-v1:" + request.operation.id.uuidString)
        let start = try await store.uploadStartReceipt(for: request.operation.id)
        let asset = try await store.asset(id: request.asset.id)
        XCTAssertNil(audit); XCTAssertNil(start); XCTAssertEqual(asset?.visibility, .visible)
        trace.flushForTesting()
        let rows = try traceRows("acceptance-failures.jsonl", in: log).filter { $0["event"] as? String == "attachment_entry_result" }
        XCTAssertEqual(rows.count, 1, "Repeated read-only observations retain one unchanged failure")
        XCTAssertEqual(rows.first?["entryCause"] as? String, "deliveryUncertain")
        XCTAssertEqual(rows.first?["setterEntered"] as? Bool, true)
        XCTAssertEqual(rows.first?["startObserved"] as? Bool, false); XCTAssertNil(rows.first?["retirementReason"])
    }

    func testWrongInvocationStaysUnknownDespiteLateRetirement() async throws {
        let (store, request) = try await fixture(), correct = try envelope(request)
        let packet = try mutate(correct) { root in
            var item = root["observation"] as! [String: Any], proof = item["preInputRetirement"] as! [String: Any]
            proof["invocationID"] = UUID().uuidString; item["preInputRetirement"] = proof; root["observation"] = item
        }
        let bridge = PreInputRetirementBridge(request: request, packet: try JSONEncoder().encode(packet), expectedBytes: png)
        let client = adapter(bridge)
        do { _ = try await client.append(request); XCTFail("Wrong-invocation commit response accepted") }
        catch ObservationError.identityMismatch {}
        try await store.markUnknown(request.operation.id, reason: "Constructed wrong-invocation commit result")
        let saved = try await store.operation(id: request.operation.id)
        let unknown = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset,
            fileURL: request.fileURL, invocationID: request.invocationID)
        let late = try await client.reconcile(unknown)
        XCTAssertEqual(late.outcome, .unknown); XCTAssertFalse(late.safeToRetry)
        _ = try await store.apply(late)
        let proof = try XCTUnwrap(WebPreInputRetirement.rejection(from: correct, for: request))
        do { try await store.recordPreInputRejection(proof); XCTFail("Late proof healed persisted UNKNOWN") }
        catch RiftletError.mismatchedReceipt {}
        let selected = try await store.prepare(assetID: request.asset.id, target: freshTarget(request.operation.target))
        XCTAssertEqual(selected.id, request.operation.id); XCTAssertEqual(selected.phase, .unknown)
        do { _ = try await client.append(request); XCTFail("Uncertain invocation replayed") }
        catch WebAdapterError.invalidRequest {}
        let actions = await bridge.actions(), bytes = await bridge.receivedBytes(), inputs = await bridge.actualInputs()
        XCTAssertEqual(actions, [.begin, .chunk, .commit, .observe]); XCTAssertEqual(bytes, png); XCTAssertEqual(inputs, 0)
        let audit = try await store.checkpoint(for: "transfer-no-input-v1:" + request.operation.id.uuidString)
        let start = try await store.uploadStartReceipt(for: request.operation.id)
        let asset = try await store.asset(id: request.asset.id)
        XCTAssertNil(audit); XCTAssertNil(start); XCTAssertEqual(asset?.visibility, .visible)
    }
}
