import Foundation
import RiftletCapture

public enum SetupSourceState: Equatable, Sendable { case checking, notChecked, notApplicable, accessible, unavailable, notConfigured }
public enum SetupCollectionState: Equatable, Sendable { case starting, collecting, waitingForSource, paused, stopped }
public enum SetupAttachmentState: Equatable, Sendable {
    case productionDisabled, syntheticWeb, systemScreenshotCandidate, offlineSimulation, available, unsupportedBrowser, targetUnavailable
}
public enum SetupPermissionState: Equatable, Sendable {
    case notNeeded, notChecked, notRequested, granted, denied, notRunning, browserUnavailable, unavailable
}
public enum SetupStorageState: Equatable, Sendable {
    case notMeasured, measuring, measured(bytes: UInt64, complete: Bool), insufficientSpace, writeFailed, unavailable
}

/// The menu belongs to Chrome. Its instructions never represent a permission observation.
public enum ChromeAttachmentSetup {
    public static let menuPath = "显示 → 开发者 → 允许 Apple 事件中的 JavaScript"
    public static let instructions = "在 Chrome 菜单栏勾选“" + menuPath + "”。已获 Chrome 自动化权限的应用可执行网页脚本。"
}

/// Closed, local-only explanations. The presentation never displays an Error's
/// description, file contents, browser identity, URL, or arbitrary remote text.
public enum SetupIssue: Equatable, Sendable {
    case sourceAccess, wrongScreenshotFolder, screenshotFolderNeedsSelection, unsupportedFormat, unsupportedSize, invalidImage
    case insufficientSpace, privateWriteFailed, storageUnavailable
    case sourceVolumeUnidentified, fileVolumeUnidentified, historicalSourceUnconfirmed
    case unsupportedBrowser, targetUnavailable, permissionDenied, chromeJavaScriptDisabled, imageUnavailable
    case initializationFailed, configurationUnavailable
    case visibilityPreferenceUnsaved, collectionPreferenceUnsaved
    case screenshotPreferenceUnsaved
    case attachmentFormat, attachmentBytes, attachmentPixels, attachmentSource

    var isAttachmentConnectionIssue: Bool {
        self == .unsupportedBrowser || self == .targetUnavailable || self == .chromeJavaScriptDisabled
    }

