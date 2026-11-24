import AppKit

typealias OnboardingCopy = ProductCopy

extension ProductCopy {
    var continueButton: String { text("继续", "Continue") }
    var back: String { text("上一步", "Back") }
    var later: String { text("稍后设置", "Set Up Later") }
    var headline: String { text("读取 Mac 上的截图", "Read screenshots saved on your Mac") }
    var chromeMenuHeading: String { text("检查浏览器连接", "Check the browser connection") }
    var checkConnection: String { text("检查连接", "Check Connection") }
    var allowAccess: String { text("允许访问…", "Allow Access…") }
    var checkPermission: String { text("检查浏览器权限…", "Check Browser Access…") }
    var title: String { text("开始使用 Riftlet", "Get Started with Riftlet") }
    var stepFolder: String { text("截图文件夹", "Screenshot Folder") }
    var stepChrome: String { text("连接浏览器", "Connect Browser") }
    var stepPosition: String { text("桌面位置", "Desktop Position") }
    var scrollLabel: String { text("Riftlet 使用引导内容", "Riftlet setup instructions") }
    var folderHeading: String { text("截图保存位置", "Screenshot folder") }
    var resume: String { text("继续收录", "Resume Collection") }
    var unhide: String { text("显示桌面截图", "Show Desktop Screenshots") }
    var recheckFolder: String { text("重新检查文件夹", "Check Folder Again") }
    var chromeHeading: String { text("把截图附加到 ChatGPT", "Attach screenshots to ChatGPT") }
    var automationHeading: String { text("允许 Riftlet 连接浏览器", "Allow Riftlet to connect to your browser") }
    var display: String { text("所在显示器", "Display") }
    var retryDisplay: String { text("重试显示器选择", "Retry Display Selection") }
    var retryPosition: String { text("重试位置选择", "Retry Position") }
    var positionHeading: String { text("选一个顺手的位置", "Choose a desktop position") }
    var positionDetail: String {
        text("新截图会从所选的屏幕边缘出现。之后可以在设置中调整。",
             "New screenshots appear at the edge you choose. You can change this later in Settings.")
    }
    var rootLabel: String { text("开始使用 Riftlet，两步引导", "Get started with Riftlet in two steps") }
    var introDetail: String {
        text("Riftlet 从截图文件夹读取新图。点托盘里的图片，就能将它附加到 Chrome 或 Edge 中的 ChatGPT 草稿。",
             "Riftlet reads new images from your screenshot folder. Click a thumbnail in the tray to add it to your ChatGPT draft in Chrome or Edge.")
    }
    var reviewDetail: String {
        text("当前为隔离审核：不连接浏览器或上传。",
             "This preview runs locally without connecting to a browser or uploading files.")
    }
    var authorizeFolder: String { text("授权读取系统截图文件夹…", "Allow Screenshot Folder Access…") }
    var localOnly: String { text("此模式仅使用本机截图。", "This mode uses local screenshots only.") }
    var recheckChrome: String { text("重新检查浏览器", "Check Browser Again") }
    var recheckConnection: String { text("重新检查连接", "Check Connection Again") }
    var legacyPosition: String {
        text("沿用之前的桌面位置。选择一个位置即可更改。",
             "Your previous desktop position is in use. Choose a position to change it.")
    }
    var fallbackDisplay: String {
        text(" 当前暂用可用显示器，已选屏幕的偏好仍保留。",
             " An available display is in use. Your preferred display is still saved.")
    }
    var previewFinish: String {
        text("预览结束后，可以从菜单栏打开设置和截图仓库。",
             "After this preview, open Settings or Screenshot Library from the menu bar.")
    }
    var finishFolder: String {
        text("请先完成截图文件夹设置，让新截图显示在桌面边缘。",
             "Set up your screenshot folder first so new screenshots can appear at the edge of your desktop.")
    }
    var finishChrome: String { text("请先完成浏览器连接设置。", "Finish connecting your browser first.") }
    func finishReady(browser: SetupBrowser) -> String {
        text("已连接 \(browser.displayName)。截一张图，在 \(browser.displayName) 打开要使用的 ChatGPT 草稿，点桌面边缘的缩略图即可附加。",
             "\(browser.displayName) is connected. Take a screenshot, open your ChatGPT draft in \(browser.displayName), then click the thumbnail at the edge of your desktop to attach it.")
    }
    var folderUnreadable: String {
        text("请确认截图文件夹仍可用。如果曾在 macOS 提示中拒绝访问，请在“文件与文件夹”中允许 Riftlet 读取这个位置，再回到这里。",
             "Check that your screenshot folder is available. If you denied access in macOS, allow Riftlet to read this location in Files and Folders, then return here.")
    }
    var filePrivacy: String { text("打开“文件与文件夹”设置…", "Open Files and Folders Settings…") }
    var wrongFolder: String {
        text("请在选择窗口中确认上面显示的截图文件夹。",
             "In the folder picker, select the screenshot folder shown above.")
    }
    var startupFailed: String {
        text("Riftlet 未能启动收录。请检查可用磁盘空间，然后重新打开 Riftlet。",
             "Collection couldn’t start. Check your available disk space, then reopen Riftlet.")
    }
    var lowSpace: String {
        text("磁盘空间不足。请腾出空间并重新检查。",
             "There isn’t enough disk space. Free some space, then check the folder again.")
    }
    var writeFailed: String {
        text("无法保存新截图。请检查磁盘是否可写，再重新检查。",
             "New screenshots couldn’t be saved. Check that you can write to the disk, then check the folder again.")
    }
    var paused: String {
        text("截图收录已暂停。继续收录后，新截图才会出现在桌面边缘。",
             "Collection is paused. Resume collection to see new screenshots at the edge of your desktop.")
    }
    var hidden: String {
        text("桌面截图已隐藏。开启显示后，即可点击缩略图。",
             "Desktop screenshots are hidden. Show them to make the thumbnails available.")
    }
    var collecting: String { text("正在收录这个文件夹里的新截图。", "Collecting new screenshots from this folder.") }
    var starting: String { text("正在准备收录。", "Preparing to collect screenshots.") }
    var checkingFolder: String {
        text("正在检查截图文件夹。如果 macOS 询问是否允许 Riftlet 访问这个位置，请点“允许”。",
             "Checking your screenshot folder. If macOS asks whether Riftlet can access this location, choose Allow.")
    }
    var unusedFolder: String { text("此模式不读取系统截图文件夹。", "This mode doesn’t read your Mac’s screenshot folder.") }
    var configureFolder: String {
        text("在 Mac 的“截屏”应用中打开“选项”，将保存位置设为文件夹，然后重新检查。",
             "In the Mac Screenshot app, open Options and choose a folder under Save to. Then check the folder again.")
    }
    var chooseFolder: String {
        text("选择这个文件夹，允许 Riftlet 读取新截图。",
             "Select this folder to let Riftlet read new screenshots.")
    }
    var unchecked: String { text("点“检查连接”，确认当前浏览器可用。", "Choose Check Connection to verify the current browser.") }
    var checking: String { text("正在检查浏览器连接…", "Checking the browser connection…") }
    var connected: String { text("已连接浏览器。", "Browser connected.") }
    var jsDisabled: String {
        text("浏览器的这个选项尚未开启。勾选后重新检查。",
             "This browser option is off. Turn it on, then check the connection again.")
    }
    var noWindow: String {
        text("请在浏览器中打开一个普通网页，然后重新检查。",
             "Open a regular webpage in your browser, then check the connection again.")
    }
    var unavailable: String {
        text("未能连接到浏览器。请打开一个普通网页，然后重新检查。",
             "Couldn’t connect to the browser. Open a regular webpage in your browser, then check the connection again.")
    }
    var primaryDisplay: String { text("使用主显示器", "Use Main Display") }
    var disconnectedDisplay: String { text("已选显示器（未连接）", "Selected Display (Disconnected)") }
    var setUpFolder: String { text("设置截图文件夹", "Set Up Screenshot Folder") }
    var endPreview: String { text("结束预览", "Finish Preview") }
    var getStarted: String { text("开始使用", "Get Started") }
    var illustrationLabel: String { text("截图进入当前聊天草稿的示意", "Illustration of a screenshot attached to a chat draft") }
    var placementPreviewLabel: String { text("桌面边缘位置预览", "Desktop edge position preview") }
    var composerPlaceholder: String { text("给 ChatGPT 发送消息", "Message ChatGPT") }
    var pickerTitle: String { text("允许 Riftlet 读取系统截图位置", "Allow Riftlet to read your screenshot folder") }
    var pickerMessage: String {
        text("请确认允许 Riftlet 读取当前系统截图文件夹：",
             "Allow Riftlet to read new screenshots in this folder:")
    }
    var pickerButton: String { text("允许读取", "Allow Access") }

