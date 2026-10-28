import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import RiftletCore
import RiftletUI

/// Fixtures for the standalone acceptance tool. These fixtures have no capture
/// service, queue database, adapter or access to the production media directory.
enum SyntheticScene {
    static let supportedCounts = [2, 3, 12, 16]

    static func makeMedia(in directory: URL) throws -> [AssetRecord] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return try (1...16).map { index in
            let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
            let dimensions = [(360, 220), (220, 360), (256, 256), (96, 768), (768, 96)][(index - 1) % 5]
            let fileName = String(format: "acceptance-%02d.png", index)
            let file = directory.appendingPathComponent(fileName)
            try writeImage(to: file, index: index, width: dimensions.0, height: dimensions.1)
            let bytes = try Data(contentsOf: file)
            let time = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            return AssetRecord(image: ImportedAsset(
                id: id, sourceKey: "acceptance-fixture-v1-\(index)", fileName: fileName,
                sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                byteCount: Int64(bytes.count), pixelWidth: dimensions.0, pixelHeight: dimensions.1,
                mediaType: "image/png", capturedAt: time, firstSeenAt: time, importedAt: time,
                origin: .synthetic), sequence: Int64(index))
        }
    }

    static func records(from fixtures: [AssetRecord], count: Int) throws -> [AssetRecord] {
        guard supportedCounts.contains(count), fixtures.count >= count,
              fixtures.allSatisfy({ $0.image.origin == .synthetic }) else {
            throw Failure.invalidFixture
        }
        return Array(fixtures.prefix(count))
    }

    /// This deliberately supplies display states directly. It does not pretend to be
    /// an upload receipt or exercise the product's persistence/admission policy.
    static func displaying(_ status: QueueStatus, assetID: UUID,
                           in records: [AssetRecord]) -> [AssetRecord] {
        records.map { record in
            guard record.id == assetID, record.image.origin == .synthetic else { return record }
            return AssetRecord(image: record.image, sequence: record.sequence, status: status)
        }
    }

    static func selfCheck() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftlet-gui-self-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = try makeMedia(in: root)
        guard fixtures.count == 16, Set(fixtures.map(\.id)).count == 16 else { throw Failure.invalidFixture }
        for fixture in fixtures {
            let file = root.appendingPathComponent(fixture.image.fileName)
            let bytes = try Data(contentsOf: file)
            guard Int64(bytes.count) == fixture.image.byteCount,
                  SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == fixture.image.sha256,
                  let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  decoded.width == fixture.image.pixelWidth,
                  decoded.height == fixture.image.pixelHeight else { throw Failure.invalidFixture }
        }
        let viewport = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        for count in supportedCounts {
            let records = try records(from: fixtures, count: count)
            let layout = RiftLayout.make(records: records, visibleFrame: viewport, configuration: .init())
            guard layout.rows.count == min(count, layout.capacity), layout.rows.map(\.assetID) == Array(records.prefix(layout.capacity)).map(\.id),
                  layout.rows.allSatisfy({ viewport.contains($0.frame) }) else { throw Failure.invalidLayout }
            for retained in [QueueStatus.failed, .unknown] {
                let changed = displaying(retained, assetID: records[0].id, in: records)
                guard RiftLayout.make(records: changed, visibleFrame: viewport, configuration: .init()) == layout else {
                    throw Failure.invalidLayout
                }
            }
            let used = displaying(.used, assetID: records[0].id, in: records)
            let shifted = RiftLayout.make(records: used, visibleFrame: viewport, configuration: .init())
            guard shifted.rows.map(\.assetID) == Array(records.dropFirst().prefix(shifted.capacity)).map(\.id),
                  shifted.rows.map(\.ordinal) == Array(1..<(shifted.rows.count + 1)) else { throw Failure.invalidLayout }
        }
    }

    private static func writeImage(to file: URL, index: Int, width: Int, height: Int) throws {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure.imageEncoding
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        // Transparent rounded corners are intentional probe locations, not a claim
        // that an NSPanel's clear pixels pass mouse events through to another window.
        let shape = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                           cornerWidth: 30, cornerHeight: 30, transform: nil)
        context.addPath(shape)
        context.setFillColor(CGColor(red: 0.76, green: 0.85, blue: 0.90, alpha: 1))
        context.fillPath()
        // Original synthetic artwork stays proportional for the 1:8 / 8:1
        // fixtures; no real screenshot or system-screenshot metadata is used.
        let inset = CGFloat(min(width, height)) * 0.12
        for row in 0..<6 {
            context.setFillColor(CGColor(red: 0.10 + Double(index % 4) * 0.12,
                                         green: 0.25 + Double(index % 3) * 0.12,
                                         blue: 0.48, alpha: 1))
            context.fill(CGRect(x: inset, y: inset + CGFloat(row) * (CGFloat(height) - 2 * inset) / 7,
                                width: (CGFloat(width) - 2 * inset) * (0.55 + 0.08 * CGFloat((row + index) % 5)),
                                height: max(2, (CGFloat(height) - 2 * inset) / 18)))
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.imageEncoding
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.imageEncoding }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    enum Failure: Error { case invalidFixture, invalidLayout, imageEncoding }
}
