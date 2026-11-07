import XCTest
import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Darwin
import RiftletCore
@testable import RiftletCapture

/// Real files and SQLite exercise the committed-media optimization separately
/// from uncommitted journals. All inputs and replacements belong to a fresh test root.
final class RecoveryValidationTests: XCTestCase {
    private struct Manifest: Codable {
        let version: Int
        let image: ImportedAsset
    }

    private struct Fixture {
        let root: URL
        let storage: URL
        let source: URL
        let store: QueueStore
        let importer: PrivateAssetImporter
        let bytes: Data

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-recovery-validation-" + UUID().uuidString)
            storage = root.appendingPathComponent("private")
            source = root.appendingPathComponent("source.png")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            store = try QueueStore(databaseURL: storage.appendingPathComponent("queue.sqlite"))
            importer = PrivateAssetImporter(privateRoot: storage, store: store)
            bytes = try RecoveryValidationTests.validPNG()
            try bytes.write(to: source, options: .withoutOverwriting)
        }

        func importImage() async throws -> AssetRecord {
            try await importer.importStableFile(at: source, signature: FileSignature.read(at: source),
                                                origin: .synthetic, firstSeenAt: Date())
        }
        func media(_ image: ImportedAsset) -> URL { storage.appendingPathComponent("media/" + image.fileName) }
        func journal(_ image: ImportedAsset) -> URL { storage.appendingPathComponent("journal/" + image.id.uuidString.lowercased() + ".json") }
        func close() { try? FileManager.default.removeItem(at: root) }
    }

    private static func validPNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 14, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 14))
        let data = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return data as Data
    }

    private func target() -> TargetLease {
        TargetLease(adapterID: "recovery-validation", surface: .webChat, applicationID: "isolated.synthetic",
                    sessionID: "session", windowID: "window", tabID: "tab", documentID: "document",
                    composerID: "composer", draftGeneration: "draft")
    }

    private func setState(_ state: String, record: AssetRecord, store: QueueStore) async throws -> UUID? {
        switch state {
        case "archived":
            let fence = QueueInteractionFence()
            let archived = try await store.archiveIdle(before: Date().addingTimeInterval(600), fence: fence,
                                                       revision: fence.snapshot().revision)
            XCTAssertEqual(archived, [record.id])
        case "removed": try await store.removeFromQueue(record.id)
        case "failed", "unknown":
            let operation = try await store.prepare(assetID: record.id, target: target())
            if state == "failed" {
                try await store.cancelPrepared(operation.id, reason: "Isolated failed-before-input fixture")
            } else {
                try await store.markDispatchIntent(operation.id)
                try await store.markUnknown(operation.id, reason: "Original unresolved synthetic operation")
            }
            return operation.id
        default: XCTAssertEqual(state, "pending")
        }
        return nil
    }

    func testCommittedRecoveryPreservesEveryFullQueueRecordAndOriginalOperation() async throws {
        for state in ["pending", "archived", "removed", "failed", "unknown"] {
            let f = try Fixture(); defer { f.close() }
            let imported = try await f.importImage()
            let operationID = try await setState(state, record: imported, store: f.store)
            let before = try await f.store.assets(includeUsed: true)
            let operationBefore: TransferOperation?
            if let operationID { operationBefore = try await f.store.operation(id: operationID) }
            else { operationBefore = nil }
            let journalBefore = try Data(contentsOf: f.journal(imported.image))
            let report = try await f.importer.recover()
            let after = try await f.store.assets(includeUsed: true)
            XCTAssertEqual(report.adopted, 0, state)
            XCTAssertTrue(report.invalid.isEmpty && report.missing.isEmpty, state)
            XCTAssertEqual(after, before, state)
            XCTAssertEqual(try Data(contentsOf: f.source), f.bytes, state)
            XCTAssertEqual(try Data(contentsOf: f.media(imported.image)), f.bytes, state)
            XCTAssertEqual(try Data(contentsOf: f.journal(imported.image)), journalBefore, state)
            if let operationID {
                let operationAfter = try await f.store.operation(id: operationID)
                let start = try await f.store.uploadStartReceipt(for: operationID)
                XCTAssertEqual(operationAfter, operationBefore, state)
                XCTAssertNil(start, state)
            }
        }
    }

    func testMissingOriginalMediaRestoresUnknownWithoutChangingItsOperation() async throws {
        let f = try Fixture(); defer { f.close() }
        let imported = try await f.importImage()
        let preparedID = try await setState("unknown", record: imported, store: f.store)
        let operationID = try XCTUnwrap(preparedID)
        let before = try await f.store.asset(id: imported.id)
        let operation = try await f.store.operation(id: operationID)
        let media = f.media(imported.image), preserved = f.root.appendingPathComponent("preserved-original.png")
        try FileManager.default.moveItem(at: media, to: preserved)
        let absent = try await f.importer.recover()
        let missing = try await f.store.asset(id: imported.id)
        XCTAssertEqual(absent.missing, [imported.id])
        XCTAssertEqual(missing?.status, .missing)
        try FileManager.default.moveItem(at: preserved, to: media)
        let recovered = try await f.importer.recover()
        let after = try await f.store.asset(id: imported.id)
        let operationAfter = try await f.store.operation(id: operationID)
        let start = try await f.store.uploadStartReceipt(for: operationID)
        XCTAssertTrue(recovered.invalid.isEmpty && recovered.missing.isEmpty)
        XCTAssertEqual(after, before)
        XCTAssertEqual(operationAfter, operation)
        XCTAssertNil(start)
    }

    func testSameLengthCorruptionStillFailsHashAndPreservesUnknown() async throws {
        let f = try Fixture(); defer { f.close() }
        let imported = try await f.importImage()
        let preparedID = try await setState("unknown", record: imported, store: f.store)
        let operationID = try XCTUnwrap(preparedID)
        let operation = try await f.store.operation(id: operationID)
        var altered = f.bytes; altered[altered.count / 2] ^= 0xff
        try altered.write(to: f.media(imported.image))
        let report = try await f.importer.recover()
        let after = try await f.store.asset(id: imported.id)
        let operationAfter = try await f.store.operation(id: operationID)
        let start = try await f.store.uploadStartReceipt(for: operationID)
        XCTAssertEqual(altered.count, f.bytes.count)
        XCTAssertEqual(report.invalid, [imported.id])
        XCTAssertEqual(report.adopted, 0)
        XCTAssertEqual(after?.status, .missing)
        XCTAssertEqual(after?.image, imported.image)
        XCTAssertEqual(operationAfter, operation)
        XCTAssertNil(start)
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
    }

    func testJournalTupleMismatchCannotBorrowCommittedValidation() async throws {
        let f = try Fixture(); defer { f.close() }
        let imported = try await f.importImage()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(imported.image)) as? [String: Any])
        object["pixelWidth"] = imported.image.pixelWidth + 1
        let different = try JSONDecoder().decode(ImportedAsset.self, from: JSONSerialization.data(withJSONObject: object))
        try JSONEncoder().encode(Manifest(version: 1, image: different)).write(to: f.journal(imported.image))
        let report = try await f.importer.recover()
        let after = try await f.store.asset(id: imported.id)
        XCTAssertEqual(report.invalid, [imported.id])
        XCTAssertEqual(report.adopted, 0)
        XCTAssertEqual(after?.image, imported.image)
        XCTAssertEqual(after?.status, .missing)
        XCTAssertEqual(try Data(contentsOf: f.media(imported.image)), f.bytes)
    }

    func testSameBytesReplacedAtomicallyAfterHashAreRejectedByPathIdentity() async throws {
        let f = try Fixture(); defer { f.close() }
        let record = try await f.importImage(), media = f.media(record.image)
        let signature = try PrivateFiles.privateSignature(at: media)
        let originalLink = f.root.appendingPathComponent("preserved-original-inode.png")
        let replacement = f.root.appendingPathComponent("same-byte-replacement.png")
        try FileManager.default.linkItem(at: media, to: originalLink)
        try f.bytes.write(to: replacement, options: .withoutOverwriting)
        XCTAssertThrowsError(try PrivateFiles.verifyPreviouslyValidatedMedia(media, asset: record.image, signature: signature, afterHash: {
            guard Darwin.rename(replacement.path, media.path) == 0 else { throw CaptureError.io("test-atomic-replacement", errno) }
        })) { XCTAssertEqual($0 as? CaptureError, .unstableFile) }
        XCTAssertEqual(try Data(contentsOf: originalLink), f.bytes)
        XCTAssertEqual(try Data(contentsOf: media), f.bytes)
        XCTAssertEqual(try PrivateFiles.privateSignature(at: originalLink).inode, signature.inode)
        XCTAssertNotEqual(try PrivateFiles.privateSignature(at: media).inode, signature.inode)
        let after = try await f.store.asset(id: record.id)
        XCTAssertEqual(after, record)
    }

    func testCommittedHelperStillChecksDecodedMetadataAgainstDurableTuple() async throws {
        let f = try Fixture(); defer { f.close() }
        let record = try await f.importImage()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record.image)) as? [String: Any])
        object["pixelWidth"] = record.image.pixelWidth + 1
        let forged = try JSONDecoder().decode(ImportedAsset.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try PrivateFiles.verifyPreviouslyValidatedMedia(f.media(record.image), asset: forged,
            signature: PrivateFiles.privateSignature(at: f.media(record.image)))) {
            XCTAssertEqual($0 as? CaptureError, .invalidManifest)
        }
    }

    func testUncommittedMediaAndStagingStillRequireRealPixelDecode() async throws {
        for location in ["media", "staging"] {
            let f = try Fixture(); defer { f.close() }
            let bytes = Self.decodeInvalidPNG()
            let id = UUID(), fileName = id.uuidString.lowercased() + ".png"
            let image = ImportedAsset(id: id, sourceKey: "isolated-forged-" + id.uuidString, fileName: fileName,
                sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(bytes.count),
                pixelWidth: 24, pixelHeight: 14, mediaType: "image/png", origin: .synthetic)
            for directory in ["media", "staging", "journal"] {
                try FileManager.default.createDirectory(at: f.storage.appendingPathComponent(directory), withIntermediateDirectories: true)
            }
            let candidate = f.storage.appendingPathComponent(location + "/" + (location == "media" ? fileName : id.uuidString.lowercased() + ".part"))
            try bytes.write(to: candidate, options: .withoutOverwriting)
            // A complete readable header is intentionally insufficient for an uncommitted copy.
            let metadata = try ValidatedImage.inspectPreviouslyValidated(candidate, byteCount: Int64(bytes.count))
            XCTAssertEqual(metadata.width, 24); XCTAssertEqual(metadata.height, 14)
            XCTAssertThrowsError(try ValidatedImage.inspect(candidate, byteCount: Int64(bytes.count))) {
                XCTAssertEqual($0 as? CaptureError, .incompleteImage)
            }
            try JSONEncoder().encode(Manifest(version: 1, image: image)).write(to: f.journal(image), options: .withoutOverwriting)
            let report = try await f.importer.recover()
            let assets = try await f.store.assets(includeUsed: true)
            XCTAssertEqual(report.adopted, 0, location)
            XCTAssertEqual(report.invalid, [id], location)
            XCTAssertTrue(assets.isEmpty, location)
            XCTAssertEqual(try Data(contentsOf: candidate), bytes, location)
            XCTAssertEqual(try Data(contentsOf: f.source), f.bytes, location)
        }
    }

    func testPreviouslyValidatedMetadataRetainsHeaderAndLimitPolicies() throws {
        let f = try Fixture(); defer { f.close() }
        let full = try ValidatedImage.inspect(f.source, byteCount: Int64(f.bytes.count))
        let metadata = try ValidatedImage.inspectPreviouslyValidated(f.source, byteCount: Int64(f.bytes.count))
        XCTAssertEqual(metadata.width, full.width); XCTAssertEqual(metadata.height, full.height)
        XCTAssertEqual(metadata.mimeType, full.mimeType); XCTAssertEqual(metadata.fileExtension, full.fileExtension)
        for byteCount in [Int64(0), ValidatedImage.maximumBytes + 1] {
            XCTAssertThrowsError(try ValidatedImage.inspect(f.source, byteCount: byteCount)) { XCTAssertEqual($0 as? CaptureError, .imageTooLarge) }
            XCTAssertThrowsError(try ValidatedImage.inspectPreviouslyValidated(f.source, byteCount: byteCount)) { XCTAssertEqual($0 as? CaptureError, .imageTooLarge) }
        }
        let pdf = f.root.appendingPathComponent("not-a-raster.png")
        try Data("%PDF-1.4\nnot a raster image\n%%EOF".utf8).write(to: pdf)
        for read in [ValidatedImage.inspect, ValidatedImage.inspectPreviouslyValidated] {
            XCTAssertThrowsError(try read(pdf, Int64(Data(contentsOf: pdf).count))) { XCTAssertEqual($0 as? CaptureError, .unsupportedImage) }
        }
        let oversized = f.root.appendingPathComponent("oversized-header.png")
        let oversizedBytes = Self.decodeInvalidPNG(width: UInt32(ScreenshotImportLimits.dimension + 1))
        try oversizedBytes.write(to: oversized)
        for read in [ValidatedImage.inspect, ValidatedImage.inspectPreviouslyValidated] {
            XCTAssertThrowsError(try read(oversized, Int64(oversizedBytes.count))) { XCTAssertEqual($0 as? CaptureError, .imageTooLarge) }
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(f.source as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let multiFrame = f.root.appendingPathComponent("two-frames.tiff")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(multiFrame as CFURL, UTType.tiff.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(writer, image, nil); CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let multipleBytes = try Data(contentsOf: multiFrame)
        for read in [ValidatedImage.inspect, ValidatedImage.inspectPreviouslyValidated] {
            XCTAssertThrowsError(try read(multiFrame, Int64(multipleBytes.count))) { XCTAssertEqual($0 as? CaptureError, .unsupportedImage) }
        }
    }

    /// Valid PNG structure/CRC and dimensions, but a reserved DEFLATE block type.
    /// The test explicitly proves metadata success and pixel-decode failure on the actual ImageIO implementation.
    private static func decodeInvalidPNG(width: UInt32 = 24) -> Data {
        func uint32(_ value: UInt32) -> Data {
            Data([UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                  UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
        }
        func chunk(_ type: String, _ payload: Data) -> Data {
            let content = Data(type.utf8) + payload
            var crc: UInt32 = 0xffffffff
            for byte in content {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
            }
            return uint32(UInt32(payload.count)) + content + uint32(crc ^ 0xffffffff)
        }
        let header = uint32(width) + uint32(14) + Data([8, 6, 0, 0, 0])
        return Data([137, 80, 78, 71, 13, 10, 26, 10]) + chunk("IHDR", header)
            + chunk("IDAT", Data([0x78, 0x9c, 0x07, 0, 0, 0, 0])) + chunk("IEND", Data())
    }
}
