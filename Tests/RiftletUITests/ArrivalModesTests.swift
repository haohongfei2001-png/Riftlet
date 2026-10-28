import AppKit
import XCTest
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import RiftletCore
@testable import RiftletUI

/// Real AppKit objects with generated image fixtures and software event/AX calls.
/// PHYSICAL_GUI_NOT_RUN, SYSTEM_SCREENSHOT_NOT_RUN, REAL_UPLOAD_NOT_RUN.
/// Rendered state is supplied as a fixture; it does not manufacture a receipt.
final class ArrivalModesTests: XCTestCase {
    private enum WaitFailure: Error { case deadline }

    @MainActor private func environment(motion: Bool = false) throws -> (URL, NSScreen, RiftConfiguration) {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first(where: { $0.frame.width > 800 && $0.visibleFrame.height > 400 }),
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            throw XCTSkip("WindowServer display unavailable; PHYSICAL_GUI_NOT_RUN")
        }
        if motion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            throw XCTSkip("Host Reduce Motion prevents native flight; PHYSICAL_GUI_NOT_RUN")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-arrival-modes-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var configuration = RiftConfiguration()
        configuration.preferredDisplayID = id
        return (root, screen, configuration)
    }

    private func generated(_ index: Int = 1, directory: URL) throws -> AssetRecord {
        let id = UUID()
        let url = directory.appendingPathComponent(id.uuidString + ".png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.15, green: 0.4, blue: 0.65, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        context.setFillColor(red: 0.9, green: CGFloat(index % 10) / 10, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 25, y: 25, width: 100, height: 100))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = try Data(contentsOf: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let imported = ImportedAsset(id: id, sourceKey: "generated-arrival-\(id)", fileName: url.lastPathComponent,
            sha256: digest, byteCount: Int64(bytes.count), pixelWidth: 200, pixelHeight: 200,
            mediaType: "image/png", origin: .synthetic)
        return AssetRecord(image: imported, sequence: Int64(index))
    }

    private func state(_ original: AssetRecord, status: QueueStatus, visibility: QueueVisibility,
                       reason: QueueVisibilityReason, revision: Int64 = 1) -> AssetRecord {
        AssetRecord(image: original.image, sequence: original.sequence, status: status, visibility: visibility,
                    visibilityRevision: revision, visibilityReason: reason)
    }

    @MainActor private func source(_ screen: NSScreen) throws -> RiftArrivalSource {
        let id = try XCTUnwrap((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value)
        let extent = CGFloat(200) / screen.backingScaleFactor
        return RiftArrivalSource(rect: CGRect(x: screen.frame.minX + 80, y: screen.frame.midY - extent / 2, width: extent, height: extent),
            displayID: id, displayFrame: screen.frame, backingScale: screen.backingScaleFactor)
    }

    @MainActor private func row(_ panel: RiftPanelController, id: UUID) throws -> (RiftDiagnosticRow, NSWindow, NSView, CALayer) {
        let info = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == id })
        let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == info.windowNumber })
        let view = try XCTUnwrap(window.contentView)
        let layer = try XCTUnwrap(view.layer?.sublayers?.first?.sublayers?.first)
        return (info, window, view, layer)
    }

    @MainActor private func eventually(_ description: String, _ condition: () -> Bool) async throws {
        for _ in 0..<70 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail(description)
        throw WaitFailure.deadline
    }

    @MainActor private func beginFlight(_ panel: RiftPanelController, record: AssetRecord, screen: NSScreen,
                                       records: [AssetRecord]? = nil) async throws {
        let token = try XCTUnwrap(panel.noteCaptureReady(record.id, uptime: ProcessInfo.processInfo.systemUptime))
        panel.resolveArrivalSource(try source(screen), assetID: record.id, token: token)
        panel.render(records ?? [record])
        // Availability does not wait for asynchronous image decoding or flight.
        XCTAssertTrue(panel.diagnosticSnapshot.rows.contains { $0.assetID == record.id })
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning)
        try await eventually("A valid generated image/source did not start native flight within the bounded window") {
            panel.arrivalDiagnostic.activeAssetID == record.id
        }
    }

    @MainActor private func assertStatic(_ panel: RiftPanelController, id: UUID,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        let (geometry, window, _, layer) = try row(panel, id: id)
        XCTAssertEqual(window.alphaValue, 1, file: file, line: line)
        for number in [geometry.imageInputWindowNumber, geometry.numberInputWindowNumber] {
            let input = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == number }, file: file, line: line)
            XCTAssertEqual(input.alphaValue, 1, file: file, line: line)
        }
        XCTAssertEqual(layer.affineTransform().tx, 0, file: file, line: line)
        XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true, file: file, line: line)
        XCTAssertFalse(layer.isHidden, file: file, line: line)
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning, file: file, line: line)
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0, file: file, line: line)
    }

    @MainActor func testNoneCreatesFinalInteractiveRowAndPressWithoutDecorativeDisplacement() throws {
        let (root, _, configuration) = try environment()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try generated(directory: root)
        var selected: [UUID] = []
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .none,
            reduceMotionOverride: { false }, onSelect: { selected.append($0) })
        defer { panel.close() }
        XCTAssertNil(panel.noteCaptureReady(record.id, uptime: ProcessInfo.processInfo.systemUptime))
        panel.render([record])
        try assertStatic(panel, id: record.id)
        let (_, _, view, _) = try row(panel, id: record.id)
        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertEqual(selected, [record.id], "No animation completion or run-loop turn authorizes selection")
        try assertStatic(panel, id: record.id)
        XCTAssertFalse(panel.interactionSnapshot.isTransitioning)
    }

    @MainActor func testNoneSwallowCompactionFailureRebirthAndUnknownStayBusinessDrivenAndSynchronous() throws {
        let (root, _, configuration) = try environment()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try generated(1, directory: root), second = try generated(2, directory: root)
        var selected: [UUID] = []
        var phases: [RiftPresentationBoundary] = []
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .none,
            reduceMotionOverride: { false }, onPresentationBoundary: { phases.append($0) }, onSelect: { selected.append($0) })
        defer { panel.close() }
        panel.render([first, second])
        let firstOrigin = try row(panel, id: first.id).0.frame.origin
        let started = state(first, status: .transferring, visibility: .swallowed, reason: .uploadStarted)
        panel.render([started, second])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [second.id])
        XCTAssertEqual(try row(panel, id: second.id).0.frame.origin, firstOrigin)
        try assertStatic(panel, id: second.id)
        XCTAssertEqual(phases.map(\.phase), [.swallowScheduled, .swallowActualStart, .swallowClose])
        XCTAssertTrue(phases.allSatisfy { $0.actualDuration == 0 })
        panel.render([state(first, status: .unknown, visibility: .swallowed, reason: .uploadStarted), second])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [second.id])
        let failed = state(first, status: .failed, visibility: .visible, reason: .safeFailure, revision: 2)
        panel.render([failed, second])
        try assertStatic(panel, id: first.id)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [first.id, second.id])
        XCTAssertTrue(try row(panel, id: first.id).2.accessibilityPerformPress())
        XCTAssertEqual(selected, [first.id], "The reborn row keeps the same asset and can be selected normally")
        try assertStatic(panel, id: first.id)
    }

    @MainActor func testReduceMotionUsesTheSameZeroDurationLifecycleWithoutChangingSelectedMode() throws {
        let (root, _, configuration) = try environment()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try generated(directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { true }, onSelect: { _ in })
        defer { panel.close() }
        XCTAssertEqual(panel.arrivalDiagnostic.selectedMode, .magnet)
        XCTAssertEqual(panel.arrivalDiagnostic.effectiveMode, .none)
        XCTAssertNil(panel.noteCaptureReady(first.id, uptime: ProcessInfo.processInfo.systemUptime))
        panel.render([first]); try assertStatic(panel, id: first.id)
        panel.render([state(first, status: .transferring, visibility: .swallowed, reason: .uploadStarted)])
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning)
        panel.render([state(first, status: .failed, visibility: .visible, reason: .safeFailure, revision: 2)])
        try assertStatic(panel, id: first.id)
        XCTAssertEqual(panel.arrivalMode, .magnet)
    }

    @MainActor func testMouseDownDuringFlightCancelsOnlyDecorationAndMouseUpSelectsOriginalAssetImmediately() async throws {
        let (root, screen, configuration) = try environment(motion: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try generated(directory: root)
        var selected: [UUID] = [], pressed: [UUID] = []
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onPress: { id, _ in pressed.append(id) }, onSelect: { selected.append($0) })
        defer { panel.close() }
        try await beginFlight(panel, record: record, screen: screen)
        let original = try row(panel, id: record.id)
        XCTAssertTrue(original.3.isHidden)
        let input = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == original.0.imageInputWindowNumber })
        let inputView = try XCTUnwrap(input.contentView)
        let point = CGPoint(x: inputView.bounds.midX, y: inputView.bounds.midY)
        let now = ProcessInfo.processInfo.systemUptime
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: now, windowNumber: input.windowNumber, context: nil, eventNumber: 101, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: now + 0.001, windowNumber: input.windowNumber, context: nil, eventNumber: 102, clickCount: 1, pressure: 0))
        inputView.mouseDown(with: down)
        XCTAssertEqual(pressed, [record.id])
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0)
        XCTAssertNil(panel.arrivalDiagnostic.activeAssetID)
        XCTAssertFalse(original.3.isHidden)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.first?.imageInputFrame, original.0.imageInputFrame)
        XCTAssertTrue(selected.isEmpty)
        inputView.mouseUp(with: up)
        XCTAssertEqual(selected, [record.id])
        XCTAssertFalse(panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [record.id], "A click alone does not swallow")
    }

    @MainActor func testSwitchToNoneDuringFlightRestoresCanonicalImageAndNeverReplaysOldCompletion() async throws {
        let (root, screen, configuration) = try environment(motion: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try generated(directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        try await beginFlight(panel, record: record, screen: screen)
        panel.setArrivalMode(.none)
        try assertStatic(panel, id: record.id)
        XCTAssertNil(panel.arrivalDiagnostic.pendingAssetID)
        XCTAssertFalse(panel.interactionSnapshot.isTransitioning)
        try await Task.sleep(nanoseconds: 550_000_000)
        try assertStatic(panel, id: record.id)
        panel.setArrivalMode(.magnet)
        XCTAssertEqual(panel.arrivalMode, .magnet)
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0, "Mode change does not replay existing assets")
    }

    @MainActor func testReduceMotionChangeInterruptsAnActiveFlightWithoutReplacingUserChoice() async throws {
        let (root, screen, configuration) = try environment(motion: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try generated(directory: root)
        var reduceMotion = false
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { reduceMotion }, onSelect: { _ in })
        defer { panel.close() }
        try await beginFlight(panel, record: record, screen: screen)
        reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try await eventually("Reduce Motion notification did not clean up active decoration") {
            panel.arrivalDiagnostic.overlayCount == 0
        }
        XCTAssertEqual(panel.arrivalMode, .magnet)
        XCTAssertEqual(panel.effectiveArrivalMode, .none)
        try assertStatic(panel, id: record.id)
    }

    @MainActor private func captureBurst(_ count: Int) async throws {
        let (root, screen, configuration) = try environment(motion: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try (1...count).map { try generated($0, directory: root) }
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        try await beginFlight(panel, record: records[0], screen: screen)
        for index in 1..<count {
            let candidate = panel.noteCaptureReady(records[index].id, uptime: ProcessInfo.processInfo.systemUptime)
            if let candidate { panel.resolveArrivalSource(try source(screen), assetID: records[index].id, token: candidate) }
            panel.render(Array(records.prefix(index + 1)))
            XCTAssertLessThanOrEqual(panel.arrivalDiagnostic.overlayCount, 1)
            XCTAssertTrue(panel.diagnosticSnapshot.rows.contains { $0.assetID == records[index].id })
        }
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0, "A rapid burst settles instead of leaving many sprites")
        for record in records {
            panel.showAsset(record.id)
            XCTAssertTrue(panel.diagnosticSnapshot.rows.contains { $0.assetID == record.id }, "Supersession cannot discard an asset")
        }
    }

    @MainActor func testThreeCaptureBurstPreservesAllAssetsWithAtMostOneDecoration() async throws { try await captureBurst(3) }
    @MainActor func testTwelveCaptureBurstPreservesAllAssetsWithAtMostOneDecoration() async throws { try await captureBurst(12) }

    @MainActor func testMissingSourceAndLateMetadataLeaveTheFirstPresentedImageStatic() async throws {
        let (root, screen, configuration) = try environment()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try generated(directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        let token = try XCTUnwrap(panel.noteCaptureReady(record.id, uptime: ProcessInfo.processInfo.systemUptime))
        panel.render([record])
        let image = try row(panel, id: record.id).3
        try await eventually("Generated image was not decoded") { image.contents != nil }
        XCTAssertNil(panel.arrivalDiagnostic.pendingAssetID)
        panel.resolveArrivalSource(try source(screen), assetID: record.id, token: token)
        try assertStatic(panel, id: record.id)
        XCTAssertNil(panel.arrivalDiagnostic.activeAssetID)
    }

    @MainActor func testSupersededSourceTokenCannotAnimateOrHideTheNewerCapture() async throws {
        let (root, screen, configuration) = try environment()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try generated(1, directory: root), second = try generated(2, directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        let old = try XCTUnwrap(panel.noteCaptureReady(first.id, uptime: ProcessInfo.processInfo.systemUptime))
        _ = panel.noteCaptureReady(second.id, uptime: ProcessInfo.processInfo.systemUptime)
        panel.resolveArrivalSource(try source(screen), assetID: first.id, token: old)
        panel.render([first, second])
        let image = try row(panel, id: second.id).3
        try await eventually("Second generated image was not decoded") { image.contents != nil }
        XCTAssertNil(panel.arrivalDiagnostic.pendingAssetID)
        try assertStatic(panel, id: first.id)
        try assertStatic(panel, id: second.id)
    }

    @MainActor func testWrongDisplayStaleFrameInvalidSourceAndAbsentMetadataFallBackWithoutChangingInput() async throws {
        let (root, screen, configuration) = try environment()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = try source(screen)
        let invalid: [RiftArrivalSource?] = [nil,
            RiftArrivalSource(rect: valid.rect, displayID: valid.displayID &+ 1, displayFrame: valid.displayFrame, backingScale: valid.backingScale),
            RiftArrivalSource(rect: valid.rect, displayID: valid.displayID, displayFrame: valid.displayFrame.offsetBy(dx: 1, dy: 0), backingScale: valid.backingScale),
            RiftArrivalSource(rect: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), displayID: valid.displayID, displayFrame: valid.displayFrame, backingScale: valid.backingScale)]
        for (index, candidate) in invalid.enumerated() {
            let record = try generated(index + 1, directory: root)
            var selected: [UUID] = []
            let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
                reduceMotionOverride: { false }, onSelect: { selected.append($0) })
            defer { panel.close() }
            let token = try XCTUnwrap(panel.noteCaptureReady(record.id, uptime: ProcessInfo.processInfo.systemUptime))
            panel.resolveArrivalSource(candidate, assetID: record.id, token: token)
            panel.render([record])
            let (_, _, view, image) = try row(panel, id: record.id)
            try await eventually("Generated fallback image was not decoded") { image.contents != nil }
            try assertStatic(panel, id: record.id)
            XCTAssertTrue(view.accessibilityPerformPress())
            XCTAssertEqual(selected, [record.id])
            panel.close()
        }
    }

    @MainActor func testHideAndCloseDuringFlightReleaseDecorationsAndIgnoreLateWork() async throws {
        let (root, screen, configuration) = try environment(motion: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try generated(directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        try await beginFlight(panel, record: record, screen: screen)
        panel.setUserHidden(true)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0)
        XCTAssertNil(panel.arrivalDiagnostic.pendingAssetID)
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        panel.setUserHidden(false)
        try assertStatic(panel, id: record.id)
        panel.close()
        panel.render([record])
        XCTAssertNil(panel.noteCaptureReady(UUID(), uptime: ProcessInfo.processInfo.systemUptime))
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0)
    }

    @MainActor func testSecondClickInterruptsCommittedSwallowAndSelectsTheOriginalSecondAsset() throws {
        let (root, _, configuration) = try environment()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try generated(1, directory: root), second = try generated(2, directory: root)
        var selected: [UUID] = []
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { selected.append($0) })
        defer { panel.close() }
        panel.render([first, second])
        XCTAssertTrue(try row(panel, id: first.id).2.accessibilityPerformPress())
        panel.render([state(first, status: .transferring, visibility: .swallowed, reason: .uploadStarted), second])
        XCTAssertTrue(panel.diagnosticSnapshot.isTransitioning)
        let originalSecond = try row(panel, id: second.id).2
        XCTAssertTrue(originalSecond.accessibilityPerformPress())
        XCTAssertEqual(selected, [first.id, second.id])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [second.id])
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning)
    }

    @MainActor func testNewCaptureInterruptsCommittedSwallowWithoutWaitingForItsDuration() throws {
        let (root, _, configuration) = try environment()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try generated(1, directory: root), second = try generated(2, directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        panel.render([first])
        let started = state(first, status: .transferring, visibility: .swallowed, reason: .uploadStarted)
        panel.render([started])
        XCTAssertTrue(panel.diagnosticSnapshot.isTransitioning)
        panel.render([started, second])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [second.id])
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning)
        XCTAssertTrue(try row(panel, id: second.id).2.accessibilityPerformPress())
    }

    @MainActor func testNaturalFlightCompletionRestoresOneCanonicalImageAtTheUnchangedInputGeometry() async throws {
        let (root, screen, configuration) = try environment(motion: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try generated(directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        try await beginFlight(panel, record: record, screen: screen)
        let original = try row(panel, id: record.id)
        let pixels = try XCTUnwrap(original.3.contents as? CGImage)
        try await eventually("Flight did not finish and clear its native overlay") { panel.arrivalDiagnostic.overlayCount == 0 }
        let final = try row(panel, id: record.id)
        XCTAssertEqual(final.0.frame, original.0.frame)
        XCTAssertEqual(final.0.imageInputFrame, original.0.imageInputFrame)
        XCTAssertEqual(final.0.numberInputFrame, original.0.numberInputFrame)
        XCTAssertTrue((final.3.contents as? CGImage) === pixels)
        try assertStatic(panel, id: record.id)
        XCTAssertFalse(panel.interactionSnapshot.isTransitioning)
    }

    @MainActor func testNativeSettingsOffersExactlyTwoModesAndPreviewsEachSuccessfulSelection() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer unavailable; PHYSICAL_GUI_NOT_RUN") }
        var chosen: [ArrivalMotionMode] = []
        let controller = ArrivalMotionSettingsController(mode: .none, hasExplicitSelection: false) { chosen.append($0) }
        defer { controller.close() }
        controller.show()
        let content = try XCTUnwrap(controller.window?.contentView)
        let choice = try XCTUnwrap(content.subviews.compactMap { $0 as? NSPopUpButton }.first)
        XCTAssertEqual(choice.itemTitles, ["无", "磁力吸引"])
        let preview = try XCTUnwrap(content.subviews.first { $0.accessibilityRole() == .image })
        let image = try XCTUnwrap(preview.layer?.sublayers?.first?.sublayers?.first)
        XCTAssertTrue(image.animationKeys()?.isEmpty ?? true)
        choice.selectItem(at: 1)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(choice.action), to: choice.target, from: choice))
        XCTAssertEqual(chosen, [.magnet])
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertTrue(image.animationKeys()?.isEmpty ?? true)
        } else {
            XCTAssertEqual(image.animationKeys(), ["arrival.preview"])
        }
        choice.selectItem(at: 0)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(choice.action), to: choice.target, from: choice))
        XCTAssertEqual(chosen, [.magnet, .none])
        XCTAssertTrue(image.animationKeys()?.isEmpty ?? true, "None preview is immediately in its final state")
    }

    @MainActor func testNativeSettingsSaveFailureRestoresThePreviousSelectionAndReportsFailure() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer unavailable; PHYSICAL_GUI_NOT_RUN") }
        let controller = ArrivalMotionSettingsController(mode: .none, hasExplicitSelection: true) { _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        defer { controller.close() }
        controller.show()
        let content = try XCTUnwrap(controller.window?.contentView)
        let choice = try XCTUnwrap(content.subviews.compactMap { $0 as? NSPopUpButton }.first)
        choice.selectItem(at: 1)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(choice.action), to: choice.target, from: choice))
        XCTAssertEqual(choice.indexOfSelectedItem, 0)
        XCTAssertTrue(content.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("未能保存") })
    }

    @MainActor func testRemovingAnEarlierRowCancelsFlightWhoseDestinationHasChanged() async throws {
        let (root, screen, configuration) = try environment(motion: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try generated(1, directory: root), second = try generated(2, directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        panel.render([first])
        let firstPosition = try row(panel, id: first.id).0.frame
        try await beginFlight(panel, record: second, screen: screen, records: [first, second])
        let previousSecondPosition = try row(panel, id: second.id).0.frame
        XCTAssertNotEqual(previousSecondPosition.origin, firstPosition.origin)
        panel.render([state(first, status: .pending, visibility: .removed, reason: .userRemoved), second])
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0)
        XCTAssertNil(panel.arrivalDiagnostic.activeAssetID)
        XCTAssertEqual(try row(panel, id: second.id).0.frame, firstPosition)
        try assertStatic(panel, id: second.id)
    }

    @MainActor func testArchiveDeferredByActiveFlightIsReconsideredAtItsCompletion() async throws {
        let (root, screen, configuration) = try environment(motion: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try generated(directory: root)
        let panel = RiftPanelController(mediaDirectory: root, configuration: configuration, arrivalMode: .magnet,
            reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        try await beginFlight(panel, record: record, screen: screen)
        panel.render([state(record, status: .pending, visibility: .archived, reason: .automaticArchive)])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [record.id])
        try await eventually("Flight did not release archive transition protection") { panel.arrivalDiagnostic.overlayCount == 0 }
        // Real WindowServer cursor placement can independently protect a row.
        // This is the same contract as existing lifecycle tests, not a bypass.
        if panel.interactionSnapshot.blocksAutomaticArchive {
            XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [record.id])
        } else {
            XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
            XCTAssertEqual(panel.diagnosticSnapshot.lineFrame, .zero)
        }
    }
}
