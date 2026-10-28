import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import RiftletCapture

/// These execute harmless real child processes on macOS. They verify process
/// cancellation/cleanup, not WindowServer capture, TCC or physical keyboard input.
final class InteractiveScreenshotProcessTests: XCTestCase {
    @MainActor
    private func waitForProcess(_ capturer: InteractiveScreenshotSystemCapture) async throws {
        for _ in 0..<100 {
            if capturer.hasRunningProcess { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Owned fixture process did not start")
    }

    @MainActor
    func testImmediateRestartWaitsForCancelledChildWithoutCancellingReplacement() async throws {
        let capturer = InteractiveScreenshotSystemCapture(executableURL: URL(fileURLWithPath: "/bin/sleep"),
            timeoutNanoseconds: 2_000_000_000, cancellationGraceNanoseconds: 50_000_000)
        let old = Task { try await capturer.run(arguments: ["10"]) }
        try await waitForProcess(capturer)
        capturer.cancel()
        try await capturer.run(arguments: ["0"])
        do { try await old.value; XCTFail("Cancelled process reported success") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertFalse(capturer.hasRunningProcess)
    }

    @MainActor
    func testTaskCancellationTerminatesOwnedChildAndCompletesContinuation() async throws {
        let capturer = InteractiveScreenshotSystemCapture(executableURL: URL(fileURLWithPath: "/bin/sleep"),
            timeoutNanoseconds: 2_000_000_000, cancellationGraceNanoseconds: 50_000_000)
        let task = Task { try await capturer.run(arguments: ["10"]) }
        try await waitForProcess(capturer)
        task.cancel()
        do { try await task.value; XCTFail("Cancelled task reported success") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertFalse(capturer.hasRunningProcess)
    }

    @MainActor
    func testTimeoutReapsChildAndAllowsSubsequentRun() async throws {
        let capturer = InteractiveScreenshotSystemCapture(executableURL: URL(fileURLWithPath: "/bin/sleep"),
            timeoutNanoseconds: 500_000_000, cancellationGraceNanoseconds: 50_000_000)
        do { try await capturer.run(arguments: ["10"]); XCTFail("Fixture must time out") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .captureTimedOut) }
        XCTAssertFalse(capturer.hasRunningProcess)
        try await capturer.run(arguments: ["0"])
        XCTAssertFalse(capturer.hasRunningProcess)
    }

    @MainActor
    func testExitedProcessIsNotTimedOutWhileTerminationDeliveryIsDelayed() async throws {
        let capturer = InteractiveScreenshotSystemCapture(executableURL: URL(fileURLWithPath: "/bin/sleep"),
            timeoutNanoseconds: 500_000_000, cancellationGraceNanoseconds: 50_000_000,
            terminationDeliveryDelayNanoseconds: 1_000_000_000)
        // The real zero-duration child exits before the deadline; its completion
        // is deliberately delivered after it. Without the running-process guard,
        // the pending job would incorrectly be marked as timed out.
        try await capturer.run(arguments: ["0"])
        XCTAssertFalse(capturer.hasRunningProcess)
    }

    @MainActor
    func testFailedLaunchCleansOnlyItsEmptyReservation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-process-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("previous-original.png"), original = Data([1, 2, 3])
        try original.write(to: existing)
        let display = InteractiveScreenshotDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            quartzFrame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        var session = InteractiveScreenshotSession()
        session.start(mode: .fullScreen, options: .init())
        let request = try XCTUnwrap(session.beginCapture(target: .init(rect: display.frame,
            quartzRect: display.quartzFrame, displays: [display], window: nil)))
        let capturer = InteractiveScreenshotSystemCapture(executableURL: root.appendingPathComponent("missing-tool"))
        do { _ = try await capturer.capture(request, outputDirectory: root); XCTFail("Missing utility must fail") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .captureToolUnavailable) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [existing.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: existing), original)
    }

    @MainActor
    func testOwnedOriginalIsHiddenBeforeToolStartsAndRemainsByteCompleteAfterCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-hidden-output-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let fixture = root.appendingPathComponent("fixture.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(fixture as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = try Data(contentsOf: fixture)

        // A harmless owned fixture utility verifies the pre-existing reservation
        // is already hidden before writing. This is not Apple-tool capture proof.
        let executable = root.appendingPathComponent("fixture-tool")
        let script = "#!/bin/sh\nfor last do :; done\ncase \"${last##*/}\" in .*.png) ;; *) exit 76 ;; esac\n[ -f \"$last\" ] || exit 77\n/bin/cp \"${0%/*}/fixture.png\" \"$last\"\n"
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let display = InteractiveScreenshotDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 16, height: 12),
            quartzFrame: CGRect(x: 0, y: 0, width: 16, height: 12), scale: 2)
        var session = InteractiveScreenshotSession()
        session.start(mode: .fullScreen, options: .init())
        let request = try XCTUnwrap(session.beginCapture(target: .init(rect: display.frame,
            quartzRect: display.quartzFrame, displays: [display], window: nil)))
        let directory = root.appendingPathComponent("captures")
        let capturer = InteractiveScreenshotSystemCapture(executableURL: executable)
        let result = try await capturer.capture(request, outputDirectory: directory)

        XCTAssertEqual(result.sourceURL.lastPathComponent, "." + request.id.uuidString.lowercased() + ".png")
        XCTAssertEqual(result.data, original)
        XCTAssertEqual(try Data(contentsOf: result.sourceURL), original)
        XCTAssertEqual(result.pixelWidth, 32); XCTAssertEqual(result.pixelHeight, 24)
        let visible = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        XCTAssertTrue(visible.isEmpty, "The system watcher must not see the owned original")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
            [result.sourceURL.lastPathComponent], "The hidden original must still exist")
    }

    func testCleanupNeverDeletesACompletedOrReplacedOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-reservation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("reserved.png")
        try Data().write(to: url)
        let reserved = try FileSignature.read(at: url)
        let completed = Data([10, 20, 30])
        try completed.write(to: url)
        InteractiveScreenshotSystemCapture.removeEmptyReservation(at: url, signature: reserved)
        XCTAssertEqual(try Data(contentsOf: url), completed)
        try FileManager.default.removeItem(at: url)
        try Data().write(to: url)
        InteractiveScreenshotSystemCapture.removeEmptyReservation(at: url, signature: reserved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "An empty replacement still belongs to someone else")
    }
}
