import Foundation

/// One explicit screenshot click and its resolved destination. This object only
/// prevents duplicate execution and lets removal/termination cancel queued work.
/// A past capture ACK, mouse timing proof and foreground epoch are not input
/// prerequisites; the adapter validates the actual destination before input.
public final class AcceptedSelection: @unchecked Sendable {
    // Retained for source compatibility with archived acceptance fixtures.
    // These labels and timestamps no longer approve or reject a new click.
    public enum Authorization: Sendable { case preEventAcknowledgement, nativeClickPin, currentClick }
    public let authorization: Authorization
    public let id: UUID
    public let assetID: UUID
    public let target: TargetLease
    public let hostEpoch: UUID
    public let acknowledgedUptime: TimeInterval
    public let eventUptime: TimeInterval
    public let acceptedUptime: TimeInterval
    public let visibilityRevision: Int64
    public let deadlineUptime: TimeInterval
    public let captureRequestID: UUID?
    public let armAttemptID: UUID?
    private let lock = NSLock()
    private var cancelled = false
    private var dispatched = false

    public convenience init(id: UUID = UUID(), assetID: UUID, target: TargetLease,
                            visibilityRevision: Int64,
                            selectedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.init(id: id, assetID: assetID, target: target, hostEpoch: UUID(),
                  acknowledgedUptime: selectedAt, eventUptime: selectedAt,
                  acceptedUptime: selectedAt, visibilityRevision: visibilityRevision,
                  deadlineUptime: .infinity, authorization: .currentClick)
    }

    public init(id: UUID = UUID(), assetID: UUID, target: TargetLease, hostEpoch: UUID,
                acknowledgedUptime: TimeInterval, eventUptime: TimeInterval, acceptedUptime: TimeInterval, visibilityRevision: Int64,
                deadlineUptime: TimeInterval, captureRequestID: UUID? = nil, armAttemptID: UUID? = nil,
                authorization: Authorization = .preEventAcknowledgement) {
        self.authorization = authorization
        self.id = id; self.assetID = assetID; self.target = target; self.hostEpoch = hostEpoch
        self.acknowledgedUptime = acknowledgedUptime
        self.eventUptime = eventUptime; self.acceptedUptime = acceptedUptime
        self.visibilityRevision = visibilityRevision; self.deadlineUptime = deadlineUptime
        self.captureRequestID = captureRequestID; self.armAttemptID = armAttemptID
    }

    public func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }

    public func isValid(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return valid(at: uptime)
    }

    private func valid(at uptime: TimeInterval) -> Bool {
        guard !cancelled, !dispatched, acceptedUptime.isFinite, uptime.isFinite,
              acceptedUptime >= 0, acceptedUptime <= uptime, visibilityRevision >= 0 else { return false }
        // New clicks remain revocable until the exact draft is rechecked at dispatch.
        if authorization == .currentClick { return true }
        return deadlineUptime.isFinite && deadlineUptime > acceptedUptime
            && deadlineUptime <= acceptedUptime + 30 && uptime < deadlineUptime
    }

    /// Serializes synchronous revocation with the final SQLite intent write,
    /// after the transaction lock and state checks. No transport, callback,
    /// contended BEGIN or await is allowed inside this lock.
    func authorizeDispatch<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard valid(at: ProcessInfo.processInfo.systemUptime) else { throw RiftletError.invalidTransition }
        let result = try body()
        dispatched = true
        return result
    }
}
