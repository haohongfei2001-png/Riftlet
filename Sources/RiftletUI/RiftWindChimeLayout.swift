import CoreGraphics
import Foundation
import RiftletCore

struct RiftWindChimeCard: Equatable, Sendable {
    let cardFrame: CGRect
    let degrees: CGFloat
    /// The physical edge of this display, in row-local coordinates.
    let clippingEdge: CGFloat

    var rotation: CGAffineTransform {
        CGAffineTransform(translationX: cardFrame.midX, y: cardFrame.midY)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -cardFrame.midX, y: -cardFrame.midY)
    }

    func contains(_ point: CGPoint) -> Bool {
        let radius = min(RiftWindChimeLayout.corner, cardFrame.width / 2, cardFrame.height / 2)
        let outline = CGPath(roundedRect: cardFrame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        return outline.contains(point.applying(rotation.inverted()))
    }
}

enum RiftWindChimeLayout {
    static let border: CGFloat = 1.5
    static let corner: CGFloat = 4
    static let topExtension: CGFloat = 14
    static let bottomExtension: CGFloat = 28

    static func rowPitch(configuration c: RiftConfiguration) -> CGFloat {
        max(c.rowPitch + 6, c.fitHeight + 10, c.minimumHitHeight + 4)
    }

    /// Use the immutable import sequence. Paging and removing a neighbour can
    /// change the displayed number, but never a surviving screenshot's pose.
    static func pose(ordinal: Int, left: Bool, arrangement: RiftWindChimeArrangement) -> (degrees: CGFloat, offset: CGFloat) {
        guard arrangement == .staggered else { return (0, 0) }
        let poses: [(CGFloat, CGFloat)] = [(2, 1), (-1, -2), (1, 0)]
        let (degrees, inward) = poses[(max(1, ordinal) - 1) % poses.count]
        return (left ? -degrees : degrees, inward)
    }

    static func make(records: [AssetRecord], visibleFrame: CGRect, configuration c: RiftConfiguration,
                     firstVisibleIndex: Int = 0, backingScale: CGFloat = 1, highContrast: Bool = false,
                     displayFrame: CGRect? = nil) -> RiftLayoutResult {
        // Keep the existing six anchors, pager, visible-record filter and number
        // metrics. The R2 string stops at the images, clear of camera and arrows.
        let display = displayFrame ?? visibleFrame
        let area = CGRect(x: display.minX, y: visibleFrame.minY, width: display.width, height: visibleFrame.height)
        var spacing = c
        spacing.rowPitch = rowPitch(configuration: c)
        spacing.outerInset = min(max(0, c.windChimeLineInset), max(0, area.width / 2))
        // Reserve paper, line, arrow and camera before choosing page capacity.
        // Large personal thumbnail sizes still leave every control on screen.
        let halfPaper = ceil((c.fitHeight + 2 * border + (c.fitWidth + 2 * border) * sin(2 * .pi / 180)) / 2)
        let arrowHeight: CGFloat = 24, controlGap: CGFloat = 4
        let cameraOffset = max(94, halfPaper + topExtension + controlGap + arrowHeight + controlGap + 18)
        let topReserve = cameraOffset - 94
        let bottomReserve = max(0, halfPaper + bottomExtension + controlGap + arrowHeight - 76)
        let placementArea = CGRect(x: area.minX, y: area.minY + bottomReserve, width: area.width,
                                   height: max(0, area.height - bottomReserve - topReserve))
        let baseline = RiftLayout.make(records: records, visibleFrame: placementArea, configuration: spacing,
                                       firstVisibleIndex: firstVisibleIndex, backingScale: backingScale,
                                       highContrast: highContrast)
        let left = c.placement?.side == .left
        let edge = left ? area.minX : area.maxX
        let scale = max(1, backingScale)
        let width: CGFloat = highContrast ? 1 : 1 / scale
        let distance = max(width / 2, spacing.outerInset)
        let spine = round((left ? edge + distance : edge - distance) * scale) / scale
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let rows: [RiftRowLayout] = baseline.rows.compactMap { row in
            guard let record = byID[row.assetID] else { return nil }
            let fit = min(1, c.fitWidth / CGFloat(max(1, record.image.pixelWidth)),
                             c.fitHeight / CGFloat(max(1, record.image.pixelHeight)))
            let size = CGSize(width: max(1, CGFloat(record.image.pixelWidth)) * fit,
                              height: max(1, CGFloat(record.image.pixelHeight)) * fit)
            let pose = pose(ordinal: Int(clamping: record.sequence), left: left, arrangement: c.windChimeArrangement)
            let inward = min(size.width / 2, max(-size.width / 2, pose.offset))
            let x = spine + (left ? inward : -inward)
            let pixels = CGRect(x: x - size.width / 2, y: row.frame.midY - size.height / 2,
                                width: size.width, height: size.height)
            let card = pixels.insetBy(dx: -border, dy: -border)
            let shape = RiftWindChimeCard(cardFrame: card, degrees: pose.degrees, clippingEdge: edge)
            let exposed = card.applying(shape.rotation).intersection(area)
            guard !exposed.isEmpty else { return nil }
            let label = RiftLayout.numberMetrics(ordinal: row.ordinal, exposed: exposed.width - 2 * border,
                                                 height: size.height, configuration: c)
            let number = CGRect(x: left ? exposed.maxX + c.numberGap : exposed.minX - c.numberGap - label.size.width,
                                y: row.frame.midY - label.size.height / 2, width: label.size.width, height: label.size.height)
            guard area.contains(number) else { return nil }
            let bounds = exposed.union(number).integral.intersection(area)
            func local(_ frame: CGRect) -> CGRect { frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
            return RiftRowLayout(assetID: row.assetID, ordinal: row.ordinal, frame: bounds,
                                 imageFrame: local(pixels), imageClipFrame: local(exposed),
                                 numberFrame: local(number), numberIsPad: label.pad,
                                 windChime: RiftWindChimeCard(cardFrame: local(card), degrees: pose.degrees,
                                                              clippingEdge: edge - bounds.minX))
        }
        let lineX = min(area.maxX - width, max(area.minX, floor(spine * scale) / scale))
        let line = stringFrame(rows: rows, x: lineX, width: width, within: area)
        var earlier = baseline.earlierArrowFrame
        var later = baseline.laterArrowFrame
        if !earlier.isEmpty { earlier.origin.y = max(earlier.minY, line.maxY + 4) }
        if !later.isEmpty { later.origin.y = min(later.minY, line.minY - 4 - later.height) }
        return RiftLayoutResult(rows: rows, lineFrame: line, firstVisibleIndex: baseline.firstVisibleIndex,
                                capacity: baseline.capacity, totalCount: baseline.totalCount,
                                earlierArrowFrame: earlier, laterArrowFrame: later,
                                cameraAnchor: CGPoint(x: baseline.cameraAnchor.x, y: baseline.cameraAnchor.y + topReserve))
    }

    static func stringFrame(rows: [RiftRowLayout], x: CGFloat, width: CGFloat, within area: CGRect) -> CGRect {
        let bounds = rows.reduce(CGRect.null) { $0.union($1.imageClipFrame.offsetBy(dx: $1.frame.minX, dy: $1.frame.minY)) }
        guard !bounds.isNull else { return .zero }
        return CGRect(x: x, y: bounds.minY - bottomExtension, width: width,
                      height: bounds.height + bottomExtension + topExtension).intersection(area)
    }
}
