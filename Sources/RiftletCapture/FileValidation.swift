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
}

struct FileSignature: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let birthSeconds: Int64
    let birthNanoseconds: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let size: Int64

    var sourceKey: String { "\(device):\(inode):\(birthSeconds):\(birthNanoseconds)" }
    var createdAt: Date {
        Date(timeIntervalSince1970: Double(birthSeconds) + Double(birthNanoseconds) / 1_000_000_000)
    }

    static func read(at url: URL) throws -> FileSignature {
        // Reject a FIFO/device via fstat without waiting for a writer before validation.
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CaptureError.io("open-source", errno) }
        defer { Darwin.close(fd) }
        return try read(descriptor: fd)
    }

    static func read(descriptor: Int32) throws -> FileSignature {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw CaptureError.io("stat-source", errno) }
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw CaptureError.notRegularFile }
        return FileSignature(device: UInt64(value.st_dev), inode: UInt64(value.st_ino),
                             birthSeconds: Int64(value.st_birthtimespec.tv_sec),
                             birthNanoseconds: Int64(value.st_birthtimespec.tv_nsec),
                             modificationSeconds: Int64(value.st_mtimespec.tv_sec),
                             modificationNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                             size: Int64(value.st_size))
    }
}

public enum CaptureSource {
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

    static let maximumBytes: Int64 = 128 * 1024 * 1024
    static let maximumPixels: Int64 = 160_000_000

    static func inspect(_ url: URL, byteCount: Int64) throws -> ValidatedImage {
        guard byteCount > 0, byteCount <= maximumBytes else { throw CaptureError.imageTooLarge }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw CaptureError.incompleteImage
        }
        guard let typeID = CGImageSourceGetType(source),
              let type = UTType(typeID as String), type.conforms(to: .image),
              let mime = type.preferredMIMEType, let ext = type.preferredFilenameExtension,
              ["png", "jpeg", "jpg", "heic", "heif", "tiff", "tif"].contains(ext.lowercased()),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw CaptureError.unsupportedImage
        }
        guard width > 0, height > 0, width <= 50_000, height <= 50_000,
              Int64(width) * Int64(height) <= maximumPixels else { throw CaptureError.imageTooLarge }
        // Force a real bounded decode, not only a file-header/status check. No full-size bitmap.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
              decoded.width > 0, decoded.height > 0 else { throw CaptureError.incompleteImage }
        return ValidatedImage(width: width, height: height, mimeType: mime, fileExtension: ext.lowercased())
    }
}
