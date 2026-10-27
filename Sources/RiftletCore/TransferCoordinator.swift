import Foundation

public struct TransferRequest: Sendable {
    public let operation: TransferOperation
    public let asset: ImportedAsset
    public let fileURL: URL

    public init(operation: TransferOperation, asset: ImportedAsset, fileURL: URL) {
        self.operation = operation; self.asset = asset; self.fileURL = fileURL
    }
}

/// No send-message method exists. A transport must revalidate the immutable target
/// in the same target-side action that appends; a prior validate call alone is insufficient.
public protocol AttachmentAdapter: Sendable {
    var id: String { get }
    func captureTarget() async throws -> TargetLease
    func validate(_ target: TargetLease) async throws -> Bool
    func append(_ request: TransferRequest) async throws -> TransferReceipt
    /// Observation of the original operation only. Must never dispatch another input.
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt
}

public actor TransferCoordinator {
    private let store: QueueStore
    private let adapter: any AttachmentAdapter
    private let mediaDirectory: URL
    private let policy: ReceiptPolicy
    private let onChange: @Sendable () async -> Void
    private var waiting: [Int: UUID] = [:]
    private var skippedTickets = Set<Int>()
    private var nextTicket = 0
    private var drainTicket = 0
    private var isDraining = false
    private var selecting: Set<UUID> = []

    public init(store: QueueStore, adapter: any AttachmentAdapter, mediaDirectory: URL,
                policy: ReceiptPolicy = .init(), onChange: @escaping @Sendable () async -> Void = {}) {
        self.store = store; self.adapter = adapter; self.mediaDirectory = mediaDirectory
        self.policy = policy; self.onChange = onChange
    }

    /// Starts immediately; callers may await completion without blocking the main run loop.
    public func select(_ assetID: UUID) async throws {
        // Covers reentrancy while captureTarget awaits a transport reply.
        guard selecting.insert(assetID).inserted else { return }
        defer { selecting.remove(assetID) }
        // Reserve before the first await: slower target resolution must not reorder clicks.
        let ticket = nextTicket; nextTicket += 1
        var enqueued = false
        do {
            guard let record = try await store.asset(id: assetID) else { throw RiftletError.assetNotFound }
            if let activeID = record.activeOperationID,
               let op = try await store.operation(id: activeID), op.phase.isUnresolved {
                if op.phase == .unknown || op.phase == .compensated { try await reconcile(op) }
                skippedTickets.insert(ticket)
                try await drain()
                return
            }
            let target = try await adapter.captureTarget()
            guard target.adapterID == adapter.id else { throw RiftletError.mismatchedReceipt }
            let op = try await store.prepare(assetID: assetID, target: target)
            waiting[ticket] = op.id
            enqueued = true
            await onChange()
            try await drain()
        } catch {
            if !enqueued {
                skippedTickets.insert(ticket)
                try? await drain()
            }
            throw error
        }
    }

    /// Startup never calls append for an interrupted operation.
    public func recover() async throws {
        try await store.recoverInterruptedOperations()
        await onChange()
        for op in try await store.unresolvedOperations() where (op.phase == .unknown || op.phase == .compensated) && op.target.adapterID == adapter.id {
            do { try await reconcile(op) }
            catch { try await store.markUnknown(op.id, reason: "Recovery observation unavailable") }
        }
        await onChange()
    }

    private func drain() async throws {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while true {
            if skippedTickets.remove(drainTicket) != nil { drainTicket += 1; continue }
            guard let id = waiting.removeValue(forKey: drainTicket) else { break }
            drainTicket += 1
            guard let op = try await store.operation(id: id), op.phase == .prepared else { continue }
            // Validation failure is before intent: safe to leave retryable, without any input.
            let targetValid: Bool
            do { targetValid = try await adapter.validate(op.target) }
            catch { try await store.cancelPrepared(id, reason: "Target validation unavailable before input"); await onChange(); continue }
            guard targetValid else {
                try await store.cancelPrepared(id, reason: "Original target changed before input")
                await onChange(); continue
            }
            let request = try await request(for: op)
            guard FileManager.default.fileExists(atPath: request.fileURL.path) else {
                try await store.cancelPrepared(id, reason: "Private image is missing; no input occurred")
                try await store.markMissingAsset(op.assetID)
                await onChange(); continue
            }
            do { try await store.markDispatchIntent(id) }
            catch RiftletError.targetBusy {
                // An UNKNOWN on this draft keeps the target locked. No hidden fallback.
                try await store.cancelPrepared(id, reason: "Original draft has an unresolved upload; no input occurred")
                await onChange(); continue
            }
            do {
                guard let committed = try await store.operation(id: id) else { throw RiftletError.operationNotFound }
                let committedRequest = try await self.request(for: committed)
                let receipt = try await adapter.append(committedRequest)
                _ = try await store.apply(receipt, policy: policy)
                if receipt.outcome == .inputTriggered || receipt.outcome == .attachedCandidate {
                    // Observation may return a candidate, never a synthetic success timeout.
                    try await store.markUnknown(id, reason: "Input observed; conclusive completion is unavailable")
                }
            } catch {
                // Includes a transport crash or a malformed/mismatched reply after intent.
                try await store.markUnknown(id, reason: "No trustworthy completion after input intent")
            }
            await onChange()
        }
    }

    private func reconcile(_ op: TransferOperation) async throws {
        guard op.target.adapterID == adapter.id else { throw RiftletError.adapterUnavailable("Original adapter is unavailable") }
        let original = try await request(for: op)
        let receipt = try await adapter.reconcile(original)
        _ = try await store.apply(receipt, policy: policy)
        await onChange()
    }

    /// Successful uploads remain observable for a correlated late failure.
    /// Transport errors or navigation are not failures and cannot reverse success.
    /// The return value controls only an in-memory observation watch.
    public func observeCompleted(operationID: UUID) async throws -> Bool {
        guard let op = try await store.operation(id: operationID), op.phase == .succeeded,
              op.target.adapterID == adapter.id else { return false }
        let receipt = try await adapter.reconcile(try await request(for: op))
        _ = try await store.apply(receipt, policy: policy)
        await onChange()
        let current = try await store.operation(id: operationID)
        return receipt.belongsToOriginalDraft && current?.phase == .succeeded
    }

    private func request(for op: TransferOperation) async throws -> TransferRequest {
        guard let asset = try await store.asset(id: op.assetID) else { throw RiftletError.assetNotFound }
        return TransferRequest(operation: op, asset: asset.image, fileURL: mediaDirectory.appendingPathComponent(asset.image.fileName))
    }
}

