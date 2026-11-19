import Foundation

public enum OriginalReceiverAccess: Sendable, Equatable {
    case granted, permissionRequired, unavailable
}

public enum OriginalAttachmentCheck: Sendable, Equatable {
    case observed, unavailable, permissionDenied, busy
}

public struct TransferRequest: Sendable {
    public let operation: TransferOperation
    public let asset: ImportedAsset
    public let fileURL: URL
    public let invocationID: UUID?

    public let requireLiveOriginal: Bool

    public init(operation: TransferOperation, asset: ImportedAsset, fileURL: URL, invocationID: UUID? = nil,
                requireLiveOriginal: Bool = false) {
        self.requireLiveOriginal = requireLiveOriginal
        self.operation = operation; self.asset = asset; self.fileURL = fileURL
        self.invocationID = invocationID
    }
}

/// No send-message method exists. A transport must revalidate the immutable target
/// in the same target-side action that appends; a prior validate call alone is insufficient.
public protocol AttachmentAdapter: Sendable {
    var id: String { get }
    /// Local-only eligibility checks, before allocating an operation or acquiring
    /// a target lock. Must never capture a target, contact an app, or input bytes.
    func preflight(asset: ImportedAsset, fileURL: URL) async throws
    func captureTarget() async throws -> TargetLease
    func validate(_ target: TargetLease) async throws -> Bool
    func append(_ request: TransferRequest) async throws -> TransferReceipt
    /// Observation of the original operation only. Must never dispatch another input.
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt
}

public extension AttachmentAdapter {
    func preflight(asset: ImportedAsset, fileURL: URL) async throws {}
}

/// The original append remains the sole owner of input and its live observation.
/// This optional boundary reports positively observed file input, NOT a raw
/// commit return, upload start, retry permission or completion. The callback
/// never replaces the eventual append receipt or its invocation checkpoint.
public protocol InputPhasedAttachmentAdapter: AttachmentAdapter {
    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt
}

/// A normal file-input adapter serializes only its synchronous setter/change
/// execution. Its return boundary is independent of the upload observation: a
/// returned setter can have an unknown result without occupying the next input.
public protocol IndependentFileInputAdapter: InputPhasedAttachmentAdapter {
    /// The observer can verify a live receiver, invocation, draft and attachment
    /// after restart. Historical candidate adapters retain their original scope.
    var supportsOriginalHandoffChecks: Bool { get }
    func append(_ request: TransferRequest,
                onInputExecutionReturned: @escaping @Sendable () async -> Void) async throws -> TransferReceipt
}

public extension IndependentFileInputAdapter {
    var supportsOriginalHandoffChecks: Bool { false }

    /// Existing adapters may report a positive input phase or simply finish the
    /// original call. Repeated return notifications are harmless; Core owns the
    /// one-operation execution lane. A Web adapter overrides this to notify even
    /// when the synchronous result is UNKNOWN, before it keeps observing START.
    func append(_ request: TransferRequest,
                onInputExecutionReturned: @escaping @Sendable () async -> Void) async throws -> TransferReceipt {
        let receipt = try await append(request, onInputConfirmed: { _ in await onInputExecutionReturned() })
        await onInputExecutionReturned()
        return receipt
    }
}

private actor InputPhaseBoundary {
    private var result: Result<Void, Error>?
    private var waiter: CheckedContinuation<Result<Void, Error>, Never>?

    func finish(_ value: Result<Void, Error> = .success(())) {
        guard result == nil else { return }
        result = value
        waiter?.resume(returning: value); waiter = nil
    }

    func wait() async throws {
        let value = await withCheckedContinuation { continuation in
            if let result { continuation.resume(returning: result) }
            else { waiter = continuation }
        }
        try value.get()
    }
}

