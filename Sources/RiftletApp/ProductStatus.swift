import Foundation
import RiftletCapture
import RiftletUI
import RiftletAdapters

/// A code-owned, honest capability description. A future Web admission changes
/// the App composition separately; permissions cannot enable that composition.
enum ProductStatus {
    static func sourceState(detectedSource: URL?, observation: CaptureStatusSnapshot?,
                            systemCollection: Bool, paused: Bool, initialized: Bool) -> SetupSourceState {
        guard systemCollection else { return .notApplicable }
        guard let detectedSource else { return .notConfigured }
        guard initialized else { return .checking }
        if let observation, observation.sourceAccessible,
           SourceAccessSelection.matches(selected: observation.sourceDirectory, actualSource: detectedSource) {
            return .accessible
        }
        return paused ? .notChecked : .unavailable
    }

    static func collectionState(systemCollection: Bool, paused: Bool, initialized: Bool,
                                running: Bool, source: SetupSourceState) -> SetupCollectionState {
        guard systemCollection else { return .stopped }
        if paused { return .paused }
        if running && source == .accessible { return .collecting }
        return initialized ? .waitingForSource : .starting
    }

    static let supportDescription = """
    本地收录：系统保存的新截图，单帧 PNG / JPEG / HEIC / HEIF / TIFF；最多 128 MiB、1.6 亿像素、单边 50,000 像素。原始字节不转换；HDR 显示效果尚未验收。剪贴板截图、PDF、动图不在收录范围。
    应用要求 macOS 13+；自动测试覆盖 macOS 14.8.9 / Apple silicon，其他平台仍需实测。
    网页候选仅在 macOS 27.0 / Chrome 156.0.8078.48 的中文普通 Chat 中有局部生成图片证据；不是公开支持或一次点击全场景验收。ChatGPT Mac、其他浏览器和 Work 尚未启用。
    真实截图内部候选另行启动，仅尝试原字节 PNG，≤8 MiB、≤16,777,216 像素。其他已收录格式和大图保留，不自动转换。开始、成功与重试均待真实截图证据准入。
    此为开发构建，未公证、未发行。截图可能包含 Riftlet；需要时可先隐藏裂缝，收录仍可继续。
    """

    static func permission(_ state: AutomationPermissionState) -> SetupPermissionState {
        switch state {
        case .notNeeded: return .notNeeded
        case .notRequested: return .notRequested
        case .granted: return .granted
        case .denied: return .denied
        case .browserNotRunning: return .notRunning
        case .browserNotInstalled: return .browserUnavailable
        case .unavailable: return .unavailable
        }
    }

    static func issue(_ diagnostic: CaptureDiagnostic) -> SetupIssue {
        switch diagnostic.code {
        case .sourceUnavailable, .sourcePreferenceUnreadable: return .sourceAccess
        case .unsupportedFormat: return .unsupportedFormat
        case .imageTooLarge: return .unsupportedSize
        case .insufficientStorage: return .insufficientSpace
        case .privateWriteFailed: return .privateWriteFailed
        case .recoveryRequired: return .storageUnavailable
        case .missingPrivateCopy: return .imageUnavailable
        }
    }

    /// Feedback only; this does not choose a browser or acquire a target lease.
    static func clickIssue(_ error: Error, frontmostBundleID: String?, webAcceptance: Bool) -> SetupIssue? {
        guard webAcceptance else { return nil }
        if let input = error as? SystemScreenshotInputError {
            switch input {
            case .unsupportedFormat, .systemScreenshotsOnly: return .attachmentFormat
            case .byteLimit: return .attachmentBytes
            case .pixelLimit: return .attachmentPixels
            }
        }
        if let web = error as? WebAdapterError {
            if web == .invalidPrivateFile { return .imageUnavailable }
            if web == .nativeEventFailed(-1743) { return .permissionDenied }
        }
        if let frontmostBundleID,
           ["com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser"]
            .contains(frontmostBundleID) { return .unsupportedBrowser }
        return .targetUnavailable
    }

    static let chromeJavaScriptHelp = "Chrome 还需在「显示 → 开发者 → 允许来自 Apple 事件的 JavaScript」中允许页面连接。Riftlet 不会代改这个设置；系统授权成功不代表该开关已开启。"
}
