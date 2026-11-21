import CryptoKit
import Foundation
import RiftletCore

struct Issue120Invocation: Equatable, Sendable {
    let target: TargetLease
    let profile: ProviderProfile
    let operation: UUID
    let invocation: UUID
    let asset: UUID
    let attempt: Int
    let pngSHA256: String
}

struct Issue120InputReply: Sendable {
    let key: Issue120Invocation
    let confirmedOneInput: Bool
}

struct Issue120Observation: Sendable {
    enum State: Sendable {
        case unknown
        case accepted(card: String, observedPayloadSHA256: String)
        case failedOriginalCard(card: String, observedPayloadSHA256: String)
    }
    let key: Issue120Invocation
    let state: State
}

/// Implementations keep the existing host's original click/relay handle. They
/// must revalidate it in the same page action as the setter. Observers receive
/// identities only and cannot submit bytes.
protocol Issue120ProviderTransport: Sendable {
    func validateOriginal(_ target: TargetLease, profile: ProviderProfile) async throws -> Bool
    func commitOnce(_ key: Issue120Invocation, png: Data) async throws -> Issue120InputReply
    func observeOriginal(_ key: Issue120Invocation) async throws -> Issue120Observation
}

actor Issue120ProviderAdapter: IndependentFileInputAdapter {
    let id = "riftlet-web-provider-v1"
    nonisolated let supportsOriginalHandoffChecks = true
    private let profile: ProviderProfile
    private let bundle: String
    private let mediaDirectory: URL
    private let transport: any Issue120ProviderTransport
    // No public website currently has an admitted event and original-card recipe.
    private var admittedScope: WebProviderBinding?

    init(profile: ProviderProfile, bundle: String, mediaDirectory: URL, transport: any Issue120ProviderTransport) {
        self.profile = profile; self.bundle = bundle; self.mediaDirectory = mediaDirectory
        self.transport = transport
    }

    #if DEBUG
    /// Decoupled from production manifests. This profile can name only the
    /// isolated loopback route; it cannot be reconstructed from a public URL.
    init(loopback: URL, profile: ProviderProfile, bundle: String, mediaDirectory: URL,
         transport: any Issue120ProviderTransport) throws {
        let paths = ["fixture-gemini-like": "/app", "fixture-claude-like": "/fixture-claude-like"]
        guard let path = paths[profile.id], profile.revision == 1,
              let port = loopback.port, (1...65535).contains(port),
              loopback.absoluteString == "http://127.0.0.1:\(port)\(path)" else { throw BindingError.invalidProfile }
        self.profile = profile; self.bundle = bundle; self.mediaDirectory = mediaDirectory
        self.transport = transport
        admittedScope = WebProviderBinding(providerID: profile.id, revision: profile.revision,
            programSHA256: profile.digest, routeSHA256: SHA256.hash(data: Data(loopback.absoluteString.utf8))
                .map { String(format: "%02x", $0) }.joined(), surface: "ordinary-fixture", mode: "image-fixture")
    }
    #endif

    private func permits(_ target: TargetLease) -> Bool {
        guard let scope = admittedScope else { return false }
        return target.adapterID == id && target.applicationID == bundle && target.providerBinding == scope &&
            target.surface == .webChat && target.clickBindingID != nil && !target.sessionID.isEmpty &&
            !target.windowID.isEmpty && !(target.tabID ?? "").isEmpty && !target.documentID.isEmpty &&
            !target.composerID.isEmpty && !target.draftGeneration.isEmpty
    }

    func captureTarget() async throws -> TargetLease { throw BindingError.unsupported }

    func preflight(asset: ImportedAsset, fileURL: URL) async throws { throw BindingError.unsupported }

    func preflight(asset: ImportedAsset, fileURL: URL, frozenTarget: TargetLease?) async throws {
        guard let target = frozenTarget, permits(target) else { throw BindingError.unsupported }
        _ = try privatePNG(asset,fileURL)
    }

    private func privatePNG(_ asset: ImportedAsset, _ file: URL) throws -> PrivateUploadFile {
        guard asset.mediaType == "image/png" else { throw WebAdapterError.invalidPrivateFile }
        return try PrivateUploadFile(asset: asset, url: file, mediaDirectory: mediaDirectory, maximumBytes: 65536)
    }

    func validate(_ target: TargetLease) async throws -> Bool {
        guard permits(target) else { return false }
        return try await transport.validateOriginal(target, profile: profile)
    }

    private func key(_ request: TransferRequest) throws -> Issue120Invocation {
        let op = request.operation
        guard permits(op.target), let invocation = request.invocationID, op.assetID == request.asset.id,
              op.attempt > 0 else { throw BindingError.targetChanged }
        return .init(target: op.target, profile: profile, operation: op.id, invocation: invocation,
                     asset: op.assetID, attempt: op.attempt, pngSHA256: request.asset.sha256)
    }

    private func receipt(_ k: Issue120Invocation, _ outcome: ReceiptOutcome, card: String? = nil, originalCardFailed: Bool = false) -> TransferReceipt {
        let accepted = outcome == .uploadStarted
        return .init(operationID: k.operation, assetID: k.asset, attempt: k.attempt, assetSHA256: k.pngSHA256,
             target: k.target, outcome: outcome, profileID: k.profile.id, attachmentID: card,
             belongsToOriginalDraft: card != nil, hasError: originalCardFailed,
             uploadStartEvidence: accepted ? UploadStartEvidence(profileID: k.profile.id, signal: .attachmentAccepted,
                                                                 evidenceID: card ?? "") : nil,
             originalCardFailureInvocationID: originalCardFailed ? k.invocation : nil)
    }

    private func observed(_ k: Issue120Invocation) async -> TransferReceipt {
        guard let result = try? await transport.observeOriginal(k), result.key == k else { return receipt(k,.unknown) }
        switch result.state {
        case let .accepted(card,digest) where !card.isEmpty && digest == k.pngSHA256:
            return receipt(k,.uploadStarted,card: card)
        case let .failedOriginalCard(card,digest) where !card.isEmpty && digest == k.pngSHA256:
            return receipt(k,.unknown,card: card,originalCardFailed: true)
        default: return receipt(k,.unknown)
        }
    }

    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        guard request.requireLiveOriginal, request.operation.phase.isUnresolved,
              request.operation.phase != .prepared else { throw BindingError.targetChanged }
        return try await observed(key(request))
    }

    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try await execute(request, input: { _ in }, returned: {})
    }
    func append(_ request: TransferRequest, onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt {
        try await execute(request, input: onInputConfirmed, returned: {})
    }
    func append(_ request: TransferRequest, onInputExecutionReturned: @escaping @Sendable () async -> Void) async throws -> TransferReceipt {
        try await execute(request, input: { _ in }, returned: onInputExecutionReturned)
    }

    private func execute(_ request: TransferRequest, input: @Sendable (TransferReceipt) async -> Void,
                         returned: @Sendable () async -> Void) async throws -> TransferReceipt {
        let k = try key(request)
        guard request.operation.phase == .dispatchIntent, !request.requireLiveOriginal else { throw BindingError.targetChanged }
        let bytes: Data
        do {
            bytes = try privatePNG(request.asset,request.fileURL).verifiedOriginal()
            guard bytes.starts(with: [137,80,78,71,13,10,26,10]), try await validate(k.target) else {
                throw BindingError.targetChanged
            }
        } catch {
            throw PreInputRejection(operationID: k.operation, assetID: k.asset, attempt: k.attempt,
                assetSHA256: k.pngSHA256, target: k.target, invocationID: k.invocation, stage: .localBeforeBegin)
        }
        // The outer runtime holds the durable input claim. Never re-issue
        // after entering this method of the original page transport.
        let reply = try? await transport.commitOnce(k, png: bytes)
        await returned()
        if let reply, reply.key == k, reply.confirmedOneInput { await input(receipt(k,.inputTriggered)) }
        return await observed(k)
    }
}