public actor TransferCoordinator {
    private let store: QueueStore
    private let dispatchOwnerID = UUID()
    private let adapter: any AttachmentAdapter
    private let mediaDirectory: URL
    private let policy: ReceiptPolicy
    private let onChange: @Sendable () async -> Void
    private let onSelectionSettled: @Sendable (UUID) async -> Void
    private let onAcceptedSelectionSettled: @Sendable (AcceptedSelection) async -> Void
    private var waiting: [Int: UUID] = [:]
    private var skippedTickets = Set<Int>()
    private var nextTicket = 0
    private var drainTicket = 0
    private var isDraining = false
    private var selecting: Set<UUID> = []
    private var observing = Set<UUID>()
    private var observationCursor = 0
    private let validateAcceptedSelection: @Sendable (AcceptedSelection) async -> Bool
    private let maximumPendingSelections: Int
    private let onAcceptedSelectionFinished: @Sendable (UUID) async -> Void
    private var acceptedSelections: [UUID: AcceptedSelection] = [:]
    private var operationSelections: [UUID: AcceptedSelection] = [:]
    private var expiryTasks: [UUID: Task<Void, Never>] = [:]
    private var drainRequested = false
    // Original calls may keep observing START after their input execution ends.
    // These observations do not occupy the next screenshot's input lane.
    private var activeAppends: [UUID: TransferRequest] = [:]
    private var inputExecutions = Set<UUID>()
    // Only new inputs acquire background polling slots. Explicit historical
    // reads use the original identity and never allocate another polling slot.
    private struct InputWatch {
        let registeredAt: TimeInterval
        var reads = 0
        var due: TimeInterval = 0
    }
    private var currentFileInputs: [UUID: InputWatch] = [:]
    private let observationClock: @Sendable () -> TimeInterval
    /// A prepared slot may survive a failed database transaction after the
    /// last running call returned. Such a slot is durable state, not work to wait for.
    public var hasInFlightAttachmentWork: Bool {
        isDraining || !selecting.isEmpty || !activeAppends.isEmpty
    }

    private var usesIndependentFileInput: Bool { adapter is any IndependentFileInputAdapter }

    public init(store: QueueStore, adapter: any AttachmentAdapter, mediaDirectory: URL,
                policy: ReceiptPolicy = .init(), onChange: @escaping @Sendable () async -> Void = {},
                onSelectionSettled: @escaping @Sendable (UUID) async -> Void = { _ in },
                onAcceptedSelectionSettled: @escaping @Sendable (AcceptedSelection) async -> Void = { _ in },
                maximumPendingSelections: Int = 12,
                observationClock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                onAcceptedSelectionFinished: @escaping @Sendable (UUID) async -> Void = { _ in },
                validateAcceptedSelection: @escaping @Sendable (AcceptedSelection) async -> Bool = { _ in false }) {
        self.observationClock = observationClock
        self.store = store; self.adapter = adapter; self.mediaDirectory = mediaDirectory
        self.policy = policy; self.onChange = onChange; self.onSelectionSettled = onSelectionSettled
        self.onAcceptedSelectionSettled = onAcceptedSelectionSettled
        self.maximumPendingSelections = max(1, min(maximumPendingSelections, 12))
        self.validateAcceptedSelection = validateAcceptedSelection
        self.onAcceptedSelectionFinished = onAcceptedSelectionFinished
    }

    /// Starts immediately. A phased Web adapter may return control after exact
    /// input confirmation; its original bounded START observation stays owned here.
    public func select(_ assetID: UUID, visibilityRevision: Int64? = nil) async throws {
        try await select(assetID, target: nil, allowCapture: true, visibilityRevision: visibilityRevision)
    }

    /// A caller that has already resolved a destination uses that exact target.
    /// Missing targets here never cause a later unrelated tab to be selected.
    public func select(_ assetID: UUID, frozenTarget: TargetLease?, visibilityRevision: Int64? = nil) async throws {
        try await select(assetID, target: frozenTarget, allowCapture: false, visibilityRevision: visibilityRevision)
    }

    /// Only for the user's explicit new intent on a staged recovery tile. The
    /// immutable predecessor ID fences delayed and double clicks across attempts.
    public func reattach(_ selection: AcceptedSelection, replacing operationID: UUID) async throws {
        guard usesIndependentFileInput, selection.authorization == .currentClick,
              selection.target.adapterID == adapter.id, !inputExecutions.contains(operationID) else {
            throw RiftletError.invalidTransition
        }
        try await accept(selection, replacing: operationID)
    }

    public func select(_ selection: AcceptedSelection) async throws {
        try await accept(selection, replacing: nil)
    }

    private func accept(_ selection: AcceptedSelection, replacing predecessor: UUID?) async throws {
        guard selection.isValid(), acceptedSelections[selection.id] == nil,
              selection.authorization == .currentClick || acceptedSelections.count < maximumPendingSelections else { throw RiftletError.invalidTransition }
        acceptedSelections[selection.id] = selection
        if selection.deadlineUptime.isFinite {
            expiryTasks[selection.id] = Task { [weak self] in
                // Task scheduling can itself be delayed. Compute the remaining
                // interval when this task actually starts, so that delay is never
                // added a second time to the original absolute selection deadline.
                do {
                    try Task.checkCancellation()
                    let remaining = selection.deadlineUptime - ProcessInfo.processInfo.systemUptime
                    if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                } catch { return }
                try? await self?.cancelAcceptedSelection(selection.id, reason: "Accepted selection expired before input")
            }
        }
        do {
            try await select(selection.assetID, target: selection.target, allowCapture: false,
                             visibilityRevision: selection.visibilityRevision, accepted: selection, replacing: predecessor)
        } catch {
            finishAcceptedSelection(selection)
            throw error
        }
    }

    /// Exact IDs prevent a delayed App cancellation message from cancelling a
    /// newer click accepted under another epoch.
    public func cancelAcceptedSelections(ids: [UUID], reason: String) async throws {
        for id in ids { acceptedSelections[id]?.cancel() }
        for id in ids { try await cancelAcceptedSelection(id, reason: reason) }
    }

    public func cancelPendingSelections(reason: String) async throws {
        let tokens = Array(acceptedSelections.values)
        for token in tokens { token.cancel() }
        for token in tokens { try await cancelAcceptedSelection(token.id, reason: reason) }
    }

    public func cancelPendingSelection(assetID: UUID, reason: String) async throws {
        let tokens = acceptedSelections.values.filter { $0.assetID == assetID }
        for token in tokens { token.cancel() }
        for token in tokens { try await cancelAcceptedSelection(token.id, reason: reason) }
    }

    private func cancelAcceptedSelection(_ tokenID: UUID, reason: String) async throws {
        guard let token = acceptedSelections[tokenID] else { return }
        token.cancel()
        let operations = operationSelections.filter { $0.value.id == tokenID }.map(\.key)
        for id in operations { try await cancelIfPrepared(id, reason: reason) }
        finishAcceptedSelection(token)
        await onChange()
        try await drain()
    }

    private func finishAcceptedSelection(_ selection: AcceptedSelection) {
        let removed = acceptedSelections.removeValue(forKey: selection.id) != nil
        expiryTasks.removeValue(forKey: selection.id)?.cancel()
        // Keep revoked authority attached until its FIFO slot is retired. An
        // unrelated store/drain error must never turn accepted work into a legacy
        // unguarded dispatch on a later wake.
        selection.cancel()
        if removed {
            let finished = onAcceptedSelectionFinished
            Task { await finished(selection.id) }
        }
    }

    private func select(_ assetID: UUID, target frozenTarget: TargetLease?, allowCapture: Bool,
                        visibilityRevision: Int64?, accepted: AcceptedSelection? = nil, replacing: UUID? = nil) async throws {
        // Covers reentrancy while captureTarget awaits a transport reply.
        // Only the selection owner may release its UI reservation. A duplicate
        // invocation cannot settle the original while captureTarget still awaits.
        guard selecting.insert(assetID).inserted else {
            if let accepted {
                await onAcceptedSelectionSettled(accepted)
                finishAcceptedSelection(accepted)
            }
            return
        }
        var ownsSelection = true
        defer { if ownsSelection { selecting.remove(assetID) } }
        // Reserve before the first await: slower target resolution must not reorder clicks.
        let ticket = nextTicket; nextTicket += 1
        var enqueued = false
        var reserved = false
        var settled = false
        do {
            guard let record = try await store.asset(id: assetID) else { throw RiftletError.assetNotFound }
            let originalOperation: TransferOperation?
            if let activeID = record.activeOperationID,
               let op = try await store.operation(id: activeID), op.phase.isUnresolved {
                originalOperation = op
            } else { originalOperation = nil }
            // A click may observe an existing UNKNOWN instead of preparing new
            // input. It still needs the original selection's fresh permission
            // and host checks before any transport call.
            if let accepted {
                if let originalOperation, replacing == nil {
                    // The App checks permission for the selection's exact
                    // process. That result cannot authorize observation in a
                    // different still-running browser session. Leave that old
                    // operation to its independent read-only recovery path.
                    guard accepted.target.adapterID == originalOperation.target.adapterID,
                          accepted.target.applicationID == originalOperation.target.applicationID,
                          accepted.target.sessionID == originalOperation.target.sessionID else {
                        throw RiftletError.invalidTransition
                    }
                }
                guard accepted.isValid(), await validateAcceptedSelection(accepted), accepted.isValid() else {
                    throw RiftletError.invalidTransition
                }
            }
            if let op = originalOperation, replacing == nil {
                if op.phase == .unknown || op.phase == .compensated {
                    if usesIndependentFileInput, try await store.ownsDispatchedOperation(op.id, ownerID: dispatchOwnerID) {
                        currentFileInputs[op.id] = InputWatch(registeredAt: observationClock())
                    }
                    try await reconcile(op)
                }
                await onChange()
                selecting.remove(assetID); ownsSelection = false; settled = true
                await settleSelection(assetID, accepted: accepted)
                if let accepted { finishAcceptedSelection(accepted) }
                skippedTickets.insert(ticket)
                try await drain()
                return
            }
            // Existing UNKNOWNs above retain their original read-only recovery
            // even when a newer input profile no longer supports their format.
            try await adapter.preflight(asset: record.image,
                fileURL: mediaDirectory.appendingPathComponent(record.image.fileName))
            try await store.reserveSelection(assetID, visibilityRevision: visibilityRevision)
            reserved = true
            let target: TargetLease
            if let frozenTarget { target = frozenTarget }
            else if allowCapture { target = try await adapter.captureTarget() }
            else { throw RiftletError.adapterUnavailable("No verified target existed at selection; image retained") }
            guard target.adapterID == adapter.id else { throw RiftletError.mismatchedReceipt }
            let op = try await store.prepare(assetID: assetID, target: target, replacing: replacing)
            await store.releaseSelection(assetID); reserved = false
            if let accepted {
                guard accepted.isValid(), acceptedSelections[accepted.id] != nil else {
                    try await cancelIfPrepared(op.id, reason: "Selection revoked during preparation; no input occurred")
                    throw RiftletError.invalidTransition
                }
                operationSelections[op.id] = accepted
            }
            waiting[ticket] = op.id
            enqueued = true
            await onChange()
            // Selection ownership ends at durable preparation, not when the
            // shared input drain finishes work for every queued image. A safely
            // reborn image may receive a new user click while that drain runs.
            selecting.remove(assetID); ownsSelection = false; settled = true
            await settleSelection(assetID, accepted: accepted)
            try await drain()
        } catch {
            if reserved { await store.releaseSelection(assetID) }
            if !settled {
                await onChange()
                selecting.remove(assetID); ownsSelection = false; settled = true
                await settleSelection(assetID, accepted: accepted)
            }
            if !enqueued {
                skippedTickets.insert(ticket)
                try? await drain()
            }
            throw error
        }
    }

    private func settleSelection(_ assetID: UUID, accepted: AcceptedSelection?) async {
        if let accepted { await onAcceptedSelectionSettled(accepted) }
        else { await onSelectionSettled(assetID) }
    }

    /// Startup never calls append for an interrupted operation.
    public func recover() async throws {
        for token in acceptedSelections.values { token.cancel() }
        for task in expiryTasks.values { task.cancel() }
        acceptedSelections.removeAll(); operationSelections.removeAll(); expiryTasks.removeAll()
        waiting.removeAll(); skippedTickets.removeAll(); drainTicket = nextTicket
        if usesIndependentFileInput {
            // Only local preparations can be released. A new click chooses its own target.
            try await store.recoverUndispatchedPreparations()
            currentFileInputs.removeAll()
            await onChange()
            return
        }
        try await store.recoverInterruptedOperations()
        await onChange()
        for op in try await store.unresolvedOperations() where (op.phase == .unknown || op.phase == .compensated) && op.target.adapterID == adapter.id {
            do { try await reconcile(op) }
            catch { try await store.markUnknown(op.id, reason: "Recovery observation unavailable") }
        }
        await onChange()
    }

    /// App snapshots these original IDs immediately after its one local recovery,
    /// before publishing the UI/armer. Never resets newer operations or captures a
    /// target. Any queued selection awakened by a terminal receipt keeps its own token.
    public func recoverOriginalObservations(operationIDs: [UUID],
        authorize: @Sendable (TargetLease) async -> Bool = { _ in true }) async throws {
        if usesIndependentFileInput {
            guard (adapter as? any IndependentFileInputAdapter)?.supportsOriginalHandoffChecks == true else { return }
            let allowed = Set(try await store.recentOriginalObservationIDs())
            for id in operationIDs.prefix(4) where allowed.contains(id) && !Task.isCancelled {
                _ = try await recheckOriginal(operationID: id, authorize: authorize)
            }
            return
        }
        for id in Set(operationIDs) {
            guard let op = try await store.operation(id: id), op.target.adapterID == adapter.id,
                  op.phase == .unknown || op.phase == .compensated else { continue }
            guard !Task.isCancelled, await authorize(op.target), !Task.isCancelled,
                  try await store.operation(id: op.id) == op else { continue }
            do { try await reconcile(op) }
            catch {
                if let current = try await store.operation(id: id),
                   current.phase == .unknown || current.phase == .compensated {
                    try await store.markUnknown(id, reason: "Recovery observation unavailable")
                }
            }
        }
        await onChange()
    }

    /// Consider only contiguous original clicks. A busy A can hold its own later
    /// clicks without head-of-line blocking an already addressed tab B.
    private func nextDispatchTicket() async throws -> Int? {
        var ticket = drainTicket
        let occupied = inputExecutions.compactMap { activeAppends[$0]?.operation.target }
        while true {
            if skippedTickets.contains(ticket) { ticket += 1; continue }
            guard let id = waiting[ticket] else { return nil }
            guard usesIndependentFileInput, !occupied.isEmpty else { return ticket }
            guard operationSelections[id]?.authorization == .currentClick else {
                return ticket == drainTicket ? ticket : nil
            }
            guard let operation = try await store.operation(id: id), operation.phase == .prepared,
                  occupied.contains(where: { $0.sharesInputTab(with: operation.target) }) else { return ticket }
            ticket += 1
        }
    }

    private func drain() async throws {
        guard !isDraining else { drainRequested = true; return }
        isDraining = true
        defer {
            isDraining = false
            if drainRequested {
                drainRequested = false
                Task { try? await self.drain() }
            }
        }
        while true {
            if skippedTickets.remove(drainTicket) != nil { drainTicket += 1; continue }
            guard let ticket = try await nextDispatchTicket(), let id = waiting[ticket] else { break }
            let accepted = operationSelections[id]
            guard let op = try await store.operation(id: id), op.phase == .prepared else {
                advanceWaiting(ticket: ticket, id: id, selection: accepted); continue
            }
            // Only a still-executing input occupies the normal file-input lane.
            // Background observers and persisted upload phases are not capacity.
            if usesIndependentFileInput {
                guard accepted?.authorization == .currentClick || inputExecutions.isEmpty else { return }
            } else {
                guard activeAppends.count < maximumPendingSelections,
                      activeAppends.values.filter({ inputExecutions.contains($0.operation.id) })
                        .allSatisfy({ op.target.hasIndependentInputDocument(from: $0.operation.target) }) else { return }
            }
            if let accepted {
                guard accepted.isValid(), await validateAcceptedSelection(accepted), accepted.isValid() else {
                    try await cancelIfPrepared(id, reason: "Original selection no longer authorized; no input occurred")
                    advanceWaiting(ticket: ticket, id: id, selection: accepted); await onChange(); continue
                }
            }
            // Validation failure is before intent: safe to leave retryable, without any input.
            let targetValid: Bool
            do { targetValid = try await adapter.validate(op.target) }
            catch {
                if try await store.operation(id: id)?.phase == .prepared {
                    try await cancelIfPrepared(id, reason: "Target validation unavailable before input")
                }
                advanceWaiting(ticket: ticket, id: id, selection: accepted); await onChange(); continue
            }
            guard try await store.operation(id: id)?.phase == .prepared else { advanceWaiting(ticket: ticket, id: id, selection: accepted); await onChange(); continue }
            guard targetValid else {
                try await cancelIfPrepared(id, reason: "Original target changed before input")
                advanceWaiting(ticket: ticket, id: id, selection: accepted); await onChange(); continue
            }
            let request = try await request(for: op)
            guard FileManager.default.fileExists(atPath: request.fileURL.path) else {
                try await cancelIfPrepared(id, reason: "Private image is missing; no input occurred")
                try await store.markMissingAsset(op.assetID)
                advanceWaiting(ticket: ticket, id: id, selection: accepted); await onChange(); continue
            }
            if let accepted {
                guard accepted.isValid(), await validateAcceptedSelection(accepted), accepted.isValid() else {
                    try await cancelIfPrepared(id, reason: "Original selection revoked before intent; no input occurred")
                    advanceWaiting(ticket: ticket, id: id, selection: accepted); await onChange(); continue
                }
            }
            do {
                if usesIndependentFileInput {
                    try await store.markIndependentFileInputIntent(id, selection: accepted, ownerID: dispatchOwnerID)
                    currentFileInputs[id] = InputWatch(registeredAt: observationClock())
                } else {
                    try await store.markDispatchIntent(id, selection: accepted, ownerID: dispatchOwnerID)
                }
            } catch RiftletError.targetBusy {
                try await cancelIfPrepared(id, reason: "This adapter still owns the target; no input occurred")
                advanceWaiting(ticket: ticket, id: id, selection: accepted); await onChange(); continue
            }
            catch RiftletError.invalidTransition {
                // A user removal may retire prepared work during preflight.
                // No intent was committed; do not resurrect or dispatch it.
                try await cancelIfPrepared(id, reason: "Selection retired before input intent")
                advanceWaiting(ticket: ticket, id: id, selection: accepted); await onChange(); continue
            }
            advanceWaiting(ticket: ticket, id: id, selection: accepted)
            let committedRequest: TransferRequest
            do {
                guard let committed = try await store.operation(id: id) else { throw RiftletError.operationNotFound }
                committedRequest = try await self.request(for: committed)
            } catch {
                // Intent is already durable and its FIFO slot is retired. A
                // failed local reread must retain UNKNOWN, never strand an
                // invisible dispatchIntent or attempt the input a second time.
                try await store.markUnknown(id, reason: "Original request unavailable after input intent")
                if let invocationID = try await store.dispatchInvocationID(for: id) {
                    try await store.recordInputExecutionReturned(operationID: id,
                        invocationID: invocationID, ownerID: dispatchOwnerID)
                }
                await onChange(); continue
            }
            if let phased = adapter as? any InputPhasedAttachmentAdapter {
                let boundary = InputPhaseBoundary()
                activeAppends[id] = committedRequest
                inputExecutions.insert(id)
                Task { await self.runPhasedAppend(committedRequest, adapter: phased, boundary: boundary) }
                if !usesIndependentFileInput || accepted?.authorization != .currentClick { try await boundary.wait() }
            } else {
                try await finishOriginalAppend(committedRequest) { try await self.adapter.append(committedRequest) }
                await onChange()
            }
        }
    }

    private func inputConfirmed(_ receipt: TransferReceipt, request: TransferRequest,
                                boundary: InputPhaseBoundary) async {
        let original = request.operation
        guard let owner = activeAppends[original.id], owner.invocationID == request.invocationID,
              request.invocationID != nil, receipt.operationID == original.id,
              receipt.assetID == original.assetID, receipt.attempt == original.attempt,
              receipt.assetSHA256 == request.asset.sha256, receipt.target == original.target,
              receipt.belongsToOriginalDraft, !receipt.hasError,
              receipt.outcome == .inputTriggered || receipt.outcome == .uploadStarted else { return }
        await boundary.finish()
    }

    private func inputExecutionReturned(request: TransferRequest, boundary: InputPhaseBoundary) async {
        let id = request.operation.id
        guard let owner = activeAppends[id], let invocationID = request.invocationID,
              owner.invocationID == invocationID, inputExecutions.remove(id) != nil else { return }
        // No receipt, START or visibility is invented. The original adapter says
        // its synchronous call returned; upload observation does not own input.
        try? await store.recordInputExecutionReturned(operationID: id,
            invocationID: invocationID, ownerID: dispatchOwnerID)
        await boundary.finish()
        try? await drain()
    }

    private func runPhasedAppend(_ request: TransferRequest, adapter: any InputPhasedAttachmentAdapter,
                                 boundary: InputPhaseBoundary) async {
        let result: Result<Void, Error>
        do {
            try await finishOriginalAppend(request) {
                if let independent = adapter as? any IndependentFileInputAdapter {
                    return try await independent.append(request, onInputExecutionReturned: {
                        await self.inputExecutionReturned(request: request, boundary: boundary)
                    })
                }
                return try await adapter.append(request, onInputConfirmed: { receipt in
                    await self.inputConfirmed(receipt, request: request, boundary: boundary)
                })
            }
            result = .success(())
        } catch { result = .failure(error) }
        activeAppends.removeValue(forKey: request.operation.id)
        inputExecutions.remove(request.operation.id)
        await boundary.finish(result)
        await onChange()
        // Transport failure also ends this host call. The page's synchronous
        // lock independently prevents a second setter from covering a live one.
        try? await drain()
    }

    private func finishOriginalAppend(_ committedRequest: TransferRequest,
                                     append: () async throws -> TransferReceipt) async throws {
        let id = committedRequest.operation.id
        do {
            let receipt = try await append()
            _ = try await store.apply(receipt, policy: policy)

            if let invocationID = committedRequest.invocationID {
                try await store.recordAppendReturned(receipt, invocationID: invocationID, ownerID: dispatchOwnerID)
            }
            if receipt.outcome == .inputTriggered || receipt.outcome == .attachedCandidate {
                // Observation may return a candidate, never a synthetic success timeout.
                try await store.markUnknown(id, reason: "Input observed; conclusive completion is unavailable")
            }
        } catch let rejection as PreInputRejection {
            do {
                guard rejection.operationID == id else { throw RiftletError.mismatchedReceipt }
                try await store.recordPreInputRejection(rejection)
                currentFileInputs.removeValue(forKey: id)
            }
            catch { try await store.markUnknown(id, reason: "Invalid pre-input proof; original operation retained") }
        } catch {
            // Includes a transport crash or a malformed/mismatched reply after intent.
            try await store.markUnknown(id, reason: "No trustworthy completion after input intent")
        }
        // A lost or malformed reply never becomes a persistent input lock.
        // This operation remains observation-only; a different screenshot has
        // its own invocation and the page checks its current synchronous lock.
        if let invocationID = committedRequest.invocationID {
            try await store.recordInputExecutionReturned(operationID: id,
                invocationID: invocationID, ownerID: dispatchOwnerID)
        }
    }

    private func advanceWaiting(ticket: Int, id: UUID, selection: AcceptedSelection?) {
        waiting.removeValue(forKey: ticket)
        operationSelections.removeValue(forKey: id)
        if ticket == drainTicket { drainTicket += 1 } else { skippedTickets.insert(ticket) }
        if let selection { finishAcceptedSelection(selection) }
    }

    /// One user-requested read of the durable original binding, independent of
    /// the background polling budget. This method never queues or drains input.
    public func recheckOriginal(operationID: UUID,
        authorize: @Sendable (TargetLease) async -> Bool) async throws -> OriginalAttachmentCheck {
        try await recheckOriginal(operationID: operationID, inspectAccess: { target in
            await authorize(target) ? .granted : .permissionRequired
        })
    }

    public func recheckOriginal(operationID: UUID,
        inspectAccess: @Sendable (TargetLease) async -> OriginalReceiverAccess) async throws -> OriginalAttachmentCheck {
        guard (adapter as? any IndependentFileInputAdapter)?.supportsOriginalHandoffChecks == true,
              let op = try await store.operation(id: operationID),
              op.phase.isUnresolved, op.phase != .prepared, op.target.adapterID == adapter.id,
              let asset = try await store.asset(id: op.assetID), asset.activeOperationID == op.id,
              let invocation = try await store.dispatchInvocationID(for: op.id) else { return .unavailable }
        switch await inspectAccess(op.target) {
        case .unavailable: return .unavailable
        case .permissionRequired: return .permissionDenied
        case .granted: break
        }
        guard !Task.isCancelled, activeAppends[op.id] == nil, observing.insert(op.id).inserted else { return .busy }
        defer { observing.remove(op.id) }
        let request = TransferRequest(operation: op, asset: asset.image,
            fileURL: mediaDirectory.appendingPathComponent(asset.image.fileName),
            invocationID: invocation, requireLiveOriginal: true)
        do {
            for read in 0..<2 {
                let receipt = try await adapter.reconcile(request)
                guard receipt.operationID == op.id, receipt.assetID == asset.id,
                      receipt.attempt == op.attempt, receipt.assetSHA256 == asset.image.sha256,
                      receipt.target == op.target, receipt.belongsToOriginalDraft,
                      !Task.isCancelled, try await store.asset(id: asset.id)?.activeOperationID == op.id else { return .unavailable }
                let previousStart = try await store.uploadStartReceipt(for: op.id)
                if let start = previousStart {
                    guard receipt.attachmentID != nil, receipt.attachmentID == start.attachmentID else { return .unavailable }
                    // Historical START does not prove that a reported failure resolved.
                    if !receipt.hasError { return .observed }
                    guard [.unknown, .definitiveFailure].contains(receipt.outcome) else { return .unavailable }
                }
                if try await store.receipt(for: op.id) != receipt {
                    _ = try await store.apply(receipt, policy: policy)
                    await onChange()
                }
                // A page may present a retained START before its live error. Once
                // Core actually commits that first fact, read the original card once
                // more so a single user check can also recover its current status.
                guard read == 0, previousStart == nil, receipt.outcome == .uploadStarted,
                      try await store.uploadStartReceipt(for: op.id) != nil else { return .observed }
            }
            return .observed
        } catch { return .unavailable }
    }

    private func reconcile(_ op: TransferOperation) async throws {
        guard op.target.adapterID == adapter.id else { throw RiftletError.adapterUnavailable("Original adapter is unavailable") }
        if usesIndependentFileInput {
            guard currentFileInputs[op.id] != nil, try await !store.isAttachmentHandled(op.id) else { return }
        }
        guard activeAppends[op.id] == nil, observing.insert(op.id).inserted else { return }
        defer { observing.remove(op.id) }
        let original = try await request(for: op)
        let receipt = try await adapter.reconcile(original)
        if usesIndependentFileInput {
            guard try await !store.isAttachmentHandled(op.id) else { return }
            // A past START stays immutable. Only an error explicitly attached to
            // that same original member can change its latest status.
            if let start = try await store.uploadStartReceipt(for: op.id) {
                guard receipt.hasError, receipt.belongsToOriginalDraft,
                      receipt.attachmentID != nil, receipt.attachmentID == start.attachmentID,
                      [.unknown, .definitiveFailure].contains(receipt.outcome) else { return }
            }
            guard try await store.receipt(for: op.id) != receipt else { return }
        }
        let updated = try await store.apply(receipt, policy: policy)
        if usesIndependentFileInput, updated.status == .failed {
            currentFileInputs.removeValue(forKey: op.id)
        }
        await onChange()
        try await drain()
    }

    /// A bounded set of single reads of current-process operations. Navigation,
    /// permission loss, and elapsed time never certify termination or re-input.
    public func observePending(limit: Int = 8,
        authorize: @Sendable (TargetLease) async -> Bool = { _ in true }) async throws {
        if usesIndependentFileInput {
            let now = observationClock()
            let due = currentFileInputs.filter { $0.value.due <= now && activeAppends[$0.key] == nil }
                .sorted { $0.value.due == $1.value.due ? $0.key.uuidString < $1.key.uuidString : $0.value.due < $1.value.due }
                .prefix(max(0, min(32, limit)))
            for (id, var watch) in due {
                guard !Task.isCancelled else { return }
                // Denied probes do not use read attempts or keep a dead watch
                // resident after the page's own ten-minute observation window.
                guard now - watch.registeredAt < 600 else {
                    currentFileInputs.removeValue(forKey: id)
                    continue
                }
                watch.due = now + min(120, 5 * pow(2, Double(watch.reads)))
                currentFileInputs[id] = watch
                guard let op = try await store.operation(id: id), op.phase.isUnresolved,
                      try await !store.isAttachmentHandled(id) else {
                    currentFileInputs.removeValue(forKey: id)
                    continue
                }
                guard await authorize(op.target), !Task.isCancelled else {
                    if currentFileInputs[id] != nil {
                        watch.due = now + 30
                        currentFileInputs[id] = watch
                    }
                    continue
                }
                guard currentFileInputs[id] != nil else { continue }
                watch.reads += 1
                currentFileInputs[id] = watch
                defer { if watch.reads >= 8 { currentFileInputs.removeValue(forKey: id) } }
                // The original durable receipt survives an inaccessible tab.
                // Transport failure consumes only this read's time budget.
                try? await reconcile(op)
            }
            return
        }
        let candidates = try await store.unresolvedOperations().filter {
            $0.target.adapterID == adapter.id && [.inputTriggered, .attachmentPresent, .unknown, .compensated].contains($0.phase)
        }
        guard !candidates.isEmpty else { observationCursor = 0; return }
        let count = max(0, min(limit, min(32, candidates.count)))
        let start = observationCursor % candidates.count
        observationCursor = (start + count) % candidates.count
        for offset in 0..<count {
            let op = candidates[(start + offset) % candidates.count]
            // Permission belongs to the immutable receiver, not the current foreground.
            // A denied check changes neither its phase nor its input/UNKNOWN history.
            guard !Task.isCancelled, await authorize(op.target), !Task.isCancelled,
                  try await store.operation(id: op.id) == op else { continue }
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
    public func observeCompleted(operationID: UUID,
        authorize: @Sendable (TargetLease) async -> Bool = { _ in true }) async throws -> Bool {
        guard !usesIndependentFileInput else { return false }
        guard let op = try await store.operation(id: operationID), op.phase == .succeeded,
              op.target.adapterID == adapter.id else { return false }
        // Temporary permission loss must retain the late-result watch.
        guard !Task.isCancelled, await authorize(op.target), !Task.isCancelled,
              try await store.operation(id: op.id) == op else { return true }
        guard observing.insert(op.id).inserted else { return true }
        defer { observing.remove(op.id) }
        let receipt = try await adapter.reconcile(try await request(for: op))
        _ = try await store.apply(receipt, policy: policy)
        await onChange()
        let current = try await store.operation(id: operationID)
        return receipt.belongsToOriginalDraft && current?.phase == .succeeded
    }

    private func cancelIfPrepared(_ id: UUID, reason: String) async throws {
        try await store.cancelPreparedIfNeeded(id, reason: reason)
    }

    private func request(for op: TransferOperation) async throws -> TransferRequest {
        guard let asset = try await store.asset(id: op.assetID) else { throw RiftletError.assetNotFound }
        return TransferRequest(operation: op, asset: asset.image, fileURL: mediaDirectory.appendingPathComponent(asset.image.fileName),
                               invocationID: try await store.dispatchInvocationID(for: op.id))
    }
}

/// Default ordinary-capture boundary. The separately launched internal candidate
/// composes its own adapter; permissions never enable this unavailable adapter.
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
