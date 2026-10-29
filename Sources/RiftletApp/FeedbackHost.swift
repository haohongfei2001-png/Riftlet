import AppKit
import RiftletCore
import RiftletCapture
import RiftletFeedback
import RiftletFeedbackUI

/// The only host coupling. No Core/adapter writes and no raw trace ingestion.
@MainActor
final class FeedbackHost {
    let diagnostics = FeedbackDiagnostics()
    private var window: FeedbackWindowController?
    private var engine: FeedbackEngine?
    private var initialization: Task<Void,Never>?
    private var wantsWindow = false
    private var lastAssetCounts: [FeedbackFact:Int] = [:]
    private var lastPhaseCounts: [FeedbackFact:Int] = [:]
    private let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0"
    // Set only in a reviewed deployment commit after actual private-repo E2E.
    static let endpoint: URL? = URL(string: "https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback")
    init(modeDirectory: String) {
        diagnostics.record(.sessionStarted)
        let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
            .appendingPathComponent(modeDirectory).appendingPathComponent("Feedback-v01")
        initialization=Task { [weak self] in
            do {
                let store=try await Task.detached(priority:.utility){try FeedbackStore(directory:root)}.value
                guard let self else {return}
                let transport:any FeedbackTransport
                if let endpoint=Self.endpoint {transport=try HTTPSFeedbackTransport(endpoint:endpoint)} else {transport=DisabledFeedbackTransport()}
                self.engine=FeedbackEngine(store:store,secrets:KeychainFeedbackSecrets(namespace:modeDirectory),transport:transport)
                if store.wasUnclean {self.diagnostics.record(.previousSessionUnclean)}
                if self.wantsWindow {self.open()}
                await self.engine?.pump()
            } catch {if let self, self.wantsWindow {self.openUnavailable()}}
            self?.initialization=nil
        }
    }
    func open() {
        wantsWindow=true
        if let window {window.show();return}
        guard let engine else {if initialization == nil {openUnavailable()};return}
        let controller=FeedbackWindowController(engine:engine,diagnostics:diagnostics,appVersion:version)
        window=controller;controller.show()
    }
    private func openUnavailable() {let controller=FeedbackWindowController(engine:nil,diagnostics:diagnostics,appVersion:version);window=controller;controller.show()}
    func prepareTermination(_ reply:@escaping(Bool)->Void) {
        Task {
            if let window, !(await window.saveBeforeClosing(lockOnSuccess:true)) {window.show();reply(false);return}
            await engine?.stop();try? await engine?.store.markClean();reply(true)
        }
    }
    func capture(_ value:CaptureDiagnostic) {
        let fact:FeedbackFact
        switch value.code {
        case .insufficientStorage,.privateWriteFailed:fact = .privateStorageIssue
        case .sourceUnavailable,.sourcePreferenceUnreadable:fact = .captureSourceUnavailable
        case .unsupportedFormat,.imageTooLarge:fact = .captureUnsupported
        default:fact = .captureImportIssue
        }
        diagnostics.record(fact)
    }
    func assets(_ records:[AssetRecord]) {
        var counts:[FeedbackFact:Int]=[:]
        func add(_ fact:FeedbackFact){counts[fact,default:0]+=1}
        for record in records {
            switch record.visibility {case .visible:add(.visibilityVisible);case .swallowed:add(.visibilitySwallowed);case .archived:add(.visibilityArchived);case .removed:add(.visibilityRemoved)}
            switch record.status {case .pending:add(.queuePending);case .transferring:add(.queueTransferring);case .unknown:add(.queueUnknown);case .failed:add(.queueFailed);case .used:add(.queueUsed);case .missing:add(.queueMissing)}
            switch record.visibilityReason {case .capture:add(.reasonCapture);case .uploadStarted:add(.reasonUploadStarted);case .legacyCompletion:add(.reasonLegacyCompletion);case .automaticArchive:add(.reasonAutomaticArchive);case .userRemoved:add(.reasonUserRemoved);case .userRestored:add(.reasonUserRestored);case .safeFailure:add(.reasonSafeFailure)}
        }
        guard counts != lastAssetCounts else{return}
        let keys = Set(counts.keys).union(lastAssetCounts.keys); lastAssetCounts=counts
        for fact in keys.sorted(by:{$0.rawValue<$1.rawValue}){diagnostics.record(fact,count:counts[fact] ?? 0)}
    }
    func operations(_ operations:[TransferOperation]) {
        var counts:[FeedbackFact:Int]=[:]
        for operation in operations {
            let fact:FeedbackFact
            switch operation.phase {case .prepared:fact = .phasePrepared;case .dispatchIntent:fact = .phaseDispatchIntent;case .inputTriggered:fact = .phaseInputTriggered;case .attachmentPresent:fact = .phaseAttachmentPresent;case .unknown:fact = .phaseUnknown;case .compensated:fact = .phaseCompensated;case .failed:fact = .phaseFailed;case .succeeded:fact = .phaseSucceeded}
            counts[fact,default:0]+=1
        }
        guard counts != lastPhaseCounts else{return}
        let keys = Set(counts.keys).union(lastPhaseCounts.keys); lastPhaseCounts=counts
        for fact in keys.sorted(by:{$0.rawValue<$1.rawValue}){diagnostics.record(fact,count:counts[fact] ?? 0)}
    }
}
