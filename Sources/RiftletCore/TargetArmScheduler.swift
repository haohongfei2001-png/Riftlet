import Foundation

/// Synchronous scheduling state only. The owning actor performs transport work
/// and sends wake signals; this type never launches, cancels, or retries input.
/// A request is a demand to observe/arm a target, not an attachment selection.
public struct TargetArmScheduler: Sendable {
    public struct Attempt: Equatable, Sendable {
        public let epoch: UUID
        public let id: UUID
        fileprivate init(epoch: UUID) { self.epoch = epoch; id = UUID() }
    }

    public struct Completion: Equatable, Sendable {
        /// Check this before publishing the returned target acknowledgement.
        public let acceptsAcknowledgement: Bool
        /// Send exactly one wake signal; begin() still enforces single flight.
        public let shouldWake: Bool
    }

    public private(set) var epoch = UUID()
    public private(set) var isRunning = false
    public private(set) var hasPendingRequest = false
    public private(set) var inFlight: Attempt?

    public init() {}

    /// Idempotent while running. Restart retains an old transport until it drains.
    @discardableResult
    public mutating func start() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        epoch = UUID()
        hasPendingRequest = true
        return inFlight == nil
    }

    /// Coalesces arbitrary event bursts into one pending arm. Target-changing
    /// events must invalidate the epoch; ordinary demand may keep an in-flight ACK.
    @discardableResult
    public mutating func request(invalidateEpoch: Bool = false) -> Bool {
        guard isRunning else { return false }
        if invalidateEpoch { epoch = UUID() }
        let alreadyPending = hasPendingRequest
        hasPendingRequest = true
        return !alreadyPending && inFlight == nil
    }

    /// Even a stale/duplicate wake cannot begin concurrent transport work.
    public mutating func begin() -> Attempt? {
        guard isRunning, hasPendingRequest, inFlight == nil else { return nil }
        hasPendingRequest = false
        let attempt = Attempt(epoch: epoch)
        inFlight = attempt
        return attempt
    }

    /// The caller must invoke complete for success or failure. A failure may
    /// leave a separately requested next arm pending, but creates no retry itself.
    public mutating func complete(_ attempt: Attempt) -> Completion? {
        guard inFlight == attempt else { return nil }
        inFlight = nil
        return Completion(acceptsAcknowledgement: isRunning && attempt.epoch == epoch,
                          shouldWake: isRunning && hasPendingRequest)
    }

    /// Revoke publication immediately, but never pretend an active transport has
    /// stopped. A later start must wait for its matching completion to drain.
    public mutating func stop() {
        isRunning = false
        epoch = UUID()
        hasPendingRequest = false
    }
}
