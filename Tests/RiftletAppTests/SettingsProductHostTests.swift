import AppKit
import Foundation
import XCTest
import RiftletCapture
@testable import RiftletUI
@testable import RiftletApp

/// Tests the actual three-surface host with temporary appearance JSON and fake
/// persistence/login boundaries. The termination cancellation case orders only
/// its temporary native windows. No system login action or browser request is
/// executed, and no ordinary application root is used.
final class SettingsProductHostTests: XCTestCase {
    @MainActor private func fixture(rootExists: Bool = true) throws -> HostFixture {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer unavailable; native host projection NOT_RUN") }
        return try HostFixture(rootExists: rootExists)
    }

    @MainActor func testGeneralShowsOnlyProductNameAndMarketingVersion() throws {
        let fixture = try fixture()
        defer { fixture.close() }
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let expected = ["Riftlet", shortVersion].compactMap { $0 }.joined(separator: " ")
        XCTAssertEqual(fixture.host.snapshot.version, expected)
        XCTAssertEqual(fixture.host.center.labels["version"]?.stringValue, expected)
    }

    @MainActor func testUpdaterMenuSettingsAndReminderShareLiveState() async throws {
        let f = try fixture(); defer { f.close() }
        f.updater = .init(canCheck: true, automaticChecks: true, availableVersion: nil, failure: nil)
        f.publish()
        let check = try XCTUnwrap(f.host.center.controls["updates.check"] as? NSButton)
        let toggle = try XCTUnwrap(f.host.center.controls["updates.automatic"] as? NSSwitch)
        let website = try XCTUnwrap(f.host.center.controls["updates.website"] as? NSButton)
        let reminder = try XCTUnwrap(f.host.control.control(identifier: "control.update") as? NSButton)
        XCTAssertTrue(check.isEnabled)
        XCTAssertEqual(toggle.state, .on)
        XCTAssertEqual(check.title, "检查更新…")
        XCTAssertTrue(reminder.isHidden)
        let menu = f.host.control.contextMenu
        let item = try XCTUnwrap(menu.item(withTitle: check.title))
        let dispatched = (0..<4).map { expectation(description: "Update control dispatch " + String($0)) }
        f.onActionRecorded = { index in
            if dispatched.indices.contains(index) { dispatched[index].fulfill() }
        }
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        await fulfillment(of: [dispatched[0]], timeout: 3)
        check.performClick(nil)
        await fulfillment(of: [dispatched[1]], timeout: 3)
        toggle.state = .off
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle))
        await fulfillment(of: [dispatched[2]], timeout: 3)
        website.performClick(nil)
        await fulfillment(of: [dispatched[3]], timeout: 3)
        XCTAssertEqual(f.actions, ["check", "check", "disable", "website"])

        f.updater = .init(canCheck: true, automaticChecks: false, availableVersion: "1.0.2", failure: nil)
        f.publish()
        XCTAssertEqual(check.title, "查看更新 1.0.2…")
        XCTAssertEqual(toggle.state, .off)
        XCTAssertFalse(reminder.isHidden)
        XCTAssertNotNil(menu.item(withTitle: check.title))
        f.updater = .init(canCheck: false, automaticChecks: nil, availableVersion: nil, failure: "网络连接中断")
        f.publish()
        XCTAssertFalse(check.isEnabled)
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertTrue(website.isEnabled)
        XCTAssertEqual(f.host.center.labels["updates.failure"]?.stringValue, "更新未完成。网络连接中断")
    }

    @MainActor func testThreeNativeSurfacesReadOneModelWithoutSavingOrShowing() throws {
        let f = try fixture(); defer { f.close() }
        var settings = f.adapter.owner.settings
        XCTAssertEqual(settings.archiveAfterMinutes, 2)
        let archivePreset = try XCTUnwrap(f.host.center.controls["archive.preset"] as? NSPopUpButton)
        XCTAssertEqual(archivePreset.indexOfSelectedItem, 2)
        settings.configuration.placement = .rightBottom
        settings.configuration.preferredDisplayID = 2; settings.preferredDisplayID = 2
        XCTAssertNil(f.host.center.controls["paused"])
        let pause = try XCTUnwrap(f.host.control.control(identifier: "control.pause") as? NSSwitch)
        XCTAssertNil(f.host.center.controls["hidden"])
        let hideImages = try XCTUnwrap(f.host.control.control(identifier: "control.hide") as? NSSwitch)
        XCTAssertEqual(pause.accessibilityLabel(), "暂停收录")
        XCTAssertEqual(hideImages.accessibilityLabel(), "隐藏桌面截图")
        for (paused, hidden) in [(true, true), (false, true), (true, false), (false, false)] {
            f.update(settings: settings, paused: paused, hidden: hidden)
            XCTAssertEqual(f.host.snapshot.state, f.host.model.snapshot)
            XCTAssertEqual(f.host.center.product.state, f.host.model.snapshot)
            XCTAssertEqual(f.host.model.snapshot.owner.collectionPaused, paused)
            XCTAssertEqual(f.host.model.snapshot.owner.isHidden, hidden)
            XCTAssertEqual(pause.state, paused ? .on : .off)
            XCTAssertEqual(hideImages.state, hidden ? .on : .off)
        }
        let centerPosition = try XCTUnwrap(f.host.center.controls["placement"] as? NSPopUpButton)
        let guidePosition = try XCTUnwrap(f.host.onboarding.control(identifier: "onboarding.placement.rightBottom") as? NSButton)
        XCTAssertEqual(centerPosition.selectedItem?.identifier?.rawValue, "settings.center.placement.rightBottom")
        XCTAssertEqual(guidePosition.state, .on)
        let centerDisplay = try XCTUnwrap(f.host.center.controls["display"] as? NSPopUpButton)
        let guideDisplay = try XCTUnwrap(f.host.onboarding.control(identifier: "onboarding.display") as? NSPopUpButton)
        XCTAssertEqual(centerDisplay.titleOfSelectedItem, "Synthetic second")
        XCTAssertEqual(guideDisplay.titleOfSelectedItem, "Synthetic second")
        XCTAssertTrue(f.adapter.requests.isEmpty); XCTAssertTrue(f.actions.isEmpty)
        XCTAssertFalse(f.host.isVisible); XCTAssertFalse(f.host.control.isShown)
        XCTAssertEqual(f.loginService.registerCalls + f.loginService.unregisterCalls + f.loginService.openSettingsCalls, 0)
    }

    @MainActor func testHostAppearanceCreatesRealScopedJSONAndSystemRemovesOverride() async throws {
        let f = try fixture(); defer { f.close() }
        let url = f.root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Opening the host must not create a missing preference")
        await f.host.perform(.appearance(.dark))
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "appearance"])
        XCTAssertEqual(object["version"] as? Int, 1); XCTAssertEqual(object["appearance"] as? String, "dark")
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        XCTAssertEqual(f.host.snapshot.appearance.selection, .dark)
        XCTAssertEqual(f.host.center.product.appearance.selection, .dark)
        let reopened = ApplicationPresentationPreferences(url: url, applyAppearance: { _ in })
        XCTAssertEqual(reopened.selection, .dark)
        await f.host.perform(.appearance(.system))
        XCTAssertNil(NSApp.appearance)
        XCTAssertEqual(f.host.snapshot.appearance.applied, .system)
        XCTAssertTrue(f.adapter.requests.isEmpty, "Appearance never enters geometric or queue persistence")
    }

    @MainActor func testHistoryStyleSharesPreferenceAndPreservesDraftAndAllSettingsDomains() async throws {
        let f = try fixture(); defer { f.close() }
        let preference = f.host.historyDisplay
        let history = RiftHistoryController(mediaDirectory: f.root, onRestore: { _ in }, onRemove: { _ in },
            onReveal: { _ in }, displayStyle: preference.selection, onDisplayStyleChanged: { preference.select($0) })
        preference.onChange = { [weak host = f.host, weak history] style in
            history?.updateDisplayStyle(style)
            host?.refreshHistoryDisplayStyle()
        }
        func selector(in view: NSView?) -> NSSegmentedControl? {
            guard let view else { return nil }
            if view.identifier?.rawValue == "history.displayStyle" { return view as? NSSegmentedControl }
            return view.subviews.lazy.compactMap { selector(in: $0) }.first
        }
        let segments = try XCTUnwrap(selector(in: history.window.contentView))
        let action = try XCTUnwrap(segments.action)
        XCTAssertEqual(segments.selectedSegment, 0)
        XCTAssertNil(f.host.center.controls["history.displayStyle"])
        XCTAssertNotNil(f.host.center.controls["history.open"])
        f.host.model.setDraftText("88.1250", for: .outerInset)
        let draft = f.host.model.snapshot
        let configurationFiles = try FileManager.default.contentsOfDirectory(atPath: f.root.path)
        for (index, style) in HistoryDisplayStyle.allCases.enumerated() {
            segments.selectedSegment = index
            XCTAssertTrue(NSApp.sendAction(action, to: segments.target, from: segments))
            XCTAssertEqual(history.displayStyle, style)
            XCTAssertEqual(preference.selection, style)
            XCTAssertEqual(f.host.snapshot.historyDisplayStyle, style)
            XCTAssertEqual(f.host.center.product.historyDisplayStyle, style)
            XCTAssertEqual(segments.selectedSegment, index)
            XCTAssertEqual(f.host.model.snapshot, draft)
        }
        XCTAssertTrue(f.adapter.requests.isEmpty)
        XCTAssertTrue(f.actions.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.root.path), configurationFiles)
    }

    @MainActor func testHostAppearanceWriteFailureRetainsPendingChoiceAndRetriesSameGoal() async throws {
        let f = try fixture(rootExists: false); defer { f.close() }
        await f.host.perform(.appearance(.light))
        XCTAssertEqual(f.host.snapshot.appearance.selection, .system)
        XCTAssertEqual(f.host.snapshot.appearance.pending, .light)
        XCTAssertNotNil(f.host.snapshot.appearance.failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.path))
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
        await f.host.perform(.retryAppearance)
        XCTAssertEqual(f.host.snapshot.appearance.selection, .light)
        XCTAssertNil(f.host.snapshot.appearance.failure)
        XCTAssertNil(f.host.snapshot.appearance.pending)
        let reopened = ApplicationPresentationPreferences(url: f.root.appendingPathComponent(ApplicationPresentationPreferences.fileName), applyAppearance: { _ in })
        XCTAssertEqual(reopened.selection, .light)
    }

    @MainActor func testAppearanceSuccessDoesNotClearIndependentSettingsFailure() async throws {
        let f = try fixture(); defer { f.close() }
        f.adapter.failures = [.collection]
        await f.host.perform(.settings(.setCollectionPaused(true)))
        XCTAssertTrue(f.host.snapshot.state.owner.collectionPaused)
        XCTAssertNotNil(f.host.snapshot.state.domains[.collection]?.saveFailure)
        await f.host.perform(.appearance(.dark))
        XCTAssertNotNil(f.host.snapshot.state.domains[.collection]?.saveFailure)
        XCTAssertFalse(f.host.center.errorRows[.collection]!.isHidden)
        XCTAssertEqual(f.host.snapshot.appearance.selection, .dark)
    }

    @MainActor func testActualLoginReadbackAndThrownErrorAreProjectedIndependently() async throws {
        for next in [LoginItemStatus.enabled, .requiresApproval] {
            let f = try fixture(); defer { f.close() }
            f.loginService.registerNext = next
            f.loginService.registerError = NSError(domain: "SyntheticLoginTest", code: 51)
            await f.host.perform(.loginEnabled(true))
            let state = f.host.snapshot.login
            XCTAssertEqual(state.status, next == .enabled ? .enabled : .requiresApproval)
            XCTAssertTrue(state.switchValue)
            XCTAssertEqual(state.errorCode, 51)
            XCTAssertNil(state.failedTarget, "An already registered request must not be registered again")
            XCTAssertFalse(state.notConfirmed)
            XCTAssertTrue(f.host.center.labels["login.detail"]!.stringValue.contains("代码 51"))
            await f.host.perform(.retryLogin)
            XCTAssertEqual(f.loginService.registerCalls, 1)
            XCTAssertEqual(f.loginService.openSettingsCalls, 0)
            XCTAssertTrue(f.adapter.requests.isEmpty)
        }
    }

    @MainActor func testLoginFailedTargetRetriesSameDirectionAndReadRefreshDoesNotRegister() async throws {
        let f = try fixture(); defer { f.close() }
        f.loginService.registerNext = .notRegistered
        f.loginService.registerError = NSError(domain: "SyntheticLoginTest", code: 14)
        await f.host.perform(.loginEnabled(true))
        XCTAssertEqual(f.host.snapshot.login.failedTarget, true)
        XCTAssertEqual(f.host.snapshot.login.status, .notRegistered)
        XCTAssertTrue(f.host.snapshot.login.notConfirmed)
        for _ in 0..<3 { f.host.refreshSystemFacts() }
        XCTAssertEqual(f.loginService.registerCalls, 1)
        XCTAssertEqual(f.host.snapshot.login.errorCode, 14, "Read refresh does not erase a real command error")
        f.loginService.registerError = nil; f.loginService.registerNext = .enabled
        await f.host.perform(.retryLogin)
        XCTAssertEqual(f.loginService.registerCalls, 2)
        XCTAssertEqual(f.loginService.unregisterCalls, 0)
        XCTAssertNil(f.host.snapshot.login.failedTarget)
        XCTAssertEqual(f.host.snapshot.login.status, .enabled)
    }

    @MainActor func testBusyChangePublishesBeforeAwaitAndCrossDomainCanFinish() async throws {
        let f = try fixture(); defer { f.close() }
        let gate = HostSaveGate(); f.adapter.gate = gate; f.adapter.delayed = .layout
        f.host.model.setDraftText("81", for: .outerInset)
        let task = Task { @MainActor in await f.host.perform(.settings(.commitField(.outerInset, "81"))) }
        await fulfillment(of: [gate.entered], timeout: 2)
        XCTAssertTrue(f.host.snapshot.state.domains[.layout]!.isSaving)
        let slider = try XCTUnwrap(f.host.center.controls["slider.outerInset"] as? NSSlider)
        XCTAssertFalse(slider.isContinuous)
        await f.host.perform(.settings(.commitField(.outerInset, "81")))
        XCTAssertEqual(f.adapter.requests.filter { $0.intent.domain == .layout }.count, 1)
        let pause = try XCTUnwrap(f.host.control.control(identifier: "control.pause") as? NSSwitch)
        XCTAssertTrue(pause.isEnabled)
        f.host.model.setDraftText("92", for: .outerInset)
        await f.host.perform(.settings(.setHidden(true)))
        XCTAssertTrue(f.host.snapshot.state.owner.isHidden)
        XCTAssertTrue(f.host.snapshot.state.domains[.layout]!.isSaving)
        gate.release(); await task.value
        XCTAssertFalse(f.host.snapshot.state.domains[.layout]!.isSaving)
        XCTAssertEqual(f.host.model.text(for: .outerInset), "92")
        XCTAssertTrue(f.host.model.hasLayoutDraft)
        XCTAssertEqual(f.adapter.requests.filter { $0.intent.domain == .layout }.count, 1)
    }

    @MainActor func testOwnerRefreshDuringDraftKeepsUntouchedDisplayMetadataAndCompatibility() async throws {
        let f = try fixture(); defer { f.close() }
        f.host.model.setDraftText("88.1250", for: .outerInset)
        var settings = f.adapter.owner.settings
        settings.displays = [.init(id: 2, name: "Synthetic second")]
        settings.configuration.lineWidth = 1.5; settings.configuration.screenPadding = 29
        settings.configuration.numberGap = 13
        f.update(settings: settings, effectiveDisplay: 2)
        XCTAssertEqual(f.host.model.text(for: .outerInset), "88.1250")
        let popup = try XCTUnwrap(f.host.center.controls["display"] as? NSPopUpButton)
        XCTAssertEqual(popup.titleOfSelectedItem, "已选显示器（未连接）")
        await f.host.perform(.settings(.commitField(.outerInset, "88.1250")))
        let actual = f.host.snapshot.state.owner.settings.configuration
        XCTAssertEqual(actual.outerInset, 88.125)
        XCTAssertEqual(actual.preferredDisplayID, 1)
        XCTAssertEqual(actual.lineWidth, 1.5); XCTAssertEqual(actual.screenPadding, 29); XCTAssertEqual(actual.numberGap, 13)
        XCTAssertEqual(f.adapter.requests.count, 1)
    }

    @MainActor func testExternalActionsPassThroughExactlyOnceAndRefreshNeverEmitsThem() async throws {
        let f = try fixture(); defer { f.close() }
        f.host.refreshSystemFacts(); f.publish(); f.publish()
        XCTAssertTrue(f.actions.isEmpty)
        await f.host.perform(.clearVisible)
        await f.host.perform(.openHistory)
        await f.host.perform(.recheck)
        XCTAssertEqual(f.actions, ["clearVisible", "openHistory", "recheck"])
        XCTAssertTrue(f.adapter.requests.isEmpty)
        XCTAssertEqual(f.loginService.openSettingsCalls, 0)
        XCTAssertFalse(f.host.isVisible)
    }

    @MainActor func testClosingHostDetachesPublishCallbacksWithoutApplyingDrafts() throws {
        let f = try fixture(); defer { f.close() }
        f.host.model.setDraftText("95", for: .outerInset)
        let last = f.host.center.product.revision
        f.host.close()
        f.host.model.setDraftText("96", for: .outerInset)
        XCTAssertNil(f.host.model.onChange)
        XCTAssertNil(f.host.login.onChange)
        XCTAssertEqual(f.host.center.product.revision, last)
        XCTAssertTrue(f.adapter.requests.isEmpty)
    }

    @MainActor func testTerminationPreparationBlocksNewActionsAndShowUntilCancelled() async throws {
        let f = try fixture(); defer { f.close() }
        let original = f.host.model.snapshot.owner
        let refreshCalls = f.refreshCalls
        let appearanceURL = f.root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        f.host.beginTerminationPreparation(); f.host.beginTerminationPreparation()
        XCTAssertTrue(f.host.isPreparingForTermination)
        let blocked: [SettingsProductAction] = [.settings(.setCollectionPaused(true)), .settings(.setHidden(true)),
            .appearance(.dark), .retryAppearance, .loginEnabled(true), .retryLogin, .openLoginSettings,
            .clearVisible, .openHistory, .recheck, .openSettings(.display), .openOnboarding, .capture]
        for action in blocked { await f.host.perform(action) }
        f.host.show(page: .display)
        XCTAssertFalse(f.host.showOnboarding())
        f.publish(); f.host.refreshSystemFacts()
        XCTAssertTrue(f.host.isPreparingForTermination, "Read-only owner refresh cannot release the termination lock")
        XCTAssertEqual(f.host.model.snapshot.owner, original)
        XCTAssertTrue(f.adapter.requests.isEmpty); XCTAssertTrue(f.actions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appearanceURL.path))
        XCTAssertEqual(f.loginService.registerCalls + f.loginService.unregisterCalls + f.loginService.openSettingsCalls, 0)
        XCTAssertEqual(f.refreshCalls, refreshCalls)
        XCTAssertFalse(f.host.isVisible); XCTAssertFalse(f.host.control.isShown)
        XCTAssertFalse(try XCTUnwrap(f.item.button).isEnabled)

        f.host.cancelTerminationPreparation(); f.host.cancelTerminationPreparation()
        XCTAssertFalse(f.host.isPreparingForTermination)
        XCTAssertTrue(try XCTUnwrap(f.item.button).isEnabled)
        await f.host.perform(.settings(.setCollectionPaused(true)))
        await f.host.perform(.appearance(.dark))
        await f.host.perform(.loginEnabled(true))
        await f.host.perform(.openHistory)
        XCTAssertTrue(f.host.model.snapshot.owner.collectionPaused)
        XCTAssertEqual(f.host.snapshot.appearance.selection, .dark)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appearanceURL.path))
        XCTAssertEqual(f.loginService.registerCalls, 1)
        XCTAssertEqual(f.actions, ["openHistory"])
        f.host.show(page: .display)
        XCTAssertTrue(f.host.center.isVisible)
        XCTAssertEqual(f.host.center.selectedPage, .display)
        XCTAssertTrue(f.host.showOnboarding())
        f.host.beginTerminationPreparation()
        XCTAssertFalse(f.host.isVisible, "Beginning termination closes both native windows synchronously")
        XCTAssertFalse(f.host.control.isShown)
    }

    @MainActor func testTerminationPreparationDoesNotCancelAlreadyStartedOwnerSave() async throws {
        let f = try fixture(); defer { f.close() }
        let gate = HostSaveGate(); f.adapter.gate = gate; f.adapter.delayed = .collection
        let task = Task { @MainActor in await f.host.perform(.settings(.setCollectionPaused(true))) }
        await fulfillment(of: [gate.entered], timeout: 2)
        XCTAssertTrue(f.host.model.snapshot.domains[.collection]!.isSaving)
        f.host.beginTerminationPreparation()
        await f.host.perform(.settings(.setHidden(true)))
        gate.release(); await task.value
        XCTAssertTrue(f.host.model.snapshot.owner.collectionPaused)
        XCTAssertFalse(f.host.model.snapshot.owner.isHidden)
        XCTAssertFalse(f.host.model.snapshot.domains[.collection]!.isSaving)
        XCTAssertEqual(f.adapter.requests.map(\.intent), [.collectionPaused(true)])
        f.host.cancelTerminationPreparation()
        await f.host.perform(.settings(.setHidden(true)))
        XCTAssertEqual(f.adapter.requests.map(\.intent), [.collectionPaused(true), .hidden(true)])
    }
}

