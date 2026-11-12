import AppKit
import XCTest
@testable import RiftletUI

final class RiftOnboardingControllerTests: XCTestCase {
    private static let mainDisplayUUID = "00000000-0000-4000-8000-000000000001"
    private static let externalDisplayUUID = "00000000-0000-4000-8000-000000000002"
    private static let disconnectedDisplayUUID = "00000000-0000-4000-8000-000000000099"

    @MainActor private func model(revision: UInt64 = 1, paused: Bool = true, hidden: Bool = true,
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
                                    source: SetupSourceState = .unavailable,
                                    permission: SetupPermissionState = .notRequested) -> SettingsProductSnapshot {
        var value = SettingsProductSnapshot(revision: revision,
            setup: .init(sourceLocation: "/tmp/synthetic-only-screenshot-folder", source: source,
                         collection: .paused, isHidden: true, attachment: .available, permission: permission,
                         permissionDetail: ChromeAttachmentSetup.instructions),
            state: model.snapshot)
        value.capabilities.initialized = true
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
        let controller = RiftOnboardingController { _ in actions += 1 }
        defer { controller.closeForTeardown() }
        XCTAssertFalse(controller.show(), "Without host facts this cannot count as actual presentation")
        let state = try model()
        controller.update(fixture(state))
        let next = try button(controller, "onboarding.next")
        let display = try XCTUnwrap(controller.control(identifier: "onboarding.display"))
        controller.update(fixture(state, revision: 2, source: .accessible, permission: .granted))
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(actions, 0)
        XCTAssertTrue(next === controller.control(identifier: "onboarding.next"))
        XCTAssertTrue(display === controller.control(identifier: "onboarding.display"))
        XCTAssertEqual(controller.currentStep, 0)
        XCTAssertEqual(controller.window.identifier, RiftOnboardingController.windowIdentifier)
    }

