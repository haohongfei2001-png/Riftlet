import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class UploadStartObservationTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-start-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture(origin: AssetOrigin = .synthetic, pin: UUID? = nil) async throws -> (QueueStore, TransferRequest) {
        let store = try QueueStore(databaseURL: root.appendingPathComponent("\(UUID()).sqlite"))
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "fixture.png",
            sha256: String(repeating: "a", count: 64), byteCount: 100,
            pixelWidth: 4, pixelHeight: 4, mediaType: "image/png", origin: origin)
        _ = try await store.importAsset(asset)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "session", windowID: "window", tabID: "tab",
            documentID: "document", composerID: "composer", draftGeneration: "generation", clickBindingID: pin)
        let op = try await store.prepare(assetID: asset.id, target: target)
        try await store.markDispatchIntent(op.id)
        let saved = try await store.operation(id: op.id)
        return (store, TransferRequest(operation: try XCTUnwrap(saved), asset: asset,
                                      fileURL: root.appendingPathComponent(asset.fileName)))
    }
    private func normalizer(start: String? = "code-owned-start") -> ObservationNormalizer {
        .init(profile: .init(adapterID: "chatgpt-web", surface: .webChat,
            profileID: "code-owned-completion", completionSignal: .attached, uploadStartProfileID: start))
    }
    private func object(_ request: TransferRequest) throws -> [String: Any] {
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        let start = ObservedUploadStart(version: 1, signal: .correlatedProgress,
            evidenceID: UUID().uuidString, inputCount: 1, inputSequence: 1, startSequence: 4,
            previousProgress: 20, currentProgress: 40, inputObservedAtMS: 10, startObservedAtMS: 25)
        let item = AttachmentObservation(identity: identity, state: .uploadStarted, attachmentID: "original-card",
            exactImageIdentity: true, belongsToOriginalDraft: true, isUploading: true, uploadStart: start)
        let packet = AttachmentObservationEnvelope(schemaVersion: 2,
            provenance: .init(source: .integratedDevelopment, evidenceID: "W5-fixture-only"), observation: item)
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(packet)) as! [String: Any]
    }
    private func decode(_ value: [String: Any]) throws -> AttachmentObservationEnvelope {
        try ObservationDecoder.decode(JSONSerialization.data(withJSONObject: value))
    }

    func testPinnedInputStartAndCompletionRoundTripWithoutLosingCapabilityIdentity() async throws {
        let (store, request) = try await fixture(pin: UUID())
        for state in [AttachmentObservedState.inputTriggered, .uploadStarted, .attached] {
            var raw = try object(request)
            var item = raw["observation"] as! [String: Any]
            item["state"] = state.rawValue
            item["isUploading"] = state == .uploadStarted
            if state != .uploadStarted { item.removeValue(forKey: "uploadStart") }
            raw["observation"] = item
            let packet = try decode(raw), receipt = try normalizer().receipt(from: packet, for: request)
            XCTAssertEqual(packet.observation.identity.target, request.operation.target)
            XCTAssertEqual(receipt.target, request.operation.target)
            XCTAssertEqual(receipt.outcome, state == .inputTriggered ? .inputTriggered : state == .uploadStarted ? .uploadStarted : .verifiedReady)
            var identity = item["identity"] as! [String: Any]
            var target = identity["target"] as! [String: Any]
            target["clickBindingID"] = UUID().uuidString
            identity["target"] = target; item["identity"] = identity; raw["observation"] = item
            XCTAssertThrowsError(try normalizer().receipt(from: decode(raw), for: request))
            target["clickBindingID"] = "malformed"
            identity["target"] = target; item["identity"] = identity; raw["observation"] = item
            XCTAssertThrowsError(try decode(raw))
        }
        let saved = try await store.operation(id: request.operation.id)
        XCTAssertEqual(saved?.target, request.operation.target)
    }

    func testStartMappingAndAdmissionAreIndependentAndPreserveFirstAudit() async throws {
        let (store, request) = try await fixture()
        let packet = try decode(object(request))
        let start = try normalizer().receipt(from: packet, for: request)
        XCTAssertEqual(start.outcome, .uploadStarted)
        XCTAssertEqual(start.uploadStartEvidence?.profileID, "code-owned-start")
        XCTAssertFalse(start.positiveReady); XCTAssertFalse(start.safeToRetry)
        let denied = try await store.apply(start)
        XCTAssertEqual(denied.visibility, .visible); XCTAssertEqual(denied.status, .unknown)
        let noAudit = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertNil(noAudit)
        let policy = ReceiptPolicy(syntheticAcceptanceProfiles: ["code-owned-completion": .webChat],
                                   syntheticUploadStartProfiles: ["code-owned-start": .webChat])
        let accepted = try await store.apply(start, policy: policy)
        XCTAssertEqual(accepted.visibility, .swallowed); XCTAssertNotEqual(accepted.status, .used)
        try await store.markUnknown(request.operation.id, reason: "fixture observation lost")
        let hiddenUnknown = try await store.asset(id: request.asset.id)
        XCTAssertEqual(hiddenUnknown?.visibility, .swallowed)
        let audit = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertEqual(audit, start)
        let noProfile = try normalizer(start: nil).receipt(from: packet, for: request)
        XCTAssertEqual(noProfile.outcome, .inputTriggered); XCTAssertNil(noProfile.uploadStartEvidence)
        var wrong = try object(request), wrongItem = wrong["observation"] as! [String: Any]
        wrongItem["attachmentID"] = "later-card"; wrong["observation"] = wrongItem
        let wrongStart = try normalizer().receipt(from: decode(wrong), for: request)
        do { _ = try await store.apply(wrongStart, policy: policy); XCTFail("Start moved to another attachment") }
        catch RiftletError.mismatchedReceipt {}
        var final = try object(request), finalItem = final["observation"] as! [String: Any]
        finalItem["state"] = "attached"; finalItem["isUploading"] = false
        finalItem.removeValue(forKey: "uploadStart"); final["observation"] = finalItem
        let ready = try normalizer().receipt(from: decode(final), for: request)
        _ = try await store.apply(ready, policy: policy)
        let succeeded = try await store.operation(id: request.operation.id)
        let old = TransferRequest(operation: try XCTUnwrap(succeeded), asset: request.asset, fileURL: request.fileURL)
        let replayedStart = try normalizer().receipt(from: packet, for: old)
        XCTAssertEqual(replayedStart.outcome, .unknown); XCTAssertNil(replayedStart.uploadStartEvidence)
    }

    func testLegacyAndPayloadPermissionsCannotBecomeStart() async throws {
        let (_, request) = try await fixture()
        let base = try object(request)
        var legacy = base; legacy["schemaVersion"] = 1
        XCTAssertThrowsError(try decode(legacy))
        for key in ["profileID", "outcome", "positiveReady", "safeToRetry"] {
            var forged = base
            var item = forged["observation"] as! [String: Any]; item[key] = "trusted"
            forged["observation"] = item
            XCTAssertThrowsError(try decode(forged))
        }
        var extra = base, item = base["observation"] as! [String: Any]
        var start = item["uploadStart"] as! [String: Any]; start["profileID"] = "trusted"
        item["uploadStart"] = start; extra["observation"] = item
        XCTAssertThrowsError(try decode(extra))
    }

    func testProgressSequenceTimeAndMembershipCounterexamplesReject() async throws {
        let (_, request) = try await fixture(); let base = try object(request)
        let bad: [(String, Any)] = [("inputCount", 2), ("inputCount", true), ("version", 2),
            ("startSequence", 1), ("inputSequence", 0), ("previousProgress", 40),
            ("currentProgress", 100), ("currentProgress", -1), ("startObservedAtMS", 10),
            ("inputObservedAtMS", -1), ("signal", "correlatedByteRequest"), ("evidenceID", "")]
        for (key, value) in bad {
            var changed = base, item = base["observation"] as! [String: Any]
            var start = item["uploadStart"] as! [String: Any]; start[key] = value
            item["uploadStart"] = start; changed["observation"] = item
            XCTAssertThrowsError(try decode(changed), key)
        }
        for (key, value) in [("hasError", true), ("isUploading", false), ("exactImageIdentity", false),
                             ("belongsToOriginalDraft", false), ("attachmentAbsent", true), ("automaticRetryExcluded", true)] {
            var changed = base, item = base["observation"] as! [String: Any]
            item[key] = value; changed["observation"] = item
            XCTAssertThrowsError(try decode(changed), key)
        }
        for value in [NSNull(), [:] as [String: Any]] as [Any] {
            var changed = base, item = base["observation"] as! [String: Any]
            item["uploadStart"] = value; changed["observation"] = item
            XCTAssertThrowsError(try decode(changed))
        }
    }

    func testWrongIdentityAndRealImageCannotUseSyntheticStart() async throws {
        let (_, request) = try await fixture(); let base = try object(request)
        for key in ["operationID", "assetID", "attempt", "assetSHA256", "target"] {
            var changed = base, item = base["observation"] as! [String: Any]
            var identity = item["identity"] as! [String: Any]
            switch key {
            case "attempt": identity[key] = request.operation.attempt + 1
            case "assetSHA256": identity[key] = String(repeating: "b", count: 64)
            case "target":
                var target = identity[key] as! [String: Any]; target["draftGeneration"] = "later"
                identity[key] = target
            default: identity[key] = UUID().uuidString
            }
            item["identity"] = identity; changed["observation"] = item
            XCTAssertThrowsError(try normalizer().receipt(from: decode(changed), for: request)) {
                XCTAssertEqual($0 as? ObservationError, .identityMismatch)
            }
        }
        let (_, real) = try await fixture(origin: .systemScreenshot)
        XCTAssertThrowsError(try normalizer().receipt(from: decode(object(real)), for: real)) {
            XCTAssertEqual($0 as? ObservationError, .syntheticEvidenceForRealAsset)
        }
    }
}
