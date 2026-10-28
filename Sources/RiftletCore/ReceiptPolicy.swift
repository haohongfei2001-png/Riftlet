import Foundation

/// Reviewed, versioned profiles only. Shipping production registry is deliberately empty.
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

    public init(admittedProfiles: [String: TargetSurface] = [:], retrySafeProfiles: [String: TargetSurface] = [:],
                syntheticAcceptanceProfiles: [String: TargetSurface] = [:],
                uploadStartProfiles: [String: TargetSurface] = [:],
                syntheticUploadStartProfiles: [String: TargetSurface] = [:],
                syntheticRetrySafeProfiles: [String: TargetSurface] = [:]) {
        self.admittedProfiles = admittedProfiles
        self.retrySafeProfiles = retrySafeProfiles
        self.syntheticAcceptanceProfiles = syntheticAcceptanceProfiles
        self.uploadStartProfiles = uploadStartProfiles
        self.syntheticUploadStartProfiles = syntheticUploadStartProfiles
        self.syntheticRetrySafeProfiles = syntheticRetrySafeProfiles
    }

    public func allowsUploadStart(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard asset.origin != .applicationScreenshot else { return false }
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
        return uploadStartProfiles[evidence.profileID] == receipt.target.surface
    }

    public func allowsConsumption(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard asset.origin != .applicationScreenshot else { return false }
        guard receipt.outcome == .verifiedReady,
              receipt.positiveReady, receipt.belongsToOriginalDraft,
              !receipt.hasError, !receipt.isUploading,
              let attachmentID = receipt.attachmentID, !attachmentID.isEmpty else { return false }
        if mode == .simulation {
            return asset.origin == .synthetic && receipt.profileID == "simulation-v1"
                && receipt.target.surface == .simulation && receipt.target.adapterID == "simulation"
        }
        guard receipt.target.surface != .simulation, receipt.target.adapterID != "simulation" else { return false }
        if let surface = syntheticAcceptanceProfiles[receipt.profileID] {
            return asset.origin == .synthetic && surface == receipt.target.surface
        }
        return admittedProfiles[receipt.profileID] == receipt.target.surface
    }

    /// A false failure can duplicate an upload, so failure admission is separate from READY.
    public func allowsRetry(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard asset.origin != .applicationScreenshot else { return false }
        guard receipt.outcome == .definitiveFailure, receipt.safeToRetry, receipt.hasError,
              let attachmentID = receipt.attachmentID, !attachmentID.isEmpty,
              receipt.belongsToOriginalDraft, !receipt.isUploading, !receipt.positiveReady else { return false }
        if mode == .simulation {
            return asset.origin == .synthetic && receipt.profileID == "simulation-v1"
                && receipt.target.surface == .simulation && receipt.target.adapterID == "simulation"
        }
        guard receipt.target.surface != .simulation, receipt.target.adapterID != "simulation" else { return false }
        if let surface = syntheticRetrySafeProfiles[receipt.profileID] {
            return asset.origin == .synthetic && surface == receipt.target.surface
        }
        guard syntheticAcceptanceProfiles[receipt.profileID] == nil else { return false }
        return retrySafeProfiles[receipt.profileID] == receipt.target.surface
    }
}
