import Foundation

/// The acknowledgement and original input event use the host uptime clock.
/// Renderer timestamps are deliberately never compared with native timestamps.
public struct ArmedTarget: Sendable {
    public let target: TargetLease
    public let acknowledgedUptime: TimeInterval
    public let hostSession: UUID

    public init(target: TargetLease, acknowledgedUptime: TimeInterval, hostSession: UUID) {
        self.target = target; self.acknowledgedUptime = acknowledgedUptime; self.hostSession = hostSession
    }

    public func freeze(eventUptime: TimeInterval, nowUptime: TimeInterval,
                       hostSession: UUID, foregroundSession: String?) -> TargetLease? {
        guard self.hostSession == hostSession, target.sessionID == foregroundSession,
              acknowledgedUptime.isFinite, eventUptime.isFinite, nowUptime.isFinite,
              acknowledgedUptime >= 0, acknowledgedUptime < eventUptime,
              eventUptime <= nowUptime else { return nil }
        return target
    }
}
