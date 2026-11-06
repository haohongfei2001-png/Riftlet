import AppKit
import RiftletCapture

/// Shared native navigation. This is presentation routing, not another preference store.
public enum SettingsPage: String, CaseIterable, Sendable {
    case general, display, capture, motion, history, help
    public var title: String {
        switch self {
        case .general: return "通用"
        case .display: return "位置与显示"
        case .capture: return "截图"
        case .motion: return "动效"
        case .history: return "历史与存储"
        case .help: return "权限与帮助"
        }
    }
    public var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .display: return "display"
        case .capture: return "camera.viewfinder"
        case .motion: return "sparkles"
        case .history: return "clock.arrow.circlepath"
        case .help: return "questionmark.circle"
        }
    }
}

public enum SettingsAppearanceChoice: String, CaseIterable, Sendable {
    case system, light, dark
    public var title: String { self == .system ? "跟随系统" : self == .light ? "浅色" : "深色" }
}
public struct SettingsAppearancePresentation: Equatable, Sendable {
    public var selection: SettingsAppearanceChoice = .system
    public var applied: SettingsAppearanceChoice?
    public var pending: SettingsAppearanceChoice?
    public var unreadable = false
    public var failure: String?
    public var available = false
    public init() {}
}
public enum SettingsLoginStatus: Equatable, Sendable {
    case notRegistered, enabled, requiresApproval, notFound, unknown
}
public struct SettingsLoginPresentation: Equatable, Sendable {
    public var status: SettingsLoginStatus?
    public var available = false
    public var unavailableReason: String?
    public var inFlightTarget: Bool?
    public var failedTarget: Bool?
    public var errorCode: Int?
    public var notConfirmed = false
    public init() {}
    public var switchValue: Bool { status == .enabled || status == .requiresApproval }
    public var isBusy: Bool { inFlightTarget != nil }
}
public struct SettingsCapabilities: Equatable, Sendable {
    public var initialized = false
    public var canChangeCollection = false
    public var canChangeVisibility = false
    public var canCapture = false
    public var canRecheck = false
    public var canRequestAutomation = false
    public var canChooseSource = false
    public var canOpenHistory = false
    public var canClearVisible = false
    public var canCheckStorage = false
    public var canEditPreferences = false
    public var canOpenConfiguration = false
    public init() {}
}
public struct SettingsAccessibility: Equatable, Sendable {
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false
    public init(reduceMotion: Bool = false, reduceTransparency: Bool = false, increaseContrast: Bool = false) {
        self.reduceMotion = reduceMotion; self.reduceTransparency = reduceTransparency; self.increaseContrast = increaseContrast
    }
}
public enum SettingsScreenRecording: Equatable, Sendable { case notChecked, granted, notGranted, unavailable }

/// Main composes one coherent projection for all native surfaces. No source/target,
/// upload or persistence authority is carried into a view.
public struct SettingsProductSnapshot: Equatable, Sendable {
    public var revision: UInt64
    public var setup: SetupSnapshot
    public var state: SettingsStateSnapshot
    public var appearance: SettingsAppearancePresentation = .init()
    public var login: SettingsLoginPresentation = .init()
    public var historyDisplayStyle: HistoryDisplayStyle = .current
    public var capabilities: SettingsCapabilities = .init()
    public var accessibility: SettingsAccessibility = .init()
    public var screenRecording: SettingsScreenRecording = .notChecked
    public var version: String = ""
    public var configurationDeferred = false
    public var reviewEnvironment = false
    public init(revision: UInt64, setup: SetupSnapshot, state: SettingsStateSnapshot) {
        self.revision = revision; self.setup = setup; self.state = state
    }
}

/// Each invocation is a deliberate action. A view must never send an action from
/// its update callback. Existing host owners remain responsible for all effects.
public enum SettingsProductAction: Sendable {
    case settings(SettingsCommand)
    case appearance(SettingsAppearanceChoice), retryAppearance
    case historyDisplayStyle(HistoryDisplayStyle)
    case loginEnabled(Bool), retryLogin, openLoginSettings
    case openSettings(SettingsPage), openOnboarding, finishOnboarding
    case capture, openHistory, openFeedback, clearVisible
    case recheck, openSource, chooseSourceAccess, requestAutomation
    case openFilePrivacy, openScreenRecordingPrivacy
    case restorePreferredDisplay, checkStorage, reloadConfiguration, openConfiguration
    case showLatest, showOldest, quit
}
public typealias SettingsProductActionHandler = @MainActor (SettingsProductAction) async -> Void
