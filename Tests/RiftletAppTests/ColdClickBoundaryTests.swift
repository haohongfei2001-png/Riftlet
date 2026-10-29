import AppKit
import XCTest
import RiftletCore
@testable import RiftletUI

/// Actual AppKit input-island callbacks with a controlled host clock. These
/// are software events, not physical mouse or live Chrome acceptance.
final class ColdClickBoundaryTests: XCTestCase {
    @MainActor private final class Probe {
        let epoch = UUID()
        let original = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "fixture-process",
            windowID: "1", tabID: "2", documentID: "original-document",
            composerID: "original-composer", draftGeneration: "original-generation")
        var armed: ArmedTarget?
        var frozen: TargetLease?
        var boundaries: [RiftSelectionBoundary] = []
        var selectedTargets: [TargetLease] = []
        var pressTimes: [TimeInterval] = []

        func publish(at time: TimeInterval, target: TargetLease? = nil) {
            armed = ArmedTarget(target: target ?? original, acknowledgedUptime: time, hostSession: epoch)
        }
    }

    @MainActor private func run(_ prepare: (Probe) -> Void,
                               between: (Probe) -> Void = { _ in }) throws -> Probe {
        _ = NSApplication.shared
        // A missing WindowServer is a failed prerequisite for this dedicated CI
        // regression; do not silently turn it into a native PASS through XCTSkip.
        XCTAssertFalse(NSScreen.screens.isEmpty)
        let probe = Probe()
        prepare(probe)
        let id = UUID()
        let asset = AssetRecord(image: ImportedAsset(id: id, sourceKey: "cold-boundary-fixture",
            fileName: "\(id).png", sha256: String(repeating: "a", count: 64), byteCount: 64,
            pixelWidth: 200, pixelHeight: 100, mediaType: "image/png", origin: .synthetic), sequence: 1)
        let panel = RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
            arrivalMode: .none, onPress: { assetID, timestamp in
                XCTAssertEqual(assetID, id)
                probe.pressTimes.append(timestamp)
                // Delivery is deliberately late (host time 20), while the
                // original NSEvent is time 10. Never substitute handler time.
                probe.frozen = probe.armed?.freeze(eventUptime: timestamp, nowUptime: 20,
                    hostSession: probe.epoch, foregroundSession: probe.original.sessionID)
            }, onSelectionBoundary: { probe.boundaries.append($0) }, onSelect: { assetID in
                XCTAssertEqual(assetID, id)
                if let frozen = probe.frozen { probe.selectedTargets.append(frozen) }
            })
        defer { panel.close() }
        panel.render([asset])
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
        let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.imageInputWindowNumber })
        let view = try XCTUnwrap(window.contentView)
        let location = window.convertPoint(fromScreen: CGPoint(x: row.imageClipFrame.midX, y: row.imageClipFrame.midY))
        func event(_ type: NSEvent.EventType, time: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: time, windowNumber: window.windowNumber, context: nil,
                eventNumber: type == .leftMouseDown ? 91 : 92, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, time: 10))
        XCTAssertTrue(panel.diagnosticSnapshot.isHolding)
        between(probe)
        view.mouseUp(with: try event(.leftMouseUp, time: 10.1))
        XCTAssertFalse(panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(probe.pressTimes, [10])
        XCTAssertEqual(probe.boundaries.count, 1)
        XCTAssertEqual(probe.boundaries.first?.eventUptime, 10)
        XCTAssertEqual(probe.boundaries.first?.eventNumber, 91)
        XCTAssertEqual(probe.boundaries.first?.windowNumber, window.windowNumber)
        XCTAssertEqual(probe.boundaries.first?.source, .mouse)
        XCTAssertEqual(probe.boundaries.first?.clickCount, 1)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.first?.assetID, id,
            "Selection alone never supplies uploadStarted or swallows an image")
        return probe
    }

    @MainActor func testPreEventPublishedACKAuthorizesOriginalTargetOnce() throws {
        let result = try run { $0.publish(at: 9) }
        XCTAssertEqual(result.selectedTargets, [result.original])
    }

    @MainActor func testACKAfterOriginalEventButBeforeCallbackNeverBackfillsDelayedMouseDown() throws {
        let result = try run { $0.publish(at: 10.026742) }
        XCTAssertTrue(result.selectedTargets.isEmpty)
        XCTAssertNil(result.frozen)
    }

    @MainActor func testACKArrivingWhileHeldDoesNotRescueUnprovedOriginalPress() throws {
        let result = try run({ _ in }, between: { $0.publish(at: 10.05) })
        XCTAssertNotNil(result.armed)
        XCTAssertNil(result.frozen)
        XCTAssertTrue(result.selectedTargets.isEmpty)
    }

    @MainActor func testLaterPublicationCannotReplaceAlreadyFrozenOriginalDraft() throws {
        let result = try run({ $0.publish(at: 9) }, between: { probe in
            probe.publish(at: 10.05, target: TargetLease(adapterID: "chatgpt-web", surface: .webChat,
                applicationID: "com.google.Chrome", sessionID: "fixture-process",
                windowID: "1", tabID: "3", documentID: "other-document",
                composerID: "other-composer", draftGeneration: "other-generation"))
        })
        XCTAssertNotEqual(result.armed?.target, result.original)
        XCTAssertEqual(result.selectedTargets, [result.original],
            "The frozen target still requires original-target validation; no new capture may replace it")
    }
}
