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
    private let onSelectionSettled: @Sendable (UUID) async -> Void
    private var waiting: [Int: UUID] = [:]
    private var skippedTickets = Set<Int>()
    private var nextTicket = 0
    private var drainTicket = 0
    private var isDraining = false
    private var selecting: Set<UUID> = []
    private var observing = Set<UUID>()
    private var observationCursor = 0

    public init(store: QueueStore, adapter: any AttachmentAdapter, mediaDirectory: URL,
                policy: ReceiptPolicy = .init(), onChange: @escaping @Sendable () async -> Void = {},
                onSelectionSettled: @escaping @Sendable (UUID) async -> Void = { _ in }) {
        self.store = store; self.adapter = adapter; self.mediaDirectory = mediaDirectory
        self.policy = policy; self.onChange = onChange; self.onSelectionSettled = onSelectionSettled
    }

    /// Starts immediately; callers may await completion without blocking the main run loop.
    public func select(_ assetID: UUID, visibilityRevision: Int64? = nil) async throws {
        try await select(assetID, target: nil, allowCapture: true, visibilityRevision: visibilityRevision)
    }

    /// Web selections freeze a pre-acknowledged target at mouse-down. A missing
    /// target must never be replaced by whatever tab is active after this await.
    public func select(_ assetID: UUID, frozenTarget: TargetLease?, visibilityRevision: Int64? = nil) async throws {
        try await select(assetID, target: frozenTarget, allowCapture: false, visibilityRevision: visibilityRevision)
    }

    private func select(_ assetID: UUID, target frozenTarget: TargetLease?, allowCapture: Bool,
                        visibilityRevision: Int64?) async throws {
        // Covers reentrancy while captureTarget awaits a transport reply.
        // Only the selection owner may release its UI reservation. A duplicate
        // invocation cannot settle the original while captureTarget still awaits.
        guard selecting.insert(assetID).inserted else { return }
        defer { selecting.remove(assetID) }
        // Reserve before the first await: slower target resolution must not reorder clicks.
        let ticket = nextTicket; nextTicket += 1
        var enqueued = false
        var reserved = false
        var settled = false
        do {
            guard let record = try await store.asset(id: assetID) else { throw RiftletError.assetNotFound }
            if let activeID = record.activeOperationID,
               let op = try await store.operation(id: activeID), op.phase.isUnresolved {
                if op.phase == .unknown || op.phase == .compensated { try await reconcile(op) }
                await onChange(); await onSelectionSettled(assetID)
                settled = true
                skippedTickets.insert(ticket)
                try await drain()
                return
            }
            try await store.reserveSelection(assetID, visibilityRevision: visibilityRevision)
            reserved = true
            let target: TargetLease
            if let frozenTarget { target = frozenTarget }
            else if allowCapture { target = try await adapter.captureTarget() }
            else { throw RiftletError.adapterUnavailable("No verified target existed at selection; image retained") }
            guard target.adapterID == adapter.id else { throw RiftletError.mismatchedReceipt }
            let op = try await store.prepare(assetID: assetID, target: target)
            await store.releaseSelection(assetID); reserved = false
            waiting[ticket] = op.id
            enqueued = true
            await onChange()
            await onSelectionSettled(assetID); settled = true
            try await drain()
        } catch {
            if reserved { await store.releaseSelection(assetID) }
            if !settled { await onChange(); await onSelectionSettled(assetID) }
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
            catch {
                if try await store.operation(id: id)?.phase == .prepared {
                    try await cancelIfPrepared(id, reason: "Target validation unavailable before input")
                }
                await onChange(); continue
            }
            guard try await store.operation(id: id)?.phase == .prepared else { await onChange(); continue }
            guard targetValid else {
                try await cancelIfPrepared(id, reason: "Original target changed before input")
                await onChange(); continue
            }
            let request = try await request(for: op)
            guard FileManager.default.fileExists(atPath: request.fileURL.path) else {
                try await cancelIfPrepared(id, reason: "Private image is missing; no input occurred")
                try await store.markMissingAsset(op.assetID)
                await onChange(); continue
            }
            do { try await store.markDispatchIntent(id) }
            catch RiftletError.targetBusy {
                // An UNKNOWN on this draft keeps the target locked. No hidden fallback.
                try await cancelIfPrepared(id, reason: "Original draft has an unresolved upload; no input occurred")
                await onChange(); continue
            }
            catch RiftletError.invalidTransition {
                // A user removal may retire prepared work during preflight.
                // No intent was committed; do not resurrect or dispatch it.
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
        guard observing.insert(op.id).inserted else { return }
        defer { observing.remove(op.id) }
        let original = try await request(for: op)
        let receipt = try await adapter.reconcile(original)
        _ = try await store.apply(receipt, policy: policy)
        await onChange()
    }

    /// Bounded, round-robin observation of original operations. Returning an
    /// early start receipt frees the input drain; this never calls append.
    public func observePending(limit: Int = 8) async throws {
        let candidates = try await store.unresolvedOperations().filter {
            $0.target.adapterID == adapter.id && [.inputTriggered, .attachmentPresent, .unknown, .compensated].contains($0.phase)
        }
        guard !candidates.isEmpty else { observationCursor = 0; return }
        let count = max(0, min(limit, min(32, candidates.count)))
        let start = observationCursor % candidates.count
        observationCursor = (start + count) % candidates.count
        for offset in 0..<count {
            let op = candidates[(start + offset) % candidates.count]
            do { try await reconcile(op) }
            catch {
                if let current = try await store.operation(id: op.id), current.phase.isUnresolved, current.phase != .prepared {
                    try await store.markUnknown(op.id, reason: "Background observation unavailable; original operation retained")
                }
            }
        }
        await onChange()
    }

    /// Successful uploads remain observable for a correlated late failure.
    /// Transport errors or navigation are not failures and cannot reverse success.
    /// The return value controls only an in-memory observation watch.
    public func observeCompleted(operationID: UUID) async throws -> Bool {
        guard let op = try await store.operation(id: operationID), op.phase == .succeeded,
              op.target.adapterID == adapter.id else { return false }
        guard observing.insert(op.id).inserted else { return true }
        defer { observing.remove(op.id) }
        let receipt = try await adapter.reconcile(try await request(for: op))
        _ = try await store.apply(receipt, policy: policy)
        await onChange()
        let current = try await store.operation(id: operationID)
        return receipt.belongsToOriginalDraft && current?.phase == .succeeded
    }

    private func cancelIfPrepared(_ id: UUID, reason: String) async throws {
        guard try await store.operation(id: id)?.phase == .prepared else { return }
        do { try await store.cancelPrepared(id, reason: reason) }
        catch RiftletError.invalidTransition { /* A concurrent explicit removal already cancelled it. */ }
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

/// Isolated demonstration of start → delayed success / safe failure / UNKNOWN.
/// These receipts never refer to a browser, client or system screenshot.
public actor SimulationAdapter: AttachmentAdapter {
    public nonisolated let id = "simulation"
    private var counter = 0
    private let settlementDelay: TimeInterval
    private var outcomes: [UUID: (outcome: ReceiptOutcome, readyAt: Date)] = [:]
    public init(settlementDelay: TimeInterval = 1.2) {
        self.settlementDelay = settlementDelay.isFinite ? max(0, min(settlementDelay, 30)) : 1.2
    }
    public func captureTarget() async throws -> TargetLease {
        guard outcomes.count < 128 else { throw RiftletError.adapterUnavailable("SIMULATION observation capacity reached") }
        // Each fixture uses an explicitly independent synthetic draft. This
        // demonstrates independent dispatch without weakening real target locks.
        let draft = "demo-\(UUID().uuidString)"
        return TargetLease(adapterID: id, surface: .simulation, applicationID: "com.riftlet.simulation",
                    sessionID: "synthetic-only", windowID: "demo", documentID: draft,
                    composerID: draft, draftGeneration: "1")
    }
    public func validate(_ target: TargetLease) async throws -> Bool {
        target.adapterID == id && target.surface == .simulation
            && target.applicationID == "com.riftlet.simulation" && target.sessionID == "synthetic-only"
            && target.windowID == "demo" && target.documentID.hasPrefix("demo-")
            && target.documentID == target.composerID && target.draftGeneration == "1"
    }
    public func append(_ request: TransferRequest) async throws -> TransferReceipt {
        guard request.asset.origin == .synthetic, try await validate(request.operation.target) else { throw RiftletError.modeMismatch }
        if outcomes[request.operation.id] == nil {
            counter += 1
            let outcome: ReceiptOutcome = counter % 3 == 1 ? .verifiedReady : (counter % 3 == 2 ? .definitiveFailure : .unknown)
            outcomes[request.operation.id] = (outcome, Date().addingTimeInterval(settlementDelay))
        }
        return receipt(for: request, outcome: .uploadStarted)
    }
    public func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        guard request.asset.origin == .synthetic, try await validate(request.operation.target) else { throw RiftletError.modeMismatch }
        guard let pending = outcomes[request.operation.id] else {
            // Restart loses simulation timing, never fabricates a new success.
            return receipt(for: request, outcome: .unknown)
        }
        return receipt(for: request, outcome: Date() >= pending.readyAt ? pending.outcome : .uploadStarted)
    }
    private func receipt(for request: TransferRequest, outcome: ReceiptOutcome) -> TransferReceipt {
        TransferReceipt(operationID: request.operation.id, assetID: request.asset.id,
                        attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
                        target: request.operation.target, outcome: outcome, profileID: "simulation-v1",
                        attachmentID: "synthetic-\(request.operation.id)", positiveReady: outcome == .verifiedReady,
                        belongsToOriginalDraft: true, hasError: outcome == .definitiveFailure,
                        isUploading: outcome == .uploadStarted, safeToRetry: outcome == .definitiveFailure,
                        reason: "SIMULATION — no real attachment",
                        uploadStartEvidence: outcome == .uploadStarted
                            ? UploadStartEvidence(profileID: "simulation-upload-start-v1", signal: .correlatedProgress,
                                                  evidenceID: "synthetic-\(request.operation.id)") : nil)
    }
}
