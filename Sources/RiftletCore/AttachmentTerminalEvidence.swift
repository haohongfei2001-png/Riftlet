import Foundation

/// Exact original dispatch identity. An observation cannot replace any field
/// with a later click, a different attachment or the currently active draft.
public struct AttachmentOperationBinding: Codable, Equatable, Sendable {
    public let version: Int
    public let operationID: UUID
    public let assetID: UUID
    public let attempt: Int
    public let assetSHA256: String
    public let target: TargetLease
    public let invocationID: UUID
    public let attachmentID: String

    public init(version: Int = 1, operationID: UUID, assetID: UUID, attempt: Int,
                assetSHA256: String, target: TargetLease, invocationID: UUID, attachmentID: String) {
        self.version = version; self.operationID = operationID; self.assetID = assetID
        self.attempt = attempt; self.assetSHA256 = assetSHA256; self.target = target
        self.invocationID = invocationID; self.attachmentID = attachmentID
    }

    public func matches(receipt: TransferReceipt, asset: ImportedAsset) -> Bool {
        version == 1 && attempt > 0 && AttachmentEvidenceValidation.sha256(assetSHA256)
            && [target.adapterID, target.applicationID, target.sessionID, target.windowID,
                target.documentID, target.composerID, target.draftGeneration].allSatisfy {
                    AttachmentEvidenceValidation.token($0, maximum: 512)
                }
            && (target.tabID.map { AttachmentEvidenceValidation.token($0, maximum: 512) }
                ?? (target.surface != .webChat && target.surface != .webWork))
            && AttachmentEvidenceValidation.token(attachmentID, maximum: 1024)
            && operationID == receipt.operationID && assetID == receipt.assetID && assetID == asset.id
            && attempt == receipt.attempt && assetSHA256 == receipt.assetSHA256 && assetSHA256 == asset.sha256
            && target == receipt.target && attachmentID == receipt.attachmentID
    }
}

/// Observer-independent vocabulary, not a claim that ChatGPT exposes these
/// fields. A separately reviewed platform decoder must establish this relation
/// from actual request/task/attachment facts; DOM names and FileList are not it.
public struct PlatformAttachmentTaskIdentity: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: String
    public let taskID: String
    public let attachmentReference: String
    public let originalSHA256: String
    public let originalByteCount: Int64

    public init(version: Int = 1, requestID: String, taskID: String, attachmentReference: String,
                originalSHA256: String, originalByteCount: Int64) {
        self.version = version; self.requestID = requestID; self.taskID = taskID
        self.attachmentReference = attachmentReference; self.originalSHA256 = originalSHA256
        self.originalByteCount = originalByteCount
    }

    public func matches(asset: ImportedAsset) -> Bool {
        version == 1 && [requestID, taskID, attachmentReference].allSatisfy { AttachmentEvidenceValidation.token($0) }
            && AttachmentEvidenceValidation.sha256(originalSHA256) && originalSHA256 == asset.sha256
            && originalByteCount > 0 && originalByteCount <= AttachmentEvidenceValidation.maximumBytes
            && originalByteCount == asset.byteCount
    }

    /// Within a single continuously observed draft, independent operations may
    /// not borrow any original request, task or platform attachment identity.
    func conflicts(with other: Self) -> Bool {
        requestID == other.requestID || taskID == other.taskID || attachmentReference == other.attachmentReference
    }
}

public struct PlatformFinalizationEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case finalizedOriginal }
    public let version: Int
    public let task: PlatformAttachmentTaskIdentity
    public let finalizationID: String
    public let kind: Kind

    public init(version: Int = 1, task: PlatformAttachmentTaskIdentity,
                finalizationID: String, kind: Kind = .finalizedOriginal) {
        self.version = version; self.task = task; self.finalizationID = finalizationID; self.kind = kind
    }

    public func matches(asset: ImportedAsset) -> Bool {
        version == 1 && kind == .finalizedOriginal && task.matches(asset: asset)
            && AttachmentEvidenceValidation.token(finalizationID)
    }
}

