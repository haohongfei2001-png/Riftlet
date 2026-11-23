import Foundation

/// Result of inspecting an attachment in its verified original draft.
public enum OriginalAttachmentPresence: String, Codable, Sendable {
    case present, absent, unknown, failed
}

/// A read-only description of a capture's current handoff. Never authorizes
/// input, retry, queue restoration, or a database transition.
public enum HistoryAttachmentState: String, Equatable, Sendable {
    case available, preparing, needsReview, checkDraft, originalCardFailed, handedOff, attached, confirmedFailure, notAttached

    public var needsVerification: Bool { self == .needsReview || self == .checkDraft || self == .originalCardFailed }

    public init(record: AssetRecord, operation: TransferOperation?, receipt: TransferReceipt?,
                startReceipt: TransferReceipt?) {
        let current = operation.flatMap { op in
            op.id == record.activeOperationID && op.assetID == record.id ? op : nil
        }
        self.init(status: record.status, assetID: record.id, sha: record.image.sha256,
                  operationID: current?.id, phase: current?.phase, attempt: current?.attempt,
                  target: current?.target, receipt: receipt, startReceipt: startReceipt)
    }

    /// Also used by the read-only SQL predicate before applying a library page limit.
    init(status: QueueStatus, assetID: UUID, sha: String?, operationID: UUID?, phase: OperationPhase?,
         attempt: Int?, target: TargetLease?, receipt: TransferReceipt?, startReceipt: TransferReceipt?) {
        func matches(_ observation: TransferReceipt) -> Bool {
            guard let operationID, let target else { return false }
            return observation.operationID == operationID && observation.assetID == assetID
                && observation.attempt == attempt && observation.target == target
                && observation.assetSHA256 == sha
        }
        let last = receipt.flatMap { matches($0) ? $0 : nil }
        let start = startReceipt.flatMap {
            matches($0) && $0.outcome == .uploadStarted && $0.belongsToOriginalDraft && !$0.hasError
                && $0.uploadStartEvidence != nil && $0.attachmentID?.isEmpty == false ? $0 : nil
        }
        if phase == .failed,
           [.failed, .pending, .missing].contains(status) {
            if let last, last.outcome == .definitiveFailure, last.hasError, last.safeToRetry,
               last.belongsToOriginalDraft, !last.isUploading, !last.positiveReady {
                self = .confirmedFailure
            } else { self = .notAttached }
        } else if let last, last.originalCardFailureInvocationID != nil, last.outcome == .unknown, last.hasError,
                  !last.safeToRetry, last.belongsToOriginalDraft, last.attachmentID != nil,
                  phase?.isUnresolved == true {
            self = .originalCardFailed
        } else if phase == .compensated {
            self = .checkDraft
        } else if let start, let last, last.hasError, !last.positiveReady, last.belongsToOriginalDraft,
                  last.outcome == .unknown || last.outcome == .definitiveFailure,
                  last.attachmentID == start.attachmentID {
            self = .checkDraft
        } else if phase == .succeeded {
            self = .attached
        } else if phase == .unknown, let last, last.outcome == .unknown, !last.hasError,
                  last.belongsToOriginalDraft, last.attachmentID == nil || last.attachmentID == start?.attachmentID {
            self = .needsReview
        } else if start != nil {
            self = .handedOff
        } else if phase == .prepared && status == .transferring {
            self = .preparing
        } else if status == .unknown || status == .transferring || phase?.isUnresolved == true {
            self = .needsReview
        } else if status == .used {
            self = .attached
        } else if status == .failed {
            self = .notAttached
        } else {
            self = .available
        }
    }
}
