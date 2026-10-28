import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import RiftletCapture

final class InteractiveScreenshotTests: XCTestCase {
    private let main = InteractiveScreenshotDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        quartzFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)

    private func target(window: InteractiveScreenshotWindow? = nil) -> InteractiveScreenshotTarget {
        InteractiveScreenshotTarget(rect: CGRect(x: 100, y: 200, width: 50, height: 40),
            quartzRect: CGRect(x: 100, y: 660, width: 50, height: 40), displays: [main], window: window)
    }

    func testQuartzConversionPreservesNegativeDisplaysAndRoundTrips() {
        let aboveAndLeft = CGRect(x: -1280, y: 900, width: 1280, height: 720)
        let quartz = InteractiveScreenshotGeometry.quartzRect(fromAppKit: aboveAndLeft, primaryScreenTop: 900)
        XCTAssertEqual(quartz, CGRect(x: -1280, y: -720, width: 1280, height: 720))
        XCTAssertEqual(InteractiveScreenshotGeometry.appKitRect(fromQuartz: quartz, primaryScreenTop: 900), aboveAndLeft)
        let below = CGRect(x: 120, y: -800, width: 1024, height: 768)
        XCTAssertEqual(InteractiveScreenshotGeometry.quartzRect(fromAppKit: below, primaryScreenTop: 900),
                       CGRect(x: 120, y: 932, width: 1024, height: 768))
    }

    func testRegionAcrossDisplaysUsesLogicalCoordinatesAndClipsOutsideDesktop() {
        let secondary = InteractiveScreenshotDisplay(id: 2, frame: CGRect(x: -1280, y: 0, width: 1280, height: 720),
            quartzFrame: CGRect(x: -1280, y: 180, width: 1280, height: 720), scale: 1)
        let rect = InteractiveScreenshotGeometry.dragRect(from: CGPoint(x: -1500, y: 50), to: CGPoint(x: 300, y: 600), displays: [main, secondary])
        XCTAssertEqual(rect, CGRect(x: -1280, y: 50, width: 1580, height: 550))
        XCTAssertNil(InteractiveScreenshotGeometry.dragRect(from: .zero, to: .zero, displays: [main]))
        XCTAssertFalse(InteractiveScreenshotGeometry.isUsable(.infinite))
        XCTAssertFalse(InteractiveScreenshotGeometry.isUsable(CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)))
    }

    func testNoninteractiveArgumentsNeverOpenSystemSelectionAndDoNotScaleRetinaPoints() throws {
        var session = InteractiveScreenshotSession()
        session.start(mode: .region, options: .init(showPointer: true))
        let request = try XCTUnwrap(session.beginCapture(target: target()))
        let path = URL(fileURLWithPath: "/tmp/riftlet captures/$(not-a-shell-command).png")
        let args = try InteractiveScreenshotCommand.arguments(for: request, outputURL: path)
        XCTAssertEqual(args, ["-x", "-t", "png", "-C", "-R", "100,660,50,40", path.path])
        XCTAssertFalse(args.contains("-i")); XCTAssertFalse(args.contains("-u"))
        XCTAssertFalse(args.contains("-D"), "Display IDs must not be mistaken for the utility's ordinal")
    }

    func testWindowArgumentsUseFrozenWindowIDInsteadOfScreenRect() throws {
        var session = InteractiveScreenshotSession()
        session.start(mode: .window, options: .init())
        let selected = InteractiveScreenshotWindow(id: 48, ownerPID: 1234, rect: target().rect)
        let request = try XCTUnwrap(session.beginCapture(target: target(window: selected)))
        let args = try InteractiveScreenshotCommand.arguments(for: request, outputURL: URL(fileURLWithPath: "/tmp/window.png"))
        XCTAssertEqual(args, ["-x", "-t", "png", "-l", "48", "/tmp/window.png"])
    }

    func testModeChangeKeepsConfirmedRequestAndSuccessRearmsCurrentMode() throws {
        var session = InteractiveScreenshotSession()
        session.start(mode: .region, options: .init(delay: 5, showPointer: true))
        let request = try XCTUnwrap(session.beginCapture(target: target()))
        session.updateMode(.fullScreen)
        session.updateOptions(.init(delay: 0, showPointer: false, editAfter: true))
        XCTAssertTrue(session.owns(request))
        XCTAssertEqual(request.mode, .region); XCTAssertEqual(request.options.delay, 5)
        XCTAssertTrue(request.options.showPointer); XCTAssertFalse(request.options.editAfter)
        XCTAssertTrue(session.complete(request)); XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.mode, .fullScreen)
        let next = try XCTUnwrap(session.beginCapture(target: target()))
        XCTAssertEqual(next.mode, .fullScreen); XCTAssertTrue(next.options.editAfter)
        XCTAssertNotEqual(next.id, request.id)
    }

    func testCancellationAndRestartRejectOldCompletionWithoutConsumingNewRequest() throws {
        var session = InteractiveScreenshotSession()
        session.start(mode: .region, options: .init())
        let old = try XCTUnwrap(session.beginCapture(target: target()))
        session.cancel(); session.start(mode: .fullScreen, options: .init())
        let current = try XCTUnwrap(session.beginCapture(target: target()))
        XCTAssertFalse(session.complete(old)); XCTAssertTrue(session.owns(current))
        XCTAssertTrue(session.complete(current)); XCTAssertTrue(session.isActive)
    }

    func testSecondSelectionCannotDuplicatePendingCaptureAndOptionsAreBounded() throws {
        var session = InteractiveScreenshotSession()
        session.start(mode: .region, options: .init(delay: .infinity))
        let request = try XCTUnwrap(session.beginCapture(target: target()))
        XCTAssertEqual(request.options.delay, 0)
        XCTAssertNil(session.beginCapture(target: target()))
        XCTAssertEqual(InteractiveScreenshotOptions(delay: -5).normalized.delay, 0)
        XCTAssertEqual(InteractiveScreenshotOptions(delay: 500).normalized.delay, 60)
    }

    private func fixturePNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 19, height: 11, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 19, height: 11))
        let bytes = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return bytes as Data
    }

    func testReadOriginalPreservesBytesAndDoesNotManufactureScreenshotMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-interactive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("fixture.png"), original = try fixturePNG()
        try original.write(to: url)
        let result = try InteractiveScreenshotSystemCapture.readOriginal(at: url)
        XCTAssertEqual(result.data, original); XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(result.pixelWidth, 19); XCTAssertEqual(result.pixelHeight, 11)
        XCTAssertFalse(result.hasSystemScreenshotMetadata)
        XCTAssertEqual(getxattr(url.path, CaptureSource.metadataName, nil, 0, 0, 0), -1)
        XCTAssertEqual(errno, ENOATTR)
    }

    func testMalformedAndSymlinkOutputsAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-interactive-invalid-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = root.appendingPathComponent("partial.png")
        try fixturePNG().prefix(20).write(to: broken)
        XCTAssertThrowsError(try InteractiveScreenshotSystemCapture.readOriginal(at: broken))
        let valid = root.appendingPathComponent("valid.png")
        try fixturePNG().write(to: valid)
        let link = root.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: valid)
        XCTAssertThrowsError(try InteractiveScreenshotSystemCapture.readOriginal(at: link))
    }

    /// Runs the installed Apple utility's help only: no capture, TCC prompt or
    /// GUI interaction. This is current-system flag evidence, not capture proof.
    func testInstalledSystemUtilityAdvertisesRequiredNoninteractiveFlags() throws {
        let process = Process(), pipe = Pipe()
        process.executableURL = InteractiveScreenshotCommand.executable
        process.arguments = ["-h"]
        process.standardOutput = pipe; process.standardError = pipe
        try process.run(); process.waitUntilExit()
        let help = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for flag in ["-R", "-l", "-C", "-t", "-x"] { XCTAssertTrue(help.contains(flag), "Installed screencapture help omits \(flag)") }
        print("RIFTLET_SYSTEM_SCREENSHOT_HELP_BEGIN\n\(help)\nRIFTLET_SYSTEM_SCREENSHOT_HELP_END")
    }
}

