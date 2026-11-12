import Foundation
import RiftletCapture

public enum RiftDesktopForm: String, CaseIterable, Sendable {
    case tray, windChime, microSlit

    public var title: String {
        switch self {
        case .microSlit: return "微缝"
        case .windChime: return "风铃"
        case .tray: return "截图托盘"
        }
    }

    public var isAvailable: Bool { true }
}

public enum RiftWindChimeArrangement: String, CaseIterable, Sendable {
    case aligned, staggered

    public var title: String {
        switch self {
        case .aligned: return "整齐"
        case .staggered: return "错落"
        }
    }
}

public enum RiftTrayTheme: String, CaseIterable, Sendable {
    case system, violetGlass, custom
    public var title: String {
        switch self {
        case .system: return "系统玻璃"
        case .violetGlass: return "紫蓝玻璃"
        case .custom: return "自定义玻璃"
        }
    }
}

/// Rendering consumes only the active theme. Dormant custom settings survive preset switches.
enum RiftTrayColors: Equatable {
    case system, violetGlass, custom(hue: Double, strength: Double)
}

/// In order from the desktop interior towards the dedicated default capture key.
public enum RiftTrayFavoriteSlot: Int, CaseIterable, Sendable {
    case first = 1, second, third

    func automaticMode(defaultMode: ScreenshotMode) -> ScreenshotMode? {
        let alternatives = ScreenshotMode.allCases.filter { $0 != defaultMode }
        let index = rawValue - 1
        return alternatives.indices.contains(index) ? alternatives[index] : nil
    }
}

public enum RiftTrayFavoriteChoice: Equatable, Sendable {
    case automatic, empty, mode(ScreenshotMode), unsupported
}

/// Keep values from newer presentation schemas verbatim in the configuration
/// model, including objects, until the user explicitly replaces that field.
private enum PresentationValue: Equatable, Sendable, Codable {
    case text(String), number(Decimal), flag(Bool), object([String: Self]), array([Self]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else if let b = try? c.decode(Bool.self) { self = .flag(b) }
        else if let n = try? c.decode(Decimal.self) { self = .number(n) }
        else if let a = try? c.decode([Self].self) { self = .array(a) }
        else { self = .object(try c.decode([String: Self].self)) }
    }

    func number(in range: ClosedRange<Double>) -> Double? {
        guard case .number(let raw) = self, let value = Double(NSDecimalNumber(decimal: raw).stringValue),
              range.contains(value) else { return nil }
        return value
    }

