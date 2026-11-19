import Foundation
import RiftletCore

/// Interpret the already verified, journaled v29 original-draft content proof.
/// This is the same local handoff signal as Chrome, not a server completion.
/// The caller must first verify the durable v29 product-system registration and
/// persist the original observation through SystemScreenshotObservationJournal.
enum EdgeDraftAttachmentAcceptance {
    static func receipt(from envelope: AttachmentObservationEnvelope, normalized receipt: TransferReceipt,
                        for request: TransferRequest) throws -> TransferReceipt {
        guard let content = envelope.observation.originalDraftContent else { return receipt }
        let profile = OrdinaryProductScreenshotScope.edgeAttachmentAcceptedProfile
        guard receipt.outcome == .inputTriggered, receipt.profileID == profile.profileID,
              request.operation.phase.isUnresolved,
              request.invocationID == content.invocationID,
              request.asset.origin == .systemScreenshot, request.asset.mediaType.lowercased() == "image/png",
              request.operation.target.applicationID == EdgeApplicationHost.bundleID,
              request.operation.target.clickBindingID != nil, request.operation.target.webDraftRoute == .chatGPTTemporaryHome,
              envelope.provenance == .init(source: .integratedDevelopment, evidenceID: ChatGPTWebPageProgram.edgeEvidenceID),
              receipt.belongsToOriginalDraft, !receipt.hasError, !receipt.isUploading,
              !receipt.positiveReady, !receipt.safeToRetry,
              receipt.uploadStartEvidence == nil, receipt.completionEvidence == nil,
              receipt.terminationEvidence == nil, receipt.continuationEvidence == nil else {
            throw WebAdapterError.invalidReply
        }
        // An opaque local attachment handle derived from the immutable content
        // evidence; it is never presented as a service file ID or a DOM node ID.
        return TransferReceipt(operationID: receipt.operationID, assetID: receipt.assetID,
            attempt: receipt.attempt, assetSHA256: receipt.assetSHA256, target: receipt.target,
            outcome: .uploadStarted, profileID: profile.profileID,
            attachmentID: "edge-draft-image:" + content.evidenceID.uuidString.lowercased(),
            positiveReady: false, belongsToOriginalDraft: true, hasError: false, isUploading: false, safeToRetry: false,
            reason: "original-draft-content:attachmentAccepted",
            uploadStartEvidence: .init(profileID: OrdinaryProductScreenshotScope.edgeAttachmentAcceptedStartProfileID,
                signal: .attachmentAccepted, evidenceID: content.evidenceID.uuidString, inputCount: 1))
    }
}
