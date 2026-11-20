import CryptoKit
import Foundation
import RiftletCore

enum BindingError: Error { case unsupported, ambiguous, invalidProfile, targetChanged }

/// A digest and revision name one bundled program, including its event recipe.
struct ProviderProfile: Codable, Hashable, Sendable {
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
    enum Locator: Sendable {
        case stableNativeID, verifiedClickBoundarySnapshot
        case existingPageWitnessOnly, mutableTabIndex, unknown

        var supportsColdClick: Bool {
            switch self {
            case .stableNativeID, .verifiedClickBoundarySnapshot: return true
            case .existingPageWitnessOnly, .mutableTabIndex, .unknown: return false
            }
        }
    }
    enum Epoch: Sendable { case navigationEntry, verifiedAlternative, unknown }
    let world: World
    let reply: Reply
    let locator: Locator
    let epoch: Epoch
    let fileSetterAndDataTransferVerified: Bool
    let maximumPinBytes: Int

    var supportsPin: Bool {
        world == .page && reply == .originalAsynchronousReply && locator.supportsColdClick &&
        epoch != .unknown && fileSetterAndDataTransferVerified && maximumPinBytes > 0
    }
}

/// Assembled by the host from its original event/reply channel and the
/// document witness. Copying later active-window state cannot establish these fields.
struct PinReceipt: Sendable {
    let click: NativeClick
    let route: ProviderRoute
    let target: TargetLease
}

@MainActor protocol BrowserHost: AnyObject {
    var bundle: String { get }
    var capabilities: HostCapabilities { get }
    // Settings only. The ordinary click lets the OS decide on the actual event.
    func permissionState() -> OriginalReceiverAccess
    func freezeClick() throws -> NativeClick
    /// Enqueue the lightweight pin here, synchronously at the original click.
    /// Only waiting for that exact, original reply is deferred.
    func enqueuePin(click: NativeClick, route: ProviderRoute, maximumBytes: Int) throws -> Task<PinReceipt, Error>
}

struct BoundClick: Sendable {
    let native: NativeClick
    let route: ProviderRoute
    let target: TargetLease

