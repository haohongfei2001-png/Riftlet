import Foundation
import RiftletCore

/// Shared page metrics for the two PR #52 presentations. All geometry is in
/// screen points except for the image and ordinal rectangles within each page.
enum RiftFolioLayout {
    static func make(records: [AssetRecord], visibleFrame screen: CGRect,
                     configuration c: RiftConfiguration, firstVisibleIndex: Int = 0,
                     backingScale: CGFloat = 1, expanded: Bool = false, anchoredID: UUID? = nil) -> RiftLayoutResult {
        let assets = records.filter { $0.visibility == .visible }
        let side = c.placement?.side ?? .right
        let margin = min(c.screenPadding, max(0, screen.height / 8))
        let availableHeight = screen.height - 2 * margin
        let inset = min(c.outerInset, max(0, screen.width / 8))
        let padding: CGFloat = 5
        let numberWidth = max(18, ceil(c.numberFontSize * 0.7 * CGFloat(max(2, String(assets.count).count))))
        let pageWidth = max(c.minimumHitWidth, c.fitWidth + 2 * padding + numberWidth + c.numberGap)
        let pageHeight = max(c.minimumHitHeight, c.numberFontSize + 2 * padding, c.fitHeight + 2 * padding)
        let pitch = max(c.rowPitch, pageHeight + 6)
        let maximumCount = min(c.visibleCountPreference, 10)
        // Both pocket states have the same capacity. Hover never removes a UUID.
        let capacity: Int
        if pageWidth + inset <= screen.width && pageHeight <= availableHeight {
            capacity = 1 + Int(min(CGFloat(maximumCount - 1), floor((availableHeight - pageHeight) / pitch)))
        } else {
            capacity = 0
        }
        let last = RiftLayout.lastPageStart(totalCount: assets.count, capacity: capacity)
        let start = assets.count <= capacity ? 0 : firstVisibleIndex >= assets.count ? last : max(0, firstVisibleIndex)
        let count = min(capacity, assets.count - start)
        let collapse = c.desktopForm == .pocket && !expanded
        // Adjustable overlap leaves a distinct exposed strip for every card.
        let compactStep = max(7, min(16, pageHeight * 0.16 * (1 - c.hiddenFraction)))
        let stepY = collapse ? compactStep : pitch
        let lastOffset = CGFloat(max(0, count - 1))
        let compactX = min(compactStep, min(14, max(0, screen.width - inset - pageWidth)) / max(1, lastOffset))
        let span = pageHeight + lastOffset * stepY
        func groupTop(for span: CGFloat) -> CGFloat {
            let highest = screen.maxY - margin
            let lowest = screen.minY + margin + span
            switch c.placement?.vertical {
            case .top: return highest
            case .bottom: return lowest
            case .middle: return screen.midY + span / 2
            case nil: return min(highest, max(lowest, screen.maxY - c.firstCenterFromTop + pageHeight / 2))
            }
        }
        let compactSpan = pageHeight + lastOffset * compactStep
        // Leave space on either side of the pocket for an approached page to
        // remain stationary as every other page opens around it.
        let headroom = min(lastOffset * (pitch - compactStep), max(0, (availableHeight - compactSpan) / 2))
        let compactTop = min(screen.maxY - margin - headroom,
                             max(screen.minY + margin + compactSpan + headroom, groupTop(for: compactSpan)))
        let top = collapse ? compactTop : groupTop(for: span)
        let scale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        func align(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let edge = side == .left ? screen.minX + inset : screen.maxX - inset
        var result = RiftLayoutResult(rows: [], lineFrame: .zero, firstVisibleIndex: start,
                                      capacity: capacity, totalCount: assets.count)
        result.cameraAnchor = CGPoint(x: edge + (side == .left ? 18 : -18),
                                     y: min(screen.maxY - 22, max(screen.minY + 22, top + 27)))
        guard count > 0 else { return result }
        let visible = assets[start..<(start + count)]
        let anchor = c.desktopForm == .pocket && expanded
            ? visible.firstIndex(where: { $0.id == anchoredID }).map { $0 - start } : nil
        let anchorOffset = CGFloat(anchor ?? 0)
        let anchorTop = compactTop - anchorOffset * compactStep
        let trailing = lastOffset - anchorOffset
        // Preserve the approached page at the exact same screen coordinates. Near
        // a screen boundary the constrained side fans out as far as fits; the
        // unconstrained side can still open completely. No anchor UUID is remapped.
        let beforePitch = min(pitch, (screen.maxY - margin - anchorTop) / max(1, anchorOffset))
        let afterPitch = min(pitch, (anchorTop - pageHeight - screen.minY - margin) / max(1, trailing))
        let rows = (0..<count).map { offset -> RiftRowLayout in
            let record = assets[start + offset]
            var delta = collapse ? CGFloat(offset) * compactX : 0
            var rowTop = top - CGFloat(offset) * stepY
            if let anchor {
                let directedOffset = CGFloat(offset - anchor)
                let availablePitch = offset < anchor ? beforePitch : afterPitch
                rowTop = anchorTop - directedOffset * availablePitch
                // Retain the exposed side strips of any still overlapping pages.
                delta = availablePitch < pageHeight ? CGFloat(offset) * compactX : anchorOffset * compactX
            }
            let frame = CGRect(x: align(side == .left ? edge + delta : edge - pageWidth - delta),
                               y: align(rowTop - pageHeight),
                               width: pageWidth, height: pageHeight)
            let pWidth = CGFloat(max(1, record.image.pixelWidth)), pHeight = CGFloat(max(1, record.image.pixelHeight))
            let ratio = min(1 / scale, c.fitWidth / pWidth, c.fitHeight / pHeight)
            let imageSize = CGSize(width: pWidth * ratio, height: pHeight * ratio)
            let imageLeft = side == .left ? padding : pageWidth - padding - c.fitWidth
            let image = CGRect(x: imageLeft + (c.fitWidth - imageSize.width) / 2,
                               y: (pageHeight - imageSize.height) / 2,
                               width: imageSize.width, height: imageSize.height)
            let number = CGRect(x: side == .left ? pageWidth - padding - numberWidth : padding,
                                y: (pageHeight - c.numberFontSize - 4) / 2,
                                width: numberWidth, height: c.numberFontSize + 4)
            return RiftRowLayout(assetID: record.id, ordinal: start + offset + 1, frame: frame,
                                 imageFrame: image, imageClipFrame: image, numberFrame: number)
        }
        let railWidth = min(22, pageWidth)
        let rail = CGRect(x: side == .left ? edge - 5 : edge - railWidth + 5,
                          y: rows[count - 1].frame.minY - 7, width: railWidth,
                          height: rows[0].frame.maxY - rows[count - 1].frame.minY + 14)
        result = RiftLayoutResult(rows: rows, lineFrame: .zero, firstVisibleIndex: start,
                                  capacity: capacity, totalCount: assets.count, cameraAnchor: result.cameraAnchor)
        result.surfaceFrame = rail.intersection(screen)
        return result
    }
}
