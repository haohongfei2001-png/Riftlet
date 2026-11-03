import Foundation

/// Source-owned, versioned profiles only. The default policy is empty; App
/// composition explicitly supplies independent, origin-scoped capabilities.
/// A label (INPUT/ATTACHED), timeout or send-button state alone is insufficient.
/// Product ATTACHED may qualify only with independently reviewed, scoped evidence.
public struct ReceiptPolicy: Sendable {
    public let admittedProfiles: [String: TargetSurface]
    public let retrySafeProfiles: [String: TargetSurface]
    /// Real-transport acceptance with generated images only. These profiles never
    /// grant consumption or retry permission to a system screenshot.
    public let syntheticAcceptanceProfiles: [String: TargetSurface]
    public let uploadStartProfiles: [String: TargetSurface]
    public let syntheticUploadStartProfiles: [String: TargetSurface]
    public let syntheticRetrySafeProfiles: [String: TargetSurface]
    public let continuationProfiles: [String: TargetSurface]
    public let requiredInputIsolationProfiles: Set<String>
    public let syntheticContinuationProfiles: [String: TargetSurface]
    /// Source-owned scope for newly admitted profiles. A profile may not borrow
    /// another capture source's approval. Absent entries preserve the historical
    /// policy (application captures are denied); no old receipt is promoted.
    public let profileOrigins: [String: Set<AssetOrigin>]
    /// New source-owned profiles can require bound proof without promoting
    /// legacy stored observations that lack it. These sets grant no capability.
    public let requiredCompletionEvidenceProfiles: Set<String>
    public let requiredTerminationEvidenceProfiles: Set<String>
    /// Platform finalization and irreversible retirement are independently
    /// reviewed semantics, not implied by ordinary completion/start admission.
    public let platformCompletionProfiles: [String: TargetSurface]
    public let terminationProfiles: [String: TargetSurface]

    public init(admittedProfiles: [String: TargetSurface] = [:], retrySafeProfiles: [String: TargetSurface] = [:],
                syntheticAcceptanceProfiles: [String: TargetSurface] = [:],
                uploadStartProfiles: [String: TargetSurface] = [:],
                syntheticUploadStartProfiles: [String: TargetSurface] = [:],
                syntheticRetrySafeProfiles: [String: TargetSurface] = [:],
                continuationProfiles: [String: TargetSurface] = [:],
                syntheticContinuationProfiles: [String: TargetSurface] = [:],
                profileOrigins: [String: Set<AssetOrigin>] = [:],
                requiredCompletionEvidenceProfiles: Set<String> = [],
                requiredTerminationEvidenceProfiles: Set<String> = [],
                platformCompletionProfiles: [String: TargetSurface] = [:],
                terminationProfiles: [String: TargetSurface] = [:],
                requiredInputIsolationProfiles: Set<String> = []) {
        self.admittedProfiles = admittedProfiles
        self.retrySafeProfiles = retrySafeProfiles
        self.syntheticAcceptanceProfiles = syntheticAcceptanceProfiles
        self.uploadStartProfiles = uploadStartProfiles
        self.syntheticUploadStartProfiles = syntheticUploadStartProfiles
        self.syntheticRetrySafeProfiles = syntheticRetrySafeProfiles
        self.continuationProfiles = continuationProfiles
        self.requiredInputIsolationProfiles = requiredInputIsolationProfiles
        self.syntheticContinuationProfiles = syntheticContinuationProfiles
        self.profileOrigins = profileOrigins
        self.requiredCompletionEvidenceProfiles = requiredCompletionEvidenceProfiles
        self.requiredTerminationEvidenceProfiles = requiredTerminationEvidenceProfiles
        self.platformCompletionProfiles = platformCompletionProfiles
        self.terminationProfiles = terminationProfiles
    }

    private func admitsOrigin(_ origin: AssetOrigin, profile: String) -> Bool {
        if let origins = profileOrigins[profile] { return origins.contains(origin) }
        return origin != .applicationScreenshot
    }

    public func allowsUploadStart(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard receipt.outcome == .uploadStarted, let evidence = receipt.uploadStartEvidence,
              evidence.version == 1, evidence.inputCount == 1,
              !evidence.evidenceID.isEmpty, evidence.evidenceID.utf8.count <= 256,
              !evidence.profileID.isEmpty, evidence.profileID.utf8.count <= 128,
              receipt.belongsToOriginalDraft, receipt.isUploading,
              !receipt.hasError, !receipt.positiveReady, !receipt.safeToRetry,
              let attachmentID = receipt.attachmentID, !attachmentID.isEmpty,
              attachmentID.utf8.count <= 1024 else { return false }
        if mode == .simulation {
            return asset.origin == .synthetic && receipt.profileID == "simulation-v1"
                && evidence.profileID == "simulation-upload-start-v1"
                && receipt.target.surface == .simulation && receipt.target.adapterID == "simulation"
        }
        guard receipt.target.surface != .simulation, receipt.target.adapterID != "simulation" else { return false }
        if let surface = syntheticUploadStartProfiles[evidence.profileID] {
            return asset.origin == .synthetic && surface == receipt.target.surface
        }
        return admitsOrigin(asset.origin, profile: evidence.profileID)
            && uploadStartProfiles[evidence.profileID] == receipt.target.surface
    }

