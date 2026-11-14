import Foundation

/// A read-only description of a capture's current handoff. Never authorizes
/// input, retry, queue restoration, or a database transition.
public enum HistoryAttachmentState: Equatable, Sendable {
    case available, preparing, needsReview, checkDraft, handedOff, attached, confirmedFailure, notAttached

    public var needsVerification: Bool { self == .needsReview || self == .checkDraft }

    public init(record: AssetRecord, operation: TransferOperation?, receipt: TransferReceipt?,
                startReceipt: TransferReceipt?) {
        let current = operation.flatMap { op in
            op.id == record.activeOperationID && op.assetID == record.id ? op : nil
        }
        func matches(_ observation: TransferReceipt) -> Bool {
            guard let current else { return false }
            return observation.operationID == current.id && observation.assetID == record.id
                && observation.attempt == current.attempt && observation.target == current.target
                && observation.assetSHA256 == record.image.sha256
        }
        let last = receipt.flatMap { matches($0) ? $0 : nil }
        let start = startReceipt.flatMap {
            matches($0) && $0.outcome == .uploadStarted && $0.belongsToOriginalDraft && !$0.hasError
                && $0.uploadStartEvidence != nil && $0.attachmentID?.isEmpty == false ? $0 : nil
        }
        if current?.phase == .failed,
           [.failed, .pending, .missing].contains(record.status) {
            if let last, last.outcome == .definitiveFailure, last.hasError, last.safeToRetry,
               last.belongsToOriginalDraft, !last.isUploading, !last.positiveReady {
                self = .confirmedFailure
            } else { self = .notAttached }
        } else if current?.phase == .compensated {
            self = .checkDraft
        } else if let start, let last, last.hasError, !last.positiveReady, last.belongsToOriginalDraft,
                  last.outcome == .unknown || last.outcome == .definitiveFailure,
                  last.attachmentID == start.attachmentID {
            self = .checkDraft
        } else if current?.phase == .succeeded {
            self = .attached
        } else if start != nil {
            self = .handedOff
        } else if current?.phase == .prepared && record.status == .transferring {
            self = .preparing
        } else if record.status == .unknown || record.status == .transferring || current?.phase.isUnresolved == true {
            self = .needsReview
        } else if record.status == .used {
            self = .attached
        } else if record.status == .failed {
            self = .notAttached
        } else {
            self = .available
        }
    }
}
