import AppKit
import XCTest
@testable import RiftletUI

final class RiftOnboardingControllerTests: XCTestCase {
    private static let mainDisplayUUID = "00000000-0000-4000-8000-000000000001"
    private static let externalDisplayUUID = "00000000-0000-4000-8000-000000000002"
    private static let disconnectedDisplayUUID = "00000000-0000-4000-8000-000000000099"

    @MainActor private func model(revision: UInt64 = 1, paused: Bool = false, hidden: Bool = false,
                                  configuration: RiftConfiguration = .init(),
                                  displays: [RiftSettingsDisplay]? = nil) throws -> SettingsStateModel {
        let settings = RiftSettingsSnapshot(entryAvailable: true, entryEnabled: false,
            displays: displays ?? [.init(id: 1, name: "合成内建屏", uuid: Self.mainDisplayUUID),
                       .init(id: 2, name: "合成外接屏", uuid: Self.externalDisplayUUID)],
            preferredDisplayID: configuration.preferredDisplayID, configuration: configuration)
        return try SettingsStateModel(owner: .init(revision: revision, settings: settings,
            collectionPaused: paused, isHidden: hidden, mainDisplayID: 1),
            adapter: SettingsPersistenceClosures { _ in .unconfirmed(nil, .writeUnconfirmed) })
    }

    @MainActor private func fixture(_ model: SettingsStateModel, revision: UInt64 = 1,
                                    source: SetupSourceState = .accessible,
                                    permission: SetupPermissionState = .granted,
                                    connection: OnboardingChromeConnection = .ready) -> SettingsProductSnapshot {
        var value = SettingsProductSnapshot(revision: revision,
            setup: .init(sourceLocation: "/tmp/synthetic-only-screenshot-folder", source: source,
                         collection: model.snapshot.owner.collectionPaused ? .paused : .collecting,
                         isHidden: model.snapshot.owner.isHidden, attachment: .available, permission: permission,
                         permissionDetail: ChromeAttachmentSetup.instructions),
            state: model.snapshot)
        value.chromeConnection = connection
        value.capabilities.initialized = true
        value.capabilities.canChangeCollection = true
        value.capabilities.canChangeVisibility = true
        value.capabilities.canChooseSource = true
        value.capabilities.canRequestAutomation = true
        value.capabilities.canEditPreferences = true
        value.capabilities.canRecheck = true
        return value
    }

