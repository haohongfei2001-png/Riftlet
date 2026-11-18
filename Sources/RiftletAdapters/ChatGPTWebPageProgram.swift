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
    static let priorClickSource = "chatgpt-web-click-document-witness-20261114-v18"
    static let priorOriginSource = "chatgpt-web-click-document-witness-20261117-v19"
    static let priorProgressSource = "chatgpt-web-click-document-witness-20261117-v20"
    static let priorLabelSource = "chatgpt-web-click-document-witness-20261117-v21"
    static let priorEdgeSource = "chatgpt-web-click-document-witness-20261117-v22"
    static let priorProductSource = "chatgpt-web-screenshot-observation-20261118-v18"
    public static let sourceID = "chatgpt-web-click-document-witness-20261118-v23"
    /// Candidate mapping only; ReceiptPolicy start registries remain separate.
    public static let acceptanceUploadStartProfileID = "chatgpt-web-zh-progress-start-development-20261027-v1"
    public static let acceptanceProfile = ObservationProfile(
        adapterID: "chatgpt-web", surface: .webChat,
        profileID: "chatgpt-web-zh-attached-development-20261027-v2",
        completionSignal: .attached, uploadStartProfileID: acceptanceUploadStartProfileID)

    // Edge keeps the exact page bytes and receipt registration exercised by
    // PR #69. Chrome uses the new program with the 1.0.5 lifecycle changes.
    static func currentSourceID(for target: TargetLease) -> String {
        target.applicationID == EdgeApplicationHost.bundleID ? priorEdgeSource : sourceID
    }

    static let edgeProgram = Result { try load(resource: "chatgpt-web-observe-v22", id: priorEdgeSource) }

    public static func load() throws -> WebPageProgram {
        try load(resource: "chatgpt-web-20261027", id: sourceID)
    }

    static func originalObservationProgram(sourceID: String) throws -> WebPageProgram? {
        switch sourceID {
        case priorEntrySource, priorHandoffSource, priorScreenshotSource:
            // v15/v16 already used the v17 observer at the previous baseline.
            return try load(resource: "chatgpt-web-observe-v17", id: priorScreenshotSource)
        case priorClickSource:
            return try load(resource: "chatgpt-web-observe-v18", id: priorClickSource)
        case priorOriginSource:
            return try load(resource: "chatgpt-web-observe-v19", id: priorOriginSource)
        case priorProgressSource:
            return try load(resource: "chatgpt-web-observe-v20", id: priorProgressSource)
        case priorEdgeSource:
            return try load(resource: "chatgpt-web-observe-v22", id: priorEdgeSource)
        case priorProductSource:
            return try load(resource: "chatgpt-web-observe-product-v18", id: priorProductSource)
        case priorLabelSource:
            return try load(resource: "chatgpt-web-observe-v21", id: priorLabelSource)
        default:
            return nil
        }
    }

    static func isHistoricalObserver(_ sourceID: String) -> Bool {
        [priorEntrySource, priorHandoffSource, priorScreenshotSource, priorClickSource, priorOriginSource, priorProgressSource, priorLabelSource, priorEdgeSource, priorProductSource].contains(sourceID)
    }

    static func observationRelayFunctions(for program: WebPageProgram) throws -> [String] {
        // Main and the earlier v17 used one registration ID but installed
        // different byte-for-byte functions. Only a unique resident channel
        // may distinguish those registrations after a native restart.
        guard program.sourceID == priorScreenshotSource else { return [program.functionSource] }
        let main = try load(resource: "chatgpt-web-observe-v17-main", id: priorScreenshotSource)
        return [program.functionSource, main.functionSource]
    }

    private static func load(resource: String, id: String) throws -> WebPageProgram {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Riftlet_RiftletAdapters.bundle"),
                  let packaged = Bundle(url: url) else { throw WebAdapterError.programUnavailable }
            resources = packaged
        } else {
            resources = Bundle.module
        }
        guard let url = resources.url(forResource: resource, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8), !source.isEmpty,
              source.utf8.count <= 128 * 1024 else { throw WebAdapterError.programUnavailable }
        // Ordinary input never executes historical observers. Their registries
        // cannot veto a new handoff; the separate legacy reader remains available
        // only to explicit historical tooling.
        return WebPageProgram(sourceID: id, functionSource: source,
                              maximumChunkBytes: 256 * 1024, inputDiscoveryTimeout: 3)
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