/// Explicit development boundary: no real screenshot leaves the machine in this build.
public struct UnavailableAdapter: AttachmentAdapter {
    public let id: String
    public init(id: String = "chatgpt-web") { self.id = id }
    public func captureTarget() async throws -> TargetLease {
        throw RiftletError.adapterUnavailable("ChatGPT attachment validation is pending; screenshot retained")
    }
    public func validate(_ target: TargetLease) async throws -> Bool { false }
    public func append(_ request: TransferRequest) async throws -> TransferReceipt { throw RiftletError.adapterUnavailable(id) }
    public func reconcile(_ request: TransferRequest) async throws -> TransferReceipt { throw RiftletError.adapterUnavailable(id) }
}

/// The only enabled adapter. Requires both a simulation database and synthetic assets.
public actor SimulationAdapter: AttachmentAdapter {
    public nonisolated let id = "simulation"
    private var counter = 0
    public init() {}
    public func captureTarget() async throws -> TargetLease {
        TargetLease(adapterID: id, surface: .simulation, applicationID: "com.riftlet.simulation",
                    sessionID: "synthetic-only", windowID: "demo", documentID: "demo",
                    composerID: "demo", draftGeneration: "1")
    }
    public func validate(_ target: TargetLease) async throws -> Bool { target == (try await captureTarget()) }
    public func append(_ request: TransferRequest) async throws -> TransferReceipt {
        guard request.asset.origin == .synthetic, request.operation.target.surface == .simulation else { throw RiftletError.modeMismatch }
        counter += 1
        // Deliberately demonstrate success, failure, UNKNOWN; never target ChatGPT.
        let outcome: ReceiptOutcome = counter % 3 == 1 ? .verifiedReady : (counter % 3 == 2 ? .definitiveFailure : .unknown)
        try await Task.sleep(nanoseconds: 450_000_000)
        return receipt(for: request, outcome: outcome)
    }
    public func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        receipt(for: request, outcome: .unknown)
    }
    private func receipt(for request: TransferRequest, outcome: ReceiptOutcome) -> TransferReceipt {
        TransferReceipt(operationID: request.operation.id, assetID: request.asset.id,
                        attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
                        target: request.operation.target, outcome: outcome, profileID: "simulation-v1",
                        attachmentID: "synthetic-\(request.operation.id)", positiveReady: outcome == .verifiedReady,
                        belongsToOriginalDraft: true, hasError: outcome == .definitiveFailure,
                        safeToRetry: outcome == .definitiveFailure, reason: "SIMULATION — no real attachment")
    }
}
