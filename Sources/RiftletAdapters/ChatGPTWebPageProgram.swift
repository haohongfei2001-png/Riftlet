import Foundation
import RiftletCore

/// Narrow development profile derived from the archived, real Apple Events
/// experiments at 6f415698. This resource is an integrated implementation, not
/// evidence that the integrated app has passed a live test. Production admission
/// remains separate; only syntheticDevelopment may execute it in this increment.
public enum ChatGPTWebPageProgram {
    public static let sourceID = "chatgpt-web-zh-20261027-integrated-v10"
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
        return try LegacyWebObservationProgram.wrapping(WebPageProgram(sourceID: sourceID, functionSource: source))
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
