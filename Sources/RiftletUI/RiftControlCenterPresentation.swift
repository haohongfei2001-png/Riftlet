import Foundation

/// A short projection of the host's facts, shared by the popover and menu.
/// It carries no mutable collection, permission, or persistence authority.
public struct RiftControlCenterPresentation {
    public enum State: Equatable { case attention, paused, hidden, collecting, preparing, stopped }
    public let state: State
    public let title: String
    public let detail: String
    public let symbol: String
    public let primaryTitle: String
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
            case .collection, .visibility, .archive: pages.insert(.capture)
            }
        }
        if snapshot.appearance.failure != nil || snapshot.appearance.unreadable { pages.insert(.general) }
        if snapshot.login.errorCode != nil || snapshot.login.notConfirmed { pages.insert(.general) }
        switch snapshot.setup.issue {
        case .screenshotPreferenceUnsaved: pages.insert(.capture)
        case .visibilityPreferenceUnsaved, .collectionPreferenceUnsaved: pages.insert(.capture)
        default: break
        }
        return SettingsPage.allCases.first(where: pages.contains)
    }

    public init(_ snapshot: SettingsProductSnapshot, copy: ProductCopy = .current) {
        primaryTitle = copy.text("截图…", "Take Screenshot…")
        let setup = snapshot.setup
        let owner = snapshot.state.owner
        let capabilities = snapshot.capabilities
        let usesAutomation = [.available, .syntheticWeb, .systemScreenshotCandidate].contains(setup.attachment)
        primaryEnabled = capabilities.canCapture
        if capabilities.canCapture {
            captureHint = nil
        } else if snapshot.reviewEnvironment {
            captureHint = copy.text("隔离审核不执行真实截图或上传。", "This preview does not capture or upload screenshots.")
        } else if !owner.settings.entryEnabled {
            captureHint = copy.text("内置截图已关闭，可在设置的“截图”页开启。", "Built-in capture is off. Turn it on in Screenshot settings.")
        } else if !owner.settings.entryAvailable {
            captureHint = copy.text("内置截图当前不可用；可在设置查看状态。", "Built-in capture is unavailable. Check Screenshot settings.")
        } else if owner.isHidden {
            captureHint = copy.text("桌面截图已隐藏；内置截图暂不可用。", "Desktop screenshots are hidden. Built-in capture is unavailable.")
        } else {
            captureHint = copy.text("内置截图暂不可用；可在设置查看当前状态。", "Built-in capture is unavailable. Check Screenshot settings.")
        }
        if let page = Self.saveRecoveryPage(snapshot) {
            state = .attention; title = copy.text("有设置尚未确认保存", "Some settings could not be saved")
            detail = copy.text("请打开未保存的设置并重试。", "Open the affected setting and try saving again.")
            symbol = "exclamationmark.circle"
            recoveryTitle = copy.text("查看未保存的设置", "Show Unsaved Settings"); recoveryPage = page
        } else if setup.issue == .configurationUnavailable {
            state = .attention; title = copy.text("设置暂不可用", "Settings Unavailable")
            detail = SetupIssue.configurationUnavailable.text(in: copy)
            symbol = "exclamationmark.circle"
            recoveryTitle = nil; recoveryPage = nil
        } else if setup.issue == .initializationFailed {
            state = .attention; title = copy.text("Riftlet 未能完成启动", "Riftlet Couldn’t Finish Starting")
            detail = SetupIssue.initializationFailed.text(in: copy)
            symbol = "exclamationmark.circle"
            recoveryTitle = copy.text("查看启动问题", "View Startup Help"); recoveryPage = .help
        } else if setup.issue == .insufficientSpace || setup.issue == .privateWriteFailed
                    || setup.storage == .insufficientSpace || setup.storage == .writeFailed {
            state = .attention; title = copy.text("无法保存新截图", "Can’t Save New Screenshots")
            detail = copy.text("请检查可用磁盘空间和文件访问权限。", "Check available disk space and file access.")
            symbol = "exclamationmark.circle"
            recoveryTitle = copy.text("查看本机存储", "Show Local Storage"); recoveryPage = .capture
        } else if setup.issue == .screenshotFolderNeedsSelection {
            state = .attention; title = copy.text("需要重新选择截图文件夹", "Choose Your Screenshot Folder Again")
            detail = copy.text("此前的文件夹选择已无法确认，已有截图保留。", "Riftlet can no longer verify the previous folder. Your screenshots are safe.")
            symbol = "folder.badge.questionmark"
            recoveryTitle = copy.text("查看截图位置", "Show Screenshot Location"); recoveryPage = .capture
        } else if setup.source == .unavailable || setup.source == .notConfigured || setup.issue == .sourceAccess {
            state = .attention; title = copy.text("无法访问截图位置", "Can’t Access the Screenshot Folder")
            detail = copy.text("已有图片保留；请检查当前系统截图位置。", "Check where your Mac saves screenshots. Your existing images are safe.")
            symbol = "folder.badge.questionmark"
            recoveryTitle = copy.text("检查截图位置", "Check Screenshot Location"); recoveryPage = .capture
        } else if !owner.collectionPaused, setup.issue == .sourceVolumeUnidentified {
            state = .attention; title = copy.text("当前截图位置无法收录", "Can’t Collect from This Location")
            detail = SetupIssue.sourceVolumeUnidentified.text(in: copy)
            symbol = "folder.badge.questionmark"
            recoveryTitle = copy.text("检查截图位置", "Check Screenshot Location"); recoveryPage = .capture
        } else if !owner.collectionPaused, let issue = setup.issue, [.fileVolumeUnidentified, .historicalSourceUnconfirmed].contains(issue) {
            state = .attention; title = copy.text("部分截图暂缓收录", "Some Screenshots Are on Hold")
            detail = issue.text(in: copy)
            symbol = "clock"
            recoveryTitle = copy.text("查看收录说明", "Show Collection Details"); recoveryPage = .capture
        } else if usesAutomation && (setup.permission == .denied || setup.issue == .permissionDenied) {
            state = .attention; title = copy.text("需要允许 Riftlet 控制 Chrome", "Allow Riftlet to Control Chrome")
            detail = copy.text("在系统设置中允许访问 Chrome，即可继续设置一键附加。", "Allow Chrome access in System Settings, then finish setting up one-click attachments.")
            symbol = "exclamationmark.circle"
            recoveryTitle = copy.text("检查 Chrome 连接", "Check Chrome Connection"); recoveryPage = .help
        } else if usesAutomation && (setup.issue == .chromeJavaScriptDisabled || snapshot.chromeConnection == .javaScriptDisabled) {
            state = .attention; title = copy.text("需要开启 Chrome 的 JavaScript 选项", "Enable JavaScript from Apple Events in Chrome")
            detail = setup.issue == .chromeJavaScriptDisabled ? SetupIssue.chromeJavaScriptDisabled.text(in: copy) : ChromeAttachmentSetup.instructions(in: copy)
            symbol = "globe"
            recoveryTitle = copy.text("检查 Chrome 连接", "Check Chrome Connection"); recoveryPage = .help
        } else if owner.collectionPaused {
            state = .paused; title = copy.text("已暂停收录", "Collection Paused")
            detail = owner.isHidden ? copy.text("已有截图保留；桌面截图也已隐藏。", "Desktop screenshots are also hidden. Existing images are kept.") : copy.text("已有截图保留，仍可按需使用。", "Existing screenshots are still available.")
            symbol = "pause.circle"
            recoveryTitle = nil; recoveryPage = nil
        } else if owner.isHidden {
            state = .hidden; title = copy.text("桌面截图已隐藏", "Desktop Screenshots Hidden")
            detail = setup.collection == .collecting ? copy.text("仍在收录新的截图。", "New screenshots are still being collected.") : copy.text("只影响边缘显示；收录按当前运行状态进行。", "Showing or hiding thumbnails does not change collection.")
            symbol = "eye.slash"
            recoveryTitle = nil; recoveryPage = nil
        } else if setup.collection == .collecting {
            state = .collecting; title = copy.text("正在收录截图", "Collecting Screenshots")
            if snapshot.reviewEnvironment {
                detail = setup.visibleCount == 0 ? copy.text("仅收录审核示例，不会上传。", "Preview examples stay on this Mac. Nothing is uploaded.") : copy.text("\(setup.visibleCount) 张审核示例在边缘，不会上传。", "Preview items at the edge: \(setup.visibleCount). Nothing is uploaded.")
            } else if !usesAutomation {
                detail = setup.visibleCount == 0 ? copy.text("新截图会保存在本机，可从截图历史查看。", "New screenshots are saved on this Mac. See them in Screenshot History.") : copy.text("\(setup.visibleCount) 张截图在边缘，可从截图历史查看。", "Screenshots at the edge: \(setup.visibleCount). See them in Screenshot History.")
            } else if let issue = setup.issue, issue.isAttachmentConnectionIssue {
                detail = issue.text(in: copy)
            } else {
                detail = setup.visibleCount == 0 ? copy.text("截图后，点一下边缘微图。", "Take a screenshot, then click its thumbnail.") : copy.text("\(setup.visibleCount) 张截图在边缘，打开要用的 Chrome 聊天草稿后点选。", "Screenshots at the edge: \(setup.visibleCount). Open your ChatGPT draft in Chrome and click one.")
            }
            symbol = "checkmark.circle"
            recoveryTitle = nil; recoveryPage = nil
        } else if !capabilities.initialized || setup.collection == .starting {
            state = .preparing; title = copy.text("正在准备截图收录", "Preparing Screenshot Collection")
            detail = copy.text("正在检查截图文件夹。", "Checking the screenshot folder.")
            symbol = "clock"
            recoveryTitle = nil; recoveryPage = nil
        } else {
            state = .stopped; title = copy.text("当前未收录新截图", "Collection Is Stopped")
            detail = copy.text("可在设置中查看截图文件夹和收录开关。", "Check the screenshot folder and collection setting.")
            symbol = "circle.dashed"
            recoveryTitle = nil; recoveryPage = nil
        }
    }
}
