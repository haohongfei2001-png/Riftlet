import Foundation

/// «薄界» implementation candidate; exact visual values await founder review.
/// All dimensions are logical points and may be changed without touching capture or transfer code.
public struct RiftConfiguration: Codable, Equatable, Sendable {
    public var fitWidth: Double = 72
    public var fitHeight: Double = 56
    public var hiddenFraction: Double = 0.25
    public var rowPitch: Double = 60
    public var lineWidth: Double = 0.5
    public var lineExtension: Double = 8
    /// Decode legacy settings without retaining the retired empty-queue line.
    public var emptyTraceLength: Double = 24
    public var outerInset: Double = 14
    public var firstCenterFromTop: Double = 202
    public var screenPadding: Double = 12
    public var numberFontSize: Double = 11
    public var numberGap: Double = 8
    public var leftPadding: Double = 4
    public var minimumHitWidth: Double = 44
    public var minimumHitHeight: Double = 44
    public var arrivalDuration: Double = 0.220
    public var pressDuration: Double = 0.060
    public var inwardDistance: Double = 1.5
    /// Adjustable engineering starting value, not an approved timing specification.
    public var swallowDuration: Double = 0.120
    public var shiftDuration: Double = 0.160
    public var returnDuration: Double = 0.180
    public var reducedMotionDuration: Double = 0.080
    /// A stable CGDirectDisplayID selected in setup. Never inferred from a late file event.
    public var preferredDisplayID: UInt32? = nil

    public init() {}

    public func validate() throws {
        let positive = [fitWidth, fitHeight, rowPitch, lineWidth, emptyTraceLength,
                        numberFontSize, minimumHitWidth, minimumHitHeight]
        let nonnegative = [lineExtension, outerInset, firstCenterFromTop, screenPadding,
                           numberGap, leftPadding, arrivalDuration, pressDuration,
                           inwardDistance, swallowDuration, shiftDuration, returnDuration,
                           reducedMotionDuration]
        guard positive.allSatisfy({ $0.isFinite && $0 > 0 }),
              nonnegative.allSatisfy({ $0.isFinite && $0 >= 0 }),
              hiddenFraction.isFinite, (0...0.9).contains(hiddenFraction),
              fitWidth <= 256, fitHeight <= 256, numberFontSize <= 32,
              minimumHitWidth <= 256, minimumHitHeight <= 256,
              lineWidth <= 8, outerInset <= 256, screenPadding <= 256,
              [arrivalDuration, pressDuration, swallowDuration, shiftDuration,
               returnDuration, reducedMotionDuration].allSatisfy({ $0 <= 3 }) else {
            throw RiftConfigurationError.invalidGeometry
        }
    }
}

public enum RiftConfigurationError: Error, Equatable { case invalidGeometry }
