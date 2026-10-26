import Foundation
import RiftletCore

public enum MacAdapterMode: Sendable { case disabled, syntheticDevelopment }
public enum MacAdapterError: Error, Equatable {
    case disabled, invalidTarget, invalidRequest, syntheticAssetsOnly, clipboardBusy, clipboardChanged
}

/// Platform observations provide PID and launch time separately; both must agree
/// with the durable TargetLease. This prevents PID/window reuse after app restart.
public struct MacTargetSession: Equatable, Sendable {
    public let processID: Int32
    public let launchedAt: Date
    public let target: TargetLease

    public static func sessionID(processID: Int32, launchedAt: Date) -> String {
        "pid:\(processID);launch:\(launchedAt.timeIntervalSince1970.bitPattern)"
    }

    public init(processID: Int32, launchedAt: Date, target: TargetLease) throws {
        guard processID > 0, launchedAt.timeIntervalSince1970.isFinite,
              target.sessionID == Self.sessionID(processID: processID, launchedAt: launchedAt),
              [TargetSurface.macChat, .macWork, .macClassic].contains(target.surface), target.tabID == nil,
              [target.adapterID, target.applicationID, target.windowID, target.documentID,
               target.composerID, target.draftGeneration].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }) else {
            throw MacAdapterError.invalidTarget
        }
        self.processID = processID; self.launchedAt = launchedAt; self.target = target
    }
}

public struct ClipboardCapturedState: Sendable {
    public let changeCount: Int
    public let snapshot: ClipboardSnapshot
    public init(changeCount: Int, snapshot: ClipboardSnapshot) {
        self.changeCount = changeCount; self.snapshot = snapshot
    }
}

public struct ClipboardOwnerState: Equatable, Sendable {
    public let changeCount: Int
    public let marker: String?
    public init(changeCount: Int, marker: String?) { self.changeCount = changeCount; self.marker = marker }
}

/// No general-pasteboard implementation is enabled in this increment. A future
/// native driver must check ownership again inside its final synchronous write
/// fragment; this interface does not assert an OS-level atomic compare-and-swap.
public protocol ClipboardTransactionDriver: Sendable {
    func capture() async throws -> ClipboardCapturedState
    func writeIfUnchanged(_ payload: ClipboardAttachmentPayload, expectedChangeCount: Int) async throws -> ClipboardOwnerState?
    func owner() async throws -> ClipboardOwnerState
    func restoreIfOwned(_ snapshot: ClipboardSnapshot, expectedOwner: ClipboardOwnerState) async throws -> Bool
}

public protocol MacAttachmentExecutor: Sendable {
    func captureTarget() async throws -> MacTargetSession
    func inspectTarget(_ original: TargetLease) async throws -> MacTargetSession?
    /// The native executor must recheck the private file's exact bytes/SHA-256,
    /// PID/launch/window/composer/draft and supplied clipboard ownership in the
    /// same input fragment. Fake executors test orchestration, not these actual
    /// filesystem/AX/pasteboard guarantees. No guessed AX selector is supplied here.
    func paste(_ request: TransferRequest, owner: ClipboardOwnerState) async throws -> Data
    /// Query the original operation only; never paste or choose the current window.
    func observe(_ request: TransferRequest) async throws -> Data
}

