import Foundation
import RiftletCore

/// Candidate composition. Existing ChatGPT input retains the same executor and
/// exact native lease; new site profiles need their own admitted transport.
@MainActor public final class DevelopmentAttachmentRouting {
    private let chatHosts: [String: ChatGPTChromiumHost]
    private let catalog: Issue120ProviderCatalog
    private let runtime: ProviderAttachmentRuntime

    public convenience init(executor: ChromeAppleEventsExecutor, store: QueueStore) throws {
        try self.init(executor: executor, store: store, adapters: [:])
    }

    init(executor: ChromeAppleEventsExecutor, store: QueueStore,
         adapters: [AdapterAddress: any IndependentFileInputAdapter]) throws {
        catalog = try Issue120ProviderCatalog()
        let program = try ChatGPTWebPageProgram.load()
        var hosts = [String: ChatGPTChromiumHost]()
        for browser in AttachmentBrowser.allCases {
            hosts[browser.rawValue] = try ChatGPTChromiumHost(browser: browser, executor: executor, program: program,
                                                       discoveryCatalog: catalog) {
                CandidateReceiver.forSettings(browser.rawValue)?.automationState() ?? .unavailable
            }
        }
        chatHosts = hosts
        runtime = ProviderAttachmentRuntime(resolver: AdapterResolver(adapters: adapters), store: store)
    }

    public var additionalAdapters: [String: any IndependentFileInputAdapter] { [runtime.id: runtime] }

    public func targetForClick(in bundle: String) throws -> Task<TargetLease, Error> {
        let pending: Task<BoundClick, Error>
        if let host = chatHosts[bundle] {
            pending = try BoundClick.capture(using: host, providers: [host.provider] + catalog.providers)
        } else if let host = CandidateBrowserHosts.host(for: bundle) {
            pending = try BoundClick.capture(using: host, providers: catalog.providers)
        } else {
            throw BindingError.unsupported
        }
        return Task { try await pending.value.target }
    }
}
