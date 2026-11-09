import XCTest
import RiftletCore
@testable import RiftletUI

final class RiftFolioLayoutTests: XCTestCase {
    private let screen = CGRect(x: -1552, y: 108, width: 1440, height: 878)
    private let images = (0..<10).map { index in
        let size = [(1440, 900), (280, 1700), (2, 1800), (5, 3)][index % 4]
        let id = UUID()
        return AssetRecord(image: ImportedAsset(id: id, sourceKey: "folio-\(index)",
            fileName: "\(id).png", sha256: String(repeating: "c", count: 64), byteCount: 100,
            pixelWidth: size.0, pixelHeight: size.1, mediaType: "image/png", origin: .synthetic),
            sequence: Int64(index + 1))
    }

    func testPagesKeepProportionsOrdinalsAndOneEdgeRoot() {
        var c = RiftConfiguration(); c.desktopForm = .edgefolio
        for place in RiftPlacement.allCases {
            c.placement = place
            for count in [0, 1, 2, 3, 4, 5, 10] {
                let records = Array(images.prefix(count))
                let layout = RiftFolioLayout.make(records: records, visibleFrame: screen, configuration: c)
                XCTAssertEqual(layout.rows.count, min(count, c.visibleCountPreference))
                XCTAssertEqual(layout.surfaceFrame.isEmpty, count == 0)
                for (index, page) in layout.rows.enumerated() {
                    XCTAssertEqual(page.assetID, records[index].id)
                    XCTAssertEqual(page.ordinal, index + 1)
                    XCTAssertTrue(screen.contains(page.frame))
                    XCTAssertTrue(layout.surfaceFrame.intersects(page.frame))
                    XCTAssertEqual(page.imageClipFrame, page.imageFrame)
                    XCTAssertFalse(page.numberFrame.intersects(page.imageFrame))
                    let image = records[index].image
                    XCTAssertEqual(page.imageFrame.width / page.imageFrame.height,
                                   CGFloat(image.pixelWidth) / CGFloat(image.pixelHeight), accuracy: 0.00001)
                    if index > 0 {
                        XCTAssertGreaterThan(layout.rows[index - 1].frame.minY, page.frame.maxY)
                        XCTAssertEqual(layout.rows[0].frame.width, page.frame.width)
                    }
                }
            }
        }
    }

    func testPocketPreservesApproachedAssetAtEachPlacementAndScale() {
        var c = RiftConfiguration(); c.desktopForm = .pocket
        for scale: CGFloat in [1, 2] {
            for place in RiftPlacement.allCases {
                c.placement = place
                for capacity in [3, 10] {
                    c.visibleCountPreference = capacity
                    let closed = RiftFolioLayout.make(records: images, visibleFrame: screen, configuration: c,
                                                      backingScale: scale)
                    for page in closed.rows {
                        let open = RiftFolioLayout.make(records: images, visibleFrame: screen, configuration: c,
                                                       backingScale: scale, expanded: true, anchoredID: page.assetID)
                        XCTAssertEqual(open.rows.map(\.assetID), closed.rows.map(\.assetID))
                        XCTAssertEqual(open.rows.first { $0.assetID == page.assetID }?.frame, page.frame)
                        // Last visual page is frontmost. An exposed point at the
                        // top of each card must still resolve to the identical ID.
                        let point = CGPoint(x: page.frame.midX, y: page.frame.maxY - 2)
                        XCTAssertEqual(closed.rows.last { $0.frame.contains(point) }?.assetID, page.assetID)
                        XCTAssertEqual(open.rows.last { $0.frame.contains(point) }?.assetID, page.assetID)
                        XCTAssertTrue(open.rows.allSatisfy { screen.contains($0.frame) && open.surfaceFrame.intersects($0.frame) })
                        if capacity == 3 {
                            for index in 1..<open.rows.count {
                                XCTAssertGreaterThan(open.rows[index - 1].frame.minY, open.rows[index].frame.maxY)
                            }
                        }
                    }
                }
            }
        }
    }

    func testViewportAndTinyImagesAtRetina() {
        var c = RiftConfiguration(); c.desktopForm = .edgefolio
        let page = RiftFolioLayout.make(records: images, visibleFrame: screen, configuration: c,
                                        firstVisibleIndex: 3, backingScale: 2)
        XCTAssertEqual(page.rows.map(\.assetID), images[3..<6].map(\.id))
        XCTAssertEqual(page.rows.first?.imageFrame.size, CGSize(width: 2.5, height: 1.5))
        XCTAssertTrue(page.hasEarlier && page.hasLater)
        let narrow = RiftFolioLayout.make(records: images, visibleFrame: CGRect(x: 5, y: 5, width: 22, height: 30),
                                         configuration: c)
        XCTAssertTrue(narrow.rows.isEmpty && narrow.surfaceFrame.isEmpty)
    }
}