/// Executable session/ownership foundation with injected platform operations.
/// ReceiptPolicy and QueueStore remain the admission and queue authorities.
public actor MacAttachmentAdapter: AttachmentAdapter {
    public nonisolated let id: String
    private let applicationID: String
    private let executor: any MacAttachmentExecutor
    private let clipboard: any ClipboardTransactionDriver
    private let mode: MacAdapterMode
    private let normalizer: ObservationNormalizer
    private let policy: ReceiptPolicy
    private let onIssue: @Sendable (String) async -> Void
    private var appending = false
    private var pending: (operationID: UUID, lease: ClipboardOwnershipLease)?

    public init(applicationID: String, executor: any MacAttachmentExecutor,
                clipboard: any ClipboardTransactionDriver, profile: ObservationProfile,
                policy: ReceiptPolicy = .init(), mode: MacAdapterMode = .disabled,
                onIssue: @escaping @Sendable (String) async -> Void = { _ in }) {
        id = profile.adapterID; self.applicationID = applicationID
        self.executor = executor; self.clipboard = clipboard
        normalizer = ObservationNormalizer(profile: profile)
        self.policy = policy; self.mode = mode; self.onIssue = onIssue
    }

    public func captureTarget() async throws -> TargetLease {
        try requireEnabled()
        let session = try await executor.captureTarget()
        try check(session.target)
        return session.target
    }

    public func validate(_ target: TargetLease) async throws -> Bool {
        try requireEnabled(); try check(target)
        // An uncertain paste may still need the current clipboard. Do not replace
        // its bytes for another image while an original consumption is unproved.
        guard pending == nil, !appending else { return false }
        return try await executor.inspectTarget(target)?.target == target
    }

    public func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try requireEnabled(); try check(request.operation.target)
        guard request.asset.origin == .synthetic else { throw MacAdapterError.syntheticAssetsOnly }
        guard request.operation.phase == .dispatchIntent,
              request.operation.assetID == request.asset.id else { throw MacAdapterError.invalidRequest }
        guard pending == nil, !appending else { throw MacAdapterError.clipboardBusy }
        appending = true
        defer { appending = false }
        guard try await executor.inspectTarget(request.operation.target)?.target == request.operation.target else {
            throw MacAdapterError.invalidTarget
        }
        let before = try await clipboard.capture()
        let payload = try ClipboardAttachmentPayload(request: request)
        guard let written = try await clipboard.writeIfUnchanged(payload, expectedChangeCount: before.changeCount),
              written.marker == payload.marker,
              written.changeCount > before.changeCount else { throw MacAdapterError.clipboardChanged }
        let lease = try ClipboardOwnershipLease(request: request, previous: before.snapshot,
            payload: payload, writtenChangeCount: written.changeCount)
        pending = (request.operation.id, lease)
        let data = try await executor.paste(request, owner: written)
        let receipt = try normalizer.receipt(from: ObservationDecoder.decode(data), for: request)
        await settleClipboardAfterObservation(receipt, request: request)
        return receipt
    }

    public func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        try requireEnabled(); try check(request.operation.target)
        guard request.asset.origin == .synthetic else { throw MacAdapterError.syntheticAssetsOnly }
        guard request.operation.phase.isUnresolved, request.operation.phase != .prepared,
              request.operation.assetID == request.asset.id else { throw MacAdapterError.invalidRequest }
        guard try await executor.inspectTarget(request.operation.target)?.target == request.operation.target else {
            throw MacAdapterError.invalidTarget
        }
        let data = try await executor.observe(request)
        let receipt = try normalizer.receipt(from: ObservationDecoder.decode(data), for: request)
        await settleClipboardAfterObservation(receipt, request: request)
        return receipt
    }

    private func settleClipboardAfterObservation(_ receipt: TransferReceipt, request: TransferRequest) async {
        guard let pending, pending.operationID == request.operation.id, pending.lease.matches(receipt) else { return }
        if policy.allowsRetry(receipt: receipt, asset: request.asset, mode: .production) {
            // A separately admitted terminal failure permits a future EXPLICIT
            // retry. It does not prove pasteboard consumption or authorize restoring
            // the old clipboard. Leave present bytes untouched; do not paste again.
            self.pending = nil
            return
        }
        guard policy.allowsConsumption(receipt: receipt, asset: request.asset, mode: .production) else { return }
        do {
            let current = try await clipboard.owner()
            if let snapshot = pending.lease.restoration(currentChangeCount: current.changeCount,
                currentMarker: current.marker, receipt: receipt, policy: policy) {
                // Recheck inside the driver too: a user copy may occur after owner().
                _ = try await clipboard.restoreIfOwned(snapshot, expectedOwner: current)
            }
        } catch {
            // A clipboard error does not invalidate independently proved remote
            // completion. Never retry input to make restoration look successful.
            await onIssue("Clipboard restoration unavailable; no attachment was replayed")
        }
        if self.pending?.operationID == request.operation.id { self.pending = nil }
    }

    private func requireEnabled() throws {
        guard case .syntheticDevelopment = mode else { throw MacAdapterError.disabled }
    }

    private func check(_ target: TargetLease) throws {
        guard [TargetSurface.macChat, .macWork, .macClassic].contains(target.surface),
              target.surface == normalizer.profile.surface, target.adapterID == id,
              target.applicationID == applicationID, target.tabID == nil else { throw MacAdapterError.invalidTarget }
    }
}
