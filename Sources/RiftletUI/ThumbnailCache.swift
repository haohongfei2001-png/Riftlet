import AppKit
import ImageIO
import RiftletCore

private final class ThumbnailBox: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Only visible thumbnails are decoded, on a serial utility queue, at their actual display scale.
@MainActor
final class ThumbnailCache {
    private let cache = NSCache<NSString, ThumbnailBox>()
    private let queue = DispatchQueue(label: "Riftlet.thumbnail", qos: .utility)
    private var pending: [String: [(CGImage?) -> Void]] = [:]
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        cache.totalCostLimit = 16 * 1_024 * 1_024
        cache.countLimit = 32
    }

    func image(for asset: ImportedAsset, maxPixelSize: Int, completion: @escaping (CGImage?) -> Void) {
        let pixelSize = min(768, max(1, maxPixelSize))
        let key = "\(asset.id.uuidString):\(pixelSize)"
        if let cached = cache.object(forKey: key as NSString) { completion(cached.image); return }
        if pending[key] != nil { pending[key, default: []].append(completion); return }
        guard !asset.fileName.isEmpty, asset.fileName == URL(fileURLWithPath: asset.fileName).lastPathComponent,
              asset.fileName != ".", asset.fileName != ".." else { completion(nil); return }
        pending[key] = [completion]
        let url = directory.appendingPathComponent(asset.fileName)
        queue.async { [weak self] in
            let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
            var image: CGImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
               CGImageSourceGetStatus(source) == .statusComplete {
                let thumbnailOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixelSize
                ]
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
            }
            let renderedImage = image
            DispatchQueue.main.async {
                guard let self else { return }
                if let renderedImage {
                    self.cache.setObject(ThumbnailBox(renderedImage), forKey: key as NSString,
                                         cost: renderedImage.bytesPerRow * renderedImage.height)
                }
                let callbacks = self.pending.removeValue(forKey: key) ?? []
                callbacks.forEach { $0(renderedImage) }
            }
        }
    }

    func clear() { cache.removeAllObjects(); pending.removeAll() }
}
