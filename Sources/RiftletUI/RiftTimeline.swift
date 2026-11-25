import AppKit
import RiftletCore

/// An unflipped document has its newest end at y=0. AppKit applies the device's
/// scrolling preference, precise deltas and momentum before the clip view moves.
@MainActor
final class RiftTimelineScrollView: NSScrollView {
    var didScroll: (() -> Void)?
    private var sizing = false
    private(set) var maximumOffset: CGFloat = 0
    var offset: CGFloat { max(0, min(maximumOffset, contentView.bounds.minY)) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        scrollerStyle = .overlay
        hasVerticalScroller = true
        autohidesScrollers = true
        hasHorizontalScroller = false
        documentView = NSView(frame: .zero)
        setAccessibilityHidden(true)
    }
    required init?(coder: NSCoder) { nil }
    // Row input islands and the capture key forward their original NSEvents.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(size: CGSize, maximum: CGFloat, line: CGFloat) {
        guard let documentView else { return }
        let visible = CGSize(width: max(1, ceil(size.width)), height: max(1, ceil(size.height)))
        let maximum = max(0, ceil(maximum))
        guard frame.size != visible || maximumOffset != maximum || verticalLineScroll != line else { return }
        let previous = offset
        sizing = true
        maximumOffset = maximum
        setFrameSize(visible)
        tile()
        documentView.setFrameSize(CGSize(width: contentSize.width, height: contentSize.height + maximum))
        verticalLineScroll = line
        move(to: previous)
        sizing = false
    }

    func move(to y: CGFloat) {
        let next = min(maximumOffset, max(0, y))
        guard contentView.bounds.minY != next else { return }
        contentView.scroll(to: CGPoint(x: 0, y: next))
        reflectScrolledClipView(contentView)
    }

    private var lastReportedOffset: CGFloat = 0
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        guard !sizing, lastReportedOffset != offset else { return }
        lastReportedOffset = offset
        didScroll?()
    }
}

struct RiftTimelineSnapshot {
    let records: [AssetRecord]
    let byID: [UUID: AssetRecord]
    let ranks: [UUID: Int]
    let oldestPageSequence: Int64?
    let hasOlder: Bool

    init(active: [AssetRecord], page: [AssetRecord], hasOlder: Bool) {
        var byID = Dictionary(page.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in active where record.visibility == .visible || byID[record.id] != nil {
            byID[record.id] = record
        }
        byID = byID.filter { $0.value.status != .missing }
        self.byID = byID
        records = byID.values.sorted { $0.sequence > $1.sequence }
        ranks = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.id, $0.offset) })
        oldestPageSequence = page.map(\.sequence).min()
        self.hasOlder = hasOlder
    }
}

/// The terminal arrangement keeps its existing two-column tray and capture key.
/// A small native scroll opens the unused slots between those same asset IDs.
/// Beyond that first row every position is computed directly from capture rank.
struct RiftTimelineViewport {
    let clip: CGRect
    let pitch: CGFloat
    let columns: Int
    let rowCount: Int
    let latest: RiftLayoutResult
    private let firstSlot: CGRect
    private let secondColumnX: CGFloat
    let maximumOffset: CGFloat

    init(latest: RiftLayoutResult, full: RiftLayoutResult, configuration: RiftConfiguration,
         count: Int, hasOlder: Bool, screenFrame: CGRect) {
        self.latest = latest
        if configuration.desktopForm == .tray {
            columns = 2
            rowCount = 2
            let surface = full.surfaceFrame.isEmpty ? latest.surfaceFrame : full.surfaceFrame
            let unit = surface.width / 246
            let verticalUnit = min(unit, screenFrame.height / 212)
            pitch = max(1, 97 * verticalUnit)
            clip = CGRect(x: surface.minX, y: surface.minY, width: surface.width,
                          height: min(screenFrame.height, 212 * verticalUnit))
            firstSlot = CGRect(x: clip.minX + 7 * unit, y: clip.minY + 18 * verticalUnit,
                               width: max(1, clip.width / 2 - 9.5 * unit), height: max(1, 80 * verticalUnit))
            secondColumnX = clip.midX + 2.5 * unit
        } else {
            columns = 1
            rowCount = max(1, latest.capacity)
            pitch = max(1, configuration.desktopForm == .windChime
                ? RiftWindChimeLayout.rowPitch(configuration: configuration)
                : max(configuration.rowPitch, max(configuration.fitHeight, configuration.minimumHitHeight) + 4))
            let top = full.rows.first?.frame.midY ?? (latest.cameraAnchor.y - 94)
            let bottom = top - CGFloat(rowCount - 1) * pitch
            firstSlot = CGRect(x: 0, y: bottom - pitch / 2, width: 1, height: pitch)
            secondColumnX = 0
            clip = CGRect(x: screenFrame.minX, y: firstSlot.minY, width: screenFrame.width,
                          height: pitch * CGFloat(rowCount)).intersection(screenFrame)
        }
        let rows = (count + columns - 1) / columns
        let hasOffscreen = count > latest.rows.count || hasOlder
        maximumOffset = hasOffscreen ? pitch * CGFloat(1 + max(0, rows - rowCount)) : 0
    }

