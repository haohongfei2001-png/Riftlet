import Foundation

/// Only the adapter's bounded paths before the file-input side effect may issue
/// this error. It is not an upload-failure receipt and never grants retry of an externally input item.
public enum PreInputRejectionStage: String, Codable, Sendable {
    // Keep the legacy raw label for old App decoding. Current native input also
    // uses it when local control flow proves commit was never invoked; reason
    // distinguishes that case from a local file failure before payload transfer.
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
    /// Optional current-operation diagnostic. Historical checkpoints omit it;
    /// this text never participates in permission for another input.
    public let reason: String?

    public init(operationID: UUID, assetID: UUID, attempt: Int, assetSHA256: String,
                target: TargetLease, invocationID: UUID, stage: PreInputRejectionStage, reason: String? = nil) {
        self.operationID = operationID; self.assetID = assetID; self.attempt = attempt
        self.assetSHA256 = assetSHA256; self.target = target
        self.invocationID = invocationID; self.stage = stage; self.reason = reason
    }
}

/// Separate from upload-start admission: the adapter must have independently
/// proved that a subsequent input cannot replace/cancel the original attachment.
/// Browser input ownership and platform task finalization are separate facts.
public struct AttachmentContinuationEvidence: Codable, Equatable, Sendable {
    public let version: Int
    public let profileID: String
    public let evidenceID: String
    public let invocationID: UUID
    /// Version 1 is historical/synthetic only. Version 2 requires both the full
    /// original binding and independently established platform-task isolation.
    public let binding: AttachmentOperationBinding?
    public let taskIsolation: AttachmentTaskIsolationEvidence?
    /// Version 3 uses measured browser request ownership, without pretending
    /// that document-local request IDs are platform/server task identities.
    public let inputIsolation: AttachmentInputIsolationEvidence?
    public init(version: Int = 1, profileID: String, evidenceID: String, invocationID: UUID,
                binding: AttachmentOperationBinding? = nil, taskIsolation: AttachmentTaskIsolationEvidence? = nil,
                inputIsolation: AttachmentInputIsolationEvidence? = nil) {
        self.version = version; self.profileID = profileID
        self.evidenceID = evidenceID; self.invocationID = invocationID
        self.binding = binding; self.taskIsolation = taskIsolation
        self.inputIsolation = inputIsolation
    }

    public func validates(receipt: TransferReceipt, asset: ImportedAsset) -> Bool {
        guard AttachmentEvidenceValidation.token(profileID, maximum: 128),
              AttachmentEvidenceValidation.token(evidenceID),
              let binding, binding.invocationID == invocationID,
              binding.matches(receipt: receipt, asset: asset),
              receipt.belongsToOriginalDraft, receipt.isUploading,
              !receipt.hasError, !receipt.positiveReady, !receipt.safeToRetry else { return false }
        switch version {
        case 2: return inputIsolation == nil && taskIsolation?.validates(receipt: receipt, asset: asset) == true
        case 3: return taskIsolation == nil && inputIsolation?.validates(receipt: receipt, asset: asset) == true
        default: return false
        }
    }
}

/// Backward-compatible operation journal. It records this operation's once-only
/// invocation and return; older rows are never consulted to permit a new file.
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
    // Local execution and the attachment outcome are independent. Optional for
    // old journals; never backfill a historical call to manufacture ownership.
    var inputExecutionReturned: Bool? = nil
    var inputResource: PreparedInputResource? = nil
}

/// Historical checkpoint payload, retained only so existing databases decode.
/// New input never constructs, validates or consumes this old reservation.
public struct PreparedInputResource: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let assetID: UUID
    public let attempt: Int
    public let assetSHA256: String
    public let target: TargetLease
    public let invocationID: UUID
    public let resourceID: UUID
    public let inputElementID: String

    public init(operationID: UUID, assetID: UUID, attempt: Int, assetSHA256: String,
                target: TargetLease, invocationID: UUID, resourceID: UUID, inputElementID: String) {
        self.operationID = operationID; self.assetID = assetID; self.attempt = attempt
        self.assetSHA256 = assetSHA256; self.target = target; self.invocationID = invocationID
        self.resourceID = resourceID; self.inputElementID = inputElementID
    }
}