@MainActor
private final class HostFixture {
    let defaultsSuite = "com.riftlet.tests.settings-host." + UUID().uuidString
    let base: URL
    let root: URL
    let oldAppearance: NSAppearance?
    let item: NSStatusItem
    let adapter: HostSettingsAdapter
    let loginService = HostLoginService()
    var host: SettingsProductHost!
    var actions: [String] = [] { didSet { onActionRecorded?(actions.count - 1) } }
    var onActionRecorded: ((Int) -> Void)?
    var updater: SettingsUpdaterPresentation?
    var refreshCalls = 0
    var closed = false
    init(rootExists: Bool) throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("settings-host-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        root = base.appendingPathComponent("application-root")
        if rootExists { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false) }
        oldAppearance = NSApp.appearance
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        adapter = HostSettingsAdapter()
        let login = LoginItemPreferences(service: loginService)
        host = try SettingsProductHost(root: root, mode: .settingsReview, statusItem: item,
            owner: adapter.owner, adapter: adapter, login: login,
            historyDisplay: HistoryDisplayPreferences(defaults: UserDefaults(suiteName: defaultsSuite)!),
            updaterPresentation: { [weak self] in self?.updater },
            onRefresh: { [weak self] in self?.refreshCalls += 1 },
            onAction: { [weak self] action in
                switch action {
                case .checkForUpdates: self?.actions.append("check")
                case .automaticUpdateChecks(let enabled): self?.actions.append(enabled ? "enable" : "disable")
                case .openDownloadWebsite: self?.actions.append("website")
                case .clearVisible: self?.actions.append("clearVisible")
                case .openHistory: self?.actions.append("openHistory")
                case .recheck: self?.actions.append("recheck")
                default: self?.actions.append("other")
                }
            })
        publish()
    }
    func update(settings: RiftSettingsSnapshot, paused: Bool? = nil, hidden: Bool? = nil, effectiveDisplay: UInt32? = nil) {
        let old = adapter.owner
        adapter.owner = .init(revision: old.revision + 1, settings: settings,
            collectionPaused: paused ?? old.collectionPaused, isHidden: hidden ?? old.isHidden,
            mainDisplayID: old.mainDisplayID, effectiveDisplayID: effectiveDisplay ?? old.effectiveDisplayID)
        publish()
    }
    func publish() {
        var capabilities = SettingsCapabilities()
        capabilities.initialized = true; capabilities.canEditPreferences = true
        capabilities.canChangeCollection = true; capabilities.canChangeVisibility = true
        capabilities.canOpenHistory = true; capabilities.canClearVisible = true
        let setup = SetupSnapshot(source: .accessible, collection: adapter.owner.collectionPaused ? .paused : .collecting,
            isHidden: adapter.owner.isHidden, visibleCount: 2, attachment: .productionDisabled, storage: .notMeasured)
        host.update(owner: adapter.owner, setup: setup, capabilities: capabilities, configurationDeferred: false)
    }
    func close() {
        guard !closed else { return }; closed = true
        host.close(); NSStatusBar.system.removeStatusItem(item); NSApp.appearance = oldAppearance
        adapter.gate?.release()
        UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: base)
    }
}

