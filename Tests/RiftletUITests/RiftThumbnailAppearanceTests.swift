#if canImport(AppKit)
import AppKit
import XCTest
@testable import RiftletUI

final class RiftThumbnailAppearanceTests: XCTestCase {
    @MainActor func testContactDisappearsForUnoccludedAndNarrowSlices() {
        XCTAssertEqual(RiftThumbnailAppearance.contactWidth(exposed: 72, hidden: false), 0)
        XCTAssertEqual(RiftThumbnailAppearance.contactWidth(exposed: 7.2, hidden: true), 0)
        XCTAssertEqual(RiftThumbnailAppearance.contactWidth(exposed: 12, hidden: true), 0)
        XCTAssertEqual(RiftThumbnailAppearance.contactWidth(exposed: 18, hidden: true), 1)
        XCTAssertEqual(RiftThumbnailAppearance.contactWidth(exposed: 54, hidden: true), 2)
    }
    @MainActor func testThreeFreeEdgesRemainOpenAndZeroOcclusionCloses() {
        for left in [false, true] {
            for width: CGFloat in [1.4, 7.2, 54, 72] {
                let rect = CGRect(x: -2.25,y: 0.25,width: width,height: 40.5)
                let open = RiftThumbnailAppearance.contour(rect, radius: 2, left: left, hidden: true)
                var closes = 0
                open.applyWithBlock { if $0.pointee.type == .closeSubpath { closes += 1 } }
                XCTAssertEqual(closes, 0)
                XCTAssertEqual(open.boundingBoxOfPath.minX,rect.minX,accuracy:0.00001)
                XCTAssertEqual(open.boundingBoxOfPath.maxX,rect.maxX,accuracy:0.00001)
                let closed = RiftThumbnailAppearance.contour(rect, radius: 2, left: left, hidden: false)
                closed.applyWithBlock { if $0.pointee.type == .closeSubpath { closes += 1 } }
                XCTAssertEqual(closes,1)
            }
        }
    }
    @MainActor func testTinyInnerContourNeverConstructsNegativeRadius() {
        XCTAssertTrue(RiftThumbnailAppearance.contour(CGRect(x:0,y:0,width:-0.6,height:9),radius:2,left:false,hidden:true).isEmpty)
    }
    @MainActor func testOrnamentsDoNotMutateSourceFitAndContactStaysAtPlane() {
        let view = NSView(frame:CGRect(x:0,y:0,width:100,height:64))
        view.wantsLayer = true
        let clip = CALayer(), image = CALayer()
        image.frame = CGRect(x:0,y:0,width:72,height:40.5)
        clip.addSublayer(image)
        let decoration = RiftThumbnailDecoration(parent:view.layer!,imageClip:clip)
        let rect = CGRect(x:20.25,y:7.25,width:54,height:40.5)
        for left in [false,true] {
            decoration.update(view:view,imageClip:clip,rect:rect,left:left,hidden:true,hovered:true,pressed:true)
            XCTAssertEqual(image.frame.size,CGSize(width:72,height:40.5))
            XCTAssertEqual(clip.frame,rect)
            XCTAssertEqual(decoration.contact.frame.width,2)
            XCTAssertEqual(left ? decoration.lip.frame.maxX : decoration.lip.frame.minX,left ? rect.minX : rect.maxX)
            XCTAssertEqual(decoration.moving.affineTransform(),.identity)
        }
    }
}
#endif
