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

    @MainActor func testVisualRefreshPreservesCompositeExitBehindFixedSeam() {
        for left in [false, true] {
            for width: CGFloat in [7.2, 54] {
                let view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 64))
                view.bounds = CGRect(x: -4, y: -4, width: 100, height: 64)
                view.wantsLayer = true
                let root = view.layer!, clip = CALayer(), image = CALayer()
                image.frame = CGRect(x: 0, y: 0, width: 72, height: 40.5)
                clip.addSublayer(image)
                let decoration = RiftThumbnailDecoration(parent: root, imageClip: clip)
                let rect = CGRect(x: 20.25, y: 7.25, width: width, height: 40.5)
                CATransaction.begin(); CATransaction.setDisableActions(true)
                decoration.update(view: view, imageClip: clip, rect: rect, left: left,
                                  hidden: true, hovered: false, pressed: false)
                let original = clip.convert(.zero, to: root)
                let offset = (left ? -1.0 : 1.0) * (width + 4)
                decoration.moving.setAffineTransform(CGAffineTransform(translationX: offset, y: 0))
                let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
                animation.values = [0, offset]; animation.duration = 0.12
                decoration.moving.add(animation, forKey: "rift.translation")
                let exited = clip.convert(.zero, to: root)
                XCTAssertEqual(exited.x, original.x + offset, accuracy: 1e-9)
                XCTAssertEqual(exited.y, original.y, accuracy: 1e-9)
                let contact = decoration.contact.frame, lip = decoration.lip.frame
                let surfaces: [CALayer] = [clip, decoration.matte, decoration.checker,
                                          decoration.outer, decoration.inner,
                                          decoration.primary, decoration.tight]
                let expected = surfaces.map { $0.convert(.zero, to: root) }
                for state in [(true, false), (false, false), (false, true), (false, false)] {
                    decoration.update(view: view, imageClip: clip, rect: rect, left: left,
                                      hidden: true, hovered: state.0, pressed: state.1)
                    for (surface, point) in zip(surfaces, expected) {
                        let actual = surface.convert(.zero, to: root)
                        XCTAssertEqual(actual.x, point.x, accuracy: 1e-9,
                                       "A visual refresh must preserve the complete committed exit; left=\(left), width=\(width)")
                        XCTAssertEqual(actual.y, point.y, accuracy: 1e-9)
                    }
                    let visible = (decoration.plane.mask as! CAShapeLayer).path!.boundingBoxOfPath
                    let content = clip.convert(clip.bounds, to: decoration.plane)
                    XCTAssertTrue(content.intersection(visible).isEmpty,
                                  "A refresh must not reveal content already behind the fixed seam")
                    XCTAssertEqual(decoration.contact.frame, contact)
                    XCTAssertEqual(decoration.lip.frame, lip)
                    XCTAssertEqual(image.frame.size, CGSize(width: 72, height: 40.5))
                    XCTAssertNotNil(decoration.moving.animation(forKey: "rift.translation"))
                }
                CATransaction.commit()
            }
        }
    }
}
#endif
