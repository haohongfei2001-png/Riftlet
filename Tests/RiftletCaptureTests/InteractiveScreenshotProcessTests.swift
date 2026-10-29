import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import RiftletCapture

/// These execute harmless real child processes on macOS. They verify process
/// cancellation/cleanup, not WindowServer capture, TCC or physical keyboard input.
final class InteractiveScreenshotProcessTests: XCTestCase {
    private func fixturePNG() throws -> Data {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let bytes = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(bytes,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return bytes as Data
    }

    @MainActor
    private func captureFixture(body: String) throws -> (root: URL, directory: URL, original: Data,
        request: InteractiveScreenshotRequest, capturer: InteractiveScreenshotSystemCapture) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-output-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = try fixturePNG()
        try original.write(to: root.appendingPathComponent("fixture.png"))
        let executable = root.appendingPathComponent("fixture-tool")
        let script = "#!/bin/sh\nset -eu\nfor last do :; done\nstage=\"${last%/*}\"\nleaf=\"${last##*/}\"\ncaptureRoot=\"${stage%/*}\"\nfixtureRoot=\"${0%/*}\"\n" + body + "\n"
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let display = InteractiveScreenshotDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 16, height: 12),
            quartzFrame: CGRect(x: 0, y: 0, width: 16, height: 12), scale: 2)
        var session = InteractiveScreenshotSession()
        session.start(mode: .fullScreen, options: .init())
        let request = try XCTUnwrap(session.beginCapture(target: .init(rect: display.frame,
            quartzRect: display.quartzFrame, displays: [display], window: nil)))
        return (root, root.appendingPathComponent("captures"), original, request,
            InteractiveScreenshotSystemCapture(executableURL: executable, timeoutNanoseconds: 5_000_000_000,
                                               cancellationGraceNanoseconds: 50_000_000))
    }

    @MainActor
    private func waitForFile(_ url: URL) async throws {
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Owned fixture did not reach its write checkpoint")
        throw CocoaError(.fileNoSuchFile)
    }

    private func assertNoVisibleOutput(in directory: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let visible = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        XCTAssertTrue(visible.isEmpty, "The independent system collector must not see an owned write", file: file, line: line)
    }

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
    func testOwnedOutputIsIsolatedDuringWriteAndPublishesHiddenByteCompleteOriginal() async throws {
        // A real harmless child verifies the ordinary reservation is inside an
        // exclusively private hidden stage. This is not Apple-tool capture proof.
        let fixture = try captureFixture(body: """
        case "$leaf" in .*) exit 76 ;; esac
        case "${stage##*/}" in .capture-*) ;; *) exit 77 ;; esac
        [ -f "$last" ] || exit 78
        [ "$(/usr/bin/stat -f '%Lp' "$stage")" = 700 ] || exit 79
        /bin/cp "$fixtureRoot/fixture.png" "$last"
        printf '%s' "$last" > "$fixtureRoot/written-path.tmp"
        /bin/mv "$fixtureRoot/written-path.tmp" "$fixtureRoot/written-path"
        while [ ! -f "$fixtureRoot/release" ]; do /bin/sleep 0.02; done
        """)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let task = Task { try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory) }
        defer { task.cancel() }
        let checkpoint = fixture.root.appendingPathComponent("written-path")
        try await waitForFile(checkpoint)
        let staged = URL(fileURLWithPath: try String(contentsOf: checkpoint, encoding: .utf8))
        XCTAssertEqual(try Data(contentsOf: staged), fixture.original)
        XCTAssertEqual(staged.lastPathComponent, fixture.request.id.uuidString.lowercased() + ".png")
        XCTAssertTrue(staged.deletingLastPathComponent().lastPathComponent.hasPrefix(".capture-"))
        try assertNoVisibleOutput(in: fixture.directory)
        try Data().write(to: fixture.root.appendingPathComponent("release"))
        let result = try await task.value

        XCTAssertEqual(result.sourceURL.deletingLastPathComponent().standardizedFileURL.path,
                       fixture.directory.standardizedFileURL.path)
        XCTAssertEqual(result.sourceURL.lastPathComponent, "." + fixture.request.id.uuidString.lowercased() + ".png")
        XCTAssertEqual(result.data, fixture.original)
        XCTAssertEqual(try Data(contentsOf: result.sourceURL), fixture.original)
        XCTAssertEqual(result.pixelWidth, 32); XCTAssertEqual(result.pixelHeight, 24)
        try assertNoVisibleOutput(in: fixture.directory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path),
            [result.sourceURL.lastPathComponent], "Only the published original remains after its empty stage is removed")
    }

    @MainActor
    func testFailedToolRetainsNonemptyStageAndSameRequestUsesFreshStage() async throws {
        let fixture = try captureFixture(body: """
        /bin/cp "$fixtureRoot/fixture.png" "$last"
        if [ ! -f "$fixtureRoot/retry" ]; then exit 23; fi
        """)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do { _ = try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory); XCTFail("Fixture must fail") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .captureFailed(23)) }
        let oldStage = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: fixture.directory,
            includingPropertiesForKeys: nil).first)
        let oldOriginal = oldStage.appendingPathComponent(fixture.request.id.uuidString.lowercased() + ".png")
        XCTAssertEqual(try Data(contentsOf: oldOriginal), fixture.original)
        try assertNoVisibleOutput(in: fixture.directory)
        try Data().write(to: fixture.root.appendingPathComponent("retry"))
        let result = try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory)
        XCTAssertEqual(result.data, fixture.original)
        XCTAssertEqual(try Data(contentsOf: oldOriginal), fixture.original, "A previous nonempty stage is never reused or removed")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)),
                       Set([oldStage.lastPathComponent, result.sourceURL.lastPathComponent]))
    }

    @MainActor
    func testCancellationRetainsCompletedStageWithoutPublishingOrExposingIt() async throws {
        let fixture = try captureFixture(body: """
        /bin/cp "$fixtureRoot/fixture.png" "$last"
        printf '%s' "$last" > "$fixtureRoot/written-path.tmp"
        /bin/mv "$fixtureRoot/written-path.tmp" "$fixtureRoot/written-path"
        exec /bin/sleep 10
        """)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let task = Task { try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory) }
        defer { task.cancel() }
        let checkpoint = fixture.root.appendingPathComponent("written-path")
        try await waitForFile(checkpoint)
        let staged = URL(fileURLWithPath: try String(contentsOf: checkpoint, encoding: .utf8))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled capture reported success") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertEqual(try Data(contentsOf: staged), fixture.original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory
            .appendingPathComponent("." + fixture.request.id.uuidString.lowercased() + ".png").path))
        try assertNoVisibleOutput(in: fixture.directory)
    }

    @MainActor
    func testPublishedRequestCannotBeOverwrittenOrCapturedAgain() async throws {
        let fixture = try captureFixture(body: "/bin/cp \"$fixtureRoot/fixture.png\" \"$last\"")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let result = try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory)
        let signature = try FileSignature.read(at: result.sourceURL)
        do { _ = try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory); XCTFail("Duplicate request must fail") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .unsafeOutputDirectory) }
        XCTAssertEqual(try FileSignature.read(at: result.sourceURL), signature)
        XCTAssertEqual(try Data(contentsOf: result.sourceURL), fixture.original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), [result.sourceURL.lastPathComponent])
    }

    @MainActor
    func testPublishConflictRetainsBothCapturedStageAndExistingDestination() async throws {
        let fixture = try captureFixture(body: """
        /bin/cp "$fixtureRoot/fixture.png" "$last"
        printf 'previous original' > "$captureRoot/.$leaf"
        """)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do { _ = try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory); XCTFail("Exclusive publication must fail") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .unsafeOutputDirectory) }
        let entries = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        let stage = try XCTUnwrap(entries.first { $0.lastPathComponent.hasPrefix(".capture-") })
        XCTAssertEqual(try Data(contentsOf: stage.appendingPathComponent(fixture.request.id.uuidString.lowercased() + ".png")), fixture.original)
        XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent("." + fixture.request.id.uuidString.lowercased() + ".png")),
                       Data("previous original".utf8))
        try assertNoVisibleOutput(in: fixture.directory)
    }

    @MainActor
    func testReplacedStageDirectoryCannotRedirectPublicationOrCleanup() async throws {
        let fixture = try captureFixture(body: """
        /bin/cp "$fixtureRoot/fixture.png" "$last"
        /bin/mv "$stage" "$stage-retained"
        /bin/mkdir -m 700 "$stage"
        printf 'replacement' > "$last"
        """)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do { _ = try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory); XCTFail("Replaced stage must fail") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .unsafeOutputDirectory) }
        let entries = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.count, 2)
        let retained = try XCTUnwrap(entries.first { $0.lastPathComponent.hasSuffix("-retained") })
        let replacement = try XCTUnwrap(entries.first { !$0.lastPathComponent.hasSuffix("-retained") })
        let name = fixture.request.id.uuidString.lowercased() + ".png"
        XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent(name)), fixture.original)
        XCTAssertEqual(try Data(contentsOf: replacement.appendingPathComponent(name)), Data("replacement".utf8))
        try assertNoVisibleOutput(in: fixture.directory)
    }

    @MainActor
    func testSymlinkOutputReplacementPreservesOriginalAndRejectsTarget() async throws {
        let fixture = try captureFixture(body: """
        /bin/cp "$fixtureRoot/fixture.png" "$last"
        /bin/mv "$last" "$last-retained"
        /bin/ln -s "$fixtureRoot/fixture.png" "$last"
        """)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do { _ = try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory); XCTFail("Symlink must fail") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .invalidOutput) }
        let stage = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil).first)
        let originalName = fixture.request.id.uuidString.lowercased() + ".png"
        XCTAssertEqual(try Data(contentsOf: stage.appendingPathComponent(originalName + "-retained")), fixture.original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: stage.appendingPathComponent(originalName).path),
                       fixture.root.appendingPathComponent("fixture.png").path)
        XCTAssertEqual(try Data(contentsOf: fixture.root.appendingPathComponent("fixture.png")), fixture.original)
        try assertNoVisibleOutput(in: fixture.directory)
    }

    @MainActor
    func testUnexpectedToolFilenameIsNeverSearchedOrAdmitted() async throws {
        let fixture = try captureFixture(body: "/bin/cp \"$fixtureRoot/fixture.png\" \"$last-renamed.png\"")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do { _ = try await fixture.capturer.capture(fixture.request, outputDirectory: fixture.directory); XCTFail("Exact empty output must fail") }
        catch { XCTAssertEqual(error as? InteractiveScreenshotError, .invalidOutput) }
        let stage = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil).first)
        let renamed = fixture.request.id.uuidString.lowercased() + ".png-renamed.png"
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: stage.path), [renamed], "Only the unchanged empty reservation is cleaned")
        XCTAssertEqual(try Data(contentsOf: stage.appendingPathComponent(renamed)), fixture.original)
        try assertNoVisibleOutput(in: fixture.directory)
    }

    func testReadBackCannotAdmitAnotherFileWithTheSamePNGBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-readback-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try fixturePNG(), first = root.appendingPathComponent("first.png")
        let replacement = root.appendingPathComponent("replacement.png")
        try original.write(to: first); try original.write(to: replacement)
        let signature = try FileSignature.read(at: first)
        XCTAssertThrowsError(try InteractiveScreenshotSystemCapture.readOriginal(at: replacement, expectedSignature: signature)) {
            XCTAssertEqual($0 as? InteractiveScreenshotError, .invalidOutput)
        }
        XCTAssertEqual(try Data(contentsOf: first), original)
        XCTAssertEqual(try Data(contentsOf: replacement), original)
    }

    func testCleanupNeverDeletesACompletedOrReplacedOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-reservation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("reserved.png")
        let directoryDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(directoryDescriptor, 0)
        defer { Darwin.close(directoryDescriptor) }
        try Data().write(to: url)
        let reserved = try FileSignature.read(at: url)
        let completed = Data([10, 20, 30])
        try completed.write(to: url)
        InteractiveScreenshotSystemCapture.removeEmptyReservation(directoryDescriptor: directoryDescriptor,
                                                                  name: url.lastPathComponent, signature: reserved)
        XCTAssertEqual(try Data(contentsOf: url), completed)
        try FileManager.default.removeItem(at: url)
        try Data().write(to: url)
        InteractiveScreenshotSystemCapture.removeEmptyReservation(directoryDescriptor: directoryDescriptor,
                                                                  name: url.lastPathComponent, signature: reserved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "An empty replacement still belongs to someone else")
    }
}
