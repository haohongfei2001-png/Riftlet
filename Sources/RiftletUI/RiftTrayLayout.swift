import Foundation
import RiftletCore

/// A viewport over the existing queue. Capture occupies the position immediately
/// after the last asset and has no asset identity of its own.
enum RiftTrayLayout {
    static func make(records: [AssetRecord], visibleFrame: CGRect,
                     configuration c: RiftConfiguration, firstVisibleIndex: Int,
                     backingScale: Double, captureEnabled: Bool, expanded: Bool,
                     arrivalIDs: [UUID] = []) -> RiftLayoutResult {
        let active = records.filter { $0.visibility == .visible }
        let menuOpen = expanded && captureEnabled
        let capacity = min(menuOpen ? 2 : 4, c.visibleCountPreference)
        let first = min(max(firstVisibleIndex, 0), max(0, active.count - min(capacity, captureEnabled ? 3 : 4)))
        var result = RiftLayoutResult(rows: [], lineFrame: .zero, firstVisibleIndex: first,
                                      capacity: capacity, totalCount: active.count)
        guard visibleFrame.width > 0, visibleFrame.height > 0, captureEnabled || !active.isEmpty else { return result }

        // Allow enough room for four compact controls on a small display.
        let width = min(visibleFrame.width, max(128, visibleFrame.width / 8))
        let height = min(visibleFrame.height, width * 0.84)
        let inset = min(c.outerInset, max(0, visibleFrame.width - width))
        let x = c.placement?.side == .left ? visibleFrame.minX + inset : visibleFrame.maxX - inset - width
        let padY = min(c.screenPadding, max(0, visibleFrame.height - height))
        let y: CGFloat
        switch c.placement?.vertical {
        case .top: y = visibleFrame.maxY - padY - height
        case .bottom: y = visibleFrame.minY + padY
        case .middle, nil: y = visibleFrame.midY - height / 2
        }
        let px = backingScale.isFinite ? max(1, backingScale) : 1
        func pixel(_ v: CGFloat) -> CGFloat { (v * px).rounded() / px }
        let surface = CGRect(x: min(visibleFrame.maxX-width,max(visibleFrame.minX,pixel(x))),
                             y: min(visibleFrame.maxY-height,max(visibleFrame.minY,pixel(y))), width: width, height: height)
        let pad = min(8, width * 0.035, height * 0.05)
        let gap = pad
        let inner = surface.insetBy(dx: pad, dy: pad)
        let cellWidth = (inner.width - gap) / 2
        let cellHeight = (inner.height - gap) / 2
        // Presentation priority exists only while the capture menu is open.
        // Keep true queue indices for labels, AX identity and hit-test routing.
        var items: [Int] = []
        if menuOpen {
            for id in arrivalIDs {
                guard items.count < capacity else { break }
                if let i = active.firstIndex(where: { $0.id == id }), !items.contains(i) {
                    items.append(i)
                }
            }
        }
        for i in first..<active.count {
            guard items.count < capacity else { break }
            if !items.contains(i) { items.append(i) }
        }
        let showButton = captureEnabled && !menuOpen && first + items.count == active.count && items.count < 4
        let useTop = menuOpen || items.count + (showButton ? 1 : 0) > 2
        func cell(_ index: Int) -> CGRect {
            CGRect(x: inner.minX + CGFloat(index % 2) * (cellWidth + gap),
                   y: index < 2 && useTop ? inner.maxY - cellHeight : inner.minY,
                   width: cellWidth, height: cellHeight)
        }
        let rows = items.enumerated().map { index, queueIndex -> RiftRowLayout in
            let record = active[queueIndex]
            let slot = cell(index)
            let w = CGFloat(record.image.pixelWidth), h = CGFloat(record.image.pixelHeight)
            let ratio = w > 0 && h > 0 ? max(0, min(1 / px, slot.width / w, slot.height / h)) : 0
            let size = CGSize(width: w * ratio, height: h * ratio)
            let image = CGRect(x: (slot.width - size.width) / 2, y: (slot.height - size.height) / 2,
                               width: size.width, height: size.height)
            let obscured = image.width * c.trayOcclusion
            let clip = CGRect(x: image.minX + (c.placement?.side == .left ? obscured : 0), y: image.minY,
                              width: image.width - obscured, height: image.height)
            return RiftRowLayout(assetID: record.id, ordinal: queueIndex + 1, frame: slot,
                                 imageFrame: image, imageClipFrame: clip, numberFrame: .zero)
        }
        result = RiftLayoutResult(rows: rows, lineFrame: .zero, firstVisibleIndex: first,
                                  capacity: capacity, totalCount: active.count + (captureEnabled && !showButton && !menuOpen ? 1 : 0))
        result.surfaceFrame = surface
        if showButton { result.captureSlot = cell(items.count) }
        if menuOpen {
            result.captureMenuFrame = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: cellHeight)
        }
        return result
    }
}