    @MainActor private func prepareAppKit() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("No WindowServer; native guidance requires AppKit") }
    }

    @MainActor private func button(_ controller: RiftOnboardingController, _ id: String) throws -> NSButton {
        try XCTUnwrap(controller.control(identifier: id) as? NSButton)
    }

    @MainActor private func assertReceived(_ condition: @escaping () -> Bool,
                                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    @MainActor func testConstructionAndRefreshNeverPresentRequestOrSave() throws {
        try prepareAppKit()
        var actions = 0
        let controller = RiftOnboardingController(copy: .simplifiedChinese) { _ in actions += 1 }
        defer { controller.closeForTeardown() }
        XCTAssertFalse(controller.show(), "Without host facts this cannot count as actual presentation")
        let state = try model()
        controller.update(fixture(state))
        let next = try button(controller, "onboarding.next")
        let folder = try XCTUnwrap(controller.control(identifier: "onboarding.sourceAccess"))
        controller.update(fixture(state, revision: 2, source: .accessible, permission: .granted))
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(actions, 0)
        XCTAssertTrue(next === controller.control(identifier: "onboarding.next"))
        XCTAssertTrue(folder === controller.control(identifier: "onboarding.sourceAccess"))
        XCTAssertEqual(controller.currentStep, 0)
        XCTAssertEqual(controller.window.identifier, RiftOnboardingController.windowIdentifier)
    }

    @MainActor func testFolderDiscoveryThenDeniedAccessAndReturnFromPrivacySettings() async throws {
        try prepareAppKit()
        var actions: [String] = []
        let controller = RiftOnboardingController(copy: .english) { action in
            switch action {
            case .openFilePrivacy: actions.append("privacy")
            default: XCTFail("Showing or refreshing guidance cannot request access")
            }
        }
        defer { controller.closeForTeardown() }
        let state = try model()
        var startup = fixture(state)
        startup.setup = .init(source: .notConfigured, collection: .starting, isChecking: true)
        startup.capabilities.initialized = false
        controller.update(startup)
        let status = try XCTUnwrap(controller.control(identifier: "onboarding.sourceStatus") as? NSTextField)
        let grant = try button(controller, "onboarding.sourceAccess")
        let privacy = try button(controller, "onboarding.filePrivacy")
        let recheck = try button(controller, "onboarding.recheck")
        XCTAssertTrue(status.stringValue.contains("Checking your screenshot folder"))
        XCTAssertTrue(status.stringValue.contains("choose Allow"))
        let preview = try XCTUnwrap(controller.control(identifier: "onboarding.workflowPreview"))
        XCTAssertFalse(preview.isHidden)
        XCTAssertTrue(grant.isHidden && privacy.isHidden && recheck.isHidden)
        var denied = fixture(state, revision: 2)
        denied.setup = .init(sourceLocation: "/fixture/Desktop", source: .unavailable,
                             collection: .waitingForSource, issue: .sourceAccess)
        controller.update(denied)
        XCTAssertTrue(controller.show())
        XCTAssertTrue(status.stringValue.contains("Files and Folders"))
        XCTAssertFalse(grant.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(privacy.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(privacy.isEnabled)
        XCTAssertTrue(preview.isHidden)
        controller.window.contentView?.layoutSubtreeIfNeeded()
        for action in [grant, privacy] {
            let clip = try XCTUnwrap(action.enclosingScrollView?.contentView)
            let frame = action.convert(action.bounds, to: clip)
            XCTAssertTrue(clip.bounds.contains(frame),
                          "\(action.title) frame \(frame), viewport \(clip.bounds), native insets \(action.alignmentRectInsets)")
        }
        privacy.performClick(nil)
        await assertReceived { actions == ["privacy"] }
        controller.update(fixture(state, revision: 3, permission: .notRequested, connection: .unchecked))
        XCTAssertTrue(privacy.isHidden && grant.isHidden)
        XCTAssertFalse(preview.isHidden)
        let next = try button(controller, "onboarding.next")
        XCTAssertTrue(next.isEnabled)
        next.performClick(nil)
        let browser = try button(controller, "onboarding.automation")
        XCTAssertEqual(browser.title, "Allow Access to Chrome…")
        XCTAssertTrue(browser.isEnabled)
        XCTAssertEqual(actions, ["privacy"])
    }

    @MainActor func testReviewGuidanceKeepsProductFlowSeparateFromCurrentNoUploadCapability() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController(copy: .simplifiedChinese) { _ in XCTFail("Reading guidance cannot issue a command") }
        defer { controller.closeForTeardown() }
        var value = fixture(try model(), source: .accessible, permission: .notNeeded)
        value.reviewEnvironment = true
        value.capabilities.canRequestAutomation = false
        controller.update(value)
        let description = try XCTUnwrap(controller.control(identifier: "onboarding.introDescription") as? NSTextField)
        let capability = try XCTUnwrap(controller.control(identifier: "onboarding.capability") as? NSTextField)
        XCTAssertFalse(description.stringValue.contains("⌘"))
        XCTAssertTrue(description.stringValue.contains("Chrome"))
        XCTAssertTrue(description.stringValue.contains("托盘里的图片"))
        XCTAssertTrue(description.stringValue.contains("ChatGPT"))
        XCTAssertTrue(capability.stringValue.contains("隔离审核"))
        XCTAssertTrue(capability.stringValue.contains("不连接浏览器或上传"))
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor func testEdgeScriptInstructionsAppearAfterARealRefusal() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController(copy: .english) { _ in XCTFail("Rendering cannot request permission") }
        defer { controller.closeForTeardown() }
        var state = fixture(try model(), source: .accessible, permission: .granted, connection: .unchecked)
        state.setup = .init(source: .accessible, collection: .collecting, attachment: .available, permission: .granted,
                            permissionDetail: ChromeAttachmentSetup.instructions(for: .edge), browser: .edge)
        controller.update(state)
        XCTAssertTrue(controller.show())
        try button(controller, "onboarding.next").performClick(nil)
        let label = try XCTUnwrap(controller.control(identifier: "onboarding.scriptStatus") as? NSTextField)
        XCTAssertTrue(label.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(try button(controller, "onboarding.checkChrome").isHiddenOrHasHiddenAncestor)
        state = fixture(try model(), revision: 2, connection: .javaScriptDisabled)
        state.setup = .init(source: .accessible, collection: .collecting, attachment: .available, permission: .granted,
                            issue: .chromeJavaScriptDisabled, browser: .edge)
        controller.update(state)
        XCTAssertFalse(label.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(label.stringValue.contains("Microsoft Edge"))
        XCTAssertFalse(label.stringValue.contains("Chrome"))
        XCTAssertFalse(try button(controller, "onboarding.next").isEnabled)
    }

    @MainActor func testChromeMenuPathIsVisibleBeforeFirstClickEvenWhenAutomationIsGranted() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController(copy: .simplifiedChinese) { _ in XCTFail("Showing setup must not contact Chrome") }
        defer { controller.closeForTeardown() }
        let state = try model()
        controller.update(fixture(state, source: .accessible, permission: .granted, connection: .unchecked))
        XCTAssertTrue(controller.show())
        try button(controller, "onboarding.next").performClick(nil)
        let instructions = try XCTUnwrap(controller.control(identifier: "onboarding.scriptStatus") as? NSTextField)
        controller.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(instructions.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(instructions.stringValue.contains("显示 → 开发者 → 允许 Apple 事件中的 JavaScript"))
        let viewport = try XCTUnwrap(instructions.enclosingScrollView?.contentView)
        XCTAssertGreaterThan(instructions.bounds.height, 0)
        let parent = try XCTUnwrap(instructions.superview)
        let textRect = parent.convert(instructions.alignmentRect(forFrame: instructions.frame), to: viewport)
        XCTAssertTrue(viewport.bounds.insetBy(dx: -1, dy: -1).contains(textRect))
        var blocked = fixture(state, revision: 2, connection: .javaScriptDisabled)
        blocked.setup = .init(source: .accessible, collection: .collecting, attachment: .available, permission: .granted,
                              permissionDetail: ChromeAttachmentSetup.instructions, issue: .chromeJavaScriptDisabled)
        controller.update(blocked)
        let next = try button(controller, "onboarding.next")
        XCTAssertFalse(next.isEnabled)
        next.performClick(nil)
        XCTAssertEqual(controller.currentStep, 1)
        let status = try XCTUnwrap(controller.control(identifier: "onboarding.connectionStatus") as? NSTextField)
        XCTAssertTrue(status.stringValue.contains("尚未开启"))
        var offline = fixture(state, revision: 3)
        offline.setup = .init(attachment: .offlineSimulation, permissionDetail: ChromeAttachmentSetup.instructions)
        controller.update(offline)
        XCTAssertTrue(instructions.isHiddenOrHasHiddenAncestor)
    }

    @MainActor func testFirstPresentationRestoresIntendedOuterSizeAndReopenPreservesResize() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController(copy: .simplifiedChinese) { _ in XCTFail("Presentation cannot save a setting") }
        defer { controller.closeForTeardown() }
        controller.update(fixture(try model()))
        XCTAssertTrue(controller.show())
        controller.window.contentView?.layoutSubtreeIfNeeded()
        if let visible = controller.window.screen?.visibleFrame, visible.width >= 584, visible.height >= 453 {
            XCTAssertEqual(controller.window.frame.width, 584, accuracy: 1)
            XCTAssertEqual(controller.window.frame.height, 453, accuracy: 1)
        }
        let presented = controller.window.frame
        controller.update(fixture(try model(), revision: 2, source: .accessible, permission: .granted))
        try button(controller, "onboarding.next").performClick(nil)
        XCTAssertEqual(controller.window.frame, presented, "Facts and stack page layout cannot replace the window size")
        controller.closeForTeardown()
        XCTAssertTrue(controller.show())
        XCTAssertEqual(controller.window.frame.size, presented.size)
        var resized = controller.window.frame
        resized.size = NSSize(width: 600, height: 560)
        controller.window.setFrame(resized, display: true)
        let accepted = controller.window.frame.size
        controller.closeForTeardown()
        XCTAssertTrue(controller.show())
        XCTAssertEqual(controller.window.frame.size, accepted)
    }

    @MainActor func testFinishRequiresBothRealChecksAndRecoversAfterLosingFolderAccess() async throws {
        try prepareAppKit()
        var actions: [String] = []
        let state = try model()
        let controller = RiftOnboardingController(copy: .simplifiedChinese) { action in
            switch action {
            case .finishOnboarding: actions.append("finish")
            case .chooseSourceAccess: actions.append("folder")
            case .checkChromeConnection: actions.append("chrome")
            default: XCTFail("Navigation must not request consent or change settings")
            }
        }
        defer { controller.closeForTeardown() }
        controller.update(fixture(state, source: .unavailable, permission: .notRequested, connection: .unchecked))
        XCTAssertTrue(controller.show())
        let next = try button(controller, "onboarding.next")
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(controller.window.initialFirstResponder === controller.control(identifier: "onboarding.sourceAccess"))
        try button(controller, "onboarding.sourceAccess").performClick(nil)
        await assertReceived { actions == ["folder"] }

        controller.update(fixture(state, revision: 2, connection: .unchecked))
        next.performClick(nil)
        XCTAssertEqual(controller.currentStep, 1)
        XCTAssertFalse(next.isEnabled, "macOS Automation alone does not establish Chrome's JavaScript setting")
        let check = try button(controller, "onboarding.checkChrome")
        XCTAssertTrue(controller.window.initialFirstResponder === check)
        check.performClick(nil)
        await assertReceived { actions == ["folder", "chrome"] }
        for (offset, result) in [OnboardingChromeConnection.checking, .javaScriptDisabled, .noWindow, .unavailable].enumerated() {
            controller.update(fixture(state, revision: UInt64(offset + 3), connection: result))
            XCTAssertFalse(next.isEnabled)
            XCTAssertEqual(check.isEnabled, result != .checking)
        }
        controller.update(fixture(state, revision: 8))
        XCTAssertTrue(next.isEnabled)
        controller.update(fixture(state, revision: 9, source: .unavailable))
        XCTAssertEqual(next.title, "设置截图文件夹")
        next.performClick(nil)
        XCTAssertEqual(controller.currentStep, 0)
        XCTAssertEqual(actions, ["folder", "chrome"])

        controller.update(fixture(state, revision: 10))
        next.performClick(nil)
        XCTAssertEqual(next.title, "开始使用")
        next.performClick(nil); next.performClick(nil)
        await assertReceived { actions == ["folder", "chrome", "finish"] }
    }

    @MainActor func testPausedAndHiddenRequireExplicitRecoveryAndDoNotAlterPreferences() async throws {
        try prepareAppKit()
        let paused = try model(paused: true, hidden: true)
        let snapshot = fixture(paused)
        XCTAssertFalse(snapshot.onboardingReady)
        var actions: [String] = []
        let controller = RiftOnboardingController(copy: .simplifiedChinese) { action in
            switch action {
            case .settings(.setCollectionPaused(false)): actions.append("resume")
            case .settings(.setHidden(false)): actions.append("show")
            default: XCTFail("Unexpected action")
            }
        }
        defer { controller.closeForTeardown() }
        controller.update(snapshot)
        XCTAssertTrue(actions.isEmpty)
        let next = try button(controller, "onboarding.next")
        XCTAssertFalse(next.isEnabled)
        try button(controller, "onboarding.resume").performClick(nil)
        await assertReceived { actions == ["resume"] }
        try button(controller, "onboarding.unhide").performClick(nil)
        await assertReceived { actions == ["resume", "show"] }
        XCTAssertTrue(paused.snapshot.owner.collectionPaused)
        XCTAssertTrue(paused.snapshot.owner.isHidden)
        XCTAssertFalse(next.isEnabled)
    }

    @MainActor func testClosingAndLaterDeferOncePerPresentationWhileTeardownDoesNot() throws {
        try prepareAppKit()
        var deferrals = 0
        let controller = RiftOnboardingController(copy: .simplifiedChinese, onDefer: { deferrals += 1 }) { _ in XCTFail("Closing must not request permissions") }
        controller.update(fixture(try model(), connection: .unchecked))
        XCTAssertTrue(controller.show())
        controller.window.performClose(nil)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(deferrals, 1)
        XCTAssertTrue(controller.show())
        try button(controller, "onboarding.next").performClick(nil)
        let later = try button(controller, "onboarding.later")
        XCTAssertEqual(later.title, "先使用本地截图")
        XCTAssertEqual(later.keyEquivalent, "\u{1b}")
        later.performClick(nil)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(deferrals, 2)
        XCTAssertTrue(controller.show())
        controller.closeForTeardown()
        XCTAssertEqual(deferrals, 2)
    }

    @MainActor func testAlreadyGrantedPermissionsDoNotOfferOrRepeatAuthorization() async throws {
        try prepareAppKit()
        var requested = 0
        let controller = RiftOnboardingController(copy: .simplifiedChinese) { action in
            if case .chooseSourceAccess = action { requested += 1 }
            if case .requestAutomation = action { requested += 1 }
        }
        defer { controller.closeForTeardown() }
        let state = try model()
        controller.update(fixture(state, source: .accessible, permission: .granted))
        let source = try button(controller, "onboarding.sourceAccess")
        let automation = try button(controller, "onboarding.automation")
        XCTAssertTrue(source.isHidden)
        XCTAssertFalse(source.isEnabled)
        let next = try button(controller, "onboarding.next")
        next.performClick(nil)
        XCTAssertTrue(automation.isHidden)
        XCTAssertFalse(automation.isEnabled)
        source.performClick(nil); automation.performClick(nil)
        await Task.yield()
        XCTAssertEqual(requested, 0)
        controller.update(fixture(state, revision: 2, permission: .notRequested, connection: .unchecked))
        XCTAssertTrue(automation.isEnabled)
        automation.performClick(nil)
        await assertReceived { requested == 1 }
        try button(controller, "onboarding.back").performClick(nil)
        controller.update(fixture(state, revision: 3, source: .unavailable))
        XCTAssertFalse(source.isHidden); XCTAssertTrue(source.isEnabled)
        source.performClick(nil)
        await assertReceived { requested == 2 }
    }

    @MainActor func testTwoStepsUseExistingPlacementAndOpenChromeOnlyWhenRequested() async throws {
        try prepareAppKit()
        var opened = 0
        let state = try model()
        let controller = RiftOnboardingController(copy: .english) { action in
            if case .openChrome = action { opened += 1 } else { XCTFail("Unexpected request") }
        }
        defer { controller.closeForTeardown() }
        controller.update(fixture(state, permission: .notRunning, connection: .unchecked))
        XCTAssertTrue(controller.show())
        let next = try button(controller, "onboarding.next")
        next.performClick(nil)
        let open = try button(controller, "onboarding.automation")
        XCTAssertEqual(open.title, "Open Chrome")
        XCTAssertFalse(next.isEnabled)
        XCTAssertFalse(open.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(try button(controller, "onboarding.checkChrome").isHiddenOrHasHiddenAncestor)
        XCTAssertNil(controller.control(identifier: "onboarding.display"))
        XCTAssertNil(controller.control(identifier: "onboarding.placement.rightTop"))
        XCTAssertEqual(opened, 0)
        open.performClick(nil)
        await assertReceived { opened == 1 }
        try button(controller, "onboarding.back").performClick(nil)
        XCTAssertEqual(controller.currentStep, 0)
        next.performClick(nil)
        XCTAssertTrue(open === controller.control(identifier: "onboarding.automation"))
    }

    func testFirstUseSelectsPreferredSupportedLanguageAndFallsBackToChinese() {
        XCTAssertEqual(OnboardingCopy.preferred(for: ["en-GB", "zh-Hans"]), .english)
        XCTAssertEqual(OnboardingCopy.preferred(for: ["fr-FR", "zh-Hans-CN", "en-US"]), .simplifiedChinese)
        XCTAssertEqual(OnboardingCopy.preferred(for: ["ja-JP", "en-US"]), .english)
        XCTAssertEqual(OnboardingCopy.preferred(for: ["de"]), .simplifiedChinese)
    }

    @MainActor func testEnglishFirstUseRecoveryNavigationAndMinimumWidth() async throws {
        try prepareAppKit()
        let state = try model()
        var actions: [String] = []
        let controller = RiftOnboardingController(copy: .english) { action in
            switch action {
            case .chooseSourceAccess: actions.append("folder")
            case .requestAutomation: actions.append("automation")
            case .finishOnboarding: actions.append("finish")
            default: XCTFail("Unexpected action")
            }
        }
        defer { controller.closeForTeardown() }
        let next = try button(controller, "onboarding.next")
        let later = try button(controller, "onboarding.later")
        let source = try button(controller, "onboarding.sourceAccess")
        controller.update(fixture(state, source: .unavailable))
        XCTAssertTrue(controller.show())
        controller.window.setContentSize(NSSize(width: 520, height: 416))
        XCTAssertEqual(controller.window.title, "Get Started with Riftlet")
        XCTAssertEqual(source.title, "Allow Screenshot Folder Access…")
        XCTAssertEqual(source.accessibilityLabel(), source.title)
        XCTAssertEqual(later.accessibilityLabel(), "Set Up Later")
        XCTAssertFalse(next.isEnabled)
        source.performClick(nil)
        await assertReceived { actions == ["folder"] }

        controller.update(fixture(state, revision: 2, permission: .denied, connection: .unchecked))
        next.performClick(nil)
        let automation = try button(controller, "onboarding.automation")
        let status = try XCTUnwrap(controller.control(identifier: "onboarding.automationStatus") as? NSTextField)
        let instructions = try XCTUnwrap(controller.control(identifier: "onboarding.scriptStatus") as? NSTextField)
        XCTAssertTrue(status.stringValue.contains("Privacy & Security → Automation"))
        XCTAssertTrue(instructions.stringValue.contains("View → Developer → Allow JavaScript from Apple Events"))
        XCTAssertEqual(automation.accessibilityLabel(), "Open Automation Settings…")
        let connection = try XCTUnwrap(controller.control(identifier: "onboarding.connectionStatus") as? NSTextField)
        let check = try button(controller, "onboarding.checkChrome")
        XCTAssertTrue(connection.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(check.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(check.isEnabled)
        XCTAssertFalse(next.isEnabled)
        automation.performClick(nil)
        await assertReceived { actions == ["folder", "automation"] }
        controller.update(fixture(state, revision: 3, permission: .granted, connection: .unchecked))
        XCTAssertFalse(connection.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(connection.stringValue, "Choose Check Connection to verify the current browser.")
        XCTAssertFalse(check.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(check.isEnabled)
        XCTAssertEqual(check.title, "Check Connection")
        XCTAssertFalse(next.isEnabled)
        controller.update(fixture(state, revision: 4, connection: .javaScriptDisabled))
        XCTAssertTrue((controller.control(identifier: "onboarding.connectionStatus") as? NSTextField)?.stringValue.contains("option is off") == true)
        XCTAssertFalse(next.isEnabled)
        controller.update(fixture(state, revision: 5))
        XCTAssertEqual(next.accessibilityLabel(), "Get Started")
        XCTAssertTrue(instructions.isHiddenOrHasHiddenAncestor)
        try button(controller, "onboarding.back").performClick(nil)
        XCTAssertEqual(controller.currentStep, 0)
        next.performClick(nil)
        next.performClick(nil)
        await assertReceived { actions == ["folder", "automation", "finish"] }
    }
}
