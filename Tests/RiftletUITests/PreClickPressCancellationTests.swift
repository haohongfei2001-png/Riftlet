import AppKit
import XCTest
import RiftletCore
@testable import RiftletUI

/// Exercises the AppKit input views directly, without posting global mouse events.
final class PreClickPressCancellationTests: XCTestCase {
    private enum Callback: Equatable {
        case pressed(UUID), cancelled(UUID), selected(UUID)
    }

    @MainActor private final class Fixture {
        let asset: AssetRecord
        let panel: RiftPanelController
        private let log: Log
        var callbacks: [Callback] { log.events }

        private final class Log {
            var events: [Callback] = []
        }

        init() throws {
            _ = NSApplication.shared
            guard !NSScreen.screens.isEmpty else { throw XCTSkip("The AppKit input views require a screen") }
            let id = UUID()
            asset = AssetRecord(image: ImportedAsset(id: id, sourceKey: "press-cancel-\(id)",
                fileName: "\(id).png", sha256: String(repeating: "a", count: 64), byteCount: 100,
                pixelWidth: 360, pixelHeight: 220, mediaType: "image/png", origin: .synthetic), sequence: 1)
            let log = Log()
            self.log = log
            panel = RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
                reduceMotionOverride: { true },
                onPress: { id, _ in log.events.append(.pressed(id)) },
                onCancelledPress: { log.events.append(.cancelled($0)) },
                onSelect: { log.events.append(.selected($0)) })
            panel.render([asset])
        }

        func imageInput() throws -> ImageInput {
            let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == asset.id })
            let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.imageInputWindowNumber })
            return ImageInput(view: try XCTUnwrap(window.contentView), window: window,
                inside: CGPoint(x: row.imageClipFrame.midX, y: row.imageClipFrame.midY),
                outside: CGPoint(x: row.frame.minX - 100, y: row.frame.minY - 100))
        }
    }

    @MainActor private struct ImageInput {
        let view: NSView
        let window: NSWindow
        let inside: CGPoint
        let outside: CGPoint

        func event(_ type: NSEvent.EventType, at point: CGPoint, time: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: time, windowNumber: window.windowNumber,
                context: nil, eventNumber: Int(time * 10), clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0))
        }
    }

    @MainActor func testReleaseOutsideCancelsOriginalPressAndAllowsNextClick() throws {
        let fixture = try Fixture()
        defer { fixture.panel.close() }
        let input = try fixture.imageInput()
        let id = fixture.asset.id
        input.view.mouseDown(with: try input.event(.leftMouseDown, at: input.inside, time: 10))
        XCTAssertTrue(fixture.panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(fixture.callbacks, [.pressed(id)])
        input.view.mouseUp(with: try input.event(.leftMouseUp, at: input.outside, time: 10.1))
        XCTAssertFalse(fixture.panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(fixture.callbacks, [.pressed(id), .cancelled(id)])

        input.view.mouseDown(with: try input.event(.leftMouseDown, at: input.inside, time: 12))
        input.view.mouseUp(with: try input.event(.leftMouseUp, at: input.inside, time: 12.1))
        XCTAssertFalse(fixture.panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(fixture.callbacks, [.pressed(id), .cancelled(id), .pressed(id), .selected(id)])
    }

    @MainActor func testReleaseInsideSelectsExactlyOnceWithoutCancellation() throws {
        let fixture = try Fixture()
        defer { fixture.panel.close() }
        let input = try fixture.imageInput()
        let id = fixture.asset.id
        input.view.mouseDown(with: try input.event(.leftMouseDown, at: input.inside, time: 10))
        XCTAssertEqual(fixture.callbacks, [.pressed(id)])
        let up = try input.event(.leftMouseUp, at: input.inside, time: 10.1)
        input.view.mouseUp(with: up)
        input.view.mouseUp(with: up)
        XCTAssertFalse(fixture.panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(fixture.callbacks, [.pressed(id), .selected(id)])
    }

    @MainActor func testRebuildingHeldViewCancelsOnlyOldPressForSameAsset() throws {
        let fixture = try Fixture()
        defer { fixture.panel.close() }
        let old = try fixture.imageInput()
        let id = fixture.asset.id
        let lateRelease = try old.event(.leftMouseUp, at: old.inside, time: 12.1)
        old.view.mouseDown(with: try old.event(.leftMouseDown, at: old.inside, time: 10))
        XCTAssertTrue(fixture.panel.diagnosticSnapshot.isHolding)
        fixture.panel.setUserHidden(true)
        XCTAssertFalse(old.window.isVisible)
        XCTAssertFalse(fixture.panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(fixture.callbacks, [.pressed(id), .cancelled(id)])
        fixture.panel.setUserHidden(false)
        let replacement = try fixture.imageInput()
        XCTAssertFalse(replacement.view === old.view)
        replacement.view.mouseDown(with: try replacement.event(.leftMouseDown, at: replacement.inside, time: 12))
        old.view.mouseUp(with: lateRelease)
        XCTAssertTrue(fixture.panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(fixture.callbacks, [.pressed(id), .cancelled(id), .pressed(id)])
        replacement.view.mouseUp(with: try replacement.event(.leftMouseUp, at: replacement.inside, time: 12.2))
        XCTAssertFalse(fixture.panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(fixture.callbacks, [.pressed(id), .cancelled(id), .pressed(id), .selected(id)])
    }
}
