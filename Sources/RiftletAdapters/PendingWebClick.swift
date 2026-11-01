import Foundation

/// Runtime-only original press. Never serialized/recovered and never an upload
/// operation: a failed/expired resolution cannot create a dispatch intent.
public final class PendingWebClick: @unchecked Sendable {
    public let id: UUID
    public let assetID: UUID
    public let session: String
    public let window: String
    public let tab: String
    public let eventUptime: TimeInterval
    public let routeFrozenUptime: TimeInterval
    public let deadlineUptime: TimeInterval
    let documentWitness: UUID
    let preparation: MainWorldCommandEnvelope?
    private let lock = NSLock()
    private var cancelled = false
    private var resolving = false
    private var promoted = false

    init(id: UUID = UUID(), assetID: UUID, session: String, window: String, tab: String,
         documentWitness: UUID, preparation: MainWorldCommandEnvelope? = nil, eventUptime: TimeInterval, routeFrozenUptime: TimeInterval) {
        self.id = id; self.assetID = assetID; self.session = session; self.window = window; self.tab = tab
        self.documentWitness = documentWitness; self.preparation = preparation; self.eventUptime = eventUptime
        self.routeFrozenUptime = routeFrozenUptime; self.deadlineUptime = eventUptime + 5
    }
    public func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
    public func isValid(at now: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }; return valid(now)
    }
    private func valid(_ now: TimeInterval) -> Bool {
        !cancelled && !promoted && now.isFinite && eventUptime.isFinite && routeFrozenUptime.isFinite
            && eventUptime >= 0 && eventUptime <= routeFrozenUptime && routeFrozenUptime <= now
            && now < deadlineUptime
    }
    func beginResolution(at now: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard valid(now), !resolving else { return false }
        resolving = true; return true
    }
    public func promote(at now: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard valid(now), resolving else { return false }
        promoted = true; return true
    }
}
