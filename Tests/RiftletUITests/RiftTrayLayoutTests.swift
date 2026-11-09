import AppKit
import RiftletCapture
import RiftletCore
import XCTest
@testable import RiftletUI

final class RiftTrayLayoutTests: XCTestCase {
    private let display = CGRect(x: -1280, y: 40, width: 1280, height: 800)
    private func assets(_ count: Int) -> [AssetRecord] {
        let sizes = [(1200, 800), (9, 12), (5, 4000), (12000, 4)]
        return (0..<count).map { n in
            let id = UUID(), size = sizes[n % sizes.count]
            return AssetRecord(image: ImportedAsset(id: id, sourceKey: "tray-\(id)", fileName: "\(id).png",
                sha256: String(repeating: "d", count: 64), byteCount: 80, pixelWidth: size.0,
                pixelHeight: size.1, mediaType: "image/png", origin: .synthetic), sequence: Int64(n+1))
        }
    }
    private func layout(_ assets: [AssetRecord], capture: Bool = true, expanded: Bool = false, first: Int = 0,
                        configuration: RiftConfiguration = .init(), scale: Double = 2, arrivals: [UUID] = []) -> RiftLayoutResult {
        RiftTrayLayout.make(records: assets, visibleFrame: display, configuration: configuration,
                            firstVisibleIndex: first, backingScale: scale, captureEnabled: capture, expanded: expanded, arrivalIDs: arrivals)
    }
    func testCountMatrixStableBoundsQueueOrderAndMenuExclusion() {
        let compact = layout([]).surfaceFrame
        let full = layout(assets(3)).surfaceFrame
        XCTAssertEqual(full.width, display.width * 246 / 1672, accuracy: 0.5)
        XCTAssertEqual(compact.width, full.width)
        XCTAssertEqual(full.height / full.width, 212 / 246.0, accuracy: 0.005)
        XCTAssertEqual(compact.height / full.width, 115 / 246.0, accuracy: 0.005)
        XCTAssertEqual(compact.minY, full.minY)
        for count in [0,1,2,3,4,5,10] {
            let records = assets(count)
            for enabled in [true,false] {
                for expanded in [true,false] {
                    let v = layout(records, capture: enabled, expanded: expanded)
                    if count == 0 && !enabled { XCTAssertTrue(v.surfaceFrame.isEmpty); continue }
                    let open = enabled && expanded
                    let needsTwoRows = count >= 2 || (open && count == 1)
                    XCTAssertEqual(v.surfaceFrame, needsTwoRows ? full : compact)
                    XCTAssertEqual(v.rows.map(\.assetID), Array(records.prefix(open ? 2 : 3)).map(\.id))
                    XCTAssertEqual(!v.captureMenuFrame.isEmpty,open)
                    XCTAssertEqual(!v.captureSlot.isEmpty,enabled && !expanded && count <= 3)
                    for r in v.rows {
                        XCTAssertTrue(v.surfaceFrame.contains(r.frame))
                        XCTAssertFalse(r.frame.intersects(v.captureMenuFrame))
                        XCTAssertFalse(r.frame.intersects(v.captureSlot))
                    }
                    if open, let first = v.rows.first {
                        XCTAssertGreaterThan(first.frame.minY,v.captureMenuFrame.maxY)
                        XCTAssertGreaterThan(v.captureMenuFrame.width,2 * first.frame.width)
                    }
                }
            }
        }
    }

