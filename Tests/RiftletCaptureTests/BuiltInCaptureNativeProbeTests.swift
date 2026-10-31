import XCTest
import AppKit
import CoreGraphics
import CryptoKit
import Darwin
import RiftletCore
@testable import RiftletCapture

private struct NativeCaptureProbeFailure: Error {
    let code: String
}

@MainActor
private final class NativeCaptureProbePattern: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        let colors: [NSColor] = [.init(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            .init(srgbRed: 0, green: 1, blue: 0, alpha: 1),
            .init(srgbRed: 0, green: 0, blue: 1, alpha: 1), .white]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSBezierPath(rect: CGRect(x: CGFloat(index) * bounds.width / 4, y: 0,
                width: bounds.width / 4, height: bounds.height)).fill()
        }
        let pixel = 1 / max(1, window?.backingScaleFactor ?? 1)
        for column in 0..<Int(bounds.width / pixel) {
            (column.isMultiple(of: 2) ? NSColor.black : .white).setFill()
            for top in [CGFloat(0), 32] {
                NSBezierPath(rect: CGRect(x: CGFloat(column) * pixel,
                    y: bounds.height - top - 16, width: pixel, height: 16)).fill()
            }
        }
    }
}

/// Opt-in CI evidence for the real Apple child -> owned publication -> original
/// readback -> durable private import. No raw images are printed or archived.
/// This is not physical input, production UI self-exclusion or upload evidence.
final class BuiltInCaptureNativeProbeTests: XCTestCase {
    private static let scope = "ACTUAL_APPLE_CAPTURE_PUBLISH_READBACK_PRIVATE_IMPORT_OWNED_SYNTHETIC_FIXTURE"

    private func emit(_ fields: [String: Any]) {
        var record = fields
        record["schemaVersion"] = 1
        record["probe"] = "built-in-native-engine"
        record["scope"] = Self.scope
        record["rawImagesPublished"] = false
        record["pixelColorAcceptance"] = "NOT_GRANTED"
        record["physicalInteractionAcceptance"] = "NOT_RUN"
        record["realUploadAcceptance"] = "NOT_RUN"
        if let bytes = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let text = String(data: bytes, encoding: .utf8) { print(text) }
    }

    private func require(_ condition: Bool, _ code: String) throws {
        // Boolean assertions never interpolate image Data, file paths or an
        // arbitrary NSError into XCTest output, including on a failing runner.
        guard condition else { throw NativeCaptureProbeFailure(code: code) }
    }

    @MainActor
    private func currentDisplays() -> [InteractiveScreenshotDisplay]? {
        let screens = NSScreen.screens
        let displays = screens.compactMap { screen -> InteractiveScreenshotDisplay? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return .init(id: id, frame: screen.frame, quartzFrame: CGDisplayBounds(id), scale: screen.backingScaleFactor)
        }
        return !displays.isEmpty && displays.count == screens.count ? displays : nil
    }

