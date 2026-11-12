import AppKit
import QuartzCore
import XCTest
import RiftletCapture
@testable import RiftletUI

final class RiftTraySurfaceMotionTests: XCTestCase {
    // One and two rows under the same Saytile bottom edge, in screen points.
    private func layout(twoRows: Bool, menu: Bool) -> RiftLayoutResult {
        let surface = CGRect(x: 1240, y: twoRows ? 705 : 756, width: 184, height: twoRows ? 111 : 60)
        let rowY = twoRows ? 714.5 : 765.5
        var layout = RiftLayoutResult(rows: [], lineFrame: .zero, firstVisibleIndex: 0, capacity: 4, totalCount: 0)
        layout.surfaceFrame = surface
        if menu {
            layout.captureMenuFrame = CGRect(x: surface.minX + 5, y: rowY, width: 174, height: 42)
        } else {
            layout.captureSlot = CGRect(x: surface.minX + 93.5, y: rowY, width: 85.5, height: 42)
        }
        return layout
    }

    @MainActor private func window() throws -> (NSWindow, RiftTraySurfaceView) {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer required") }
        let frame = layout(twoRows: false, menu: true).surfaceFrame
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = RiftTraySurfaceView(frame: CGRect(origin: .zero, size: frame.size))
        window.contentView = view
        return (window, view)
    }

    private let modes: [ScreenshotMode] = [.region, .fullScreen, .window]
    @MainActor private func apply(_ layout: RiftLayoutResult, to view: RiftTraySurfaceView, window: NSWindow, reduceMotion: Bool) {
        window.setFrame(layout.surfaceFrame, display: false)
        view.update(layout: layout, colors: .violetGlass, defaultMode: .window,
                    favoriteModes: modes, reduceMotion: reduceMotion)
        view.layoutSubtreeIfNeeded()
    }

    @MainActor private func buttons(_ view: RiftTraySurfaceView) -> [NSButton] {
        view.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
    }

    @MainActor func testTopAnchoredGrowthAndShrinkKeepMenuKeysHittableDuringPanelMotion() throws {
        let (window, view) = try window()
        defer { window.close() }
        let compact = layout(twoRows: false, menu: true), expanded = layout(twoRows: true, menu: true)
        XCTAssertEqual(compact.surfaceFrame.maxY, expanded.surfaceFrame.maxY)
        apply(compact, to: view, window: window, reduceMotion: true)
        let keys = buttons(view)
        let localFrames = keys.map(\.frame)
        XCTAssertEqual(keys.count, 4)
        var routed: [ScreenshotMode] = []
        view.onCapture = { routed.append($0) }
        for next in [expanded, compact] {
            apply(next, to: view, window: window, reduceMotion: false)
            XCTAssertEqual(keys.map(\.frame), localFrames)
            routed.removeAll()
            for key in keys {
                XCTAssertEqual(key.frame.minY + next.surfaceFrame.minY, next.captureMenuFrame.minY)
                XCTAssertNil(key.layer?.animation(forKey: "rift.tray.morph"))
                XCTAssertTrue(view.hitTest(CGPoint(x: key.frame.midX, y: key.frame.midY)) === key)
                XCTAssertTrue(key.sendAction(key.action, to: key.target))
            }
            XCTAssertEqual(routed, modes + [.window])
        }
    }

    @MainActor func testOpeningAndClosingPreserveKeyMorphsInLocalCoordinates() throws {
        let (window, view) = try window()
        defer { window.close() }
        let compact = layout(twoRows: false, menu: false), expanded = layout(twoRows: true, menu: true)
        apply(compact, to: view, window: window, reduceMotion: true)
        let camera = try XCTUnwrap(buttons(view).first)
        let closedWidth = camera.frame.width
        for opening in [true, false] {
            let target = opening ? expanded : compact
            apply(target, to: view, window: window, reduceMotion: false)
            let keys = buttons(view)
            XCTAssertEqual(keys.count, 4)
            for key in keys {
                let morph = try XCTUnwrap(key.layer?.animation(forKey: "rift.tray.morph") as? CAAnimationGroup)
                let transform = try XCTUnwrap(morph.animations?.compactMap { $0 as? CABasicAnimation }
                    .first { $0.keyPath == "transform" })
                let start = try XCTUnwrap((transform.fromValue as? NSValue)?.caTransform3DValue)
                XCTAssertEqual(start.m42, 0, accuracy: 0.001)
                if opening { XCTAssertEqual(start.m11, closedWidth / key.frame.width, accuracy: 0.001) }
                else { XCTAssertLessThan(start.m11, 1) }
            }
            apply(target, to: view, window: window, reduceMotion: true)
        }
        XCTAssertEqual(buttons(view).count, 1)
        XCTAssertTrue(buttons(view).first === camera)
    }
}
