import Foundation
import RiftletCore

/// Narrow development profile derived from the archived, real Apple Events
/// experiments at 6f415698. This resource is an integrated implementation, not
/// evidence that the integrated app has passed a live test. Production admission
/// remains separate. Generated acceptance and the explicitly isolated original-
/// screenshot candidate use distinct native scopes; page provenance is unchanged.
public enum ChatGPTWebPageProgram {
    static let priorEntrySource = "chatgpt-web-attachment-entry-20261105-v15"
    static let priorHandoffSource = "chatgpt-web-attachment-handoff-20261105-v16"
    static let priorScreenshotSource = "chatgpt-web-screenshot-handoff-20261105-v17"
    static let priorObservationSource = "chatgpt-web-screenshot-observation-20261118-v18"
    static let priorCardObservationSource = "chatgpt-web-screenshot-card-observation-20261118-v19"
    static let priorOriginalReviewSource = "chatgpt-web-screenshot-original-review-20261118-v20"
    static let priorMemberStatusSource = "chatgpt-web-screenshot-member-status-20261119-v21"
    static let priorObservedStartSource = "chatgpt-web-screenshot-observed-start-20261119-v22"
    static let priorOwnedPreviewSource = "chatgpt-web-screenshot-owned-preview-20261119-v23"
    static let priorProgressCardSource = "chatgpt-web-screenshot-progress-card-20261119-v24"
    static let priorRetryOverlaySource = "chatgpt-web-screenshot-retry-overlay-20261119-v25"
    public static let sourceID = "chatgpt-web-browser-handoff-20261120-v30"
    /// Candidate mapping only; ReceiptPolicy start registries remain separate.
    public static let acceptanceUploadStartProfileID = "chatgpt-web-zh-progress-start-development-20261027-v1"
    public static let acceptanceProfile = ObservationProfile(
        adapterID: "chatgpt-web", surface: .webChat,
        profileID: "chatgpt-web-zh-attached-development-20261027-v2",
        completionSignal: .attached, uploadStartProfileID: acceptanceUploadStartProfileID)

    public static func load() throws -> WebPageProgram {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Riftlet_RiftletAdapters.bundle"),
                  let packaged = Bundle(url: url) else { throw WebAdapterError.programUnavailable }
            resources = packaged
        } else {
            resources = Bundle.module
        }
        guard let url = resources.url(forResource: "chatgpt-web-20261027", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8), !source.isEmpty,
              source.utf8.count <= 128 * 1024 else { throw WebAdapterError.programUnavailable }
        // The click-time Apple Event transmits only the shared resolver and witness.
        // Resource layout is verified before either program can run.
        let sections = source.components(separatedBy: "\n  // RIFTLET_CLICK_PIN_END\n")
        guard sections.count == 2, !sections[0].isEmpty, !sections[1].isEmpty else {
            throw WebAdapterError.programUnavailable
        }
        let pinSource = sections[0] + "\n  return 'refused';\n}"
        // Ordinary input never executes historical observers. Their registries
        // cannot veto a new handoff; the separate legacy reader remains available
        // only to explicit historical tooling.
        return WebPageProgram(sourceID: sourceID, functionSource: source,
                              maximumChunkBytes: 256 * 1024, inputDiscoveryTimeout: 3, pinSource: pinSource)
    }
}

/// A time budget limits observation work; elapsed time never proves completion.
/// Tests can disable waiting without changing any completion or retry policy.
public struct WebObservationPolling: Sendable {
    public let timeout: TimeInterval
    public let interval: TimeInterval
    public static let acceptance = WebObservationPolling()
    public static let disabled = WebObservationPolling(timeout: 0)

    public init(timeout: TimeInterval = 10, interval: TimeInterval = 0.25) {
        self.timeout = timeout.isFinite ? min(30, max(0, timeout)) : 0
        self.interval = interval.isFinite ? min(2, max(0.01, interval)) : 0.25
    }
}
