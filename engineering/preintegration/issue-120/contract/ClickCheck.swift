import Foundation
import RiftletCore

@MainActor private final class HostFixture: BrowserHost {
    let bundle = "test.fixture.browser"
    var locator = HostCapabilities.Locator.stableNativeID
    var available = true
    var fault = ""
    var captured = 0
    var enqueued = 0
    var capabilities: HostCapabilities {
        .init(world: available ? .page : .unknown, reply: .originalAsynchronousReply,
              locator: locator, epoch: .navigationEntry,
              fileSetterAndDataTransferVerified: true, maximumPinBytes: 16_384)
    }
    func permissionState() -> OriginalReceiverAccess { fatalError("Ordinary pin requested a separate permission preflight") }
    func freezeClick() throws -> NativeClick {
        captured += 1
        return NativeClick(bundle: bundle, pid: 11, processBirth: "birth", session: "session",
                           window: "w", tab: "t", url: URL(string: "https://fixture.invalid/draft")!,
                           generation: UUID(), uptime: ProcessInfo.processInfo.systemUptime)
    }

    func enqueuePin(click: NativeClick, route: ProviderRoute, maximumBytes: Int) throws -> Task<PinReceipt, Error> {
        enqueued += 1
        precondition(maximumBytes == capabilities.maximumPinBytes)
        let actual = NativeClick(bundle: bundle, pid: click.pid,
                                 processBirth: fault == "birth" ? "restarted" : click.processBirth,
                                 session: click.session, window: click.window, tab: click.tab, url: click.url,
                                 generation: fault == "late" ? UUID() : click.generation, uptime: click.uptime)
        let target = TargetLease(adapterID: "fixture", surface: .webChat, applicationID: bundle,
                                 sessionID: click.session, windowID: click.window, tabID: click.tab,
                                 documentID: "document", composerID: "composer", draftGeneration: "epoch", clickBindingID: fault == "stalePin" ? UUID() : click.generation)
        let replyRoute = fault == "mode" ? ProviderRoute(profile: route.profile, route: .init(identity: "draft", surface: "chat", mode: "changed")) : route
        return Task { PinReceipt(click: actual, route: replyRoute, target: target) }
    }
}

@MainActor func checkClickBinding(provider: any ConversationProvider) async throws {
    let host = HostFixture()
    host.available = false
    precondition((try? BoundClick.capture(using: host, providers: [provider])) == nil)
    precondition(host.captured == 0 && host.enqueued == 0)
    host.available = true
    // Safari's observed index resolves to a replacement same-URL document. A
    // nonce first created after that swap or a warm-only witness cannot bind a cold click.
    for locator in [HostCapabilities.Locator.mutableTabIndex, .existingPageWitnessOnly, .unknown] {
        host.locator = locator
        precondition((try? BoundClick.capture(using: host, providers: [provider])) == nil)
    }
    precondition(host.captured == 0 && host.enqueued == 0)
    host.locator = .stableNativeID
    for fault in ["late", "birth", "mode", "stalePin", ""] {
        host.fault = fault
        let pending = try BoundClick.capture(using: host, providers: [provider])
        precondition(host.enqueued == host.captured)
        let original = try? await pending.value
        precondition((original != nil) == fault.isEmpty, fault)
        if let original { try await checkReadOnlyRestart(click: original) }
    }
    precondition(host.enqueued == 5)
}
