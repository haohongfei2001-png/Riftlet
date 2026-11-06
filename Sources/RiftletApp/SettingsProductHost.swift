import AppKit
import RiftletUI

/// The three native surfaces share one presentation model and the existing
/// persistence owners. This host never captures a target or performs an upload.
@MainActor
final class SettingsProductHost {
    let model: SettingsStateModel
    private(set) var center: RiftSettingsCenterController!
    private(set) var control: RiftControlCenterController!
    private(set) var onboarding: RiftOnboardingController!
    let appearance: ApplicationPresentationPreferences
    let login: LoginItemPreferences
    private var setup = SetupSnapshot()
    private var capabilities = SettingsCapabilities()
    private var deferred = false
    private var revision: UInt64 = 0
    private let onAction: SettingsProductActionHandler
    private let onRefresh: @MainActor () -> Void
    private let reviewEnvironment: Bool
    private var accessibilityObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private(set) var isPreparingForTermination = false

    init(root: URL, mode: ApplicationMode, statusItem: NSStatusItem,
         owner: SettingsOwnerSnapshot, adapter: any SettingsPersistenceAdapter,
         login: LoginItemPreferences? = nil,
         onRefresh: @escaping @MainActor () -> Void,
         onAction: @escaping SettingsProductActionHandler) throws {
        model = try SettingsStateModel(owner: owner, adapter: adapter)
        reviewEnvironment = mode == .settingsReview || OrdinaryCaptureConfiguration.isInternalAcceptance
        self.onAction = onAction; self.onRefresh = onRefresh
        self.login = login ?? LoginItemPreferences.live(mode: mode)
        appearance = ApplicationPresentationPreferences(
            url: root.appendingPathComponent(ApplicationPresentationPreferences.fileName),
            applyAppearance: { NSApp.appearance = $0 })
        // Reading an existing preference does not rewrite or migrate its file.
        try? appearance.applyAcceptedSelection()
        center = RiftSettingsCenterController(model: model, onAction: { [weak self] in await self?.perform($0) })
        control = RiftControlCenterController(statusItem: statusItem, onAction: { [weak self] in await self?.perform($0) })
        onboarding = RiftOnboardingController(onAction: { [weak self] in await self?.perform($0) })
        model.onChange = { [weak self] _ in self?.publish() }
        self.login.onChange = { [weak self] _ in self?.publish() }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.publish() }
            }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onRefresh() }
            }
        self.login.refresh()
        publish()
    }

    var isVisible: Bool { center.isVisible || onboarding.isVisible }

    func update(owner: SettingsOwnerSnapshot, setup: SetupSnapshot,
                capabilities: SettingsCapabilities, configurationDeferred: Bool) {
        self.setup = setup; self.capabilities = capabilities; deferred = configurationDeferred
        if !model.receive(owner) { publish() }
    }

    var snapshot: SettingsProductSnapshot {
        var result = SettingsProductSnapshot(revision: revision, setup: setup, state: model.snapshot)
        result.capabilities = capabilities
        result.configurationDeferred = deferred
        let workspace = NSWorkspace.shared
        result.accessibility = .init(reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
        result.appearance.selection = .init(rawValue: appearance.selection.rawValue) ?? .system
        result.appearance.applied = appearance.appliedSelection.flatMap { .init(rawValue: $0.rawValue) }
        result.appearance.pending = appearance.pendingSelection.flatMap { .init(rawValue: $0.rawValue) }
        result.appearance.unreadable = appearance.loadState == .unreadable
        result.appearance.failure = appearance.failure.map { $0 == .preparationFailed ? "暂时无法应用这个外观。" : "外观未能保存，请重试。" }
        result.appearance.available = true
        let fact = login.snapshot
        result.login.available = fact.availability == .available
        if !result.login.available { result.login.unavailableReason = "此运行环境不更改系统登录项。请在正式安装的 Riftlet 中设置。" }
        result.login.status = fact.status.map {
            switch $0 {
            case .enabled: return .enabled
            case .notRegistered: return .notRegistered
            case .requiresApproval: return .requiresApproval
            case .notFound: return .notFound
            case .unknown: return .unknown
            }
        }
        result.login.inFlightTarget = fact.inFlightTarget
        if let last = fact.lastCommand {
            result.login.errorCode = last.serviceError
            result.login.notConfirmed = last.disposition == .notConfirmed
            if last.disposition == .notConfirmed || last.disposition == .unavailable {
                result.login.failedTarget = last.target
            }
        }
        // A read-only preflight; never presents the macOS permission dialog.
        result.screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let label = Bundle.main.object(forInfoDictionaryKey: "RiftletVersionLabel") as? String
        result.version = (label.map { $0 + " · " } ?? "") + (build.map { "\(version)（\($0)）" } ?? version)
        result.reviewEnvironment = reviewEnvironment
        return result
    }

    private func publish() {
        revision += 1
        let value = snapshot
        center?.update(value); control?.update(value); onboarding?.update(value)
    }

    func show(page: SettingsPage = .general) {
        guard !isPreparingForTermination else { return }
        control.close(); login.refresh(); onRefresh(); center.show(page: page)
    }

    @discardableResult func showOnboarding() -> Bool {
        guard !isPreparingForTermination else { return false }
        control.close(); onRefresh(); return onboarding.show()
    }

    /// Called synchronously after the settings close decision is accepted and
    /// before Feedback's asynchronous termination preparation. Existing owner
    /// writes are not cancelled; new UI actions cannot enter during that gap.
    func beginTerminationPreparation() {
        guard !isPreparingForTermination else { return }
        isPreparingForTermination = true
        control.setInteractionSuspended(true)
        center.closeForTeardown()
        onboarding.closeForTeardown()
    }

    func cancelTerminationPreparation() {
        guard isPreparingForTermination else { return }
        isPreparingForTermination = false
        control.setInteractionSuspended(false)
    }

    func refreshSystemFacts() { login.refresh(); publish() }

    func perform(_ action: SettingsProductAction) async {
        guard !isPreparingForTermination else { return }
        switch action {
        case .settings(let command): _ = await model.perform(command)
        case .appearance(let choice):
            if let value = ApplicationAppearanceChoice(rawValue: choice.rawValue) { try? appearance.select(value) }
            publish()
        case .retryAppearance: _ = try? appearance.retry(); publish()
        case .loginEnabled(let target): _ = await login.setEnabled(target); publish()
        case .retryLogin:
            if let target = snapshot.login.failedTarget { _ = await login.setEnabled(target); publish() }
        case .openLoginSettings: control.close(); _ = login.openSystemSettings()
        case .finishOnboarding: onboarding.closeForTeardown()
        default: await onAction(action)
        }
    }

    func close() {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        accessibilityObserver = nil; screenObserver = nil
        model.onChange = nil; login.onChange = nil
        control.close(); center.closeForTeardown(); onboarding.closeForTeardown()
    }
}
