import Foundation
import XCTest
@testable import RiftletCore

final class ReceiptBackwardCompatibilityTests: XCTestCase {
    private func receipt(signal: UploadStartSignal = .attachmentAccepted) -> TransferReceipt {
        .init(operationID: UUID(), assetID: UUID(), attempt: 1, assetSHA256: String(repeating: "a", count: 64),
            target: .init(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
                sessionID: "synthetic-process", windowID: "1", tabID: "1", documentID: "document",
                composerID: "composer", draftGeneration: "1", clickBindingID: UUID()),
            outcome: .uploadStarted, profileID: "synthetic-receipt", attachmentID: "new-attachment",
            belongsToOriginalDraft: true, isUploading: true, reason: "Synthetic acceptance",
            uploadStartEvidence: .init(profileID: "synthetic-acceptance", signal: signal, evidenceID: "acceptance-1"))
    }

    func testNewAcceptanceRoundTripsAndTheActualOldSignalDecoderCanReadIt() throws {
        let original = receipt(), bytes = try JSONEncoder().encode(original)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(fields["uploadStartEvidence"], "PR40 cannot decode the new enum case under its known key")
        let acceptance = try XCTUnwrap(fields["attachmentAcceptanceEvidence"] as? [String: Any])
        XCTAssertEqual(acceptance["signal"] as? String, "attachmentAccepted")
        XCTAssertEqual(try JSONDecoder().decode(TransferReceipt.self, from: bytes), original)
        var incompatible = fields
        incompatible["uploadStartEvidence"] = incompatible.removeValue(forKey: "attachmentAcceptanceEvidence")
        XCTAssertThrowsError(try JSONDecoder().decode(PR40Receipt.self,
            from: JSONSerialization.data(withJSONObject: incompatible)),
            "The frozen decoder must actually reject the new signal under its old key")

        // This decoder reproduces PR40's complete stored receipt shape, with a
        // frozen two-case signal enum. It does not share the extended new enum.
        let old = try JSONDecoder().decode(PR40Receipt.self, from: bytes)
        XCTAssertEqual(old.operationID, original.operationID)
        XCTAssertEqual(old.target, original.target)
        XCTAssertEqual(old.outcome, .uploadStarted)
        XCTAssertNil(old.uploadStartEvidence, "Rollback must not fabricate an old progress observation")
        XCTAssertFalse(old.safeToRetry)
        let oldRoundTrip = try JSONDecoder().decode(TransferReceipt.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(oldRoundTrip.operationID, original.operationID)
        XCTAssertEqual(oldRoundTrip.attachmentID, original.attachmentID)
        XCTAssertNil(oldRoundTrip.uploadStartEvidence)
    }

    func testBothOldSignalEncodingsRoundTripWithoutChangingTheirMeaning() throws {
        for oldSignal in [PR40Signal.correlatedProgress, .correlatedByteRequest] {
            // Encode using the old type before handing bytes to the new decoder.
            let shell = try JSONDecoder().decode(PR40Receipt.self, from: JSONEncoder().encode(receipt()))
            let old = shell.withStart(.init(version: 1, profileID: "historical-start", signal: oldSignal,
                                           evidenceID: "historical-1", inputCount: 1))
            let oldBytes = try JSONEncoder().encode(old)
            let current = try JSONDecoder().decode(TransferReceipt.self, from: oldBytes)
            XCTAssertEqual(current.uploadStartEvidence?.signal.rawValue, oldSignal.rawValue)
            let newBytes = try JSONEncoder().encode(current)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: newBytes) as? [String: Any])
            XCTAssertNil(fields["attachmentAcceptanceEvidence"])
            XCTAssertNotNil(fields["uploadStartEvidence"])
            XCTAssertEqual(try JSONDecoder().decode(PR40Receipt.self, from: newBytes), old)
        }
    }

    func testContradictoryStartKeysAreRejectedInsteadOfSilentlyChangingEvidence() throws {
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt())) as? [String: Any])
        fields["uploadStartEvidence"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            UploadStartEvidence(profileID: "historical-start", signal: .correlatedProgress, evidenceID: "old-1")))
        XCTAssertThrowsError(try JSONDecoder().decode(TransferReceipt.self,
            from: JSONSerialization.data(withJSONObject: fields)))
    }
}

// Frozen copies of the original stored format. Synthesized Codable is exactly
// what the retained PR40 binary used; unknown top-level keys are ignored, while
// an unknown value in its known signal key really does fail decoding.
private enum PR40Signal: String, Codable { case correlatedProgress, correlatedByteRequest }
private struct PR40StartEvidence: Codable, Equatable {
    let version: Int
    let profileID: String
    let signal: PR40Signal
    let evidenceID: String
    let inputCount: Int
}
private struct PR40Receipt: Codable, Equatable {
    let operationID: UUID
    let assetID: UUID
    let attempt: Int
    let assetSHA256: String
    let target: TargetLease
    let outcome: ReceiptOutcome
    let profileID: String
    let attachmentID: String?
    let positiveReady: Bool
    let belongsToOriginalDraft: Bool
    let hasError: Bool
    let isUploading: Bool
    let safeToRetry: Bool
    let reason: String
    let uploadStartEvidence: PR40StartEvidence?
    let continuationEvidence: AttachmentContinuationEvidence?
    let completionEvidence: AttachmentCompletionEvidence?
    let terminationEvidence: AttachmentTerminationEvidence?

    func withStart(_ start: PR40StartEvidence) -> Self {
        .init(operationID: operationID, assetID: assetID, attempt: attempt, assetSHA256: assetSHA256,
            target: target, outcome: outcome, profileID: profileID, attachmentID: attachmentID,
            positiveReady: positiveReady, belongsToOriginalDraft: belongsToOriginalDraft,
            hasError: hasError, isUploading: isUploading, safeToRetry: safeToRetry, reason: reason,
            uploadStartEvidence: start, continuationEvidence: continuationEvidence,
            completionEvidence: completionEvidence, terminationEvidence: terminationEvidence)
    }
}
