import Foundation
import RiftletCore

/// Tracks ownership of explicit clicks, cancellation and duplicate prevention.
/// Chrome focus, background discovery and historical ACKs do not decide whether
/// an already selected destination can receive a screenshot.
@MainActor
final class SelectionAuthority {
    private var selections: [UUID: AcceptedSelection] = [:]

    /// Used by the actual panel callback as well as the cold-click regression.
    /// Resolves this click's target even when no background capture ever ran.
    func accept(id: UUID, assetID: UUID, visibilityRevision: Int64,
                selectedAt: TimeInterval = ProcessInfo.processInfo.systemUptime,
                target: Task<TargetLease, Error>,
                isCurrent: @MainActor () -> Bool) async throws -> AcceptedSelection {
        let result = await target.result
        try Task.checkCancellation()
        guard !target.isCancelled, isCurrent() else { throw CancellationError() }
        let resolved = try result.get()
        let selection = AcceptedSelection(id: id, assetID: assetID, target: resolved,
                                          visibilityRevision: visibilityRevision, selectedAt: selectedAt)
        guard insert(selection, now: ProcessInfo.processInfo.systemUptime) else {
            throw RiftletError.invalidTransition
        }
        return selection
    }

    func insert(_ selection: AcceptedSelection, now: TimeInterval) -> Bool {
        selections = selections.filter { $0.value.isValid(at: now) }
        guard selection.isValid(at: now), selections.count < 16,
              !selections.values.contains(where: { $0.assetID == selection.assetID }) else { return false }
        selections[selection.id] = selection
        return true
    }

    func permits(_ selection: AcceptedSelection, epoch: UUID, foregroundSession: String?,
                 hidden: Bool, terminating: Bool, now: TimeInterval) -> Bool {
        selections[selection.id] === selection && selection.isValid(at: now)
            && !hidden && !terminating
    }

    func finish(_ id: UUID) { selections.removeValue(forKey: id) }

    func cancel(id: UUID) {
        selections.removeValue(forKey: id)?.cancel()
    }

    @discardableResult
    func cancelPinned(session: String) -> [UUID] {
        let ids = selections.values.filter { $0.target.sessionID == session }.map(\.id)
        ids.forEach { cancel(id: $0) }
        return ids
    }

    @discardableResult
    func cancelUnpinned() -> [UUID] {
        let ids = selections.values.filter { $0.authorization != .nativeClickPin }.map(\.id)
        ids.forEach { cancel(id: $0) }
        return ids
    }

    @discardableResult
    func cancel(assetID: UUID? = nil) -> [UUID] {
        var cancelled: [UUID] = []
        for (id, selection) in selections where assetID == nil || selection.assetID == assetID {
            selection.cancel()
            cancelled.append(id)
            selections.removeValue(forKey: id)
        }
        return cancelled
    }
}
