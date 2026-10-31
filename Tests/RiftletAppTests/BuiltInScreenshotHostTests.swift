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
    var requests: [InteractiveScreenshotRequest] = []
    var cancellations = 0
    func capture(_ request: InteractiveScreenshotRequest, outputDirectory: URL) async throws -> InteractiveScreenshotFile {
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
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

    @MainActor
    func testCountdownPresentsFrozenRequestAndNextModeWithoutCreatingAnotherCapture() async throws {
        let root = try prepare(); defer { try? FileManager.default.removeItem(at: root) }
        try ScreenshotEntryPreferences(defaultMode: .region).save(to: root.appendingPathComponent("capture-entry-settings.json"))
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let rift = RiftPanelController(mediaDirectory: root.appendingPathComponent("media"), onSelect: { _ in })
        let permission = HostPermissionFixture(), capturer = HostCaptureFixture()
        let (capture, target) = engine(root: root, permission: permission, capturer: capturer)
        let imported = expectation(description: "first original imported")
        let host = try ScreenshotEntryHost(root: root, store: store, rift: rift,
            onChange: { imported.fulfill() }, onIssue: { XCTFail($0) }, captureController: capture)
        defer { host.close(); rift.close() }
        let countdown = expectation(description: "real five-second countdown projected")
        let hostStateChange = capture.onStateChange
        capture.onStateChange = { state in
            hostStateChange?(state)
            if state == .countdown(5) { countdown.fulfill() }
        }
        host.beginFromMenu()
        host.entry.setOptions(.init(delay: 5)); host.entry.onOptions?(host.entry.options)
        let originalSlots = host.entry.diagnosticSnapshot.controls.map(\.mode)
        let firstBegan = expectation(description: "original confirmed exposure")
        capturer.onRequest = { firstBegan.fulfill() }
        capture.submitSelection(target)
        await fulfillment(of: [countdown], timeout: 2)
        let frozen = try XCTUnwrap(host.entry.capturePresentation)
        XCTAssertEqual(frozen.confirmedMode, .region)
        XCTAssertEqual(frozen.remainingSeconds, 5)
        XCTAssertEqual(host.entry.diagnosticSnapshot.captureStatusText, "已选区域 · 5 秒后拍摄")

        for mode in [ScreenshotMode.window, .fullScreen] {
            host.entry.setMode(mode); host.entry.onMode?(mode)
            let current = try XCTUnwrap(host.entry.capturePresentation)
            XCTAssertEqual(current.sessionID, frozen.sessionID)
            XCTAssertEqual(current.requestID, frozen.requestID)
            XCTAssertEqual(current.confirmedMode, .region)
            XCTAssertEqual(current.nextMode, mode)
            XCTAssertEqual(host.entry.diagnosticSnapshot.controls.map(\.mode), originalSlots)
        }
        XCTAssertEqual(host.entry.diagnosticSnapshot.captureStatusText, "已选区域 · 5 秒后拍摄\n下一张：全屏")
        host.entry.setOptions(.init(delay: 0, showPointer: true))
        host.entry.onOptions?(host.entry.options)
        capture.submitSelection(target) // A second complete gesture cannot create another pending request.
        XCTAssertTrue(capturer.requests.isEmpty)
        XCTAssertEqual(host.entry.capturePresentation?.requestID, frozen.requestID)

        let visual = host.entry.diagnosticSnapshot
        let statusWindow = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == visual.captureStatusWindowNumber })
        XCTAssertTrue(statusWindow.ignoresMouseEvents)
        XCTAssertFalse(statusWindow.canBecomeKey); XCTAssertFalse(statusWindow.canBecomeMain)
        XCTAssertLessThanOrEqual(visual.captureStatusFrame.width, 240)
        XCTAssertTrue(host.entry.captureExclusionWindowIDs.contains(CGWindowID(statusWindow.windowNumber)))
        XCTAssertFalse(visual.controls.contains { $0.frame.intersects(visual.captureStatusFrame) })
        let cancel = try XCTUnwrap(visual.controls.first(where: \.isCancel))
        let cancelView = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == cancel.windowNumber }?.contentView)
        XCTAssertEqual(cancelView.accessibilityLabel(), "结束截图")
        capture.onCaptureVisibilityChanged?(true)
        XCTAssertFalse(statusWindow.isVisible)
        capture.onCaptureVisibilityChanged?(false)
        XCTAssertEqual(host.entry.capturePresentation?.requestID, frozen.requestID)

        await fulfillment(of: [firstBegan], timeout: 7)
        XCTAssertEqual(capturer.requests.count, 1)
        XCTAssertEqual(capturer.requests[0].id, frozen.requestID)
        XCTAssertEqual(capturer.requests[0].mode, .region)
        XCTAssertEqual(capturer.requests[0].options, .init(delay: 5))
        XCTAssertEqual(host.entry.diagnosticSnapshot.captureStatusText, "正在拍摄已选区域\n下一张：全屏")
        capturer.complete(try pngFile(root: root))
        await fulfillment(of: [imported], timeout: 3)
        XCTAssertNil(host.entry.capturePresentation)
        XCTAssertNil(host.entry.diagnosticSnapshot.captureStatusText)
        XCTAssertTrue(capture.isActive); XCTAssertTrue(host.entry.isExpanded)

        let secondBegan = expectation(description: "next explicit selection uses next mode")
        capturer.onRequest = { secondBegan.fulfill() }
        capture.submitSelection(target)
        await fulfillment(of: [secondBegan], timeout: 2)
        XCTAssertEqual(capturer.requests.count, 2)
        XCTAssertEqual(capturer.requests[1].mode, .fullScreen)
        XCTAssertEqual(capturer.requests[1].options, .init(delay: 0, showPointer: true))
        XCTAssertFalse(host.entry.diagnosticSnapshot.captureStatusText?.contains("0 秒") ?? true)
        host.cancel(); host.beginFromMenu()
        XCTAssertNil(host.entry.capturePresentation)
        capturer.complete(try pngFile(root: root)) // Cancelled old completion cannot revive its text or import.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(host.entry.capturePresentation)
        XCTAssertNil(host.entry.diagnosticSnapshot.captureStatusText)
        XCTAssertEqual(capturer.requests.count, 2)
        let saved = try await store.assets(includeUsed: true)
        XCTAssertEqual(saved.count, 1)
    }

    @MainActor
    func testCancelCountdownClearsProjectionAndOldTaskCannotReviveIt() async throws {
        let root = try prepare(); defer { try? FileManager.default.removeItem(at: root) }
        try ScreenshotEntryPreferences(defaultMode: .region).save(to: root.appendingPathComponent("capture-entry-settings.json"))
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let rift = RiftPanelController(mediaDirectory: root.appendingPathComponent("media"), onSelect: { _ in })
        let permission = HostPermissionFixture(), capturer = HostCaptureFixture()
        let (capture, target) = engine(root: root, permission: permission, capturer: capturer)
        let host = try ScreenshotEntryHost(root: root, store: store, rift: rift,
            onChange: { XCTFail("Cancelled countdown must not import") }, onIssue: { XCTFail($0) }, captureController: capture)
        defer { host.close(); rift.close() }
        let countdown = expectation(description: "countdown began")
        let hostStateChange = capture.onStateChange
        capture.onStateChange = { state in
            hostStateChange?(state)
            if state == .countdown(5) { countdown.fulfill() }
        }
        host.beginFromMenu(); capture.updateOptions(.init(delay: 5)); capture.submitSelection(target)
        await fulfillment(of: [countdown], timeout: 2)
        XCTAssertNotNil(host.entry.capturePresentation)
        host.cancel(); host.beginFromMenu()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(capture.isActive)
        XCTAssertNil(host.entry.capturePresentation)
        XCTAssertNil(host.entry.diagnosticSnapshot.captureStatusText)
        XCTAssertTrue(capturer.requests.isEmpty)
        host.setHidden(true)
        XCTAssertNil(host.entry.capturePresentation)
        host.close()
        XCTAssertNil(host.entry.capturePresentation)
    }

    func testUnsupportedSourceHasHonestLocalOnlyFeedback() {
        XCTAssertEqual(ProductStatus.clickIssue(SystemScreenshotInputError.systemScreenshotsOnly,
            frontmostBundleID: "com.google.Chrome", webAcceptance: true), .attachmentSource)
    }
}
