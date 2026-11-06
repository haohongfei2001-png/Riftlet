import AppKit
import XCTest
@testable import RiftletUI

final class RiftControlCenterControllerTests: XCTestCase {
    @MainActor private func fixture(revision: UInt64 = 1, paused: Bool = false, hidden: Bool = false,
                                    source: SetupSourceState = .accessible,
                                    collection: SetupCollectionState = .collecting,
                                    issue: SetupIssue? = nil) -> SettingsProductSnapshot {
        let settings = RiftSettingsSnapshot(entryAvailable: true, entryEnabled: true,
            displays: [.init(id: 1, name: "合成显示器", uuid: "synthetic-display")])
        let model = try! SettingsStateModel(owner: .init(revision: revision, settings: settings,
            collectionPaused: paused, isHidden: hidden, mainDisplayID: 1),
            adapter: SettingsPersistenceClosures { _ in .unconfirmed(nil, .ownerUnavailable) })
        var value = SettingsProductSnapshot(revision: revision,
            setup: .init(source: source, collection: collection, isHidden: hidden, visibleCount: 3,
                         attachment: .available, permission: .granted, issue: issue), state: model.snapshot)
        value.capabilities.initialized = true
        value.capabilities.canChangeCollection = true
        value.capabilities.canChangeVisibility = true
        value.capabilities.canCapture = !hidden
        value.capabilities.canOpenHistory = true
        value.capabilities.canClearVisible = true
        value.capabilities.canEditPreferences = true
        return value
    }

