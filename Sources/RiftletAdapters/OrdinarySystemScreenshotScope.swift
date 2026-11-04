import Foundation
import RiftletCore

/// Interpretation scope only. This defines no ReceiptPolicy and cannot enable ordinary uploads.
public enum SystemScreenshotAdmissionScope: Sendable, Equatable {
    case candidate, ordinary, ordinaryCurrentDraftInternal
    /// One ordinary product, with separate immutable source qualifications.
    /// Neither case is a production approval or a second transport.
    case productSystem, productApplication

    public var legacyProfile: ObservationProfile {
        switch self {
        case .candidate: return SystemScreenshotWebCandidate.profile
        case .ordinary: return OrdinarySystemScreenshotScope.profile
        case .ordinaryCurrentDraftInternal: return OrdinaryCurrentDraftInternalScope.profile
        case .productSystem: return OrdinaryProductScreenshotScope.systemProfile
        case .productApplication: return OrdinaryProductScreenshotScope.applicationProfile
        }
    }
    public var admittedProfile: ObservationProfile {
        switch self {
        case .candidate: return SystemScreenshotWebCandidate.admittedProfile
        case .ordinary: return OrdinarySystemScreenshotScope.admittedProfile
        case .ordinaryCurrentDraftInternal: return OrdinaryCurrentDraftInternalScope.admittedProfile
        case .productSystem: return OrdinaryProductScreenshotScope.admittedSystemProfile
        case .productApplication: return OrdinaryProductScreenshotScope.admittedApplicationProfile
        }
    }
    var observationScope: DevelopmentObservationScope { self == .candidate ? .systemScreenshotCandidate : .ordinarySystemScreenshot }
    var admissionPrefix: String {
        switch self {
        case .candidate: return "system-screenshot-admission-v2"
        case .ordinary: return "ordinary-system-screenshot-admission-v1"
        case .ordinaryCurrentDraftInternal: return "ordinary-current-draft-internal-admission-v1"
        case .productSystem: return "ordinary-product-system-admission-v1"
        case .productApplication: return "ordinary-product-application-admission-v1"
        }
    }
    var journalPrefix: String {
        switch self {
        case .candidate: return "system-screenshot-candidate-observation-v1"
        case .ordinary: return "ordinary-system-screenshot-observation-v1"
        case .ordinaryCurrentDraftInternal: return "ordinary-current-draft-internal-observation-v1"
        case .productSystem: return "ordinary-product-system-observation-v1"
        case .productApplication: return "ordinary-product-application-observation-v1"
        }
    }
    public var origin: AssetOrigin { self == .productApplication ? .applicationScreenshot : .systemScreenshot }
    var isProduct: Bool { self == .productSystem || self == .productApplication }
    var originalObservationScopes: [Self] {
        switch self {
        case .ordinaryCurrentDraftInternal: return [.ordinary]
        case .productSystem: return [.ordinaryCurrentDraftInternal, .ordinary]
        default: return []
        }
    }
    func validateMetadata(_ asset: ImportedAsset) throws {
        try SystemScreenshotWebCandidate.validateMetadata(asset, expectedOrigin: origin)
    }
    func validateTarget(_ target: TargetLease) throws {
        guard self == .ordinaryCurrentDraftInternal || isProduct else {
            return try SystemScreenshotWebCandidate.validateAdmittedTarget(target)
        }
        // The ordinary tool binds the actual native tab, document and composer.
        // Its usable file input is established by the page, without React internals.
        guard target.adapterID == "chatgpt-web", target.surface == .webChat,
              target.applicationID == "com.google.Chrome",
              !target.sessionID.isEmpty, !target.windowID.isEmpty, target.tabID?.isEmpty == false,
              !target.documentID.isEmpty, !target.composerID.isEmpty, !target.draftGeneration.isEmpty else {
            throw WebAdapterError.invalidTarget
        }
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
        if OrdinaryProductScreenshotScope.matches(profile) { return true }
        return profile.adapterID == "chatgpt-web" && profile.surface == .webChat && profile.completionSignal == .attached
            && profile.failureSignal == nil && ((profile.profileID == completionProfileID && profile.uploadStartProfileID == uploadStartProfileID)
                || (profile.profileID == admittedCompletionProfileID && profile.uploadStartProfileID == admittedUploadStartProfileID))
    }
}

/// Source-qualified profiles for the single ordinary product. Runtime receipt
/// policy must independently admit each profile for its exact asset origin;
/// merely constructing these values grants no input, start, completion or retry.
public enum OrdinaryProductScreenshotScope {
    public static let systemContinuationProfileID = "chatgpt-web-product-system-request-owned-20261103-v1"
    public static let applicationContinuationProfileID = "chatgpt-web-product-application-request-owned-20261103-v1"
    public static let systemUploadStartProfileID = "chatgpt-web-product-system-start-20261102-v1"
    public static let systemCompletionProfileID = "chatgpt-web-product-system-attached-20261102-v1"
    public static let applicationUploadStartProfileID = "chatgpt-web-product-application-start-20261102-v1"
    public static let applicationCompletionProfileID = "chatgpt-web-product-application-attached-20261102-v1"
    public static let systemProfile = profile(origin: "system", admitted: false)
    public static let applicationProfile = profile(origin: "application", admitted: false)
    public static let admittedSystemProfile = profile(origin: "system", admitted: true)
    public static let admittedApplicationProfile = profile(origin: "application", admitted: true)

    private static func profile(origin: String, admitted: Bool) -> ObservationProfile {
        let suffix = admitted ? "20261102-v1" : "unadmitted-20261102-v1"
        return ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
            profileID: "chatgpt-web-product-\(origin)-attached-\(suffix)", completionSignal: .attached,
            uploadStartProfileID: "chatgpt-web-product-\(origin)-start-\(suffix)",
            continuationProfileID: admitted
                ? (origin == "system" ? systemContinuationProfileID : applicationContinuationProfileID) : nil)
    }
    static func matches(_ candidate: ObservationProfile) -> Bool {
        [systemProfile, applicationProfile, admittedSystemProfile, admittedApplicationProfile].contains { profile in
            candidate.adapterID == profile.adapterID && candidate.surface == profile.surface
                && candidate.completionSignal == profile.completionSignal && candidate.failureSignal == nil
                && candidate.profileID == profile.profileID && candidate.uploadStartProfileID == profile.uploadStartProfileID
                && candidate.continuationProfileID == profile.continuationProfileID
        }
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
