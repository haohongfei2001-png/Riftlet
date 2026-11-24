import AppKit
import XCTest
import RiftletCapture
@testable import RiftletUI

/// Native AppKit objects and synthetic owners. These tests do not request OS
/// permission, register a login item, read a screenshot or drive a real browser.
final class RiftSettingsCenterTests: XCTestCase {
    @MainActor private func host() throws -> SettingsCenterTestHost {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer unavailable; native settings interaction NOT_RUN") }
        return try SettingsCenterTestHost()
    }
    private enum WaitFailure: Error { case deadline }
    @MainActor private func waitFor(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                                   _ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                XCTFail("Timed out waiting for " + description, file: file, line: line)
                throw WaitFailure.deadline
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
    @MainActor private func actionAndWait(_ host: SettingsCenterTestHost, file: StaticString = #filePath, line: UInt = #line,
                                          _ action: () throws -> Void) async throws {
        let expected = host.startedActions + 1
        try action()
        try await waitFor("native host action \(expected) completion", file: file, line: line) { host.completedActions.contains(expected) }
    }
    @MainActor private func clickAndWait(_ host: SettingsCenterTestHost, _ id: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        try await actionAndWait(host, file: file, line: line) { try click(host, id) }
    }
    @MainActor private func changeAndWait(_ host: SettingsCenterTestHost, _ id: String, index: Int,
                                         file: StaticString = #filePath, line: UInt = #line) async throws {
        try await actionAndWait(host, file: file, line: line) { try change(host, id, index: index) }
    }
    @MainActor private func control<T: NSControl>(_ host: SettingsCenterTestHost, _ id: String, as type: T.Type = T.self) throws -> T {
        try XCTUnwrap(host.controller.controls[id] as? T)
    }
    @MainActor private func click(_ host: SettingsCenterTestHost, _ id: String) throws {
        if let toggle = host.controller.controls[id] as? NSSwitch {
            // The native switch action receives its newly selected state. This
            // is an AppKit action test; physical mouse routing is separate.
            guard toggle.isEnabled else { return }
            toggle.state = toggle.state == .on ? .off : .on
            XCTAssertTrue(toggle.sendAction(toggle.action, to: toggle.target))
        } else {
            let button: NSButton = try control(host, id)
            button.performClick(nil)
        }
    }
    @MainActor private func change(_ host: SettingsCenterTestHost, _ id: String, index: Int) throws {
        if let control = host.controller.controls[id] as? NSSegmentedControl {
            control.selectedSegment = index
            XCTAssertTrue(control.sendAction(control.action,to:control.target))
            return
        }
        let popup: NSPopUpButton = try control(host, id)
        popup.selectItem(at: index)
        _ = popup.sendAction(popup.action, to: popup.target)
    }
    @MainActor private func answerClose(_ host: SettingsCenterTestHost, _ response: NSApplication.ModalResponse,
                                       remainsOpen: Bool = false) async throws {
        let alert = try XCTUnwrap(host.controller.pendingCloseAlert)
        let expected = host.startedActions + 1
        alert.window.animationBehavior = .none
        let index = response == .alertSecondButtonReturn ? 1 : response == .alertThirdButtonReturn ? 2 : 0
        XCTAssertTrue(alert.buttons[index].isEnabled)
        alert.buttons[index].performClick(nil)
        if response == .alertSecondButtonReturn || response == .alertThirdButtonReturn {
            try await waitFor("sheet action \(expected) completion") { host.completedActions.contains(expected) }
        }
        if remainsOpen {
            try await waitFor("failed decision remains actionable in the same sheet") {
                host.controller.pendingCloseAlert === alert && alert.buttons[2].isEnabled
            }
            XCTAssertTrue(host.controller.window.attachedSheet === alert.window)
        } else {
            try await waitFor("native sheet completion") { host.controller.pendingCloseAlert == nil }
            XCTAssertNil(host.controller.pendingCloseAlert, "Native sheet completion must arrive before asserting the selected outcome")
        }
    }

    @MainActor func testFourPagesAndLegacyDeepLinksShareOneWindowAndViewingNeverPersists() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        let window = h.controller.window
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertEqual(SettingsPage.allCases, [.general, .display, .capture, .help])
        XCTAssertEqual(h.controller.navigation.count, 4)
        for page in SettingsPage.allCases {
            h.controller.show(page: page)
            XCTAssertTrue(h.controller.window === window)
            XCTAssertEqual(h.controller.selectedPage, page)
            XCTAssertTrue(h.controller.scroll.documentView === h.controller.pages[page])
        }
        h.controller.show(page:.motion)
        XCTAssertEqual(h.controller.selectedPage,.display)
        XCTAssertFalse(try XCTUnwrap(h.controller.disclosures["display.advanced"]?.content).isHidden)
        h.controller.show(page:.history)
        XCTAssertEqual(h.controller.selectedPage,.capture)
        h.publish()
        XCTAssertTrue(h.actions.isEmpty)
        XCTAssertTrue(h.requests.isEmpty)
        h.controller.closeForTeardown(); h.publish()
        XCTAssertFalse(h.controller.isVisible, "Background updates do not open a closed settings window")
    }

    @MainActor func testFourPagesExposeWorkingControlsInTheirPrimaryLocation() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show()
        XCTAssertEqual(h.controller.selectedPage, .general)
        for id in ["login", "updates.check", "updates.automatic"] {
            let view = try XCTUnwrap(h.controller.controls[id])
            XCTAssertTrue(view.window === h.controller.window)
            XCTAssertFalse(view.isHiddenOrHasHiddenAncestor)
        }
        XCTAssertTrue(h.controller.labels["version"]?.window === h.controller.window)
        h.controller.show(page: .display)
        for id in ["appearance", "desktop.visible"] {
            XCTAssertTrue(h.controller.controls[id]?.window === h.controller.window)
        }
        for moved in ["paused", "hidden", "history.displayStyle", "configuration.open", "configuration.reload"] {
            XCTAssertNil(h.controller.controls[moved])
        }
        h.controller.show(page: .capture)
        let entry: NSSwitch = try control(h, "entry")
        XCTAssertEqual(entry.accessibilityLabel(), ProductCopy.text("显示内置截图入口", "Show Capture Button"))
        XCTAssertEqual(entry.state, .on)
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testScreenshotFolderShowsItsLocationAndPreservesTheFullPathAtMinimumWidth() throws {
        let h = try host()
        defer { h.controller.closeForTeardown() }
        var snapshot = h.controller.product
        let path = NSHomeDirectory() + "/Pictures/" + String(repeating: "Example Folder/", count: 20) + "Screenshots"
        snapshot.setup = .init(sourceLocation: path, source: .accessible, collection: .collecting)
        h.controller.update(snapshot)
        h.controller.show(page: .capture)
        h.controller.window.setContentSize(SettingsNativeStyle.settingsMinimumSize)
        h.controller.window.contentView?.layoutSubtreeIfNeeded()
        let folder = try XCTUnwrap(h.controller.labels["sourcePath.capture"])
        XCTAssertEqual(folder.stringValue, (path as NSString).abbreviatingWithTildeInPath)
        XCTAssertEqual(folder.toolTip, path)
        XCTAssertEqual(folder.lineBreakMode, .byTruncatingMiddle)
        let open = try XCTUnwrap(h.controller.controls["source.open.capture"])
        let clip = h.controller.scroll.contentView
        XCTAssertTrue(clip.bounds.contains(open.convert(open.bounds, to: clip)))
        XCTAssertLessThanOrEqual(folder.bounds.width, clip.bounds.width)
    }

