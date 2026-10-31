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
                // Compare native-to-native. AppKit normalizes borderless window
                // origins to its backing grid; mathematical frame addition is not
                // the pre-R2.1 behavior at fractional row heights (e.g. 40.5 pt).
                // This reference reproduces the unpadded R2 window/view setup and
                // never orders a reference window onto the desktop.
                let legacy = NSPanel(contentRect: expected.frame,
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                legacy.isReleasedWhenClosed = false; legacy.hasShadow = false
                legacy.isOpaque = false; legacy.backgroundColor = .clear
                legacy.ignoresMouseEvents = true
                let legacyView = NSView(frame: CGRect(origin: .zero, size: expected.frame.size))
                legacyView.wantsLayer = true; legacy.contentView = legacyView
                legacyView.frame.size = expected.frame.size
                legacy.setFrame(expected.frame, display: true)
                defer { legacy.close() }
                func assertRect(_ actual: CGRect, _ reference: CGRect,
                                file: StaticString = #filePath, line: UInt = #line) {
                    XCTAssertEqual(actual.minX, reference.minX, accuracy: 1e-9, file: file, line: line)
                    XCTAssertEqual(actual.minY, reference.minY, accuracy: 1e-9, file: file, line: line)
                    XCTAssertEqual(actual.width, reference.width, accuracy: 1e-9, file: file, line: line)
                    XCTAssertEqual(actual.height, reference.height, accuracy: 1e-9, file: file, line: line)
                }
                for (actual, inputFrame, local) in [
                    (row.imageClipFrame, row.imageInputFrame, expected.imageClipFrame),
                    (row.numberFrame, row.numberInputFrame, expected.numberFrame)
                ] {
                    let reference = legacy.convertToScreen(legacyView.convert(local, to: nil))
                    assertRect(actual, reference)
                    let legacyInput = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    legacyInput.isReleasedWhenClosed = false
                    legacyInput.setFrame(reference, display: true)
                    assertRect(inputFrame, legacyInput.frame)
                    legacyInput.close()
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

    @MainActor func testAppendOutsideCurrentPagePreservesNativePreview() async throws {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("No native screen") }
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NativeVisualEvidence/R21Fixtures")
        let records = (1...4).map { index in
            AssetRecord(image:ImportedAsset(id:UUID(),sourceKey:"r21-append-\(index)",fileName:"codex1.png",
                sha256:String(repeating:"a",count:64),byteCount:0,pixelWidth:1920,pixelHeight:1080,
                mediaType:"image/png",origin:.synthetic),sequence:Int64(index))
        }
        let preexistingWindows = Set(NSApp.windows.map(\.windowNumber))
        let controller = RiftPanelController(mediaDirectory:root,onSelect:{ _ in })
        defer { controller.close() }
        controller.render(Array(records.prefix(3)))
        let row = try XCTUnwrap(controller.diagnosticSnapshot.rows.first)
        let visual = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.windowNumber })
        XCTAssertEqual(visual.contentView?.accessibilityCustomActions()?.first?.handler?(),true)
        func preview() -> NSWindow? {
            NSApp.windows.first { panel in
                !preexistingWindows.contains(panel.windowNumber) &&
                panel.isVisible && panel.contentView?.subviews.contains(where: { ($0 as? NSImageView)?.image != nil }) == true
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while preview() == nil && ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds:10_000_000) }
        let panel = try XCTUnwrap(preview()), frame = panel.frame
        _ = controller.noteCaptureReady(records[3].id,uptime:ProcessInfo.processInfo.systemUptime)
        XCTAssertTrue(panel.isVisible,"Arrival alone must not revoke an unchanged visible page")
        controller.render(records)
        XCTAssertTrue(panel.isVisible); XCTAssertEqual(panel.frame,frame)
    }
}
