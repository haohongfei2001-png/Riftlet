import AppKit
import RiftletCapture

/// Shared native navigation. This is presentation routing, not another preference store.
public enum SettingsPage: String, CaseIterable, Sendable {
    case general, display, capture, motion, history, help
    /// The two historical routes remain valid deep links into these four pages.
    public static let allCases: [SettingsPage] = [.general, .display, .capture, .help]
    public var destination: SettingsPage {
        switch self { case .history: return .capture; case .motion: return .display; default: return self }
    }
    public var title: String {
        switch self {
        case .motion, .display: return "桌面"
        case .capture, .history: return "截图"
        case .general: return "通用"
        case .help: return "帮助"
        }
    }
    public var symbol: String {
        switch self {
        case .motion, .display: return "rectangle.3.group"
        case .capture, .history: return "camera"
        case .general: return "gearshape"
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
public struct SettingsUpdaterPresentation: Equatable, Sendable {
    public var canCheck: Bool
    public var automaticChecks: Bool?
    public var availableVersion: String?
    public var failure: String?
    public init(canCheck: Bool, automaticChecks: Bool?, availableVersion: String?, failure: String?) {
        self.canCheck = canCheck; self.automaticChecks = automaticChecks
        self.availableVersion = availableVersion; self.failure = failure
    }
    public var checkTitle: String { availableVersion.map { "查看更新 " + $0 + "…" } ?? "检查更新…" }
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
public enum SettingsPreferenceDomain: String, CaseIterable, Sendable { case layout, archive }

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
    public var updater: SettingsUpdaterPresentation?
    public var chromeConnection: OnboardingChromeConnection = .unchecked
    public var preferenceRecovery: Set<SettingsPreferenceDomain> = []
    public var preferenceRecoveryFailure: SettingsPreferenceDomain?
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
    case recheck, openSource, chooseSourceAccess, requestAutomation, checkChromeConnection
    case openFilePrivacy, openScreenRecordingPrivacy
    case restorePreferredDisplay, checkStorage, revealDataFolder, reloadConfiguration, openConfiguration
    case restorePreference(SettingsPreferenceDomain)
    case checkForUpdates, automaticUpdateChecks(Bool), openDownloadWebsite
    case showLatest, showOldest, quit
}
public typealias SettingsProductActionHandler = @MainActor (SettingsProductAction) async -> Void
