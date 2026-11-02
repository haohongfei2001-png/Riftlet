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
    public let platformCompletionProfileID: String?
    public let terminationProfileID: String?
    public let continuationProfileID: String?

    public init(adapterID: String, surface: TargetSurface, profileID: String,
                completionSignal: ObservationCompletionSignal? = nil,
                failureSignal: ObservationFailureSignal? = nil, uploadStartProfileID: String? = nil,
                platformCompletionProfileID: String? = nil, terminationProfileID: String? = nil,
                continuationProfileID: String? = nil) {
        self.adapterID = adapterID; self.surface = surface; self.profileID = profileID
        self.completionSignal = completionSignal; self.failureSignal = failureSignal
        self.uploadStartProfileID = uploadStartProfileID
        self.platformCompletionProfileID = platformCompletionProfileID
        self.terminationProfileID = terminationProfileID
        self.continuationProfileID = continuationProfileID
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
                        for request: TransferRequest, liveAppend: Bool = false) throws -> TransferReceipt {
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
        if OrdinaryProductScreenshotScope.matches(profile) {
            let allowed = request.asset.origin == .systemScreenshot
                ? [OrdinaryProductScreenshotScope.systemProfile, OrdinaryProductScreenshotScope.admittedSystemProfile]
                : request.asset.origin == .applicationScreenshot
                    ? [OrdinaryProductScreenshotScope.applicationProfile, OrdinaryProductScreenshotScope.admittedApplicationProfile] : []
            guard allowed.contains(where: { $0.profileID == profile.profileID && $0.uploadStartProfileID == profile.uploadStartProfileID }) else {
                throw ObservationError.syntheticEvidenceForRealAsset
            }
        }

        var outcome: ReceiptOutcome = .unknown
        var positiveReady = false
        var safeToRetry = false
        var uploadStartEvidence: UploadStartEvidence?
        var terminationEvidence: AttachmentTerminationEvidence?
        var continuationEvidence: AttachmentContinuationEvidence?
        let proofBindings = [item.completionEvidence?.binding, item.terminationEvidence?.binding,
            item.continuationEvidence?.binding].compactMap { $0 }
        if let invocation = request.invocationID,
           proofBindings.contains(where: { $0.invocationID != invocation })
            || (item.requestEvidence.map { $0.invocationID != invocation } ?? false) {
            throw ObservationError.identityMismatch
        }
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
                if liveAppend, let observed = item.continuationEvidence,
                   let invocation = request.invocationID, observed.binding.invocationID == invocation,
                   let continuationProfile = profile.continuationProfileID {
                    continuationEvidence = AttachmentContinuationEvidence(version: 2,
                        profileID: continuationProfile, evidenceID: observed.evidenceID, invocationID: invocation,
                        binding: observed.binding, taskIsolation: observed.taskIsolation)
                }
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
                if item.completionEvidence?.kind == .platformFinalizedOriginal {
                    // A generic HTTP response cannot acquire this profile. No
                    // shipping platform decoder currently supplies this path.
                    // Keep the original receipt profile across START, COMPLETE
                    // and late failure. A separate capability may admit platform
                    // semantics for that profile; it must not rename the operation.
                    if profile.platformCompletionProfileID != profile.profileID {
                        positiveReady = false; outcome = .attachedCandidate
                    }
                }
            }
        case .failed:
            if let observed = item.terminationEvidence, let terminationProfile = profile.terminationProfileID,
               profile.failureSignal != nil, exactMember, item.hasError,
               item.attachmentAbsent, item.attachmentID != nil, item.automaticRetryExcluded, !item.isUploading {
                terminationEvidence = AttachmentTerminationEvidence(profileID: terminationProfile,
                    evidenceID: observed.evidenceID, binding: observed.binding, task: observed.task,
                    retirementID: observed.retirementID, kind: observed.kind)
                outcome = .definitiveFailure; safeToRetry = true
            } else if envelope.schemaVersion < 4, profile.failureSignal != nil, exactMember, item.hasError,
               item.attachmentAbsent, item.attachmentID == nil,
               item.automaticRetryExcluded, !item.isUploading {
                outcome = .definitiveFailure; safeToRetry = true
            }
        case .unknown, .invalidated:
            break
        }

        // Reasons are bounded code-owned labels. Do not persist arbitrary page/error text.
        let receipt = TransferReceipt(operationID: operation.id, assetID: request.asset.id,
            attempt: operation.attempt, assetSHA256: request.asset.sha256,
            target: operation.target, outcome: outcome, profileID: profile.profileID,
            attachmentID: item.attachmentID, positiveReady: positiveReady,
            belongsToOriginalDraft: item.belongsToOriginalDraft,
            hasError: item.hasError, isUploading: item.isUploading, safeToRetry: safeToRetry,
            reason: "observer-v\(envelope.schemaVersion):\(item.state.rawValue):\(envelope.provenance.source.rawValue)",
            uploadStartEvidence: uploadStartEvidence, continuationEvidence: continuationEvidence,
            completionEvidence: item.completionEvidence, terminationEvidence: terminationEvidence)
        if let proof = item.completionEvidence, !proof.validates(receipt: receipt, asset: request.asset) {
            throw ObservationError.invalidField("completion identity chain")
        }
        if let proof = terminationEvidence, !proof.validates(receipt: receipt, asset: request.asset) {
            throw ObservationError.invalidField("termination identity chain")
        }
        // Core additionally checks the durable original invocation and independent
        // admission; restart/reconcile never manufacture continuation eligibility.
        return receipt
    }
}
