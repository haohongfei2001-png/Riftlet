import XCTest
import AppKit
import CoreGraphics
import CryptoKit
import ImageIO
import Darwin
import RiftletCore
@testable import RiftletCapture

private struct NativeCaptureProbeFailure: Error { let code: String }

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

@MainActor
private final class NativeCaptureProbeEvidence {
    private let source: String
    private let checkout: String
    private var directory: URL?
    private var events: [[String: Any]] = []
    private var outcome = "NOT_RUN"
    private var details: [String: Any] = [:]
    var attempts = 0
    var invocations = 0
    var returned = 0
    var preGuard = false
    var postGuard = false
    var pixelPattern = false
    var originalPublished = false

    init(environment: [String: String]) {
        func sha(_ key: String) -> String {
            guard let value = environment[key], value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
                return "UNAVAILABLE"
            }
            return value
        }
        source = sha("RIFTLET_BUILD_HEAD_SHA"); checkout = sha("GITHUB_SHA")
    }

    func prepare(environment: [String: String]) throws {
        guard source != "UNAVAILABLE", checkout != "UNAVAILABLE",
              let path = environment["GITHUB_WORKSPACE"], path.hasPrefix("/") else {
            throw NativeCaptureProbeFailure(code: "EXACT_CI_SOURCE_OR_WORKSPACE_UNAVAILABLE")
        }
        let workspace = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard workspace.resolvingSymlinksInPath() == workspace else {
            throw NativeCaptureProbeFailure(code: "EVIDENCE_WORKSPACE_NOT_CANONICAL")
        }
        let parent = workspace.appendingPathComponent("test-results", isDirectory: true)
        var info = stat()
        guard lstat(parent.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == geteuid() else { throw NativeCaptureProbeFailure(code: "EVIDENCE_PARENT_UNAVAILABLE") }
        let output = parent.appendingPathComponent("builtin-capture-component", isDirectory: true)
        // A second invocation cannot silently overwrite the first run's evidence.
        guard mkdir(output.path, 0o700) == 0 else { throw NativeCaptureProbeFailure(code: "EVIDENCE_DIRECTORY_ALREADY_EXISTS_OR_UNAVAILABLE") }
        directory = output
    }

    private func base() -> [String: Any] {
        ["schemaVersion": 1, "probe": "built-in-native-engine",
         "scope": "ACTUAL_APPLE_REGION_CAPTURE_PUBLISH_READBACK_PRIVATE_IMPORT_OWNED_SYNTHETIC_FIXTURE",
         "sourceSHA": source, "checkoutSHA": checkout, "mode": "region",
         "captureAttemptCount": attempts, "invocationCount": invocations, "engineReturnedCount": returned,
         "maximumInvocations": 1, "preCaptureOwnOpaqueWindowGuard": preGuard,
         "postCaptureOwnOpaqueWindowGuard": postGuard, "everyPixelMatchesSyntheticPattern": pixelPattern,
         "otherApplicationPixels": preGuard && postGuard && pixelPattern ? "NONE_OBSERVED_IN_VERIFIED_PATTERN" :
            invocations == 0 ? "NOT_CAPTURED" : "NOT_VERIFIED_NO_RAW_ARTIFACT_PUBLISHED",
         "guardTemporalScope": "PRE_POST_WINDOWSERVER_AND_COMPLETE_OUTPUT_PATTERN_NOT_CONTINUOUS_OCCLUSION_MONITOR",
         "rawOriginalPublished": originalPublished, "publicRelease": false,
         "pixelColorAcceptance": "NOT_GRANTED", "physicalInteractionAcceptance": "NOT_RUN",
         "guiScreenshotEntryAcceptance": "NOT_RUN", "windowModeAcceptance": "NOT_RUN",
         "fullScreenModeAcceptance": "NOT_RUN", "realUploadAcceptance": "NOT_RUN", "uploadCount": 0]
    }

    func emit(_ event: String, status: String, _ fields: [String: Any] = [:]) {
        var record = base()
        record.merge(fields) { _, new in new }
        record["event"] = event; record["status"] = status
        outcome = status; details.merge(fields) { _, new in new }
        events.append(record)
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }

    func preserveOriginal(_ data: Data) throws {
        guard let directory, preGuard, postGuard, pixelPattern, invocations == 1, returned == 1 else {
            throw NativeCaptureProbeFailure(code: "RAW_ARTIFACT_PRIVACY_PROOF_INCOMPLETE")
        }
        let name = "region-original.png"
        let directoryDescriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryDescriptor >= 0 else { throw NativeCaptureProbeFailure(code: "RAW_ARTIFACT_DIRECTORY_UNAVAILABLE") }
        defer { Darwin.close(directoryDescriptor) }
        details["originalArtifactCandidateFile"] = name
        details["unverifiedOriginalArtifactMayRemain"] = true
        let descriptor = openat(directoryDescriptor, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw NativeCaptureProbeFailure(code: "RAW_ARTIFACT_EXCLUSIVE_CREATE_FAILED") }
        defer { Darwin.close(descriptor) }
        func stillOwnsFile() -> Bool {
            var held = stat(), named = stat()
            return fstat(descriptor, &held) == 0 && fstatat(directoryDescriptor, name, &named, AT_SYMLINK_NOFOLLOW) == 0
                && held.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) && named.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                && held.st_uid == geteuid() && named.st_uid == geteuid()
                && held.st_dev == named.st_dev && held.st_ino == named.st_ino
                && held.st_birthtimespec.tv_sec == named.st_birthtimespec.tv_sec
                && held.st_birthtimespec.tv_nsec == named.st_birthtimespec.tv_nsec
        }
        defer {
            if !originalPublished {
                // Only this exclusive creation is eligible for cleanup. A
                // replaced/unverifiable entry is retained and explicitly
                // reported as a possible unverified artifact, never hidden by
                // rawOriginalPublished=false/originalFile=null.
                if stillOwnsFile(), unlinkat(directoryDescriptor, name, 0) == 0 {
                    details["unverifiedOriginalArtifactMayRemain"] = false
                    details["originalArtifactFailureCleanup"] = "OWNED_FILE_REMOVED"
                } else {
                    details["originalArtifactFailureCleanup"] = "IDENTITY_UNVERIFIABLE_OR_REMOVAL_FAILED_NO_OTHER_FILE_DELETED"
                }
            }
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fchmod(descriptor, 0o600) == 0, fsync(descriptor) == 0 else {
            throw NativeCaptureProbeFailure(code: "RAW_ARTIFACT_WRITE_OR_READBACK_FAILED")
        }
        try handle.seek(toOffset: 0)
        var heldDirectory = stat(), namedDirectory = stat()
        guard try handle.readToEnd() == data, stillOwnsFile(), fsync(directoryDescriptor) == 0,
              fstat(directoryDescriptor, &heldDirectory) == 0, lstat(directory.path, &namedDirectory) == 0,
              namedDirectory.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              heldDirectory.st_dev == namedDirectory.st_dev, heldDirectory.st_ino == namedDirectory.st_ino,
              stillOwnsFile() else { throw NativeCaptureProbeFailure(code: "RAW_ARTIFACT_WRITE_OR_READBACK_FAILED") }
        originalPublished = true
        details["unverifiedOriginalArtifactMayRemain"] = false
    }

    func flush() throws {
        guard let directory else { return }
        var record = base()
        record.merge(details) { _, new in new }
        record["status"] = outcome; record["events"] = events
        if originalPublished { record["originalFile"] = "region-original.png" }
        else { record["originalFile"] = NSNull() }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        let file = directory.appendingPathComponent("capture.json")
        try data.write(to: file, options: .withoutOverwriting)
        guard chmod(file.path, 0o600) == 0 else { throw NativeCaptureProbeFailure(code: "MANIFEST_PERMISSION_FAILED") }
    }
}

