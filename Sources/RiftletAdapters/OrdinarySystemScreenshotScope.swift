import Foundation
import RiftletCore

/// Interpretation scope only. This defines no ReceiptPolicy and cannot enable ordinary uploads.
public enum SystemScreenshotAdmissionScope: Sendable, Equatable {
    case candidate, ordinary

    var legacyProfile: ObservationProfile { self == .candidate ? SystemScreenshotWebCandidate.profile : OrdinarySystemScreenshotScope.profile }
    var admittedProfile: ObservationProfile { self == .candidate ? SystemScreenshotWebCandidate.admittedProfile : OrdinarySystemScreenshotScope.admittedProfile }
    var observationScope: DevelopmentObservationScope { self == .candidate ? .systemScreenshotCandidate : .ordinarySystemScreenshot }
    var admissionPrefix: String { self == .candidate ? "system-screenshot-admission-v2" : "ordinary-system-screenshot-admission-v1" }
    var journalPrefix: String { self == .candidate ? "system-screenshot-candidate-observation-v1" : "ordinary-system-screenshot-observation-v1" }
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
        profile.adapterID == "chatgpt-web" && profile.surface == .webChat && profile.completionSignal == .attached
            && profile.failureSignal == nil && ((profile.profileID == completionProfileID && profile.uploadStartProfileID == uploadStartProfileID)
                || (profile.profileID == admittedCompletionProfileID && profile.uploadStartProfileID == admittedUploadStartProfileID))
    }
}
