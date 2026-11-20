import CryptoKit
import Foundation
import RiftletCore

enum BindingError: Error { case unsupported, ambiguous, invalidProfile, targetChanged }

/// A digest and revision name one bundled program, including its event recipe.
struct ProviderProfile: Hashable, Sendable {
    let id: String
    let revision: Int
    let digest: String

    init(id: String, revision: Int, program: Data) throws {
        guard !id.isEmpty, revision > 0, !program.isEmpty else { throw BindingError.invalidProfile }
        self.id = id
        self.revision = revision
        self.digest = SHA256.hash(data: program).map { String(format: "%02x", $0) }.joined()
    }
}

struct NativeClick: Equatable, Sendable {
    let bundle: String
    let pid: Int32
    let processBirth: String
    let session: String
    let window: String
    let tab: String
    let url: URL
    let generation: UUID
    let uptime: TimeInterval
}

struct DraftRoute: Hashable, Sendable {
    let identity: String
    let surface: String
    let mode: String
}

protocol ConversationProvider: Sendable {
    var profile: ProviderProfile { get }
    var httpsHosts: Set<String> { get }
    /// A native URL can nominate a provider. Whether a composer owns a file input
    /// and its current mode admits images must still be verified at the original page.
    func classify(_ url: URL) -> DraftRoute?
}

struct ProviderRoute: Hashable, Sendable {
    let profile: ProviderProfile
    let route: DraftRoute
}

func resolveProvider(_ url: URL, among providers: [any ConversationProvider]) throws -> ProviderRoute {
    guard let u = URLComponents(url: url, resolvingAgainstBaseURL: false),
          u.scheme?.lowercased() == "https", u.user == nil, u.password == nil,
          u.port == nil || u.port == 443,
          let host = u.percentEncodedHost?.lowercased(), !host.isEmpty,
          !host.contains("%") else { throw BindingError.unsupported }
    let matches = providers.compactMap { provider -> ProviderRoute? in
        guard provider.httpsHosts.contains(host), let route = provider.classify(url) else { return nil }
        return ProviderRoute(profile: provider.profile, route: route)
    }
    guard let first = matches.first else { throw BindingError.unsupported }
    guard matches.count == 1 else { throw BindingError.ambiguous }
    return first
}

struct HostCapabilities: Sendable {
    enum World: Sendable { case page, isolated, unknown }
    enum Reply: Sendable { case originalAsynchronousReply, synchronousOnly, unknown }
    enum Locator: Sendable { case stableNativeID, pageBoundOpaqueLocator, unknown }
    enum Epoch: Sendable { case navigationEntry, verifiedAlternative, unknown }
    let world: World
    let reply: Reply
    let locator: Locator
    let epoch: Epoch
    let fileSetterAndDataTransferVerified: Bool
    let maximumPinBytes: Int
}

@MainActor protocol BrowserHost: AnyObject {
    var bundle: String { get }
    var capabilities: HostCapabilities { get }
    func permissionState() -> OriginalReceiverAccess
    func freezeClick() throws -> NativeClick
    /// Enqueue the lightweight pin here, synchronously at the original click.
    /// Only waiting for that exact, original reply is deferred.
    func enqueuePin(click: NativeClick, route: ProviderRoute) throws -> Task<TargetLease, Error>
}

struct BoundClick: Sendable {
    let native: NativeClick
    let route: ProviderRoute
    let target: TargetLease

    @MainActor static func capture(using host: any BrowserHost, providers: [any ConversationProvider]) throws -> Task<Self, Error> {
        let click = try host.freezeClick()
        guard click.bundle == host.bundle, click.pid > 0, !click.processBirth.isEmpty,
              !click.window.isEmpty, !click.tab.isEmpty, !click.session.isEmpty,
              host.permissionState() == .granted else { throw BindingError.unsupported }
        let route = try resolveProvider(click.url, among: providers)
        let originalReply = try host.enqueuePin(click: click, route: route)
        return Task {
            let target = try await originalReply.value
            guard target.applicationID == click.bundle, target.sessionID == click.session,
                  target.windowID == click.window, target.tabID == click.tab,
                  target.surface == .webChat, target.clickBindingID != nil,
                  !target.documentID.isEmpty, !target.composerID.isEmpty,
                  !target.draftGeneration.isEmpty else { throw BindingError.targetChanged }
            return Self(native: click, route: route, target: target)
        }
    }

    private init(native: NativeClick, route: ProviderRoute, target: TargetLease) {
        self.native = native
        self.route = route
        self.target = target
    }
}

struct AdapterAddress: Hashable, Sendable {
    let bundle: String
    let profile: ProviderProfile
    let adapterID: String
}

/// Never expose a writer through the historical lookup.
struct OriginalReader: Sendable {
    private let adapter: any IndependentFileInputAdapter
    private let operation: TransferOperation

    fileprivate init(adapter: any IndependentFileInputAdapter, operation: TransferOperation) {
        self.adapter = adapter
        self.operation = operation
    }

    func observe(_ request: TransferRequest) async throws -> TransferReceipt {
        guard request.operation.id == operation.id, request.operation.target == operation.target,
              request.operation.attempt == operation.attempt, request.operation.assetID == operation.assetID,
              request.asset.id == operation.assetID else { throw BindingError.targetChanged }
        return try await adapter.reconcile(request)
    }
}

struct AdapterResolver: Sendable {
    let adapters: [AdapterAddress: any IndependentFileInputAdapter]

    func adapter(for click: BoundClick) throws -> any IndependentFileInputAdapter {
        try exactAdapter(AdapterAddress(bundle: click.native.bundle, profile: click.route.profile,
                                        adapterID: click.target.adapterID))
    }

    /// Caller supplies the ORIGINAL stored profile. A missing legacy profile has
    /// no generic fallback; the legacy read-only decoder remains with build 53.
    func reader(for operation: TransferOperation, storedProfile: ProviderProfile) throws -> OriginalReader {
        let address = AdapterAddress(bundle: operation.target.applicationID, profile: storedProfile,
                                     adapterID: operation.target.adapterID)
        return try OriginalReader(adapter: exactAdapter(address), operation: operation)
    }

    private func exactAdapter(_ address: AdapterAddress) throws -> any IndependentFileInputAdapter {
        guard let adapter = adapters[address], adapter.id == address.adapterID else { throw BindingError.unsupported }
        return adapter
    }
}
