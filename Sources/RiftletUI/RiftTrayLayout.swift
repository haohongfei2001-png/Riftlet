import Foundation
import RiftletCore

/// A menu belongs to the viewport from which its camera was opened. A later
/// capture can create an upper row even when that same UUID would have been
/// pushed out had it already existed at opening.
struct RiftTrayMenuState {
    let openingRows: [UUID]
    let displacedID: UUID?
    private(set) var receivedCapture = false
    private(set) var usesOpeningPage = true
    private(set) var priorityIDs: [UUID] = []

    init(openingLayout: RiftLayoutResult) {
        openingRows = openingLayout.rows.map(\.assetID)
        let cameraReplacesImage = !openingLayout.captureSlot.isEmpty && !openingRows.count.isMultiple(of: 2)
        displacedID = cameraReplacesImage ? openingRows.first : nil
    }

    mutating func receiveCaptures(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        receivedCapture = true
        prioritize(ids)
    }

    mutating func prioritize(_ ids: [UUID]) {
        var seen = Set<UUID>()
        priorityIDs = Array((ids + priorityIDs).filter { seen.insert($0).inserted }.prefix(2))
    }

    mutating func userPaged() {
        usesOpeningPage = false
        priorityIDs.removeAll()
    }
}

/// A viewport over the existing queue. Capture occupies the position immediately
/// after the last asset and has no asset identity of its own.
enum RiftTrayLayout {
    static func make(records: [AssetRecord], visibleFrame: CGRect,
                     configuration c: RiftConfiguration, firstVisibleIndex: Int,
                     backingScale: Double, captureEnabled: Bool, menu: RiftTrayMenuState? = nil,
                     displayFrame: CGRect? = nil) -> RiftLayoutResult {
        let active = records.filter { $0.visibility == .visible }
        let menu = captureEnabled ? menu : nil
        let menuOpen = menu != nil
        let capacity = min(menuOpen ? 2 : 4, c.visibleCountPreference)
        let first = min(max(firstVisibleIndex, 0), max(0, active.count - min(capacity, captureEnabled ? 3 : 4)))
        var result = RiftLayoutResult(rows: [], lineFrame: .zero, firstVisibleIndex: first,
                                      capacity: capacity, totalCount: active.count)
        guard visibleFrame.width > 0, visibleFrame.height > 0, captureEnabled || !active.isEmpty else { return result }

        // The target display sets the width. The 246-unit reference supplies the interior ratios.
        let px = CGFloat(backingScale.isFinite ? max(1, backingScale) : 1)
        func snap(_ points: CGFloat) -> CGFloat { (points * px).rounded() / px }
        let display = displayFrame ?? visibleFrame
        let width = min(visibleFrame.width, max(1 / px, snap(display.width / 8)))
        let unit = width / 246
        let verticalUnit = min(unit, visibleFrame.height / 212)
        // An explicitly revealed safe failure can be the sole visible row too.
        // Its existing UUID is not a new capture and never changes that latch.
        let twoRows = active.count >= 2 || (active.count == 1 && menu.map {
            $0.receivedCapture || $0.openingRows.count >= 2 || $0.priorityIDs.contains(active[0].id)
        } == true)
        let maximumHeight = min(visibleFrame.height, snap(212 * verticalUnit))
        let height = twoRows ? maximumHeight : min(maximumHeight, snap(115 * verticalUnit))
        let inset = min(c.outerInset, max(0, visibleFrame.width - width))
        let x = c.placement?.side == .left ? visibleFrame.minX + inset : visibleFrame.maxX - inset - width
        let padY = min(c.screenPadding, max(0, visibleFrame.height - maximumHeight))
        let bottom: CGFloat
        switch c.placement?.vertical {
        case .top: bottom = visibleFrame.maxY - padY - maximumHeight
        case .bottom: bottom = visibleFrame.minY + padY
        case .middle, nil:
            // In the full 941-pixel display the tray center is 56 px below
            // center. The Dock changes the usable frame; only use it to clamp.
            bottom = display.midY - maximumHeight / 2 - 56 * verticalUnit
        }
        // The compact state retains the bottom row. Opening lifts the images,
        // while scrolling a long queue never changes the outer rectangle.
        let surface = CGRect(x: min(visibleFrame.maxX-width, max(visibleFrame.minX,snap(x))),
                             y: min(visibleFrame.maxY-maximumHeight, max(visibleFrame.minY,snap(bottom))),
                             width: width, height: height)
        let innerLeft = snap(surface.minX + 7 * unit)
        let innerRight = snap(surface.maxX - 7 * unit)
        let columnEnd = snap(surface.midX - 2.5 * unit)
        let columnStart = snap(surface.midX + 2.5 * unit)
        let rowBottom = snap(surface.minY + 18 * verticalUnit)
        let rowHeight = snap(80 * verticalUnit)
        let topBottom = snap(surface.minY + 115 * verticalUnit)
        // Presentation priority exists only while the capture menu is open.
        // Keep true queue indices for labels, AX identity and hit-test routing.
        var items: [Int] = []
        if let menu, twoRows {
            for id in menu.priorityIDs {
                guard items.count < capacity else { break }
                if let i = active.firstIndex(where: { $0.id == id }), !items.contains(i) {
                    items.append(i)
                }
            }
        }
        if !menuOpen || twoRows {
            // Only the opening's leading card is displaced. The cursor still
            // points at its original page so closing restores the same slots.
            let skipLeading = menu?.usesOpeningPage == true && menu?.openingRows.count == 3
                && first < active.count && active[first].id == menu?.displacedID
            let start = skipLeading ? first + 1 : first
            for i in start..<active.count {
                guard items.count < capacity else { break }
                if !items.contains(i) { items.append(i) }
            }
        }
        let showButton = captureEnabled && !menuOpen && first + items.count == active.count && items.count < 4
        func cell(_ index: Int) -> CGRect {
            let left = index.isMultiple(of: 2)
            return CGRect(x: left ? innerLeft : columnStart,
                          y: twoRows && index < 2 ? topBottom : rowBottom,
                          width: left ? columnEnd - innerLeft : innerRight - columnStart,
                          height: rowHeight)
        }
        let rows = items.enumerated().map { index, queueIndex -> RiftRowLayout in
            let record = active[queueIndex]
            let slot = cell(index)
            let w = CGFloat(record.image.pixelWidth), h = CGFloat(record.image.pixelHeight)
            // Leave the whole bitmap inside the rounded glass sheet. Its corner
            // and foot belong to the backing, including for tiny and tall images.
            let rim = min(2.75 * unit, slot.width / 8, slot.height / 8)
            let foot = min(0.75 * unit, slot.height / 10)
            let maxW = slot.width - 2 * rim, maxH = slot.height - 2 * rim - foot
            let ratio = w > 0 && h > 0 ? max(0, min(1 / px, maxW / w, maxH / h)) : 0
            let size = CGSize(width: w * ratio, height: h * ratio)
            let origin = CGPoint(x: (slot.width - size.width) / CGFloat(2),
                                 y: (slot.height - size.height + foot) / CGFloat(2))
            let image = CGRect(origin: origin, size: size)
            let obscured = image.width * c.trayOcclusion
            let clip = CGRect(x: image.minX + (c.placement?.side == .left ? obscured : 0), y: image.minY,
                              width: image.width - obscured, height: image.height)
            var row = RiftRowLayout(assetID: record.id, ordinal: queueIndex + 1, frame: slot,
                                    imageFrame: image, imageClipFrame: clip, numberFrame: .zero)
            row.trayCardFrame = CGRect(x: clip.minX - rim, y: clip.minY - rim - foot,
                                       width: clip.width + 2 * rim, height: clip.height + 2 * rim + foot)
            return row
        }
        result = RiftLayoutResult(rows: rows, lineFrame: .zero, firstVisibleIndex: first,
                                  capacity: capacity, totalCount: active.count + (captureEnabled && !showButton && !menuOpen ? 1 : 0))
        result.surfaceFrame = surface
        if showButton { result.captureSlot = cell(items.count) }
        if menuOpen {
            result.captureMenuFrame = CGRect(x: innerLeft, y: rowBottom, width: innerRight - innerLeft, height: rowHeight)
        }
        return result
    }
}
