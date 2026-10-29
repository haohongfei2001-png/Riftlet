import AppKit
import XCTest
import RiftletCore
@testable import RiftletUI

/// Direct native callback/geometry tests; not WindowServer click routing proof.
final class RiftInputIslandTests: XCTestCase {
    private func record(_ sequence: Int64 = 1) -> AssetRecord {
        let id = UUID()
        return AssetRecord(image: ImportedAsset(id: id, sourceKey: "input-island-\(id)",
            fileName: "\(id).png", sha256: String(repeating: "a", count: 64), byteCount: 100,
            pixelWidth: 360, pixelHeight: 220, mediaType: "image/png", origin: .synthetic), sequence: sequence)
    }

    @MainActor private func controller(onBoundary: @escaping (RiftSelectionBoundary) -> Void = { _ in },
                                      onReceipt: @escaping (RiftSelectionBoundary, Bool) -> Void = { _, _ in },
                                      onWindows: @escaping (RiftInputWindowObservation) -> Void = { _ in },
                                      onSelect: @escaping (UUID) -> Void = { _ in }) throws -> RiftPanelController {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("No AppKit screen; native routing remains separately unverified") }
        var configuration = RiftConfiguration()
        configuration.arrivalDuration = 0.01; configuration.pressDuration = 0.01
        configuration.swallowDuration = 0.02; configuration.shiftDuration = 0.01
        configuration.returnDuration = 0.01
        return RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
            configuration: configuration, arrivalMode: .magnet, onSelectionBoundary: onBoundary,
            onInputReceipt: onReceipt, onInputWindowObservation: onWindows, onSelect: onSelect)
    }

    @MainActor private func window(_ number: Int) throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0.windowNumber == number })
    }

    @MainActor private func event(_ type: NSEvent.EventType, window: NSWindow, screen: CGPoint,
                                  time: TimeInterval, count: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screen),
            modifierFlags: [], timestamp: time, windowNumber: window.windowNumber,
            context: nil, eventNumber: Int(time * 10), clickCount: count, pressure: 1))
    }

    @MainActor func testVisualIsMouseTransparentAndOnlyInputIslandsCoverImageAndNumber() throws {
        let panel = try controller(); defer { panel.close() }
        let asset = record(); panel.render([asset])
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
        let visual = try window(row.windowNumber)
        let image = try window(row.imageInputWindowNumber), number = try window(row.numberInputWindowNumber)
        XCTAssertEqual(Set([visual.windowNumber, image.windowNumber, number.windowNumber]).count, 3)
        XCTAssertTrue(visual.ignoresMouseEvents)
        for input in [image, number] {
            XCTAssertFalse(input.ignoresMouseEvents)
            XCTAssertFalse(input.canBecomeKey); XCTAssertFalse(input.canBecomeMain)
            XCTAssertTrue(input.styleMask.contains(.nonactivatingPanel))
            XCTAssertTrue(input.contentView?.isAccessibilityHidden() ?? false)
            XCTAssertNotEqual(input.contentView?.accessibilityIdentifier(), "riftlet-synthetic-\(asset.id)")
        }
        XCTAssertEqual(visual.contentView?.accessibilityIdentifier(), "riftlet-synthetic-\(asset.id)")
        XCTAssertEqual(row.imageInputFrame, image.frame); XCTAssertEqual(row.numberInputFrame, number.frame)
        // Native window frames may round fractional point dimensions; intended
        // region centers and the measured CLEAR point must remain unambiguous.
        XCTAssertTrue(image.frame.contains(CGPoint(x: row.imageClipFrame.midX, y: row.imageClipFrame.midY)))
        XCTAssertTrue(number.frame.contains(CGPoint(x: row.numberFrame.midX, y: row.numberFrame.midY)))
        let clear = CGPoint(x: row.frame.minX + 1.5, y: row.frame.minY + 2)
        XCTAssertFalse(image.frame.contains(clear)); XCTAssertFalse(number.frame.contains(clear))
        panel.setUserHidden(true)
        XCTAssertFalse(visual.isVisible); XCTAssertFalse(image.isVisible); XCTAssertFalse(number.isVisible)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
    }

    @MainActor func testOriginalInputEventSelectsSameAssetAcrossItsTwoIslandsAndRejectsPaddingRelease() throws {
        var selected: [UUID] = [], boundaries: [RiftSelectionBoundary] = []
        var receipts: [(RiftSelectionBoundary, Bool)] = []
        let panel = try controller(onBoundary: { boundaries.append($0) },
            onReceipt: { receipts.append(($0, $1)) }, onSelect: { selected.append($0) })
        defer { panel.close() }
        let asset = record(); panel.render([asset])
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
        let image = try window(row.imageInputWindowNumber), number = try window(row.numberInputWindowNumber)
        let imageView = try XCTUnwrap(image.contentView), numberView = try XCTUnwrap(number.contentView)
        let imagePoint = CGPoint(x: row.imageClipFrame.midX, y: row.imageClipFrame.midY)
        let numberPoint = CGPoint(x: row.numberFrame.midX, y: row.numberFrame.midY)
        // Original down window continues to receive the release, now over the
        // same asset's number island. Preserve exact event timestamp/window ID.
        imageView.mouseDown(with: try event(.leftMouseDown, window: image, screen: imagePoint, time: 10))
        XCTAssertTrue(panel.diagnosticSnapshot.isHolding)
        imageView.mouseUp(with: try event(.leftMouseUp, window: image, screen: numberPoint, time: 10.1))
        XCTAssertEqual(selected, [asset.id])
        XCTAssertEqual(boundaries.first?.windowNumber, image.windowNumber)
        XCTAssertEqual(boundaries.first?.eventUptime, 10)
        numberView.mouseDown(with: try event(.leftMouseDown, window: number, screen: numberPoint, time: 12))
        numberView.mouseUp(with: try event(.leftMouseUp, window: number, screen: numberPoint, time: 12.1))
        XCTAssertEqual(selected, [asset.id, asset.id])
        XCTAssertEqual(boundaries.last?.windowNumber, number.windowNumber)
        imageView.mouseDown(with: try event(.leftMouseDown, window: image, screen: imagePoint, time: 14))
        let clear = CGPoint(x: row.frame.minX + 1.5, y: row.frame.minY + 2)
        imageView.mouseUp(with: try event(.leftMouseUp, window: image, screen: clear, time: 14.1))
        XCTAssertEqual(selected.count, 2); XCTAssertFalse(panel.diagnosticSnapshot.isHolding)
        // A double-click cannot turn into an independent new selection.
        numberView.mouseDown(with: try event(.leftMouseDown, window: number, screen: numberPoint, time: 14.2, count: 2))
        numberView.mouseUp(with: try event(.leftMouseUp, window: number, screen: numberPoint, time: 14.3, count: 2))
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(receipts.count, 4, "Raw delivered presses include the rejected double click")
        XCTAssertEqual(receipts.map { $0.1 }, [true, true, true, false])
        XCTAssertEqual(receipts.last?.0.eventUptime, 14.2, "A rejected event retains its original time")
        XCTAssertEqual(receipts.last?.0.windowNumber, number.windowNumber)
        panel.close()
        imageView.mouseDown(with: try event(.leftMouseDown, window: image, screen: imagePoint, time: 20))
        imageView.mouseUp(with: try event(.leftMouseUp, window: image, screen: imagePoint, time: 20.1))
        XCTAssertEqual(selected.count, 2, "Retained closed input references cannot select")
    }

    @MainActor func testInputObservationDoesNotClaimSuppressedWindowsAreClickable() throws {
        var observations: [RiftInputWindowObservation] = []
        let panel = try controller(onWindows: { observations.append($0) }); defer { panel.close() }
        panel.setCaptureSuppressed(true)
        let asset = record(); panel.render([asset])
        let value = try XCTUnwrap(observations.first)
        XCTAssertEqual(value.assetID, asset.id)
        XCTAssertEqual(value.phase, "initialOrder")
        XCTAssertFalse(value.windowsVisible)
        XCTAssertFalse(value.selectionStateEligible)
        XCTAssertFalse(value.imageDecoded)
        XCTAssertFalse(value.ignoresMouseEvents, "Input capability and actual visibility are separate")
        XCTAssertGreaterThan(value.uptime, 0)
    }

    @MainActor func testHeldAssetDefersSwallowAndAllThreeWindowsCloseBeforeCompaction() async throws {
        let panel = try controller(); defer { panel.close() }
        let asset = record(), other = record(2); panel.render([asset, other])
        let before = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
        let image = try window(before.imageInputWindowNumber), visual = try window(before.windowNumber)
        let number = try window(before.numberInputWindowNumber), input = try XCTUnwrap(image.contentView)
        let point = CGPoint(x: before.imageClipFrame.midX, y: before.imageClipFrame.midY)
        input.mouseDown(with: try event(.leftMouseDown, window: image, screen: point, time: 30))
        let started = AssetRecord(image: asset.image, sequence: asset.sequence, status: .transferring,
            visibility: .swallowed, visibilityRevision: 1, visibilityReason: .uploadStarted)
        panel.render([started, other])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.first?.assetID, asset.id)
        XCTAssertTrue(panel.diagnosticSnapshot.isHolding)
        input.mouseUp(with: try event(.leftMouseUp, window: image, screen: point, time: 30.1))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(image.isVisible); XCTAssertFalse(number.isVisible); XCTAssertFalse(visual.isVisible)
        let after = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
        XCTAssertEqual(after.assetID, other.id)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.count, 1)
        let shiftedImage = try window(after.imageInputWindowNumber), shiftedNumber = try window(after.numberInputWindowNumber)
        XCTAssertEqual(shiftedImage.frame, after.imageInputFrame)
        XCTAssertTrue(shiftedImage.frame.contains(CGPoint(x: after.imageClipFrame.midX, y: after.imageClipFrame.midY)))
        XCTAssertTrue(shiftedNumber.frame.contains(CGPoint(x: after.numberFrame.midX, y: after.numberFrame.midY)))
        let oldWindows = [shiftedImage, shiftedNumber, try window(after.windowNumber)]
        var config = panel.configuration; config.fitWidth += 5
        try panel.updateConfiguration(config)
        XCTAssertTrue(oldWindows.allSatisfy { !$0.isVisible }, "Reflow retires every old input window")
        XCTAssertEqual(panel.diagnosticSnapshot.rows.first?.assetID, other.id)
    }
}
