import Foundation
import RiftletCore
import RiftletAdapters

/// Separate evidence decisions from 493d1d8: SC-START and SC-COMPLETE are admitted
/// only for registered new operations in the restricted internal candidate.
/// Historical v1, safe failure/retry and ordinary production remain unadmitted.
/// These maps are code-owned, never read from arguments, defaults or page JSON.
enum SystemScreenshotCandidateConfiguration {
    static let uploadStartProfiles: [String: TargetSurface] = [SystemScreenshotWebCandidate.admittedUploadStartProfileID: .webChat]
    static let completedAttachmentProfiles: [String: TargetSurface] = [SystemScreenshotWebCandidate.admittedCompletionProfileID: .webChat]
    static let safeFailureProfiles: [String: TargetSurface] = [:]
    static let receiptPolicy = ReceiptPolicy(admittedProfiles: completedAttachmentProfiles,
        retrySafeProfiles: safeFailureProfiles, uploadStartProfiles: uploadStartProfiles)

    static func validateStore(_ store: QueueStore) async throws {
        guard await store.mode == .production,
              try await store.assets(includeUsed: true).allSatisfy({ $0.image.origin != .synthetic }) else {
            throw RiftletError.modeMismatch
        }
        // Edited/unmarked in-app images may be retained in this same history.
        // The adapter still rejects them before input; ReceiptPolicy also denies
        // all three admissions. Retaining a local image is not upload authority.
    }
}

/// This factory is used by the App and software integration tests. Constructing
/// a closed ordinary-capture composition never initializes the Chrome executor.
struct ApplicationAttachmentComposition {
    let adapter: any AttachmentAdapter
    let policy: ReceiptPolicy

    @MainActor static func make(mode: ApplicationMode, root: URL, store: QueueStore,
                                executor: (any WebBridgeExecutor)? = nil,
                                traceEnabled: Bool = false,
                                polling: WebObservationPolling = .acceptance,
                                ordinary: OrdinaryAttachmentAdmission = OrdinaryCaptureConfiguration.admission) throws -> Self {
        let media = root.appendingPathComponent("media")
        switch mode {
        case .capture:
            // Closed means no Chrome executor, page load, permission probe or
            // registration. Test injection here is not a runtime switch.
            guard ordinary.allowsInput else { return Self(adapter: UnavailableAdapter(), policy: .init()) }
            return Self(adapter: WebAttachmentAdapter(mediaDirectory: media,
                executor: executor ?? ChromeAppleEventsExecutor(traceEnabled: traceEnabled),
                program: try ChatGPTWebPageProgram.load(), mode: .ordinarySystemScreenshot,
                profile: ordinary.observationProfile, polling: polling,
                candidateJournal: SystemScreenshotObservationJournal(store: store, scope: ordinary.targetScope),
                candidateAdmission: SystemScreenshotCandidateAdmission(store: store, scope: ordinary.targetScope)),
                policy: ordinary.receiptPolicy)
        case .simulation: return Self(adapter: SimulationAdapter(), policy: .init())
        case .webAcceptance:
            return Self(adapter: WebAttachmentAdapter(mediaDirectory: media,
                executor: executor ?? ChromeAppleEventsExecutor(traceEnabled: traceEnabled),
                program: try ChatGPTWebPageProgram.load(), mode: .syntheticDevelopment,
                profile: ChatGPTWebPageProgram.acceptanceProfile, polling: polling),
                policy: WebAcceptanceConfiguration.receiptPolicy)
        case .systemScreenshotCandidate:
            return Self(adapter: WebAttachmentAdapter(mediaDirectory: media,
                executor: executor ?? ChromeAppleEventsExecutor(traceEnabled: traceEnabled),
                program: try ChatGPTWebPageProgram.load(), mode: .systemScreenshotCandidate,
                profile: SystemScreenshotWebCandidate.profile, polling: polling,
                candidateJournal: SystemScreenshotObservationJournal(store: store),
                candidateAdmission: SystemScreenshotCandidateAdmission(store: store)),
                policy: SystemScreenshotCandidateConfiguration.receiptPolicy)
        }
    }
}