    func testReferenceGeometryAndSingleImageFillMotionAtBothScales() throws {
        let records = assets(3)
        var c = RiftConfiguration()
        c.placement = .rightMiddle
        c.outerInset = 16
        let frame = CGRect(x: 0, y: 0, width: 1672, height: 910)
        for scale in [1.0, 2.0] {
            func measure(_ count: Int, open: Bool = false) -> RiftLayoutResult {
                RiftTrayLayout.make(records: Array(records.prefix(count)), visibleFrame: frame,
                                    configuration: c, firstVisibleIndex: 0, backingScale: scale,
                                    captureEnabled: true, expanded: open,
                                    displayFrame: CGRect(x: 0, y: 0, width: 1672, height: 941))
            }
            let full = measure(3)
            XCTAssertEqual(full.surfaceFrame.minX, 1410)
            XCTAssertEqual(full.surfaceFrame.minY, 308.5, accuracy: 0.5)
            XCTAssertEqual(full.surfaceFrame.size, CGSize(width: 246, height: 212))
            XCTAssertEqual(full.rows[0].frame.width, 113.5, accuracy: 0.5)
            XCTAssertEqual(full.rows[0].frame.height, 80)
            XCTAssertEqual(full.rows[0].frame.minX - full.surfaceFrame.minX, 7)
            XCTAssertEqual(full.rows[1].frame.minX - full.rows[0].frame.maxX, 5, accuracy: 1)
            XCTAssertEqual(full.rows[0].frame.minY - full.rows[2].frame.maxY, 17, accuracy: 1)
            let single = measure(1), open = measure(1, open: true)
            XCTAssertEqual(single.surfaceFrame.height, 115)
            XCTAssertEqual(open.rows[0].assetID, single.rows[0].assetID)
            XCTAssertEqual(open.rows[0].frame.minY - single.rows[0].frame.minY, 97, accuracy: 1)
            XCTAssertEqual(open.captureMenuFrame.width, 232)
            XCTAssertEqual(measure(0, open: true).surfaceFrame, single.surfaceFrame)
            for row in full.rows {
                let card = try XCTUnwrap(row.trayCardFrame)
                XCTAssertTrue(card.insetBy(dx: -0.001, dy: -0.001).contains(row.imageFrame))
                let slot = CGRect(origin: .zero, size: row.frame.size).insetBy(dx: -0.001, dy: -0.001)
                XCTAssertTrue(slot.contains(card))
            }
        }
    }

    func testFourthImageAndLastButtonAreBothReachableWithoutChangingIDs() {
        var c = RiftConfiguration()
        c.visibleCountPreference = 10
        for count in [4,8,10] {
            let records = assets(count)
            let start = layout(records,configuration: c)
            XCTAssertEqual(start.rows.count,4)
            XCTAssertTrue(start.hasLater)
            XCTAssertTrue(start.captureSlot.isEmpty)
            let last = layout(records, first: Int.max, configuration: c)
            XCTAssertEqual(last.rows.map(\.assetID), records.suffix(3).map(\.id))
            XCTAssertFalse(last.captureSlot.isEmpty)
            XCTAssertFalse(last.hasLater)
            let lastWithoutButton = layout(records,capture:false,first:Int.max,configuration:c)
            XCTAssertEqual(lastWithoutButton.rows.map(\.assetID),records.suffix(4).map(\.id))
        }
    }

    func testFitOcclusionEdgesAndSmallImage() {
        var c = RiftConfiguration()
        c.visibleCountPreference = 4
        let records = assets(4)
        for placement in RiftPlacement.allCases {
            c.placement = placement
            for scale in [1.0,2.0] {
                c.trayOcclusion = 0
                let full = layout(records,capture:false,configuration:c,scale:scale)
                XCTAssertTrue(display.contains(full.surfaceFrame))
                for (i,row) in full.rows.enumerated() {
                    let source = records[i].image
                    XCTAssertEqual(row.imageFrame,row.imageClipFrame)
                    XCTAssertLessThanOrEqual(row.imageFrame.width * scale,CGFloat(source.pixelWidth))
                    XCTAssertLessThanOrEqual(row.imageFrame.height * scale,CGFloat(source.pixelHeight))
                    XCTAssertEqual(row.imageFrame.width/row.imageFrame.height,
                                   CGFloat(source.pixelWidth)/CGFloat(source.pixelHeight),accuracy:1e-8)
                }
                c.trayOcclusion = 0.4
                let masked = layout(records,capture:false,configuration:c,scale:scale)
                XCTAssertEqual(masked.rows.map(\.assetID),full.rows.map(\.assetID))
                for row in masked.rows {
                    XCTAssertEqual(row.imageClipFrame.width, 0.6 * row.imageFrame.width, accuracy: 1e-8)
                    XCTAssertTrue(row.containsSelectionPoint(CGPoint(x:row.imageClipFrame.midX,y:row.imageClipFrame.midY)))
                }
            }
        }
    }

