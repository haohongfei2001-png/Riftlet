import Foundation

/// Only the adapter's bounded paths before the file-input side effect may issue
/// this error. It is not an upload-failure receipt and never grants retry of an externally input item.
public enum PreInputRejectionStage: String, Codable, Sendable {
    case localBeforeBegin, pageRetiredBeforeCommit, pageRejectedBeforeBegin, pageRetiredBeforeFileInput
}

public struct PreInputRejection: Error, Codable, Equatable, Sendable {
    public let operationID: UUID
    public let assetID: UUID
    public let attempt: Int
    public let assetSHA256: String
    public let target: TargetLease
    public let invocationID: UUID
    public let stage: PreInputRejectionStage

    public init(operationID: UUID, assetID: UUID, attempt: Int, assetSHA256: String,
                target: TargetLease, invocationID: UUID, stage: PreInputRejectionStage) {
        self.operationID = operationID; self.assetID = assetID; self.attempt = attempt
        self.assetSHA256 = assetSHA256; self.target = target
        self.invocationID = invocationID; self.stage = stage
    }
}

/// Separate from upload-start admission: the adapter must have independently
/// proved that a subsequent input cannot replace/cancel the original attachment.
/// No shipping Web adapter or App profile grants this capability.
public struct AttachmentContinuationEvidence: Codable, Equatable, Sendable {
    public let version: Int
    public let profileID: String
    public let evidenceID: String
    public let invocationID: UUID
    /// Version 1 is historical/synthetic only. Version 2 requires both the full
    /// original binding and independently established platform-task isolation.
    public let binding: AttachmentOperationBinding?
    public let taskIsolation: AttachmentTaskIsolationEvidence?
    public init(version: Int = 1, profileID: String, evidenceID: String, invocationID: UUID,
                binding: AttachmentOperationBinding? = nil, taskIsolation: AttachmentTaskIsolationEvidence? = nil) {
        self.version = version; self.profileID = profileID
        self.evidenceID = evidenceID; self.invocationID = invocationID
        self.binding = binding; self.taskIsolation = taskIsolation
    }

    public func validates(receipt: TransferReceipt, asset: ImportedAsset) -> Bool {
        guard version == 2, AttachmentEvidenceValidation.token(profileID, maximum: 128),
              AttachmentEvidenceValidation.token(evidenceID),
              let binding, binding.invocationID == invocationID,
              binding.matches(receipt: receipt, asset: asset),
              let taskIsolation, taskIsolation.validates(receipt: receipt, asset: asset),
              receipt.belongsToOriginalDraft, receipt.isUploading,
              !receipt.hasError, !receipt.positiveReady, !receipt.safeToRetry else { return false }
        return true
    }
}

/// A versioned additive checkpoint keeps schema-v3 readers conservative. Missing
/// records are legacy, never backfilled. A new coordinator owner cannot inherit
/// dispatch eligibility after restart just because the record exists.
struct DispatchCallRecord: Codable, Equatable, Sendable {
    let version: Int
    let operationID: UUID
    let assetID: UUID
    let attempt: Int
    let assetSHA256: String
    let target: TargetLease
    let invocationID: UUID
    let ownerID: UUID?
    var returnedReceipt: TransferReceipt?
}
