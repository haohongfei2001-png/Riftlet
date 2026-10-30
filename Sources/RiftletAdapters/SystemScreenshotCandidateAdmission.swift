import Foundation
import RiftletCore

/// A native, durable scope registration for a newly dispatched internal test.
/// It is neither upload-start evidence nor completion proof. No observation,
/// recovery, old journal, argument or page JSON can create this registration.
public actor SystemScreenshotCandidateAdmission {
    private let store: QueueStore

    public nonisolated let scope: SystemScreenshotAdmissionScope

    public init(store: QueueStore, scope: SystemScreenshotAdmissionScope = .candidate) { self.store = store; self.scope = scope }

    private struct Registration: Codable, Equatable {
        let version: Int
        let sourceID: String
        let startProfileID: String
        let completionProfileID: String
        let identity: ObservationIdentity
        let enrollmentID: UUID
    }

    /// Called only by append after local format and full-file SHA verification,
    /// before its first begin. Existing registrations authorize observation
    /// only; they can never authorize another append, even for the same request.
    func enroll(_ request: TransferRequest) async throws {
        try SystemScreenshotWebCandidate.validateMetadata(request.asset)
        try scope.validateTarget(request.operation.target)
        guard request.operation.phase == .dispatchIntent else { throw WebAdapterError.invalidRequest }
        let key = Self.checkpointKey(for: request, scope: scope)
        guard try await store.checkpoint(for: key) == nil else { throw WebAdapterError.invalidRequest }
        let registration = Registration(version: 1, sourceID: SystemScreenshotWebCandidate.sourceID,
            startProfileID: scope.admittedProfile.uploadStartProfileID!,
            completionProfileID: scope.admittedProfile.profileID,
            identity: Self.identity(for: request), enrollmentID: UUID())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let proposed = try encoder.encode(registration)
        // The store validates the actual persisted dispatch intent and full
        // asset/operation identity in the same transaction as this first write.
        // A fresh nonce distinguishes concurrent proposals for the same key.
        // The historical key is also the cross-scope one-shot fence. Keeping it
        // unchanged protects old candidate registrations and prevents two scopes
        // from independently claiming the same dispatch intent in two connections.
        let fenceKey = Self.checkpointKey(for: request)
        if scope != .candidate {
            guard try await store.checkpoint(for: fenceKey) == nil else { throw WebAdapterError.invalidRequest }
            let fenced = try await store.claimDispatchCheckpoint(proposed, for: fenceKey,
                operation: request.operation, asset: request.asset)
            guard fenced == proposed else { throw WebAdapterError.invalidRequest }
        }
        let retained = try await store.claimDispatchCheckpoint(proposed, for: key,
            operation: request.operation, asset: request.asset)
        guard retained == proposed else { throw WebAdapterError.invalidRequest }
    }

    /// Missing v2 registration is the permanent legacy boundary. In particular,
    /// F and older UNKNOWN records keep their unadmitted v1 observations/locks.
    func admits(_ request: TransferRequest) async throws -> Bool {
        guard let data = try await store.checkpoint(for: Self.checkpointKey(for: request, scope: scope)) else { return false }
        if scope != .candidate {
            guard try await store.checkpoint(for: Self.checkpointKey(for: request)) == data else {
                throw WebAdapterError.invalidRequest
            }
        }
        guard data.count <= 64 * 1024,
              let registration = try? JSONDecoder().decode(Registration.self, from: data),
              registration.version == 1,
              registration.sourceID == SystemScreenshotWebCandidate.sourceID,
              registration.startProfileID == scope.admittedProfile.uploadStartProfileID!,
              registration.completionProfileID == scope.admittedProfile.profileID,
              registration.identity == Self.identity(for: request),
              request.operation.assetID == request.asset.id, request.operation.phase != .prepared,
              request.operation.phase.isUnresolved || request.operation.phase == .succeeded,
              await store.mode == .production,
              let asset = try await store.asset(id: request.asset.id), asset.image == request.asset,
              asset.activeOperationID == request.operation.id,
              let operation = try await store.operation(id: request.operation.id),
              operation.assetID == request.asset.id, operation.attempt == request.operation.attempt,
              operation.target == request.operation.target, operation.phase != .prepared,
              operation.phase.isUnresolved || operation.phase == .succeeded else {
            throw WebAdapterError.invalidRequest
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard (try? encoder.encode(registration)) == data else { throw WebAdapterError.invalidRequest }
        try SystemScreenshotWebCandidate.validateMetadata(request.asset)
        try scope.validateTarget(request.operation.target)
        return true
    }

    /// Read-only compatibility for operations enrolled by the preceding ordinary
    /// internal App in this same store. Never enrolls, repairs partial fences or
    /// borrows candidate registrations. Malformed current registrations throw.
    func admittedObservationScope(for request: TransferRequest) async throws -> SystemScreenshotAdmissionScope? {
        if try await admits(request) { return scope }
        guard scope == .ordinaryCurrentDraftInternal else { return nil }
        let prior = SystemScreenshotCandidateAdmission(store: store, scope: .ordinary)
        return try await prior.admits(request) ? .ordinary : nil
    }

    static func checkpointKey(for request: TransferRequest, scope: SystemScreenshotAdmissionScope = .candidate) -> String {
        "\(scope.admissionPrefix):\(request.operation.id.uuidString.lowercased()):\(request.operation.attempt)"
    }

    private static func identity(for request: TransferRequest) -> ObservationIdentity {
        ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
    }
}
