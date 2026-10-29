import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin
import RiftletCore
@testable import RiftletCapture

private final class CompletedCaptureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance() { lock.lock(); value.addTimeInterval(1); lock.unlock() }
}

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
        XCTAssertTrue(derivative.lastPathComponent.hasPrefix("."), "Owned derivative must stay outside the system collector")
        let mode = try FileManager.default.attributesOfItem(atPath: derivative.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        do {
            _ = try await importer.importBuiltInScreenshot(original: original, editedPNG: edited, outputDirectory: root)
            XCTFail("Derivative escaped its owned capture directory")
        } catch CaptureError.privatePathUnsafe {}
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    func testOverlappingSystemDirectoryKeepsOwnedCapturesSeparateWithoutDroppingSystemScreenshots() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let captures = root.appendingPathComponent("captures"), other = root.appendingPathComponent("other-system-location")
        for directory in [captures, other] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let clock = CompletedCaptureClock()
        let service = CaptureService(store: store, privateRoot: root, sourceDirectory: captures, now: { clock.read() })
        do {
            try await service.start()
            let owned = captures.appendingPathComponent("." + UUID().uuidString.lowercased() + ".png")
            let system = captures.appendingPathComponent("Screen Shot fixture.png")
            let original = try syntheticPNG(at: owned)
            _ = try syntheticPNG(at: system, red: 0.8)
            let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            // Real filesystem/xattr fixtures, not real screen or upload evidence.
            for url in [owned, system] {
                XCTAssertEqual(marker.withUnsafeBytes { setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }, 0)
            }
            try await service.rescan(); clock.advance(); try await service.rescan()
            // Exercise the departing-directory scan as well, before explicit
            // built-in import (for example while the markup window is open).
            clock.advance(); try await service.setSourceDirectory(other)
            clock.advance(); try await service.rescan()
            let collected = try await store.assets(includeUsed: true)
            XCTAssertEqual(collected.count, 1)
            XCTAssertEqual(collected.first?.image.origin, .systemScreenshot)
            XCTAssertEqual(collected.first?.image.sourceKey, try FileSignature.read(at: system).sourceKey)

            let importer = PrivateAssetImporter(privateRoot: root, store: store)
            let application = try await importer.importBuiltInScreenshot(original: owned, outputDirectory: captures)
            XCTAssertEqual(application.image.origin, .applicationScreenshot)
            try await service.setSourceDirectory(captures)
            clock.advance(); try await service.rescan()
            let coexist = try await store.assets(includeUsed: true)
            XCTAssertEqual(coexist.count, 2)
            XCTAssertEqual(Set(coexist.map { $0.image.origin.rawValue }), ["systemScreenshot", "applicationScreenshot"])
            XCTAssertEqual(try Data(contentsOf: owned), original)
            await service.stop()
        } catch {
            await service.stop()
            throw error
        }
    }

    func testBuiltInImportRejectsAnExistingOtherOriginWithoutRetaggingHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let captures = root.appendingPathComponent("captures"), source = captures.appendingPathComponent("legacy.png")
        let bytes = try syntheticPNG(at: source)
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        XCTAssertEqual(marker.withUnsafeBytes { setxattr(source.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }, 0)
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let importer = PrivateAssetImporter(privateRoot: root, store: store)
        let existing = try await importer.importCompletedScreenshot(at: source, origin: .systemScreenshot)
        do {
            _ = try await importer.importBuiltInScreenshot(original: source, outputDirectory: captures)
            XCTFail("Existing system provenance must not be returned as built-in success")
        } catch RiftletError.modeMismatch {}
        let unchanged = try await store.asset(id: existing.id)
        XCTAssertEqual(unchanged, existing)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testCompletedApplicationPNGIsCopiedExactlyAndOriginalIsRetained() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let captures = root.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let source = InteractiveScreenshotOutput.originalURL(in: captures, captureID: UUID())
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

    func testOwnedOriginalAndEditedFilesCannotEnterOverlappingActiveOrRetiredWatcher() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let captures = root.appendingPathComponent("captures"), other = root.appendingPathComponent("other")
        for directory in [captures, other] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let clock = CompletedImportClock()
        let service = CaptureService(store: store, privateRoot: root, sourceDirectory: captures, now: { clock.read() })
        try await service.start()
        do {
            let owned = InteractiveScreenshotOutput.originalURL(in: captures, captureID: UUID())
            let edited = InteractiveScreenshotOutput.editedURL(in: captures)
            let visible = captures.appendingPathComponent("new-system-screenshot.png")
            let bytes = try generatedPNG()
            // Generated bytes and synthetic xattrs exercise watcher admission;
            // these are never evidence of real system capture or TCC permission.
            for file in [owned, edited, visible] {
                try bytes.write(to: file); try markSyntheticScreenshot(file)
            }
            try await service.rescan()
            clock.advance()
            try await service.rescan()
            var records = try await store.assets()
            XCTAssertEqual(records.count, 1, "The active watcher must see only the visible system file")
            XCTAssertEqual(records.first?.image.sourceKey, try FileSignature.read(at: visible).sourceKey)
            try await service.setSourceDirectory(other)
            clock.advance()
            try await service.rescan()
            records = try await store.assets()
            XCTAssertEqual(records.count, 1, "Retiring the overlapping directory must not import owned files")
            let importer = PrivateAssetImporter(privateRoot: root, store: store)
            let selected = try await importer.importCompletedScreenshot(at: edited, origin: .applicationScreenshot)
            XCTAssertEqual(selected.image.origin, .applicationScreenshot)
            try await service.setSourceDirectory(captures)
            clock.advance()
            try await service.rescan()
            records = try await store.assets()
            XCTAssertEqual(records.count, 2, "Only the explicitly selected derivative joins the ordinary screenshot")
            XCTAssertFalse(records.contains { $0.image.sourceKey == (try? FileSignature.read(at: owned).sourceKey) })
            for file in [owned, edited, visible] { XCTAssertEqual(try Data(contentsOf: file), bytes) }
            let usage = try PrivateStorageUsage.measure(privateRoot: root)
            XCTAssertEqual(usage.areas.first(where: { $0.area == .captures })?.regularFileCount, 3)
            XCTAssertEqual(usage.areas.first(where: { $0.area == .captures })?.logicalBytes, UInt64(bytes.count * 3))
        } catch {
            await service.stop()
            throw error
        }
        await service.stop()
    }

    func testHiddenUneditedPNGKeepsExistingSystemMetadataRequirementAndOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let captures = root.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let source = InteractiveScreenshotOutput.originalURL(in: captures, captureID: UUID())
        let bytes = try generatedPNG()
        try bytes.write(to: source)
        // This marker exists only in an isolated synthetic test fixture.
        try markSyntheticScreenshot(source)
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let importer = PrivateAssetImporter(privateRoot: root, store: store)
        let record = try await importer.importCompletedScreenshot(at: source, origin: .systemScreenshot)
        XCTAssertEqual(record.image.origin, .systemScreenshot)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("media").appendingPathComponent(record.image.fileName)), bytes)
    }

    private func generatedPNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 12, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func markSyntheticScreenshot(_ url: URL) throws {
        let bytes = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        XCTAssertEqual(bytes.withUnsafeBytes { setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }, 0)
    }
}

private final class CompletedImportClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance() { lock.lock(); value.addTimeInterval(1); lock.unlock() }
}
