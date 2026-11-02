import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Synthetic contracts only. These fixtures do not describe a ChatGPT response
/// schema or assert that the service implements the supplied terminal semantics.
final class AttachmentEvidenceV4Tests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-proof-v4-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func fixture() async throws -> (QueueStore, TransferRequest) {
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "fixture.png",
            sha256: String(repeating: "a", count: 64), byteCount: 128, pixelWidth: 32, pixelHeight: 24,
            mediaType: "image/png", origin: .synthetic)
        _ = try await store.importAsset(asset)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "session", windowID: "window", tabID: "tab", documentID: "document",
            composerID: "composer", draftGeneration: "draft")
        let op = try await store.prepare(assetID: asset.id, target: target)
        let invocation = try await store.markDispatchIntent(op.id)
        let saved = try await store.operation(id: op.id)
        return (store, TransferRequest(operation: try XCTUnwrap(saved), asset: asset,
            fileURL: URL(fileURLWithPath: "/not-opened-fixture.png"), invocationID: invocation))
    }

    private func binding(_ request: TransferRequest) throws -> AttachmentOperationBinding {
        .init(operationID: request.operation.id, assetID: request.asset.id, attempt: request.operation.attempt,
              assetSHA256: request.asset.sha256, target: request.operation.target,
              invocationID: try XCTUnwrap(request.invocationID), attachmentID: "original-attachment")
    }
    private func identity(_ request: TransferRequest) -> ObservationIdentity {
        .init(operationID: request.operation.id, assetID: request.asset.id, attempt: request.operation.attempt,
              assetSHA256: request.asset.sha256, target: request.operation.target)
    }
    private func packet(_ item: AttachmentObservation) -> AttachmentObservationEnvelope {
        .init(schemaVersion: 4, provenance: .init(source: .syntheticFixture, evidenceID: "v4-contract-fixture"), observation: item)
    }
    private func normalize(_ envelope: AttachmentObservationEnvelope, _ request: TransferRequest,
                           profile: ObservationProfile? = nil, live: Bool = false) throws -> TransferReceipt {
        try ObservationNormalizer(profile: profile ?? .init(adapterID: "chatgpt-web", surface: .webChat,
            profileID: "fixture-v4", completionSignal: .attached, uploadStartProfileID: "fixture-start"))
            .receipt(from: ObservationDecoder.decode(JSONEncoder().encode(envelope)), for: request, liveAppend: live)
    }
    private func complete(_ request: TransferRequest, pixels: Bool = false) throws -> AttachmentObservationEnvelope {
        let proof = AttachmentCompletionEvidence(evidenceID: UUID().uuidString, binding: try binding(request),
            kind: pixels ? .exactSRGBPixels : .exactOriginalBytes,
            originalByteCount: request.asset.byteCount, originalSHA256: request.asset.sha256,
            observedByteCount: pixels ? nil : request.asset.byteCount, observedSHA256: pixels ? nil : request.asset.sha256,
            originalWidth: pixels ? 32 : nil, originalHeight: pixels ? 24 : nil,
            originalPixelSHA256: pixels ? String(repeating: "b", count: 64) : nil,
            previewWidth: pixels ? 32 : nil, previewHeight: pixels ? 24 : nil,
            previewPixelSHA256: pixels ? String(repeating: "b", count: 64) : nil)
        return packet(.init(identity: identity(request), state: .attached, attachmentID: "original-attachment",
            exactImageIdentity: true, belongsToOriginalDraft: true, completionEvidence: proof))
    }
    private func mutate(_ packet: AttachmentObservationEnvelope, _ body: (inout [String: Any]) -> Void) throws -> Data {
        var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(packet)) as! [String: Any]
        var observation = root["observation"] as! [String: Any]
        body(&observation); root["observation"] = observation
        return try JSONSerialization.data(withJSONObject: root)
    }
    func testVersionedExactBytesAndPixelsReachOriginalDurableOperation() async throws {
        for pixels in [false, true] {
            let (store, request) = try await fixture()
            let receipt = try normalize(complete(request, pixels: pixels), request)
            let saved = try await store.apply(receipt, policy: .init(syntheticAcceptanceProfiles: ["fixture-v4": .webChat]))
            XCTAssertEqual(saved.status, .used)
            XCTAssertNotNil(receipt.completionEvidence)
            let persisted = try await store.receipt(for: request.operation.id)
            XCTAssertEqual(persisted?.completionEvidence, receipt.completionEvidence)
        }
    }
    func testScaledPreviewCannotBorrowEqualPixelHashAndWrongInvocationCannotComplete() async throws {
        let (_, request) = try await fixture()
        for field in ["previewWidth", "originalPixelSHA256", "invocationID", "attachmentID", "attempt", "unexpectedApproval"] {
            let data = try mutate(complete(request, pixels: true)) { item in
                var proof = item["completionEvidence"] as! [String: Any]
                if ["invocationID", "attachmentID", "attempt"].contains(field) {
                    var bound = proof["binding"] as! [String: Any]
                    bound[field] = field == "attempt" ? 2 : field == "attachmentID" ? "other-attachment" : UUID().uuidString
                    proof["binding"] = bound
                } else { proof[field] = field == "previewWidth" ? 16 : field == "unexpectedApproval" ? true : String(repeating: "c", count: 64) }
                item["completionEvidence"] = proof
            }
            XCTAssertThrowsError(try ObservationNormalizer(profile: .init(adapterID: "chatgpt-web", surface: .webChat,
                profileID: "fixture-v4", completionSignal: .attached)).receipt(from: ObservationDecoder.decode(data), for: request), field)
        }
    }
    func testExactOriginalRequestHTTP200AndAbortAreOnlyFacts() async throws {
        let (_, request) = try await fixture()
        for terminal in ["response", "aborted"] {
            let raw: [String: Any] = ["version": 1, "invocationID": request.invocationID!.uuidString,
                "inputCount": 1, "inputSequence": 1, "inputObservedAtMS": 1,
                "fileSHA256": request.asset.sha256, "coverage": "exactOriginalFileOnly",
                "observationClosed": false, "requests": [["requestID": 1, "transport": "xhr",
                    "requestSequence": 2, "requestedAtMS": 2, "terminal": terminal, "terminalSequence": 4,
                    "terminalAtMS": 4, "status": terminal == "response" ? 200 : 0,
                    "progress": ["loaded": 128, "total": 128, "lengthComputable": true, "sequence": 3, "observedAtMS": 3]]]]
            let facts = try JSONDecoder().decode(ObservedRequestEvidence.self, from: JSONSerialization.data(withJSONObject: raw))
            let receipt = try normalize(packet(.init(identity: identity(request), state: .inputTriggered,
                belongsToOriginalDraft: true, requestEvidence: facts)), request)
            XCTAssertEqual(receipt.outcome, .inputTriggered)
            XCTAssertNil(receipt.completionEvidence); XCTAssertNil(receipt.terminationEvidence)
            XCTAssertNil(receipt.continuationEvidence); XCTAssertFalse(receipt.safeToRetry)
            let bad = try mutate(packet(.init(identity: identity(request), state: .inputTriggered,
                belongsToOriginalDraft: true, requestEvidence: facts))) { item in
                var evidence = item["requestEvidence"] as! [String: Any]
                var records = evidence["requests"] as! [[String: Any]]
                var progress = records[0]["progress"] as! [String: Any]
                progress["sequence"] = 5; records[0]["progress"] = progress
                evidence["requests"] = records; item["requestEvidence"] = evidence
            }
            XCTAssertThrowsError(try ObservationDecoder.decode(bad))
        }
    }
    func testNewSchemaWithoutEvidenceAndUnknownVersionRemainRejected() async throws {
        let (_, request) = try await fixture()
        XCTAssertThrowsError(try ObservationDecoder.decode(JSONEncoder().encode(packet(
            .init(identity: identity(request), state: .attached, attachmentID: "original-attachment",
                  exactImageIdentity: true, belongsToOriginalDraft: true)))))
        let data = try mutate(complete(request)) { $0["completionEvidence"] = NSNull() }
        XCTAssertThrowsError(try ObservationDecoder.decode(data))
    }

    private func task(_ request: TransferRequest) -> PlatformAttachmentTaskIdentity {
        .init(requestID: "synthetic-request", taskID: "synthetic-task", attachmentReference: "synthetic-platform-file",
            originalSHA256: request.asset.sha256, originalByteCount: request.asset.byteCount)
    }

    func testSyntheticPlatformFinalizationNeedsItsOwnNativeProfileNotOrdinaryAdmission() async throws {
        let (store, request) = try await fixture()
        let proof = AttachmentCompletionEvidence(evidenceID: "synthetic-finalization-proof", binding: try binding(request),
            kind: .platformFinalizedOriginal, originalByteCount: request.asset.byteCount, originalSHA256: request.asset.sha256,
            platform: .init(task: task(request), finalizationID: "synthetic-finalization"))
        let envelope = packet(.init(identity: identity(request), state: .attached, attachmentID: "original-attachment",
            exactImageIdentity: true, belongsToOriginalDraft: true, completionEvidence: proof))
        let unadmitted = try normalize(envelope, request)
        XCTAssertEqual(unadmitted.outcome, .attachedCandidate)
        XCTAssertFalse(unadmitted.positiveReady)
        let pending = try await store.apply(unadmitted, policy: .init(syntheticAcceptanceProfiles: ["fixture-v4": .webChat]))
        XCTAssertNotEqual(pending.status, .used)
        let scoped = try normalize(envelope, request, profile: .init(adapterID: "chatgpt-web", surface: .webChat,
            profileID: "fixture-v4", completionSignal: .attached, platformCompletionProfileID: "fixture-v4"))
        XCTAssertEqual(scoped.profileID, "fixture-v4")
        let denied = try await store.apply(scoped, policy: .init(syntheticAcceptanceProfiles: ["fixture-v4": .webChat]))
        XCTAssertEqual(denied.status, .unknown)
        let accepted = try await store.apply(scoped, policy: .init(syntheticAcceptanceProfiles: ["fixture-v4": .webChat],
            platformCompletionProfiles: ["fixture-v4": .webChat]))
        XCTAssertEqual(accepted.status, .used)
    }

    func testTerminalProofKeepsOriginalAttachmentAndCannotBeGrantedByHTTPFailure() async throws {
        let (store, request) = try await fixture()
        let proof = ObservedAttachmentTermination(version: 1, evidenceID: "synthetic-retirement-proof",
            binding: try binding(request), task: task(request), retirementID: "synthetic-irrevocable-tombstone",
            kind: .irreversibleRetirementNoAutomaticRetry)
        let envelope = packet(.init(identity: identity(request), state: .failed, attachmentID: "original-attachment",
            exactImageIdentity: true, belongsToOriginalDraft: true, hasError: true, attachmentAbsent: true,
            automaticRetryExcluded: true, terminationEvidence: proof))
        let unadmitted = try normalize(envelope, request)
        XCTAssertEqual(unadmitted.outcome, .unknown); XCTAssertFalse(unadmitted.safeToRetry)
        let malformed = try mutate(envelope) { item in
            var proof = item["terminationEvidence"] as! [String: Any]
            var task = proof["task"] as! [String: Any]
            task["version"] = 2; proof["task"] = task; item["terminationEvidence"] = proof
        }
        XCTAssertThrowsError(try ObservationDecoder.decode(malformed))
        let scoped = try normalize(envelope, request, profile: .init(adapterID: "chatgpt-web", surface: .webChat,
            profileID: "fixture-v4", failureSignal: .terminalErrorAndNoResidual,
            terminationProfileID: "synthetic-retirement"))
        XCTAssertEqual(scoped.attachmentID, "original-attachment")
        XCTAssertEqual(scoped.terminationEvidence?.binding.invocationID, request.invocationID)
        let denied = try await store.apply(scoped, policy: .init(syntheticRetrySafeProfiles: ["fixture-v4": .webChat]))
        XCTAssertEqual(denied.status, .unknown)
        let accepted = try await store.apply(scoped, policy: .init(syntheticRetrySafeProfiles: ["fixture-v4": .webChat],
            terminationProfiles: ["synthetic-retirement": .webChat]))
        XCTAssertEqual(accepted.status, .failed)
        let op = try await store.operation(id: request.operation.id)
        XCTAssertEqual(op?.phase, .failed)
        // No input or prepared operation is created by applying the retirement.
        XCTAssertEqual(accepted.activeOperationID, request.operation.id)
    }

    func testContinuationOnlyProjectsDuringOriginalLiveAppendAndCannotBeFilledByReconcile() async throws {
        let (_, request) = try await fixture()
        let startID = UUID().uuidString
        let start = ObservedUploadStart(version: 1, signal: .correlatedProgress, evidenceID: startID,
            inputCount: 1, inputSequence: 1, startSequence: 4, previousProgress: 12, currentProgress: 36,
            inputObservedAtMS: 10, startObservedAtMS: 30)
        let proof = ObservedAttachmentContinuation(version: 1, evidenceID: "synthetic-continuation-proof",
            binding: try binding(request), taskIsolation: .init(task: task(request), ownershipID: "synthetic-independent-task",
                startEvidenceID: startID, inputSequence: 1, callSettledSequence: 2, startSequence: 4, observedSequence: 5))
        let envelope = packet(.init(identity: identity(request), state: .uploadStarted, attachmentID: "original-attachment",
            exactImageIdentity: true, belongsToOriginalDraft: true, isUploading: true, uploadStart: start, continuationEvidence: proof))
        let profile = ObservationProfile(adapterID: "chatgpt-web", surface: .webChat, profileID: "fixture-v4",
            uploadStartProfileID: "fixture-start", continuationProfileID: "synthetic-independent")
        XCTAssertNil(try normalize(envelope, request).continuationEvidence)
        XCTAssertNil(try normalize(envelope, request, profile: profile).continuationEvidence)
        let receipt = try normalize(envelope, request, profile: profile, live: true)
        XCTAssertEqual(receipt.continuationEvidence?.version, 2)
        XCTAssertEqual(receipt.continuationEvidence?.binding?.target, request.operation.target)
        let resumed = TransferRequest(operation: request.operation, asset: request.asset, fileURL: request.fileURL)
        XCTAssertNil(try normalize(envelope, resumed, profile: profile, live: true).continuationEvidence)
        for field in ["startEvidenceID", "inputSequence", "version", "callSettledSequence", "ownershipID"] {
            let data = try mutate(envelope) { item in
                var proof = item["continuationEvidence"] as! [String: Any]
                var isolation = proof["taskIsolation"] as! [String: Any]
                switch field {
                case "inputSequence": isolation[field] = 3
                case "version": isolation[field] = 2
                case "callSettledSequence": isolation[field] = 1
                case "ownershipID": isolation[field] = ""
                default: isolation[field] = UUID().uuidString
                }
                proof["taskIsolation"] = isolation; item["continuationEvidence"] = proof
            }
            XCTAssertThrowsError(try ObservationDecoder.decode(data))
        }
    }
}
