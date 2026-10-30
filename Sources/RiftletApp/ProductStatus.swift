import Foundation
import RiftletCore
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
    \(OrdinaryCaptureConfiguration.admission.supportText) 真实截图内部候选需另行启动；受限 v2 开始与完成仅适用于新登记操作，旧的待核实操作不补资格、不重传。安全失败与重试仍未开放。
    真实截图证据限定于 macOS 27.0 / Chrome 156.0.8078.73、中文 ChatGPT 普通已有聊天、点击前已验证的原草稿与一次软件鼠标输入；不是物理鼠标、冷首击或全场景支持。Home／新草稿、临时或只读聊天、Work、ChatGPT Mac 和其他浏览器不在本次范围。
    候选仅接收原字节单帧、非交错 8-bit RGBA PNG，≤8 MiB、≤16,777,216 像素。其他已收录格式和大图保留，不缩放、不重新编码、不自动转换。
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
            case .unsupportedFormat: return .attachmentFormat
            case .systemScreenshotsOnly: return .attachmentSource
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

    /// Presentation only. No case grants input, retry, admission or a new target.
    enum AttachmentFeedback: Equatable, CaseIterable {
        case waiting, preparing, cancelledBeforeInput, expiredBeforeInput, targetChangedBeforeInput
        case targetValidationUnavailableBeforeInput, noClickTimeTarget, targetUnavailable
        case unresolvedDraftBeforeInput, imageMissingBeforeInput, resultUnconfirmed

        var text: String {
            switch self {
            case .waiting: return "已接收，正在等待附加；本次尚未上传。"
            case .preparing: return "附加处理中，结果尚待确认；请保留当前聊天草稿。"
            case .cancelledBeforeInput: return "此次附加已取消，图片保留；本次未上传。"
            case .expiredBeforeInput: return "等待已超时，此次附加已取消；图片保留，本次未上传。"
            case .targetChangedBeforeInput: return "原聊天草稿已变化，此次附加已取消；图片保留，本次未上传。"
            case .targetValidationUnavailableBeforeInput: return "暂时无法核实原聊天草稿；图片保留，本次未上传。"
            case .noClickTimeTarget: return "点击时页面尚未完成验证；图片保留，本次未上传。"
            case .targetUnavailable: return "当前没有可验证的附件目标；图片记录保留，请在运行状态中查看原因。"
            case .unresolvedDraftBeforeInput: return "原草稿中还有一张图片的附加结果待核实；本次未上传，图片保留。"
            case .imageMissingBeforeInput: return "找不到这张图片的本地副本；本次未上传。"
            case .resultUnconfirmed: return "附加结果暂不能确认，图片记录已保留；不会自动再次附加。"
            }
        }
    }

    /// Match only code-owned exact reasons. Receipt/browser text and future
    /// reasons fall back to neutral wording, never raw text or a no-input claim.
    /// The persisted diagnostic is not modified by this presentation mapping.
    static func operationFeedback(_ reason: String?) -> AttachmentFeedback {
        switch reason {
        case "Accepted selection expired before input": return .expiredBeforeInput
        case "Original target changed before input": return .targetChangedBeforeInput
        case "Target validation unavailable before input": return .targetValidationUnavailableBeforeInput
        case "Original draft has an unresolved upload; no input occurred": return .unresolvedDraftBeforeInput
        case "Private image is missing; no input occurred": return .imageMissingBeforeInput
        case "Selection revoked during preparation; no input occurred",
             "Original selection no longer authorized; no input occurred",
             "Original selection revoked before intent; no input occurred",
             "Selection retired before input intent",
             "Removed before external input intent",
             "Restart before dispatch intent; no input occurred",
             // App cancellation reasons reach Core only through cancelPrepared.
             "termination", "observationLimit", "submissionCancelled", "submissionLimit",
             "selectionRejected", "permissionUnavailable", "activation", "wake",
             "removed", "clearVisible", "hidden": return .cancelledBeforeInput
        default: return .resultUnconfirmed
        }
    }

    /// The exact no-ACK error is distinct from a missing/invalid target.
    /// Unhandled errors retain the existing permission/format issue mapping.
    static func clickFeedback(_ error: Error) -> AttachmentFeedback? {
        if let core = error as? RiftletError,
           case .adapterUnavailable("No verified target existed at selection; image retained") = core {
            return .noClickTimeTarget
        }
        if let web = error as? WebAdapterError, web == .invalidTarget {
            return .targetUnavailable
        }
        return nil
    }

    static let chromeJavaScriptHelp = "Chrome 还需在「显示 → 开发者 → 允许来自 Apple 事件的 JavaScript」中允许页面连接。Riftlet 不会代改这个设置；系统授权成功不代表该开关已开启。"
}