@MainActor
private final class HostSettingsAdapter: SettingsPersistenceAdapter {
    var owner: SettingsOwnerSnapshot
    var requests: [SettingsSaveRequest] = []
    var failures: Set<SettingsDomain> = []
    var delayed: SettingsDomain?
    var gate: HostSaveGate?
    init() {
        var config = RiftConfiguration(); config.preferredDisplayID = 1
        owner = .init(revision: 1, settings: .init(entryAvailable: true,
            displays: [.init(id: 1, name: "Synthetic first"), .init(id: 2, name: "Synthetic second")],
            preferredDisplayID: 1, configuration: config),
            collectionPaused: false, isHidden: false, mainDisplayID: 1, effectiveDisplayID: 1)
    }
    func save(_ request: SettingsSaveRequest) async -> SettingsSaveOutcome {
        requests.append(request)
        if request.intent.domain == delayed { await gate?.suspend() }
        var settings = owner.settings, paused = owner.collectionPaused, hidden = owner.isHidden
        let failed = failures.contains(request.intent.domain)
        switch request.intent {
        case .collectionPaused(let value): if value || !failed { paused = value }
        case .hidden(let value): if value || !failed { hidden = value }
        case .entryEnabled(let value): if !value || !failed { settings.entryEnabled = value }; settings.capturePreferencesSaveFailed = failed
        case .captureMode(let value): if !failed { settings.defaultCaptureMode = value }
        case .arrival(let value): if !failed { settings.arrivalMode = value; settings.hasArrivalSelection = true }
        case .archiveMinutes(let value): if !failed { settings.archiveAfterMinutes = value }
        case .layout, .placement, .display, .desktopForm, .windChimeArrangement, .trayTheme, .trayFavorite:
            if !failed, let config = request.configuration { settings.configuration = config; settings.preferredDisplayID = config.preferredDisplayID }
        }
        owner = .init(revision: owner.revision + 1, settings: settings, collectionPaused: paused, isHidden: hidden,
            mainDisplayID: owner.mainDisplayID, effectiveDisplayID: owner.effectiveDisplayID)
        return failed ? .unconfirmed(owner, .writeUnconfirmed) : .confirmed(owner)
    }
}

@MainActor
private final class HostSaveGate {
    let entered = XCTestExpectation(description: "Actual host owner save is awaiting its receipt")
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func suspend() async {
        if released { return }
        await withCheckedContinuation { continuation = $0; entered.fulfill() }
    }
    func release() { released = true; let value = continuation; continuation = nil; value?.resume() }
}

@MainActor
private final class HostLoginService: LoginItemService {
    var value = LoginItemStatus.notRegistered
    var registerNext = LoginItemStatus.enabled
    var registerError: Error?
    var registerCalls = 0, unregisterCalls = 0, openSettingsCalls = 0
    var status: LoginItemStatus { value }
    func register() throws { registerCalls += 1; value = registerNext; if let registerError { throw registerError } }
    func unregister() async throws { unregisterCalls += 1; value = .notRegistered }
    func openSystemSettings() { openSettingsCalls += 1 }
}