    @MainActor private func prepareAppKit() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("No WindowServer; native control verification requires AppKit") }
    }

    @MainActor private func receive(_ condition: @escaping () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return condition()
    }

    @MainActor private func assertReceived(_ condition: @escaping () -> Bool,
                                           file: StaticString = #filePath, line: UInt = #line) async {
        let received = await receive(condition)
        XCTAssertTrue(received, file: file, line: line)
    }

    @MainActor func testFourStateProjectionPreservesFixedCaptureActionAndIndependentFacts() {
        let normal = RiftControlCenterPresentation(fixture())
        XCTAssertEqual(normal.state, .collecting)
        XCTAssertEqual(normal.primaryTitle, "截图…")
        let paused = RiftControlCenterPresentation(fixture(paused: true, hidden: true, collection: .paused))
        XCTAssertEqual(paused.state, .paused)
        XCTAssertTrue(paused.detail.contains("也已隐藏"))
        XCTAssertEqual(paused.primaryTitle, "截图…")
        XCTAssertFalse(paused.primaryEnabled)
        let hidden = RiftControlCenterPresentation(fixture(hidden: true))
        XCTAssertEqual(hidden.state, .hidden)
        XCTAssertTrue(hidden.detail.contains("仍在收录"))
        let fault = RiftControlCenterPresentation(fixture(paused: true, hidden: true, source: .unavailable, collection: .paused))
        XCTAssertEqual(fault.state, .attention)
        XCTAssertEqual(fault.recoveryPage, .help)
    }

    @MainActor func testTransientAttachmentContextIsNotPersistentAttentionOrFalseRunning() {
        for issue in [SetupIssue.targetUnavailable, .unsupportedBrowser, .unsupportedFormat, .imageUnavailable] {
            XCTAssertEqual(RiftControlCenterPresentation(fixture(issue: issue)).state, .collecting)
        }
        let stopped = RiftControlCenterPresentation(fixture(collection: .stopped))
        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertFalse(stopped.title.contains("正在收录"))
        let waiting = RiftControlCenterPresentation(fixture(hidden: true, source: .notChecked, collection: .waitingForSource))
        XCTAssertFalse(waiting.detail.contains("仍在收录"))
    }

    @MainActor func testSaveIssueProjectsCompactRecoveryWithoutClaimingRollback() {
        var value = fixture(paused: true, hidden: true)
        value.appearance.unreadable = true
        let projection = RiftControlCenterPresentation(value)
        XCTAssertEqual(projection.state, .attention)
        XCTAssertEqual(projection.recoveryPage, .general)
        XCTAssertTrue(projection.title.contains("确认保存"))
        XCTAssertFalse(projection.detail.contains("回滚"))
    }

    @MainActor func testUpdateIsPassivePreservesControlsAndRejectsOldRevisions() throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var actions = 0
        let controller = RiftControlCenterController(statusItem: item) { _ in actions += 1 }
        defer { controller.close() }
        controller.update(fixture())
        let pause = try XCTUnwrap(controller.control(identifier: "control.pause") as? NSSwitch)
        let hide = try XCTUnwrap(controller.control(identifier: "control.hide") as? NSSwitch)
        let capture = try XCTUnwrap(controller.control(identifier: "control.capture") as? NSButton)
        controller.update(fixture(revision: 2, paused: true, hidden: true, collection: .paused))
        XCTAssertTrue(pause === controller.control(identifier: "control.pause"))
        XCTAssertTrue(capture === controller.control(identifier: "control.capture"))
        XCTAssertEqual(pause.state, .on); XCTAssertEqual(hide.state, .on)
        XCTAssertFalse(capture.isEnabled)
        controller.update(fixture(revision: 1))
        XCTAssertEqual(pause.state, .on); XCTAssertEqual(hide.state, .on)
        XCTAssertEqual(actions, 0)
        XCTAssertFalse(controller.isShown)
        XCTAssertEqual(item.button?.accessibilityLabel(), "Riftlet")
        XCTAssertTrue(item.button?.image?.isTemplate == true)
        XCTAssertEqual(item.button?.title, "")
    }

    @MainActor func testSwitchActionsHaveExplicitTargetsWithoutOptimisticSuccess() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var targets: [String] = []
        let controller = RiftControlCenterController(statusItem: item) { action in
            switch action {
            case .settings(.setCollectionPaused(let target)): targets.append("pause:\(target)")
            case .settings(.setHidden(let target)): targets.append("hidden:\(target)")
            default: XCTFail("Unrelated action")
            }
        }
        defer { controller.close() }
        controller.update(fixture())
        let pause = try XCTUnwrap(controller.control(identifier: "control.pause") as? NSSwitch)
        let hide = try XCTUnwrap(controller.control(identifier: "control.hide") as? NSSwitch)
        pause.state = .on
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(pause.action), to: pause.target, from: pause))
        XCTAssertEqual(pause.state, .off, "Only a host receipt can change the accepted UI state")
        XCTAssertEqual(hide.state, .off)
        XCTAssertTrue(hide.isEnabled, "A collection request cannot lock independent visibility")
        await assertReceived { targets.count == 1 }
        controller.update(fixture(revision: 2, paused: true, collection: .paused))
        hide.state = .on
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(hide.action), to: hide.target, from: hide))
        await assertReceived { targets.count == 2 }
        XCTAssertEqual(targets, ["pause:true", "hidden:true"])
        XCTAssertEqual(pause.state, .on)
    }

    @MainActor func testMenuUsesSameCommandsAndPreservesItsExplicitTargetAcrossRefresh() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var values: [Bool] = []
        let controller = RiftControlCenterController(statusItem: item) { action in
            if case .settings(.setCollectionPaused(let value)) = action { values.append(value) }
        }
        defer { controller.close() }
        controller.update(fixture())
        let originalPause = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "暂停收录" })
        controller.update(fixture(revision: 2, paused: true, collection: .paused))
        XCTAssertNotNil(controller.contextMenu.items.first { $0.title == "继续收录" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(originalPause.action), to: originalPause.target, from: originalPause))
        await assertReceived { values.count == 1 }
        XCTAssertEqual(values, [true], "An already displayed command must not invert a newer owner state")
        XCTAssertNotNil(controller.contextMenu.items.first { $0.title == "定位最早截图" })
        XCTAssertEqual(controller.contextMenu.items.first { $0.title == "设置…" }?.keyEquivalent, ",")
    }

    @MainActor func testUnavailableCaptureCannotDispatchButHistoryRemainsAvailable() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var history = 0, captureCalls = 0
        let controller = RiftControlCenterController(statusItem: item) { action in
            if case .openHistory = action { history += 1 }
            if case .capture = action { captureCalls += 1 }
        }
        defer { controller.close() }
        var value = fixture(hidden: true)
        value.capabilities.canChangeCollection = false
        controller.update(value)
        let capture = try XCTUnwrap(controller.control(identifier: "control.capture") as? NSButton)
        capture.performClick(nil)
        XCTAssertFalse(capture.isEnabled)
        let historyButton = try XCTUnwrap(controller.control(identifier: "control.history") as? NSButton)
        XCTAssertTrue(historyButton.isEnabled)
        historyButton.performClick(nil)
        await assertReceived { history == 1 }
        XCTAssertEqual(captureCalls, 0)
    }

    @MainActor func testStatusActivationTogglesOnePopoverAndActionClosesBeforeDispatch() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        weak var observed: RiftControlCenterController?
        var openedSettings = 0
        let controller = RiftControlCenterController(statusItem: item) { action in
            if case .openSettings = action {
                XCTAssertFalse(observed?.isShown ?? true)
                openedSettings += 1
            }
        }
        observed = controller
        defer { controller.close() }
        controller.update(fixture())
        let button = try XCTUnwrap(item.button)
        guard button.window?.isVisible == true else { throw XCTSkip("No usable native status-bar anchor; real menu focus acceptance remains separate") }
        button.performClick(nil)
        XCTAssertTrue(controller.isShown)
        await assertReceived { controller.isShown && controller.window?.isVisible == true }
        controller.contentView.layoutSubtreeIfNeeded()
        for id in ["control.pause", "control.hide"] {
            let toggle = try XCTUnwrap(controller.control(identifier: id))
            let row = try XCTUnwrap(toggle.superview as? NSStackView)
            let copy = try XCTUnwrap(row.arrangedSubviews.first { $0.identifier?.rawValue == id + ".text" })
            XCTAssertGreaterThan(copy.frame.width, 200, "Wrapping copy must use the open space to the left of its switch")
            XCTAssertEqual(copy.frame.width + toggle.frame.width + row.spacing, row.bounds.width, accuracy: 1)
        }
        let firstWindow = controller.window
        button.performClick(nil)
        XCTAssertFalse(controller.isShown)
        await assertReceived { !controller.isShown && controller.window?.isVisible != true }
        button.performClick(nil)
        XCTAssertTrue(controller.isShown)
        await assertReceived { controller.isShown && controller.window?.isVisible == true }
        XCTAssertTrue(controller.window === firstWindow)
        let settings = try XCTUnwrap(controller.control(identifier: "control.settings") as? NSButton)
        settings.performClick(nil)
        await assertReceived { openedSettings == 1 }
        XCTAssertFalse(controller.isShown)
    }

    @MainActor func testSuspendedInteractionRejectsStatusAndStaleCommandsThenRestoresLatestState() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var actions = 0
        let controller = RiftControlCenterController(statusItem: item) { _ in actions += 1 }
        defer { controller.close() }
        controller.update(fixture())
        let status = try XCTUnwrap(item.button)
        let pause = try XCTUnwrap(controller.control(identifier: "control.pause") as? NSSwitch)
        let settings = try XCTUnwrap(controller.control(identifier: "control.settings") as? NSButton)
        let staleMenu = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "暂停收录" })
        controller.setInteractionSuspended(true)
        controller.update(fixture(revision: 2, paused: true, hidden: true, collection: .paused))
        XCTAssertFalse(status.isEnabled); XCTAssertFalse(pause.isEnabled); XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(controller.contextMenu.items.filter { $0.action != nil }.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(status.action), to: status.target, from: status))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(pause.action), to: pause.target, from: pause))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(settings.action), to: settings.target, from: settings))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(staleMenu.action), to: staleMenu.target, from: staleMenu))
        XCTAssertFalse(controller.isShown)
        XCTAssertEqual(actions, 0)
        controller.setInteractionSuspended(false)
        XCTAssertTrue(status.isEnabled); XCTAssertTrue(pause.isEnabled); XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(pause.state, .on, "Cancelling Quit keeps the latest owner state")
        XCTAssertFalse(try XCTUnwrap(controller.control(identifier: "control.capture") as? NSButton).isEnabled)
        settings.performClick(nil)
        await assertReceived { actions == 1 }
        XCTAssertEqual(actions, 1, "No command blocked during termination may be replayed after cancellation")
    }
}
