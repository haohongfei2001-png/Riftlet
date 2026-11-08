import XCTest
import Foundation
import ImageIO
import CryptoKit
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

    func makePNG(at url: URL, red: CGFloat = 0.3, description: String? = nil) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        let properties = description.map { [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: $0]] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
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

    // Seed an existing v1 private journal and media as written by the old importer.
    // Its original filename and volume were never part of that record.
    private func journal(_ source: URL, key: String, in fixture: Fixture) throws -> ImportedAsset {
        struct Manifest: Encodable { let version = 1; let image: ImportedAsset }
        let bytes = try Data(contentsOf: source)
        let id = UUID()
        let name = id.uuidString.lowercased() + ".png"
        let image = ImportedAsset(id: id, sourceKey: key, fileName: name,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 32, pixelHeight: 18, mediaType: "image/png")
        for (folder, file, data) in [("media", name, bytes),
            ("journal", id.uuidString.lowercased() + ".json", try JSONEncoder().encode(Manifest(image: image)))] {
            let directory = fixture.privateRoot.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file)
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return image
    }

    func testMountNumberChangesDoNotChangeAnOccurrenceAndVolumesRemainDistinct() async throws {
        let f = try Fixture(); defer { f.close() }
        let url = f.source.appendingPathComponent("capture.png")
        try makePNG(at: url); try markScreenshot(url)
        let signature = try FileSignature.read(at: url)
        let volume = try XCTUnwrap(url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString)
        XCTAssertEqual(signature.sourceKey, "volume:\(volume.lowercased()):\(signature.fileID)")
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(signature)) as? [String: Any])
        fields["device"] = signature.device + 1
        func decoded() throws -> FileSignature {
            try JSONDecoder().decode(FileSignature.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        let remounted = try decoded()
        XCTAssertNotEqual(remounted, signature)
        XCTAssertEqual(remounted.sourceKey, signature.sourceKey)
        // An unrelated disk with exactly the same file identity, name and bytes.
        fields["volumeUUID"] = UUID().uuidString
        let other = try decoded()
        let previous = try journal(url, key: other.sourceKey, in: f)
        let record = try await f.importer.importFile(at: url)
        XCTAssertNotEqual(record.id, previous.id)
        XCTAssertNotEqual(record.image.sourceKey, previous.sourceKey)
        XCTAssertEqual(record.image.sha256, previous.sha256)
        let reopened = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        let again = try await reopened.importFile(at: url)
        XCTAssertEqual(again.id, record.id)

        fields.removeValue(forKey: "volumeUUID")
        let unwitnessed = try decoded()
        XCTAssertEqual(FileSignature.legacyFileID(unwitnessed.sourceKey), signature.fileID)
        do {
            _ = try await reopened.importStableFile(at: url, signature: unwitnessed, firstSeenAt: Date())
            XCTFail("A new import requires a persistent volume identifier")
        } catch CaptureError.sourceVolumeUnidentified {}
        let rows = try await f.store.assets(includeUsed: true)
        XCTAssertEqual(Set(rows.map(\.id)), [record.id, previous.id])
    }

    func testSameNameReplacementWithTheSameBytesCreatesANewOccurrence() async throws {
        let f = try Fixture(); defer { f.close() }
        let path = f.source.appendingPathComponent("capture.png")
        let moved = f.source.appendingPathComponent("retained-original.png")
        try makePNG(at: path); try markScreenshot(path)
        let first = try await f.importer.importFile(at: path)
        try FileManager.default.moveItem(at: path, to: moved)
        try Data(contentsOf: moved).write(to: path); try markScreenshot(path)
        let next = try await f.importer.importFile(at: path)
        let original = try await f.importer.importFile(at: moved)
        XCTAssertEqual(first.id, original.id)
        XCTAssertNotEqual(first.id, next.id)
        XCTAssertEqual(first.image.sha256, next.image.sha256)
    }

    func testLegacyOriginalEditedInPlaceRemainsUnconfirmedAndPreservesUnknown() async throws {
        let f = try Fixture(); defer { f.close() }
        let url = f.source.appendingPathComponent("possibly-old.png")
        let neighbor = f.source.appendingPathComponent("new-same-pixels.png")
        try makePNG(at: url, description: "capture-A"); try markScreenshot(url)
        let original = try Data(contentsOf: url)
        let signature = try FileSignature.read(at: url)
        let legacy = try journal(url, key: "\(signature.device + 1):\(signature.fileID)", in: f)
        let recovered = try await f.importer.recover()
        XCTAssertEqual(recovered.adopted, 1)
        let target = TargetLease(adapterID: "local-test", surface: .webChat, applicationID: "fixture-browser",
            sessionID: "fixture-session", windowID: "w", documentID: "d", composerID: "c", draftGeneration: "g")
        let operation = try await f.store.prepare(assetID: legacy.id, target: target)
        _ = try await f.store.markDispatchIntent(operation.id)
        try await f.store.markUnknown(operation.id, reason: "fixture-unknown")
        let before = try await f.store.asset(id: legacy.id)
        let evidence = try await f.store.operation(id: operation.id)
        XCTAssertEqual(before?.status, .unknown)
        // Keep the file open while changing bytes first at the same length, then at
        // another length. Its inode and birth time stay exactly the same in both cases.
        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        for (index, description) in ["capture-A", "capture-B", "a longer edited description"].enumerated() {
            if index > 0 {
                let fixture = f.root.appendingPathComponent("edit-\(index).png")
                try makePNG(at: fixture, description: description)
                let edited = try Data(contentsOf: fixture)
                XCTAssertNotEqual(edited, original)
                XCTAssertEqual(edited.count == original.count, index == 1)
                try writer.truncate(atOffset: 0)
                try writer.seek(toOffset: 0)
                try writer.write(contentsOf: edited)
                try writer.synchronize()
            }
            XCTAssertEqual(try FileSignature.read(at: url).sourceKey, signature.sourceKey)
            do {
                _ = try await f.importer.importFile(at: url)
                XCTFail("Changed bytes cannot prove that this is a different source occurrence")
            } catch CaptureError.historicalSourceUnconfirmed {}
        }
        try Data(contentsOf: url).write(to: neighbor); try markScreenshot(neighbor)
        let new = try await f.importer.importFile(at: neighbor)
        let after = try await f.store.asset(id: legacy.id)
        let retained = try await f.store.operation(id: operation.id)
        let rows = try await f.store.assets(includeUsed: true)
        XCTAssertEqual(before, after)
        XCTAssertEqual(evidence, retained)
        XCTAssertNotEqual(new.image.sha256, legacy.sha256)
        XCTAssertEqual(Set(rows.map(\.id)), [legacy.id, new.id])
        for folder in ["media", "journal"] {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.privateRoot.appendingPathComponent(folder).path).count, 2)
        }
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
