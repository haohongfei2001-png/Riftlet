import Foundation
import RiftletCore
import RiftletAdapters

/// Input scope and evidence admission are distinct. The explicit candidate can
/// collect original system files and exercise the existing one-input bridge;
/// these THREE registries remain empty until real screenshot evidence is reviewed.
/// They are code-owned, never read from arguments, defaults, plist or page JSON.
enum SystemScreenshotCandidateConfiguration {
    static let uploadStartProfiles: [String: TargetSurface] = [:]
    static let completedAttachmentProfiles: [String: TargetSurface] = [:]
    static let safeFailureProfiles: [String: TargetSurface] = [:]
    static let receiptPolicy = ReceiptPolicy(admittedProfiles: completedAttachmentProfiles,
        retrySafeProfiles: safeFailureProfiles, uploadStartProfiles: uploadStartProfiles)

    static func validateStore(_ store: QueueStore) async throws {
        guard await store.mode == .production,
              try await store.assets(includeUsed: true).allSatisfy({ $0.image.origin == .systemScreenshot }) else {
            throw RiftletError.modeMismatch
        }
    }
}

/// This factory is used by the App and software integration tests. Constructing
/// an ordinary-capture composition never initializes the Chrome executor.
struct ApplicationAttachmentComposition {
    let adapter: any AttachmentAdapter
    let policy: ReceiptPolicy

    @MainActor static func make(mode: ApplicationMode, root: URL, store: QueueStore,
                                executor: (any WebBridgeExecutor)? = nil,
                                traceEnabled: Bool = false,
                                polling: WebObservationPolling = .acceptance) throws -> Self {
        let media = root.appendingPathComponent("media")
        switch mode {
        case .capture: return Self(adapter: UnavailableAdapter(), policy: .init())
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
                candidateJournal: SystemScreenshotObservationJournal(store: store)),
                policy: SystemScreenshotCandidateConfiguration.receiptPolicy)
        }
    }
}