    @MainActor func testFourAccessibleControlsRouteRealModesWithDefaultAtOuterEdge() {
        let records = assets(2)
        let v = layout(records, expanded:true)
        let surface = RiftTraySurfaceView(frame:CGRect(origin:.zero,size:v.surfaceFrame.size))
        var pressed: [ScreenshotMode] = []
        surface.onCapture = { pressed.append($0) }
        for side in [RiftSide.left, .right] {
            for mode in ScreenshotMode.allCases {
                let automatic = RiftConfiguration().trayFavoriteModes(defaultMode: mode)
                for choices: [ScreenshotMode?] in [automatic, [.region, .window, .region]] {
                    surface.update(layout: v, violet: true, defaultMode: mode,
                                   favoriteModes: choices, reduceMotion: true, side: side)
                    let buttons = surface.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }
                        .sorted { $0.frame.minX < $1.frame.minX }
                    XCTAssertEqual(buttons.count, 4)
                    XCTAssertEqual(buttons.compactMap { $0.accessibilityLabel() }.count, 4)
                    let innerToOuter = side == .left ? Array(buttons.reversed()) : buttons
                    XCTAssertEqual(innerToOuter.map(\.isEnabled), (choices + [mode]).map { $0 != nil })
                    pressed.removeAll()
                    for button in innerToOuter { button.performClick(nil) }
                    XCTAssertEqual(pressed, choices.compactMap { $0 } + [mode])
                }
            }
        }
    }

    @MainActor func testCollapseMovesGlassWithTheOriginalScreenshot() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer required") }
        var c = RiftConfiguration()
        c.desktopForm = .tray
        c.shiftDuration = 0.65
        let panel = RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
                                        configuration: c, reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        let one = assets(1)
        panel.setTrayCapture(enabled: true, defaultMode: .window)
        panel.render(one)
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.contentView is RiftTraySurfaceView })
        let compactHeight = window.frame.height
        panel.setTrayExpanded(true)
        let deadline = Date().addingTimeInterval(2)
        while panel.diagnosticSnapshot.isTransitioning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let fullHeight = window.frame.height
        XCTAssertGreaterThan(fullHeight, compactHeight)
        panel.setTrayExpanded(false)
        var intermediate = false
        let closeDeadline = Date().addingTimeInterval(2)
        while panel.diagnosticSnapshot.isTransitioning && Date() < closeDeadline {
            if window.frame.height > compactHeight + 1 && window.frame.height < fullHeight - 1 {
                let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
                XCTAssertEqual(row.assetID, one[0].id)
                XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(row.imageInputFrame))
                intermediate = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(intermediate, "Glass must follow the moving row before reaching its compact height")
    }

    func testExpandedArrivalsRetainTrueOrdinalsAndCloseRestoresViewport() {
        let records = assets(10)
        let arrivals = [UUID(),records[9].id,records[9].id]
        let open = layout(records, expanded:true, first:3, arrivals:arrivals)
        XCTAssertEqual(open.rows.map(\.assetID),[records[9].id,records[3].id])
        XCTAssertEqual(open.rows.map(\.ordinal),[10,4])
        XCTAssertEqual(open.firstVisibleIndex,3)
        let updated = layout(records, expanded:true, first:3, arrivals:[records[8].id]+arrivals)
        XCTAssertEqual(updated.rows.map(\.ordinal),[9,10])
        let closed = layout(records, first:3, arrivals:arrivals)
        XCTAssertEqual(closed.rows.map(\.ordinal),[4,5,6])
        let disabled = layout(records,capture:false,expanded:true,first:3,arrivals:arrivals)
        XCTAssertEqual(disabled.rows.map(\.ordinal),[4,5,6])
    }
}
