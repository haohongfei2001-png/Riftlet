import Foundation
import RiftletCore

/// Runtime authorization only; Core owns parking, ordering and durable attempts.
/// Revocation happens synchronously before any asynchronous cancellation message.
@MainActor
final class SelectionAuthority {
    private var selections: [UUID: AcceptedSelection] = [:]

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
            && selection.hostEpoch == epoch && selection.target.sessionID == foregroundSession
            && !hidden && !terminating
    }

    func finish(_ id: UUID) { selections.removeValue(forKey: id) }

    func cancel(id: UUID) {
        selections.removeValue(forKey: id)?.cancel()
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