/// Three distinct completion proofs. Exact pixels are unscaled sRGB RGBA8;
/// they do not assert that server-stored encoded bytes are unchanged. Platform
/// finalization is a different, independently admitted signal, never a fallback
/// for a mismatched preview. Fields must be measured, not echoed from a request.
public struct AttachmentCompletionEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case exactOriginalBytes, exactSRGBPixels, platformFinalizedOriginal }
    public let version: Int
    public let evidenceID: String
    public let binding: AttachmentOperationBinding
    public let kind: Kind
    public let originalByteCount: Int64
    public let originalSHA256: String
    public let observedByteCount: Int64?
    public let observedSHA256: String?
    public let originalWidth: Int?
    public let originalHeight: Int?
    public let originalPixelSHA256: String?
    public let previewWidth: Int?
    public let previewHeight: Int?
    public let previewPixelSHA256: String?
    public let platform: PlatformFinalizationEvidence?

    public init(version: Int = 1, evidenceID: String, binding: AttachmentOperationBinding, kind: Kind,
                originalByteCount: Int64, originalSHA256: String,
                observedByteCount: Int64? = nil, observedSHA256: String? = nil,
                originalWidth: Int? = nil, originalHeight: Int? = nil, originalPixelSHA256: String? = nil,
                previewWidth: Int? = nil, previewHeight: Int? = nil, previewPixelSHA256: String? = nil,
                platform: PlatformFinalizationEvidence? = nil) {
        self.version = version; self.evidenceID = evidenceID; self.binding = binding; self.kind = kind
        self.originalByteCount = originalByteCount; self.originalSHA256 = originalSHA256
        self.observedByteCount = observedByteCount; self.observedSHA256 = observedSHA256
        self.originalWidth = originalWidth; self.originalHeight = originalHeight; self.originalPixelSHA256 = originalPixelSHA256
        self.previewWidth = previewWidth; self.previewHeight = previewHeight; self.previewPixelSHA256 = previewPixelSHA256
        self.platform = platform
    }

    public func validates(receipt: TransferReceipt, asset: ImportedAsset) -> Bool {
        guard version == 1, AttachmentEvidenceValidation.token(evidenceID),
              binding.matches(receipt: receipt, asset: asset),
              (receipt.outcome == .verifiedReady && receipt.positiveReady)
                || (receipt.outcome == .attachedCandidate && !receipt.positiveReady),
              receipt.belongsToOriginalDraft, !receipt.hasError,
              !receipt.isUploading, !receipt.safeToRetry,
              originalByteCount > 0, originalByteCount <= AttachmentEvidenceValidation.maximumBytes,
              originalByteCount == asset.byteCount,
              AttachmentEvidenceValidation.sha256(originalSHA256), originalSHA256 == asset.sha256 else { return false }
        let noPixels = originalWidth == nil && originalHeight == nil && originalPixelSHA256 == nil
            && previewWidth == nil && previewHeight == nil && previewPixelSHA256 == nil
        switch kind {
        case .exactOriginalBytes:
            return noPixels && platform == nil && observedByteCount == originalByteCount && observedSHA256 == originalSHA256
        case .exactSRGBPixels:
            guard observedByteCount == nil, observedSHA256 == nil, platform == nil,
                  let width = originalWidth, let height = originalHeight, width > 0, height > 0,
                  width <= AttachmentEvidenceValidation.maximumPixels / height,
                  width == asset.pixelWidth, height == asset.pixelHeight,
                  previewWidth == width, previewHeight == height,
                  let originalPixelSHA256, AttachmentEvidenceValidation.sha256(originalPixelSHA256),
                  previewPixelSHA256 == originalPixelSHA256 else { return false }
            return true
        case .platformFinalizedOriginal:
            return noPixels && observedByteCount == nil && observedSHA256 == nil && platform?.matches(asset: asset) == true
        }
    }
}

/// Durable irreversible retirement is stronger than an error or absent card.
/// This closed semantic must be proved by a separately admitted platform
/// observer. Merely supplying identifiers/this enum never grants safe retry.
public struct AttachmentTerminationEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case irreversibleRetirementNoAutomaticRetry }
    public let version: Int
    public let profileID: String
    public let evidenceID: String
    public let binding: AttachmentOperationBinding
    public let task: PlatformAttachmentTaskIdentity
    public let retirementID: String
    public let kind: Kind

    public init(version: Int = 1, profileID: String, evidenceID: String, binding: AttachmentOperationBinding,
                task: PlatformAttachmentTaskIdentity, retirementID: String,
                kind: Kind = .irreversibleRetirementNoAutomaticRetry) {
        self.version = version; self.profileID = profileID; self.evidenceID = evidenceID
        self.binding = binding; self.task = task; self.retirementID = retirementID; self.kind = kind
    }

    public func validates(receipt: TransferReceipt, asset: ImportedAsset) -> Bool {
        version == 1 && kind == .irreversibleRetirementNoAutomaticRetry
            && AttachmentEvidenceValidation.token(profileID, maximum: 128)
            && AttachmentEvidenceValidation.token(evidenceID) && AttachmentEvidenceValidation.token(retirementID)
            && binding.matches(receipt: receipt, asset: asset) && task.matches(asset: asset)
            && receipt.outcome == .definitiveFailure && receipt.hasError && receipt.safeToRetry
            && receipt.belongsToOriginalDraft && !receipt.isUploading && !receipt.positiveReady
    }
}

/// A platform-owned upload task proven independent of the composer file input.
/// The return of change dispatch, a File reference or a still-visible card does
/// not produce this fact. There is currently no shipping ChatGPT decoder for it.
public struct AttachmentTaskIsolationEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case independentTaskSurvivesSubsequentInput }
    public let version: Int
    public let task: PlatformAttachmentTaskIdentity
    public let ownershipID: String
    public let kind: Kind
    public let startEvidenceID: String
    public let inputSequence: Int
    public let callSettledSequence: Int
    public let startSequence: Int
    public let observedSequence: Int

    public init(version: Int = 1, task: PlatformAttachmentTaskIdentity, ownershipID: String,
                kind: Kind = .independentTaskSurvivesSubsequentInput, startEvidenceID: String,
                inputSequence: Int, callSettledSequence: Int, startSequence: Int, observedSequence: Int) {
        self.version = version; self.task = task; self.ownershipID = ownershipID; self.kind = kind
        self.startEvidenceID = startEvidenceID; self.inputSequence = inputSequence
        self.callSettledSequence = callSettledSequence; self.startSequence = startSequence; self.observedSequence = observedSequence
    }

    public func validates(receipt: TransferReceipt, asset: ImportedAsset) -> Bool {
        version == 1 && kind == .independentTaskSurvivesSubsequentInput && task.matches(asset: asset)
            && AttachmentEvidenceValidation.token(ownershipID) && AttachmentEvidenceValidation.token(startEvidenceID)
            && receipt.outcome == .uploadStarted && receipt.uploadStartEvidence?.inputCount == 1
            && startEvidenceID == receipt.uploadStartEvidence?.evidenceID
            && inputSequence > 0 && callSettledSequence > inputSequence && startSequence > inputSequence
            && observedSequence >= max(callSettledSequence, startSequence)
    }
}

enum AttachmentEvidenceValidation {
    static let maximumBytes: Int64 = 8 * 1024 * 1024
    static let maximumPixels = 16_777_216
    static func token(_ value: String, maximum: Int = 256) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
            && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
    static func sha256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