    func positionLabel(_ value: RiftPlacement) -> String {
        text("桌面位置：" + value.title(in: .simplifiedChinese), "Desktop position: " + placement(value))
    }

    func placement(_ value: RiftPlacement) -> String {
        value.title(in: self == .english ? .english : .simplifiedChinese)
    }

    func saveError(display: Bool) -> String {
        let name = display ? "显示器" : "位置"
        return text("\(name)未能保存，仍保留原选择。可以重试这次选择。",
                    display ? "The display couldn’t be saved. Your previous choice is still in use. Try again."
                            : "The position couldn’t be saved. Your previous choice is still in use. Try again.")
    }

    func progress(step: Int) -> String {
        text("第 \(step) 步，共 2 步", "Step \(step) of 2")
    }

    func introduction(_ presentation: SetupPresentation) -> (title: String, detail: String) {
        guard self == .english else { return (presentation.firstUseTitle, presentation.firstUseDescription) }
        switch presentation.snapshot.attachment {
        case .available: return (headline, introDetail)
        case .productionDisabled:
            return ("Keep screenshots at the edge of your desktop", "View your screenshots and history locally. Attachments are unavailable in this mode.")
        case .offlineSimulation:
            return ("Explore Riftlet offline", "Try the desktop edge with sample images in an offline demo.")
        case .syntheticWeb:
            return ("Preview web attachments", "Only generated test images are collected for this preview.")
        case .systemScreenshotCandidate:
            return ("Preview screenshot attachments", "This internal build attaches a screenshot after verifying the image and its destination.")
        case .unsupportedBrowser, .targetUnavailable:
            return ("Open your ChatGPT draft in Chrome or Edge", "Your screenshots are saved on this Mac. Bring your intended ChatGPT draft to the front in Chrome or Edge.")
        }
    }