    @MainActor func testFolderFailureNeedsRecoveryWhileAnIndividualFileIssueStaysInScreenshotSettings() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        for issue in [SetupIssue.sourceVolumeUnidentified, .fileVolumeUnidentified, .historicalSourceUnconfirmed] {
            h.revision += 1
            let setup = SetupSnapshot(sourceLocation: "/synthetic/screenshots", source: .accessible,
                                      collection: .collecting, issue: issue)
            let snapshot = SettingsProductSnapshot(revision: h.revision, setup: setup, state: h.model.snapshot)
            h.controller.update(snapshot)
            let status = RiftControlCenterPresentation(snapshot)
            let setupView = SetupPresentation(snapshot: setup)
            if issue == .sourceVolumeUnidentified {
                XCTAssertEqual(status.state, .attention)
                XCTAssertEqual(status.recoveryPage, .capture)
                XCTAssertEqual(status.title, ProductCopy.text("当前截图位置无法收录", "Can’t Collect from This Location"))
                XCTAssertEqual(status.detail, issue.text)
                XCTAssertEqual(setupView.collectionText, issue.text)
            } else {
                XCTAssertEqual(status.state, .collecting)
                XCTAssertNil(status.recovery(snapshot))
                XCTAssertEqual(setupView.collectionText, ProductCopy.text("正在收录新截图。", "Collecting new screenshots."))
            }
            let source = try XCTUnwrap(h.controller.labels["source.capture"])
            XCTAssertFalse(source.isHidden)
            XCTAssertEqual(source.stringValue, issue.text)
            XCTAssertNil(h.controller.labels["source.help"])
        }
    }

    @MainActor func testChromeJavaScriptRefusalShowsRecoveryAndKeepsMacAutomationGranted() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var snapshot = h.controller.product
        snapshot.setup = .init(source: .accessible, collection: .collecting, attachment: .available,
                               permission: .granted, permissionDetail: ChromeAttachmentSetup.instructions, issue: .chromeJavaScriptDisabled)
        h.controller.update(snapshot)
        let attachment = try XCTUnwrap(h.controller.labels["attachment"])
        let automation = try XCTUnwrap(h.controller.labels["automation"])
        XCTAssertEqual(h.controller.labels["access.chrome"]?.stringValue, ProductCopy.text("需开启 JavaScript", "Enable JavaScript"))
        XCTAssertEqual(h.controller.labels["chrome.menu"]?.isHidden, true, "Recovery already contains the path")
        let expected = ProductCopy.text("Chrome 拒绝了这次附加，截图仍在本机。", "Chrome declined the attachment. The screenshot is saved on your Mac. ") + ChromeAttachmentSetup.instructions
        XCTAssertEqual(attachment.stringValue, expected)
        XCTAssertEqual(RiftControlCenterPresentation(snapshot).detail, expected)
        XCTAssertEqual(automation.stringValue, ProductCopy.text("macOS 已允许 Riftlet 与 Chrome 通信。", "macOS allows Riftlet to communicate with Chrome."))
        XCTAssertTrue(h.actions.isEmpty)

        snapshot.setup = .init(attachment: .productionDisabled, issue: .chromeJavaScriptDisabled)
        h.controller.update(snapshot)
        XCTAssertFalse(attachment.stringValue.contains("JavaScript"))
        XCTAssertNil(SetupPresentation(snapshot: snapshot.setup).issueText)
    }

    @MainActor func testCaptureLocationLinkOpensDetailsAndOnlyOffersAccessWhenNeeded() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var snapshot = h.controller.product
        snapshot.setup = .init(sourceLocation: "/fixture/shots", source: .accessible, issue: .imageUnavailable)
        h.controller.update(snapshot)
        h.controller.show(page: .capture)
        let captureAccess: NSButton = try control(h, "source.access.capture")
        XCTAssertTrue(captureAccess.isHidden)
        h.controller.show(page: .help)
        try click(h, "disclosure.diagnostics")
        let verifyMedia: NSButton = try control(h, "storage.recheckMedia")
        XCTAssertFalse(verifyMedia.isHiddenOrHasHiddenAncestor, "A working screenshot folder must not hide private-copy recovery")
        XCTAssertTrue(verifyMedia.isEnabled)

        h.controller.show(page: .capture)
        XCTAssertNil(h.controller.controls["source.access.help"])
        snapshot.setup = .init(sourceLocation: "/fixture/shots", source: .accessible, issue: .screenshotFolderNeedsSelection)
        h.controller.update(snapshot)
        XCTAssertEqual(h.controller.selectedPage, .capture)
        XCTAssertFalse(captureAccess.isHidden)
        XCTAssertTrue(captureAccess.isEnabled)
        XCTAssertEqual(captureAccess.title, ProductCopy.text("允许访问截图文件夹…", "Allow Screenshot Folder Access…"))
        let recheck: NSButton = try control(h, "source.recheck.capture")
        XCTAssertTrue(recheck.isHidden, "Only the relevant folder authorization action is offered")
        XCTAssertTrue(h.actions.isEmpty)
    }

    @MainActor func testChromeCheckUsesCurrentPermissionAndRequiresExplicitAction() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var snapshot = h.controller.product
        snapshot.setup = .init(attachment: .available, permission: .granted,
                               permissionDetail: ChromeAttachmentSetup.instructions)
        snapshot.capabilities.canRequestAutomation = true
        h.controller.update(snapshot)
        h.controller.show(page: .help)
        let check: NSButton = try control(h, "chrome.check")
        let grant: NSButton = try control(h, "automation.request")
        XCTAssertTrue(grant.isHidden)
        XCTAssertFalse(check.isHidden)
        XCTAssertTrue(check.isEnabled)
        XCTAssertEqual(h.controller.labels["access.chrome"]?.stringValue, ProductCopy.text("待检查连接", "Connection Not Checked"))
        XCTAssertTrue(h.actions.isEmpty)
        try await clickAndWait(h, "chrome.check")
        XCTAssertEqual(h.actions, ["checkChromeConnection"])

        snapshot.revision = h.controller.product.revision
        snapshot.chromeConnection = .checking
        h.controller.update(snapshot)
        XCTAssertFalse(check.isEnabled)
        snapshot.chromeConnection = .javaScriptDisabled
        snapshot.setup = .init(attachment: .available, permission: .granted)
        h.controller.update(snapshot)
        XCTAssertEqual(h.controller.labels["attachment"]?.isHidden, true)
        XCTAssertEqual(h.controller.labels["chrome.menu"]?.isHidden, false)
        XCTAssertTrue(h.controller.labels["chrome.menu"]?.stringValue.contains(ChromeAttachmentSetup.menuPath) == true)
        snapshot.chromeConnection = .ready
        h.controller.update(snapshot)
        XCTAssertEqual(h.controller.labels["attachment"]?.isHidden, true)
        XCTAssertEqual(h.controller.labels["access.chrome"]?.stringValue, ProductCopy.text("已连接", "Connected"))
        snapshot.setup = .init(attachment: .available, permission: .denied)
        h.controller.update(snapshot)
        XCTAssertEqual(h.controller.labels["access.chrome"]?.stringValue, ProductCopy.text("需要授权", "Access Needed"))
        XCTAssertTrue(check.isHidden)
        XCTAssertFalse(grant.isHidden)
    }

    @MainActor func testAppearanceApplyFailureKeepsItsReasonAndRetryTarget() throws {
        let h = try host()
        defer { h.controller.closeForTeardown() }
        var snapshot = h.controller.product
        snapshot.appearance.available = true
        snapshot.appearance.applied = .dark
        snapshot.appearance.selection = .dark
        snapshot.appearance.pending = .light
        snapshot.appearance.failure = "暂时无法应用这个外观。"
        h.controller.update(snapshot)
        let reason = try XCTUnwrap(h.controller.labels["appearance.detail"])
        let retry: NSButton = try control(h, "appearance.retry")
        XCTAssertFalse(reason.isHidden)
        XCTAssertEqual(reason.stringValue, snapshot.appearance.failure)
        XCTAssertFalse(retry.isHidden)
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(h.controller.product.appearance.pending, .light)
    }

    @MainActor func testMotionAndHistoryNotesFollowSystemAndAttachmentState() throws {
        let h = try host()
        defer { h.controller.closeForTeardown() }
        let motion = try XCTUnwrap(h.controller.labels["motion.detail"])
        let history = try XCTUnwrap(h.controller.labels["history.detail"])
        var snapshot = h.controller.product
        snapshot.setup = .init(pendingCount: 0)
        snapshot.accessibility.reduceMotion = false
        h.controller.update(snapshot)
        XCTAssertTrue(motion.isHidden)
        XCTAssertTrue(history.isHidden)

        snapshot.setup = .init(pendingCount: 2)
        snapshot.accessibility.reduceMotion = true
        h.controller.update(snapshot)
        XCTAssertFalse(motion.isHidden)
        XCTAssertTrue(motion.stringValue.contains(ProductCopy.text("减少动态效果", "Reduce Motion")))
        XCTAssertFalse(history.isHidden)
        XCTAssertTrue(history.stringValue.contains(ProductCopy.text("2 张", "2 screenshot")))
        XCTAssertTrue(history.stringValue.contains(ProductCopy.text("不会自动重传", "won’t retry them automatically")))

        snapshot.setup = .init(pendingCount: 0)
        snapshot.accessibility.reduceMotion = false
        h.controller.update(snapshot)
        XCTAssertTrue(motion.isHidden)
        XCTAssertTrue(history.isHidden)
        XCTAssertTrue(h.actions.isEmpty)
    }

    @MainActor func testFirstShowRestoresV2ContentSizeAndLaterShowsKeepUserResize() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        let window = h.controller.window
        let visible = try XCTUnwrap((window.screen ?? NSScreen.main)?.visibleFrame)
        let available = window.contentRect(forFrameRect: visible).size
        let expected = NSSize(width: min(640, available.width), height: min(560, available.height))
        h.controller.show()
        window.contentView?.layoutSubtreeIfNeeded()
        let actual = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(window.frame.minX, visible.minX - 0.5)
        XCTAssertLessThanOrEqual(window.frame.maxX, visible.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(window.frame.minY, visible.minY - 0.5)
        XCTAssertLessThanOrEqual(window.frame.maxY, visible.maxY + 0.5)
        let smaller = NSSize(width: max(600, expected.width - 40), height: max(460, expected.height - 30))
        window.setContentSize(smaller)
        let resized = window.frame.size
        h.publish(); h.controller.show(page: .capture)
        XCTAssertEqual(window.frame.size.width, resized.width, accuracy: 0.5)
        XCTAssertEqual(window.frame.size.height, resized.height, accuracy: 0.5)
    }

    @MainActor func testFirstPresentationFrameFitsSmallAndOffsetScreens() {
        let proposed = NSRect(x: 0, y: 0, width: 960, height: 706)
        let compact = NSRect(x: -800, y: 40, width: 800, height: 600)
        XCTAssertEqual(RiftSettingsCenterController.firstPresentationFrame(proposed, visibleFrame: compact), compact)
        let large = NSRect(x: 1200, y: -30, width: 1600, height: 1000)
        let frame = RiftSettingsCenterController.firstPresentationFrame(proposed, visibleFrame: large)
        XCTAssertEqual(frame.size, proposed.size)
        XCTAssertEqual(frame.midX, large.midX); XCTAssertEqual(frame.midY, large.midY)
    }

    @MainActor func testInlinePreviewAndEdgePickerStayAccessibleAtCompactWidth() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        let document = try XCTUnwrap(h.controller.pages[.display])
        let picker: NSPopUpButton = try control(h, "placement")
        for size in [SettingsNativeStyle.settingsSize, SettingsNativeStyle.settingsMinimumSize] {
            h.controller.window.setContentSize(size)
            for placement in RiftPlacement.allCases {
                var settings = h.owner.settings
                settings.configuration.placement = placement
                h.receive(settings)
                h.controller.window.contentView?.layoutSubtreeIfNeeded()
                let preview = h.controller.geometryPreview
                XCTAssertEqual(preview.bounds.height, 140, accuracy: 1)
                XCTAssertEqual(preview.accessibilityValue() as? String, preview.geometrySummary)
                XCTAssertTrue(preview.geometrySummary.hasPrefix(placement.title))
                XCTAssertEqual(picker.titleOfSelectedItem, placement.title)
                XCTAssertFalse(picker.convert(picker.bounds, to: document).intersects(preview.convert(preview.bounds, to: document)))
            }
            picker.scrollToVisible(picker.bounds)
            let clip = h.controller.scroll.contentView
            XCTAssertTrue(clip.bounds.insetBy(dx: -1, dy: -1).contains(picker.convert(picker.bounds, to: clip)))
            XCTAssertEqual(picker.itemArray.filter { !$0.isHidden }.map(\.title), RiftPlacement.allCases.map(\.title))
            XCTAssertEqual(picker.accessibilityLabel(), ProductCopy.text("屏幕边缘", "Screen Edge"))
        }
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testPlacementHasOneVisibleCheckmarkAndFailureKeepsConfirmedSelection() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        func assertSelection(_ expected: RiftPlacement) throws {
            XCTAssertEqual(h.controller.geometryPreview.configuration.placement, expected)
            XCTAssertTrue(h.controller.geometryPreview.geometrySummary.hasPrefix(expected.title + " · "))
            let picker: NSPopUpButton = try control(h,"placement")
            let index = try XCTUnwrap(RiftPlacement.allCases.firstIndex(of: expected))
            XCTAssertEqual(picker.selectedItem?.identifier?.rawValue, "settings.center.placement." + expected.rawValue)
            XCTAssertEqual(picker.indexOfSelectedItem, index)
            XCTAssertEqual(picker.titleOfSelectedItem,expected.title)
        }
        for (index, placement) in RiftPlacement.allCases.enumerated() {
            try await changeAndWait(h, "placement", index:index)
            XCTAssertEqual(h.owner.settings.configuration.placement, placement)
            try assertSelection(placement)
        }
        let confirmed = try XCTUnwrap(h.owner.settings.configuration.placement)
        let pending: RiftPlacement = confirmed == .leftMiddle ? .rightMiddle : .leftMiddle
        h.failures = [.placement]
        try await changeAndWait(h, "placement", index: try XCTUnwrap(RiftPlacement.allCases.firstIndex(of: pending)))
        try assertSelection(confirmed)
        XCTAssertTrue(h.model.snapshot.domains[.placement]!.hasIssue)
        h.failures = []
        try await clickAndWait(h, "retry.placement")
        try assertSelection(pending)
        XCTAssertFalse(h.model.snapshot.domains[.placement]!.hasIssue)
    }

    @MainActor func testRecommendedAppearanceAndUndoPreserveUnrelatedChoices() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var settings = h.owner.settings
        settings.configuration.outerInset = 22
        settings.archiveAfterMinutes = 1.75
        h.receive(settings)
        h.controller.show(page: .display)
        try await clickAndWait(h, "layout.defaults.display")
        XCTAssertEqual(h.owner.settings.configuration.outerInset, RiftConfiguration().outerInset)
        XCTAssertNil(h.controller.window.attachedSheet)
        try await clickAndWait(h, "layout.defaults.display")
        XCTAssertEqual(h.owner.settings.configuration.outerInset, 22)
        XCTAssertEqual(h.owner.settings.archiveAfterMinutes, 1.75)
        XCTAssertEqual(h.owner.settings.configuration.desktopForm, settings.configuration.desktopForm)
    }

    @MainActor func testTrayShowsActualCapacityAndKeepsStoredCountOnOtherEditsAndSwitches() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var settings = h.owner.settings
        settings.configuration.visibleCountPreference = 10
        settings.configuration.desktopForm = .tray
        h.receive(settings)
        h.controller.show(page: .display)
        try click(h, "disclosure.display.advanced")
        let picker: NSPopUpButton = try control(h, "count")
        XCTAssertEqual(picker.itemTitles, ["1", "2", "3", "4"])
        XCTAssertEqual(picker.titleOfSelectedItem, "4")
        XCTAssertEqual(h.controller.geometryPreview.configuration.visibleCountPreference, 4)
        XCTAssertTrue(!h.controller.controls.keys.contains(where: { $0.hasPrefix("field.") }))
        XCTAssertTrue(h.requests.isEmpty)
        try await changeAndWait(h, "desktopForm", index: RiftDesktopForm.allCases.firstIndex(of: .microSlit)!)
        XCTAssertEqual(h.owner.settings.configuration.visibleCountPreference, 10)
        XCTAssertEqual(Int(picker.titleOfSelectedItem ?? ""), min(10,h.controller.countCapacity(h.model.snapshot.owner)))
    }

    @MainActor func testWindChimeArrangementControlTracksFormAndOwner() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        let form: NSSegmentedControl = try control(h, "desktopForm")
        let arrangement: NSSegmentedControl = try control(h, "windChimeArrangement")
        XCTAssertTrue(form.isEnabled(forSegment: 1))
        XCTAssertTrue(h.controller.windChimeSettings.isHidden)
        try await changeAndWait(h, "desktopForm", index: 1)
        XCTAssertFalse(h.controller.windChimeSettings.isHidden)
        XCTAssertTrue(h.controller.geometryPreview.geometrySummary.hasSuffix(ProductCopy.text("风铃 · 错落", "Wind Chime · Staggered")))
        XCTAssertNil(h.controller.controls["field.windChimeLineInset"])
        XCTAssertEqual(arrangement.accessibilityLabel(), ProductCopy.text("风铃排列", "Wind Chime Layout"))
        XCTAssertEqual(arrangement.label(forSegment: arrangement.selectedSegment), ProductCopy.text("错落", "Staggered"))
        try await changeAndWait(h, "windChimeArrangement", index: 0)
        XCTAssertEqual(h.owner.settings.configuration.windChimeArrangement, .aligned)
        XCTAssertTrue(h.controller.geometryPreview.geometrySummary.hasSuffix(ProductCopy.text("风铃 · 整齐", "Wind Chime · Aligned")))
        var updated = h.owner.settings
        updated.configuration.windChimeArrangement = .staggered
        h.receive(updated)
        XCTAssertEqual(arrangement.selectedSegment, 1)
        try await changeAndWait(h, "desktopForm", index: 0)
        XCTAssertTrue(h.controller.windChimeSettings.isHidden)
        XCTAssertEqual(h.owner.settings.configuration.windChimeArrangement, .staggered)
    }

    @MainActor func testSettingsAndFirstUseDrawDistinctWindChimeArrangementsAtFractionalScale() throws {
        // The native sample views project a fractional number of display points.
        // A right-edge drawing once lost every row when its window bounds rounded outwards.
        let settings = RiftSettingsCenterPreview()
        settings.frame = CGRect(x: 0, y: 0, width: 524, height: 115)
        let onboarding = RiftOnboardingPlacementPreview()
        onboarding.frame = CGRect(x: 0, y: 0, width: 466, height: 103)
        func raster(_ view: NSView) throws -> Data {
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        for side in [RiftPlacement.leftMiddle, .rightMiddle] {
            var config = RiftConfiguration()
            config.desktopForm = .windChime
            config.placement = side
            config.windChimeArrangement = .aligned
            settings.update(configuration: config)
            onboarding.configuration = config
            let alignedSettings = try raster(settings)
            let alignedOnboarding = try raster(onboarding)
            config.windChimeArrangement = .staggered
            settings.update(configuration: config)
            onboarding.configuration = config
            XCTAssertNotEqual(try raster(settings), alignedSettings, "Settings sample must visibly change: \(side)")
            XCTAssertNotEqual(try raster(onboarding), alignedOnboarding, "First-use sample must visibly change: \(side)")
        }
    }

    @MainActor func testTrayFavoritePickersKeepOrderAndUpdateAutomaticLabelsOnOwnerRefresh() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var settings = h.owner.settings
        settings.configuration.desktopForm = .tray
        settings.defaultCaptureMode = .window
        h.receive(settings)
        h.controller.show(page: .display)
        h.controller.show(page:.capture)
        try click(h, "disclosure.tray.favorites")
        let first: NSPopUpButton = try control(h, "trayFavorite1")
        let third: NSPopUpButton = try control(h, "trayFavorite3")
        XCTAssertEqual(first.titleOfSelectedItem, ProductCopy.text("自动（区域）", "Automatic (Area)"))
        XCTAssertEqual(third.titleOfSelectedItem, ProductCopy.text("自动（留空）", "Automatic (Empty)"))
        XCTAssertEqual(third.accessibilityLabel(), ProductCopy.text("常用键 3", "Favorite 3"))
        XCTAssertFalse(third.itemTitles.contains("更多"))
        let custom = try XCTUnwrap(RiftTrayFavoriteChoice.menuChoices.firstIndex(of: .mode(.window)))
        try await changeAndWait(h, "trayFavorite3", index: custom)
        XCTAssertEqual(h.owner.settings.configuration.trayFavorite(.third), .mode(.window))
        settings = h.owner.settings
        settings.defaultCaptureMode = .region
        h.receive(settings)
        XCTAssertTrue(h.controller.controls["trayFavorite1"] === first)
        XCTAssertTrue(h.controller.controls["trayFavorite3"] === third)
        XCTAssertEqual(first.titleOfSelectedItem, ProductCopy.text("自动（窗口）", "Automatic (Window)"))
        XCTAssertEqual(third.titleOfSelectedItem, ProductCopy.text("窗口", "Window"))
    }

    @MainActor func testExplicitDefaultsAffectOnlyCurrentPublicNumbers() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var settings = h.owner.settings
        settings.configuration.outerInset = 12
        settings.configuration.fitWidth = 101
        settings.configuration.trayOcclusion = 0.54
        h.receive(settings)
        h.controller.show(page: .display)
        _ = await h.model.perform(.restoreVisibleDefaults)
        XCTAssertEqual(h.owner.settings.configuration.outerInset, 6)
        XCTAssertEqual(h.owner.settings.configuration.fitWidth, 101)
        XCTAssertEqual(h.owner.settings.configuration.trayOcclusion, 0.54)
        XCTAssertNil(h.controller.controls["layout.apply.display"])
        XCTAssertNil(h.controller.controls["archive.save"])
    }

    @MainActor func testInheritedFractionalArchiveIsShownUntilANewPresetIsChosen() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var settings = h.owner.settings
        settings.archiveAfterMinutes = 1.75
        h.receive(settings)
        h.controller.show(page: .capture)
        let preset: NSPopUpButton = try control(h, "archive.preset")
        XCTAssertEqual(preset.indexOfSelectedItem, 5)
        XCTAssertTrue(preset.titleOfSelectedItem?.contains(SettingsStateModel.archiveMinutesText(1.75, decimalSeparator: Locale.current.decimalSeparator ?? ".")) == true)
        XCTAssertFalse(preset.lastItem!.isEnabled)
        XCTAssertTrue(h.requests.isEmpty)
        h.controller.window.performClose(nil)
        XCTAssertNil(h.controller.pendingCloseAlert)
        h.controller.show(page: .capture)
        try await changeAndWait(h, "archive.preset", index: 3)
        XCTAssertEqual(h.owner.settings.archiveAfterMinutes, 5)
        XCTAssertTrue(preset.lastItem!.isHidden)
        try await changeAndWait(h, "archive.preset", index: 0)
        XCTAssertNil(h.owner.settings.archiveAfterMinutes)
        XCTAssertNil(h.controller.controls["archive.minutes"])
    }

    @MainActor func testCloseEscapeDoesNotReopenOrMutateDraftAfterTeardown() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history); h.model.setArchiveDraftText("1")
        h.controller.window.performClose(nil)
        let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
        let previousResponder = alert.window.nextResponder
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: alert.window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        h.controller.closeForTeardown()
        XCTAssertTrue(alert.window.nextResponder === previousResponder)
        NSApp.sendEvent(escape)
        XCTAssertNil(h.controller.pendingCloseAlert)
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertTrue(h.model.hasArchiveDraft)
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testCloseEscapeIgnoresModifiersOtherKeysAndOtherWindows() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history); h.model.setArchiveDraftText("1")
        h.controller.window.performClose(nil)
        let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
        let cases: [(NSWindow, NSEvent.ModifierFlags, UInt16, String)] = [
            (alert.window, .command, 53, "\u{1b}"),
            (alert.window, .control, 53, "\u{1b}"),
            (alert.window, .option, 53, "\u{1b}"),
            (alert.window, .shift, 53, "\u{1b}"),
            (alert.window, [], 0, "a"),
            (h.controller.window, [], 53, "\u{1b}")
        ]
        for (window, modifiers, code, characters) in cases {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            NSApp.sendEvent(event)
            XCTAssertTrue(h.controller.pendingCloseAlert === alert)
            XCTAssertTrue(h.controller.window.attachedSheet === alert.window)
        }
        XCTAssertEqual(h.model.archiveDraftText, "1")
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testApplyAndCloseWaitsForActualConfirmation() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        h.model.setArchiveDraftText("1")
        h.controller.window.performClose(nil)
        try await answerClose(h, .alertThirdButtonReturn)
        XCTAssertEqual(h.owner.settings.archiveAfterMinutes, 1)
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertEqual(h.requests.count, 1)
    }

    @MainActor func testFailedApplyAndCloseRetainsWindowAndDraft() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.failures = [.archive]
        h.controller.show(page: .history)
        h.model.setArchiveDraftText("1")
        h.controller.window.performClose(nil)
        try await answerClose(h, .alertThirdButtonReturn, remainsOpen: true)
        XCTAssertTrue(h.controller.isVisible)
        XCTAssertEqual(h.model.archiveDraftText, "1")
        XCTAssertTrue(h.model.snapshot.domains[.archive]?.hasIssue == true)
        XCTAssertFalse(h.controller.errorRows[.archive]!.isHidden)
    }

    @MainActor func testDiscardCloseDoesNotClearImmediateDomainErrorOrWrite() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.failures = [.collection]
        _ = await h.model.perform(.setCollectionPaused(true))
        h.controller.show(page: .history)
        h.model.setArchiveDraftText("1")
        h.controller.window.performClose(nil)
        try await answerClose(h, .alertSecondButtonReturn)
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertFalse(h.model.hasArchiveDraft)
        XCTAssertTrue(h.model.snapshot.domains[.collection]?.hasIssue == true)
        XCTAssertEqual(h.requests.map(\.intent), [.collectionPaused(true)])
    }

    @MainActor func testPartialCloseSaveDoesNotRepeatSuccessfulDomain() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.failures = [.archive]
        h.model.setDraftText("81", for: .fitWidth)
        h.model.setArchiveDraftText("8")
        h.controller.show(page: .history)
        h.controller.window.performClose(nil)
        try await answerClose(h, .alertThirdButtonReturn, remainsOpen: true)
        XCTAssertEqual(h.owner.settings.configuration.fitWidth, 81)
        XCTAssertTrue(h.controller.isVisible)
        h.failures = []
        h.controller.window.performClose(nil)
        try await answerClose(h, .alertThirdButtonReturn)
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .layout }.count, 1)
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .archive }.count, 2)
    }

    @MainActor func testTerminationWithoutDraftOrSaveAnswersImmediatelyWithoutOpeningOrWriting() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var answers: [Bool] = []
        h.controller.requestCloseForTermination { answers.append($0) }
        XCTAssertEqual(answers, [true])
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertNil(h.controller.pendingCloseAlert)
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testTerminationReusesExistingSheetAndContinueCancelsOnlyItsRequest() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        h.model.setArchiveDraftText("8")
        h.controller.window.performClose(nil)
        let original = try XCTUnwrap(h.controller.pendingCloseAlert)
        var answers: [Bool] = [], repeatedAnswers: [Bool] = []
        h.controller.requestCloseForTermination { answers.append($0) }
        h.controller.requestCloseForTermination { repeatedAnswers.append($0) }
        XCTAssertTrue(h.controller.pendingCloseAlert === original)
        XCTAssertTrue(answers.isEmpty)
        XCTAssertEqual(repeatedAnswers, [false], "A new request cannot replace the unanswered original callback")
        try await answerClose(h, .alertFirstButtonReturn)
        XCTAssertEqual(answers, [false])
        XCTAssertEqual(repeatedAnswers, [false])
        XCTAssertTrue(h.controller.isVisible)
        XCTAssertEqual(h.model.archiveDraftText, "8")
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testTerminationApplyWaitsForOwnerReceiptAndApprovesOnce() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        h.model.setArchiveDraftText("8")
        h.delayDomain = .archive
        var answers: [Bool] = []
        h.controller.requestCloseForTermination { answers.append($0) }
        let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
        alert.window.animationBehavior = .none
        alert.buttons[2].performClick(nil)
        try await waitFor("termination save is awaiting its owner receipt") { h.continuation != nil }
        XCTAssertTrue(answers.isEmpty)
        XCTAssertTrue(h.controller.pendingCloseAlert === alert)
        XCTAssertFalse(alert.buttons[1].isEnabled)
        XCTAssertFalse(alert.buttons[2].isEnabled)
        h.publish()
        XCTAssertTrue(answers.isEmpty, "A snapshot refresh must not approve Quit")
        h.resumeSave()
        try await waitFor("successful termination decision") { answers == [true] }
        XCTAssertEqual(h.owner.settings.archiveAfterMinutes, 8)
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertNil(h.controller.pendingCloseAlert)
        h.publish(); h.controller.closeForTeardown()
        XCTAssertEqual(answers, [true])
        XCTAssertEqual(h.requests.count, 1)
    }

    @MainActor func testTerminationFailedApplyRetainsSameSheetAndCallbackUntilContinue() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        h.model.setArchiveDraftText("8")
        h.failures = [.archive]
        var answers: [Bool] = []
        h.controller.requestCloseForTermination { answers.append($0) }
        let original = try XCTUnwrap(h.controller.pendingCloseAlert)
        try await answerClose(h, .alertThirdButtonReturn, remainsOpen: true)
        XCTAssertTrue(h.controller.pendingCloseAlert === original)
        XCTAssertTrue(original.informativeText.contains(ProductCopy.text("尚未保存", "haven’t been saved")))
        XCTAssertTrue(answers.isEmpty)
        h.publish()
        XCTAssertTrue(h.controller.pendingCloseAlert === original)
        XCTAssertTrue(answers.isEmpty)
        try await answerClose(h, .alertFirstButtonReturn)
        XCTAssertEqual(answers, [false])
        XCTAssertTrue(h.controller.isVisible)
        XCTAssertEqual(h.model.archiveDraftText, "8")
    }

    @MainActor func testTerminationFailedApplyCanDiscardWithoutAnotherWrite() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        h.model.setArchiveDraftText("8")
        h.failures = [.archive]
        var answers: [Bool] = []
        h.controller.requestCloseForTermination { answers.append($0) }
        let original = try XCTUnwrap(h.controller.pendingCloseAlert)
        try await answerClose(h, .alertThirdButtonReturn, remainsOpen: true)
        XCTAssertTrue(h.controller.pendingCloseAlert === original)
        try await answerClose(h, .alertSecondButtonReturn)
        XCTAssertEqual(answers, [true])
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertFalse(h.model.hasArchiveDraft)
        XCTAssertEqual(h.owner.settings.archiveAfterMinutes, 2)
        XCTAssertEqual(h.requests.count, 1)
    }

    @MainActor func testTerminationPartialSaveRetriesOnlyUnconfirmedDomainInSameSheet() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        h.model.setDraftText("81", for: .fitWidth)
        h.model.setArchiveDraftText("8")
        h.failures = [.archive]
        var answers: [Bool] = []
        h.controller.requestCloseForTermination { answers.append($0) }
        let original = try XCTUnwrap(h.controller.pendingCloseAlert)
        try await answerClose(h, .alertThirdButtonReturn, remainsOpen: true)
        XCTAssertEqual(h.owner.settings.configuration.fitWidth, 81)
        XCTAssertTrue(answers.isEmpty)
        XCTAssertTrue(h.controller.pendingCloseAlert === original)
        h.failures = []
        try await answerClose(h, .alertThirdButtonReturn)
        XCTAssertEqual(answers, [true])
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .layout }.count, 1)
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .archive }.count, 2)
    }

    @MainActor func testTerminationContinueAndTeardownCannotBeApprovedByLateSave() async throws {
        for teardown in [false, true] {
            let h = try host(); defer { h.controller.closeForTeardown() }
            h.controller.show(page: .history)
            h.model.setArchiveDraftText("8")
            h.delayDomain = .archive
            var answers: [Bool] = []
            h.controller.requestCloseForTermination { answers.append($0) }
            let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
            alert.window.animationBehavior = .none
            let actionID = h.startedActions + 1
            alert.buttons[2].performClick(nil)
            try await waitFor("save before cancelling termination") { h.continuation != nil }
            if teardown { h.controller.closeForTeardown() }
            else { try await answerClose(h, .alertFirstButtonReturn) }
            XCTAssertEqual(answers, [false])
            h.resumeSave()
            try await waitFor("late owner save completion") { h.completedActions.contains(actionID) }
            XCTAssertEqual(answers, [false])
            XCTAssertEqual(h.controller.isVisible, !teardown)
            XCTAssertNil(h.controller.pendingCloseAlert)
            XCTAssertEqual(h.owner.settings.archiveAfterMinutes, 8, "Cancelling Quit does not undo an already started owner write")
            XCTAssertEqual(h.requests.count, 1)
        }
    }

    @MainActor func testTerminationWaitsForImmediateDomainSaveWithoutInventingDraft() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show()
        h.delayDomain = .collection
        let actionID = h.startedActions + 1
        h.controller.dispatch(.settings(.setCollectionPaused(true)))
        try await waitFor("collection owner receipt") { h.continuation != nil }
        XCTAssertFalse(h.model.hasLayoutDraft); XCTAssertFalse(h.model.hasArchiveDraft)
        var answers: [Bool] = []
        h.controller.requestCloseForTermination { answers.append($0) }
        let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
        XCTAssertTrue(answers.isEmpty)
        XCTAssertFalse(alert.buttons[1].isEnabled); XCTAssertFalse(alert.buttons[2].isEnabled)
        h.resumeSave()
        try await waitFor("collection completion") { h.completedActions.contains(actionID) }
        XCTAssertTrue(answers.isEmpty, "Completing an unrelated save is not itself permission to close")
        try await answerClose(h, .alertSecondButtonReturn)
        XCTAssertEqual(answers, [true])
        XCTAssertEqual(h.requests.map(\.intent), [.collectionPaused(true)])
    }

    @MainActor func testTerminationAlsoWaitsForHostLoginOperation() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.login.inFlightTarget = true
        h.publish()
        var answers: [Bool] = []
        h.controller.requestCloseForTermination { answers.append($0) }
        let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
        XCTAssertTrue(answers.isEmpty)
        XCTAssertFalse(alert.buttons[1].isEnabled); XCTAssertFalse(alert.buttons[2].isEnabled)
        try await answerClose(h, .alertFirstButtonReturn)
        XCTAssertEqual(answers, [false])
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testThreeStopErrorsStayIndependentAndRetryOriginalDirection() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.failures = [.collection, .visibility, .entry]
        h.controller.show()
        try await actionAndWait(h) { h.controller.dispatch(.settings(.setCollectionPaused(!h.owner.collectionPaused))) }
        try await actionAndWait(h) { h.controller.dispatch(.settings(.setHidden(true))) }
        h.controller.show(page: .capture)
        try await clickAndWait(h, "entry")
        XCTAssertTrue(h.owner.collectionPaused); XCTAssertTrue(h.owner.isHidden); XCTAssertFalse(h.owner.settings.entryEnabled)
        for domain in [SettingsDomain.collection, .visibility, .entry] { XCTAssertTrue(h.model.snapshot.domains[domain]?.hasIssue == true) }
        _ = await h.model.perform(.setArrival(.magnet))
        for domain in [SettingsDomain.collection, .visibility, .entry] { XCTAssertTrue(h.model.snapshot.domains[domain]?.hasIssue == true) }
        h.failures = []
        try await clickAndWait(h, "retry.entry")
        XCTAssertFalse(h.model.snapshot.domains[.entry]!.hasIssue)
        XCTAssertTrue(h.model.snapshot.domains[.collection]!.hasIssue)
        h.controller.show()
        try await clickAndWait(h, "retry.collection")
        try await clickAndWait(h, "retry.visibility")
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .entry }.map(\.intent), [.entryEnabled(false), .entryEnabled(false)])
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .collection }.map(\.intent), [.collectionPaused(true), .collectionPaused(true)])
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .visibility }.map(\.intent), [.hidden(true), .hidden(true)])
    }

    @MainActor func testFailedResumeKeepsActualStoppedSwitchAndRetryUsesResume() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        _ = await h.model.perform(.setCollectionPaused(true))
        h.failures = [.collection]
        h.controller.show()
        try await actionAndWait(h) { h.controller.dispatch(.settings(.setCollectionPaused(!h.owner.collectionPaused))) }
        XCTAssertTrue(h.owner.collectionPaused)
        XCTAssertEqual(h.model.snapshot.domains[.collection]?.pending, .collectionPaused(false))
        XCTAssertTrue(h.controller.errorLabels[.collection]!.stringValue.contains(ProductCopy.text("继续收录", "Resume Collection")))
        h.failures = []; try await clickAndWait(h, "retry.collection")
        XCTAssertFalse(h.owner.collectionPaused)
    }

    @MainActor func testDisplayFallbackRefreshKeepsDraftAndConcreteSelection() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        h.model.setDraftText("95.125", for: .fitWidth)
        var next = h.owner.settings
        next.displays = [.init(id: 2, name: "Second screen")]
        next.configuration.numberGap = 14
        h.receive(next, effectiveDisplay: 2)
        let display: NSPopUpButton = try control(h, "display")
        XCTAssertEqual(display.titleOfSelectedItem, ProductCopy.text("已选显示器（未连接）", "Preferred Display (Disconnected)"))
        XCTAssertEqual(h.model.text(for: .fitWidth), "95.125")
        try await actionAndWait(h) { h.controller.dispatch(.settings(.applyLayout)) }
        XCTAssertEqual(h.owner.settings.configuration.preferredDisplayID, 1)
        XCTAssertEqual(h.owner.settings.configuration.numberGap, 14)
        XCTAssertEqual(h.owner.settings.configuration.fitWidth, 95.125)
    }

    @MainActor func testDisplayMenuTrackingDoesNotReplaceInvokedItemIdentity() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        let display: NSPopUpButton = try control(h, "display")
        let menu = try XCTUnwrap(display.menu)
        h.controller.menuWillOpen(menu)
        let old = display.itemArray
        var next = h.owner.settings
        next.displays = [.init(id: 2, name: "Renamed second"), .init(id: 1, name: "Renamed first")]
        h.receive(next)
        XCTAssertTrue(display.item(at: 1) === old[1])
        display.selectItem(at: 1)
        h.controller.menuDidClose(menu)
        try await actionAndWait(h) { _ = display.sendAction(display.action, to: display.target) }
        guard case .display(let preference) = try XCTUnwrap(h.requests.last?.intent) else { return XCTFail("Missing concrete display intent") }
        XCTAssertEqual(preference.id, 2)
    }

    @MainActor func testSameNamedDisplaysRemainDistinctNativeMenuItems() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var next = h.owner.settings
        next.displays = [.init(id: 1, name: "External display"), .init(id: 2, name: "External display")]
        h.receive(next); h.controller.show(page: .display)
        let display: NSPopUpButton = try control(h, "display")
        XCTAssertEqual(display.numberOfItems, 2)
        XCTAssertEqual(display.itemTitles, ["External display · 1", "External display · 2"])
        XCTAssertEqual(display.itemArray.compactMap { ($0.representedObject as? NSNumber)?.uint32Value }, [1, 2])
        try await changeAndWait(h, "display", index: 1)
        XCTAssertEqual(h.owner.settings.configuration.preferredDisplayID, 2)
    }

    @MainActor func testRestoreCurrentPagePreservesOtherDraftsAndSevenLegacyValues() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var next = h.owner.settings
        next.configuration.lineWidth = 1.25; next.configuration.lineExtension = 21
        next.configuration.emptyTraceLength = 33; next.configuration.screenPadding = 23
        next.configuration.arrivalDuration = 0.73; next.configuration.inwardDistance = 7
        next.configuration.reducedMotionDuration = 0.11
        h.receive(next)
        h.model.setDraftText("40", for: .swallowDuration)
        h.controller.show(page: .display)
        _ = await h.model.perform(.restoreVisibleDefaults)
        let config = h.owner.settings.configuration
        XCTAssertEqual(config.hiddenFraction, 0.25); XCTAssertEqual(config.outerInset, 6)
        XCTAssertEqual(config.swallowDuration, next.configuration.swallowDuration)
        XCTAssertEqual(h.model.text(for: .swallowDuration), "40")
        XCTAssertEqual([config.lineWidth, config.lineExtension, config.emptyTraceLength, config.screenPadding,
                        config.arrivalDuration, config.inwardDistance, config.reducedMotionDuration], [1.25, 21, 33, 23, 0.73, 7, 0.11])
    }

    @MainActor func testSinglePreviewAndArrivalModeKeepSystemReducedMotion() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .motion)
        try await changeAndWait(h, "arrival", index: ArrivalMotionMode.allCases.firstIndex(of: .magnet)!)
        XCTAssertEqual(h.owner.settings.arrivalMode, .magnet)
        h.accessibility.reduceMotion = true; h.publish()
        XCTAssertFalse(try XCTUnwrap(h.controller.labels["motion.detail"]).isHidden)
        XCTAssertNil(h.controller.controls["swallow.preview"])
        XCTAssertTrue(h.controller.geometryPreview.window === h.controller.window)
    }

    @MainActor func testLoginApprovalIsNotReportedAsEnabledAndRefreshIsReadOnly() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.login.available = true; h.login.status = .requiresApproval
        h.publish(); h.controller.show()
        let login: NSSwitch = try control(h, "login")
        XCTAssertEqual(login.state, .on)
        XCTAssertTrue(h.controller.labels["login.detail"]!.stringValue.contains(ProductCopy.text("尚未获准", "to enable launch at login")))
        XCTAssertFalse(h.controller.controls["login.system"]!.isHidden)
        XCTAssertTrue(h.actions.isEmpty)
        h.login.status = .unknown; h.publish()
        XCTAssertFalse(login.isEnabled)
    }

    @MainActor func testNotFoundLoginCanRequestEnableWithoutInventingConfirmedState() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.login.available = true; h.login.status = .notFound
        h.publish(); h.controller.show()
        let login: NSSwitch = try control(h, "login")
        XCTAssertTrue(login.isEnabled)
        XCTAssertEqual(login.state, .off)
        XCTAssertTrue(h.controller.labels["login.detail"]!.stringValue.contains(ProductCopy.text("可以尝试开启", "try enabling it")))
        XCTAssertTrue(h.actions.isEmpty, "A missing service readback does not register automatically")
        try await clickAndWait(h, "login")
        XCTAssertEqual(h.actions, ["login:true"])
        XCTAssertEqual(login.state, .off, "The synthetic host still reports notFound; a click is not confirmation")
        h.login.inFlightTarget = true; h.publish()
        XCTAssertFalse(login.isEnabled)
        h.login.inFlightTarget = nil; h.login.status = .unknown; h.publish()
        XCTAssertFalse(login.isEnabled)
        h.login.status = .notFound; h.login.available = false; h.publish()
        XCTAssertFalse(login.isEnabled)
        XCTAssertEqual(h.actions, ["login:true"])
    }

    @MainActor func testLoginOperationErrorDoesNotEraseEnabledOrPendingApprovalReadback() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.login.available = true; h.login.errorCode = 7
        h.controller.show()
        for status in [SettingsLoginStatus.enabled, .requiresApproval] {
            h.login.status = status; h.login.failedTarget = nil; h.login.notConfirmed = false; h.publish()
            let login: NSSwitch = try control(h, "login")
            XCTAssertEqual(login.state, .on, "Actual system readback is not rolled back after an error")
            let detail = h.controller.labels["login.detail"]!.stringValue
            XCTAssertTrue(detail.contains(ProductCopy.text("代码 7", "code 7")))
            XCTAssertTrue(detail.contains(status == .enabled ? ProductCopy.text("已允许", "allows") : ProductCopy.text("尚未获准", "to enable launch at login")))
            XCTAssertTrue(h.controller.controls["login.retry"]!.isHidden)
            XCTAssertEqual(h.controller.controls["login.system"]!.isHidden, status != .requiresApproval)
        }
        XCTAssertTrue(h.actions.isEmpty)
    }

    @MainActor func testNoStorageMeasurementNeverShowsInventedZeroAndClearRequestsHostConfirmationOnce() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        XCTAssertTrue(h.controller.labels["storage"]!.stringValue.contains(ProductCopy.text("尚未检查", "hasn’t been checked")))
        XCTAssertFalse(h.controller.labels["storage"]!.stringValue.contains("0 B"))
        XCTAssertTrue(h.actions.isEmpty)
        h.controller.show(page: .help)
        try click(h, "disclosure.diagnostics")
        try await clickAndWait(h, "storage.reveal")
        XCTAssertEqual(h.actions, ["revealDataFolder"])
        XCTAssertNil(h.controller.controls["history.clear"])
        XCTAssertEqual(h.actions, ["revealDataFolder"])
        XCTAssertNil(h.controller.window.attachedSheet, "The shared host owns the only confirmation; this surface cannot clear a store")
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testInFlightSaveKeepsOtherDomainsAvailableAndNewDraftSurvives() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.delayDomain = .layout
        h.model.setDraftText("80", for: .fitWidth)
        h.controller.show(page: .display)
        let layoutAction = h.startedActions + 1
        h.controller.dispatch(.settings(.applyLayout))
        try await waitFor("layout owner waiting on its actual receipt") { h.continuation != nil && h.model.snapshot.domains[.layout]!.isSaving }
        XCTAssertTrue(h.model.snapshot.domains[.layout]!.isSaving)
        h.model.setDraftText("89", for: .fitWidth)
        h.controller.show()
        XCTAssertTrue(h.controller.product.capabilities.canChangeCollection)
        try await actionAndWait(h) { h.controller.dispatch(.settings(.setCollectionPaused(!h.owner.collectionPaused))) }
        XCTAssertTrue(h.owner.collectionPaused)
        h.controller.window.performClose(nil)
        let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
        XCTAssertFalse(alert.buttons[1].isEnabled, "Discard cannot cancel an in-flight write")
        try await answerClose(h, .alertFirstButtonReturn)
        h.resumeSave()
        try await waitFor("the original layout action completion") { h.completedActions.contains(layoutAction) }
        XCTAssertEqual(h.model.text(for: .fitWidth), "89")
        XCTAssertTrue(h.model.hasLayoutDraft)
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .layout }.count, 1)
    }

    @MainActor func testSettingsRecoverLegacyPauseWithoutOfferingAnotherPauseSwitch() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .capture)
        let resume: NSButton = try control(h, "collection.resume")
        let visible: NSSwitch = try control(h, "desktop.visible")
        XCTAssertTrue(resume.isHidden)
        XCTAssertNil(h.controller.controls["collection.enabled"])
        XCTAssertEqual(visible.state, .on)
        try await actionAndWait(h) { h.controller.dispatch(.settings(.setCollectionPaused(true))) }
        XCTAssertFalse(resume.isHidden)
        try await clickAndWait(h, "desktop.visible")
        XCTAssertTrue(h.owner.collectionPaused)
        XCTAssertTrue(h.owner.isHidden)
        try await clickAndWait(h, "collection.resume")
        XCTAssertFalse(h.owner.collectionPaused)
        XCTAssertTrue(h.owner.isHidden, "Resuming collection must not change visibility")
        XCTAssertTrue(resume.isHidden)
        try await clickAndWait(h, "desktop.visible")
        XCTAssertFalse(h.owner.isHidden)
        XCTAssertEqual(h.requests.map(\.intent), [.collectionPaused(true), .hidden(true), .collectionPaused(false), .hidden(false)])
    }

    @MainActor func testLegacyResumeFailureKeepsIndependentRetryDirection() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .capture)
        try await actionAndWait(h) { h.controller.dispatch(.settings(.setCollectionPaused(true))) }
        h.failures = [.collection]
        try await clickAndWait(h, "collection.resume")
        XCTAssertTrue(h.owner.collectionPaused)
        XCTAssertEqual(h.model.snapshot.domains[.collection]?.pending, .collectionPaused(false))
        try await clickAndWait(h, "desktop.visible")
        XCTAssertTrue(h.model.snapshot.domains[.collection]?.hasIssue == true)
        h.failures = []
        try await clickAndWait(h, "retry.collection")
        XCTAssertFalse(h.owner.collectionPaused)
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .collection }.map(\.intent), [.collectionPaused(true), .collectionPaused(false), .collectionPaused(false)])
    }

    @MainActor func testLibraryStyleOwnedByLibraryAndSettingsStillOpensIt() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.historyStyle = .imageGrid; h.publish()
        h.controller.show(page: .capture)
        XCTAssertNil(h.controller.controls["history.style"])
        try await clickAndWait(h, "history.open")
        XCTAssertEqual(h.historyStyle, .imageGrid)
        XCTAssertEqual(h.actions, ["openHistory"])
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testFreshTrayShowsOnlyCurrentMaterialAndLegacyRowsFollowActualNonDefaultFields() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var settings = h.owner.settings
        settings.configuration.desktopForm = .tray
        h.receive(settings)
        h.controller.show(page: .display)
        let legacy = try XCTUnwrap(h.controller.legacySection)
        let slider: NSSlider = try control(h, "tray.transparency")
        XCTAssertTrue(legacy.isHidden)
        XCTAssertFalse(slider.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(slider.minValue, 0)
        XCTAssertEqual(slider.maxValue, 0.75)
        settings.configuration.outerInset = 22
        h.receive(settings)
        XCTAssertFalse(legacy.isHidden)
        XCTAssertFalse(try XCTUnwrap(h.controller.controls["layout.defaults.display"]).isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(!h.controller.controls.keys.contains(where: { $0.hasPrefix("field.") }))
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testUnavailableServicesShowStatusAndRecoveryInsteadOfDeadControls() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.login.available = false; h.appearance.available = false; h.updater = nil; h.publish()
        h.controller.show(page: .general)
        for id in ["login", "updates.check", "updates.automatic"] {
            XCTAssertTrue(try XCTUnwrap(h.controller.controls[id]).isHiddenOrHasHiddenAncestor)
        }
        XCTAssertFalse(try XCTUnwrap(h.controller.labels["login.detail"]).isHidden)
        XCTAssertFalse(try XCTUnwrap(h.controller.labels["updates.failure"]).isHidden)
        XCTAssertFalse(try XCTUnwrap(h.controller.controls["updates.website"]).isHiddenOrHasHiddenAncestor)
        h.login.available = true; h.appearance.available = true
        h.updater = .init(canCheck: false, automaticChecks: true, availableVersion: nil, failure: nil)
        h.publish()
        XCTAssertFalse(try XCTUnwrap(h.controller.controls["updates.check"]).isHiddenOrHasHiddenAncestor,
                       "A temporary in-progress check remains visible, unlike an absent updater")
        XCTAssertFalse(try XCTUnwrap(h.controller.controls["updates.check"]).isEnabled)
    }

    @MainActor func testStandaloneSettingsActionsKeepNaturalWidthAndRecoveryLeavesNoEmptyRow() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .general)
        h.controller.window.contentView?.layoutSubtreeIfNeeded()
        let update: NSButton = try control(h, "updates.check")
        let row = try XCTUnwrap(update.superview as? NSStackView)
        XCTAssertTrue(try XCTUnwrap(h.controller.labels["version"]).isDescendant(of: row),
                      "The current version and its update action belong in one row")
        XCTAssertLessThan(update.bounds.width, row.bounds.width - 40, "A short action must not stretch across the page")
        XCTAssertEqual(update.alignmentRect(forFrame: update.frame).midY, row.bounds.midY, accuracy: 1)
        XCTAssertEqual(update.alignmentRect(forFrame: update.frame).maxX, row.bounds.maxX, accuracy: 1)
        XCTAssertTrue(try XCTUnwrap(h.controller.actionContainers["appearance.retry"]).isHidden)
        h.appearance.selection = .dark; h.appearance.applied = .light
        h.appearance.pending = .dark; h.appearance.failure = "Synthetic save failure"; h.appearance.available = true
        h.publish()
        XCTAssertFalse(try XCTUnwrap(h.controller.actionContainers["appearance.retry"]).isHidden)
    }

    @MainActor func testResizeRetainsFieldsAndScrollableDocument() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        var legacy = h.owner.settings
        legacy.configuration.outerInset = 22
        h.receive(legacy)
        let field = try XCTUnwrap(h.controller.controls["layout.defaults.display"])
        let size = SettingsNativeStyle.settingsMinimumSize
        h.controller.window.setContentSize(size)
        let scroll = h.controller.scroll
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertFalse(scroll.hasHorizontalScroller)
        for style in [NSScroller.Style.legacy, .overlay] {
            // AppKit can change the effective style with system preferences or
            // the pointing device. The form must fit the resulting viewport.
            scroll.scrollerStyle = style
            scroll.tile()
            h.controller.window.contentView?.layoutSubtreeIfNeeded()
            let clip = scroll.contentView
            XCTAssertEqual(document.bounds.width, clip.bounds.width, accuracy: 1)
            XCTAssertGreaterThan(document.bounds.height, clip.bounds.height)
            clip.scroll(to: .zero)
            scroll.reflectScrolledClipView(clip)
            XCTAssertFalse(clip.bounds.contains(field.convert(field.bounds, to: clip)))
            field.scrollToVisible(field.bounds)
            XCTAssertGreaterThan(clip.bounds.minY, 0)
            XCTAssertTrue(clip.bounds.insetBy(dx: -0.5, dy: -0.5).contains(field.convert(field.bounds, to: clip)),
                          "The advanced field must be fully reachable with the available scroll width")
            XCTAssertTrue(h.controller.controls["layout.defaults.display"] === field)
        }
        XCTAssertNotNil(field.accessibilityLabel())
        XCTAssertFalse(field.accessibilityLabel()!.isEmpty)
    }
    @MainActor func testLocalizedFourPagesKeepReadableNativeControlsAndStableEditors() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .general)
        h.controller.window.setContentSize(SettingsNativeStyle.settingsMinimumSize)
        let field = try XCTUnwrap(h.controller.controls["layout.defaults.display"])
        for page in SettingsPage.allCases {
            h.controller.show(page: page)
            h.controller.window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(h.controller.pageHeading.stringValue, page.title)
            XCTAssertEqual(h.controller.navigation[page]?.accessibilityLabel(), page.title)
            XCTAssertTrue(field === h.controller.controls["layout.defaults.display"])
            for control in h.controller.controls.values where !control.isHiddenOrHasHiddenAncestor {
                guard let button = control as? NSButton, !(button is NSPopUpButton), button.imagePosition != .imageOnly, button.window != nil else { continue }
                let width = (button.title as NSString).size(withAttributes: [.font: button.font ?? NSFont.systemFont(ofSize: 13)]).width
                XCTAssertGreaterThanOrEqual(button.bounds.width, width, "Button title must remain readable: " + button.title)
            }
        }
        XCTAssertEqual((h.controller.controls["source.access.capture"] as? NSButton)?.title,
                       ProductCopy.text("允许访问截图文件夹…", "Allow Screenshot Folder Access…"))
        XCTAssertNil(h.controller.controls["archive.minutes"])
    }

}