    func row(forRank rank: Int) -> Int { rank / columns }

    func layout(snapshot: RiftTimelineSnapshot, offset: CGFloat,
                template: (AssetRecord) -> RiftRowLayout?) -> RiftLayoutResult {
        guard offset > 0, !snapshot.records.isEmpty else { return latest }
        let progress = min(1, offset / pitch)
        let documentY = max(0, offset - pitch)
        let firstRow = max(0, Int(floor(documentY / pitch)) - 1)
        let lastRow = firstRow + rowCount + 3
        let lower = min(snapshot.records.count, firstRow * columns)
        let upper = min(snapshot.records.count, (lastRow + 1) * columns)
        let terminal = Dictionary(uniqueKeysWithValues: latest.rows.map { ($0.assetID, $0) })
        var ranks = Set(lower..<upper)
        if progress < 1 { ranks.formUnion(terminal.keys.compactMap { snapshot.ranks[$0] }) }
        var rows: [RiftRowLayout] = []
        var visible = clip
        if columns == 2, !latest.surfaceFrame.isEmpty {
            visible.size.height = latest.surfaceFrame.height + (clip.height - latest.surfaceFrame.height) * progress
        }
        for rank in ranks.sorted(by: >) {
            let record = snapshot.records[rank]
            guard var row = terminal[record.id] ?? template(record) else { continue }
            let original = row.frame
            let y = firstSlot.midY + CGFloat(self.row(forRank: rank)) * pitch - documentY - row.frame.height / 2
            let x = columns == 1 ? original.minX : (rank.isMultiple(of: 2) ? secondColumnX : firstSlot.minX)
            let base = CGPoint(x: x, y: y)
            var origin = base
            if progress < 1 {
                if let initial = terminal[record.id] {
                    // A long-archived gap above an active row must not fling it
                    // across thousands of points in the first scroll pixel.
                    let boundedY = min(clip.maxY + pitch, max(clip.minY - pitch, y))
                    origin.x = initial.frame.minX + (x - initial.frame.minX) * progress
                    origin.y = initial.frame.minY + (boundedY - initial.frame.minY) * progress
                } else {
                    origin.y += max(0, clip.maxY + 4 - y) * (1 - progress)
                }
            }
            row = row.positioned(at: origin, ordinal: Int(clamping: record.sequence))
            if row.frame.intersects(visible) { rows.append(row) }
        }
        let clippedLine = latest.lineFrame.intersection(visible)
        var layout = RiftLayoutResult(rows: rows, lineFrame: clippedLine.isNull ? .zero : clippedLine,
                                      firstVisibleIndex: lower, capacity: rowCount * columns,
                                      totalCount: snapshot.records.count, cameraAnchor: latest.cameraAnchor)
        if columns == 2 {
            layout.surfaceFrame = visible
            if !latest.captureSlot.isEmpty {
                let capture = latest.captureSlot.offsetBy(dx: 0, dy: -offset)
                if visible.contains(capture) { layout.captureSlot = capture }
            }
        } else if !rows.isEmpty, !latest.lineFrame.isEmpty {
            let line = latest.lineFrame
            let bounds = rows.reduce(CGRect.null) { $0.union($1.frame) }.intersection(visible)
            layout = RiftLayoutResult(rows: rows,
                lineFrame: CGRect(x: line.minX, y: bounds.minY, width: line.width, height: bounds.height),
                firstVisibleIndex: lower, capacity: rowCount, totalCount: snapshot.records.count,
                cameraAnchor: latest.cameraAnchor)
        }
        return layout
    }
}

private extension RiftRowLayout {
    func positioned(at point: CGPoint, ordinal: Int) -> Self {
        RiftRowLayout(assetID: assetID, ordinal: ordinal, frame: CGRect(origin: point, size: frame.size),
                      imageFrame: imageFrame, imageClipFrame: imageClipFrame, numberFrame: numberFrame,
                      numberIsPad: numberIsPad, trayCardFrame: trayCardFrame, windChime: windChime)
    }
}
