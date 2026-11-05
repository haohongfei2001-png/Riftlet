import Foundation
import ImageIO
import UniformTypeIdentifiers
import RiftletCore

/// Compatibility rendering for captured raster formats outside PNG/JPEG.
/// The caller keeps the verified source and its original queue identity.
enum WebScreenshotPNG {
    private final class Output {
        var bytes = Data()
        var oversized = false
    }

    /// An unusually large uncompressed rendition can exceed the collector's
    /// transport budget. In that case offer the smaller original exactly once.
    static func encode(_ original: Data, asset: ImportedAsset) throws -> Data? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(original as CFData, options), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == asset.pixelWidth,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == asset.pixelHeight else {
            throw WebAdapterError.invalidPrivateFile
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let image: CGImage?
        if orientation == 1 {
            image = CGImageSourceCreateImageAtIndex(source, 0, options)
        } else {
            let fullSize = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: max(asset.pixelWidth, asset.pixelHeight),
                            kCGImageSourceShouldCache: false] as CFDictionary
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, fullSize)
        }
        let rotated = (5...8).contains(orientation)
        guard let image, image.width == (rotated ? asset.pixelHeight : asset.pixelWidth),
              image.height == (rotated ? asset.pixelWidth : asset.pixelHeight) else {
            throw WebAdapterError.invalidPrivateFile
        }
        let output = Output()
        var callbacks = CGDataConsumerCallbacks(putBytes: { info, raw, count in
            guard let info else { return 0 }
            let buffer = Unmanaged<Output>.fromOpaque(info).takeUnretainedValue()
            guard !buffer.oversized, count <= Int(ScreenshotImportLimits.bytes) - buffer.bytes.count else {
                buffer.oversized = true; return 0
            }
            buffer.bytes.append(raw.assumingMemoryBound(to: UInt8.self), count: count)
            return count
        }, releaseConsumer: nil)
        guard let consumer = CGDataConsumer(info: Unmanaged.passUnretained(output).toOpaque(), cbks: &callbacks),
              let destination = CGImageDestinationCreateWithDataConsumer(consumer, UTType.png.identifier as CFString, 1, nil) else {
            throw WebAdapterError.invalidPrivateFile
        }
        CGImageDestinationAddImage(destination, image, nil)
        let ended = CGImageDestinationFinalize(destination)
        if output.oversized { return nil }
        guard ended, !output.bytes.isEmpty else { throw WebAdapterError.invalidPrivateFile }
        return output.bytes
    }
}
