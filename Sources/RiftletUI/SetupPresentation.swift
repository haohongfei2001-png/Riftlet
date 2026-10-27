import Foundation

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

/// Closed, local-only explanations. The presentation never displays an Error's
/// description, file contents, browser identity, URL, or arbitrary remote text.
public enum SetupIssue: Equatable, Sendable {
    case sourceAccess, unsupportedFormat, unsupportedSize, invalidImage
    case insufficientSpace, privateWriteFailed, storageUnavailable
    case unsupportedBrowser, targetUnavailable, permissionDenied, imageUnavailable
    case initializationFailed, configurationUnavailable
    case visibilityPreferenceUnsaved, collectionPreferenceUnsaved
    case attachmentFormat, attachmentBytes, attachmentPixels

    public var text: String {
        switch self {
        case .attachmentFormat:
            return "截图已保存在本机。当前真实截图候选只接收原样 PNG；本图未上传、未转换，原文件与私有副本保留。"
        case .attachmentBytes:
            return "截图已保存在本机，但超过当前网页候选的 8 MiB 传输上限。本图未上传、未压缩，原文件与私有副本保留。"
        case .attachmentPixels:
            return "截图已保存在本机，但超过当前网页候选的 16,777,216 像素上限。本图未上传、未缩放，原文件与私有副本保留。"
        case .sourceAccess:
            return "无法读取截图保存位置。请确认文件夹仍存在，在系统设置「隐私与安全性 → 文件与文件夹」中检查 Riftlet，或允许访问当前截图位置；原截图没有被删除。"
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
            return "当前浏览器不在已支持范围内。截图保留，不会自动切换窗口或寻找其他聊天。"
        case .targetUnavailable:
            return "当前没有唯一、可验证的 ChatGPT 附件目标。截图保留，不会上传到其他窗口。"
        case .permissionDenied:
            return "Chrome 自动化访问被拒绝。请在系统设置的「隐私与安全性 → 自动化」中检查 Riftlet，再重新检查。"
        case .imageUnavailable:
            return "这张截图的私有副本暂不可用。没有重新附加，也没有删除系统原图。"
        case .initializationFailed:
            return "Riftlet 未能完成启动。已有数据保留；请检查磁盘与文件访问权限，再重新打开应用。"
        case .configurationUnavailable:
            return "部分本地设置暂不可用。已有截图与上传记录保留；未通过删除数据重置状态。"
        case .visibilityPreferenceUnsaved:
            return "显示偏好未能保存；本次运行保持隐藏，重启可能恢复之前的设置。请检查磁盘可写后重新操作；图片仍保留。"
        case .collectionPreferenceUnsaved:
            return "收录开关未能保存；本次运行仍暂停收录，重启可能恢复之前的设置。请检查磁盘可写后重新操作；已有图片仍保留。"
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

    public init(sourceLocation: String? = nil, source: SetupSourceState = .checking,
                collection: SetupCollectionState = .starting, isHidden: Bool = false,
                visibleCount: Int = 0, pendingCount: Int = 0,
                attachment: SetupAttachmentState = .productionDisabled,
                permission: SetupPermissionState = .notNeeded, permissionDetail: String? = nil,
                storage: SetupStorageState = .notMeasured, issue: SetupIssue? = nil,
                supportDescription: String = "", isChecking: Bool = false) {
        self.sourceLocation = sourceLocation; self.source = source; self.collection = collection
        self.isHidden = isHidden; self.visibleCount = max(0, visibleCount); self.pendingCount = max(0, pendingCount)
        self.attachment = attachment; self.permission = permission; self.permissionDetail = permissionDetail
        self.storage = storage; self.issue = issue; self.supportDescription = supportDescription
        self.isChecking = isChecking
    }
}

public struct SetupPresentation: Equatable, Sendable {
    public let snapshot: SetupSnapshot
    public init(snapshot: SetupSnapshot) { self.snapshot = snapshot }

    public var sourceText: String {
        switch snapshot.source {
        case .checking: return "正在检查系统截图保存位置。"
        case .notChecked: return "尚未检查截图位置的访问状态；暂停收录时不会据此判断权限被拒绝。"
        case .notApplicable: return "此模式不读取系统截图文件夹。"
        case .accessible: return "截图位置可读取。"
        case .unavailable: return "截图位置目前不可访问；请检查文件夹与访问权限。"
        case .notConfigured: return "尚未找到可用的文件夹。请在系统截图工具栏的「选项」中确认保存位置。"
        }
    }

    public var sourcePath: String {
        Self.displayText(snapshot.sourceLocation, limit: 4_096) ?? "尚未确定位置"
    }

    public var collectionText: String {
        switch snapshot.collection {
        case .starting: return "收录正在准备；尚不能确认新截图已保存。"
        case .collecting: return "正在收录新截图，并保留本机私有副本。"
        case .waitingForSource: return "收录开关已开启；当前保存位置尚未确认可读，请检查来源。已有图片保留。"
        case .paused: return "收录已暂停；已有截图保留。隐藏裂缝不会自动暂停收录。"
        case .stopped: return "当前未收录新截图；已有截图保留。"
        }
    }

    public var riftText: String {
        if snapshot.isHidden {
            return "裂缝已隐藏（\(snapshot.visibleCount) 张待显示）。隐藏只影响显示，不删除图片，也不改变收录开关。"
        }
        if snapshot.visibleCount == 0 { return "没有可见截图，因此屏幕上没有裂缝。" }
        return "裂缝中有 \(snapshot.visibleCount) 张截图。"
    }

    public var pendingText: String? {
        guard snapshot.pendingCount > 0 else { return nil }
        return "\(snapshot.pendingCount) 张结果待核实 · 图片仍保存在本机，不会自动再次附加。可在内部历史查看。"
    }

    public var attachmentText: String {
        switch snapshot.attachment {
        case .productionDisabled:
            return "此工程版本尚未启用真实截图附加。截图可以在本机收录与查看；授权不会开启尚未验收的能力。"
        case .syntheticWeb:
            return "当前是独立 Web 验收模式，仅允许生成的测试图片。不会收录或上传真实截图，也不会发送聊天消息。"
        case .systemScreenshotCandidate:
            return "真实截图内部候选：点击会尝试把原样 PNG 输入当前 ChatGPT 草稿。开始、成功与安全重试尚未准入；只保存待审观察，不自动吞噬、不宣布成功、不重传，不发送消息。普通模式仍未启用上传。"
        case .offlineSimulation:
            return "当前是离线模拟，仅演示生成图片的显示与状态变化；没有连接 ChatGPT。"
        case .available:
            return "仅向当前唯一、受支持的 ChatGPT 草稿附加图片；不会替你发送消息。"
        case .unsupportedBrowser:
            return "当前浏览器不受支持。截图保留，不会切换到其他浏览器或聊天。"
        case .targetUnavailable:
            return "当前 ChatGPT 草稿或附件入口不可用。截图保留，不会切换目标。"
        }
    }

    /// Disabled production and offline modes must not suggest that TCC is the
    /// reason they cannot upload, even if a stale permission observation exists.
    public var permissionText: String? {
        guard hasAutomationCapability else { return nil }
        let main: String
        switch snapshot.permission {
        case .notNeeded: return nil
        case .notChecked: main = "尚未检查 Chrome 自动化权限。只有主动操作时才会请求。"
        case .notRequested: main = "需要 Chrome 自动化访问；可按下方按钮请求 macOS 授权。"
        case .granted: main = "macOS 已允许 Chrome 自动化访问；这不代表页面附件能力已经通过验证。"
        case .denied: main = "Chrome 自动化访问被拒绝。可打开系统设置恢复，再重新检查。"
        case .notRunning: main = "Chrome 尚未运行。请自行打开 Chrome，再重新检查；Riftlet 不会替你切换窗口。"
        case .browserUnavailable: main = "没有找到受支持的 Chrome 应用。"
        case .unavailable: main = "暂时无法确定 Chrome 自动化权限。请重新检查；未据此输入附件。"
        }
        guard let detail = Self.displayText(snapshot.permissionDetail, limit: 700) else { return main }
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
        if !hasAutomationCapability {
            switch issue {
            case .permissionDenied, .unsupportedBrowser, .targetUnavailable: return nil
            default: break
            }
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
    public var hideActionTitle: String { snapshot.isHidden ? "显示裂缝" : "隐藏裂缝" }
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