    public var text: String {
        switch self {
        case .attachmentSource:
            return "这张图片来自不支持一键附加的来源。请在 ChatGPT 中手动选择原图。"
        case .attachmentFormat:
            return "截图已保存在本机。此 PNG 格式暂不支持一键附加，请在 ChatGPT 中手动选择原图。"
        case .attachmentBytes:
            return "截图已保存在本机。文件太大，无法一键附加。可以截取较小的区域，或在 ChatGPT 中手动选择原图。"
        case .attachmentPixels:
            return "截图已保存在本机。图片尺寸过大，无法一键附加。可以截取较小的区域。"
        case .sourceAccess:
            return "无法读取截图保存位置。请确认文件夹仍存在，在系统设置「隐私与安全性 → 文件与文件夹」中检查 Riftlet，或允许访问当前截图位置；原截图没有被删除。"
        case .sourceVolumeUnidentified:
            return CaptureDiagnostic(code: .sourceVolumeUnidentified).userMessage
        case .fileVolumeUnidentified:
            return CaptureDiagnostic(code: .fileVolumeUnidentified).userMessage
        case .historicalSourceUnconfirmed:
            return CaptureDiagnostic(code: .historicalSourceUnconfirmed).userMessage
        case .wrongScreenshotFolder:
            return "所选文件夹与当前系统截图位置不同。点“重新检查”，确认路径后再选择截图文件夹。"
        case .screenshotFolderNeedsSelection:
            return "此前选择的截图文件夹已无法确认。请重新选择下方的系统截图文件夹，确认后再继续收录。已有截图保留。"
        case .unsupportedFormat:
            return "这张截图的格式暂不支持，未收录。原文件保留，可在下方查看当前支持的格式。"
        case .unsupportedSize:
            return "这张截图超过当前文件或像素上限，未收录。原文件保留，其他符合要求的截图仍可收录。"
        case .invalidImage:
            return "图片尚未完整写入或无法完整解码，暂未收录。原文件保留；可重新检查截图来源。"
        case .insufficientSpace:
            return "私有存储空间不足，新的截图暂不能安全保存。请释放磁盘空间后重新检查；已有记录与系统原图保留。"
        case .privateWriteFailed:
            return "无法写入 Riftlet 私有存储。请检查磁盘和访问权限后重新检查；不要删除已有数据来恢复。"
        case .storageUnavailable:
            return "暂时无法检查私有存储，不能确认保存状态。已有记录与系统原图保留。"
        case .unsupportedBrowser:
            return "请用 Google Chrome 打开要附加图片的 ChatGPT 草稿。截图仍在本机。"
        case .targetUnavailable:
            return "未能连接到可附加图片的聊天。请在 Chrome 前台显示要用的 ChatGPT 草稿，确认其中有添加附件的入口。截图仍在本机。"
        case .permissionDenied:
            return "Chrome 自动化访问被拒绝。请在系统设置的「隐私与安全性 → 自动化」中检查 Riftlet，再重新检查。"
        case .chromeJavaScriptDisabled:
            return "Chrome 拒绝了这次附加，截图仍在本机。" + ChromeAttachmentSetup.instructions
        case .imageUnavailable:
            return "这张截图的私有副本暂不可用。没有重新附加，也没有删除系统原图。"
        case .initializationFailed:
            return "Riftlet 未能完成启动。已有数据保留；请检查磁盘与文件访问权限，再重新打开应用。"
        case .configurationUnavailable:
            return "部分设置无法读取。请在“权限与帮助”的“关于与诊断”中点“重新读取配置”。"
        case .visibilityPreferenceUnsaved:
            return "显示偏好未能保存；本次运行保持隐藏，重启可能恢复之前的设置。请检查磁盘可写后重新操作；图片仍保留。"
        case .collectionPreferenceUnsaved:
            return "收录开关未能保存；本次运行仍暂停收录，重启可能恢复之前的设置。请检查磁盘可写后重新操作；已有图片仍保留。"
        case .screenshotPreferenceUnsaved:
            return "内置截图设置未能保存；重启可能恢复之前的设置。请检查磁盘可写后重试；系统截图收录和已有图片仍保留。"
        }
    }
}

/// A user-facing snapshot composed by the host. Updating it has no side effects.
/// `sourceLocation` stays inside the local window; it must not be included in
/// public diagnostics. Support/version text is supplied by the host's actual
/// capability manifest rather than inferred from a minimum OS version.
public struct SetupSnapshot: Equatable, Sendable {
    public let sourceLocation: String?
    public let source: SetupSourceState
    public let collection: SetupCollectionState
    public let isHidden: Bool
    public let visibleCount: Int
    public let pendingCount: Int
    public let attachment: SetupAttachmentState
    public let permission: SetupPermissionState
    public let permissionDetail: String?
    public let storage: SetupStorageState
    public let issue: SetupIssue?
    public let supportDescription: String
    /// A host-owned collection/recheck transaction is in flight. This is UI
    /// feedback only; the host must also serialize mutations independently.
    public let isChecking: Bool
    /// nil means this application mode has no built-in screenshot capability.
    /// Independent of collection pause, rift visibility and TCC permission.
    public let builtInScreenshotEnabled: Bool?
    public let defaultScreenshotMode: ScreenshotMode

    public init(sourceLocation: String? = nil, source: SetupSourceState = .checking,
                collection: SetupCollectionState = .starting, isHidden: Bool = false,
                visibleCount: Int = 0, pendingCount: Int = 0,
                attachment: SetupAttachmentState = .productionDisabled,
                permission: SetupPermissionState = .notNeeded, permissionDetail: String? = nil,
                storage: SetupStorageState = .notMeasured, issue: SetupIssue? = nil,
                supportDescription: String = "", isChecking: Bool = false,
                builtInScreenshotEnabled: Bool? = nil, defaultScreenshotMode: ScreenshotMode = .window) {
        self.sourceLocation = sourceLocation; self.source = source; self.collection = collection
        self.isHidden = isHidden; self.visibleCount = max(0, visibleCount); self.pendingCount = max(0, pendingCount)
        self.attachment = attachment; self.permission = permission; self.permissionDetail = permissionDetail
        self.storage = storage; self.issue = issue; self.supportDescription = supportDescription
        self.isChecking = isChecking
        self.builtInScreenshotEnabled = builtInScreenshotEnabled
        self.defaultScreenshotMode = defaultScreenshotMode
    }
}

