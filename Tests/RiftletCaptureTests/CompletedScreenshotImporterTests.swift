import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin
import RiftletCore
@testable import RiftletCapture

final class CompletedScreenshotImporterTests: XCTestCase {
    private func syntheticPNG(at url: URL, red: CGFloat = 0.25) throws -> Data {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 20, height: 12, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: red, green: 0.5, blue: 0.75, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try Data(contentsOf: url)
    }

    func testBuiltInProvenanceCannotBorrowSystemMarkerAndBothSourcesCoexistAcrossRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let captures = root.appendingPathComponent("captures")
        let builtin = captures.appendingPathComponent("builtin.png")
        let bytes = try syntheticPNG(at: builtin)
        let system = root.appendingPathComponent("synthetic-system-source/system.png")
        _ = try syntheticPNG(at: system)
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        // Synthetic metadata fixture, not real screenshot/upload evidence.
        for url in [builtin, system] {
            XCTAssertEqual(marker.withUnsafeBytes { setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }, 0)
        }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let importer = PrivateAssetImporter(privateRoot: root, store: store)
        let owned = try await importer.importBuiltInScreenshot(original: builtin, outputDirectory: captures)
        let repeated = try await importer.importBuiltInScreenshot(original: builtin, outputDirectory: captures)
        let external = try await importer.importCompletedScreenshot(at: system, origin: .systemScreenshot)
        XCTAssertEqual(owned.id, repeated.id)
        XCTAssertNotEqual(owned.id, external.id)
        XCTAssertEqual(owned.image.origin, .applicationScreenshot)
        XCTAssertEqual(external.image.origin, .systemScreenshot)
        XCTAssertEqual(try Data(contentsOf: builtin), bytes)
        let reopened = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let recovered = try await reopened.assets(includeUsed: true)
        XCTAssertEqual(recovered.count, 2)
        XCTAssertEqual(Set(recovered.map { $0.image.origin.rawValue }), ["systemScreenshot", "applicationScreenshot"])
        let media = root.appendingPathComponent("media").appendingPathComponent(owned.image.fileName)
        XCTAssertEqual(try Data(contentsOf: media), bytes, "Profile, pixels and PNG chunks stay byte-identical")
    }

    func testOptionalDerivativeUsesPrivateDurableWriteWithoutChangingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let captures = root.appendingPathComponent("captures")
        let original = captures.appendingPathComponent("original.png")
        let bytes = try syntheticPNG(at: original)
        let edited = try syntheticPNG(at: root.appendingPathComponent("fixture-edited.png"), red: 0.8)
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let importer = PrivateAssetImporter(privateRoot: root, store: store)
        let record = try await importer.importBuiltInScreenshot(original: original, editedPNG: edited, outputDirectory: captures)
        XCTAssertEqual(record.image.origin, .applicationScreenshot)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("media").appendingPathComponent(record.image.fileName)), edited)
        let names = try FileManager.default.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil)
        let derivative = try XCTUnwrap(names.first { $0.lastPathComponent.hasSuffix("-edited.png") })
        let mode = try FileManager.default.attributesOfItem(atPath: derivative.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        do {
            _ = try await importer.importBuiltInScreenshot(original: original, editedPNG: edited, outputDirectory: root)
            XCTFail("Derivative escaped its owned capture directory")
        } catch CaptureError.privatePathUnsafe {}
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

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