    @MainActor
    private func rejection(window: NSWindow, expectedFrame: CGRect, expectedQuartz: CGRect,
                           target: CGRect, topology: [InteractiveScreenshotDisplay]) -> String? {
        guard CGPreflightScreenCaptureAccess() else { return "SCREEN_CAPTURE_PERMISSION_NOT_ALREADY_GRANTED" }
        guard let current = currentDisplays(), InteractiveScreenshotGeometry.sameTopology(topology, current) else {
            return "DISPLAY_CONFIGURATION_CHANGED"
        }
        guard window.isVisible, window.isOpaque, window.alphaValue == 1,
              window.contentView?.isOpaque == true, window.frame == expectedFrame,
              expectedQuartz.contains(target) else { return "OWN_FIXTURE_DOES_NOT_COVER_REQUEST" }
        guard let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return "WINDOWSERVER_LIST_UNAVAILABLE"
        }
        for row in rows {
            // Unknown front-to-back entries fail closed. No foreign title,
            // geometry, PID or WindowServer dictionary is ever serialized.
            guard let alpha = (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha.isFinite, alpha >= 0, alpha <= 1 else { return "WINDOWSERVER_ENTRY_UNVERIFIABLE" }
            if alpha == 0 { continue }
            guard let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  InteractiveScreenshotGeometry.isUsable(rect) else { return "WINDOWSERVER_ENTRY_UNVERIFIABLE" }
            if !rect.intersects(target) { continue }
            guard let number = (row[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else {
                return "WINDOWSERVER_ENTRY_UNVERIFIABLE"
            }
            guard number == window.windowNumber, pid == getpid() else { return "FOREIGN_OVERLAP_VETO" }
            guard alpha == 1, rect == expectedQuartz, rect.contains(target) else {
                return "OWN_WINDOWSERVER_BOUNDS_CHANGED"
            }
            return nil
        }
        return "OWN_FIXTURE_NOT_ON_SCREEN"
    }

    @MainActor
    func testActualAppleCapturePublicationAndPrivateImport() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RIFTLET_REAL_CAPTURE_FIXTURE"] == "1" else {
            emit(["event": "summary", "status": "NOT_RUN", "reason": "EXPLICIT_CI_OPT_IN_REQUIRED", "completedModes": [String]()])
            throw XCTSkip("Actual capture requires both explicit CI environment flags")
        }
        guard CGPreflightScreenCaptureAccess() else {
            emit(["event": "summary", "status": "NOT_RUN", "reason": "SCREEN_CAPTURE_PERMISSION_NOT_ALREADY_GRANTED", "completedModes": [String]()])
            throw XCTSkip("Screen capture permission is not already granted; no permission was requested")
        }
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.accessory)
        defer { app.setActivationPolicy(previousPolicy) }
        guard let topology = currentDisplays(), let display = topology.first,
              let primary = topology.first(where: { $0.id == CGMainDisplayID() }),
              display.scale.isFinite, display.scale > 0,
              display.frame.width >= 256, display.frame.height >= 224,
              display.quartzFrame == display.quartzFrame.integral,
              display.quartzFrame.width * display.scale <= 8_192,
              display.quartzFrame.height * display.scale <= 8_192,
              display.quartzFrame.width * display.quartzFrame.height * display.scale * display.scale <= 16_000_000 else {
            emit(["event": "summary", "status": "NOT_RUN", "reason": "DISPLAY_UNAVAILABLE_OR_OUTSIDE_FIXTURE_BUDGET", "completedModes": [String]()])
            throw XCTSkip("No bounded display available for the owned fixture")
        }
        // Use the entire display frame, never visibleFrame. A menu bar, Dock,
        // overlay, Space change or constrained panel must still pass the guards.
        let window = NSPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isOpaque = true; window.backgroundColor = .white; window.hasShadow = false
        window.level = .screenSaver; window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false; window.animationBehavior = .none
        window.contentView = NativeCaptureProbePattern(frame: CGRect(origin: .zero, size: display.frame.size))
        window.setFrame(display.frame, display: false)
        window.orderFrontRegardless(); window.displayIfNeeded()
        defer { window.close() }
        try await Task.sleep(nanoseconds: 250_000_000)
        let ownFrame = window.frame
        let ownQuartz = InteractiveScreenshotGeometry.quartzRect(fromAppKit: ownFrame, primaryScreenTop: primary.frame.maxY)
        let regionQuartz = CGRect(x: ownQuartz.minX + 32, y: ownQuartz.minY + 32, width: 128, height: 96)
        let regionFrame = InteractiveScreenshotGeometry.appKitRect(fromQuartz: regionQuartz, primaryScreenTop: primary.frame.maxY)
        guard InteractiveScreenshotGeometry.isUsable(ownQuartz),
              ownQuartz.insetBy(dx: 16, dy: 16).contains(regionQuartz),
              regionQuartz == regionQuartz.integral else {
            emit(["event": "summary", "status": "NOT_RUN", "reason": "OWN_FIXTURE_GEOMETRY_UNAVAILABLE", "completedModes": [String]()])
            throw XCTSkip("The owned fixture cannot contain the bounded region")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-native-probe-" + UUID().uuidString, isDirectory: true)
        var ownsRoot = false
        defer { if ownsRoot { try? FileManager.default.removeItem(at: root) } }
        var completed: [String] = [], rejected: [String] = []
        var phase = "TEMPORARY_STORE_SETUP", activeMode = "none"
        var service: CaptureService?
        let capturer = InteractiveScreenshotSystemCapture()
        defer { capturer.cancel() }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            ownsRoot = true
            let captures = root.appendingPathComponent("captures", isDirectory: true)
            try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let database = root.appendingPathComponent("queue.sqlite")
            let store = try QueueStore(databaseURL: database)
            let importer = PrivateAssetImporter(privateRoot: root, store: store)
            let collector = CaptureService(store: store, privateRoot: root, sourceDirectory: captures)
            service = collector
            try await collector.start()
            let modes: [(ScreenshotMode, CGRect, CGRect)] = [
                (.window, ownFrame, ownQuartz), (.region, regionFrame, regionQuartz),
                (.fullScreen, display.frame, display.quartzFrame)]
            for (mode, appKitRect, quartzRect) in modes {
                activeMode = mode.rawValue
                if let reason = rejection(window: window, expectedFrame: ownFrame, expectedQuartz: ownQuartz,
                                          target: quartzRect, topology: topology) {
                    rejected.append(mode.rawValue)
                    emit(["event": "mode", "mode": mode.rawValue, "status": "NOT_RUN", "reason": reason,
                          "phase": "BEFORE_CAPTURE", "completedModes": completed])
                    continue
                }
                let selectedWindow = mode == .window ? InteractiveScreenshotWindow(id: UInt32(window.windowNumber), ownerPID: getpid(), rect: ownFrame) : nil
                let request = InteractiveScreenshotRequest(id: UUID(), sessionID: UUID(), mode: mode, options: .init(),
                    target: .init(rect: appKitRect, quartzRect: quartzRect, displays: [display], window: selectedWindow, topology: topology))
                phase = "APPLE_CAPTURE_PUBLISH_READBACK"
                let captureStart = ProcessInfo.processInfo.systemUptime
                let file = try await capturer.capture(request, outputDirectory: captures)
                let captureMS = (ProcessInfo.processInfo.systemUptime - captureStart) * 1_000
                if let reason = rejection(window: window, expectedFrame: ownFrame, expectedQuartz: ownQuartz,
                                          target: quartzRect, topology: topology) {
                    rejected.append(mode.rawValue)
                    emit(["event": "mode", "mode": mode.rawValue, "status": "NOT_RUN", "reason": reason,
                          "phase": "AFTER_CAPTURE_BEFORE_IMPORT_OR_METADATA", "engineReturned": true, "completedModes": completed])
                    continue
                }
                phase = "ORIGINAL_AND_COLLECTOR_VERIFICATION"
                let verificationStart = ProcessInfo.processInfo.systemUptime
                var info = stat()
                try require(lstat(file.sourceURL.path, &info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                    && info.st_uid == geteuid() && info.st_mode & 0o777 == 0o600, "FINAL_ORIGINAL_NOT_PRIVATE_REGULAR_FILE")
                try require(file.sourceURL.deletingLastPathComponent().standardizedFileURL == captures.standardizedFileURL
                    && file.sourceURL.lastPathComponent.hasPrefix("."), "FINAL_ORIGINAL_NOT_HIDDEN_IN_CAPTURE_ROOT")
                let original = try Data(contentsOf: file.sourceURL)
                try require(original == file.data, "ENGINE_READBACK_DIFFERS_FROM_FINAL_ORIGINAL")
                let visible = try FileManager.default.contentsOfDirectory(at: captures,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                try require(visible.isEmpty, "SYSTEM_ENUMERATION_EXPOSED_OWNED_CAPTURE")
                try await collector.rescan()
                let beforeImport = try await store.assets(includeUsed: true)
                try require(beforeImport.count == completed.count && beforeImport.allSatisfy { $0.image.origin == .applicationScreenshot },
                            "SYSTEM_COLLECTOR_IMPORTED_OWNED_CAPTURE")
                if mode != .window {
                    try require(file.pixelWidth == Int(quartzRect.width * display.scale)
                        && file.pixelHeight == Int(quartzRect.height * display.scale), "NATIVE_SCALE_DIMENSIONS_MISMATCH")
                }
                let beforeImportMS = (ProcessInfo.processInfo.systemUptime - verificationStart) * 1_000
                phase = "DURABLE_PRIVATE_IMPORT"
                let importStart = ProcessInfo.processInfo.systemUptime
                let record = try await importer.importBuiltInScreenshot(original: file.sourceURL, outputDirectory: captures)
                let importMS = (ProcessInfo.processInfo.systemUptime - importStart) * 1_000
                phase = "PRIVATE_BYTES_AND_PROVENANCE_VERIFICATION"
                let media = root.appendingPathComponent("media", isDirectory: true).appendingPathComponent(record.image.fileName)
                let privateBytes = try Data(contentsOf: media)
                let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
                try require(privateBytes == original && file.data == privateBytes, "PRIVATE_COPY_DIFFERS_FROM_ORIGINAL")
                try require(record.image.origin == .applicationScreenshot && record.image.sha256 == digest,
                            "PRIVATE_IMPORT_PROVENANCE_OR_HASH_MISMATCH")
                let persisted = try await store.asset(id: record.id)
                try require(persisted?.image.origin == .applicationScreenshot, "PERSISTED_ORIGIN_NOT_APPLICATION_SCREENSHOT")
                let repeated = try await importer.importBuiltInScreenshot(original: file.sourceURL, outputDirectory: captures)
                try require(repeated.id == record.id && repeated.image.origin == .applicationScreenshot, "REIMPORT_CHANGED_ID_OR_ORIGIN")
                completed.append(mode.rawValue)
                emit(["event": "mode", "mode": mode.rawValue, "status": "PASS", "pixelWidth": file.pixelWidth,
                    "pixelHeight": file.pixelHeight, "displayScale": Double(display.scale), "rawPNGBytes": original.count,
                    "rawPNGSHA256": digest, "hasSystemScreenshotMetadata": file.hasSystemScreenshotMetadata,
                    "origin": record.image.origin.rawValue, "originalEqualsPrivateCopy": true, "finalOriginalHidden": true,
                    "ordinaryCollectorExcluded": true, "reimportDeduplicated": true,
                    "capturePublishReadbackMS": captureMS, "originalVerificationMS": beforeImportMS, "privateImportMS": importMS,
                    "completedModes": completed])
            }
            phase = "FINAL_COLLECTOR_AND_REOPEN_VERIFICATION"
            try await collector.rescan()
            await collector.stop(); service = nil
            let reopened = try QueueStore(databaseURL: database)
            let rows = try await reopened.assets(includeUsed: true)
            try require(rows.count == completed.count && rows.allSatisfy { $0.image.origin == .applicationScreenshot },
                        "REOPENED_QUEUE_CONTAINS_UNEXPECTED_SOURCE_OR_COUNT")
        } catch {
            if let service { await service.stop() }
            emit(["event": "failure", "status": "FAIL", "mode": activeMode, "phase": phase,
                  "code": (error as? NativeCaptureProbeFailure)?.code ?? "ACTUAL_OPERATION_FAILED", "completedModes": completed])
            // Do not turn an Apple process, publication, readback, import or
            // persistence error into an environmental skip or print its path.
            throw NativeCaptureProbeFailure(code: (error as? NativeCaptureProbeFailure)?.code ?? "ACTUAL_OPERATION_FAILED")
        }
        emit(["event": "summary", "status": completed.isEmpty ? "NOT_RUN" : rejected.isEmpty ? "PASS" : "PARTIAL",
              "completedModes": completed, "notRunModes": rejected, "connectedDisplayCount": topology.count,
              "displayScale": Double(display.scale), "selectedDisplayPointWidth": Double(display.quartzFrame.width),
              "selectedDisplayPointHeight": Double(display.quartzFrame.height)])
        if completed.isEmpty { throw XCTSkip("No capture mode had a fully verified, unoccluded owned fixture") }
    }
}
