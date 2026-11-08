// Stability and ImageIO completeness primitives adapted from Screenshoss
// ScreenshotImportService.swift @ 8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac.
// Copyright (c) 2026 Mert Oztopkara. MIT; see ThirdPartyNotices.
// Riftlet changes: descriptor identity, symlink rejection, complete indexed image,
// bounded decode, shared stability window, and copy verification instead of moving.
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin
import CoreFoundation
import RiftletCore

public enum CaptureError: Error, Equatable, Sendable {
    case io(String, Int32)
    case notRegularFile
    case notScreenshot
    case metadataPending
    case unstableFile
    case incompleteImage
    case imageTooLarge
    case unsupportedImage
    case invalidManifest
    case privatePathUnsafe
    case importInProgress
    case invalidLocationPreference
    case insufficientStorage
    case sourceVolumeUnidentified
    case historicalSourceUnconfirmed
}

/// Read from the very same open file/directory being identified. A mount's
/// st_dev is useful for live descriptor checks but may change after a reboot.
enum CaptureVolume {
    static func identifier(of descriptor: Int32) -> UUID? {
        var request = attrlist()
        request.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_UUID)
        var reply: (UInt32, uuid_t) = (0, (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let size = MemoryLayout.size(ofValue: reply)
        guard fgetattrlist(descriptor, &request, &reply, size, 0) == 0, reply.0 == size,
              withUnsafeBytes(of: reply.1, { $0.contains { $0 != 0 } }) else { return nil }
        return UUID(uuid: reply.1)
    }
}

struct FileSignature: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let birthSeconds: Int64
    let birthNanoseconds: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let size: Int64
    let volumeUUID: UUID? // absent in pre-volume handoff checkpoints

    var fileID: String { "\(inode):\(birthSeconds):\(birthNanoseconds)" }
    var sourceKey: String {
        if let volumeUUID { return "volume:\(volumeUUID.uuidString.lowercased()):\(fileID)" }
        // Decode and retain old intents. The importer requires a volume UUID
        // before recording any new occurrence.
        return "\(device):\(fileID)"
    }
    static func legacyFileID(_ key: String) -> String? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, UInt64(parts[0]) != nil, UInt64(parts[1]) != nil,
              Int64(parts[2]) != nil, let ns = Int64(parts[3]), (0..<1_000_000_000).contains(ns) else { return nil }
        return parts.dropFirst().joined(separator: ":")
    }
    var createdAt: Date {
        Date(timeIntervalSince1970: Double(birthSeconds) + Double(birthNanoseconds) / 1_000_000_000)
    }

    static func read(at url: URL) throws -> FileSignature {
        try observe(at: url).signature
    }

    static func observe(at url: URL) throws -> (signature: FileSignature, changedAt: Duration) {
        // Reject a FIFO/device via fstat without waiting for a writer before validation.
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CaptureError.io("open-source", errno) }
        defer { Darwin.close(fd) }
        return try observe(descriptor: fd)
    }

    static func read(descriptor: Int32) throws -> FileSignature {
        try observe(descriptor: descriptor).signature
    }

    private static func observe(descriptor: Int32) throws -> (signature: FileSignature, changedAt: Duration) {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw CaptureError.io("stat-source", errno) }
        let changedAt = Duration.seconds(value.st_ctimespec.tv_sec) + .nanoseconds(value.st_ctimespec.tv_nsec)
        return (try read(metadata: value, volumeUUID: CaptureVolume.identifier(of: descriptor)), changedAt)
    }

    static func read(metadata value: stat, volumeUUID: UUID?) throws -> FileSignature {
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw CaptureError.notRegularFile }
        return FileSignature(device: UInt64(UInt32(bitPattern: value.st_dev)), inode: UInt64(value.st_ino),
                             birthSeconds: Int64(value.st_birthtimespec.tv_sec),
                             birthNanoseconds: Int64(value.st_birthtimespec.tv_nsec),
                             modificationSeconds: Int64(value.st_mtimespec.tv_sec),
                             modificationNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                             size: Int64(value.st_size), volumeUUID: volumeUUID)
    }
}