public struct SetupPresentation: Equatable, Sendable {
    public let snapshot: SetupSnapshot
    public init(snapshot: SetupSnapshot) { self.snapshot = snapshot }

    /// First-use guidance follows the host's actual capability. It never turns
    /// a permission grant or an illustration into a promise of upload access.
    public var firstUseTitle: String {
        switch snapshot.attachment {
        case .productionDisabled: return "截图留在桌面边缘"
        case .offlineSimulation: return "认识 Riftlet · 离线演示"
        case .syntheticWeb: return "生成图片 · 网页验收"
        case .systemScreenshotCandidate: return "截图附加 · 内部候选"
        case .available: return "截图一次，点击一次"
        case .unsupportedBrowser, .targetUnavailable: return "截图保留，检查当前目标"
        }
    }

    public var firstUseCapability: String {
        switch snapshot.attachment {
        case .productionDisabled: return "本机收录与查看，附加尚未启用"
        case .offlineSimulation: return "仅演示生成图片，不读取或上传真实截图"
        case .syntheticWeb: return "仅附加生成的验收图片，不发送消息"
        case .systemScreenshotCandidate: return "仅在内部候选核验通过后附加，不发送消息"
        case .available: return "只附加图片，不发送消息"
        case .unsupportedBrowser, .targetUnavailable: return "当前目标不可用，截图继续保留在本机"
        }
    }

    public var firstUseDescription: String {
        switch snapshot.attachment {
        case .productionDisabled:
            return "截图自然地停在桌面边缘。当前仅本地收录，可以查看截图与历史。"
        case .offlineSimulation:
            return "用生成图片认识桌面边缘的裂缝。当前是离线演示，没有连接聊天草稿。"
        case .syntheticWeb:
            return "生成的测试图片停在桌面边缘。当前仅用于独立网页验收，不收录真实截图。"
        case .systemScreenshotCandidate:
            return "截图自然地停在桌面边缘。内部候选只在目标与图片均通过核验后，附加到当前聊天草稿。"
        case .available:
            return "新截图出现在桌面边缘。打开 Chrome 中的 ChatGPT 对话，点一下截图就能附加。"
        case .unsupportedBrowser, .targetUnavailable:
            return "截图自然地停在桌面边缘。当前附加目标不可用，图片留在本机。"
        }
    }

    public var firstUseFlow: String {
        switch snapshot.attachment {
        case .productionDisabled: return "截图 → 收录 → 查看"
        case .offlineSimulation: return "生成图片 → 显示 → 演示"
        case .syntheticWeb: return "生成测试图 → 核验目标 → 验收"
        case .systemScreenshotCandidate: return "出现 → 核验 → 附加"
        case .available: return "出现 → 点击 → 继续"
        case .unsupportedBrowser, .targetUnavailable: return "截图 → 保留 → 检查目标"
        }
    }

    public var firstUseNextStep: String {
        switch snapshot.attachment {
        case .productionDisabled:
            return "确认截图位置可读取并开启收录后，用一张新的截图开始。当前不会上传，授权也不会开启附加能力。"
        case .offlineSimulation:
            return "继续查看生成图片的显示与状态变化。演示不会读取真实截图，也不会上传。"
        case .syntheticWeb:
            return "仅使用此模式生成的测试图片；受支持的 Chrome 草稿仍需独立核验。不会上传真实截图。"
        case .systemScreenshotCandidate:
            return "仅在获准的内部验收中，使用新截图与受支持的 Chrome 普通已有对话。无需先聚焦发言框；目标和原样图片仍须通过核验。"
        case .available:
            return "在 Chrome 中打开要使用的 ChatGPT 对话，截一张图，再点桌面边缘的缩略图。"
        case .unsupportedBrowser, .targetUnavailable:
            return "先检查当前浏览器与聊天草稿。截图继续保留，不会切换到其他窗口或自动再次附加。"
        }
    }

