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

    /// Selection eligibility only; rejecting padding does not forward an event
    /// through this row's rectangular native window to another application.
    func containsSelectionPoint(_ localPoint: CGPoint) -> Bool {
        imageClipFrame.contains(localPoint) || numberFrame.contains(localPoint)
    }
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
    private struct RowMetrics {
        let record: AssetRecord
        let ordinal: Int
        let fitted: CGSize
        let exposed: Double
        let numberWidth: Double
        let width: Double
        let height: Double
    }

    private static func metrics(for record: AssetRecord, ordinal: Int,
                                configuration c: RiftConfiguration) -> RowMetrics {
        let fitted = fit(pixelWidth: record.image.pixelWidth,
                         pixelHeight: record.image.pixelHeight, configuration: c)
        let exposed = Double(fitted.width) * (1 - c.hiddenFraction)
        let numberWidth = Double(String(ordinal).count) * c.numberFontSize * 0.65
        return RowMetrics(record: record, ordinal: ordinal, fitted: fitted, exposed: exposed,
                          numberWidth: numberWidth,
                          width: max(c.minimumHitWidth, exposed + c.numberGap + numberWidth + c.leftPadding),
                          height: max(c.minimumHitHeight, Double(fitted.height)))
    }

    public static func fit(pixelWidth: Int, pixelHeight: Int, configuration c: RiftConfiguration) -> CGSize {
        guard pixelWidth > 0, pixelHeight > 0 else { return .zero }
        let ratio = min(c.fitWidth / Double(pixelWidth), c.fitHeight / Double(pixelHeight))
        return CGSize(width: Double(pixelWidth) * ratio, height: Double(pixelHeight) * ratio)
    }

    public static func make(records: [AssetRecord], visibleFrame: CGRect,
                            configuration c: RiftConfiguration, firstVisibleIndex: Int = 0) -> RiftLayoutResult {
        let active = records.filter { $0.visibility == .visible }
        let height = max(c.fitHeight, c.minimumHitHeight)
        // Preserve a genuine empty strip between row windows even for experimental dimensions.
        let pitch = max(c.rowPitch, height + 4)
        let available = max(0, Double(visibleFrame.height) - 2 * c.screenPadding)
        let capacity = available >= height ? max(1, Int(floor((available - height) / pitch)) + 1) : 0
        let index = min(max(0, firstVisibleIndex), max(0, active.count - capacity))
        let count = min(capacity, max(0, active.count - index))
        let fittedRows = (0..<count).map { offset in
            metrics(for: active[index + offset], ordinal: index + offset + 1, configuration: c)
        }
        // Experimental insets must not push otherwise fitting input windows off a
        // narrow/rotated display. All visible rows still share one fixed rift edge.
        let minimumEdgeX = min(Double(visibleFrame.maxX),
                               Double(visibleFrame.minX) + (fittedRows.map(\.width).max() ?? 0))
        let edgeX = max(minimumEdgeX, Double(visibleFrame.maxX) - c.outerInset)
        let topLimit = Double(visibleFrame.maxY) - c.screenPadding - height / 2
        let bottomLimit = Double(visibleFrame.minY) + c.screenPadding + height / 2
        let preferred = Double(visibleFrame.maxY) - c.firstCenterFromTop
        let needed = bottomLimit + Double(max(0, count - 1)) * pitch
        let firstCenter = min(topLimit, max(preferred, needed))
        var rows: [RiftRowLayout] = []
        for (offset, item) in fittedRows.enumerated() {
            let ordinal = item.ordinal
            let record = item.record
            let fitted = item.fitted
            let exposed = item.exposed
            let numberWidth = item.numberWidth
            let width = item.width
            let rowHeight = item.height
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
            // Empty visible queues have no decorative remnant, regardless of
            // any legacy emptyTraceLength stored by an earlier build.
            rawLine = .zero
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


/// Main-thread interaction facts used to protect automatic archiving. No upload
/// or visibility authority is inferred from these transient UI observations.
public struct RiftInteractionSnapshot: Equatable, Sendable {
    public let revision: UInt64
    public let protectedAssetIDs: Set<UUID>
    public let isHolding: Bool
    public let isSelecting: Bool
    public let isTransitioning: Bool
    public var blocksAutomaticArchive: Bool {
        !protectedAssetIDs.isEmpty || isHolding || isSelecting || isTransitioning
    }
}

/// Value semantics allow the asynchronous selection boundary and animation /
/// hover protection to be tested without pretending to exercise a physical GUI.
struct RiftInteractionState: Sendable {
    private(set) var revision: UInt64 = 0
    private(set) var heldID: UUID?
    private var hoveredIDs: Set<UUID> = []
    private var selectedIDs: Set<UUID> = []
    private var menuIDs: Set<UUID> = []
    private var animationTokens: Set<UUID> = []
    private var layoutTransition = false

    var snapshot: RiftInteractionSnapshot {
        RiftInteractionSnapshot(revision: revision,
            protectedAssetIDs: hoveredIDs.union(selectedIDs).union(menuIDs),
            isHolding: heldID != nil, isSelecting: !selectedIDs.isEmpty,
            isTransitioning: layoutTransition || !animationTokens.isEmpty)
    }

    mutating func setHovered(_ ids: Set<UUID>) {
        guard hoveredIDs != ids else { return }
        hoveredIDs = ids; revision &+= 1
    }

    mutating func beginSelection(_ id: UUID, held: Bool) {
        selectedIDs.insert(id)
        if held { heldID = id }
        revision &+= 1
    }

    mutating func releasePointer(accepted: Bool) {
        guard let id = heldID else { return }
        heldID = nil
        if !accepted { selectedIDs.remove(id) }
        revision &+= 1
    }

    mutating func finishSelection(_ id: UUID) {
        guard selectedIDs.remove(id) != nil else { return }
        revision &+= 1
    }

    mutating func setMenu(_ id: UUID, open: Bool) {
        let old = menuIDs
        if open { menuIDs.insert(id) } else { menuIDs.remove(id) }
        if menuIDs != old { revision &+= 1 }
    }

    mutating func setTransitioning(_ value: Bool) {
        guard value != layoutTransition else { return }
        layoutTransition = value; revision &+= 1
    }

    mutating func beginAnimation(_ token: UUID) {
        if animationTokens.insert(token).inserted { revision &+= 1 }
    }

    mutating func endAnimation(_ token: UUID) {
        if animationTokens.remove(token) != nil { revision &+= 1 }
    }

    /// Hide/reflow cancels only a pointer still down. A released selection may
    /// already be awaiting durable prepare, and must keep its protection.
    mutating func resetPresentation() {
        if let heldID { selectedIDs.remove(heldID) }
        heldID = nil; hoveredIDs.removeAll(); menuIDs.removeAll()
        animationTokens.removeAll(); layoutTransition = false; revision &+= 1
    }

    mutating func close() {
        resetPresentation(); selectedIDs.removeAll(); revision &+= 1
    }
}