public enum CaptureSource {
    static func mayBeImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "pdf", "gif", "bmp"].contains(url.pathExtension.lowercased())
    }

    /// Read-only. Does not write preferences or restart the system screenshot UI.
    public static func defaultDirectory() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    static let metadataName = "com.apple.metadata:kMDItemIsScreenCapture"

    /// Missing metadata is retryable. A present false/nonboolean value is never a screenshot.
    static func isScreenshot(descriptor: Int32) throws -> Bool {
        let size = fgetxattr(descriptor, metadataName, nil, 0, 0, 0)
        guard size >= 0 else {
            if errno == ENOATTR { throw CaptureError.metadataPending }
            throw CaptureError.io("read-screenshot-metadata", errno)
        }
        guard size > 0, size <= 4096 else { return false }
        var data = Data(count: size)
        let count = data.withUnsafeMutableBytes {
            fgetxattr(descriptor, metadataName, $0.baseAddress, size, 0, 0)
        }
        guard count == size else { throw CaptureError.metadataPending }
        guard let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }
}

struct ValidatedImage: Sendable {
    let width: Int
    let height: Int
    let mimeType: String
    let fileExtension: String

    static let maximumBytes = ScreenshotImportLimits.bytes
    static let maximumPixels = ScreenshotImportLimits.pixels

    static func inspect(_ url: URL, byteCount: Int64) throws -> ValidatedImage {
        try inspect(url, byteCount: byteCount, decodePixels: true)
    }

    /// Only for committed media whose journal, stored asset and full content hash
    /// still match the bytes validated before their original durable import.
    /// Current format, frame, size and completeness policy is always rechecked.
    static func inspectPreviouslyValidated(_ url: URL, byteCount: Int64) throws -> ValidatedImage {
        try inspect(url, byteCount: byteCount, decodePixels: false)
    }

    private static func inspect(_ url: URL, byteCount: Int64, decodePixels: Bool) throws -> ValidatedImage {
        guard byteCount > 0, byteCount <= maximumBytes else { throw CaptureError.imageTooLarge }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            // PDF is a real system screenshot option, but is not a raster image input.
            // Recognize its file signature rather than trust a misleading extension.
            if try hasPDFSignature(url) { throw CaptureError.unsupportedImage }
            throw CaptureError.incompleteImage
        }
        guard let typeID = CGImageSourceGetType(source),
              let type = UTType(typeID as String), type.conforms(to: .image),
              let mime = type.preferredMIMEType, let ext = type.preferredFilenameExtension,
              ["png", "jpeg", "jpg", "heic", "heif", "tiff", "tif"].contains(ext.lowercased()) else {
            throw CaptureError.unsupportedImage
        }
        guard CGImageSourceGetCount(source) <= 1 else { throw CaptureError.unsupportedImage }
        guard CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw CaptureError.incompleteImage }
        guard
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw CaptureError.unsupportedImage
        }
        guard width > 0, height > 0, width <= ScreenshotImportLimits.dimension, height <= ScreenshotImportLimits.dimension,
              Int64(width) * Int64(height) <= maximumPixels else { throw CaptureError.imageTooLarge }
        if decodePixels {
            // New imports and unfinished journals always force a real bounded decode.
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
                  decoded.width > 0, decoded.height > 0 else { throw CaptureError.incompleteImage }
        }
        return ValidatedImage(width: width, height: height, mimeType: mime, fileExtension: ext.lowercased())
    }

    private static func hasPDFSignature(_ url: URL) throws -> Bool {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CaptureError.io("open-private-copy", errno) }
        defer { Darwin.close(descriptor) }
        _ = try PrivateFiles.privateSignature(descriptor: descriptor)
        var header = [UInt8](repeating: 0, count: 5)
        let count = header.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
        guard count >= 0 else { throw CaptureError.io("read-private-copy", errno) }
        return count == header.count && header == Array("%PDF-".utf8)
    }
}
