import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Generated images and a controlled executor on a private store. This
/// exercises ordinary preflight, dispatch and observation without a real chat.
final class WebScreenshotTransportTests: XCTestCase {
    func testOrdinaryProductDeliversLargeJPEGGrayscalePNGHEICAndOrientedTIFF() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-format-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jpeg = try XCTUnwrap(Data(base64Encoded: "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAABKADAAQAAAABAAAABAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgABAAEAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A+iKKKK+4Pjz/2Q=="))
        var largeJPEG = Data(jpeg.prefix(2))
        var segment = Data([255, 239, 255, 255]); segment.append(Data(repeating: 97, count: 65_533))
        for _ in 0..<129 { largeJPEG.append(segment) }
        largeJPEG.append(jpeg.dropFirst(2))
        let gray = try grayImage(width: 4097, height: 4097)
        let png = try encode(gray, type: .png)
        let tiff = try encode(grayImage(width: 3, height: 2), type: .tiff, orientation: 6)
        let heic = try XCTUnwrap(Data(base64Encoded: "AAAAKGZ0eXBoZWljAAAAAG1pZjFNaUhFTWlQcm1pYWZNaUhCaGVpYwAAAoFtZXRhAAAAAAAAACFoZGxyAAAAAAAAAABwaWN0AAAAAAAAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAA5waXRtAAAAAAABAAAAOGlpbmYAAAAAAAIAAAAVaW5mZQIAAAAAAQAAaHZjMQAAAAAVaW5mZQIAAAEAAgAAaHZjMQAAAAAaaXJlZgAAAAAAAAAOYXV4bAACAAEAAQAAAaRpcHJwAAABe2lwY28AAAATY29scm5jbHgAAgACAAaAAAAADGNsbGkAywBAAAAAFGlzcGUAAAAAAAAABAAAAAQAAAAJaXJvdAAAAAAQcGl4aQAAAAADCAgIAAAADnBpeGkAAAAAAQgAAAA3YXV4QwAAAAB1cm46bXBlZzpoZXZjOjIwMTU6YXV4aWQ6MQAAAAAMAAAACE4BpQQAAf5AAAAAcWh2Y0MBA3AAAACwAAAAAAAe8AD8/fj4AAALA6AAAQAXQAEMAf//A3AAAAMAsAAAAwAAAwAecCShAAEAI0IBAQNwAAADALAAAAMAAAMAHqAUIEHAnw/iHuRZVNwICBgCogABAAlEAcBhcshAUyQAAABxaHZjQwEECAAAAL/IAAAAAB7wAPz8+PgAAAsDoAABABdAAQwB//8ECAAAAwC/yAAAAwAAHhcCQKEAAQAjQgEBBAgAAAMAv8gAAAMAAB7AUIEHATsHuIF7kWVTcCAgIAiiAAEACUQBwGHSyEBTJAAAACFpcG1hAAAAAAAAAAIAAQaBAgMFiIQAAgUDBoeJhAAAACxpbG9jAAAAAEQAAAIAAQAAAAEAAAK5AAAAPQACAAAAAQAAAvYAAAAUAAAAAW1kYXQAAAAAAAAAYQAAADkoAa+i9kaBfP/+O1Pr/HH//vnz1X/8GJ//2L6f4WD3TLJn+iD5wjnkPhf11/vNfCL2FfgrcISbIrgAAAAQKAGvTsCSkCNF8UBhZRnBPg=="))
        let samples: [(Data, String, String, Int, Int, AssetOrigin)] = [
            (largeJPEG, "image/jpeg", "jpg", 4, 4, .systemScreenshot),
            (png, "image/png", "png", 4097, 4097, .applicationScreenshot),
            (tiff, "image/tiff", "tiff", 3, 2, .systemScreenshot),
            (heic, "image/heic", "heic", 4, 4, .applicationScreenshot)]
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "fixture", windowID: "1", tabID: "2", documentID: "doc", composerID: "composer", draftGeneration: "draft")
        for (source, mime, ext, width, height, origin) in samples {
            let file = root.appendingPathComponent(UUID().uuidString + "." + ext)
            try source.write(to: file)
            let hash = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
            let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent, sha256: hash,
                byteCount: Int64(source.count), pixelWidth: width, pixelHeight: height, mediaType: mime, origin: origin)
            _ = try await store.importAsset(asset)
            let bridge = FormatBridge()
            let adapter = WebAttachmentAdapter(mediaDirectory: root, executor: bridge, program: try ChatGPTWebPageProgram.load(),
                mode: .ordinaryProduct, profile: OrdinaryProductScreenshotScope.systemProfile, polling: .disabled,
                productStore: store, productOrigins: [.systemScreenshot, .applicationScreenshot])
            try await adapter.preflight(asset: asset, fileURL: file)
            let prepared = try await store.prepare(assetID: asset.id, target: target)
            let invocation = try await store.markDispatchIntent(prepared.id)
            let saved = try await store.operation(id: prepared.id)
            let request = TransferRequest(operation: try XCTUnwrap(saved), asset: asset, fileURL: file, invocationID: invocation)
            let receipt = try await adapter.append(request)
            XCTAssertEqual(receipt.outcome, .uploadStarted); XCTAssertEqual(receipt.assetSHA256, hash)
            _ = try await store.apply(receipt)
            let (begin, delivered, commits) = await bridge.result()
            XCTAssertEqual(commits, 1); XCTAssertEqual(begin?.identity?.assetSHA256, hash)
            XCTAssertEqual(begin?.byteCount, Int64(delivered.count)); XCTAssertEqual(try Data(contentsOf: file), source)
            let encodedMIME = mime == "image/jpeg" ? mime : "image/png"
            XCTAssertEqual(begin?.mediaType, encodedMIME)
            if mime == encodedMIME {
                XCTAssertEqual(delivered, source)
            } else {
                let decoded = try XCTUnwrap(CGImageSourceCreateWithData(delivered as CFData, nil))
                XCTAssertEqual(CGImageSourceGetType(decoded) as String?, UTType.png.identifier)
                let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
                XCTAssertEqual(pixels.width, ext == "tiff" ? height : width)
                XCTAssertEqual(pixels.height, ext == "tiff" ? width : height)
                if ext == "tiff" {
                    let original = try XCTUnwrap(CGImageSourceCreateWithData(source as CFData, nil))
                    let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: width] as CFDictionary
                    let expected = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(original, 0, options))
                    XCTAssertEqual(try luminance(pixels), try luminance(expected))
                }
            }
            let registered = try await store.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: request))
            XCTAssertNotNil(registered)
        }
    }

    private func grayImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0.15, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return try XCTUnwrap(context.makeImage())
    }

    private func encode(_ image: CGImage, type: UTType, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        let target = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(target, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(target))
        return data as Data
    }

    private func luminance(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height))
    }
}

