import Foundation
import RiftletCore

public struct RiftRowLayout: Equatable, Sendable {
    public let assetID: UUID
    public let ordinal: Int
    /// Screen coordinates, with no input window at the outer inset or between rows.
    public let frame: CGRect
    /// Full aspect-fitted image; its right edge lies beyond the clipping boundary.
    public let imageFrame: CGRect
    public let imageClipFrame: CGRect
    public let numberFrame: CGRect
}

public struct RiftLayoutResult: Equatable, Sendable {
    public let rows: [RiftRowLayout]
    public let lineFrame: CGRect
    public let firstVisibleIndex: Int
    public let capacity: Int
    public let totalCount: Int
    public var hasEarlier: Bool { firstVisibleIndex > 0 }
    public var hasLater: Bool { firstVisibleIndex + rows.count < totalCount }
}

/// Deterministic geometry, independent of NSWindow and of upload semantics.
public enum RiftLayout {
    public static func fit(pixelWidth: Int, pixelHeight: Int, configuration c: RiftConfiguration) -> CGSize {
        guard pixelWidth > 0, pixelHeight > 0 else { return .zero }
        let ratio = min(c.fitWidth / Double(pixelWidth), c.fitHeight / Double(pixelHeight))
        return CGSize(width: Double(pixelWidth) * ratio, height: Double(pixelHeight) * ratio)
    }

    public static func make(records: [AssetRecord], visibleFrame: CGRect,
                            configuration c: RiftConfiguration, firstVisibleIndex: Int = 0) -> RiftLayoutResult {
        let active = records.filter { $0.status != .used }
        let height = max(c.fitHeight, c.minimumHitHeight)
        // Preserve a genuine empty strip between row windows even for experimental dimensions.
        let pitch = max(c.rowPitch, height + 4)
        let available = max(0, Double(visibleFrame.height) - 2 * c.screenPadding)
        let capacity = available >= height ? max(1, Int(floor((available - height) / pitch)) + 1) : 0
        let index = min(max(0, firstVisibleIndex), max(0, active.count - capacity))
        let count = min(capacity, max(0, active.count - index))
        let edgeX = max(Double(visibleFrame.minX), Double(visibleFrame.maxX) - c.outerInset)
        let topLimit = Double(visibleFrame.maxY) - c.screenPadding - height / 2
        let bottomLimit = Double(visibleFrame.minY) + c.screenPadding + height / 2
        let preferred = Double(visibleFrame.maxY) - c.firstCenterFromTop
        let needed = bottomLimit + Double(max(0, count - 1)) * pitch
        let firstCenter = min(topLimit, max(preferred, needed))
        var rows: [RiftRowLayout] = []
        for offset in 0..<count {
            let ordinal = index + offset + 1
            let record = active[index + offset]
            let fitted = fit(pixelWidth: record.image.pixelWidth,
                             pixelHeight: record.image.pixelHeight, configuration: c)
            let exposed = Double(fitted.width) * (1 - c.hiddenFraction)
            let numberWidth = Double(String(ordinal).count) * c.numberFontSize * 0.65
            let width = max(c.minimumHitWidth, exposed + c.numberGap + numberWidth + c.leftPadding)
            let rowHeight = max(c.minimumHitHeight, Double(fitted.height))
            let center = firstCenter - Double(offset) * pitch
            let imageX = width - exposed
            let imageY = (rowHeight - Double(fitted.height)) / 2
            rows.append(RiftRowLayout(
                assetID: record.id, ordinal: ordinal,
                frame: CGRect(x: edgeX - width, y: center - rowHeight / 2, width: width, height: rowHeight),
                imageFrame: CGRect(x: imageX, y: imageY, width: fitted.width, height: fitted.height),
                imageClipFrame: CGRect(x: imageX, y: imageY, width: exposed, height: fitted.height),
                numberFrame: CGRect(x: imageX - c.numberGap - numberWidth,
                                    y: rowHeight / 2 - c.numberFontSize / 2 - 1,
                                    width: numberWidth, height: c.numberFontSize + 2)))
        }
        let rawLine: CGRect
        if let first = rows.first, let last = rows.last {
            let top = Double(first.frame.maxY) + c.lineExtension
            let bottom = Double(last.frame.minY) - c.lineExtension
            rawLine = CGRect(x: edgeX - c.lineWidth / 2, y: bottom, width: c.lineWidth, height: top - bottom)
        } else {
            rawLine = CGRect(x: edgeX - c.lineWidth / 2,
                             y: min(topLimit, max(bottomLimit, preferred)) - c.emptyTraceLength / 2,
                             width: c.lineWidth, height: c.emptyTraceLength)
        }
        let line = rawLine.intersection(visibleFrame)
        return RiftLayoutResult(rows: rows, lineFrame: line.isNull ? .zero : line,
                                firstVisibleIndex: index, capacity: capacity, totalCount: active.count)
    }
}

/// Shared across all row windows: a double-click must not select a replacement row.
public struct PointerSelectionGate: Sendable {
    private var heldID: UUID?
    private var heldPoint: CGPoint?
    private var heldTime: TimeInterval?
    private var previousPoint: CGPoint?
    private var previousTime: TimeInterval?
    public var isHolding: Bool { heldID != nil }
    public init() {}

    public mutating func begin(assetID: UUID, screenPoint: CGPoint, timestamp: TimeInterval,
                               clickCount: Int, doubleClickInterval: TimeInterval,
                               acceptsSelection: Bool) -> Bool {
        guard !isHolding, acceptsSelection, clickCount == 1 else { return false }
        if let previousTime, let previousPoint,
           timestamp >= previousTime, timestamp - previousTime <= doubleClickInterval,
           hypot(screenPoint.x - previousPoint.x, screenPoint.y - previousPoint.y) <= 4 {
            return false
        }
        heldID = assetID; heldPoint = screenPoint; heldTime = timestamp
        return true
    }

    public mutating func end(inside: Bool) -> UUID? {
        defer { heldID = nil; heldPoint = nil; heldTime = nil }
        guard inside, let heldID else { return nil }
        previousPoint = heldPoint; previousTime = heldTime
        return heldID
    }

    public mutating func cancel() { heldID = nil; heldPoint = nil; heldTime = nil }
}
