import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Protocol counterexamples, not a new real-platform acceptance claim. Every
/// fixture has its own isolated SQLite file and original dispatch invocation.
final class IndependentAttachmentObservationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-input-isolation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func request() async throws -> TransferRequest {
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "fixture.png",
            sha256: String(repeating: "a", count: 64), byteCount: 128, pixelWidth: 32, pixelHeight: 24,
            mediaType: "image/png", origin: .synthetic)
        _ = try await store.importAsset(asset)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "session", windowID: "window", tabID: "tab", documentID: "document",
            composerID: "composer", draftGeneration: "draft")
        let operation = try await store.prepare(assetID: asset.id, target: target)
        let invocation = try await store.markDispatchIntent(operation.id)
        let saved = try await store.operation(id: operation.id)
        return TransferRequest(operation: try XCTUnwrap(saved), asset: asset,
            fileURL: URL(fileURLWithPath: "/not-opened-fixture.png"), invocationID: invocation)
    }

    private var profile: ObservationProfile {
        .init(adapterID: "chatgpt-web", surface: .webChat, profileID: "isolated-fixture",
            completionSignal: .attached, uploadStartProfileID: "isolated-start",
            continuationProfileID: "isolated-input-ownership")
    }

    private func packet(_ request: TransferRequest, transport: String = "xhr", response: Bool = false) throws -> [String: Any] {
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        let rawIdentity = try JSONSerialization.jsonObject(with: JSONEncoder().encode(identity)) as! [String: Any]
        var binding = rawIdentity
        binding["version"] = 1; binding["invocationID"] = request.invocationID!.uuidString
        binding["attachmentID"] = "original-attachment"
        let startID = UUID().uuidString
        let start: [String: Any] = ["version": 1, "signal": "correlatedProgress", "evidenceID": startID,
            "inputCount": 1, "inputSequence": 1, "startSequence": 5, "previousProgress": 10,
            "currentProgress": 30, "inputObservedAtMS": 10, "startObservedAtMS": 50]
        let isolation: [String: Any] = ["version": 1, "ownershipID": "document:request:7",
            "inputElementID": "document:input:3", "kind": "originalRequestBodyOwned",
            "requestID": 7, "requestSequence": 3, "requestTransport": transport,
            "originalSHA256": request.asset.sha256, "originalByteCount": request.asset.byteCount,
            "startEvidenceID": startID, "inputSequence": 1, "callSettledSequence": 4,
            "startSequence": 5, "observedSequence": 8]
        var record: [String: Any] = ["requestID": 7, "transport": transport, "requestSequence": 3, "requestedAtMS": 30]
        if response {
            record["terminal"] = "response"; record["terminalSequence"] = 7
            record["terminalAtMS"] = 70; record["status"] = 200
        }
        let facts: [String: Any] = ["version": 1, "invocationID": request.invocationID!.uuidString,
            "inputCount": 1, "inputSequence": 1, "inputObservedAtMS": 10,
            "fileSHA256": request.asset.sha256, "coverage": "exactOriginalFileOnly",
            "observationClosed": false, "requests": [record]]
        return ["schemaVersion": 4, "provenance": ["source": "syntheticFixture", "evidenceID": "input-isolation-fixture"],
            "observation": ["identity": rawIdentity, "state": "uploadStarted", "attachmentID": "original-attachment",
                "exactImageIdentity": true, "belongsToOriginalDraft": true, "hasError": false,
                "isUploading": true, "attachmentAbsent": false, "automaticRetryExcluded": false,
                "uploadStart": start, "requestEvidence": facts,
                "continuationEvidence": ["version": 1, "evidenceID": "original-input-ownership",
                    "binding": binding, "inputIsolation": isolation]]]
    }

    private func decode(_ packet: [String: Any]) throws -> AttachmentObservationEnvelope {
        try ObservationDecoder.decode(JSONSerialization.data(withJSONObject: packet))
    }

    private func mutate(_ packet: [String: Any], _ body: (inout [String: Any]) -> Void) -> [String: Any] {
        var result = packet
        var item = result["observation"] as! [String: Any]
        body(&item); result["observation"] = item
        return result
    }

    private func changeIsolation(_ packet: [String: Any], _ body: (inout [String: Any]) -> Void) -> [String: Any] {
        mutate(packet) { item in
            var proof = item["continuationEvidence"] as! [String: Any]
            var isolation = proof["inputIsolation"] as! [String: Any]
            body(&isolation); proof["inputIsolation"] = isolation; item["continuationEvidence"] = proof
        }
    }

    func testOriginalOwnedRequestProducesOnlyLiveContinuationAndNoCompletionOrRetry() async throws {
        let request = try await request()
        for transport in ["xhr", "fetch"] {
            for response in [false, true] {
                let envelope = try decode(packet(request, transport: transport, response: response))
                let receipt = try ObservationNormalizer(profile: profile).receipt(from: envelope, for: request, liveAppend: true)
                XCTAssertEqual(receipt.outcome, .uploadStarted)
                XCTAssertEqual(receipt.continuationEvidence?.version, 3)
                XCTAssertEqual(receipt.continuationEvidence?.binding?.invocationID, request.invocationID)
                XCTAssertEqual(receipt.continuationEvidence?.inputIsolation?.requestID, 7)
                XCTAssertNil(receipt.continuationEvidence?.taskIsolation)
                XCTAssertNil(receipt.completionEvidence); XCTAssertNil(receipt.terminationEvidence)
                XCTAssertFalse(receipt.positiveReady); XCTAssertFalse(receipt.safeToRetry)
            }
        }
    }

    func testObservationAndReconcileCannotMintContinuation() async throws {
        let request = try await request(), envelope = try decode(packet(request))
        XCTAssertNil(try ObservationNormalizer(profile: profile).receipt(from: envelope, for: request).continuationEvidence)
        let resumed = TransferRequest(operation: request.operation, asset: request.asset, fileURL: request.fileURL)
        XCTAssertNil(try ObservationNormalizer(profile: profile).receipt(from: envelope, for: resumed, liveAppend: true).continuationEvidence)
        for continuation in [nil, "", String(repeating: "x", count: 129)] as [String?] {
            let absent = ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
                profileID: "isolated-fixture", uploadStartProfileID: "isolated-start", continuationProfileID: continuation)
            XCTAssertNil(try ObservationNormalizer(profile: absent).receipt(from: envelope, for: request, liveAppend: true).continuationEvidence)
        }
    }

    func testInputOwnershipCannotBorrowAnotherRequestOrStart() async throws {
        let request = try await request(), original = try packet(request)
        let changes: [(String, Any)] = [("requestID", 8), ("requestSequence", 2), ("requestTransport", "fetch"),
            ("originalSHA256", String(repeating: "b", count: 64)), ("originalByteCount", 0),
            ("startEvidenceID", UUID().uuidString), ("inputSequence", 2), ("startSequence", 6),
            ("callSettledSequence", 1), ("observedSequence", 4), ("ownershipID", ""),
            ("inputElementID", ""), ("version", 2), ("kind", "independentTaskSurvivesSubsequentInput"),
            ("platformTaskID", "invented-platform-id")]
        for (field, value) in changes {
            XCTAssertThrowsError(try decode(changeIsolation(original) { $0[field] = value }), field)
        }
        // A later original-File request cannot retroactively explain an earlier
        // upload START, even when the echoed request fields agree with it.
        let lateRequest = mutate(changeIsolation(original) { $0["requestSequence"] = 6 }) { item in
            var facts = item["requestEvidence"] as! [String: Any]
            var records = facts["requests"] as! [[String: Any]]
            records[0]["requestSequence"] = 6; facts["requests"] = records; item["requestEvidence"] = facts
        }
        XCTAssertThrowsError(try decode(lateRequest))
    }

    func testMissingClosedRepeatedOrFailedRequestNeverGrantsInputOwnership() async throws {
        let request = try await request(), original = try packet(request)
        for scenario in ["missing", "closed", "repeated", "invocation", "inputSequence", "inputTime", "hash", "requestTime", "aborted", "rejected", "error", "timeout", "threw", "futureTerminal", "futureProgress"] {
            let changed = mutate(original) { item in
                if scenario == "missing" { item.removeValue(forKey: "requestEvidence"); return }
                var facts = item["requestEvidence"] as! [String: Any]
                var requests = facts["requests"] as! [[String: Any]]
                switch scenario {
                case "closed": facts["observationClosed"] = true; facts["closeReason"] = "hookReplaced"
                case "repeated":
                    var second = requests[0]; second["requestID"] = 8; requests.append(second)
                case "invocation": facts["invocationID"] = UUID().uuidString
                case "inputSequence": facts["inputSequence"] = 2
                case "inputTime": facts["inputObservedAtMS"] = 11
                case "hash": facts["fileSHA256"] = String(repeating: "c", count: 64)
                case "requestTime": requests[0]["requestedAtMS"] = 9
                case "futureProgress": requests[0]["progress"] = ["loaded": 32, "total": 128,
                    "lengthComputable": true, "sequence": 9, "observedAtMS": 90]
                default:
                    requests[0]["terminal"] = scenario == "futureTerminal" ? "response" : scenario
                    requests[0]["terminalSequence"] = scenario == "futureTerminal" ? 9 : 7
                    requests[0]["terminalAtMS"] = 70; requests[0]["status"] = scenario == "futureTerminal" ? 200 : 0
                }
                facts["requests"] = requests; item["requestEvidence"] = facts
            }
            XCTAssertThrowsError(try decode(changed), scenario)
        }
    }

    func testExactlyOneIsolationVariantIsRequiredAndNullIsNotAProof() async throws {
        let request = try await request(), original = try packet(request)
        for scenario in ["neither", "null", "both"] {
            let changed = mutate(original) { item in
                var proof = item["continuationEvidence"] as! [String: Any]
                if scenario == "neither" { proof.removeValue(forKey: "inputIsolation") }
                else if scenario == "null" { proof["inputIsolation"] = NSNull() }
                else { proof["taskIsolation"] = [:] as [String: Any] }
                item["continuationEvidence"] = proof
            }
            XCTAssertThrowsError(try decode(changed), scenario)
        }
    }

    func testLateReceiptAndWrongOriginalBytesCannotBeAssignedToNextOperation() async throws {
        let first = try await request(), second = try await request(), original = try packet(first)
        XCTAssertThrowsError(try ObservationNormalizer(profile: profile).receipt(from: decode(original), for: second, liveAppend: true))
        let wrongBytes = changeIsolation(original) { $0["originalByteCount"] = 129 }
        XCTAssertThrowsError(try ObservationNormalizer(profile: profile).receipt(from: decode(wrongBytes), for: first, liveAppend: true))
        let wrongInvocation = TransferRequest(operation: first.operation, asset: first.asset, fileURL: first.fileURL, invocationID: UUID())
        XCTAssertThrowsError(try ObservationNormalizer(profile: profile).receipt(from: decode(original), for: wrongInvocation, liveAppend: true))
        for state in ["unknown", "invalidated", "attached", "failed"] {
            let changed = mutate(original) { $0["state"] = state }
            XCTAssertThrowsError(try decode(changed), state)
        }
    }

    func testCompletionProofAbsenceIsAnHonestUnknownWithBoundedReason() async throws {
        let request = try await request(), original = try packet(request)
        let reasons = ["previewDimensionsUnproven", "previewPixelsUnproven", "previewProofUnavailable", "previewChanged",
            "attachmentRemoved", "attachmentReplaced", "attachmentIdentityChanged", "repeatedInput",
            "originalTargetInvalidated", "attachmentError"]
        for reason in reasons {
            let unknown = mutate(original) { item in
                item["state"] = "unknown"; item["isUploading"] = false; item["reason"] = reason
                item.removeValue(forKey: "uploadStart"); item.removeValue(forKey: "continuationEvidence")
            }
            let receipt = try ObservationNormalizer(profile: profile).receipt(from: decode(unknown), for: request, liveAppend: true)
            XCTAssertEqual(receipt.outcome, .unknown)
            XCTAssertTrue(receipt.reason.hasSuffix(":" + reason))
            XCTAssertFalse(receipt.safeToRetry); XCTAssertFalse(receipt.positiveReady)
            XCTAssertNil(receipt.continuationEvidence); XCTAssertNil(receipt.terminationEvidence)
            XCTAssertEqual(receipt.operationID, request.operation.id)
        }
        XCTAssertThrowsError(try decode(mutate(original) { $0["reason"] = "arbitrary private page text" }))
    }
}
