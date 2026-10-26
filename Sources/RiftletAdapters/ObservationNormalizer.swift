import Foundation
import RiftletCore

/// A reviewed observer may define product ATTACHED as completion. The mapping is
/// supplied by application code, not JSON, and does not register a ReceiptPolicy.
public enum ObservationCompletionSignal: Sendable { case attached, ready }
public enum ObservationFailureSignal: Sendable { case terminalErrorAndNoResidual }

public struct ObservationProfile: Sendable {
    public let adapterID: String
    public let surface: TargetSurface
    public let profileID: String
    public let completionSignal: ObservationCompletionSignal?
    public let failureSignal: ObservationFailureSignal?

    public init(adapterID: String, surface: TargetSurface, profileID: String,
                completionSignal: ObservationCompletionSignal? = nil,
                failureSignal: ObservationFailureSignal? = nil) {
        self.adapterID = adapterID; self.surface = surface; self.profileID = profileID
        self.completionSignal = completionSignal; self.failureSignal = failureSignal
    }
}

/// Produces the existing Core receipt. QueueStore remains the only state writer;
/// ReceiptPolicy independently controls successful completion and safe retry.
public struct ObservationNormalizer: Sendable {
    public let profile: ObservationProfile
    public init(profile: ObservationProfile) { self.profile = profile }

    public func receipt(from envelope: AttachmentObservationEnvelope,
                        for request: TransferRequest) throws -> TransferReceipt {
        try ObservationDecoder.validate(envelope)
        let item = envelope.observation
        let identity = item.identity
        let operation = request.operation
        guard operation.phase.isUnresolved, operation.phase != .prepared else {
            throw ObservationError.operationNotDispatched
        }
        guard identity.operationID == operation.id, identity.assetID == request.asset.id,
              operation.assetID == request.asset.id, identity.attempt == operation.attempt,
              identity.assetSHA256 == request.asset.sha256, identity.target == operation.target else {
            throw ObservationError.identityMismatch
        }
        guard profile.adapterID == operation.target.adapterID,
              profile.surface == operation.target.surface, !profile.profileID.isEmpty else {
            throw ObservationError.profileTargetMismatch
        }
        if envelope.provenance.source == .syntheticFixture && request.asset.origin != .synthetic {
            throw ObservationError.syntheticEvidenceForRealAsset
        }

        var outcome: ReceiptOutcome = .unknown
        var positiveReady = false
        var safeToRetry = false
        let exactMember = item.exactImageIdentity && item.belongsToOriginalDraft
        let identifiedAttachment = item.attachmentID != nil && !item.attachmentAbsent
        let cleanAttachment = exactMember && identifiedAttachment && !item.hasError && !item.isUploading

        switch item.state {
        case .inputTriggered:
            if item.belongsToOriginalDraft && !item.hasError { outcome = .inputTriggered }
        case .attached, .ready:
            if cleanAttachment {
                let matches: Bool
                switch (profile.completionSignal, item.state) {
                case (.attached?, .attached), (.ready?, .ready): matches = true
                default: matches = false
                }
                positiveReady = matches
                outcome = matches ? .verifiedReady : .attachedCandidate
            }
        case .failed:
            if profile.failureSignal != nil, exactMember, item.hasError,
               item.attachmentAbsent, item.attachmentID == nil,
               item.automaticRetryExcluded, !item.isUploading {
                outcome = .definitiveFailure; safeToRetry = true
            }
        case .unknown, .invalidated:
            break
        }

        // Reasons are bounded code-owned labels. Do not persist arbitrary page/error text.
        return TransferReceipt(operationID: operation.id, assetID: request.asset.id,
            attempt: operation.attempt, assetSHA256: request.asset.sha256,
            target: operation.target, outcome: outcome, profileID: profile.profileID,
            attachmentID: item.attachmentID, positiveReady: positiveReady,
            belongsToOriginalDraft: item.belongsToOriginalDraft,
            hasError: item.hasError, isUploading: item.isUploading, safeToRetry: safeToRetry,
            reason: "observer-v1:\(item.state.rawValue):\(envelope.provenance.source.rawValue)")
    }
}
