import Foundation
import RiftletCore

/// Interpretation scope only. This defines no ReceiptPolicy and cannot enable ordinary uploads.
public enum SystemScreenshotAdmissionScope: Sendable, Equatable {
    case candidate, ordinary, ordinaryCurrentDraftInternal

    var legacyProfile: ObservationProfile {
        switch self {
        case .candidate: return SystemScreenshotWebCandidate.profile
        case .ordinary: return OrdinarySystemScreenshotScope.profile
        case .ordinaryCurrentDraftInternal: return OrdinaryCurrentDraftInternalScope.profile
        }
    }
    var admittedProfile: ObservationProfile {
        switch self {
        case .candidate: return SystemScreenshotWebCandidate.admittedProfile
        case .ordinary: return OrdinarySystemScreenshotScope.admittedProfile
        case .ordinaryCurrentDraftInternal: return OrdinaryCurrentDraftInternalScope.admittedProfile
        }
    }
    var observationScope: DevelopmentObservationScope { self == .candidate ? .systemScreenshotCandidate : .ordinarySystemScreenshot }
    var admissionPrefix: String {
        switch self {
        case .candidate: return "system-screenshot-admission-v2"
        case .ordinary: return "ordinary-system-screenshot-admission-v1"
        case .ordinaryCurrentDraftInternal: return "ordinary-current-draft-internal-admission-v1"
        }
    }
    var journalPrefix: String {
        switch self {
        case .candidate: return "system-screenshot-candidate-observation-v1"
        case .ordinary: return "ordinary-system-screenshot-observation-v1"
        case .ordinaryCurrentDraftInternal: return "ordinary-current-draft-internal-observation-v1"
        }
    }
    func validateTarget(_ target: TargetLease) throws {
        guard self == .ordinaryCurrentDraftInternal else {
            return try SystemScreenshotWebCandidate.validateAdmittedTarget(target)
        }
        // Recognition preserves the exact business identity. It never aliases a
        // local draft to a UUID, nor authorizes an unbound Home composer.
        guard target.adapterID == "chatgpt-web", target.surface == .webChat,
              target.applicationID == "com.google.Chrome",
              target.logicalDraftIdentity?.isRecognized == true else { throw WebAdapterError.invalidTarget }
    }

}

/// Dormant ordinary scope: distinct operation registrations and receipt profiles.
/// These identifiers are not an admission decision; default production policy stays empty.
public enum OrdinarySystemScreenshotScope {
    public static let sourceID = SystemScreenshotWebCandidate.sourceID
    public static let uploadStartProfileID = "chatgpt-web-ordinary-system-screenshot-start-unadmitted-20261030-v1"
    public static let completionProfileID = "chatgpt-web-ordinary-system-screenshot-attached-unadmitted-20261030-v1"
    public static let admittedUploadStartProfileID = "chatgpt-web-ordinary-system-screenshot-start-20261030-v1"
    public static let admittedCompletionProfileID = "chatgpt-web-ordinary-system-screenshot-attached-20261030-v1"
    public static let profile = ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
        profileID: completionProfileID, completionSignal: .attached, uploadStartProfileID: uploadStartProfileID)
    public static let admittedProfile = ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
        profileID: admittedCompletionProfileID, completionSignal: .attached, uploadStartProfileID: admittedUploadStartProfileID)
    static func matches(_ profile: ObservationProfile) -> Bool {
        if OrdinaryCurrentDraftInternalScope.matches(profile) { return true }
        return profile.adapterID == "chatgpt-web" && profile.surface == .webChat && profile.completionSignal == .attached
            && profile.failureSignal == nil && ((profile.profileID == completionProfileID && profile.uploadStartProfileID == uploadStartProfileID)
                || (profile.profileID == admittedCompletionProfileID && profile.uploadStartProfileID == admittedUploadStartProfileID))
    }
}

/// Explicit internal test scope. No production receipt policy consumes these
/// profiles; candidate and historical ordinary registrations remain separate.
public enum OrdinaryCurrentDraftInternalScope {
    public static let uploadStartProfileID = "chatgpt-web-current-draft-internal-start-unadmitted-20261031-v1"
    public static let completionProfileID = "chatgpt-web-current-draft-internal-attached-unadmitted-20261031-v1"
    public static let admittedUploadStartProfileID = "chatgpt-web-current-draft-internal-start-20261031-v1"
    public static let admittedCompletionProfileID = "chatgpt-web-current-draft-internal-attached-20261031-v1"
    public static let profile = ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
        profileID: completionProfileID, completionSignal: .attached, uploadStartProfileID: uploadStartProfileID)
    public static let admittedProfile = ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
        profileID: admittedCompletionProfileID, completionSignal: .attached, uploadStartProfileID: admittedUploadStartProfileID)
    static func matches(_ profile: ObservationProfile) -> Bool {
        profile.adapterID == "chatgpt-web" && profile.surface == .webChat && profile.completionSignal == .attached
            && profile.failureSignal == nil && ((profile.profileID == completionProfileID && profile.uploadStartProfileID == uploadStartProfileID)
                || (profile.profileID == admittedCompletionProfileID && profile.uploadStartProfileID == admittedUploadStartProfileID))
    }
}
