import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import RiftletCore
@testable import RiftletCapture

final class CompletedScreenshotImporterTests: XCTestCase {
    func testCompletedApplicationPNGIsCopiedExactlyAndOriginalIsRetained() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let captures = root.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let source = captures.appendingPathComponent("fixture.png")
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 20, height: 12, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let original = try Data(contentsOf: source)
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let importer = PrivateAssetImporter(privateRoot: root, store: store)
        // A generated fixture has no genuine system-screenshot marker. The
        // existing importer represents an absent marker as metadataPending;
        // notScreenshot means a present but false/invalid marker.
        do { _ = try await importer.importCompletedScreenshot(at: source, origin: .systemScreenshot); XCTFail("Unmarked file gained system origin") }
        catch CaptureError.metadataPending {}
        let record = try await importer.importCompletedScreenshot(at: source, origin: .applicationScreenshot)
        let repeated = try await importer.importCompletedScreenshot(at: source, origin: .applicationScreenshot)
        XCTAssertEqual(record.id, repeated.id)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("media").appendingPathComponent(record.image.fileName)), original)
        XCTAssertEqual(record.image.origin, .applicationScreenshot)
        let usage = try PrivateStorageUsage.measure(privateRoot: root)
        XCTAssertEqual(usage.areas.first(where: { $0.area == .captures })?.regularFileCount, 1)
        XCTAssertEqual(usage.areas.first(where: { $0.area == .captures })?.logicalBytes, UInt64(original.count))
    }
}
