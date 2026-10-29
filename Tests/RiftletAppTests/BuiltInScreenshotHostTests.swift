import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
import RiftletCore
import RiftletUI
import RiftletAdapters
@testable import RiftletCapture
@testable import RiftletApp

/// AppKit + real temporary SQLite/files; capture/permission are injected.
/// These are not physical screenshot, TCC or ChatGPT upload acceptance.
@MainActor
private final class HostPermissionFixture: InteractiveScreenshotPermissionChecking {
    var checks = 0, requests = 0
    func hasAccess() -> Bool { checks += 1; return true }
    func requestAccess() -> Bool { requests += 1; return false }
}

@MainActor
private final class HostCaptureFixture: InteractiveScreenshotCapturing {
    var onRequest: (() -> Void)?
    var pending: [CheckedContinuation<InteractiveScreenshotFile, Error>] = []
    var cancellations = 0
    func capture(_ request: InteractiveScreenshotRequest, outputDirectory: URL) async throws -> InteractiveScreenshotFile {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation); onRequest?()
        }
    }
    func cancel() { cancellations += 1 }
    func complete(_ file: InteractiveScreenshotFile) { pending.removeFirst().resume(returning: file) }
}

final class BuiltInScreenshotHostTests: XCTestCase {
    @MainActor
    private func prepare() throws -> URL {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("No AppKit display; software host checks only") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-builtin-host-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor
    private func engine(root: URL, permission: HostPermissionFixture, capturer: HostCaptureFixture)
        -> (InteractiveScreenshotController, InteractiveScreenshotTarget) {
        let display = InteractiveScreenshotDisplay(id: 7, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            quartzFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let controller = InteractiveScreenshotController(outputDirectory: root.appendingPathComponent("captures"),
            permission: permission, capturer: capturer, displays: { [display] }, windows: { [] }, presentsPanels: false)
        return (controller, .init(rect: display.frame, quartzRect: display.quartzFrame, displays: [display], window: nil))
    }

    private func pngFile(root: URL) throws -> InteractiveScreenshotFile {
        let directory = root.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString + ".png")
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 24, height: 12, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 24, height: 12))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return .init(sourceURL: url, data: try Data(contentsOf: url), pixelWidth: 24, pixelHeight: 12,
                     hasSystemScreenshotMetadata: true) // Deliberate counterfactual; must not grant system origin.
    }

    @MainActor
    func testPersistedOffNeverObservesOrRequestsPermissionAndIndependentStoreFlagsSurvive() async throws {
        let root = try prepare(); defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("capture-entry-settings.json")
        try ScreenshotEntryPreferences(defaultMode: .region, builtInScreenshotEnabled: false).save(to: settings)
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        try await store.setCapturePaused(true); try await store.setUserHidden(true)
        let rift = RiftPanelController(mediaDirectory: root.appendingPathComponent("media"), onSelect: { _ in })
        let permission = HostPermissionFixture(), capturer = HostCaptureFixture()
        let (capture, _) = engine(root: root, permission: permission, capturer: capturer)
        let host = try ScreenshotEntryHost(root: root, store: store, rift: rift, onChange: {}, onIssue: { _ in }, captureController: capture)
        defer { host.close(); rift.close() }
        host.beginFromMenu(); capture.start(mode: .region)
        host.configure(); host.setHidden(true); host.setHidden(false)
        capture.onCaptureVisibilityChanged?(true)
        XCTAssertFalse(host.isEnabled); XCTAssertFalse(capture.isActive)
        XCTAssertFalse(host.entry.isExpanded)
        XCTAssertEqual(host.entry.diagnosticSnapshot.pointerMonitorCount, 0)
        XCTAssertFalse(host.entry.diagnosticSnapshot.hasScheduledFrame)
        XCTAssertFalse(host.entry.diagnosticSnapshot.isCaptureSuppressed)
        XCTAssertEqual(permission.checks, 0); XCTAssertEqual(permission.requests, 0)
        let paused = try await store.capturePaused(), hidden = try await store.userHidden()
        XCTAssertTrue(paused); XCTAssertTrue(hidden)
        host.setEnabled(true)
        XCTAssertTrue(host.isEnabled); XCTAssertFalse(capture.isActive, "Enabling alone must not request capture")
        XCTAssertEqual(permission.checks, 0)
        host.beginFromMenu(); XCTAssertTrue(capture.isActive)
        host.setEnabled(false)
        XCTAssertFalse(capture.isActive); XCTAssertFalse(host.entry.isExpanded)
        XCTAssertFalse(try ScreenshotEntryPreferences.load(from: settings).builtInScreenshotEnabled)
        XCTAssertEqual(try ScreenshotEntryPreferences.load(from: settings).defaultMode, .region)
        let reopened = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let reopenedPaused = try await reopened.capturePaused(), reopenedHidden = try await reopened.userHidden()
        XCTAssertTrue(reopenedPaused); XCTAssertTrue(reopenedHidden)
    }

    @MainActor
    func testDisableDuringExposureDropsLateResultAndReenableRequiresFreshCapture() async throws {
        let root = try prepare(); defer { try? FileManager.default.removeItem(at: root) }
        try ScreenshotEntryPreferences(defaultMode: .region).save(to: root.appendingPathComponent("capture-entry-settings.json"))
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let rift = RiftPanelController(mediaDirectory: root.appendingPathComponent("media"), onSelect: { _ in })
        let permission = HostPermissionFixture(), capturer = HostCaptureFixture()
        let (capture, target) = engine(root: root, permission: permission, capturer: capturer)
        let imported = expectation(description: "fresh screenshot durably imported")
        let host = try ScreenshotEntryHost(root: root, store: store, rift: rift,
            onChange: { imported.fulfill() }, onIssue: { XCTFail($0) }, captureController: capture)
        defer { host.close(); rift.close() }
        let began = expectation(description: "first exposure started")
        capturer.onRequest = { began.fulfill() }
        host.beginFromMenu(); capture.submitSelection(target)
        await fulfillment(of: [began], timeout: 2)
        let cancelled = try pngFile(root: root)
        host.setEnabled(false); host.setEnabled(true)
        XCTAssertFalse(capture.isActive); XCTAssertFalse(host.entry.isExpanded)
        capturer.complete(cancelled)
        for _ in 0..<20 { await Task.yield() }
        let before = try await store.assets(includeUsed: true)
        XCTAssertTrue(before.isEmpty)
        XCTAssertEqual(try Data(contentsOf: cancelled.sourceURL), cancelled.data, "Completed original is never deleted by disable")

        let second = expectation(description: "fresh exposure started")
        capturer.onRequest = { second.fulfill() }
        host.beginFromMenu(); capture.submitSelection(target)
        await fulfillment(of: [second], timeout: 2)
        let fresh = try pngFile(root: root); capturer.complete(fresh)
        await fulfillment(of: [imported], timeout: 3)
        let records = try await store.assets(includeUsed: true)
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records.first?.image.origin, .applicationScreenshot)
        XCTAssertEqual(try Data(contentsOf: fresh.sourceURL), fresh.data)
        let name = try XCTUnwrap(records.first?.image.fileName)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("media").appendingPathComponent(name)), fresh.data)
        XCTAssertTrue(host.entry.isExpanded); XCTAssertTrue(capture.isActive)
        XCTAssertEqual(host.entry.mode, .region)
        host.cancel() // Same boundary used before opening unified Settings.
        XCTAssertFalse(capture.isActive); XCTAssertFalse(host.entry.isExpanded)
        XCTAssertTrue(host.isEnabled, "An explicit settings visit cancels the session, not the feature")
    }

    @MainActor
    func testPersistenceFailureDisablesImmediatelyAndCannotUnsafelyReenable() throws {
        let root = try prepare(); defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("capture-entry-settings.json")
        try ScreenshotEntryPreferences(defaultMode: .region).save(to: settings)
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let rift = RiftPanelController(mediaDirectory: root.appendingPathComponent("media"), onSelect: { _ in })
        let permission = HostPermissionFixture(), capturer = HostCaptureFixture()
        let (capture, _) = engine(root: root, permission: permission, capturer: capturer)
        var failWrite = true, issues: [String] = []
        let host = try ScreenshotEntryHost(root: root, store: store, rift: rift, onChange: {},
            onIssue: { issues.append($0) }, captureController: capture,
            savePreferences: { value, url in
                if failWrite { throw CocoaError(.fileWriteOutOfSpace) }
                try value.save(to: url)
            })
        defer { host.close(); rift.close() }
        host.beginFromMenu(); XCTAssertTrue(capture.isActive)
        host.setEnabled(false)
        XCTAssertFalse(host.isEnabled); XCTAssertFalse(capture.isActive)
        XCTAssertTrue(host.preferenceSaveFailed)
        host.setEnabled(true); host.beginFromMenu()
        XCTAssertFalse(host.isEnabled); XCTAssertFalse(capture.isActive)
        XCTAssertEqual(issues.count, 2)
        failWrite = false; host.setEnabled(false)
        XCTAssertFalse(host.preferenceSaveFailed)
        XCTAssertFalse(try ScreenshotEntryPreferences.load(from: settings).builtInScreenshotEnabled)
        host.setEnabled(true); XCTAssertTrue(host.isEnabled)
        XCTAssertFalse(capture.isActive)
    }

    func testUnsupportedSourceHasHonestLocalOnlyFeedback() {
        XCTAssertEqual(ProductStatus.clickIssue(SystemScreenshotInputError.systemScreenshotsOnly,
            frontmostBundleID: "com.google.Chrome", webAcceptance: true), .attachmentSource)
    }
}
