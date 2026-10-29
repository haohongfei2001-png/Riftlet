import AppKit
import CryptoKit
import Darwin
import ImageIO
import RiftletCore

enum HistoryPreviewFailure: Error {
    case invalidFile, fileChanged, unsupportedImage, displayBudget, cancelled
}

/// This is a display budget, not a claim about total ImageIO/process peak memory.
struct HistoryPreviewPlan: Equatable {
    static let maximumPixels = 16_000_000
    static let maximumBytes = 64 * 1_024 * 1_024
    let sourceSize: CGSize
    let maxPixelSize: Int

    static func make(width: Int, height: Int, orientation: Int = 1, depth: Int = 8,
                     viewport: CGSize, backing: CGFloat) throws -> Self {
        guard width > 0, height > 0, width <= 50_000, height <= 50_000,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0, backing.isFinite, backing > 0, backing <= 8 else {
            throw HistoryPreviewFailure.unsupportedImage
        }
        let rotated = (5...8).contains(orientation)
        let w = CGFloat(rotated ? height : width), h = CGFloat(rotated ? width : height)
        let fit = min(min(viewport.width / w, viewport.height / h), 1)
        var longest = max(1, Int(min(max(w, h), ceil(max(w, h) * fit * backing))))
        // Source bit depth supplies a conservative starting budget. Actual
        // bytesPerRow is checked again after ImageIO returns, never inferred.
        let bytesPerPixel = depth > 8 ? 8 : 4
        while longest > 1 {
            let ratio = CGFloat(longest) / max(w, h)
            let pw = max(1, Int(ceil(w * ratio))), ph = max(1, Int(ceil(h * ratio)))
            let paddedRow = ((pw * bytesPerPixel + 255) / 256) * 256
            if pw * ph <= maximumPixels && paddedRow * ph <= maximumBytes { break }
            let factor = min(sqrt(Double(maximumPixels) / Double(pw * ph)),
                             sqrt(Double(maximumBytes) / Double(paddedRow * ph)))
            longest = max(1, min(longest - 1, Int(Double(longest) * factor)))
        }
        return Self(sourceSize: CGSize(width: w, height: h), maxPixelSize: longest)
    }

    static func accepts(_ image: CGImage) -> Bool {
        let pixels = image.width.multipliedReportingOverflow(by: image.height)
        let bytes = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        return image.width > 0 && image.height > 0 && !pixels.overflow && !bytes.overflow
            && pixels.partialValue <= maximumPixels && bytes.partialValue <= maximumBytes
    }
}

struct HistoryPreviewFileIdentity: Equatable, Sendable {
    let device: UInt64, inode: UInt64
    let size: Int64, modifiedSeconds: Int64, modifiedNanoseconds: Int64
    let changedSeconds: Int64, changedNanoseconds: Int64

    private init(_ value: stat) throws {
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw HistoryPreviewFailure.invalidFile }
        device = UInt64(value.st_dev); inode = UInt64(value.st_ino); size = Int64(value.st_size)
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec); modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec); changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }

    static func read(descriptor: Int32) throws -> Self {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw HistoryPreviewFailure.invalidFile }
        return try Self(value)
    }

    func matches(_ url: URL) -> Bool {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return false }
        return (try? Self(value)) == self
    }
}

final class HistoryPreviewCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw HistoryPreviewFailure.cancelled }
    }
}

struct HistoryPreviewRequest {
    let asset: ImportedAsset
    let directory: URL
    let viewport: CGSize
    let backing: CGFloat

    var url: URL { directory.appendingPathComponent(asset.fileName) }
}

struct HistoryPreviewImage {
    let image: CGImage
    let sourceSize: CGSize
    let identity: HistoryPreviewFileIdentity
    let url: URL

    /// NSImage sizes are points. A small source must not turn one source pixel
    /// into two physical pixels merely because its window moved to Retina.
    func displaySize(backing: CGFloat) -> CGSize {
        guard backing.isFinite, backing > 0 else { return .zero }
        return CGSize(width: sourceSize.width / backing, height: sourceSize.height / backing)
    }
}

enum HistoryPreviewDecode {
    static let maximumEncodedBytes = 128 * 1_024 * 1_024