    static func number(_ value: Double, in range: ClosedRange<Double>) -> Self? {
        guard range.contains(value), let number = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return .number(number)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .flag(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}

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

    private var storedForm: PresentationValue?
    private var storedWindChimeLineInset: PresentationValue?
    private var storedWindChimeArrangement: PresentationValue?
    private var storedTrayScalePercent: PresentationValue?
    private var storedTrayHorizontalOffset: PresentationValue?
    private var storedTrayVerticalOffset: PresentationValue?
    private var storedTrayCompanionGap: PresentationValue?
    private var storedTrayFollowsSaytile: PresentationValue?
    private var storedTrayTheme: PresentationValue?
    private var storedTrayTintHue: PresentationValue?
    private var storedTrayTintStrength: PresentationValue?
    private var storedTrayOcclusion: PresentationValue?
    private var storedTrayFavorite1: PresentationValue?
    private var storedTrayFavorite2: PresentationValue?
    private var storedTrayFavorite3: PresentationValue?

    private static func favoriteKey(_ slot: RiftTrayFavoriteSlot) -> WritableKeyPath<Self, PresentationValue?> {
        switch slot {
        case .first: return \.storedTrayFavorite1
        case .second: return \.storedTrayFavorite2
        case .third: return \.storedTrayFavorite3
        }
    }

    public func trayFavorite(_ slot: RiftTrayFavoriteSlot) -> RiftTrayFavoriteChoice {
        switch self[keyPath: Self.favoriteKey(slot)] {
        case nil: return .automatic
        case .null: return .empty
        case .text(let raw): return ScreenshotMode(rawValue: raw).map(RiftTrayFavoriteChoice.mode) ?? .unsupported
        default: return .unsupported
        }
    }

    public mutating func setTrayFavorite(_ choice: RiftTrayFavoriteChoice, for slot: RiftTrayFavoriteSlot) {
        let key = Self.favoriteKey(slot)
        switch choice {
        case .automatic: self[keyPath: key] = nil
        case .empty: self[keyPath: key] = .null
        case .mode(let mode): self[keyPath: key] = .text(mode.rawValue)
        case .unsupported: break
        }
    }

    public func trayFavoriteModes(defaultMode: ScreenshotMode) -> [ScreenshotMode?] {
        RiftTrayFavoriteSlot.allCases.map { slot in
            switch trayFavorite(slot) {
            case .automatic: return slot.automaticMode(defaultMode: defaultMode)
            case .mode(let mode): return mode
            case .empty, .unsupported: return nil
            }
        }
    }

    public var desktopForm: RiftDesktopForm {
        get {
            guard case .text(let raw) = storedForm else { return .microSlit }
            // Resolve retired candidates without changing the preference on unrelated saves.
            if raw == "edgefolio" || raw == "pocket" { return .tray }
            return RiftDesktopForm(rawValue: raw) ?? .microSlit
        }
        set {
            // R1 stored only the selected form. Preserve its aligned appearance on later switches.
            if storedWindChimeArrangement == nil, newValue != desktopForm,
               desktopForm == .windChime || newValue == .windChime {
                storedWindChimeArrangement = .text(windChimeArrangement.rawValue)
            }
            storedForm = .text(newValue.rawValue)
        }
    }

    public var windChimeArrangement: RiftWindChimeArrangement {
        get {
            if storedWindChimeArrangement == nil, desktopForm == .windChime { return .aligned }
            guard case .text(let raw) = storedWindChimeArrangement else { return .staggered }
            return RiftWindChimeArrangement(rawValue: raw) ?? .staggered
        }
        set { storedWindChimeArrangement = .text(newValue.rawValue) }
    }

    /// Wind chime measures its cord from the actual display edge, independently of the slit inset.
    public var windChimeLineInset: Double {
        get { storedWindChimeLineInset?.number(in: 0...256) ?? 18 }
        set {
            if let value = PresentationValue.number(newValue, in: 0...256) { storedWindChimeLineInset = value }
        }
    }

    static let trayScaleRange: ClosedRange<Double> = 60...160
    static let trayOffsetRange: ClosedRange<Double> = -256...256
    static let trayGapRange: ClosedRange<Double> = 0...96

    public var trayFollowsSaytile: Bool {
        get {
            guard case .flag(let enabled) = storedTrayFollowsSaytile else { return true }
            return enabled
        }
        set { storedTrayFollowsSaytile = .flag(newValue) }
    }

    public var trayScalePercent: Double {
        get { storedTrayScalePercent?.number(in: Self.trayScaleRange) ?? 100 }
        set { if let value = PresentationValue.number(newValue, in: Self.trayScaleRange) { storedTrayScalePercent = value } }
    }

    public var trayHorizontalOffset: Double {
        get { storedTrayHorizontalOffset?.number(in: Self.trayOffsetRange) ?? 0 }
        set { if let value = PresentationValue.number(newValue, in: Self.trayOffsetRange) { storedTrayHorizontalOffset = value } }
    }

    public var trayVerticalOffset: Double {
        get { storedTrayVerticalOffset?.number(in: Self.trayOffsetRange) ?? 0 }
        set { if let value = PresentationValue.number(newValue, in: Self.trayOffsetRange) { storedTrayVerticalOffset = value } }
    }

    public var trayCompanionGap: Double {
        get { storedTrayCompanionGap?.number(in: Self.trayGapRange) ?? 10 }
        set { if let value = PresentationValue.number(newValue, in: Self.trayGapRange) { storedTrayCompanionGap = value } }
    }

    public var trayTheme: RiftTrayTheme {
        get {
            guard case .text(let raw) = storedTrayTheme else { return .system }
            return RiftTrayTheme(rawValue: raw) ?? .system
        }
        set { storedTrayTheme = .text(newValue.rawValue) }
    }

    public var trayTintHue: Double {
        get { storedTrayTintHue?.number(in: 0...360) ?? 255 }
        set { if let value = PresentationValue.number(newValue, in: 0...360) { storedTrayTintHue = value } }
    }

    public var trayTintStrength: Double {
        get { storedTrayTintStrength?.number(in: 0...1) ?? 0.65 }
        set { if let value = PresentationValue.number(newValue, in: 0...1) { storedTrayTintStrength = value } }
    }

    var trayColors: RiftTrayColors {
        switch trayTheme {
        case .system: return .system
        case .violetGlass: return .violetGlass
        case .custom: return .custom(hue: trayTintHue, strength: trayTintStrength)
        }
    }

    public var trayOcclusion: Double {
        get {
            storedTrayOcclusion?.number(in: 0...0.9) ?? 0
        }
        set {
            if let value = PresentationValue.number(newValue, in: 0...0.9) { storedTrayOcclusion = value }
        }
    }

    public init() {}


    private enum CodingKeys: String, CodingKey { case fitWidth, fitHeight, hiddenFraction, rowPitch, lineWidth, lineExtension, emptyTraceLength, outerInset, firstCenterFromTop, screenPadding, numberFontSize, numberGap, leftPadding, minimumHitWidth, minimumHitHeight, arrivalDuration, pressDuration, inwardDistance, swallowDuration, shiftDuration, returnDuration, reducedMotionDuration, preferredDisplayID, visibleCountPreference, placement, placementSource, preferredDisplayUUID
        case storedWindChimeArrangement = "windChimeArrangement", storedWindChimeLineInset = "windChimeLineInset"
        case storedForm = "desktopForm", storedTrayTheme = "trayTheme", storedTrayOcclusion = "trayOcclusion"
        case storedTrayScalePercent = "trayScalePercent"
        case storedTrayHorizontalOffset = "trayHorizontalOffset"
        case storedTrayVerticalOffset = "trayVerticalOffset"
        case storedTrayCompanionGap = "trayCompanionGap"
        case storedTrayFollowsSaytile = "trayFollowsSaytile"
        case storedTrayTintHue = "trayTintHue", storedTrayTintStrength = "trayTintStrength"
        case storedTrayFavorite1 = "trayFavorite1", storedTrayFavorite2 = "trayFavorite2", storedTrayFavorite3 = "trayFavorite3"
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.storedForm) { storedForm = try values.decode(PresentationValue.self, forKey: .storedForm) }
        if values.contains(.storedWindChimeLineInset) {
            storedWindChimeLineInset = try values.decode(PresentationValue.self, forKey: .storedWindChimeLineInset)
        }
        if values.contains(.storedWindChimeArrangement) {
            storedWindChimeArrangement = try values.decode(PresentationValue.self, forKey: .storedWindChimeArrangement)
        }
        if values.contains(.storedTrayScalePercent) { storedTrayScalePercent = try values.decode(PresentationValue.self, forKey: .storedTrayScalePercent) }
        if values.contains(.storedTrayHorizontalOffset) { storedTrayHorizontalOffset = try values.decode(PresentationValue.self, forKey: .storedTrayHorizontalOffset) }
        if values.contains(.storedTrayVerticalOffset) { storedTrayVerticalOffset = try values.decode(PresentationValue.self, forKey: .storedTrayVerticalOffset) }
        if values.contains(.storedTrayCompanionGap) { storedTrayCompanionGap = try values.decode(PresentationValue.self, forKey: .storedTrayCompanionGap) }
        if values.contains(.storedTrayFollowsSaytile) { storedTrayFollowsSaytile = try values.decode(PresentationValue.self, forKey: .storedTrayFollowsSaytile) }
        if values.contains(.storedTrayTheme) { storedTrayTheme = try values.decode(PresentationValue.self, forKey: .storedTrayTheme) }
        if values.contains(.storedTrayTintHue) { storedTrayTintHue = try values.decode(PresentationValue.self, forKey: .storedTrayTintHue) }
        if values.contains(.storedTrayTintStrength) { storedTrayTintStrength = try values.decode(PresentationValue.self, forKey: .storedTrayTintStrength) }
        if values.contains(.storedTrayOcclusion) { storedTrayOcclusion = try values.decode(PresentationValue.self, forKey: .storedTrayOcclusion) }
        if values.contains(.storedTrayFavorite1) { storedTrayFavorite1 = try values.decode(PresentationValue.self, forKey: .storedTrayFavorite1) }
        if values.contains(.storedTrayFavorite2) { storedTrayFavorite2 = try values.decode(PresentationValue.self, forKey: .storedTrayFavorite2) }
        if values.contains(.storedTrayFavorite3) { storedTrayFavorite3 = try values.decode(PresentationValue.self, forKey: .storedTrayFavorite3) }
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
