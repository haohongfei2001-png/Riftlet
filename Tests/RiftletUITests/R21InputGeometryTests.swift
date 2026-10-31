import AppKit
import XCTest
import RiftletCore
@testable import RiftletUI

/// Native window geometry/direct callbacks, not physical WindowServer routing.
final class R21InputGeometryTests: XCTestCase {
    @MainActor func testDecorativePaddingNeverMovesInputOrPressTarget() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { throw XCTSkip("No native screen") }
        for side in [RiftPlacement.leftMiddle, .rightMiddle] {
            for hidden in [0.0, 0.25, 0.9] {
                var c = RiftConfiguration(); c.placement = side; c.hiddenFraction = hidden
                c.arrivalDuration = 0; c.pressDuration = 0
                let id = UUID()
                let record = AssetRecord(image: ImportedAsset(id: id, sourceKey: "r21-synthetic", fileName: "r21-not-loaded.png",
                    sha256: String(repeating:"a",count:64), byteCount:0,pixelWidth:1920,pixelHeight:1080,mediaType:"image/png",origin:.synthetic),sequence:1)
                var selected: [UUID] = []
                let controller = RiftPanelController(mediaDirectory:FileManager.default.temporaryDirectory,
                    configuration:c,onSelect:{ selected.append($0) })
                defer { controller.close() }
                controller.render([record])
                let row = try XCTUnwrap(controller.diagnosticSnapshot.rows.first)
                let expected = try XCTUnwrap(RiftLayout.make(records:[record],visibleFrame:screen.visibleFrame,
                    configuration:c,backingScale:screen.backingScaleFactor,
                    highContrast:NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast).rows.first)
                for (actual, local) in [(row.imageClipFrame,expected.imageClipFrame),(row.numberFrame,expected.numberFrame)] {
                    XCTAssertEqual(actual.minX,expected.frame.minX+local.minX,accuracy:0.001)
                    XCTAssertEqual(actual.minY,expected.frame.minY+local.minY,accuracy:0.001)
                    XCTAssertEqual(actual.size,local.size)
                }
                let input = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.numberInputWindowNumber })
                let view = try XCTUnwrap(input.contentView)
                let location = CGPoint(x:input.frame.width/2,y:input.frame.height/2)
                func event(_ type:NSEvent.EventType)->NSEvent {
                    NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:10,
                        windowNumber:input.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
                }
                view.mouseDown(with:event(.leftMouseDown))
                let pressed = try XCTUnwrap(controller.diagnosticSnapshot.rows.first)
                XCTAssertEqual(pressed.imageInputFrame,row.imageInputFrame)
                XCTAssertEqual(pressed.numberInputFrame,row.numberInputFrame)
                XCTAssertEqual(pressed.imageClipFrame,row.imageClipFrame)
                view.mouseUp(with:event(.leftMouseUp))
                XCTAssertEqual(selected,[id])
            }
        }
    }
}
