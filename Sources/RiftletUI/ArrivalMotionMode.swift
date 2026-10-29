import Foundation

/// The complete arrival-decoration choice set. It never controls upload-start
/// swallow, press feedback or queue reflow. Retired experiments are not modes.
public enum ArrivalMotionMode: String, CaseIterable, Codable, Sendable {
    case none
    case magnet

    /// A conservative engineering fallback, NOT an approved product default.
    /// Persistence keeps an absent choice distinct from an explicit `none`.
    public static let provisionalFallback: Self = .none

    public var title: String {
        switch self {
        case .none: return "无"
        case .magnet: return "磁力吸引"
        }
    }

    public func effective(reduceMotion: Bool) -> Self { reduceMotion ? .none : self }
}

/// Optional, ephemeral source evidence. Never part of the durable queue or an
/// upload receipt. All rectangles are global AppKit POINTS, not file pixels.
public struct RiftArrivalSource: Equatable, Sendable {
    public let rect: CGRect
    public let displayID: UInt32
    public let displayFrame: CGRect
    public let backingScale: CGFloat

    public init(rect: CGRect, displayID: UInt32, displayFrame: CGRect, backingScale: CGFloat) {
        self.rect = rect
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.backingScale = backingScale
    }
}

public enum RiftArrivalPhase: String, Sendable {
    case rowAvailable, imageDecoded, decorationStarted, decorationEnded
    case animationSubmitted, animationDelegateStarted, animationDelegateStopped
}

/// Optional software timing only: not a display-photon or physical-input claim.
public struct RiftArrivalBoundary: Sendable {
    public let phase: RiftArrivalPhase
    public let assetID: UUID
    public let uptime: TimeInterval
    public let mode: ArrivalMotionMode
    public let reason: String?
}