    @MainActor static func capture(using host: any BrowserHost, providers: [any ConversationProvider]) throws -> Task<Self, Error> {
        let capabilities = host.capabilities
        guard capabilities.supportsPin else { throw BindingError.unsupported }
        let click = try host.freezeClick()
        guard click.bundle == host.bundle, click.pid > 0, !click.processBirth.isEmpty,
              !click.window.isEmpty, !click.tab.isEmpty, !click.session.isEmpty else { throw BindingError.unsupported }
        let route = try resolveProvider(click.url, among: providers)
        let originalReply = try host.enqueuePin(click: click, route: route, maximumBytes: capabilities.maximumPinBytes)
        return Task {
            let receipt = try await originalReply.value
            let target = receipt.target
            guard receipt.click == click, receipt.route == route, target.applicationID == click.bundle, target.sessionID == click.session,
                  target.windowID == click.window, target.tabID == click.tab,
                  target.surface == .webChat, target.clickBindingID != nil,
                  !target.documentID.isEmpty, !target.composerID.isEmpty,
                  !target.draftGeneration.isEmpty else { throw BindingError.targetChanged }
            let binding = WebProviderBinding(providerID: route.profile.id, revision: route.profile.revision,
                programSHA256: route.profile.digest,
                routeSHA256: SHA256.hash(data: Data(route.route.identity.utf8)).map { String(format: "%02x", $0) }.joined(),
                surface: route.route.surface, mode: route.route.mode)
            guard target.providerBinding == nil || target.providerBinding == binding else { throw BindingError.targetChanged }
            let bound = TargetLease(adapterID: target.adapterID, surface: target.surface, applicationID: target.applicationID,
                sessionID: target.sessionID, windowID: target.windowID, tabID: target.tabID, documentID: target.documentID,
                composerID: target.composerID, draftGeneration: target.draftGeneration, logicalDraftIdentity: target.logicalDraftIdentity,
                clickBindingID: target.clickBindingID, historyConversationID: target.historyConversationID, providerBinding: binding)
            return Self(native: click, route: route, target: bound)
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

/// These immutable fields come from the original durable dispatch. Historical
/// rows without this information continue through their existing read-only path.
struct StoredDispatch: Codable, Sendable {
    let inputClaim: UUID?
    let operationID: UUID
    let invocationID: UUID
    let attempt: Int
    let assetID: UUID
    let originalSHA256: String
    let target: TargetLease
    let profile: ProviderProfile
}

struct OriginalReader: Sendable {
    private let adapter: any IndependentFileInputAdapter
    private let request: TransferRequest

    fileprivate init(adapter: any IndependentFileInputAdapter, request: TransferRequest) {
        self.adapter = adapter
        self.request = request
    }

    func observe() async throws -> TransferReceipt {
        try await adapter.reconcile(request)
    }
}

struct AdapterResolver: Sendable {
    let adapters: [AdapterAddress: any IndependentFileInputAdapter]

    func adapter(for click: BoundClick) throws -> any IndependentFileInputAdapter {
        try exactAdapter(AdapterAddress(bundle: click.native.bundle, profile: click.route.profile,
                                        adapterID: click.target.adapterID))
    }

    func reader(for request: TransferRequest, original: StoredDispatch) throws -> OriginalReader {
        let op = request.operation
        guard request.requireLiveOriginal, request.invocationID == original.invocationID,
              op.phase.isUnresolved, op.phase != .prepared, op.id == original.operationID,
              op.attempt == original.attempt, op.target == original.target,
              op.assetID == original.assetID, request.asset.id == original.assetID,
              request.asset.sha256 == original.originalSHA256 else { throw BindingError.targetChanged }
        let address = AdapterAddress(bundle: original.target.applicationID, profile: original.profile,
                                     adapterID: original.target.adapterID)
        let adapter = try exactAdapter(address)
        guard adapter.supportsOriginalHandoffChecks else { throw BindingError.unsupported }
        return OriginalReader(adapter: adapter, request: request)
    }

    private func exactAdapter(_ address: AdapterAddress) throws -> any IndependentFileInputAdapter {
        guard let adapter = adapters[address], adapter.id == address.adapterID else { throw BindingError.unsupported }
        return adapter
    }
}

extension StoredDispatch {
    private static func key(_ id: UUID) -> String { "issue120.dispatch.v1." + id.uuidString }

    /// Admission belongs to a new, already durable dispatch and the exact fresh
    /// click. The existing store owns the first-writer transaction.
    static func register(_ click: BoundClick, request: TransferRequest, store: QueueStore) async throws {
        guard request.operation.target == click.target else { throw BindingError.targetChanged }
        try await claimInput(profile: click.route.profile, request: request, store: store)
    }

    static func claimInput(profile: ProviderProfile, request: TransferRequest, store: QueueStore) async throws {
        let op = request.operation
        guard op.phase == .dispatchIntent, !request.requireLiveOriginal,
              let owner = op.target.providerBinding, owner.providerID == profile.id,
              owner.revision == profile.revision, owner.programSHA256 == profile.digest,
              let id = request.invocationID, try await store.dispatchInvocationID(for: op.id) == id
        else { throw BindingError.targetChanged }
        // A second contender presents a different claim. Reading the first
        // writer's checkpoint can authorize observation only, never another append.
        let record = Self(inputClaim: UUID(), operationID: op.id, invocationID: id, attempt: op.attempt,
                          assetID: request.asset.id, originalSHA256: request.asset.sha256,
                          target: op.target, profile: profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(record)
        let saved = try await store.claimDispatchCheckpoint(bytes, for: key(op.id), operation: op, asset: request.asset)
        guard saved == bytes else { throw BindingError.targetChanged }
    }

    static func load(for id: UUID, store: QueueStore) async throws -> Self? {
        guard let data = try await store.checkpoint(for: key(id)) else { return nil }
        let record = try JSONDecoder().decode(Self.self, from: data)
        guard record.operationID == id else { throw BindingError.targetChanged }
        return record
    }
}
