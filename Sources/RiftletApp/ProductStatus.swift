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

    static let supportDescription = supportDescription(for: OrdinaryCaptureConfiguration.admission)

    static func supportDescription(for admission: OrdinaryAttachmentAdmission, copy: ProductCopy = .current) -> String {
        if copy == .english && admission.usesUnifiedProduct {
            return """
            Riftlet collects single-frame PNG, JPEG, HEIC, HEIF and TIFF screenshots saved by macOS. Limits are 128 MiB, 160 million pixels and 50,000 pixels per side. Clipboard-only images, animated images and PDFs are excluded. Originals are preserved. HDR display has not been verified.
            Open an editable new or existing ChatGPT draft in Chrome. Click a desktop thumbnail to add its screenshot. When the draft starts receiving it, you can click the next one. You choose when to send. PNG and JPEG are attached as saved. Other supported formats usually become a full-resolution PNG; if it is too large, the original format is offered to the page instead.
            Check the original draft for an uncertain attachment. Riftlet keeps it in history and never automatically resubmits it. ChatGPT attachment availability can vary by page, account and chat mode.
            Requires macOS 13 or later. Release notes list tested environments. To keep Riftlet out of a screenshot, you can hide desktop thumbnails while collection continues.
            """
        }
        let attachmentScope = admission.usesUnifiedProduct ? """
        \(admission.supportText)
        结果不明的图片保留在历史里，不会自动再次附加。页面、账号功能和聊天模式都可能影响附件是否可用。
        """ : """
        \(admission.supportText) 真实截图内部候选需另行启动；受限 v2 开始与完成仅适用于新登记操作，旧的待核实操作不补资格、不重传。安全失败与重试仍未开放。
        受限候选仅附加非交错 8-bit RGBA PNG，≤8 MiB、≤16,777,216 像素；其他格式保留，不自动转换。
        旧内部候选的真实截图证据限定于 macOS 27.0 / Chrome 156.0.8078.73、中文 ChatGPT 普通已有聊天、点击前已验证的原草稿与一次软件鼠标输入；不是物理鼠标、冷首击或全场景支持。这些旧候选证据不涵盖 Home／新草稿、临时或只读聊天、Work、ChatGPT Mac 和其他浏览器；普通入口的当前范围以上方说明为准。
        """
        return """
    本地收录：系统保存的新截图，单帧 PNG / JPEG / HEIC / HEIF / TIFF；最多 128 MiB、1.6 亿像素、单边 50,000 像素。原始字节不转换；HDR 显示效果尚未验收。剪贴板截图、PDF、动图不在收录范围。
    需要 macOS 13 或更高版本。各版本的实测范围见版本说明。
    \(attachmentScope)
    截图可能包含 Riftlet。需要时可先隐藏桌面截图，收录仍可继续。公开下载状态和版本说明见 Riftlet 官网。
    """
    }

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
        case .sourceVolumeUnidentified: return .sourceVolumeUnidentified
        case .fileVolumeUnidentified: return .fileVolumeUnidentified
        case .historicalSourceUnconfirmed: return .historicalSourceUnconfirmed
        }
    }

    /// Feedback only; this does not choose a browser or acquire a target lease.
    static func clickIssue(_ error: Error, frontmostBundleID: String?, webAcceptance: Bool) -> SetupIssue? {
        guard webAcceptance else { return nil }
        if let input = error as? SystemScreenshotInputError {
            switch input {
            case .unsupportedFormat: return .attachmentFormat
            case .systemScreenshotsOnly, .sourceNotAdmitted: return .attachmentSource
            case .byteLimit: return .attachmentBytes
            case .pixelLimit: return .attachmentPixels
            }
        }
        if let web = error as? WebAdapterError {
            if web == .invalidPrivateFile { return .imageUnavailable }
            if web == .nativeEventFailed(-1743) { return .permissionDenied }
            if web == .nativeEventFailed(12) { return .chromeJavaScriptDisabled }
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
        case independentAttachmentUnavailableBeforeInput
        case inputResourceUnavailableBeforeInput
        case inputExecutingBeforeInput, filePreparationFailedBeforeInput
        case attachmentEntryUnavailable, attachmentInputNotCreated, attachmentInputAmbiguous, attachmentEntryFailed

        var text: String {
            text(in: .current)
        }

        func text(in copy: ProductCopy) -> String {
            switch self {
            case .waiting: return copy.text("已接收，正在等待附加；本次尚未上传。",
                    "Queued for attachment; this image has not been uploaded yet.")
            case .preparing: return copy.text("附加处理中，结果尚待确认；请保留当前聊天草稿。",
                    "Attachment in progress; the result is not yet confirmed. Keep the current chat draft open.")
            case .cancelledBeforeInput: return copy.text("此次附加已取消，图片保留；本次未上传。",
                    "Attachment cancelled. The image is kept and was not uploaded.")
            case .expiredBeforeInput: return copy.text("等待已超时，此次附加已取消；图片保留，本次未上传。",
                    "The wait timed out and the attachment was cancelled. The image is kept and was not uploaded.")
            case .targetChangedBeforeInput: return copy.text("原聊天草稿已变化，此次附加已取消；图片保留，本次未上传。",
                    "The original chat draft changed. Attachment cancelled; the image is kept and was not uploaded.")
            case .targetValidationUnavailableBeforeInput: return copy.text("暂时无法核实原聊天草稿；图片保留，本次未上传。",
                    "The original chat draft could not be verified. The image is kept and was not uploaded.")
            case .noClickTimeTarget: return copy.text("这次点击没有找到可用的聊天草稿，本次未上传。请把要用的 ChatGPT 草稿切到 Chrome 前台，再点边缘截图。",
                    "No available chat draft was found for this click; the image was not uploaded. Bring your ChatGPT draft to the front in Chrome, then click the desktop screenshot.")
            case .targetUnavailable: return SetupIssue.targetUnavailable.text(in: copy)
            case .unresolvedDraftBeforeInput: return copy.text("原草稿中还有一张图片的附加结果待核实；本次未上传，图片保留。",
                    "Another attachment in the original draft is still unconfirmed. This image was not uploaded and is kept.")
            case .independentAttachmentUnavailableBeforeInput:
                return copy.text("暂不能确认当前页面能保留原附件并继续追加；本次未上传，图片保留。",
                    "The page could not be confirmed to support another attachment while preserving existing ones. This image was not uploaded and is kept.")
            case .inputResourceUnavailableBeforeInput:
                return copy.text("当前页面的附件入口尚不能安全接收下一张图片；本次未上传，图片保留。",
                    "The page cannot safely receive the next image yet. This image was not uploaded and is kept.")
            case .inputExecutingBeforeInput:
                return copy.text("上一张的文件输入仍在执行；本次尚未附加，图片保留。",
                    "The previous file is still being handed to the page. This image has not been attached and is kept.")
            case .filePreparationFailedBeforeInput:
                return copy.text("当前图片未能交给浏览器；本次尚未附加，图片保留。",
                    "The image could not be handed to the browser. It has not been attached and is kept.")
            case .attachmentEntryUnavailable:
                return copy.text("未找到当前聊天可执行的附件入口；本次未附加，图片保留。",
                    "No usable attachment entry was found in this chat. The image was not attached and is kept.")
            case .attachmentInputNotCreated:
                return copy.text("已执行附件入口，但页面未提供文件输入；本次未附加，图片保留。",
                    "The attachment entry opened, but the page provided no file input. The image was not attached and is kept.")
            case .attachmentInputAmbiguous:
                return copy.text("附件入口未能确定当前聊天使用的文件控件；本次未附加，图片保留。",
                    "The file input for this chat could not be identified. The image was not attached and is kept.")
            case .attachmentEntryFailed:
                return copy.text("执行当前聊天的附件入口时失败；本次未附加，图片保留。",
                    "The attachment entry in this chat could not be opened. The image was not attached and is kept.")
            case .imageMissingBeforeInput: return copy.text("找不到这张图片的本地副本；本次未上传。",
                    "The local copy of this image could not be found. It was not uploaded.")
            case .resultUnconfirmed: return copy.text("附加结果暂不能确认，图片记录已保留；不会自动再次附加。",
                    "The attachment result is unconfirmed. Its history is kept; Riftlet will not attach it again automatically.")
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
        case "Verified pre-input rejection: pageRetiredBeforeFileInput: targetInvalidBeforeInput":
            return .targetChangedBeforeInput
        case "Verified pre-input rejection: pageRetiredBeforeFileInput: inputExecutionBusy":
            return .inputExecutingBeforeInput
        case "Verified pre-input rejection: pageRetiredBeforeFileInput: attachmentEntryUnavailable":
            return .attachmentEntryUnavailable
        case "Verified pre-input rejection: pageRetiredBeforeFileInput: attachmentInputNotCreated":
            return .attachmentInputNotCreated
        case "Verified pre-input rejection: pageRetiredBeforeFileInput: attachmentInputAmbiguous":
            return .attachmentInputAmbiguous
        case "Verified pre-input rejection: pageRetiredBeforeFileInput: attachmentEntryFailed":
            return .attachmentEntryFailed
        case "Verified pre-input rejection: localBeforeBegin",
             "Verified pre-input rejection: localBeforeBegin: fileInputCommandNotInvoked",
             "Verified pre-input rejection: pageRetiredBeforeCommit",
             "Verified pre-input rejection: pageRetiredBeforeFileInput: invalidPNGSignature",
             "Verified pre-input rejection: pageRetiredBeforeFileInput: inputHashMismatch",
             "Verified pre-input rejection: pageRetiredBeforeFileInput: inputPreparationFailed":
            return .filePreparationFailedBeforeInput
        case "Target validation unavailable before input": return .targetValidationUnavailableBeforeInput
        case "Original draft has an unresolved upload; no input occurred": return .unresolvedDraftBeforeInput
        case "Independent attachment input is unproven for this draft; no input occurred": return .independentAttachmentUnavailableBeforeInput
        case "Current attachment input cannot be reserved safely; no input occurred": return .inputResourceUnavailableBeforeInput
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
}
