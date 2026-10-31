import AppKit
import XCTest
import RiftletCore
@testable import RiftletUI

/// Native geometry/state checks only; physical WindowServer routing remains a
/// separate real-Mac acceptance check.
final class RiftCapturePresentationTests: XCTestCase {
    private func records(_ count: Int) -> [AssetRecord] {
        (0..<count).map { index in
            let id = UUID()
            return AssetRecord(image: ImportedAsset(id: id, sourceKey: "capture-header-\(id)",
                fileName: "\(id).png", sha256: String(repeating: "a", count: 64), byteCount: 100,
                pixelWidth: 1440, pixelHeight: 900, mediaType: "image/png", origin: .synthetic),
                sequence: Int64(index + 1))
        }
    }

    @MainActor private func controller() throws -> RiftPanelController {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("No AppKit display") }
        var configuration = RiftConfiguration()
        configuration.placement = .rightMiddle
        configuration.fitHeight = 48; configuration.rowPitch = 62
        configuration.outerInset = 14; configuration.firstCenterFromTop = 332
        configuration.arrivalDuration = 0.01
        return RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
                                   configuration: configuration, reduceMotionOverride: { false }, onSelect: { _ in })
    }

    @MainActor func testCaptureHeaderNeverMovesQueueOrExtendsItsLine() throws {
        let controller = try controller(); defer { controller.close() }
        let frame = try XCTUnwrap(controller.preferredScreen).visibleFrame
        let input = records(80); controller.render(input)
        let before = controller.diagnosticSnapshot
        let anchor = CGPoint(x: frame.maxX - 32, y: frame.maxY - 246)
        controller.setCaptureHeaderAnchor(anchor)
        XCTAssertEqual(controller.diagnosticSnapshot.rows.map(\.frame),before.rows.map(\.frame))
        XCTAssertEqual(controller.diagnosticSnapshot.lineFrame,before.lineFrame)
        XCTAssertEqual(before.rows.count,3)
        controller.showLatest()
        XCTAssertEqual(controller.diagnosticSnapshot.rows.last?.assetID,input.last?.id)
        XCTAssertTrue(controller.diagnosticSnapshot.rows.allSatisfy { frame.contains($0.frame) })
        let last = try XCTUnwrap(controller.diagnosticSnapshot.rows.last)
        XCTAssertGreaterThanOrEqual(controller.diagnosticSnapshot.lineFrame.minY,last.frame.minY)
    }

    @MainActor func testExposureSuppressionRetainsRowsAndUserHideWinsOverRestore() throws {
        let controller = try controller(); defer { controller.close() }
        let input = records(2); controller.render(input)
        let before = controller.diagnosticSnapshot.rows
        XCTAssertEqual(before.count, 2)
        controller.setCaptureSessionActive(true)
        for row in before {
            let panel = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.imageInputWindowNumber })
            XCTAssertEqual(panel.level.rawValue, NSWindow.Level.statusBar.rawValue + 1)
        }
        controller.setCaptureSuppressed(true)
        XCTAssertTrue(controller.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(controller.diagnosticSnapshot.lineFrame, .zero)
        controller.render(input + records(1))
        XCTAssertTrue(controller.diagnosticSnapshot.rows.isEmpty, "Refresh during exposure cannot reveal the queue")
        controller.setCaptureSuppressed(false)
        XCTAssertEqual(Set(controller.diagnosticSnapshot.rows.prefix(2).map(\.assetID)), Set(input.map(\.id)))
        controller.setCaptureSuppressed(true)
        controller.setUserHidden(true)
        controller.setCaptureSuppressed(false)
        XCTAssertTrue(controller.diagnosticSnapshot.rows.isEmpty)
        controller.setUserHidden(false)
        XCTAssertEqual(controller.diagnosticSnapshot.rows.count, 3)
    }

    @MainActor func testIndependentCameraHasAnchorBeforeFirstQueueRender() throws {
        let controller = try controller(); defer { controller.close() }
        let frame = try XCTUnwrap(controller.preferredScreen).visibleFrame
        let anchor = try XCTUnwrap(controller.screenshotEntryAnchor)
        XCTAssertTrue(frame.contains(anchor))
        XCTAssertTrue(controller.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(controller.diagnosticSnapshot.lineFrame, .zero)
        controller.render([])
        XCTAssertEqual(controller.screenshotEntryAnchor, anchor)
        controller.close()
        XCTAssertNil(controller.screenshotEntryAnchor)
    }

    @MainActor func testEmptyQueueNeverDrawsALineEvenWithCaptureHeader() throws {
        let controller = try controller(); defer { controller.close() }
        let frame = try XCTUnwrap(controller.preferredScreen).visibleFrame
        controller.setCaptureHeaderAnchor(CGPoint(x: frame.maxX - 32, y: frame.maxY - 246))
        controller.render([])
        XCTAssertEqual(controller.diagnosticSnapshot.lineFrame, .zero)
        controller.setCaptureSessionActive(true)
        XCTAssertEqual(controller.diagnosticSnapshot.lineFrame, .zero)
        controller.close(); controller.setCaptureSuppressed(false)
        XCTAssertTrue(controller.diagnosticSnapshot.rows.isEmpty)
    }

    @MainActor func testExposureRestoreDoesNotReverseAnInFlightSwallow() async throws {
        let controller = try controller(); defer { controller.close() }
        var config = controller.configuration; config.swallowDuration = 0.15
        try controller.updateConfiguration(config)
        let input = records(2); controller.render(input)
        let row = try XCTUnwrap(controller.diagnosticSnapshot.rows.first)
        let visual = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.windowNumber })
        // AppKit may insert a drawing/backing layer ahead of our clip on some
        // OS versions. Inspect the actual named content, never its array order.
        func descendants(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(descendants) }
        let imageLayer = try XCTUnwrap(descendants(try XCTUnwrap(visual.contentView?.layer)).first { $0.name == "rift.image.content" })
        let rootLayer = try XCTUnwrap(visual.contentView?.layer)
        let restingX = imageLayer.convert(.zero, to: rootLayer).x
        let swallowed = AssetRecord(image: input[0].image, sequence: input[0].sequence,
            status: .transferring, visibility: .swallowed, visibilityRevision: 1, visibilityReason: .uploadStarted)
        controller.render([swallowed, input[1]])
        let destination = imageLayer.convert(.zero, to: rootLayer).x - restingX
        XCTAssertGreaterThan(destination, 0)
        controller.setCaptureSuppressed(true); controller.setCaptureSuppressed(false)
        XCTAssertEqual(imageLayer.convert(.zero, to: rootLayer).x - restingX, destination, "Exposure restoration must not animate the image back out")
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(visual.isVisible)
        XCTAssertEqual(controller.diagnosticSnapshot.rows.map(\.assetID), [input[1].id])
    }
}
