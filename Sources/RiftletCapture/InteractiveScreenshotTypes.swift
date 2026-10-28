import Foundation
import CoreGraphics

public enum ScreenshotMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case window, region, fullScreen
}

public struct InteractiveScreenshotOptions: Equatable, Sendable {
    public var delay: TimeInterval
    public var showPointer: Bool
    /// Passed unchanged to the host. This module never edits or re-encodes a capture.
    public var editAfter: Bool

    public init(delay: TimeInterval = 0, showPointer: Bool = false, editAfter: Bool = false) {
        self.delay = delay
        self.showPointer = showPointer
        self.editAfter = editAfter
    }

    var normalized: Self {
        Self(delay: delay.isFinite ? min(60, max(0, delay)) : 0,
             showPointer: showPointer, editAfter: editAfter)
    }
}

/// A newly produced, original file. This result does not grant attachment admission.
/// The durable importer must independently validate its source and original bytes.
public struct InteractiveScreenshotCapture: Sendable {
    public let sourceURL: URL
    public let pngData: Data
    public let mode: ScreenshotMode
    /// Frozen selected bounds in global AppKit points, with the y axis pointing up.
    /// Window PNGs may include the system's window shadow outside these bounds.
    public let rect: CGRect
    public let displayID: UInt32
    public let displayIDs: [UInt32]
    public let windowID: UInt32?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let options: InteractiveScreenshotOptions
    /// Read from the actual system output. Never inferred from a filename or command.
    /// False must not be relabelled as systemScreenshot to borrow candidate admission.
    public let hasSystemScreenshotMetadata: Bool
}

public enum InteractiveScreenshotState: Equatable, Sendable {
    case idle
    case selecting(ScreenshotMode)
    case countdown(Int)
    case capturing(ScreenshotMode)
}

public enum InteractiveScreenshotError: Error, Equatable, Sendable, LocalizedError {
    case screenRecordingPermissionRequired
    case noDisplay
    case invalidSelection
    case displayConfigurationChanged
    case selectedWindowUnavailable
    case captureToolUnavailable
    case captureFailed(Int32)
    case captureTimedOut
    case captureOverlayStillVisible
    case unsafeOutputDirectory
    case invalidOutput
    case imageTooLarge

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionRequired: return "请在系统设置中允许 Riftlet 录制屏幕，然后再次点击截图入口。"
        case .noDisplay: return "当前没有可用的屏幕。"
        case .invalidSelection: return "没有选中有效的截图区域。"
        case .displayConfigurationChanged: return "屏幕布局已改变，请重新选择截图目标。"
        case .selectedWindowUnavailable: return "刚才选择的窗口已不可用，请重新选择。"
        case .captureToolUnavailable: return "无法启动 macOS 截图工具。"
        case .captureFailed: return "macOS 未能完成这次截图，请检查屏幕录制权限后重试。"
        case .captureTimedOut: return "这次系统截图没有及时完成，已停止等待；请重新选择目标。"
        case .captureOverlayStillVisible: return "截图界面尚未完全隐藏，本次没有拍摄；请重试。"
        case .unsafeOutputDirectory: return "无法安全访问应用内截图保存目录。"
        case .invalidOutput: return "系统没有返回完整有效的 PNG 截图。"
        case .imageTooLarge: return "截图超出本地图片处理范围；原始文件未被改写。"
        }
    }
}

struct InteractiveScreenshotDisplay: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    let quartzFrame: CGRect
    let scale: CGFloat
}

struct InteractiveScreenshotWindow: Equatable, Sendable {
    let id: UInt32
    let ownerPID: Int32
    let rect: CGRect
}

struct InteractiveScreenshotTarget: Equatable, Sendable {
    let rect: CGRect
    let quartzRect: CGRect
    let displays: [InteractiveScreenshotDisplay]
    let window: InteractiveScreenshotWindow?
}

struct InteractiveScreenshotRequest: Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let mode: ScreenshotMode
    let options: InteractiveScreenshotOptions
    let target: InteractiveScreenshotTarget
}

