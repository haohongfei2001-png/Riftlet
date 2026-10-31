import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Darwin
@testable import RiftletCapture
import RiftletCore

/// Generated image fixtures with synthetic screenshot metadata, never private system
/// captures. These tests prove local byte preservation, not Web upload admission.
final class SystemScreenshotFidelityTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let source: URL
        let privateRoot: URL
        let store: QueueStore

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-image-fidelity-" + UUID().uuidString)
            source = root.appendingPathComponent("source", isDirectory: true)
            privateRoot = root.appendingPathComponent("private", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            store = try QueueStore(databaseURL: privateRoot.appendingPathComponent("queue.sqlite"))
        }

        func close() { try? FileManager.default.removeItem(at: root) }
        func media(for record: AssetRecord) -> URL {
            privateRoot.appendingPathComponent("media").appendingPathComponent(record.image.fileName)
        }
    }

    private func markScreenshot(_ url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        XCTAssertEqual(data.withUnsafeBytes {
            setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0)
        }, 0)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        try markScreenshot(url)
    }

    private func importAndCheck(_ url: URL, fixture: Fixture) async throws -> AssetRecord {
        let bytes = try Data(contentsOf: url)
        let expectedHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let importer = PrivateAssetImporter(privateRoot: fixture.privateRoot, store: fixture.store)
        let record = try await importer.importStableFile(at: url, signature: FileSignature.read(at: url), firstSeenAt: Date())
        XCTAssertEqual(record.image.origin, .systemScreenshot)
        XCTAssertEqual(record.image.sha256, expectedHash)
        XCTAssertEqual(record.image.byteCount, Int64(bytes.count))
        XCTAssertEqual(try Data(contentsOf: fixture.media(for: record)), bytes)
        XCTAssertEqual(try Data(contentsOf: url), bytes)

        // Reopen the same SQLite v3 store and recover the existing private journal.
        // Recovery must retain the complete original image, not rewrite a Web-sized
        // derivative or reinterpret it as a new capture occurrence.
        let reopened = try QueueStore(databaseURL: fixture.privateRoot.appendingPathComponent("queue.sqlite"))
        let recovering = PrivateAssetImporter(privateRoot: fixture.privateRoot, store: reopened)
        let report = try await recovering.recover()
        XCTAssertTrue(report.invalid.isEmpty)
        XCTAssertTrue(report.missing.isEmpty)
        XCTAssertEqual(report.adopted, 0)
        let restored = try await reopened.asset(id: record.id)
        let all = try await reopened.assets(includeUsed: true)
        XCTAssertEqual(restored?.image, record.image)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.media(for: record)), bytes)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        return record
    }

    func testPNGAboveWebByteLimitIsPreservedLocallyAcrossRestartWithoutCompression() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let width = 2_048, height = 1_536
        var pixels = Data(count: width * height * 4)
        // Deterministic incompressible RGB content creates an actual valid >8 MiB
        // PNG, rather than lying about metadata or adding an unrelated file tail.
        pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            var state: UInt32 = 0x7c3a91e5
            for offset in stride(from: 0, to: buffer.count, by: 4) {
                state ^= state << 13; state ^= state >> 17; state ^= state << 5
                buffer[offset] = UInt8(truncatingIfNeeded: state >> 16)
                buffer[offset + 1] = UInt8(truncatingIfNeeded: state >> 8)
                buffer[offset + 2] = UInt8(truncatingIfNeeded: state)
                buffer[offset + 3] = 255
            }
        }
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = fixture.source.appendingPathComponent("generated-large-system-fixture.png")
        try writePNG(image, to: url)
        let size = try FileSignature.read(at: url).size
        XCTAssertGreaterThan(size, 8 * 1024 * 1024, "The fixture must cross the current Web byte limit")
        XCTAssertLessThan(size, ValidatedImage.maximumBytes)
        let record = try await importAndCheck(url, fixture: fixture)
        XCTAssertEqual(record.image.pixelWidth, width)
        XCTAssertEqual(record.image.pixelHeight, height)
        XCTAssertEqual(record.image.mediaType, "image/png")
    }

    func testSixteenBitPNGProfileAndDepthSurvivePrivateCopyAndRecovery() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let width = 24, height = 16
        // A 16-bit integer PNG is not an HDR/gain-map acceptance claim. This
        // checks that local storage never silently down-converts it to 8 bits.
        var pixels = Data(count: width * height * 8)
        pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            for offset in stride(from: 0, to: buffer.count, by: 8) {
                let value = UInt16((offset / 8) * 127)
                buffer[offset] = UInt8(truncatingIfNeeded: value >> 8)
                buffer[offset + 1] = UInt8(truncatingIfNeeded: value)
                buffer[offset + 2] = 0x50; buffer[offset + 3] = 0x31
                buffer[offset + 4] = 0xb4; buffer[offset + 5] = 0x69
                buffer[offset + 6] = 0xff; buffer[offset + 7] = 0xff
            }
        }
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(.byteOrder16Big)
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 8, space: colorSpace, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = fixture.source.appendingPathComponent("generated-sixteen-bit.png")
        try writePNG(image, to: url)
        let record = try await importAndCheck(url, fixture: fixture)
        let originalSource = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let privateSource = try XCTUnwrap(CGImageSourceCreateWithURL(fixture.media(for: record) as CFURL, nil))
        let originalImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(originalSource, 0, nil))
        let privateImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(privateSource, 0, nil))
        XCTAssertEqual(originalImage.bitsPerComponent, 16, "Generator must produce the format claimed by the test")
        XCTAssertEqual(privateImage.bitsPerComponent, 16)
        XCTAssertEqual(privateImage.width, width)
        XCTAssertEqual(privateImage.height, height)
        let originalProfile = try XCTUnwrap(originalImage.colorSpace?.copyICCData())
        let privateProfile = try XCTUnwrap(privateImage.colorSpace?.copyICCData())
        XCTAssertEqual(privateProfile as Data, originalProfile as Data)
    }
}
