import Foundation

public struct QueueInteractionState: Equatable, Sendable {
    public let revision: UInt64
    public let blocked: Bool
}

/// Bridges synchronous AppKit input and actor-owned archive transactions. It
/// contains no AppKit objects and never calls client code while updating state.
public final class QueueInteractionFence: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var blocked = false

    public init() {}

    public func update(blocked: Bool) {
        lock.lock(); defer { lock.unlock() }
        revision &+= 1
        self.blocked = blocked
    }

    public func snapshot() -> QueueInteractionState {
        lock.lock(); defer { lock.unlock() }
        return QueueInteractionState(revision: revision, blocked: blocked)
    }

    /// QueueStore has already obtained its SQLite write transaction before this
    /// lock. Never perform transport, sleeps, filesystem scans or awaits here.
    func withArchivePermit<T>(expectedRevision: UInt64, _ body: () throws -> T) rethrows -> T? {
        lock.lock(); defer { lock.unlock() }
        guard !blocked, revision == expectedRevision else { return nil }
        return try body()
    }
}