/// One optional real region capture; the ordinary parallel suite skips before
/// creating a window. This never requests permission, sends events, touches an
/// existing database or exercises upload. Only verified synthetic original bytes
/// may be retained in this CI run's artifact directory.
final class BuiltInCaptureNativeProbeTests: XCTestCase {
    private func require(_ condition: Bool, _ code: String) throws {
        guard condition else { throw NativeCaptureProbeFailure(code: code) }
    }

    @MainActor
    private func currentDisplays() -> [InteractiveScreenshotDisplay]? {
        let screens = NSScreen.screens
        let displays = screens.compactMap { screen -> InteractiveScreenshotDisplay? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return .init(id: id, frame: screen.frame, quartzFrame: CGDisplayBounds(id), scale: screen.backingScaleFactor)
        }
        return !displays.isEmpty && displays.count == screens.count && Set(displays.map(\.id)).count == displays.count ? displays : nil
    }

    @MainActor
    private func rejection(window: NSWindow, expectedFrame: CGRect, expectedQuartz: CGRect,
                           target: CGRect, topology: [InteractiveScreenshotDisplay]) -> String? {
        guard CGPreflightScreenCaptureAccess() else { return "SCREEN_CAPTURE_PERMISSION_NOT_ALREADY_GRANTED" }
        guard let current = currentDisplays(), topology.sorted(by: { $0.id < $1.id }) == current.sorted(by: { $0.id < $1.id }) else {
            return "DISPLAY_CONFIGURATION_CHANGED"
        }
        guard window.isVisible, window.isOpaque, window.alphaValue == 1,
              window.contentView?.isOpaque == true, window.frame == expectedFrame,
              expectedQuartz.contains(target) else { return "OWN_FIXTURE_DOES_NOT_COVER_REQUEST" }
        guard let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return "WINDOWSERVER_LIST_UNAVAILABLE"
        }
        for row in rows {
            // Only bounds/ownership needed to veto occlusion are read. Never
            // serialize foreign titles, IDs, geometry or WindowServer records.
            guard let alpha = (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha.isFinite, alpha >= 0, alpha <= 1 else { return "WINDOWSERVER_ENTRY_UNVERIFIABLE" }
            if alpha == 0 { continue }
            guard let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  InteractiveScreenshotGeometry.isUsable(rect) else { return "WINDOWSERVER_ENTRY_UNVERIFIABLE" }
            if !rect.intersects(target) { continue }
            guard let number = (row[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return "WINDOWSERVER_ENTRY_UNVERIFIABLE" }
            guard number == window.windowNumber, pid == getpid() else { return "FOREIGN_OVERLAP_VETO" }
            guard alpha == 1, rect == expectedQuartz, rect.contains(target) else { return "OWN_WINDOWSERVER_BOUNDS_CHANGED" }
            return nil
        }
        return "OWN_FIXTURE_NOT_ON_SCREEN"
    }

    /// Exact pattern-position verification is only an artifact privacy guard.
    /// Both bitmap row conventions are accepted; no colors/bytes are rewritten,
    /// and this does not grant color fidelity, HDR or human visual acceptance.
    private func verifyPattern(_ data: Data, width: Int, height: Int, scale: CGFloat,
                               displayWidth: CGFloat) throws -> String {
        guard width > 0, height > 0, width <= 1024, height <= 768,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width, image.height == height,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw NativeCaptureProbeFailure(code: "PATTERN_IMAGE_UNVERIFIABLE")
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw NativeCaptureProbeFailure(code: "PATTERN_BITMAP_UNAVAILABLE") }
        let bands: [[Int]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]]
        func matches(flipped: Bool) -> Bool {
            for y in 0..<height {
                let row = flipped ? height - 1 - y : y
                let top = 32 + (CGFloat(row) + 0.5) / scale
                for x in 0..<width {
                    let left = 32 + (CGFloat(x) + 0.5) / scale
                    let expected: [Int]
                    if (0..<CGFloat(16)).contains(top) || (32..<CGFloat(48)).contains(top) {
                        expected = Int(floor(left * scale)).isMultiple(of: 2) ? [0, 0, 0] : [255, 255, 255]
                    } else {
                        expected = bands[min(3, max(0, Int(floor(left / (displayWidth / 4)))))]
                    }
                    let index = (y * width + x) * 4
                    guard pixels[index + 3] == 255 else { return false }
                    for channel in 0..<3 where abs(Int(pixels[index + channel]) - expected[channel]) > 8 { return false }
                }
            }
            return true
        }
        if matches(flipped: false) { return "TOP_TO_BOTTOM" }
        if matches(flipped: true) { return "BOTTOM_TO_TOP" }
        throw NativeCaptureProbeFailure(code: "OUTPUT_DOES_NOT_MATCH_OWN_SYNTHETIC_PATTERN")
    }

    @MainActor
    func testActualAppleCapturePublicationAndPrivateImport() async throws {
        let environment = ProcessInfo.processInfo.environment
        let evidence = NativeCaptureProbeEvidence(environment: environment)
        guard environment["GITHUB_ACTIONS"] == "true", environment["RIFTLET_REAL_CAPTURE_FIXTURE"] == "1" else {
            evidence.emit("summary", status: "NOT_RUN", ["reason": "EXPLICIT_CI_OPT_IN_REQUIRED"])
            throw XCTSkip("Actual capture requires explicit CI opt-in; no window or capture was created")
        }
        do { try evidence.prepare(environment: environment) }
        catch {
            evidence.emit("failure", status: "FAIL", ["code": (error as? NativeCaptureProbeFailure)?.code ?? "EVIDENCE_SETUP_FAILED"])
            throw NativeCaptureProbeFailure(code: "EVIDENCE_SETUP_FAILED")
        }
        defer {
            do { try evidence.flush() }
            catch { XCTFail("Sanitized component manifest could not be saved") }
        }
        guard CGPreflightScreenCaptureAccess() else {
            evidence.emit("summary", status: "NOT_RUN", ["reason": "SCREEN_CAPTURE_PERMISSION_NOT_ALREADY_GRANTED"])
            throw XCTSkip("Screen capture permission was not already granted; no permission was requested")
        }
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.accessory)
        defer { app.setActivationPolicy(previousPolicy) }
        guard let topology = currentDisplays(), let display = topology.first,
              let primary = topology.first(where: { $0.id == CGMainDisplayID() }),
              display.scale == 1 || display.scale == 2,
              display.frame.width >= 256, display.frame.height >= 224,
              display.quartzFrame == display.quartzFrame.integral,
              display.quartzFrame.width * display.scale <= 8192,
              display.quartzFrame.height * display.scale <= 8192,
              display.quartzFrame.width * display.quartzFrame.height * display.scale * display.scale <= 16_000_000 else {
            evidence.emit("summary", status: "NOT_RUN", ["reason": "DISPLAY_UNAVAILABLE_OR_OUTSIDE_FIXTURE_BUDGET"])
            throw XCTSkip("No bounded 1x/2x display available for the owned fixture")
        }
        let window = NSPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        guard InteractiveScreenshotGeometry.isUsable(ownQuartz), ownQuartz.insetBy(dx: 16, dy: 16).contains(regionQuartz),
              regionQuartz == regionQuartz.integral else {
            evidence.emit("summary", status: "NOT_RUN", ["reason": "OWN_FIXTURE_GEOMETRY_UNAVAILABLE"])
            throw XCTSkip("The owned fixture cannot contain the bounded region")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-native-probe-" + UUID().uuidString, isDirectory: true)
        var ownsRoot = false
        defer { if ownsRoot { try? FileManager.default.removeItem(at: root) } }
        var phase = "TEMPORARY_STORE_SETUP"
        var service: CaptureService?
        let capturer = InteractiveScreenshotSystemCapture(onProcessStarted: {
            evidence.invocations += 1
            evidence.emit("appleProcessStarted", status: "IN_PROGRESS")
        })
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
            if let reason = rejection(window: window, expectedFrame: ownFrame, expectedQuartz: ownQuartz,
                                      target: regionQuartz, topology: topology) {
                await collector.stop(); service = nil
                evidence.emit("summary", status: "NOT_RUN", ["reason": reason, "phase": "BEFORE_CAPTURE"])
                throw XCTSkip("Own-window privacy guard prevented the single capture")
            }
            evidence.preGuard = true
            let request = InteractiveScreenshotRequest(id: UUID(), sessionID: UUID(), mode: .region, options: .init(),
                target: .init(rect: regionFrame, quartzRect: regionQuartz, displays: [display], window: nil))
            phase = "APPLE_CAPTURE_PUBLISH_READBACK"
            evidence.attempts += 1
            let captureStart = ProcessInfo.processInfo.systemUptime
            let file = try await capturer.capture(request, outputDirectory: captures)
            evidence.returned += 1
            let captureMS = (ProcessInfo.processInfo.systemUptime - captureStart) * 1000
            if let reason = rejection(window: window, expectedFrame: ownFrame, expectedQuartz: ownQuartz,
                                      target: regionQuartz, topology: topology) {
                await collector.stop(); service = nil
                evidence.emit("summary", status: "NOT_RUN", ["reason": reason, "phase": "AFTER_CAPTURE_BEFORE_IMPORT_OR_ARTIFACT"])
                throw XCTSkip("Post-capture privacy guard rejected evidence; the invocation remains recorded")
            }
            evidence.postGuard = true
            phase = "ORIGINAL_AND_PATTERN_VERIFICATION"
            var info = stat()
            try require(lstat(file.sourceURL.path, &info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                && info.st_uid == geteuid() && info.st_mode & 0o777 == 0o600, "FINAL_ORIGINAL_NOT_PRIVATE_REGULAR_FILE")
            try require(file.sourceURL.deletingLastPathComponent().standardizedFileURL == captures.standardizedFileURL
                && file.sourceURL.lastPathComponent.hasPrefix("."), "FINAL_ORIGINAL_NOT_HIDDEN_IN_CAPTURE_ROOT")
            let original = try Data(contentsOf: file.sourceURL)
            try require(original == file.data, "ENGINE_READBACK_DIFFERS_FROM_FINAL_ORIGINAL")
            try require(file.pixelWidth == Int(regionQuartz.width * display.scale)
                && file.pixelHeight == Int(regionQuartz.height * display.scale), "NATIVE_SCALE_DIMENSIONS_MISMATCH")
            let rowOrder = try verifyPattern(original, width: file.pixelWidth, height: file.pixelHeight,
                scale: display.scale, displayWidth: ownFrame.width)
            evidence.pixelPattern = true
            let visible = try FileManager.default.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            try require(visible.isEmpty, "SYSTEM_ENUMERATION_EXPOSED_OWNED_CAPTURE")
            try await collector.rescan()
            let beforeImport = try await store.assets(includeUsed: true)
            try require(beforeImport.isEmpty, "SYSTEM_COLLECTOR_IMPORTED_OWNED_CAPTURE")
            phase = "DURABLE_PRIVATE_IMPORT"
            let record = try await importer.importBuiltInScreenshot(original: file.sourceURL, outputDirectory: captures)
            let privateBytes = try Data(contentsOf: root.appendingPathComponent("media").appendingPathComponent(record.image.fileName))
            let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
            try require(privateBytes == original, "PRIVATE_COPY_DIFFERS_FROM_ORIGINAL")
            try require(record.image.origin == .applicationScreenshot && record.image.sha256 == digest,
                        "PRIVATE_IMPORT_PROVENANCE_OR_HASH_MISMATCH")
            let repeated = try await importer.importBuiltInScreenshot(original: file.sourceURL, outputDirectory: captures)
            try require(repeated.id == record.id && repeated.image.origin == .applicationScreenshot, "REIMPORT_CHANGED_ID_OR_ORIGIN")
            phase = "FINAL_COLLECTOR_AND_REOPEN_VERIFICATION"
            try await collector.rescan()
            await collector.stop(); service = nil
            let reopened = try QueueStore(databaseURL: database)
            let rows = try await reopened.assets(includeUsed: true)
            try require(rows.count == 1 && rows.first?.image.origin == .applicationScreenshot && rows.first?.id == record.id,
                        "REOPENED_QUEUE_CONTAINS_UNEXPECTED_SOURCE_OR_COUNT")
            try require(evidence.attempts == 1 && evidence.invocations == 1 && evidence.returned == 1, "ACTUAL_CAPTURE_COUNT_MISMATCH")
            phase = "PRESERVE_VERIFIED_ORIGINAL_BYTES"
            try evidence.preserveOriginal(original)
            evidence.emit("summary", status: "PASS", ["pixelWidth": file.pixelWidth, "pixelHeight": file.pixelHeight,
                "displayScale": Double(display.scale), "connectedDisplayCount": topology.count,
                "rawPNGBytes": original.count, "rawPNGSHA256": digest,
                "hasSystemScreenshotMetadata": file.hasSystemScreenshotMetadata, "origin": record.image.origin.rawValue,
                "originalEqualsPrivateCopy": true, "originalReencoded": false, "finalOriginalHidden": true,
                "ordinaryCollectorExcluded": true, "reimportDeduplicated": true, "sqliteReopenVerified": true,
                "patternVerificationRowOrder": rowOrder, "capturePublishReadbackMS": captureMS])
        } catch let skip as XCTSkip {
            if let service { await service.stop() }
            throw skip
        } catch {
            if let service { await service.stop() }
            evidence.emit("failure", status: "FAIL", ["phase": phase,
                "code": (error as? NativeCaptureProbeFailure)?.code ?? "ACTUAL_OPERATION_FAILED"])
            // Apple execution, publication, import and persistence failures are
            // actual failures, never environmental skips or arbitrary log text.
            throw NativeCaptureProbeFailure(code: (error as? NativeCaptureProbeFailure)?.code ?? "ACTUAL_OPERATION_FAILED")
        }
    }
}