private actor FormatBridge: WebBridgeExecutor {
    private var begin: WebBridgeCommand?
    private var bytes = Data()
    private var commits = 0
    func result() -> (WebBridgeCommand?, Data, Int) { (begin, bytes, commits) }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        let identity = try XCTUnwrap(command.identity)
        switch command.action {
        case .begin, .chunk:
            if command.action == .begin { begin = command }
            if let encoded = command.chunkBase64 { bytes.append(try XCTUnwrap(Data(base64Encoded: encoded))) }
            return try JSONSerialization.data(withJSONObject: ["operationID": identity.operationID.uuidString,
                "attempt": identity.attempt, "nextChunk": command.action == .begin ? 0 : (command.chunkIndex ?? -1) + 1])
        case .commit:
            commits += 1
            let start = ObservedUploadStart(version: 1, signal: .attachmentAccepted, evidenceID: UUID().uuidString,
                inputCount: 1, inputSequence: 1, startSequence: 2, previousProgress: 0, currentProgress: 0,
                inputObservedAtMS: 10, startObservedAtMS: 11)
            return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 2,
                provenance: .init(source: .integratedDevelopment, evidenceID: "screenshot-handoff-20261105-v17"),
                observation: .init(identity: identity, state: .uploadStarted, attachmentID: "format-" + identity.operationID.uuidString,
                    exactImageIdentity: true, belongsToOriginalDraft: true, uploadStart: start)))
        default: throw WebAdapterError.invalidRequest
        }
    }
}
