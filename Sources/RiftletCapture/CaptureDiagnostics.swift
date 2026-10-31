import Foundation
import Darwin
import RiftletCore

/// Public-safe categories. Native error descriptions, screenshot names and paths are
/// deliberately excluded; the App may show the source directory locally in its setup UI.
public enum CaptureDiagnosticCode: String, Equatable, Sendable {
    case sourceUnavailable, sourcePreferenceUnreadable, unsupportedFormat, imageTooLarge
    case insufficientStorage, privateWriteFailed, recoveryRequired, missingPrivateCopy
}

public enum CaptureDiagnosticContext: Sendable { case source, locationPreference, privateStorage }

public struct CaptureDiagnostic: Equatable, Sendable {
    public let code: CaptureDiagnosticCode
    public init(code: CaptureDiagnosticCode) { self.code = code }

    public var userMessage: String {
        switch code {
        case .sourceUnavailable:
            return "无法读取系统截图文件夹。请检查文件夹访问权限或恢复该位置，再重新检查；已有截图仍保留。"
        case .sourcePreferenceUnreadable:
            return "暂时无法读取系统截图保存位置。请在系统截图工具的“选项”中检查位置，再重新检查。"
        case .unsupportedFormat:
            return "一张系统截图的格式暂不支持。支持单帧 PNG、JPEG、HEIC/HEIF 和 TIFF；系统原图未改动。"
        case .imageTooLarge:
            return "一张系统截图超过本地收录限制（128 MiB、1.6 亿像素或单边 50,000 像素）；系统原图未改动。"
        case .insufficientStorage:
            return "Riftlet 私有存储空间不足，已停止这张图的复制。请释放磁盘空间后重新检查；原图和已有记录仍保留。"
        case .privateWriteFailed:
            return "无法写入 Riftlet 私有存储。请检查磁盘和访问权限后重新检查；原图、队列与恢复记录仍保留。"
        case .recoveryRequired:
            return "部分本地收录记录需要恢复。有效截图仍可查看，请恢复存储访问后重新检查。"
        case .missingPrivateCopy:
            return "部分 Riftlet 私有副本缺失。原有队列和操作记录仍保留；这不表示 ChatGPT 上传失败。"
        }
    }

    public static func classify(_ error: Error, context: CaptureDiagnosticContext) -> CaptureDiagnostic {
        if let capture = error as? CaptureError {
            switch capture {
            case .insufficientStorage: return .init(code: .insufficientStorage)
            case .unsupportedImage: return .init(code: .unsupportedFormat)
            case .imageTooLarge: return .init(code: .imageTooLarge)
            case .invalidLocationPreference: return .init(code: .sourcePreferenceUnreadable)
            case .invalidManifest: return .init(code: .recoveryRequired)
            case .privatePathUnsafe: return .init(code: .privateWriteFailed)
            case .io(let operation, let code):
                if code == ENOSPC || code == EDQUOT { return .init(code: .insufficientStorage) }
                if ["open-source", "stat-source", "read-source", "read-screenshot-metadata", "watch-directory"].contains(operation) {
                    if case .locationPreference = context { return .init(code: .sourcePreferenceUnreadable) }
                    return .init(code: .sourceUnavailable)
                }
                if operation == "read-location-preference" { return .init(code: .sourcePreferenceUnreadable) }
                return .init(code: .privateWriteFailed)
            default: break
            }
        }
        if error is RiftletError { return .init(code: .privateWriteFailed) }
        if isOutOfSpace(error as NSError) { return .init(code: .insufficientStorage) }
        switch context {
        case .source: return .init(code: .sourceUnavailable)
        case .locationPreference: return .init(code: .sourcePreferenceUnreadable)
        case .privateStorage: return .init(code: .privateWriteFailed)
        }
    }

    private static func isOutOfSpace(_ error: NSError, depth: Int = 0) -> Bool {
        guard depth < 4 else { return false }
        if error.domain == NSPOSIXErrorDomain && (error.code == Int(ENOSPC) || error.code == Int(EDQUOT)) { return true }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isOutOfSpace(underlying, depth: depth + 1) }
        return false
    }
}

public struct CaptureStatusSnapshot: Sendable {
    public let sourceDirectory: URL
    public let isRunning: Bool
    /// True only after this source has actually been enumerated. A successful watcher
    /// registration alone does not establish directory-read/TCC permission.
    public let sourceAccessible: Bool
    public let latestDiagnostic: CaptureDiagnostic?
}