    static func load(_ request: HistoryPreviewRequest, cancellation: HistoryPreviewCancellation) throws -> HistoryPreviewImage {
        try cancellation.check()
        let name = request.asset.fileName
        guard !name.isEmpty, name != ".", name != "..",
              name == URL(fileURLWithPath: name).lastPathComponent else { throw HistoryPreviewFailure.invalidFile }
        let descriptor = Darwin.open(request.url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw HistoryPreviewFailure.invalidFile }
        defer { Darwin.close(descriptor) }
        let identity = try HistoryPreviewFileIdentity.read(descriptor: descriptor)
        guard identity.size > 0, identity.size <= Int64(maximumEncodedBytes),
              identity.size == request.asset.byteCount else { throw HistoryPreviewFailure.invalidFile }
        // Read compressed bytes from this descriptor, rather than let ImageIO
        // reopen a replaceable pathname. No source pixels are eagerly expanded.
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data(), hasher = SHA256()
        while true {
            try cancellation.check()
            let remaining = maximumEncodedBytes - data.count
            guard let chunk = try handle.read(upToCount: min(1_024 * 1_024, remaining + 1)), !chunk.isEmpty else { break }
            guard chunk.count <= remaining else { throw HistoryPreviewFailure.invalidFile }
            hasher.update(data: chunk); data.append(chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard Int64(data.count) == identity.size, digest == request.asset.sha256.lowercased(),
              try HistoryPreviewFileIdentity.read(descriptor: descriptor) == identity,
              identity.matches(request.url) else { throw HistoryPreviewFailure.fileChanged }
        try cancellation.check()
        let sourceOptions = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetStatus(source) == .statusComplete, CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw HistoryPreviewFailure.unsupportedImage
        }
        let plan = try HistoryPreviewPlan.make(width: width, height: height,
            orientation: (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1,
            depth: (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue ?? 8,
            viewport: request.viewport, backing: request.backing)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false, kCGImageSourceThumbnailMaxPixelSize: plan.maxPixelSize]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw HistoryPreviewFailure.unsupportedImage
        }
        // Reject unusual high-depth/stride output instead of repeatedly decoding
        // a giant image. The controller clears the preview and explains the failure.
        guard HistoryPreviewPlan.accepts(image) else { throw HistoryPreviewFailure.displayBudget }
        try cancellation.check()
        guard try HistoryPreviewFileIdentity.read(descriptor: descriptor) == identity,
              identity.matches(request.url) else { throw HistoryPreviewFailure.fileChanged }
        return HistoryPreviewImage(image: image, sourceSize: plan.sourceSize, identity: identity, url: request.url)
    }
}

/// One process-wide decoding lane. There is one running decode and at most one
/// latest request; superseded requests never build an unbounded dispatch queue.
/// No high-resolution cache is retained here. Production uses shared only.
@MainActor
final class HistoryPreviewLoader {
    static let shared = HistoryPreviewLoader()
    private static let queue = DispatchQueue(label: "Riftlet.history-preview", qos: .userInitiated)
    typealias Decoder = (HistoryPreviewRequest, HistoryPreviewCancellation) throws -> HistoryPreviewImage
    private struct Work {
        let owner: UUID, generation: UInt
        let request: HistoryPreviewRequest
        let cancellation: HistoryPreviewCancellation
        let completion: (Result<HistoryPreviewImage, Error>) -> Void
    }
    private let decoder: Decoder
    private var owner: UUID?
    private var generation: UInt = 0
    private var activeCancellation: HistoryPreviewCancellation?
    private var pending: Work?
    private var running = false
    private var ownerInvalidated: (() -> Void)?

    init(decoder: @escaping Decoder = HistoryPreviewDecode.load) { self.decoder = decoder }

    func request(owner: UUID, request: HistoryPreviewRequest, invalidated: @escaping () -> Void,
                 completion: @escaping (Result<HistoryPreviewImage, Error>) -> Void) {
        if let current = self.owner, current != owner { ownerInvalidated?() }
        generation &+= 1; self.owner = owner; ownerInvalidated = invalidated
        activeCancellation?.cancel(); pending?.cancellation.cancel()
        pending = Work(owner: owner, generation: generation, request: request,
                       cancellation: HistoryPreviewCancellation(), completion: completion)
        launchNext()
    }

    func cancel(owner: UUID) {
        guard self.owner == owner else { return }
        invalidate(owner: owner); self.owner = nil; ownerInvalidated = nil
    }

    /// Resize/backing changes invalidate work but retain the current window's
    /// ownership while its previous bitmap remains displayed during debounce.
    func invalidate(owner: UUID) {
        guard self.owner == owner else { return }
        generation &+= 1
        activeCancellation?.cancel(); pending?.cancellation.cancel(); pending = nil
    }

    private func launchNext() {
        guard !running, let work = pending else { return }
        pending = nil; running = true; activeCancellation = work.cancellation
        let decode = decoder
        Self.queue.async {
            let result = Result { try autoreleasepool { try decode(work.request, work.cancellation) } }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.running = false; self.activeCancellation = nil
                if self.owner == work.owner, self.generation == work.generation {
                    work.completion(result)
                }
                self.launchNext()
            }
        }
    }
}

/// Watch only the selected private file. Replacement, truncation and deletion
/// invalidate the displayed identity; this never observes system screenshots.
@MainActor
final class HistoryPreviewFileObserver {
    private var source: DispatchSourceFileSystemObject?
    init?(url: URL, changed: @escaping () -> Void) {
        let descriptor = Darwin.open(url.path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke, .attrib, .extend], queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source; source.resume()
    }
    func cancel() { source?.cancel(); source = nil }
    deinit { source?.cancel() }
}