/// Session identity is independent of mode/selection identity: changing mode must
/// not discard an already confirmed, asynchronously executing capture.
struct InteractiveScreenshotSession {
    private(set) var id = UUID()
    private(set) var isActive = false
    private(set) var mode: ScreenshotMode = .window
    private(set) var options = InteractiveScreenshotOptions()
    private(set) var selectionRevision: UInt64 = 0
    private(set) var pending: InteractiveScreenshotRequest?

    mutating func start(mode: ScreenshotMode, options: InteractiveScreenshotOptions) {
        id = UUID(); isActive = true; self.mode = mode; self.options = options.normalized
        selectionRevision &+= 1; pending = nil
    }

    mutating func updateMode(_ mode: ScreenshotMode) {
        self.mode = mode; selectionRevision &+= 1
    }

    mutating func updateOptions(_ options: InteractiveScreenshotOptions) {
        self.options = options.normalized
    }

    mutating func beginCapture(target: InteractiveScreenshotTarget) -> InteractiveScreenshotRequest? {
        guard isActive, pending == nil, InteractiveScreenshotGeometry.isUsable(target.rect),
              InteractiveScreenshotGeometry.isUsable(target.quartzRect), !target.displays.isEmpty,
              mode != .window || target.window != nil else { return nil }
        let request = InteractiveScreenshotRequest(id: UUID(), sessionID: id, mode: mode,
                                                   options: options, target: target)
        pending = request
        selectionRevision &+= 1
        return request
    }

    func owns(_ request: InteractiveScreenshotRequest) -> Bool {
        isActive && request.sessionID == id && pending?.id == request.id
    }

    mutating func complete(_ request: InteractiveScreenshotRequest) -> Bool {
        guard owns(request) else { return false }
        pending = nil
        return true
    }

    mutating func cancel() {
        isActive = false; id = UUID(); pending = nil; selectionRevision &+= 1
    }
}

enum InteractiveScreenshotGeometry {
    // AppKit and Quartz share x, but Quartz is relative to the main display's
    // top-left. Other displays may have negative x and/or y. Never multiply this
    // logical rectangle by backingScaleFactor; the system owns Retina encoding.
    static func quartzRect(fromAppKit rect: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitRect(fromQuartz rect: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite && rect.width >= 1 && rect.height >= 1
            && rect.width <= 50_000 && rect.height <= 50_000
            && abs(rect.minX) <= 1_000_000 && abs(rect.minY) <= 1_000_000
    }

    static func dragRect(from: CGPoint, to: CGPoint, displays: [InteractiveScreenshotDisplay]) -> CGRect? {
        guard from.x.isFinite, from.y.isFinite, to.x.isFinite, to.y.isFinite,
              let first = displays.first else { return nil }
        let desktop = displays.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(from.x - to.x), height: abs(from.y - to.y)).intersection(desktop)
        guard isUsable(rect), displays.contains(where: { $0.frame.intersects(rect) }) else { return nil }
        return rect
    }
}

enum InteractiveScreenshotCommand {
    static let executable = URL(fileURLWithPath: "/usr/sbin/screencapture")

    static func arguments(for request: InteractiveScreenshotRequest, outputURL: URL) throws -> [String] {
        guard outputURL.isFileURL, InteractiveScreenshotGeometry.isUsable(request.target.quartzRect) else {
            throw InteractiveScreenshotError.invalidSelection
        }
        var arguments = ["-x", "-t", "png"]
        if request.options.showPointer { arguments.append("-C") }
        if request.mode == .window {
            guard let window = request.target.window, window.id != 0 else {
                throw InteractiveScreenshotError.selectedWindowUnavailable
            }
            arguments += ["-l", String(window.id)]
        } else {
            // -R addresses exact global coordinates, unlike -D's display ordinal.
            // The system receives points and produces its native pixel dimensions.
            let rect = request.target.quartzRect.integral
            arguments += ["-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"]
        }
        arguments.append(outputURL.path)
        return arguments
    }
}