    var sourceIssue: SetupIssue? {
        switch snapshot.issue {
        case .screenshotFolderNeedsSelection, .wrongScreenshotFolder, .sourceVolumeUnidentified,
             .fileVolumeUnidentified, .historicalSourceUnconfirmed:
            return snapshot.issue
        default: return nil
        }
    }

    public var sourceText: String {
        if let sourceIssue { return sourceIssue.text }
        switch snapshot.source {
        case .checking: return "正在检查系统截图保存位置。"
        case .notChecked: return "尚未检查截图文件夹的访问权限。"
        case .notApplicable: return "此模式不读取系统截图文件夹。"
        case .accessible: return "截图位置可读取。"
        case .unavailable: return "截图位置目前不可访问。请确认文件夹仍在原处，再点“允许访问此位置…”重新选择。"
        case .notConfigured: return "尚未找到截图文件夹。打开 Mac 的“截屏”应用，在“选项”中将截图存储到文件夹，然后点“重新检查”。"
        }
    }

    public var needsSourceAccess: Bool {
        hasSourceLocation && snapshot.source != .notApplicable
            && (snapshot.source != .accessible || snapshot.issue == .screenshotFolderNeedsSelection)
    }

    public var sourcePath: String {
        Self.displayText(snapshot.sourceLocation, limit: 4_096) ?? "尚未确定位置"
    }

    public var collectionText: String {
        switch snapshot.collection {
        case .starting: return "正在准备收录新截图。"
        case .collecting:
            if let issue = snapshot.issue, [.sourceVolumeUnidentified, .fileVolumeUnidentified, .historicalSourceUnconfirmed].contains(issue) {
                return issue.text
            }
            return "正在收录新截图。"
        case .waitingForSource: return "收录开关已开启。请确认 Riftlet 可以访问截图文件夹。"
        case .paused: return "收录已暂停；已有截图保留。隐藏桌面截图不会自动暂停收录。"
        case .stopped: return "当前未收录新截图；已有截图保留。"
        }
    }

    public var riftText: String {
        if snapshot.isHidden {
            return "桌面截图已隐藏（\(snapshot.visibleCount) 张待显示）。隐藏只影响显示，不删除图片，也不改变收录开关。"
        }
        if snapshot.visibleCount == 0 { return "没有可见截图。" }
        return "桌面边缘有 \(snapshot.visibleCount) 张截图。"
    }

    public var pendingText: String? {
        guard snapshot.pendingCount > 0 else { return nil }
        return "\(snapshot.pendingCount) 张结果待核实 · 图片仍保存在本机，不会自动再次附加。可在截图历史中查看。"
    }

    public var attachmentText: String {
        if let issue = snapshot.issue, hasAutomationCapability, issue.isAttachmentConnectionIssue {
            return issue.text
        }
        switch snapshot.attachment {
        case .productionDisabled:
            return "此工程版本尚未启用真实截图附加。截图可以在本机收录与查看；授权不会开启尚未验收的能力。"
        case .syntheticWeb:
            return "当前是独立 Web 验收模式，仅允许生成的测试图片。不会收录或上传真实截图，也不会发送聊天消息。"
        case .systemScreenshotCandidate:
            return "真实截图内部候选：仅支持 Chrome 中文 ChatGPT 普通已有聊天中的原样 8-bit RGBA PNG。新操作在真实上传开始后快速吞噬，独立完成证明到达后在后台记录成功。旧待核实操作保持原状；安全失败与重试未开放，不重传、不发送消息。普通模式仍未启用上传。"
        case .offlineSimulation:
            return "当前是离线模拟，仅演示生成图片的显示与状态变化；没有连接 ChatGPT。"
        case .available:
            return "在 Chrome 中打开要使用的 ChatGPT 对话，点击桌面边缘的截图即可附加。消息由你发送。"
        case .unsupportedBrowser:
            return "当前浏览器不受支持。截图保留，不会切换到其他浏览器或聊天。"
        case .targetUnavailable:
            return "当前 ChatGPT 草稿或附件入口不可用。截图保留，不会切换目标。"
        }
    }