@MainActor
private final class SettingsCenterTestHost {
    var owner: SettingsOwnerSnapshot
    var model: SettingsStateModel!
    var controller: RiftSettingsCenterController!
    var requests: [SettingsSaveRequest] = []
    var actions: [String] = []
    var startedActions = 0
    var completedActions: Set<Int> = []
    var failures: Set<SettingsDomain> = []
    var delayDomain: SettingsDomain?
    var continuation: CheckedContinuation<Void, Never>?
    var revision: UInt64 = 0
    var accessibility = SettingsAccessibility()
    var login = SettingsLoginPresentation()
    var appearance = SettingsAppearancePresentation()
    var historyStyle = HistoryDisplayStyle.current
    var updater: SettingsUpdaterPresentation? = .init(canCheck: true, automaticChecks: true, availableVersion: nil, failure: nil)

    init() throws {
        login.available = true; login.status = .notRegistered
        appearance.available = true; appearance.applied = .system
        var configuration = RiftConfiguration(); configuration.preferredDisplayID = 1
        let settings = RiftSettingsSnapshot(entryAvailable: true,
            displays: [.init(id: 1, name: "First screen"), .init(id: 2, name: "Second screen")], preferredDisplayID: 1,
            archiveAfterMinutes: QueueArchivePolicy.defaultMinutes, configuration: configuration)
        owner = .init(revision: 1, settings: settings, collectionPaused: false, isHidden: false, mainDisplayID: 1, effectiveDisplayID: 1)
        model = try SettingsStateModel(owner: owner, decimalSeparator: ".", adapter: SettingsPersistenceClosures { [weak self] request in
            guard let self else { return .unconfirmed(nil, .ownerUnavailable) }
            return await save(request)
        })
        controller = RiftSettingsCenterController(model: model) { [weak self] action in
            guard let self else { return }
            startedActions += 1
            let actionID = startedActions
            if case .settings(let command) = action { _ = await model.perform(command) }
            else {
                switch action {
                case .openHistory: actions.append("openHistory")
                case .checkChromeConnection: actions.append("checkChromeConnection")
                case .clearVisible: actions.append("clearVisible")
                case .revealDataFolder: actions.append("revealDataFolder")
                case .loginEnabled(let value): actions.append("login:\(value)")
                case .appearance(let value): actions.append("appearance:\(value.rawValue)")
                case .historyDisplayStyle(let value): historyStyle = value; actions.append("historyStyle:\(value.rawValue)")
                default: actions.append("hostAction")
                }
            }
            publish()
            completedActions.insert(actionID)
        }
        model.onChange = { [weak self] _ in self?.publish() }
        publish()
    }
    func save(_ request: SettingsSaveRequest) async -> SettingsSaveOutcome {
        requests.append(request)
        if request.intent.domain == delayDomain { await withCheckedContinuation { continuation = $0 } }
        var settings = owner.settings
        var paused = owner.collectionPaused, hidden = owner.isHidden
        let failure = failures.contains(request.intent.domain)
        switch request.intent {
        case .collectionPaused(let value): if value || !failure { paused = value }
        case .hidden(let value): if value || !failure { hidden = value }
        case .entryEnabled(let value): if !value || !failure { settings.entryEnabled = value }; settings.capturePreferencesSaveFailed = failure
        case .captureMode(let mode): if !failure { settings.defaultCaptureMode = mode; settings.capturePreferencesSaveFailed = false }
        case .arrival(let mode): if !failure { settings.arrivalMode = mode; settings.hasArrivalSelection = true }
        case .archiveMinutes(let value): if !failure { settings.archiveAfterMinutes = value }
        case .layout, .placement, .display, .desktopForm, .windChimeArrangement, .trayTheme, .trayFavorite, .trayBackgroundTransparency, .trayCameraBodyColor, .restoreLegacyCustom:
            if !failure, let configuration = request.configuration { settings.configuration = configuration; settings.preferredDisplayID = configuration.preferredDisplayID }
        }
        owner = SettingsOwnerSnapshot(revision: owner.revision + 1, settings: settings, collectionPaused: paused, isHidden: hidden,
            mainDisplayID: owner.mainDisplayID, effectiveDisplayID: owner.effectiveDisplayID)
        return failure ? .unconfirmed(owner, .writeUnconfirmed) : .confirmed(owner)
    }
    func resumeSave() { delayDomain = nil; let pending = continuation; continuation = nil; pending?.resume() }
    func receive(_ settings: RiftSettingsSnapshot, hidden: Bool? = nil, effectiveDisplay: UInt32? = nil) {
        owner = SettingsOwnerSnapshot(revision: owner.revision + 1, settings: settings, collectionPaused: owner.collectionPaused,
            isHidden: hidden ?? owner.isHidden, mainDisplayID: owner.mainDisplayID, effectiveDisplayID: effectiveDisplay ?? owner.effectiveDisplayID)
        _ = model.receive(owner); publish()
    }
    func publish() {
        revision += 1
        let setup = SetupSnapshot(sourceLocation: "/synthetic/screenshots", source: .accessible,
            collection: owner.collectionPaused ? .paused : .collecting, isHidden: owner.isHidden,
            visibleCount: 2, pendingCount: 0, attachment: .available, permission: .granted,
            storage: .notMeasured, supportDescription: "Synthetic settings test host")
        var snapshot = SettingsProductSnapshot(revision: revision, setup: setup, state: model.snapshot)
        snapshot.legacyCustomFields = Set(SettingsField.legacyAppearance.filter { field in
            field.value(in: owner.settings.configuration) != field.value(in: RiftConfiguration())
        })
        snapshot.hasLegacyTrayTheme = owner.settings.configuration.trayTheme != .system
        snapshot.accessibility = accessibility; snapshot.login = login; snapshot.appearance = appearance
        snapshot.historyDisplayStyle = historyStyle; snapshot.updater = updater
        snapshot.capabilities.initialized = true; snapshot.capabilities.canChangeCollection = true
        snapshot.capabilities.canChangeVisibility = true; snapshot.capabilities.canEditPreferences = true
        snapshot.capabilities.canClearVisible = true; snapshot.capabilities.canOpenHistory = true
        snapshot.capabilities.canCheckStorage = true; snapshot.capabilities.canRecheck = true
        snapshot.capabilities.canChooseSource = true; snapshot.capabilities.canCapture = true
        controller.update(snapshot)
    }
}