@MainActor
private final class InteractivePermissionFixture: InteractiveScreenshotPermissionChecking {
    var allowed = true
    var requestCalls = 0
    func hasAccess() -> Bool { allowed }
    func requestAccess() -> Bool { requestCalls += 1; return allowed }
}

@MainActor
private final class InteractiveCapturerFixture: InteractiveScreenshotCapturing {
    var requests: [InteractiveScreenshotRequest] = []
    var continuations: [CheckedContinuation<InteractiveScreenshotFile, Error>] = []
    var cancelCalls = 0
    var onRequest: (() -> Void)?
    func capture(_ request: InteractiveScreenshotRequest, outputDirectory: URL) async throws -> InteractiveScreenshotFile {
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation); onRequest?()
        }
    }
    func cancel() { cancelCalls += 1 }
    func succeed() {
        continuations.removeFirst().resume(returning: .init(sourceURL: URL(fileURLWithPath: "/tmp/synthetic-untouched.png"),
            data: Data([1, 2, 3]), pixelWidth: 19, pixelHeight: 11, hasSystemScreenshotMetadata: false))
    }
    func fail() { continuations.removeFirst().resume(throwing: InteractiveScreenshotError.captureFailed(2)) }
}

final class InteractiveScreenshotControllerTests: XCTestCase {
    @MainActor
    private func fixture(permission: InteractivePermissionFixture? = nil, capturer: InteractiveCapturerFixture? = nil,
                         windows: @escaping () -> [InteractiveScreenshotWindow] = { [] })
        -> (InteractiveScreenshotController, InteractivePermissionFixture, InteractiveCapturerFixture, InteractiveScreenshotTarget) {
        let permission = permission ?? InteractivePermissionFixture()
        let capturer = capturer ?? InteractiveCapturerFixture()
        let display = InteractiveScreenshotDisplay(id: 7, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            quartzFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let controller = InteractiveScreenshotController(outputDirectory: URL(fileURLWithPath: "/tmp/not-used-by-fixture"),
            permission: permission, capturer: capturer, displays: { [display] }, windows: windows, presentsPanels: false)
        let target = InteractiveScreenshotTarget(rect: display.frame, quartzRect: display.quartzFrame, displays: [display], window: nil)
        return (controller, permission, capturer, target)
    }

    @MainActor
    func testConstructionNeverRequestsPermissionAndDeniedStartCannotCapture() {
        let permission = InteractivePermissionFixture(); permission.allowed = false
        let (controller, _, capturer, target) = fixture(permission: permission)
        XCTAssertEqual(permission.requestCalls, 0)
        var errors: [InteractiveScreenshotError] = []
        controller.onError = { errors.append($0) }
        controller.start(mode: .region)
        controller.submitSelection(target)
        XCTAssertEqual(permission.requestCalls, 1); XCTAssertFalse(controller.isActive)
        XCTAssertEqual(errors, [.screenRecordingPermissionRequired]); XCTAssertTrue(capturer.requests.isEmpty)
    }

    @MainActor
    func testCompletionSurvivesModeSwitchAndLeavesSessionArmed() async {
        let (controller, _, capturer, target) = fixture()
        let began = expectation(description: "capture began"), completed = expectation(description: "capture delivered")
        capturer.onRequest = { began.fulfill() }
        var delivered: InteractiveScreenshotCapture?
        controller.onCapture = { delivered = $0; completed.fulfill() }
        controller.start(mode: .region, options: .init(showPointer: true))
        controller.submitSelection(target)
        await fulfillment(of: [began], timeout: 1)
        controller.updateMode(.fullScreen); controller.updateOptions(.init(editAfter: true))
        capturer.succeed()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(delivered?.mode, .region); XCTAssertEqual(delivered?.options.showPointer, true)
        XCTAssertEqual(delivered?.options.editAfter, false)
        XCTAssertTrue(controller.isActive); XCTAssertFalse(controller.isCapturing)
        XCTAssertEqual(controller.currentMode, .fullScreen)
        XCTAssertEqual(controller.state, .selecting(.fullScreen))
        controller.cancel()
    }

    @MainActor
    func testCancelledSessionIgnoresLateSuccessAndDoesNotCancelTwice() async {
        let (controller, _, capturer, target) = fixture()
        let began = expectation(description: "capture began")
        capturer.onRequest = { began.fulfill() }
        var captures = 0, cancellations = 0
        controller.onCapture = { _ in captures += 1 }; controller.onCancel = { cancellations += 1 }
        controller.start(mode: .region); controller.submitSelection(target)
        await fulfillment(of: [began], timeout: 1)
        controller.cancel(); controller.cancel(); capturer.succeed()
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(captures, 0); XCTAssertEqual(cancellations, 1); XCTAssertFalse(controller.isActive)
    }

    @MainActor
    func testCaptureFailureIsExplicitAndRearmsWithoutPretendingSuccess() async {
        let (controller, _, capturer, target) = fixture()
        let began = expectation(description: "capture began"), failed = expectation(description: "failure delivered")
        capturer.onRequest = { began.fulfill() }
        var captures = 0
        controller.onCapture = { _ in captures += 1 }
        controller.onError = { error in XCTAssertEqual(error, .captureFailed(2)); failed.fulfill() }
        controller.start(mode: .fullScreen); controller.submitSelection(target)
        await fulfillment(of: [began], timeout: 1)
        capturer.fail(); await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(captures, 0); XCTAssertTrue(controller.isActive); XCTAssertFalse(controller.isCapturing)
        controller.cancel()
    }

    @MainActor
    func testDelayedWindowRevalidatesFrozenOwnerBeforeStartingTool() async {
        let selected = InteractiveScreenshotWindow(id: 42, ownerPID: 111, rect: CGRect(x: 10, y: 10, width: 300, height: 200))
        var current = [selected]
        let (controller, _, capturer, displayTarget) = fixture(windows: { current })
        let target = InteractiveScreenshotTarget(rect: selected.rect, quartzRect: CGRect(x: 10, y: 690, width: 300, height: 200),
                                                 displays: displayTarget.displays, window: selected)
        let rejected = expectation(description: "replaced window rejected")
        controller.onError = { error in XCTAssertEqual(error, .selectedWindowUnavailable); rejected.fulfill() }
        controller.start(mode: .window, options: .init(delay: 0.02))
        controller.submitSelection(target)
        current = [InteractiveScreenshotWindow(id: 42, ownerPID: 999, rect: selected.rect)]
        await fulfillment(of: [rejected], timeout: 1)
        XCTAssertTrue(capturer.requests.isEmpty); XCTAssertTrue(controller.isActive); XCTAssertFalse(controller.isCapturing)
        controller.cancel()
    }

    @MainActor
    func testMenuSuspensionRejectsSelectionUntilExplicitResume() async {
        let (controller, _, capturer, target) = fixture()
        controller.start(mode: .region); controller.setInteractionSuspended(true)
        controller.submitSelection(target)
        for _ in 0..<4 { await Task.yield() }
        XCTAssertTrue(capturer.requests.isEmpty); XCTAssertFalse(controller.isCapturing)
        let began = expectation(description: "new selection after menu")
        capturer.onRequest = { began.fulfill() }
        controller.setInteractionSuspended(false); controller.submitSelection(target)
        await fulfillment(of: [began], timeout: 1)
        controller.cancel(); capturer.succeed()
    }
}
