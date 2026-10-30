import Foundation
import RiftletCore

/// A reviewed observer may define product ATTACHED as completion. The mapping is
/// supplied by application code, not JSON, and does not register a ReceiptPolicy.
public enum ObservationCompletionSignal: Equatable, Sendable { case attached, ready }
public enum ObservationFailureSignal: Equatable, Sendable { case terminalErrorAndNoResidual }

public enum DevelopmentObservationScope: Sendable {
    case syntheticOnly, systemScreenshotCandidate, ordinarySystemScreenshot
}

public struct ObservationProfile: Sendable {
    public let adapterID: String
    public let surface: TargetSurface
    public let profileID: String
    public let completionSignal: ObservationCompletionSignal?
    public let failureSignal: ObservationFailureSignal?
    public let uploadStartProfileID: String?

    public init(adapterID: String, surface: TargetSurface, profileID: String,
                completionSignal: ObservationCompletionSignal? = nil,
                failureSignal: ObservationFailureSignal? = nil, uploadStartProfileID: String? = nil) {
        self.adapterID = adapterID; self.surface = surface; self.profileID = profileID
        self.completionSignal = completionSignal; self.failureSignal = failureSignal
        self.uploadStartProfileID = uploadStartProfileID
    }
}

/// Produces the existing Core receipt. QueueStore remains the only state writer;
/// ReceiptPolicy independently controls successful completion and safe retry.
public struct ObservationNormalizer: Sendable {
    public let profile: ObservationProfile
    private let developmentScope: DevelopmentObservationScope
    public init(profile: ObservationProfile, developmentScope: DevelopmentObservationScope = .syntheticOnly) {
        self.profile = profile; self.developmentScope = developmentScope
    }

    public func receipt(from envelope: AttachmentObservationEnvelope,
                        for request: TransferRequest) throws -> TransferReceipt {
        try ObservationDecoder.validate(envelope)
        let item = envelope.observation
        let identity = item.identity
        let operation = request.operation
        guard (operation.phase.isUnresolved || operation.phase == .succeeded), operation.phase != .prepared else {
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
        if envelope.provenance.source == .integratedDevelopment && request.asset.origin != .synthetic {
            let matches: Bool
            switch developmentScope {
            case .syntheticOnly: matches = false
            case .systemScreenshotCandidate: matches = SystemScreenshotWebCandidate.matches(profile)
            case .ordinarySystemScreenshot: matches = OrdinarySystemScreenshotScope.matches(profile)
            }
            guard matches else {
                throw ObservationError.syntheticEvidenceForRealAsset
            }
            // Candidate interpretation only. It keeps the original provenance;
            // ReceiptPolicy separately refuses unadmitted start/success/retry.
        }

        var outcome: ReceiptOutcome = .unknown
        var positiveReady = false
        var safeToRetry = false
        var uploadStartEvidence: UploadStartEvidence?
        let exactMember = item.exactImageIdentity && item.belongsToOriginalDraft
        let identifiedAttachment = item.attachmentID != nil && !item.attachmentAbsent
        let cleanAttachment = exactMember && identifiedAttachment && !item.hasError && !item.isUploading

        switch item.state {
        case .uploadStarted:
            if operation.phase != .succeeded && operation.phase != .compensated,
               let start = item.uploadStart, let startProfile = profile.uploadStartProfileID,
               !startProfile.isEmpty, startProfile.utf8.count <= 128 {
                outcome = .uploadStarted
                uploadStartEvidence = UploadStartEvidence(profileID: startProfile,
                    signal: start.signal, evidenceID: start.evidenceID, inputCount: start.inputCount)
            } else if operation.phase != .succeeded && operation.phase != .compensated {
                outcome = .inputTriggered
            }
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
            reason: "observer-v\(envelope.schemaVersion):\(item.state.rawValue):\(envelope.provenance.source.rawValue)",
            uploadStartEvidence: uploadStartEvidence)
    }
}