    public func allowsContinuation(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard allowsUploadStart(receipt: receipt, asset: asset, mode: mode),
              let evidence = receipt.continuationEvidence,
              !evidence.evidenceID.isEmpty, evidence.evidenceID.utf8.count <= 256,
              !evidence.profileID.isEmpty, evidence.profileID.utf8.count <= 128 else { return false }
        if requiredInputIsolationProfiles.contains(evidence.profileID), evidence.version != 3 { return false }
        switch evidence.version {
        case 1:
            // Retain old synthetic fixtures; a stored v1 token is not a new
            // real-platform isolation proof and can never be upgraded in place.
            guard asset.origin == .synthetic, evidence.binding == nil, evidence.taskIsolation == nil,
                  evidence.inputIsolation == nil else { return false }
        case 2, 3:
            guard evidence.validates(receipt: receipt, asset: asset) else { return false }
        default: return false
        }
        if mode == .simulation { return evidence.profileID == "simulation-independent-attachment-v1" }
        if let surface = syntheticContinuationProfiles[evidence.profileID] {
            return asset.origin == .synthetic && surface == receipt.target.surface
        }
        return admitsOrigin(asset.origin, profile: evidence.profileID)
            && continuationProfiles[evidence.profileID] == receipt.target.surface
    }

    public func allowsConsumption(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard receipt.outcome == .verifiedReady,
              receipt.positiveReady, receipt.belongsToOriginalDraft,
              !receipt.hasError, !receipt.isUploading,
              let attachmentID = receipt.attachmentID, !attachmentID.isEmpty else { return false }
        if let proof = receipt.completionEvidence {
            guard proof.validates(receipt: receipt, asset: asset) else { return false }
            if proof.kind == .platformFinalizedOriginal {
                guard platformCompletionProfiles[receipt.profileID] == receipt.target.surface,
                      admitsOrigin(asset.origin, profile: receipt.profileID) else { return false }
            }
        } else if requiredCompletionEvidenceProfiles.contains(receipt.profileID) { return false }
        if mode == .simulation {
            return asset.origin == .synthetic && receipt.profileID == "simulation-v1"
                && receipt.target.surface == .simulation && receipt.target.adapterID == "simulation"
        }
        guard receipt.target.surface != .simulation, receipt.target.adapterID != "simulation" else { return false }
        if let surface = syntheticAcceptanceProfiles[receipt.profileID] {
            return asset.origin == .synthetic && surface == receipt.target.surface
        }
        return admitsOrigin(asset.origin, profile: receipt.profileID)
            && admittedProfiles[receipt.profileID] == receipt.target.surface
    }

    /// A false failure can duplicate an upload, so failure admission is separate from READY.
    public func allowsRetry(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard receipt.outcome == .definitiveFailure, receipt.safeToRetry, receipt.hasError,
              let attachmentID = receipt.attachmentID, !attachmentID.isEmpty,
              receipt.belongsToOriginalDraft, !receipt.isUploading, !receipt.positiveReady else { return false }
        if let proof = receipt.terminationEvidence {
            guard proof.validates(receipt: receipt, asset: asset),
                  terminationProfiles[proof.profileID] == receipt.target.surface,
                  admitsOrigin(asset.origin, profile: proof.profileID) else { return false }
        } else if requiredTerminationEvidenceProfiles.contains(receipt.profileID) { return false }
        if mode == .simulation {
            return asset.origin == .synthetic && receipt.profileID == "simulation-v1"
                && receipt.target.surface == .simulation && receipt.target.adapterID == "simulation"
        }
        guard receipt.target.surface != .simulation, receipt.target.adapterID != "simulation" else { return false }
        if let surface = syntheticRetrySafeProfiles[receipt.profileID] {
            return asset.origin == .synthetic && surface == receipt.target.surface
        }
        guard syntheticAcceptanceProfiles[receipt.profileID] == nil else { return false }
        return admitsOrigin(asset.origin, profile: receipt.profileID)
            && retrySafeProfiles[receipt.profileID] == receipt.target.surface
    }
}
