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
    public var outerInset: Double = 6
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

    public var visibleCountPreference: Int = 3
    /// nil preserves a legacy absolute right-edge layout until an explicit choice.
    public var placement: RiftPlacement? = .leftMiddle
    public var placementSource: RiftPlacementSource = .initialRecommendation
    public var preferredDisplayUUID: String? = nil

    public init() {}


    private enum CodingKeys: String, CodingKey { case fitWidth, fitHeight, hiddenFraction, rowPitch, lineWidth, lineExtension, emptyTraceLength, outerInset, firstCenterFromTop, screenPadding, numberFontSize, numberGap, leftPadding, minimumHitWidth, minimumHitHeight, arrivalDuration, pressDuration, inwardDistance, swallowDuration, shiftDuration, returnDuration, reducedMotionDuration, preferredDisplayID, visibleCountPreference, placement, placementSource, preferredDisplayUUID }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fitWidth = try values.decodeIfPresent(Double.self, forKey: .fitWidth) ?? 72
        fitHeight = try values.decodeIfPresent(Double.self, forKey: .fitHeight) ?? 56
        hiddenFraction = try values.decodeIfPresent(Double.self, forKey: .hiddenFraction) ?? 0.25
        rowPitch = try values.decodeIfPresent(Double.self, forKey: .rowPitch) ?? 60
        lineWidth = try values.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 0.5
        lineExtension = try values.decodeIfPresent(Double.self, forKey: .lineExtension) ?? 8
        emptyTraceLength = try values.decodeIfPresent(Double.self, forKey: .emptyTraceLength) ?? 24
        outerInset = try values.decodeIfPresent(Double.self, forKey: .outerInset) ?? 14
        firstCenterFromTop = try values.decodeIfPresent(Double.self, forKey: .firstCenterFromTop) ?? 202
        screenPadding = try values.decodeIfPresent(Double.self, forKey: .screenPadding) ?? 12
        numberFontSize = try values.decodeIfPresent(Double.self, forKey: .numberFontSize) ?? 11
        numberGap = try values.decodeIfPresent(Double.self, forKey: .numberGap) ?? 8
        leftPadding = try values.decodeIfPresent(Double.self, forKey: .leftPadding) ?? 4
        minimumHitWidth = try values.decodeIfPresent(Double.self, forKey: .minimumHitWidth) ?? 44
        minimumHitHeight = try values.decodeIfPresent(Double.self, forKey: .minimumHitHeight) ?? 44
        arrivalDuration = try values.decodeIfPresent(Double.self, forKey: .arrivalDuration) ?? 0.220
        pressDuration = try values.decodeIfPresent(Double.self, forKey: .pressDuration) ?? 0.060
        inwardDistance = try values.decodeIfPresent(Double.self, forKey: .inwardDistance) ?? 1.5
        swallowDuration = try values.decodeIfPresent(Double.self, forKey: .swallowDuration) ?? 0.120
        shiftDuration = try values.decodeIfPresent(Double.self, forKey: .shiftDuration) ?? 0.160
        returnDuration = try values.decodeIfPresent(Double.self, forKey: .returnDuration) ?? 0.180
        reducedMotionDuration = try values.decodeIfPresent(Double.self, forKey: .reducedMotionDuration) ?? 0.080
        preferredDisplayID = try values.decodeIfPresent(UInt32.self, forKey: .preferredDisplayID)
        visibleCountPreference = try values.decodeIfPresent(Int.self, forKey: .visibleCountPreference) ?? 3
        placement = try values.decodeIfPresent(RiftPlacement.self, forKey: .placement)
        placementSource = try values.decodeIfPresent(RiftPlacementSource.self, forKey: .placementSource) ?? .legacy
        preferredDisplayUUID = try values.decodeIfPresent(String.self, forKey: .preferredDisplayUUID)
        try validate()
    }

    public func validate() throws {
        let positive = [fitWidth, fitHeight, rowPitch, lineWidth, emptyTraceLength,
                        numberFontSize, minimumHitWidth, minimumHitHeight]
        let nonnegative = [lineExtension, outerInset, firstCenterFromTop, screenPadding,
                           numberGap, leftPadding, arrivalDuration, pressDuration,
                           inwardDistance, swallowDuration, shiftDuration, returnDuration,
                           reducedMotionDuration]
        guard positive.allSatisfy({ $0.isFinite && $0 > 0 }),
              nonnegative.allSatisfy({ $0.isFinite && $0 >= 0 }),
              (1...10).contains(visibleCountPreference),
              preferredDisplayUUID.map({ UUID(uuidString: $0) != nil }) ?? true,
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

public enum RiftSide: String, Codable, Sendable { case left, right }
public enum RiftVerticalPlacement: String, Codable, Sendable { case top, middle, bottom }
public enum RiftPlacementSource: String, Codable, Sendable { case initialRecommendation, user, legacy }
public enum RiftPlacement: String, Codable, CaseIterable, Sendable {
    case leftTop, leftMiddle, leftBottom, rightTop, rightMiddle, rightBottom
    public var side: RiftSide { rawValue.hasPrefix("left") ? .left : .right }
    public var vertical: RiftVerticalPlacement {
        if rawValue.hasSuffix("Top") { return .top }
        if rawValue.hasSuffix("Bottom") { return .bottom }
        return .middle
    }
    public var title: String {
        switch self { case .leftTop: return "左上"; case .leftMiddle: return "左中"; case .leftBottom: return "左下"
        case .rightTop: return "右上"; case .rightMiddle: return "右中"; case .rightBottom: return "右下" }
    }
}
