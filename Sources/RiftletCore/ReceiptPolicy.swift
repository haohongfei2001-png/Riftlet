import Foundation

/// Reviewed, versioned profiles only. Shipping production registry is deliberately empty.
/// A label (INPUT/ATTACHED), timeout or send-button state alone is insufficient.
/// Product ATTACHED may qualify only with independently reviewed, scoped evidence.
public struct ReceiptPolicy: Sendable {
    public let admittedProfiles: [String: TargetSurface]
    public let retrySafeProfiles: [String: TargetSurface]

    public init(admittedProfiles: [String: TargetSurface] = [:], retrySafeProfiles: [String: TargetSurface] = [:]) {
        self.admittedProfiles = admittedProfiles
        self.retrySafeProfiles = retrySafeProfiles
    }

    public func allowsConsumption(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard receipt.outcome == .verifiedReady,
              receipt.positiveReady, receipt.belongsToOriginalDraft,
              !receipt.hasError, !receipt.isUploading,
              let attachmentID = receipt.attachmentID, !attachmentID.isEmpty else { return false }
        if mode == .simulation {
            return asset.origin == .synthetic && receipt.profileID == "simulation-v1"
                && receipt.target.surface == .simulation && receipt.target.adapterID == "simulation"
        }
        guard receipt.target.surface != .simulation, receipt.target.adapterID != "simulation" else { return false }
        return admittedProfiles[receipt.profileID] == receipt.target.surface
    }

    /// A false failure can duplicate an upload, so failure admission is separate from READY.
    public func allowsRetry(receipt: TransferReceipt, asset: ImportedAsset, mode: StoreMode) -> Bool {
        guard receipt.outcome == .definitiveFailure, receipt.safeToRetry,
              receipt.belongsToOriginalDraft, !receipt.isUploading, !receipt.positiveReady else { return false }
        if mode == .simulation {
            return asset.origin == .synthetic && receipt.profileID == "simulation-v1"
                && receipt.target.surface == .simulation && receipt.target.adapterID == "simulation"
        }
        guard receipt.target.surface != .simulation, receipt.target.adapterID != "simulation" else { return false }
        return retrySafeProfiles[receipt.profileID] == receipt.target.surface
    }
}
