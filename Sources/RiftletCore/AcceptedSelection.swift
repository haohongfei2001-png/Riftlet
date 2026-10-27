import Foundation

/// One accepted, original UI selection. Runtime-only: restart cannot restore its
/// authority. The App creates this at its synchronous frozen-target boundary and
/// revokes it synchronously before posting asynchronous coordinator cancellation.
public final class AcceptedSelection: @unchecked Sendable {
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

    public init(id: UUID = UUID(), assetID: UUID, target: TargetLease, hostEpoch: UUID,
                acknowledgedUptime: TimeInterval, eventUptime: TimeInterval, acceptedUptime: TimeInterval, visibilityRevision: Int64,
                deadlineUptime: TimeInterval, captureRequestID: UUID? = nil, armAttemptID: UUID? = nil) {
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
        !cancelled && !dispatched && acknowledgedUptime.isFinite && eventUptime.isFinite && acceptedUptime.isFinite
            && deadlineUptime.isFinite && uptime.isFinite && acknowledgedUptime >= 0
            && acknowledgedUptime < eventUptime
            && eventUptime <= acceptedUptime && acceptedUptime <= uptime
            // Match the App's acceptedUptime + 30 construction. Subtraction
            // can round a valid boundary to 30.000000000000007 and refuse it.
            && deadlineUptime > acceptedUptime && deadlineUptime <= acceptedUptime + 30
            && uptime < deadlineUptime && visibilityRevision >= 0
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