    @MainActor func testReviewGuidanceKeepsProductFlowSeparateFromCurrentNoUploadCapability() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController { _ in XCTFail("Reading guidance cannot issue a command") }
        defer { controller.closeForTeardown() }
        var value = fixture(try model(), source: .accessible, permission: .notNeeded)
        value.reviewEnvironment = true
        value.capabilities.canRequestAutomation = false
        controller.update(value)
        let description = try XCTUnwrap(controller.control(identifier: "onboarding.introDescription") as? NSTextField)
        let capability = try XCTUnwrap(controller.control(identifier: "onboarding.capability") as? NSTextField)
        XCTAssertTrue(description.stringValue.contains("⇧⌘4"))
        XCTAssertTrue(description.stringValue.contains("Chrome 前台"))
        XCTAssertTrue(description.stringValue.contains("屏幕边缘的微图"))
        XCTAssertTrue(description.stringValue.contains("ChatGPT"))
        XCTAssertTrue(capability.stringValue.contains("隔离审核"))
        XCTAssertTrue(capability.stringValue.contains("不连接浏览器或上传"))
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor func testChromeMenuPathIsVisibleBeforeFirstClickEvenWhenAutomationIsGranted() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController { _ in XCTFail("Showing setup must not contact Chrome") }
        defer { controller.closeForTeardown() }
        let state = try model()
        controller.update(fixture(state, source: .accessible, permission: .granted))
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
        var blocked = fixture(state, revision: 2)
        blocked.setup = .init(source: .accessible, attachment: .available, permission: .granted,
                              permissionDetail: ChromeAttachmentSetup.instructions, issue: .chromeJavaScriptDisabled)
        controller.update(blocked)
        try button(controller, "onboarding.next").performClick(nil)
        let finish = try XCTUnwrap(controller.control(identifier: "onboarding.finishHint") as? NSTextField)
        XCTAssertTrue(finish.stringValue.contains(ChromeAttachmentSetup.menuPath))
        XCTAssertFalse(finish.stringValue.contains("点屏幕边缘的微图"))
        var offline = fixture(state, revision: 3)
        offline.setup = .init(attachment: .offlineSimulation, permissionDetail: ChromeAttachmentSetup.instructions)
        controller.update(offline)
        XCTAssertTrue(instructions.isHiddenOrHasHiddenAncestor)
    }

    @MainActor func testDefaultPlacementStepShowsAllSixChoicesWithoutScrolling() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController { _ in XCTFail("Navigation cannot save a preference") }
        defer { controller.closeForTeardown() }
        controller.update(fixture(try model(paused: false, hidden: false), source: .accessible, permission: .granted))
        XCTAssertTrue(controller.show())
        guard let screen = controller.window.screen,
              screen.visibleFrame.width >= SettingsNativeStyle.onboardingSize.width,
              screen.visibleFrame.height >= SettingsNativeStyle.onboardingSize.height else {
            throw XCTSkip("The intended onboarding size is unavailable on this display")
        }
        try button(controller, "onboarding.next").performClick(nil)
        try button(controller, "onboarding.next").performClick(nil)
        controller.window.contentView?.layoutSubtreeIfNeeded()
        for placement in RiftPlacement.allCases {
            let choice = try button(controller, "onboarding.placement." + placement.rawValue)
            XCTAssertFalse(choice.isHiddenOrHasHiddenAncestor)
            XCTAssertGreaterThan(choice.bounds.width, 0)
            let viewport = try XCTUnwrap(choice.enclosingScrollView?.contentView)
            let choiceInViewport = choice.convert(choice.bounds, to: viewport)
            XCTAssertTrue(viewport.bounds.insetBy(dx: -1, dy: -1).contains(choiceInViewport),
                          "Every placement choice must be reachable in the default first viewport")
        }
    }

    @MainActor func testFirstPresentationRestoresIntendedOuterSizeAndReopenPreservesResize() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController { _ in XCTFail("Presentation cannot save a setting") }
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

    @MainActor func testAllThreeStepsAllowIncompleteConnectionsAndFinishHasNoCaptureOrToggle() async throws {
        try prepareAppKit()
        let state = try model()
        var actions: [String] = []
        let controller = RiftOnboardingController { action in
            switch action {
            case .finishOnboarding: actions.append("finish")
            default: actions.append("unexpected"); XCTFail("Finishing cannot authorize, capture, send, or unpause")
            }
        }
        defer { controller.closeForTeardown() }
        controller.update(fixture(state))
        let next = try button(controller, "onboarding.next")
        next.performClick(nil); XCTAssertEqual(controller.currentStep, 1)
        XCTAssertTrue(actions.isEmpty)
        next.performClick(nil); XCTAssertEqual(controller.currentStep, 2)
        XCTAssertEqual(next.title, "开始使用")
        XCTAssertTrue(actions.isEmpty)
        next.performClick(nil)
        await assertReceived { actions.count == 1 }
        XCTAssertEqual(actions, ["finish"])
        XCTAssertTrue(state.snapshot.owner.collectionPaused)
        XCTAssertTrue(state.snapshot.owner.isHidden)
        XCTAssertFalse(state.snapshot.owner.settings.entryEnabled)
        next.performClick(nil)
        await Task.yield()
        XCTAssertEqual(actions, ["finish"], "A finished presentation cannot dispatch twice")
    }

    @MainActor func testLaterAndTeardownDoNotDispatchFinishOrAnyCommand() async throws {
        try prepareAppKit()
        var actions = 0
        let controller = RiftOnboardingController { _ in actions += 1 }
        controller.update(fixture(try model()))
        try button(controller, "onboarding.next").performClick(nil)
        try button(controller, "onboarding.later").performClick(nil)
        controller.closeForTeardown()
        await Task.yield()
        XCTAssertEqual(actions, 0)
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor func testAlreadyGrantedPermissionsDoNotOfferOrRepeatAuthorization() async throws {
        try prepareAppKit()
        var requested = 0
        let controller = RiftOnboardingController { action in
            if case .chooseSourceAccess = action { requested += 1 }
            if case .requestAutomation = action { requested += 1 }
        }
        defer { controller.closeForTeardown() }
        let state = try model()
        controller.update(fixture(state, source: .accessible, permission: .granted))
        try button(controller, "onboarding.next").performClick(nil)
        let source = try button(controller, "onboarding.sourceAccess")
        let automation = try button(controller, "onboarding.automation")
        XCTAssertTrue(source.isHidden)
        XCTAssertFalse(source.isEnabled)
        XCTAssertFalse(automation.isEnabled)
        source.performClick(nil); automation.performClick(nil)
        await Task.yield()
        XCTAssertEqual(requested, 0)
        controller.update(fixture(state, revision: 2))
        XCTAssertFalse(source.isHidden); XCTAssertTrue(source.isEnabled)
        XCTAssertTrue(automation.isEnabled)
        source.performClick(nil); automation.performClick(nil)
        await assertReceived { requested == 2 }
    }

    @MainActor func testPlacementAndDisplayUseExistingExplicitCommandsAndPreserveLegacyValues() async throws {
        try prepareAppKit()
        var configuration = RiftConfiguration()
        configuration.placement = nil; configuration.placementSource = .legacy
        configuration.outerInset = 14; configuration.hiddenFraction = 0.57
        configuration.preferredDisplayID = 2; configuration.preferredDisplayUUID = Self.externalDisplayUUID
        try configuration.validate()
        let state = try model(configuration: configuration)
        var selected: [String] = []
        let controller = RiftOnboardingController { action in
            switch action {
            case .settings(.selectPlacement(let placement)): selected.append(placement.rawValue)
            case .settings(.selectDisplay(let id)): selected.append(id.map(String.init) ?? "primary")
            default: XCTFail("Unrelated command")
            }
        }
        defer { controller.closeForTeardown() }
        controller.update(fixture(state))
        for _ in 0..<2 { try button(controller, "onboarding.next").performClick(nil) }
        for placement in RiftPlacement.allCases {
            XCTAssertEqual(try button(controller, "onboarding.placement." + placement.rawValue).state, .off)
        }
        try button(controller, "onboarding.placement.leftMiddle").performClick(nil)
        await assertReceived { selected.count == 1 }
        XCTAssertEqual(state.snapshot.owner.settings.configuration, configuration)
        let display = try XCTUnwrap(controller.control(identifier: "onboarding.display") as? NSPopUpButton)
        XCTAssertEqual(display.titleOfSelectedItem, "合成外接屏")
        display.selectItem(at: 0)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(display.action), to: display.target, from: display))
        await assertReceived { selected.count == 2 }
        XCTAssertEqual(selected, ["leftMiddle", "primary"])
        XCTAssertEqual(state.snapshot.owner.settings.configuration, configuration,
                       "A UI action cannot fabricate persistence or apply the recommendation")
    }

    @MainActor func testUnconfirmedPlacementShowsSameTargetRetryAndOtherDomainRemainsUsable() async throws {
        try prepareAppKit()
        let state = try model()
        weak var observed: RiftOnboardingController?
        var commands: [String] = []
        var revision: UInt64 = 1
        let controller = RiftOnboardingController { action in
            guard case .settings(let command) = action else { XCTFail("Unrelated action"); return }
            switch command {
            case .selectPlacement(let value): commands.append(value.rawValue)
            case .retry(let domain): commands.append("retry:" + domain.rawValue)
            default: XCTFail("Unexpected preference domain")
            }
            _ = await state.perform(command)
            revision += 1
            observed?.update(self.fixture(state, revision: revision))
        }
        observed = controller
        defer { controller.closeForTeardown() }
        controller.update(fixture(state))
        for _ in 0..<2 { try button(controller, "onboarding.next").performClick(nil) }
        try button(controller, "onboarding.placement.rightBottom").performClick(nil)
        await assertReceived { state.snapshot.domains[.placement]?.saveFailure != nil }
        // The closure also publishes the receipt before returning to the view.
        await assertReceived { (controller.control(identifier: "onboarding.retryPlacement") as? NSButton)?.isEnabled == true }
        XCTAssertEqual(state.snapshot.owner.settings.configuration.placement, .leftMiddle)
        XCTAssertTrue(try XCTUnwrap(controller.control(identifier: "onboarding.display") as? NSPopUpButton).isEnabled)
        let retry = try button(controller, "onboarding.retryPlacement")
        XCTAssertFalse(retry.isHidden)
        retry.performClick(nil)
        await assertReceived { commands.count == 2 }
        XCTAssertEqual(commands, ["rightBottom", "retry:placement"])
        XCTAssertEqual(state.snapshot.domains[.placement]?.pending, .placement(.rightBottom))
    }

    @MainActor func testDisconnectedSelectedDisplayAndOldSnapshotCannotChangePreference() throws {
        try prepareAppKit()
        var configuration = RiftConfiguration()
        configuration.preferredDisplayID = 99; configuration.preferredDisplayUUID = Self.disconnectedDisplayUUID
        try configuration.validate()
        let state = try model(configuration: configuration)
        let controller = RiftOnboardingController { _ in XCTFail("A refresh cannot save a fallback") }
        defer { controller.closeForTeardown() }
        controller.update(fixture(state, revision: 4))
        let display = try XCTUnwrap(controller.control(identifier: "onboarding.display") as? NSPopUpButton)
        XCTAssertEqual(display.titleOfSelectedItem, "已选显示器（未连接）")
        XCTAssertFalse(try XCTUnwrap(display.selectedItem).isEnabled)
        controller.update(fixture(try model(), revision: 3))
        XCTAssertEqual(display.titleOfSelectedItem, "已选显示器（未连接）")
        XCTAssertEqual(state.snapshot.owner.settings.configuration.preferredDisplayUUID, Self.disconnectedDisplayUUID)
    }

    @MainActor func testBackAndForwardKeepSameNativeControlsAndAccessibleNames() throws {
        try prepareAppKit()
        let controller = RiftOnboardingController { _ in XCTFail("Navigation cannot run a host command") }
        defer { controller.closeForTeardown() }
        controller.update(fixture(try model()))
        let display = try XCTUnwrap(controller.control(identifier: "onboarding.display"))
        let placement = try button(controller, "onboarding.placement.leftTop")
        let next = try button(controller, "onboarding.next")
        next.performClick(nil); next.performClick(nil)
        XCTAssertEqual(controller.currentStep, 2)
        try button(controller, "onboarding.back").performClick(nil)
        XCTAssertEqual(controller.currentStep, 1)
        next.performClick(nil)
        XCTAssertTrue(display === controller.control(identifier: "onboarding.display"))
        XCTAssertTrue(placement === controller.control(identifier: "onboarding.placement.leftTop"))
        XCTAssertEqual(placement.accessibilityLabel(), "桌面位置：左上")
        XCTAssertEqual((display as? NSPopUpButton)?.accessibilityLabel(), "所在显示器")
        XCTAssertEqual(try button(controller, "onboarding.later").keyEquivalent, "\u{1b}")
    }

    @MainActor func testDuplicateDisplayNamesKeepDistinctNativeItemIdentities() async throws {
        try prepareAppKit()
        let state = try model(displays: [.init(id: 1, name: "Studio Display", uuid: Self.mainDisplayUUID),
                                         .init(id: 2, name: "Studio Display", uuid: Self.externalDisplayUUID)])
        var selected: [UInt32?] = []
        let controller = RiftOnboardingController { action in
            if case .settings(.selectDisplay(let id)) = action { selected.append(id) }
            else { XCTFail("Unexpected command") }
        }
        defer { controller.closeForTeardown() }
        controller.update(fixture(state))
        let display = try XCTUnwrap(controller.control(identifier: "onboarding.display") as? NSPopUpButton)
        XCTAssertEqual(display.numberOfItems, 3)
        XCTAssertEqual(display.itemTitle(at: 1), display.itemTitle(at: 2))
        XCTAssertEqual((display.item(at: 1)?.representedObject as? NSNumber)?.uint32Value, 1)
        XCTAssertEqual((display.item(at: 2)?.representedObject as? NSNumber)?.uint32Value, 2)
        display.selectItem(at: 2)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(display.action), to: display.target, from: display))
        await assertReceived { selected.count == 1 }
        XCTAssertEqual(selected, [2])
    }

    @MainActor func testDisplayTrackingDefersRefreshUntilChosenNativeItemHasDispatched() async throws {
        try prepareAppKit()
        let state = try model()
        var selected: [UInt32?] = []
        let controller = RiftOnboardingController { action in
            if case .settings(.selectDisplay(let id)) = action { selected.append(id) }
        }
        defer { controller.closeForTeardown() }
        controller.update(fixture(state))
        let display = try XCTUnwrap(controller.control(identifier: "onboarding.display") as? NSPopUpButton)
        let menu = try XCTUnwrap(display.menu)
        let selectedItem = try XCTUnwrap(display.item(at: 2))
        controller.menuWillOpen(menu)
        let changed = try model(revision: 2, displays: [.init(id: 1, name: "合成内建屏", uuid: Self.mainDisplayUUID)])
        controller.update(fixture(changed, revision: 2))
        XCTAssertEqual(display.numberOfItems, 3)
        XCTAssertTrue(display.item(at: 2) === selectedItem)
        display.select(selectedItem)
        controller.menuDidClose(menu)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(display.action), to: display.target, from: display))
        await assertReceived { selected.count == 1 }
        XCTAssertEqual(selected, [2], "The original item identity reaches the host, which validates current availability")
        await assertReceived { display.numberOfItems == 2 }
    }
}
