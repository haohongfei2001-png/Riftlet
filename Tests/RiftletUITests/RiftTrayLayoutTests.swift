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
        let fixed = layout([]).surfaceFrame
        XCTAssertEqual(fixed.width, display.width / 8)
        for count in [0,1,2,3,4,5,10] {
            let records = assets(count)
            for enabled in [true,false] {
                for expanded in [true,false] {
                    let v = layout(records, capture: enabled, expanded: expanded)
                    if count == 0 && !enabled { XCTAssertTrue(v.surfaceFrame.isEmpty); continue }
                    XCTAssertEqual(v.surfaceFrame, fixed)
                    let open = enabled && expanded
                    XCTAssertEqual(v.rows.map(\.assetID), Array(records.prefix(open ? 2 : 3)).map(\.id))
                    XCTAssertEqual(!v.captureMenuFrame.isEmpty,open)
                    XCTAssertEqual(!v.captureSlot.isEmpty,enabled && !expanded && count <= 3)
                    for r in v.rows {
                        XCTAssertTrue(fixed.contains(r.frame))
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
        var pressed: [ScreenshotMode] = [], more = 0
        surface.onCapture = { pressed.append($0) }
        surface.onMore = { _ in more += 1 }
        for side in [RiftSide.left, .right] {
            for mode in ScreenshotMode.allCases {
                surface.update(layout:v,violet:true,defaultMode:mode,reduceMotion:true,side:side)
                let buttons = surface.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }
                    .sorted { $0.frame.minX < $1.frame.minX }
                XCTAssertEqual(buttons.count,4)
                XCTAssertEqual(buttons.compactMap { $0.accessibilityLabel() }.count,4)
                let innerToOuter = side == .left ? Array(buttons.reversed()) : buttons
                pressed.removeAll()
                more = 0
                innerToOuter.first?.performClick(nil)
                XCTAssertEqual(more,1)
                for b in innerToOuter.dropFirst() { b.performClick(nil) }
                XCTAssertEqual(pressed.count,3)
                XCTAssertEqual(Set(pressed),Set(ScreenshotMode.allCases))
                XCTAssertEqual(pressed.last,mode)
            }
        }
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