    /// Disabled production and offline modes must not suggest that TCC is the
    /// reason they cannot upload, even if a stale permission observation exists.
    public var automationStatusText: String? {
        guard hasAutomationCapability else { return nil }
        switch snapshot.permission {
        case .notNeeded: return nil
        case .notChecked: return "尚未检查 Chrome 自动化权限。点“检查 Chrome 权限…”按 macOS 提示操作。"
        case .notRequested: return "点“检查 Chrome 权限…”，在 macOS 提示中允许 Riftlet 控制 Chrome。"
        case .granted: return "macOS 已允许 Riftlet 与 Chrome 通信。"
        case .denied: return "Chrome 自动化访问被拒绝。打开“系统设置 → 隐私与安全性 → 自动化”，在 Riftlet 下允许 Google Chrome，再回到这里点“重新检查”。"
        case .notRunning: return "Chrome 尚未运行。请打开 Google Chrome，再点“重新检查”。"
        case .browserUnavailable: return "没有找到受支持的 Google Chrome 应用。"
        case .unavailable: return "打开 Google Chrome，再点“重新检查”查看自动化权限。"
        }
    }

    public var chromeScriptInstructions: String? {
        guard hasAutomationCapability else { return nil }
        return Self.displayText(snapshot.permissionDetail, limit: 700)
    }

    public var permissionText: String? {
        guard let main = automationStatusText else { return nil }
        guard let detail = chromeScriptInstructions else { return main }
        return main + "\n" + detail
    }

    public var supportText: String { Self.displayText(snapshot.supportDescription, limit: 1_200) ?? "支持范围尚未声明；不会自动启用附件能力。" }

    public var storageText: String {
        switch snapshot.storage {
        case .notMeasured: return "私有存储用量尚未检查。隐藏、移除与归档都不等于删除图片。"
        case .measuring: return "正在检查私有存储用量；不会读取图片内容或删除文件。"
        case .measured(let bytes, let complete):
            let value = bytes <= UInt64(Int64.max)
                ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                : "\(bytes) 字节"
            return "私有存储\(complete ? "约" : "已统计至少") \(value)（文件逻辑大小）。\(complete ? "" : "部分项目暂无法统计。")不代表可释放磁盘空间。"
        case .insufficientSpace: return SetupIssue.insufficientSpace.text
        case .writeFailed: return SetupIssue.privateWriteFailed.text
        case .unavailable: return "私有存储用量暂无法确认；已有数据保留。"
        }
    }

    public var issueText: String? {
        guard let issue = snapshot.issue else { return nil }
        if !hasAutomationCapability && (issue == .permissionDenied || issue.isAttachmentConnectionIssue) {
            return nil
        }
        return issue.text
    }
    public var permissionActionTitle: String {
        snapshot.permission == .denied ? "打开自动化设置…" : "检查 Chrome 权限…"
    }
    public var canRequestPermission: Bool {
        guard hasAutomationCapability else { return false }
        switch snapshot.permission {
        case .notChecked, .notRequested, .denied, .unavailable: return true
        case .notNeeded, .granted, .notRunning, .browserUnavailable: return false
        }
    }
    public var hasSourceLocation: Bool { Self.displayText(snapshot.sourceLocation, limit: 4_096) != nil }
    public var hideActionTitle: String { snapshot.isHidden ? "显示桌面截图" : "隐藏桌面截图" }
    public var collectionActionTitle: String { snapshot.collection == .paused ? "继续收录" : "暂停收录" }

    private var hasAutomationCapability: Bool {
        snapshot.attachment == .syntheticWeb || snapshot.attachment == .systemScreenshotCandidate || snapshot.attachment == .available
    }

    /// Make the two permitted host strings fit a native local window. Strip
    /// control/bidi formatting characters; preserve ordinary Unicode and lines.
    private static func displayText(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let scalars = text.unicodeScalars.filter {
            $0 == "\n" || (!CharacterSet.controlCharacters.contains($0)
                && !CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}").contains($0))
        }
        let clean = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return clean.count <= limit ? clean : String(clean.prefix(limit)) + "…"
    }
}
