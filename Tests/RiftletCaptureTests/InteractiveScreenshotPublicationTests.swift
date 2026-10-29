import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import RiftletCapture

/// Synthetic child processes exercise the production reservation/publication
/// path. They never invoke screencapture, read the screen or grant provenance.
final class InteractiveScreenshotPublicationTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let captures: URL
        let source: URL
        let bytes: Data
        let request: InteractiveScreenshotRequest

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("riftlet-publication-" + UUID().uuidString)
            captures = root.appendingPathComponent("captures", isDirectory: true)
            source = root.appendingPathComponent("synthetic.png")
            try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 12, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
            let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(encoder, try XCTUnwrap(context.makeImage()), nil)
            guard CGImageDestinationFinalize(encoder) else { throw InteractiveScreenshotError.invalidOutput }
            bytes = try Data(contentsOf: source)
            let rect = CGRect(x: 10, y: 10, width: 20, height: 12)
            let display = InteractiveScreenshotDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
                quartzFrame: CGRect(x: 0, y: 0, width: 1024, height: 768), scale: 1)
            request = .init(id: UUID(), sessionID: UUID(), mode: .region, options: .init(),
                target: .init(rect: rect, quartzRect: rect, displays: [display], window: nil))
        }

        var final: URL { InteractiveScreenshotOutput.originalURL(in: captures, captureID: request.id) }

        func executable(_ body: String) throws -> URL {
            let script = root.appendingPathComponent("synthetic-child.sh")
            try Data(("#!/bin/sh\nset -eu\nfor output; do :; done\n" + body + "\n").utf8).write(to: script)
            guard chmod(script.path, 0o700) == 0 else { throw InteractiveScreenshotError.captureToolUnavailable }
            return script
        }

        func stageFiles(in directory: URL? = nil) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: directory ?? captures, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix(".capture-") }
                .flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
        }
    }

    private func quote(_ url: URL) -> String { "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @MainActor
    func testOrdinaryStagedLeafPublishesHiddenOriginalWithoutReencoding() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let executable = try fixture.executable("""
        case "${output##*/}" in .*) exit 41;; esac
        parent=${output%/*}
        case "${parent##*/}" in .capture-*) :;; *) exit 42;; esac
        /bin/cat \(quote(fixture.source)) > "$output"
        """)
        var started = 0
        let engine = InteractiveScreenshotSystemCapture(executableURL: executable, onProcessStarted: { started += 1 })
        let result = try await engine.capture(fixture.request, outputDirectory: fixture.captures)
        XCTAssertEqual(started, 1)
        XCTAssertEqual(result.sourceURL, fixture.final)
        XCTAssertEqual(result.data, fixture.bytes)
        XCTAssertEqual(try Data(contentsOf: fixture.final), fixture.bytes)
        XCTAssertEqual(result.pixelWidth, 20); XCTAssertEqual(result.pixelHeight, 12)
        XCTAssertFalse(result.hasSystemScreenshotMetadata)
        var info = stat()
        XCTAssertEqual(lstat(fixture.final.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertTrue(try fixture.stageFiles().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: fixture.captures, includingPropertiesForKeys: nil), [fixture.final])
    }

    @MainActor
    func testDestinationCreatedDuringCaptureIsNotReplaced() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let executable = try fixture.executable("""
        /bin/cat \(quote(fixture.source)) > "$output"
        printf 'existing-final' > \(quote(fixture.final))
        """)
        let engine = InteractiveScreenshotSystemCapture(executableURL: executable)
        do { _ = try await engine.capture(fixture.request, outputDirectory: fixture.captures); XCTFail("Existing output was replaced") }
        catch InteractiveScreenshotError.unsafeOutputDirectory {}
        XCTAssertEqual(try Data(contentsOf: fixture.final), Data("existing-final".utf8))
        let staged = try XCTUnwrap(try fixture.stageFiles().only)
        XCTAssertEqual(try Data(contentsOf: staged), fixture.bytes)
    }

    @MainActor
    func testFailedChildPreservesItsNonemptyStagedOutput() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let executable = try fixture.executable("/bin/cat \(quote(fixture.source)) > \"$output\"\nexit 3")
        let engine = InteractiveScreenshotSystemCapture(executableURL: executable)
        do { _ = try await engine.capture(fixture.request, outputDirectory: fixture.captures); XCTFail("Failed child was accepted") }
        catch InteractiveScreenshotError.captureFailed(3) {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.final.path))
        let staged = try XCTUnwrap(try fixture.stageFiles().only)
        XCTAssertEqual(try Data(contentsOf: staged), fixture.bytes)
    }

    @MainActor
    func testCancellationPreservesTheChildsNonemptyStagedOutput() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let ready = fixture.root.appendingPathComponent("child-ready")
        let executable = try fixture.executable("""
        /bin/cat \(quote(fixture.source)) > "$output"
        printf 'ready' > \(quote(ready))
        exec /bin/sleep 30
        """)
        let engine = InteractiveScreenshotSystemCapture(executableURL: executable)
        defer { engine.cancel() }
        let operation = Task { @MainActor in try await engine.capture(fixture.request, outputDirectory: fixture.captures) }
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath: ready.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path), "Synthetic child did not reach its cancellation boundary")
        engine.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled child was accepted") }
        catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.final.path))
        let staged = try XCTUnwrap(try fixture.stageFiles().only)
        XCTAssertEqual(try Data(contentsOf: staged), fixture.bytes)
    }

    @MainActor
    func testLaunchFailureRemovesOnlyItsUnchangedEmptyReservation() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var started = 0
        let engine = InteractiveScreenshotSystemCapture(executableURL: fixture.root.appendingPathComponent("missing-child"),
                                                        onProcessStarted: { started += 1 })
        do { _ = try await engine.capture(fixture.request, outputDirectory: fixture.captures); XCTFail("Missing child was accepted") }
        catch InteractiveScreenshotError.captureToolUnavailable {}
        XCTAssertEqual(started, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: fixture.captures, includingPropertiesForKeys: nil).isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.bytes)
    }

    @MainActor
    func testCaptureDirectoryReplacementCannotRedirectPublicationOrCleanup() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let displaced = fixture.root.appendingPathComponent("displaced", isDirectory: true)
        let sentinel = fixture.captures.appendingPathComponent("replacement-sentinel")
        let executable = try fixture.executable("""
        /bin/cat \(quote(fixture.source)) > "$output"
        /bin/mv \(quote(fixture.captures)) \(quote(displaced))
        /bin/mkdir -m 700 \(quote(fixture.captures))
        printf 'replacement-directory' > \(quote(sentinel))
        """)
        let engine = InteractiveScreenshotSystemCapture(executableURL: executable)
        do { _ = try await engine.capture(fixture.request, outputDirectory: fixture.captures); XCTFail("Replaced directory was accepted") }
        catch InteractiveScreenshotError.unsafeOutputDirectory {}
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("replacement-directory".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.final.path))
        let staged = try XCTUnwrap(try fixture.stageFiles(in: displaced).only)
        XCTAssertEqual(try Data(contentsOf: staged), fixture.bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: fixture.captures, includingPropertiesForKeys: nil), [sentinel])
    }

    @MainActor
    func testReplacedStageSymlinkDoesNotPublishOrModifyItsTarget() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let executable = try fixture.executable("""
        /bin/rm "$output"
        /bin/ln -s \(quote(fixture.source)) "$output"
        """)
        let engine = InteractiveScreenshotSystemCapture(executableURL: executable)
        do { _ = try await engine.capture(fixture.request, outputDirectory: fixture.captures); XCTFail("Symlink output was accepted") }
        catch InteractiveScreenshotError.invalidOutput {}
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.final.path))
        let staged = try XCTUnwrap(try fixture.stageFiles().only)
        var info = stat()
        XCTAssertEqual(lstat(staged.path, &info), 0)
        XCTAssertEqual(info.st_mode & mode_t(S_IFMT), mode_t(S_IFLNK))
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
