import XCTest
import Foundation
import CoreGraphics
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
            timeoutNanoseconds: 40_000_000, cancellationGraceNanoseconds: 40_000_000)
        do { try await capturer.run(arguments: ["10"]); XCTFail("Fixture must time out") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .captureTimedOut) }
        XCTAssertFalse(capturer.hasRunningProcess)
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
