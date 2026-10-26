import XCTest
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Darwin
@testable import RiftletCapture
import RiftletCore

final class CaptureTests: XCTestCase {
    struct Fixture {
        let root: URL
        let source: URL
        let privateRoot: URL
        let store: QueueStore
        let importer: PrivateAssetImporter

        init(mode: StoreMode = .production) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-test-" + UUID().uuidString, isDirectory: true)
            source = root.appendingPathComponent("source", isDirectory: true)
            privateRoot = root.appendingPathComponent("private", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)
            store = try QueueStore(databaseURL: privateRoot.appendingPathComponent("queue.sqlite"), mode: mode)
            importer = PrivateAssetImporter(privateRoot: privateRoot, store: store)
        }

        func close() { try? FileManager.default.removeItem(at: root) }
    }

    func makePNG(at url: URL, red: CGFloat = 0.3) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func markScreenshot(_ url: URL, value: Any = true) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        let result = data.withUnsafeBytes { setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }
        XCTAssertEqual(result, 0, "Synthetic metadata fixture should be writable")
    }

    func testPrivateCopyPreservesOriginalAndRealCodecAndPermissions() async throws {
        let f = try Fixture(); defer { f.close() }
        // Deliberately misleading source extension: importer must inspect the actual encoding.
        let source = f.source.appendingPathComponent("synthetic-image.jpeg")
        try makePNG(at: source); try markScreenshot(source)
        let original = try Data(contentsOf: source)
        let record = try await f.importer.importFile(at: source)
        XCTAssertEqual(record.image.mediaType, "image/png")
        XCTAssertTrue(record.image.fileName.hasSuffix(".png"))
        XCTAssertEqual(record.image.pixelWidth, 32)
        XCTAssertEqual(record.image.pixelHeight, 18)
        let copy = f.privateRoot.appendingPathComponent("media").appendingPathComponent(record.image.fileName)
        XCTAssertEqual(try Data(contentsOf: copy), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let permission = try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permission?.intValue, 0o600)
        let rootPermission = try FileManager.default.attributesOfItem(atPath: f.privateRoot.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(rootPermission?.intValue, 0o700)
    }

    func testRepeatedSourceEventDeduplicatesButIdenticalNewCaptureDoesNot() async throws {
        let f = try Fixture(); defer { f.close() }
        let first = f.source.appendingPathComponent("first.png")
        let second = f.source.appendingPathComponent("second.png")
        try makePNG(at: first); try markScreenshot(first)
        let a = try await f.importer.importFile(at: first)
        let sameEvent = try await f.importer.importFile(at: first)
        XCTAssertEqual(a.id, sameEvent.id)
        // Writing the same bytes creates a distinct occurrence/inode, not a content duplicate.
        try Data(contentsOf: first).write(to: second); try markScreenshot(second)
        let b = try await f.importer.importFile(at: second)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.image.sha256, b.image.sha256)
        let all = try await f.store.assets()
        XCTAssertEqual(all.count, 2)
    }

    func testMissingFalseAndNumericMetadataAreNotAccepted() async throws {
        let f = try Fixture(); defer { f.close() }
        let source = f.source.appendingPathComponent("截图.png")
        try makePNG(at: source)
        do { _ = try await f.importer.importFile(at: source); XCTFail("Missing metadata should stay pending") }
        catch { XCTAssertEqual(error as? CaptureError, .metadataPending) }
        try markScreenshot(source, value: false)
        do { _ = try await f.importer.importFile(at: source); XCTFail("False metadata is not a screenshot") }
        catch { XCTAssertEqual(error as? CaptureError, .notScreenshot) }
        try markScreenshot(source, value: 1)
        do { _ = try await f.importer.importFile(at: source); XCTFail("Numeric 1 is not a boolean true") }
        catch { XCTAssertEqual(error as? CaptureError, .notScreenshot) }
        try markScreenshot(source)
        _ = try await f.importer.importFile(at: source)
        let all = try await f.store.assets()
        XCTAssertEqual(all.count, 1)
    }

    func testTruncatedAndChangingFilesDoNotEnterQueue() async throws {
        let f = try Fixture(); defer { f.close() }
        let complete = f.source.appendingPathComponent("complete.png")
        let partial = f.source.appendingPathComponent("partial.png")
        try makePNG(at: complete)
        let bytes = try Data(contentsOf: complete)
        try bytes.prefix(bytes.count / 2).write(to: partial)
        try markScreenshot(partial)
        do { _ = try await f.importer.importFile(at: partial); XCTFail("Half image cannot be imported") }
        catch { XCTAssertTrue(error is CaptureError) }
        let signature = try FileSignature.read(at: partial)
        try bytes.write(to: partial)
        try markScreenshot(partial)
        do {
            _ = try await f.importer.importStableFile(at: partial, signature: signature, firstSeenAt: Date())
            XCTFail("Source version change must invalidate a stability observation")
        } catch { XCTAssertEqual(error as? CaptureError, .unstableFile) }
        let all = try await f.store.assets()
        XCTAssertTrue(all.isEmpty)
        _ = try await f.importer.importFile(at: partial)
        let recovered = try await f.store.assets()
        XCTAssertEqual(recovered.count, 1)
    }

    func testSymlinkSourceIsRejectedAndOriginalIsUntouched() async throws {
        let f = try Fixture(); defer { f.close() }
        let source = f.source.appendingPathComponent("actual.png")
        let link = f.source.appendingPathComponent("alias.png")
        try makePNG(at: source); try markScreenshot(source)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        do { _ = try await f.importer.importFile(at: link); XCTFail("Symlink is outside source identity contract") }
        catch { XCTAssertTrue(error is CaptureError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let all = try await f.store.assets()
        XCTAssertTrue(all.isEmpty)
    }

    func testRecoveryAdoptsJournaledMediaAndDoesNotDeleteOriginal() async throws {
        let f = try Fixture(); defer { f.close() }
        let source = f.source.appendingPathComponent("recover.png")
        try makePNG(at: source); try markScreenshot(source)
        let original = try await f.importer.importFile(at: source)
        // A fresh index plus the same durable private manifest/media is equivalent to
        // a crash after promotion and before the original SQLite insert.
        let replacementStore = try QueueStore(databaseURL: f.privateRoot.appendingPathComponent("recovered.sqlite"))
        let recovering = PrivateAssetImporter(privateRoot: f.privateRoot, store: replacementStore)
        let report = try await recovering.recover()
        XCTAssertEqual(report.adopted, 1)
        let recovered = try await replacementStore.asset(id: original.id)
        XCTAssertEqual(recovered?.image, original.image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let second = try await recovering.recover()
        XCTAssertEqual(second.adopted, 0)
    }

    func testRecoveryFinishesJournaledStagingPromotion() async throws {
        let f = try Fixture(); defer { f.close() }
        let source = f.source.appendingPathComponent("staged.png")
        try makePNG(at: source); try markScreenshot(source)
        let original = try await f.importer.importFile(at: source)
        let media = f.privateRoot.appendingPathComponent("media").appendingPathComponent(original.image.fileName)
        let stage = f.privateRoot.appendingPathComponent("staging").appendingPathComponent(original.id.uuidString.lowercased() + ".part")
        try FileManager.default.moveItem(at: media, to: stage)
        let replacementStore = try QueueStore(databaseURL: f.privateRoot.appendingPathComponent("staged-recovery.sqlite"))
        let recovering = PrivateAssetImporter(privateRoot: f.privateRoot, store: replacementStore)
        let report = try await recovering.recover()
        XCTAssertEqual(report.adopted, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.path))
    }

    func testRecoveryPreservesAndMarksMissingCopy() async throws {
        let f = try Fixture(); defer { f.close() }
        let source = f.source.appendingPathComponent("missing.png")
        try makePNG(at: source); try markScreenshot(source)
        let original = try await f.importer.importFile(at: source)
        let media = f.privateRoot.appendingPathComponent("media").appendingPathComponent(original.image.fileName)
        let mediaBytes = try Data(contentsOf: media)
        try FileManager.default.removeItem(at: media)
        let report = try await f.importer.recover()
        XCTAssertTrue(report.missing.contains(original.id))
        let record = try await f.store.asset(id: original.id)
        XCTAssertEqual(record?.status, .missing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        try mediaBytes.write(to: media)
        _ = try await f.importer.recover()
        let restored = try await f.store.asset(id: original.id)
        XCTAssertEqual(restored?.status, .pending)
    }

    func testSimulationRejectsRealOriginBeforePrivateCopy() async throws {
        let f = try Fixture(mode: .simulation); defer { f.close() }
        let source = f.source.appendingPathComponent("real-origin.png")
        try makePNG(at: source); try markScreenshot(source)
        do { _ = try await f.importer.importFile(at: source); XCTFail("Simulation must reject real origin") }
        catch { XCTAssertEqual(error as? RiftletError, .modeMismatch) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.privateRoot.appendingPathComponent("media").path))
        _ = try await f.importer.importFile(at: source, origin: .synthetic)
        let all = try await f.store.assets()
        XCTAssertEqual(all.count, 1)
    }

    func testRecoveryRejectsSameLengthCorruption() async throws {
        let f = try Fixture(); defer { f.close() }
        let source = f.source.appendingPathComponent("integrity.png")
        try makePNG(at: source); try markScreenshot(source)
        let original = try await f.importer.importFile(at: source)
        let media = f.privateRoot.appendingPathComponent("media").appendingPathComponent(original.image.fileName)
        var corrupted = try Data(contentsOf: media)
        corrupted[corrupted.count / 2] ^= 0xff
        try corrupted.write(to: media)
        let report = try await f.importer.recover()
        XCTAssertTrue(report.invalid.contains(original.id))
        let record = try await f.store.asset(id: original.id)
        XCTAssertEqual(record?.status, .missing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testOrdinaryImagesDoNotStarveLaterScreenshot() async throws {
        let f = try Fixture(); defer { f.close() }
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.source)
        try await service.start()
        let template = f.root.appendingPathComponent("template.png")
        try makePNG(at: template)
        let bytes = try Data(contentsOf: template)
        for i in 0..<130 {
            let ordinary = f.source.appendingPathComponent("ordinary-\(i).png")
            try bytes.write(to: ordinary)
            try markScreenshot(ordinary, value: false)
        }
        let screenshot = f.source.appendingPathComponent("real-synthetic-screenshot.png")
        try bytes.write(to: screenshot); try markScreenshot(screenshot)
        try await service.rescan()
        for _ in 0..<30 {
            if try await f.store.assets().count == 1 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        await service.stop()
        let records = try await f.store.assets()
        XCTAssertEqual(records.count, 1)
    }

    func testServiceBaselinesHistoryAndRecoversCaptureMadeWhileStopped() async throws {
        let f = try Fixture(); defer { f.close() }
        let old = f.source.appendingPathComponent("old.png")
        try makePNG(at: old); try markScreenshot(old)
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.source)
        try await service.start()
        let baseline = try await f.store.assets()
        XCTAssertTrue(baseline.isEmpty)
        await service.stop()
        let fresh = f.source.appendingPathComponent("new.png")
        try makePNG(at: fresh); try markScreenshot(fresh)
        let restart = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.source)
        try await restart.start()
        for _ in 0..<20 {
            if try await f.store.assets().count == 1 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        await restart.stop()
        let result = try await f.store.assets()
        XCTAssertEqual(result.count, 1)
    }
}
