import Foundation

/// A short projection of the host's facts, shared by the popover and menu.
/// It carries no mutable collection, permission, or persistence authority.
public struct RiftControlCenterPresentation {
    public enum State: Equatable { case attention, paused, hidden, collecting, preparing, stopped }
    public let state: State
    public let title: String
    public let detail: String
    public let symbol: String
    public let primaryTitle = "截图…"
    public let primaryEnabled: Bool
    public let captureHint: String?
    public let recoveryTitle: String?
    public let recoveryPage: SettingsPage?

    public init(_ snapshot: SettingsProductSnapshot) {
        let setup = snapshot.setup
        let owner = snapshot.state.owner
        let capabilities = snapshot.capabilities
        let usesAutomation = [.available, .syntheticWeb, .systemScreenshotCandidate].contains(setup.attachment)
        primaryEnabled = capabilities.canCapture
        if capabilities.canCapture {
            captureHint = nil
        } else if snapshot.reviewEnvironment {
            captureHint = "隔离审核不执行真实截图或上传。"
        } else if !owner.settings.entryEnabled {
            captureHint = "内置截图已关闭；系统截图收录保持原设置。"
        } else if !owner.settings.entryAvailable {
            captureHint = "内置截图当前不可用；可在设置查看状态。"
        } else if owner.isHidden {
            captureHint = "裂缝已隐藏；内置截图暂不可用。"
        } else {
            captureHint = "内置截图暂不可用；可在设置查看当前状态。"
        }
        let hasSaveIssue = snapshot.state.hasSaveIssues || snapshot.appearance.failure != nil
            || snapshot.appearance.unreadable || snapshot.login.errorCode != nil || snapshot.login.notConfirmed
        if hasSaveIssue || [.visibilityPreferenceUnsaved, .collectionPreferenceUnsaved,
                            .screenshotPreferenceUnsaved, .configurationUnavailable].contains(setup.issue) {
            state = .attention; title = "有设置尚未确认保存"
            detail = "当前运行状态如下。请到设置查看并重试。"
            symbol = "exclamationmark.circle"
            recoveryTitle = "查看未保存的设置"; recoveryPage = .general
        } else if setup.issue == .initializationFailed {
            state = .attention; title = "Riftlet 未能完成启动"
            detail = "已有图片保留。请查看权限与帮助。"
            symbol = "exclamationmark.circle"
            recoveryTitle = "查看启动问题"; recoveryPage = .help
        } else if setup.issue == .insufficientSpace || setup.issue == .privateWriteFailed
                    || setup.storage == .insufficientSpace || setup.storage == .writeFailed {
            state = .attention; title = "私有存储需要处理"
            detail = "新截图暂不能安全保存；已有图片保留。"
            symbol = "exclamationmark.circle"
            recoveryTitle = "查看本机存储"; recoveryPage = .history
        } else if setup.source == .unavailable || setup.source == .notConfigured || setup.issue == .sourceAccess {
            state = .attention; title = "无法访问截图位置"
            detail = "已有图片保留；请检查当前系统截图位置。"
            symbol = "folder.badge.questionmark"
            recoveryTitle = "检查截图位置"; recoveryPage = .help
        } else if usesAutomation && (setup.permission == .denied || setup.issue == .permissionDenied) {
            state = .attention; title = "Chrome 自动化需要允许"
            detail = "这只影响主动附加；截图收录按当前设置进行。"
            symbol = "exclamationmark.circle"
            recoveryTitle = "检查 Chrome 连接"; recoveryPage = .help
        } else if owner.collectionPaused {
            state = .paused; title = "已暂停收录"
            detail = owner.isHidden ? "已有截图保留；裂缝也已隐藏。" : "已有截图保留，仍可按需使用。"
            symbol = "pause.circle"
            recoveryTitle = nil; recoveryPage = nil
        } else if owner.isHidden {
            state = .hidden; title = "裂缝已隐藏"
            detail = setup.collection == .collecting ? "仍在收录新的截图。" : "只影响边缘显示；收录按当前运行状态进行。"
            symbol = "eye.slash"
            recoveryTitle = nil; recoveryPage = nil
        } else if setup.collection == .collecting {
            state = .collecting; title = "正在收录截图"
            if snapshot.reviewEnvironment {
                detail = setup.visibleCount == 0 ? "仅收录审核示例，不会上传。" : "\(setup.visibleCount) 张审核示例在边缘，不会上传。"
            } else if !usesAutomation {
                detail = setup.visibleCount == 0 ? "新截图会保存在本机，可从截图历史查看。" : "\(setup.visibleCount) 张截图在边缘，可从截图历史查看。"
            } else if let issue = setup.issue, issue == .unsupportedBrowser || issue == .targetUnavailable {
                detail = issue.text
            } else {
                detail = setup.visibleCount == 0 ? "截图后，点一下边缘微图。" : "\(setup.visibleCount) 张截图在边缘，打开要用的 Chrome 聊天草稿后点选。"
            }
            symbol = "checkmark.circle"
            recoveryTitle = nil; recoveryPage = nil
        } else if !capabilities.initialized || setup.collection == .starting {
            state = .preparing; title = "正在准备截图收录"
            detail = "尚未确认开始；已有图片保留。"
            symbol = "clock"
            recoveryTitle = nil; recoveryPage = nil
        } else {
            state = .stopped; title = "当前未收录新截图"
            detail = "已有图片保留，可在设置查看当前状态。"
            symbol = "circle.dashed"
            recoveryTitle = nil; recoveryPage = nil
        }
    }
}