    func storageIssue(_ issue: SetupIssue?) -> String {
        guard self == .english else { return issue?.text ?? "" }
        switch issue {
        case .insufficientSpace: return lowSpace
        case .privateWriteFailed: return writeFailed
        case .sourceVolumeUnidentified:
            return "Riftlet can’t identify the disk that holds your screenshot folder. In Screenshot, open Options and choose another save location, then check the folder again."
        default: return ""
        }
    }

    func automationStatus(_ presentation: SetupPresentation) -> String {
        presentation.automationStatusText ?? localOnly
    }

    func chromeInstructions(_ presentation: SetupPresentation) -> String {
        guard let instructions = presentation.chromeScriptInstructions else { return "" }
        // Only the host's known browser recipe is localized. Custom details have
        // already gone through the presentation’s sanitization and size limit.
        guard instructions == ChromeAttachmentSetup.instructions(in: .english, browser: presentation.snapshot.browser)
                || instructions == ChromeAttachmentSetup.instructions(in: .simplifiedChinese, browser: presentation.snapshot.browser) else { return instructions }
        return ChromeAttachmentSetup.instructions(in: self, browser: presentation.snapshot.browser)
    }
}

/// Called on the system picker used to authorize the detected screenshot folder.
/// The host still chooses and validates the URL and owns the authorization.
public enum ScreenshotFolderPickerCopy {
    @MainActor public static func configure(_ panel: NSOpenPanel, folder: URL) {
        let copy = OnboardingCopy.current
        panel.title = copy.pickerTitle
        panel.message = copy.pickerMessage + "\n" + folder.path
        panel.prompt = copy.pickerButton
    }

    public static var wrongFolder: String {
        OnboardingCopy.current == .english ? "The selected folder is different from your Mac’s screenshot folder."
                                           : "所选文件夹与当前系统截图位置不同。"
    }

    public static var recoverySuggestion: String {
        OnboardingCopy.current == .english
            ? "Select the folder shown in the picker. To see where screenshots are saved, open Screenshot → Options → Save to."
            : "请选择窗口中显示的截图文件夹。可以在 macOS「截屏」的「选项」中查看保存位置。"
    }
}
