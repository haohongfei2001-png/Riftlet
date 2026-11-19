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
    static let priorEncodedSource = "chatgpt-web-click-document-witness-20261118-v24"
    static let priorEncodedEvidence = "click-document-witness-20261118-v24"
    static let priorStagedSource = "chatgpt-web-click-document-witness-20261118-v26"
    static let priorStagedEvidence = "click-document-witness-20261118-v26"
    static let priorDraftContentSource = "chatgpt-web-click-document-witness-20261118-v27"
    static let priorRootContentSource = "chatgpt-web-click-document-witness-20261119-v28"
    static let edgeSourceID = "chatgpt-web-click-document-witness-20261119-v29"
    static let draftContentEvidenceV27 = "click-document-witness-20261118-v27"
    static let draftContentEvidenceV28 = "click-document-witness-20261119-v28"
    static let edgeEvidenceID = "click-document-witness-20261119-v29"
    static func isEdgeExclusive(_ source: String) -> Bool {
        [priorEncodedSource, priorStagedSource, priorDraftContentSource, priorRootContentSource, edgeSourceID].contains(source)
    }
    static let priorProductSource = "chatgpt-web-screenshot-observation-20261118-v18"
    static let priorProductCardSource = "chatgpt-web-screenshot-card-observation-20261118-v19"
    static let priorUnifiedSource = "chatgpt-web-click-document-witness-20261118-v23"
    public static let sourceID = "chatgpt-web-click-document-witness-20261118-v25"
    /// Candidate mapping only; ReceiptPolicy start registries remain separate.
    public static let acceptanceUploadStartProfileID = "chatgpt-web-zh-progress-start-development-20261027-v1"
    public static let acceptanceProfile = ObservationProfile(
        adapterID: "chatgpt-web", surface: .webChat,
        profileID: "chatgpt-web-zh-attached-development-20261027-v2",
        completionSignal: .attached, uploadStartProfileID: acceptanceUploadStartProfileID)

    static func currentSourceID(for target: TargetLease) -> String {
        target.applicationID == EdgeApplicationHost.bundleID ? edgeSourceID : sourceID
    }

    // v18 through v22 also shipped on Chrome before the implementations diverged.
    // A fenced operation supplies both its source and its native target.
    static func edgeEvidence(for source: String) -> String? {
        switch source {
        case edgeSourceID: return edgeEvidenceID
        case priorRootContentSource: return draftContentEvidenceV28
        case priorEncodedSource: return priorEncodedEvidence
        case priorStagedSource: return priorStagedEvidence
        case priorDraftContentSource: return draftContentEvidenceV27
        case priorEdgeSource: return "click-document-witness-20261117-v22"
        case priorLabelSource: return "click-document-witness-20261117-v21"
        case priorProgressSource: return "click-document-witness-20261117-v20"
        case priorOriginSource: return "click-document-witness-20261117-v19"
        case priorClickSource: return "click-document-witness-20261114-v18"
        default: return nil
        }
    }

    static let edgeProgram = Result {
        // v29 uses the exact v28 content proof. Only the new resident identity
        // changes; native code interprets its new registrations as draft acceptance.
        var source = try originalRootContentProgram.get().functionSource
        for (original, replacement) in [
            ("__riftletEdgeFileInput20261119v28", "__riftletEdgeFileInput20261119v29"),
            (draftContentEvidenceV28, edgeEvidenceID)
        ] {
            let parts = source.components(separatedBy: original)
            guard parts.count == 2 else { throw WebAdapterError.programUnavailable }
            source = parts.joined(separator: replacement)
        }
        return WebPageProgram(sourceID: edgeSourceID, functionSource: source,
                              maximumChunkBytes: 256 * 1024, inputDiscoveryTimeout: 3)
    }

    private static let originalRootContentProgram = Result {
        let previous = try originalDraftContentProgram.get()
        let owner = try resourceSource("edge-draft-content-owner-v28")
        let priorPredicate = """
        const popup = labels.filter(node => node !== scope && node.tagName === 'DIV' &&
                  visual.contains(node) && node.contains(image));
        """
        var source = previous.functionSource
        for (original, replacement) in [
            (priorPredicate, "const popup = (" + owner + ")(filename, labels, scope, visual, image, remove);"),
            ("__riftletEdgeFileInput20261118v27", "__riftletEdgeFileInput20261119v28"),
            (draftContentEvidenceV27, draftContentEvidenceV28)
        ] {
            let parts = source.components(separatedBy: original)
            guard parts.count == 2 else { throw WebAdapterError.programUnavailable }
            source = parts.joined(separator: replacement)
        }
        guard source.utf8.count <= 128 * 1024 else { throw WebAdapterError.programUnavailable }
        return WebPageProgram(sourceID: priorRootContentSource, functionSource: source,
                              maximumChunkBytes: 256 * 1024, inputDiscoveryTimeout: 3)
    }

    private static let originalDraftContentProgram = Result {
        try loadEdgeProgram(templateName: "chatgpt-web-edge-v27", watcherName: "edge-encoded-preview-v27",
                            source: priorDraftContentSource, evidence: draftContentEvidenceV27)
    }

    private static let originalStagedProgram = Result {
        try loadEdgeProgram(templateName: "chatgpt-web-edge-v26", watcherName: "edge-encoded-preview-v26",
                            source: priorStagedSource, evidence: priorStagedEvidence)
    }

    private static let originalEncodedProgram = Result {
        try loadEdgeProgram(templateName: "chatgpt-web-edge-v24", watcherName: "edge-encoded-preview",
                            source: priorEncodedSource, evidence: priorEncodedEvidence)
    }

    private static func loadEdgeProgram(templateName: String, watcherName: String, source: String, evidence: String) throws -> WebPageProgram {
        let script = try assembleEdgeProgram(template: resourceSource(templateName), watcher: resourceSource(watcherName),
                                             evidence: evidence)
        return WebPageProgram(sourceID: source, functionSource: script,
                              maximumChunkBytes: 256 * 1024, inputDiscoveryTimeout: 3)
    }

    static func assembleEdgeProgram(template: String, watcher: String, evidence: String = edgeEvidenceID) throws -> String {
        let marker = "/*__RIFTLET_ENCODED_PREVIEW_WATCHER__*/"
        let sections = template.components(separatedBy: marker)
        guard sections.count == 2, !watcher.contains(marker),
              watcher.components(separatedBy: "function watchEdgeEncodedPreview(file, name)").count == 2,
              template.contains(evidence) else { throw WebAdapterError.programUnavailable }
        let source = sections.joined(separator: watcher)
        guard source.utf8.count <= 128 * 1024 else { throw WebAdapterError.programUnavailable }
        return source
    }

    public static func load() throws -> WebPageProgram {
        try load(resource: "chatgpt-web-20261027", id: sourceID)
    }

    static func originalObservationProgram(sourceID: String) throws -> WebPageProgram? {
        switch sourceID {
        case priorEncodedSource: return try originalEncodedProgram.get()
        case priorStagedSource: return try originalStagedProgram.get()
        case priorDraftContentSource: return try originalDraftContentProgram.get()
        case priorRootContentSource: return try originalRootContentProgram.get()
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
        case priorProductCardSource:
            return try load(resource: "chatgpt-web-observe-product-v19", id: priorProductCardSource)
        case priorUnifiedSource:
            return try load(resource: "chatgpt-web-observe-v23", id: priorUnifiedSource)
        case priorProductSource:
            return try load(resource: "chatgpt-web-observe-product-v18", id: priorProductSource)
        case priorLabelSource:
            return try load(resource: "chatgpt-web-observe-v21", id: priorLabelSource)
        default:
            return nil
        }
    }

    static func isHistoricalObserver(_ sourceID: String) -> Bool {
        [priorEntrySource, priorHandoffSource, priorScreenshotSource, priorClickSource, priorOriginSource, priorProgressSource, priorLabelSource, priorEdgeSource, priorProductSource, priorProductCardSource, priorUnifiedSource, priorEncodedSource, priorStagedSource, priorDraftContentSource, priorRootContentSource].contains(sourceID)
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
        WebPageProgram(sourceID: id, functionSource: try resourceSource(resource),
                       maximumChunkBytes: 256 * 1024, inputDiscoveryTimeout: 3)
    }

    private static func resourceSource(_ resource: String) throws -> String {
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
        return source
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
