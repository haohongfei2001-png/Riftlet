import AppKit
import XCTest
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import RiftletCore
@testable import RiftletUI

/// Native objects and direct callback events only. These are not physical input
/// or WindowServer click-through evidence, and never create an upload receipt.
final class QuietEdgeInteractionTests: XCTestCase {
    private func records(_ count: Int) -> [AssetRecord] {
        (0..<count).map { index in
            let id = UUID()
            return AssetRecord(image: ImportedAsset(id: id, sourceKey: "quiet-edge-test-\(id)",
                fileName: "\(id).png", sha256: String(repeating: "a", count: 64), byteCount: 100,
                pixelWidth: 360, pixelHeight: 220, mediaType: "image/png", origin: .synthetic),
                sequence: Int64(index + 1))
        }
    }

    private func swallowed(_ record: AssetRecord) -> AssetRecord {
        AssetRecord(image: record.image, sequence: record.sequence, status: .unknown,
            visibility: .swallowed, visibilityRevision: 1, visibilityReason: .uploadStarted)
    }

    @MainActor private func controller(mediaDirectory: URL? = nil,
                                      onBoundary: @escaping (RiftSelectionBoundary) -> Void = { _ in },
                                      onSelect: @escaping (UUID) -> Void = { _ in }) throws -> RiftPanelController {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.height > 500 && $0.visibleFrame.width > 500 }),
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            throw XCTSkip("No suitable AppKit display; physical input remains NOT_RUN")
        }
        var configuration = RiftConfiguration()
        configuration.preferredDisplayID = id
        configuration.swallowDuration = 0.02
        configuration.shiftDuration = 0.4 // Long enough to inspect the actual native intermediate geometry.
        return RiftPanelController(mediaDirectory: mediaDirectory ?? FileManager.default.temporaryDirectory,
            configuration: configuration, arrivalMode: .none, reduceMotionOverride: { false },
            onSelectionBoundary: onBoundary, onSelect: onSelect)
    }

    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Native presentation did not reach the bounded expected state")
        throw NSError(domain: "QuietEdgeInteractionTests", code: 1)
    }

    @MainActor private func window(_ number: Int) throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0.windowNumber == number })
    }

    @MainActor private func event(_ type: NSEvent.EventType, window: NSWindow,
                                  point: CGPoint, time: TimeInterval) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point),
            modifierFlags: [], timestamp: time, windowNumber: window.windowNumber,
            context: nil, eventNumber: 987, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
    }

    @MainActor func testCaptureSuppressionRestoresExistingPagerAndSessionLevelWithoutNewRender() throws {
        let panel = try controller(); defer { panel.close() }
        panel.render(records(80))
        let arrows = NSApp.windows.filter { window in
            guard window.isVisible, let button = window.contentView as? NSButton else { return false }
            return ["上一组截图", "下一组截图"].contains(button.toolTip ?? "")
        }
        XCTAssertEqual(arrows.count, 2)
        panel.setCaptureSessionActive(true)
        XCTAssertTrue(arrows.allSatisfy { $0.level.rawValue == NSWindow.Level.statusBar.rawValue + 1 })
        panel.setCaptureSuppressed(true)
        XCTAssertTrue(arrows.allSatisfy { !$0.isVisible })
        panel.setCaptureSuppressed(false)
        XCTAssertTrue(arrows.allSatisfy(\.isVisible), "Restoring a capture overlay must not require a new queue update")
        panel.setCaptureSessionActive(false)
        XCTAssertTrue(arrows.allSatisfy { $0.level == .floating })
        panel.setUserHidden(true)
        panel.setCaptureSuppressed(true); panel.setCaptureSuppressed(false)
        XCTAssertTrue(arrows.allSatisfy { !$0.isVisible }, "Explicit Hide still owns final visibility")
    }

    @MainActor func testExposureCancelsPendingDecodeAndRejectsRetainedAccessibilityReference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quiet-edge-decode-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 360, height: 220, bitsPerComponent: 8,
            bytesPerRow: 1440, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 360, height: 220))
        let cg = try XCTUnwrap(context.makeImage()), id = UUID()
        let url = root.appendingPathComponent("\(id).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = try Data(contentsOf: url)
        let record = AssetRecord(image: ImportedAsset(id: id, sourceKey: "synthetic-late-decode-\(id)",
            fileName: url.lastPathComponent, sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 360, pixelHeight: 220, mediaType: "image/png", origin: .synthetic), sequence: 1)
        var selections: [UUID] = []
        let panel = try controller(mediaDirectory: root, onSelect: { selections.append($0) })
        defer { panel.close() }
        panel.setArrivalMode(.magnet)
        let screen = try XCTUnwrap(panel.preferredScreen)
        let displayID = try XCTUnwrap((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value)
        let source = RiftArrivalSource(rect: CGRect(x: screen.frame.minX + 80, y: screen.frame.midY, width: 180, height: 110),
            displayID: displayID, displayFrame: screen.frame, backingScale: screen.backingScaleFactor)
        let token = try XCTUnwrap(panel.noteCaptureReady(id, uptime: ProcessInfo.processInfo.systemUptime))
        panel.resolveArrivalSource(source, assetID: id, token: token)
        panel.render([record])
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
        let retainedView = try XCTUnwrap(try window(row.windowNumber).contentView)
        // No suspension between render and suppression: ThumbnailCache's main
        // queue delivery has not run even if its worker already decoded bytes.
        panel.setCaptureSuppressed(true)
        XCTAssertFalse(retainedView.accessibilityPerformPress())
        XCTAssertNil(panel.arrivalDiagnostic.pendingAssetID)
        panel.resolveArrivalSource(source, assetID: id, token: token)
        XCTAssertNil(panel.noteCaptureReady(UUID(), uptime: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertNil(panel.arrivalDiagnostic.activeAssetID)
        XCTAssertNil(panel.arrivalDiagnostic.pendingAssetID)
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        panel.setCaptureSuppressed(false)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [id])
        XCTAssertEqual(panel.arrivalDiagnostic.overlayCount, 0, "Restoring exposure must not replay the cancelled source flight")
    }

    @MainActor func testReenterSamePreviewCancelsLeaveAndLateDecodeCannotResurrectCancelledPreview() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("No AppKit display") }
        let before = Set(NSApp.windows.map(\.windowNumber))
        let peek = RiftPeek(); defer { peek.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg = try XCTUnwrap(context.makeImage()), id = UUID()
        let row = CGRect(x: screen.visibleFrame.maxX - 90, y: screen.visibleFrame.midY, width: 70, height: 44)
        var deliveries: [((CGImage?) -> Void)] = []
        func schedule() {
            peek.schedule(id: id, immediate: true, stillValid: { true },
                load: { deliveries.append($0) }, anchor: { (row, screen.visibleFrame, row.minX) })
        }
        schedule()
        try await eventually { deliveries.count == 1 }
        deliveries[0](cg)
        let preview = try XCTUnwrap(NSApp.windows.first { !before.contains($0.windowNumber) && $0.isVisible })
        XCTAssertTrue(preview.ignoresMouseEvents); XCTAssertFalse(preview.canBecomeKey)
        peek.leave(); schedule()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(peek.assetID, id)
        XCTAssertTrue(preview.isVisible, "Returning within the leave grace period must retain the same preview")
        peek.cancel(); schedule()
        try await eventually { deliveries.count == 2 }
        peek.cancel(); deliveries[1](cg)
        XCTAssertNil(peek.assetID)
        XCTAssertFalse(preview.isVisible, "A late image decode must not reopen a cancelled private preview")
    }

    @MainActor func testFeedbackReusesPointerFreePeekAndInvalidatesOldDecodeAndWaitingDeadline() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("No AppKit display") }
        let peek = RiftPeek(); defer { peek.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg = try XCTUnwrap(context.makeImage()), id = UUID()
        let row = CGRect(x: screen.visibleFrame.maxX - 90, y: screen.visibleFrame.midY, width: 70, height: 44)
        let anchor = { (row, screen.visibleFrame, row.minX) as (CGRect, CGRect, CGFloat)? }
        var delivery: ((CGImage?) -> Void)?
        peek.schedule(id: id, immediate: true, stillValid: { true }, load: { delivery = $0 }, anchor: anchor)
        try await eventually { delivery != nil }
        let panel = peek.presentationPanel
        peek.scheduleNote(id: id, text: "正在等待附加", delay: 0.25, stillValid: { true }, anchor: anchor)
        delivery?(cg)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(panel.isVisible, "An old image decode cannot bypass the waiting delay")
        peek.leave()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(panel.isVisible, "Leaving the island cancels the pending explanation")
        XCTAssertNil(peek.assetID)
        peek.scheduleNote(id: id, text: "图片已保留，当前聊天暂时不能接收图片。", delay: 0,
            stillValid: { true }, anchor: anchor)
        try await eventually { peek.isNoteVisible }
        XCTAssertTrue(panel.ignoresMouseEvents); XCTAssertFalse(panel.canBecomeKey); XCTAssertFalse(panel.canBecomeMain)
        XCTAssertLessThanOrEqual(panel.frame.width, 240)
        XCTAssertLessThanOrEqual(panel.frame.maxX, row.minX - 12)
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
        // A repeated projection does not renew the bounded display lifetime.
        peek.scheduleNote(id: id, text: "图片已保留，当前聊天暂时不能接收图片。", delay: 0,
            stillValid: { true }, anchor: anchor)
        try await Task.sleep(nanoseconds: 2_600_000_000)
        XCTAssertFalse(panel.isVisible); XCTAssertNil(peek.assetID)
    }

    @MainActor func testPortraitPreviewClearsEveryNativeNumberAndImageInputIsland() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = try [(12, 100), (180, 16), (90, 120)].enumerated().map { index, size -> AssetRecord in
            let context = try XCTUnwrap(CGContext(data: nil, width: size.0, height: size.1, bitsPerComponent: 8,
                bytesPerRow: size.0 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.0, height: size.1))
            let cg = try XCTUnwrap(context.makeImage()), id = UUID()
            let url = root.appendingPathComponent("\(id).png")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, cg, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
            let data = try Data(contentsOf: url)
            return AssetRecord(image: ImportedAsset(id: id, sourceKey: "peek-clearance-\(id)", fileName: url.lastPathComponent,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(data.count),
                pixelWidth: size.0, pixelHeight: size.1, mediaType: "image/png", origin: .synthetic), sequence: Int64(index + 1))
        }
        let panel = try controller(mediaDirectory: root); defer { panel.close() }
        panel.render(input)
        let rows = panel.diagnosticSnapshot.rows
        let owner = try XCTUnwrap(rows.first { $0.assetID == input[0].id })
        let leading = try XCTUnwrap(rows.flatMap { [$0.imageInputFrame.minX, $0.numberInputFrame.minX] }.min())
        XCTAssertLessThan(leading, owner.frame.minX, "The wider neighbor must exercise the original overlap")
        let before = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        let content = try XCTUnwrap(try window(owner.windowNumber).contentView)
        let action = try XCTUnwrap(content.accessibilityCustomActions()?.first)
        XCTAssertTrue(action.handler?() == true)
        try await eventually { NSApp.windows.contains { $0.isVisible && !before.contains($0.windowNumber) } }
        let preview = try XCTUnwrap(NSApp.windows.first { $0.isVisible && !before.contains($0.windowNumber) })
        XCTAssertLessThanOrEqual(preview.frame.maxX, leading - 12)
        XCTAssertTrue(preview.ignoresMouseEvents); XCTAssertFalse(preview.canBecomeKey)
        for row in rows {
            XCTAssertFalse(preview.frame.intersects(row.imageInputFrame))
            XCTAssertFalse(preview.frame.intersects(row.numberInputFrame))
        }
    }

    @MainActor func testPressDuringNativeReflowKeepsRawEventAndOriginalReleaseRegion() async throws {
        var selected: [UUID] = [], boundaries: [RiftSelectionBoundary] = []
        let panel = try controller(onBoundary: { boundaries.append($0) }, onSelect: { selected.append($0) })
        defer { panel.close() }
        let input = records(3); panel.render(input)
        let started = swallowed(input[0]); panel.render([started, input[1], input[2]])
        try await eventually { panel.diagnosticSnapshot.rows.count == 2 && panel.diagnosticSnapshot.isTransitioning }
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == input[1].id })
        let native = try window(row.imageInputWindowNumber), view = try XCTUnwrap(native.contentView)
        let originalPoint = CGPoint(x: native.frame.midX, y: native.frame.midY)
        let time = ProcessInfo.processInfo.systemUptime
        view.mouseDown(with: try event(.leftMouseDown, window: native, point: originalPoint, time: time))
        XCTAssertTrue(panel.diagnosticSnapshot.isHolding)
        XCTAssertEqual(boundaries.map(\.assetID), [input[1].id])
        XCTAssertEqual(boundaries.first?.eventUptime, time)
        XCTAssertEqual(boundaries.first?.windowNumber, native.windowNumber)
        let extra = records(1)[0]
        panel.render([started, input[1], input[2], extra])
        XCTAssertFalse(panel.diagnosticSnapshot.rows.contains { $0.assetID == extra.id }, "A new capture cannot replace a held target")
        view.mouseUp(with: try event(.leftMouseUp, window: native, point: originalPoint, time: time + 0.05))
        XCTAssertEqual(selected, [input[1].id], "Reflow interruption must consume the original click exactly once")
        try await eventually { panel.diagnosticSnapshot.rows.contains { $0.assetID == extra.id } }
        XCTAssertFalse(panel.diagnosticSnapshot.isHolding)
    }

    @MainActor func testDigitBoundaryReflowKeepsFixedClippingPlaneUntilOrdinalHandoff() async throws {
        let panel = try controller(); defer { panel.close() }
        let input = records(10); panel.render(input); panel.showLatest()
        // Keep both ordinals 9 and 10 visible even when a partial final page
        // contains only ordinal 10. This test inspects the digit-width handoff.
        panel.showAsset(input[8].id)
        let original = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == input[9].id })
        let removed = try XCTUnwrap(panel.diagnosticSnapshot.rows.first?.assetID)
        XCTAssertNotEqual(removed, input[9].id)
        let changed = input.map { $0.id == removed ? swallowed($0) : $0 }
        panel.render(changed)
        try await eventually {
            !panel.diagnosticSnapshot.rows.contains { $0.assetID == removed } && panel.diagnosticSnapshot.isTransitioning
        }
        for _ in 0..<3 {
            let moving = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == input[9].id })
            XCTAssertEqual(moving.imageClipFrame.maxX, original.imageClipFrame.maxX, accuracy: 0.6,
                "Changing 10 to 9 must not translate the image's occlusion plane horizontally")
            XCTAssertEqual(moving.ordinal, 10, "The old number is retained until the geometric handoff")
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await eventually { !panel.diagnosticSnapshot.isTransitioning }
        let finished = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == input[9].id })
        XCTAssertEqual(finished.ordinal, 9)
        XCTAssertEqual(finished.imageClipFrame.maxX, original.imageClipFrame.maxX, accuracy: 0.6)
    }
}
