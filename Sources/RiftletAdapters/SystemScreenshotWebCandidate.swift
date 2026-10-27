import Foundation
import Darwin
import RiftletCore

/// Native candidate scope, not an admission. It reuses the exact bundled v12
/// program/MAIN bridge and never changes a page provenance label to "real".
/// Separate identifiers prevent generated-image permissions admitting screenshots.
public enum SystemScreenshotWebCandidate {
    public static let sourceID = "chatgpt-web-zh-20261027-integrated-v12"
    public static let uploadStartProfileID = "chatgpt-web-system-screenshot-start-candidate-20261028-v1"
    public static let completionProfileID = "chatgpt-web-system-screenshot-attached-candidate-20261028-v1"
    public static let profile = ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
        profileID: completionProfileID, completionSignal: .attached,
        uploadStartProfileID: uploadStartProfileID)

    /// These are the existing page's transport/decode bounds, not a claim about
    /// ChatGPT's product limits. Original bytes are the only supported rendition.
    public static let maximumBytes: Int64 = 8 * 1024 * 1024
    public static let maximumPixels: Int64 = 16 * 1024 * 1024

    public static func validateMetadata(_ asset: ImportedAsset) throws {
        guard asset.origin == .systemScreenshot else { throw SystemScreenshotInputError.systemScreenshotsOnly }
        guard asset.mediaType == "image/png", URL(fileURLWithPath: asset.fileName).pathExtension == "png" else {
            throw SystemScreenshotInputError.unsupportedFormat
        }
        guard asset.byteCount > 0, asset.byteCount <= maximumBytes else { throw SystemScreenshotInputError.byteLimit }
        guard asset.pixelWidth > 0, asset.pixelHeight > 0,
              asset.pixelWidth <= 50_000, asset.pixelHeight <= 50_000,
              Int64(asset.pixelWidth) * Int64(asset.pixelHeight) <= maximumPixels else {
            throw SystemScreenshotInputError.pixelLimit
        }
    }

    /// Cheap local format check before operation creation. Capture already did
    /// complete single-frame ImageIO validation. Append still performs BOTH
    /// full SHA256 passes on one no-follow descriptor before its sole commit.
    static func preflight(_ asset: ImportedAsset, fileURL: URL, mediaDirectory: URL) throws {
        try validateMetadata(asset)
        let url = fileURL.standardizedFileURL
        guard url.isFileURL, url.lastPathComponent == asset.fileName,
              url.deletingLastPathComponent().resolvingSymlinksInPath() == mediaDirectory.resolvingSymlinksInPath() else {
            throw WebAdapterError.invalidPrivateFile
        }
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw WebAdapterError.invalidPrivateFile }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size == asset.byteCount else { throw WebAdapterError.invalidPrivateFile }
        var header = [UInt8](repeating: 0, count: 33)
        let count = header.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count == header.count,
              Array(header[0..<8]) == [137, 80, 78, 71, 13, 10, 26, 10],
              Array(header[8..<16]) == [0, 0, 0, 13, 73, 72, 68, 82] else {
            throw WebAdapterError.invalidPrivateFile
        }
        let width = header[16..<20].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let height = header[20..<24].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard width == UInt64(asset.pixelWidth), height == UInt64(asset.pixelHeight) else {
            throw WebAdapterError.invalidPrivateFile
        }
    }

    static func matches(_ profile: ObservationProfile) -> Bool {
        profile.adapterID == "chatgpt-web" && profile.surface == .webChat
            && profile.profileID == completionProfileID && profile.completionSignal == .attached
            && profile.uploadStartProfileID == uploadStartProfileID && profile.failureSignal == nil
    }
}

public enum SystemScreenshotInputError: Error, Equatable, Sendable {
    case systemScreenshotsOnly, unsupportedFormat, byteLimit, pixelLimit
}
