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

    /// Multiple failures remain independent. Offer the first affected page in
    /// sidebar order; the next unconfirmed page becomes reachable after retry.
    private static func saveRecoveryPage(_ snapshot: SettingsProductSnapshot) -> SettingsPage? {
        var pages = Set<SettingsPage>()
        for (domain, state) in snapshot.state.domains where state.saveFailure != nil {
            switch domain {
            case .arrival, .layout, .placement, .display, .desktopForm, .windChimeArrangement, .trayTheme: pages.insert(.display)
            case .entry, .captureMode, .trayFavorite1, .trayFavorite2, .trayFavorite3: pages.insert(.capture)
            case .collection, .visibility, .archive: pages.insert(.history)
            }
        }
        if snapshot.appearance.failure != nil || snapshot.appearance.unreadable { pages.insert(.display) }
        if snapshot.login.errorCode != nil || snapshot.login.notConfirmed { pages.insert(.history) }
        switch snapshot.setup.issue {
        case .screenshotPreferenceUnsaved: pages.insert(.capture)
        case .visibilityPreferenceUnsaved, .collectionPreferenceUnsaved: pages.insert(.history)
        case .configurationUnavailable: pages.insert(.help) // Reload/open configuration.
        default: break
        }
        return SettingsPage.allCases.first(where: pages.contains)
    }

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
            captureHint = "内置截图已关闭，可在设置的“截图”页开启。"
        } else if !owner.settings.entryAvailable {
            captureHint = "内置截图当前不可用；可在设置查看状态。"
        } else if owner.isHidden {
            captureHint = "桌面截图已隐藏；内置截图暂不可用。"
        } else {
            captureHint = "内置截图暂不可用；可在设置查看当前状态。"
        }
        if let page = Self.saveRecoveryPage(snapshot) {
            state = .attention; title = "有设置尚未确认保存"
            detail = "请打开未保存的设置并重试。"
            symbol = "exclamationmark.circle"
            recoveryTitle = "查看未保存的设置"; recoveryPage = page
        } else if setup.issue == .initializationFailed {
            state = .attention; title = "Riftlet 未能完成启动"
            detail = "已有图片保留。请查看权限与帮助。"
            symbol = "exclamationmark.circle"
            recoveryTitle = "查看启动问题"; recoveryPage = .help
        } else if setup.issue == .insufficientSpace || setup.issue == .privateWriteFailed
                    || setup.storage == .insufficientSpace || setup.storage == .writeFailed {
            state = .attention; title = "无法保存新截图"
            detail = "请检查可用磁盘空间和文件访问权限。"
            symbol = "exclamationmark.circle"
            recoveryTitle = "查看本机存储"; recoveryPage = .history
        } else if setup.issue == .screenshotFolderNeedsSelection {
            state = .attention; title = "需要重新选择截图文件夹"
            detail = "此前的文件夹选择已无法确认，已有截图保留。"
            symbol = "folder.badge.questionmark"
            recoveryTitle = "查看截图位置"; recoveryPage = .help
        } else if setup.source == .unavailable || setup.source == .notConfigured || setup.issue == .sourceAccess {
            state = .attention; title = "无法访问截图位置"
            detail = "已有图片保留；请检查当前系统截图位置。"
            symbol = "folder.badge.questionmark"
            recoveryTitle = "检查截图位置"; recoveryPage = .help
        } else if !owner.collectionPaused, setup.issue == .sourceVolumeUnidentified {
            state = .attention; title = "当前截图位置无法收录"
            detail = SetupIssue.sourceVolumeUnidentified.text
            symbol = "folder.badge.questionmark"
            recoveryTitle = "检查截图位置"; recoveryPage = .capture
        } else if !owner.collectionPaused, let issue = setup.issue, [.fileVolumeUnidentified, .historicalSourceUnconfirmed].contains(issue) {
            state = .attention; title = "部分截图暂缓收录"
            detail = issue.text
            symbol = "clock"
            recoveryTitle = "查看收录说明"; recoveryPage = .capture
        } else if usesAutomation && (setup.permission == .denied || setup.issue == .permissionDenied) {
            state = .attention; title = "需要允许 Riftlet 控制 Chrome"
            detail = "在系统设置中允许访问 Chrome，即可继续设置一键附加。"
            symbol = "exclamationmark.circle"
            recoveryTitle = "检查 Chrome 连接"; recoveryPage = .help
        } else if usesAutomation && (setup.issue == .chromeJavaScriptDisabled || snapshot.chromeConnection == .javaScriptDisabled) {
            state = .attention; title = "需要开启 Chrome 的 JavaScript 选项"
            detail = setup.issue == .chromeJavaScriptDisabled ? SetupIssue.chromeJavaScriptDisabled.text : ChromeAttachmentSetup.instructions
            symbol = "globe"
            recoveryTitle = "检查 Chrome 连接"; recoveryPage = .help
        } else if owner.collectionPaused {
            state = .paused; title = "已暂停收录"
            detail = owner.isHidden ? "已有截图保留；桌面截图也已隐藏。" : "已有截图保留，仍可按需使用。"
            symbol = "pause.circle"
            recoveryTitle = nil; recoveryPage = nil
        } else if owner.isHidden {
            state = .hidden; title = "桌面截图已隐藏"
            detail = setup.collection == .collecting ? "仍在收录新的截图。" : "只影响边缘显示；收录按当前运行状态进行。"
            symbol = "eye.slash"
            recoveryTitle = nil; recoveryPage = nil
        } else if setup.collection == .collecting {
            state = .collecting; title = "正在收录截图"
            if snapshot.reviewEnvironment {
                detail = setup.visibleCount == 0 ? "仅收录审核示例，不会上传。" : "\(setup.visibleCount) 张审核示例在边缘，不会上传。"
            } else if !usesAutomation {
                detail = setup.visibleCount == 0 ? "新截图会保存在本机，可从截图历史查看。" : "\(setup.visibleCount) 张截图在边缘，可从截图历史查看。"
            } else if let issue = setup.issue, issue.isAttachmentConnectionIssue {
                detail = issue.text
            } else {
                detail = setup.visibleCount == 0 ? "截图后，点一下边缘微图。" : "\(setup.visibleCount) 张截图在边缘，打开要用的 Chrome 聊天草稿后点选。"
            }
            symbol = "checkmark.circle"
            recoveryTitle = nil; recoveryPage = nil
        } else if !capabilities.initialized || setup.collection == .starting {
            state = .preparing; title = "正在准备截图收录"
            detail = "正在检查截图文件夹。"
            symbol = "clock"
            recoveryTitle = nil; recoveryPage = nil
        } else {
            state = .stopped; title = "当前未收录新截图"
            detail = "可在设置中查看截图文件夹和收录开关。"
            symbol = "circle.dashed"
            recoveryTitle = nil; recoveryPage = nil
        }
    }
}
