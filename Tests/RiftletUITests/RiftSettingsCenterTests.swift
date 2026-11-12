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
    @MainActor private func enter(_ host: SettingsCenterTestHost, field: NSTextField, text: String) throws -> NSTextView {
        XCTAssertTrue(host.controller.window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.string = text
        editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        host.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        return editor
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
        XCTAssertEqual(SettingsPage.allCases, [.display, .capture, .history, .help])
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
        h.controller.show(page:.general)
        XCTAssertEqual(h.controller.selectedPage,.history)
        h.publish()
        XCTAssertTrue(h.actions.isEmpty)
        XCTAssertTrue(h.requests.isEmpty)
        h.controller.closeForTeardown(); h.publish()
        XCTAssertFalse(h.controller.isVisible, "Background updates do not open a closed settings window")
    }

    @MainActor func testNativeSwitchesMatchPositiveLabelsAndEffectiveState() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        let expected = [("paused", "收录系统截图"), ("hidden", "显示桌面截图"), ("login", "登录时启动 Riftlet"), ("entry", "显示内置截图入口")]
        for (id, label) in expected {
            let toggle: NSSwitch = try control(h, id)
            XCTAssertEqual(toggle.identifier?.rawValue, "settings.center." + id)
            XCTAssertEqual(toggle.accessibilityLabel(), label)
        }
        let paused: NSSwitch = try control(h, "paused"), hidden: NSSwitch = try control(h, "hidden"), entry: NSSwitch = try control(h, "entry")
        XCTAssertEqual(paused.state, .on); XCTAssertEqual(hidden.state, .on); XCTAssertEqual(entry.state, .on)
        func labels(in view: NSView) -> [String] {
            (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap { labels(in: $0) }
        }
        let titles = labels(in: try XCTUnwrap(h.controller.pages[.history]))
        XCTAssertTrue(titles.contains("收录系统截图")); XCTAssertTrue(titles.contains("显示桌面截图"))
        XCTAssertFalse(titles.contains("收录新截图")); XCTAssertFalse(titles.contains("显示边缘微图"))
    }

    @MainActor func testControlCenterAndBothSettingsPagesExplainVolumeAndIndividualCaptureProblems() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        for issue in [SetupIssue.sourceVolumeUnidentified, .fileVolumeUnidentified, .historicalSourceUnconfirmed] {
            h.revision += 1
            let setup = SetupSnapshot(sourceLocation: "/synthetic/screenshots", source: .accessible,
                                      collection: .collecting, issue: issue)
            let snapshot = SettingsProductSnapshot(revision: h.revision, setup: setup, state: h.model.snapshot)
            h.controller.update(snapshot)
            let status = RiftControlCenterPresentation(snapshot)
            XCTAssertEqual(status.state, .attention)
            XCTAssertEqual(status.recoveryPage, .capture)
            XCTAssertEqual(status.detail, issue.text)
            if issue == .sourceVolumeUnidentified {
                XCTAssertEqual(status.title, "当前截图位置无法收录")
                XCTAssertTrue(status.detail.contains("选择其他保存位置"))
            } else {
                XCTAssertEqual(status.title, "部分截图暂缓收录")
                XCTAssertTrue(status.detail.contains("其他新截图仍可收录"))
            }
            for page in ["capture", "help"] {
                XCTAssertEqual(h.controller.labels["source." + page]?.stringValue, issue.text)
            }
            XCTAssertEqual(SetupPresentation(snapshot: setup).collectionText, issue.text)
        }
    }

    @MainActor func testChromeJavaScriptRefusalShowsRecoveryAndKeepsMacAutomationGranted() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var snapshot = h.controller.product
        snapshot.setup = .init(source: .accessible, collection: .collecting, attachment: .available,
                               permission: .granted, issue: .chromeJavaScriptDisabled)
        h.controller.update(snapshot)
        let attachment = try XCTUnwrap(h.controller.labels["attachment"])
        let automation = try XCTUnwrap(h.controller.labels["automation"])
        let expected = "Chrome 尚未允许通过 Apple 事件执行 JavaScript。截图已保留，尚未附加。请在 Chrome 的『视图 → 开发者』中启用『允许来自 Apple 事件的 JavaScript』。"
        XCTAssertEqual(attachment.stringValue, expected)
        XCTAssertEqual(RiftControlCenterPresentation(snapshot).detail, expected)
        XCTAssertEqual(automation.stringValue, "macOS 已允许 Riftlet 与 Chrome 通信。")
        XCTAssertTrue(h.actions.isEmpty)

        snapshot.setup = .init(attachment: .productionDisabled, issue: .chromeJavaScriptDisabled)
        h.controller.update(snapshot)
        XCTAssertFalse(attachment.stringValue.contains("JavaScript"))
        XCTAssertNil(SetupPresentation(snapshot: snapshot.setup).issueText)
    }

    @MainActor func testFirstShowRestoresV2ContentSizeAndLaterShowsKeepUserResize() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        let window = h.controller.window
        let visible = try XCTUnwrap((window.screen ?? NSScreen.main)?.visibleFrame)
        let available = window.contentRect(forFrameRect: visible).size
        let expected = NSSize(width: min(814, available.width), height: min(580, available.height))
        h.controller.show()
        window.contentView?.layoutSubtreeIfNeeded()
        let actual = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(window.frame.minX, visible.minX - 0.5)
        XCTAssertLessThanOrEqual(window.frame.maxX, visible.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(window.frame.minY, visible.minY - 0.5)
        XCTAssertLessThanOrEqual(window.frame.maxY, visible.maxY + 0.5)
        let smaller = NSSize(width: max(716, expected.width - 40), height: max(450, expected.height - 30))
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

    @MainActor func testLayoutCaptionStaysOutsideDrawingForAllPlacementsAndCompactWidth() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        let caption = try XCTUnwrap(h.controller.labels["layoutPreview.detail"])
        let document = try XCTUnwrap(h.controller.pages[.display])
        try click(h, "disclosure.display.advanced")
        for size in [SettingsNativeStyle.settingsSize, SettingsNativeStyle.settingsMinimumSize] {
            h.controller.window.setContentSize(size)
            for placement in RiftPlacement.allCases {
                for count in [1, 3, 10] {
                    var settings = h.owner.settings
                    settings.configuration.placement = placement
                    settings.configuration.visibleCountPreference = count
                    h.receive(settings)
                    h.controller.window.contentView?.layoutSubtreeIfNeeded()
                    let drawingRect = h.controller.geometryPreview.convert(h.controller.geometryPreview.bounds, to: document)
                    let captionRect = caption.convert(caption.bounds, to: document)
                    XCTAssertGreaterThan(captionRect.height, 0)
                    XCTAssertFalse(drawingRect.intersects(captionRect), "The caption must never cover a synthetic card, including left-middle")
                    if document.isFlipped { XCTAssertGreaterThanOrEqual(captionRect.minY, drawingRect.maxY + 8) }
                    else { XCTAssertLessThanOrEqual(captionRect.maxY, drawingRect.minY - 8) }
                    XCTAssertTrue(caption.stringValue.contains(placement.title + " · \(count) 张"))
                    XCTAssertEqual(h.controller.geometryPreview.accessibilityValue() as? String, h.controller.geometryPreview.geometrySummary)
                    XCTAssertEqual(caption.stringValue.contains("示意前 4 张"), count > 4)
                }
            }
            let visible = h.controller.scroll.contentView.documentVisibleRect
            let picker: NSPopUpButton = try control(h, "placement")
            let rect = picker.convert(picker.bounds, to: document)
            let drawingRect = h.controller.geometryPreview.convert(h.controller.geometryPreview.bounds, to: document)
            XCTAssertTrue(visible.contains(rect), "Placement must be operable in the initial viewport")
            XCTAssertFalse(rect.intersects(drawingRect))
            XCTAssertEqual(picker.itemArray.filter { !$0.isHidden }.map(\.title), RiftPlacement.allCases.map(\.title))
            XCTAssertEqual(picker.accessibilityLabel(), "屏幕边缘")
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

    @MainActor func testNativeFieldsKeepIdentityRawTextAndSelectionAcrossOwnerRefresh() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        try click(h, "disclosure.display.advanced"); try click(h, "disclosure.display.details")
        let field = try XCTUnwrap(h.controller.numericFields[.fitWidth])
        let editor = try enter(h, field: field, text: "83.2500")
        editor.setSelectedRange(NSRange(location: 2, length: 3))
        let range = editor.selectedRange()
        var next = h.owner.settings
        next.configuration.fitHeight = 61
        h.receive(next, hidden: true)
        XCTAssertTrue(h.controller.numericFields[.fitWidth] === field)
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertEqual(editor.string, "83.2500")
        XCTAssertEqual(editor.selectedRange(), range)
        XCTAssertEqual(h.model.text(for: .fitWidth), "83.2500")
        XCTAssertEqual(h.model.configurationDraft?.fitHeight, 61)
        h.controller.window.makeFirstResponder(h.controller.navigation[.display])
        h.publish()
        XCTAssertEqual(field.stringValue, "83.2500", "Blurred drafts retain formatting, too")
    }

    @MainActor func testPairedPreviewSwitchDrawsOneEnclosureOrTwoBareCardsWithoutSaving() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        var settings = h.owner.settings
        settings.configuration.desktopForm = .tray
        h.receive(settings)
        let preview = h.controller.geometryPreview
        let selector: NSSegmentedControl = try control(h, "tray.borderPreview")
        XCTAssertFalse(h.controller.trayBorderPreviewRow.isHidden)
        XCTAssertEqual(selector.selectedSegment, 0)
        let rect = CGRect(x: 0.5, y: 0.5, width: 523, height: 114)
        let bordered = TrayPlacementIllustration.frames(in: rect, configuration: settings.configuration, twoRows: true,
                                                         withSaytile: true, framed: true, flipped: true)
        let outer = try XCTUnwrap(bordered.outer)
        let card = try XCTUnwrap(bordered.saytile)
        XCTAssertTrue(outer.contains(card) && outer.contains(bordered.tray))
        XCTAssertLessThan(bordered.tray.width, outer.width)
        XCTAssertEqual(bordered.tray.width, card.width, accuracy: 0.1)
        XCTAssertEqual(bordered.tray.maxX, card.maxX, accuracy: 0.1)

        try change(h, "tray.borderPreview", index: 1)
        XCTAssertFalse(preview.previewSaytileBorder)
        XCTAssertTrue(preview.geometrySummary.contains("无外框"))
        let borderless = TrayPlacementIllustration.frames(in: rect, configuration: settings.configuration, twoRows: true,
                                                           withSaytile: true, framed: false, flipped: false)
        XCTAssertNil(borderless.outer)
        let fullWidth = try XCTUnwrap(borderless.saytile)
        XCTAssertGreaterThan(fullWidth.width, card.width)
        XCTAssertEqual(fullWidth.width, borderless.tray.width, accuracy: 0.1)
        XCTAssertEqual(fullWidth.maxX, borderless.tray.maxX, accuracy: 0.1)
        h.publish()
        XCTAssertEqual(selector.selectedSegment, 1)
        XCTAssertFalse(h.model.hasLayoutDraft)
        XCTAssertTrue(h.requests.isEmpty)
        settings.configuration.trayFollowsSaytile = false
        h.receive(settings)
        XCTAssertTrue(h.controller.trayBorderPreviewRow.isHidden)
    }

    @MainActor func testTrayControlsApplyScaleSignedOffsetsAndStandalonePlacement() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        try await changeAndWait(h, "desktopForm", index: 0)
        XCTAssertFalse(h.controller.traySettings.isHidden)
        let toggle: NSSwitch = try control(h, "trayFollowsSaytile")
        XCTAssertEqual(toggle.state, .on)
        XCTAssertFalse(h.controller.trayGapSetting.isHidden)
        XCTAssertTrue(h.controller.geometryPreview.geometrySummary.contains("Saytile"))
        try await clickAndWait(h, "trayFollowsSaytile")
        XCTAssertEqual(toggle.state, .off)
        XCTAssertTrue(h.controller.trayGapSetting.isHidden)
        XCTAssertFalse(h.controller.geometryPreview.geometrySummary.contains("Saytile"))
        try click(h, "disclosure.tray.offsets")
        let size = try XCTUnwrap(h.controller.numericFields[.trayScalePercent])
        let offset = try XCTUnwrap(h.controller.numericFields[.trayHorizontalOffset])
        _ = try enter(h, field: size, text: "124")
        _ = try enter(h, field: offset, text: "-24")
        XCTAssertEqual(h.controller.geometryPreview.configuration.trayScalePercent, 124)
        XCTAssertEqual(h.controller.geometryPreview.configuration.trayHorizontalOffset, -24)
        try await clickAndWait(h, "layout.apply.display")
        XCTAssertEqual(h.owner.settings.configuration.trayScalePercent, 124)
        XCTAssertEqual(h.owner.settings.configuration.trayHorizontalOffset, -24)
        XCTAssertFalse(h.owner.settings.configuration.trayFollowsSaytile)
        try await changeAndWait(h, "desktopForm", index: 1)
        XCTAssertTrue(h.controller.traySettings.isHidden)
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
        XCTAssertTrue(h.controller.commonEdgeSettings.isHidden)
        XCTAssertFalse(h.controller.windChimeLineSetting.isHidden)
        XCTAssertTrue(h.controller.geometryPreview.geometrySummary.hasSuffix("风铃 · 错落"))
        XCTAssertEqual(h.controller.numericFields[.windChimeLineInset]?.stringValue, "18")
        XCTAssertEqual(arrangement.accessibilityLabel(), "风铃排列")
        XCTAssertEqual(arrangement.label(forSegment: arrangement.selectedSegment), "错落")
        try await changeAndWait(h, "windChimeArrangement", index: 0)
        XCTAssertEqual(h.owner.settings.configuration.windChimeArrangement, .aligned)
        XCTAssertTrue(h.controller.geometryPreview.geometrySummary.hasSuffix("风铃 · 整齐"))
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
        let settings = RiftSettingsCenterPreview(kind: .geometry)
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
            settings.update(configuration: config, mode: .none, reduceMotion: false)
            onboarding.configuration = config
            let alignedSettings = try raster(settings)
            let alignedOnboarding = try raster(onboarding)
            config.windChimeArrangement = .staggered
            settings.update(configuration: config, mode: .none, reduceMotion: false)
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
        XCTAssertEqual(first.titleOfSelectedItem, "自动（区域）")
        XCTAssertEqual(third.titleOfSelectedItem, "自动（留空）")
        XCTAssertEqual(third.accessibilityLabel(), "常用键 3")
        XCTAssertFalse(third.itemTitles.contains("更多"))
        let custom = try XCTUnwrap(RiftTrayFavoriteChoice.menuChoices.firstIndex(of: .mode(.window)))
        try await changeAndWait(h, "trayFavorite3", index: custom)
        XCTAssertEqual(h.owner.settings.configuration.trayFavorite(.third), .mode(.window))
        settings = h.owner.settings
        settings.defaultCaptureMode = .region
        h.receive(settings)
        XCTAssertTrue(h.controller.controls["trayFavorite1"] === first)
        XCTAssertTrue(h.controller.controls["trayFavorite3"] === third)
        XCTAssertEqual(first.titleOfSelectedItem, "自动（窗口）")
        XCTAssertEqual(third.titleOfSelectedItem, "窗口")
    }

    @MainActor func testExplicitDefaultsAndDiscardRetireOldEditorBeforeReplacingDraft() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display); try click(h, "disclosure.display.advanced"); try click(h, "disclosure.display.details")
        let width = try XCTUnwrap(h.controller.numericFields[.fitWidth])
        _ = try enter(h, field: width, text: "89")
        try await clickAndWait(h, "layout.defaults.display")
        XCTAssertNil(width.currentEditor())
        XCTAssertEqual(Double(h.model.text(for: .fitWidth)), 72)
        XCTAssertEqual(width.stringValue, h.model.text(for: .fitWidth))
        _ = try enter(h, field: width, text: "96")
        try await clickAndWait(h, "layout.discard.display")
        XCTAssertNil(width.currentEditor())
        XCTAssertEqual(Double(width.stringValue), 72)
        XCTAssertEqual(width.stringValue, h.model.text(for: .fitWidth))
        XCTAssertFalse(h.model.hasLayoutDraft)
        h.controller.show(page: .history); try change(h, "archive.preset", index: 5)
        _ = try enter(h, field: h.controller.archiveField, text: "2.5")
        try await clickAndWait(h, "archive.discard")
        XCTAssertNil(h.controller.archiveField.currentEditor())
        XCTAssertEqual(Double(h.model.archiveDraftText), 2)
        XCTAssertEqual(h.controller.archiveField.stringValue, h.model.archiveDraftText)
        h.controller.show(page: .general)
        XCTAssertFalse(h.model.hasArchiveDraft)
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testExplicitDiscardCancelsMarkedInputWithoutSavingOrReintroducingIt() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history); try change(h, "archive.preset", index: 5)
        let field = h.controller.archiveField!
        let editor = try enter(h, field: field, text: "2")
        editor.setMarkedText("2.5", selectedRange: NSRange(location: 2, length: 1), replacementRange: NSRange(location: 0, length: 1))
        h.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertTrue(editor.hasMarkedText())
        try await clickAndWait(h, "archive.discard")
        XCTAssertNil(field.currentEditor())
        XCTAssertEqual(Double(h.model.archiveDraftText), 2)
        XCTAssertEqual(field.stringValue, h.model.archiveDraftText)
        XCTAssertFalse(h.model.hasArchiveDraft)
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testMarkedCompositionSurvivesRefreshAndReturnDoesNotSave() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        try change(h, "archive.preset", index: 5)
        let field = h.controller.archiveField!
        let editor = try enter(h, field: field, text: "1.")
        editor.setMarkedText("1.5", selectedRange: NSRange(location: 2, length: 1), replacementRange: NSRange(location: 0, length: 2))
        let before = editor.markedRange()
        h.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        h.publish()
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.markedRange(), before)
        XCTAssertFalse(h.controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(h.requests.isEmpty, "IME confirmation is not an Apply command")
    }

    @MainActor func testArchiveFirstSaveUsesLastEditorTextAndDoesNotClose() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        try change(h, "archive.preset", index: 5)
        let field = h.controller.archiveField!
        let editor = try enter(h, field: field, text: "2")
        // The active editor contains the newest text even if its notification
        // has not yet been delivered when the first Save action arrives.
        editor.string = "1.5"
        try await clickAndWait(h, "archive.save")
        XCTAssertEqual(h.requests.map(\.intent), [.archiveMinutes(1.5)])
        XCTAssertEqual(h.owner.settings.archiveAfterMinutes, 1.5)
        XCTAssertTrue(h.controller.isVisible)
    }

    @MainActor func testArchiveDisableIsSeparateFromCustomZeroAndRequiresSave() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        let preset: NSPopUpButton = try control(h, "archive.preset")
        XCTAssertEqual(preset.itemTitles, ["关闭","1 分钟","2 分钟","5 分钟","10 分钟","自定义…"])
        XCTAssertEqual(preset.indexOfSelectedItem, 2)
        try change(h, "archive.preset", index: 5)
        let minutes = try XCTUnwrap(h.controller.archiveField)
        XCTAssertEqual(minutes.identifier?.rawValue, "settings.center.archive.minutes")
        _ = try enter(h, field: minutes, text: "0")
        try await clickAndWait(h, "archive.save")
        XCTAssertEqual(h.model.snapshot.domains[.archive]?.validationFailure, .invalidArchive)
        XCTAssertFalse(h.model.archiveIsDisabled)
        XCTAssertTrue(h.requests.isEmpty)
        try change(h, "archive.preset", index: 0)
        XCTAssertTrue(h.model.archiveIsDisabled)
        XCTAssertTrue(h.requests.isEmpty)
        XCTAssertEqual(h.owner.settings.archiveAfterMinutes, 2)
        XCTAssertTrue(h.model.hasArchiveDraft)
        try await clickAndWait(h, "archive.save")
        XCTAssertEqual(h.requests.map(\.intent), [.archiveMinutes(nil)])
        XCTAssertNil(h.owner.settings.archiveAfterMinutes)
        XCTAssertFalse(h.model.hasArchiveDraft)
        h.controller.window.performClose(nil)
        XCTAssertNil(h.controller.pendingCloseAlert)
        XCTAssertFalse(h.controller.isVisible)
        h.controller.show(page:.history)
        XCTAssertEqual(preset.indexOfSelectedItem, 0)
        try change(h, "archive.preset", index: 5)
        XCTAssertTrue(h.model.hasArchiveDraft)
        try await clickAndWait(h, "archive.save")
        XCTAssertEqual(h.owner.settings.archiveAfterMinutes, QueueArchivePolicy.defaultMinutes)
        h.controller.window.performClose(nil)
        XCTAssertNil(h.controller.pendingCloseAlert)
    }

    @MainActor func testFirstClosePromptsForCurrentDraftAndContinuePreservesIt() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        try change(h, "archive.preset", index: 5)
        let editor = try enter(h, field: h.controller.archiveField, text: "2.25")
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        h.controller.window.performClose(nil)
        let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
        XCTAssertEqual(alert.buttons.map(\.title), ["继续编辑", "不保存", "应用并关闭"])
        XCTAssertTrue(alert.window.defaultButtonCell === alert.buttons[0].cell,
                      "AppKit may temporarily disable the key equivalent, but Return's default choice must remain Continue")
        XCTAssertTrue(h.controller.isVisible)
        try await answerClose(h, .alertFirstButtonReturn)
        XCTAssertEqual(h.model.archiveDraftText, "2.25")
        XCTAssertTrue(h.controller.isVisible)
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testCloseEscapeRestoresDraftSelectionWithoutChangingResponderChain() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history); try change(h, "archive.preset", index: 5)
        let editor = try enter(h, field: h.controller.archiveField, text: "2.25")
        let selection = NSRange(location: 1, length: 2)
        editor.setSelectedRange(selection)
        let ordinaryEscapeFlags: [NSEvent.ModifierFlags] = [[], .capsLock, .function]
        for modifiers in ordinaryEscapeFlags {
            h.controller.window.performClose(nil)
            let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
            let previousResponder = alert.window.nextResponder
            XCTAssertTrue(alert.window.defaultButtonCell === alert.buttons[0].cell)
            let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: alert.window.windowNumber, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            XCTAssertTrue(escape.window === alert.window)
            NSApp.sendEvent(escape)
            try await waitFor("exact-sheet Escape completion") { h.controller.pendingCloseAlert == nil }
            XCTAssertTrue(alert.window.nextResponder === previousResponder)
            XCTAssertTrue(h.controller.isVisible)
            XCTAssertEqual(h.model.archiveDraftText, "2.25")
            let restoredEditor = try XCTUnwrap(h.controller.archiveField.currentEditor() as? NSTextView)
            XCTAssertEqual(restoredEditor.string, "2.25")
            XCTAssertEqual(restoredEditor.selectedRange(), selection)
            XCTAssertTrue(h.requests.isEmpty)
        }
    }

    @MainActor func testCloseEscapeDoesNotReopenOrMutateDraftAfterTeardown() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history); try change(h, "archive.preset", index: 1)
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
        h.controller.show(page: .history); try change(h, "archive.preset", index: 1)
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
        try change(h, "archive.preset", index: 1)
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
        try change(h, "archive.preset", index: 1)
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
        try change(h, "archive.preset", index: 1)
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
        XCTAssertTrue(original.informativeText.contains("尚未保存"))
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
        try click(h, "paused")
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
        try await clickAndWait(h, "paused")
        try await clickAndWait(h, "hidden")
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
        try await clickAndWait(h, "paused")
        let pause: NSSwitch = try control(h, "paused")
        XCTAssertEqual(pause.state, .off)
        XCTAssertEqual(h.model.snapshot.domains[.collection]?.pending, .collectionPaused(false))
        XCTAssertTrue(h.controller.errorLabels[.collection]!.stringValue.contains("继续收录"))
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
        XCTAssertEqual(display.titleOfSelectedItem, "已选显示器（未连接）")
        XCTAssertEqual(h.model.text(for: .fitWidth), "95.125")
        try await clickAndWait(h, "layout.apply.display")
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
        try await clickAndWait(h, "layout.defaults.display")
        try await clickAndWait(h, "layout.apply.display")
        let config = h.owner.settings.configuration
        XCTAssertEqual(config.hiddenFraction, 0.25); XCTAssertEqual(config.outerInset, 6)
        XCTAssertEqual(config.swallowDuration, 0.04)
        XCTAssertEqual([config.lineWidth, config.lineExtension, config.emptyTraceLength, config.screenPadding,
                        config.arrivalDuration, config.inwardDistance, config.reducedMotionDuration], [1.25, 21, 33, 23, 0.73, 7, 0.11])
    }

    @MainActor func testExplicitPreviewOnlyAndReducedMotionDoesNotExtendFortyMilliseconds() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .motion)
        h.controller.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(h.controller.arrivalPreview.playCount, 0)
        try await changeAndWait(h, "arrival", index: ArrivalMotionMode.allCases.firstIndex(of: .magnet)!)
        h.publish()
        XCTAssertEqual(h.controller.arrivalPreview.playCount, 0)
        try click(h, "arrival.preview")
        XCTAssertEqual(h.controller.arrivalPreview.playCount, 1)
        h.publish()
        XCTAssertEqual(h.controller.arrivalPreview.playCount, 1)
        h.accessibility.reduceMotion = true
        h.model.setDraftText("40", for: .swallowDuration)
        h.publish(); try click(h, "swallow.preview")
        XCTAssertEqual(h.controller.swallowPreview.lastDuration, 0.04, accuracy: 0.0001)
        h.controller.show(page: .general)
        XCTAssertFalse(h.controller.arrivalPreview.isAnimating)
        XCTAssertFalse(h.controller.swallowPreview.isAnimating)
    }

    @MainActor func testLoginApprovalIsNotReportedAsEnabledAndRefreshIsReadOnly() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.login.available = true; h.login.status = .requiresApproval
        h.publish(); h.controller.show()
        let login: NSSwitch = try control(h, "login")
        XCTAssertEqual(login.state, .on)
        XCTAssertTrue(h.controller.labels["login.detail"]!.stringValue.contains("尚未获准"))
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
        XCTAssertTrue(h.controller.labels["login.detail"]!.stringValue.contains("可以尝试开启"))
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
            XCTAssertTrue(detail.contains("代码 7"))
            XCTAssertTrue(detail.contains(status == .enabled ? "已允许" : "尚未获准"))
            XCTAssertTrue(h.controller.controls["login.retry"]!.isHidden)
            XCTAssertEqual(h.controller.controls["login.system"]!.isHidden, status != .requiresApproval)
        }
        XCTAssertTrue(h.actions.isEmpty)
    }

    @MainActor func testNoStorageMeasurementNeverShowsInventedZeroAndClearRequestsHostConfirmationOnce() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        XCTAssertTrue(h.controller.labels["storage"]!.stringValue.contains("尚未检查"))
        XCTAssertFalse(h.controller.labels["storage"]!.stringValue.contains("0 B"))
        XCTAssertTrue(h.actions.isEmpty)
        try await clickAndWait(h, "storage.reveal")
        XCTAssertEqual(h.actions, ["revealDataFolder"])
        try await clickAndWait(h, "history.clear")
        XCTAssertEqual(h.actions, ["revealDataFolder", "clearVisible"])
        XCTAssertNil(h.controller.window.attachedSheet, "The shared host owns the only confirmation; this surface cannot clear a store")
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testInFlightSaveKeepsOtherDomainsAvailableAndNewDraftSurvives() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.delayDomain = .layout
        h.model.setDraftText("80", for: .fitWidth)
        h.controller.show(page: .display)
        let layoutAction = h.startedActions + 1
        try click(h, "layout.apply.display")
        try await waitFor("layout owner waiting on its actual receipt") { h.continuation != nil && h.model.snapshot.domains[.layout]!.isSaving }
        XCTAssertTrue(h.model.snapshot.domains[.layout]!.isSaving)
        h.model.setDraftText("89", for: .fitWidth)
        h.controller.show()
        let pause: NSSwitch = try control(h, "paused")
        XCTAssertTrue(pause.isEnabled)
        try await clickAndWait(h, "paused")
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

    @MainActor func testResizeRetainsFieldsAndScrollableDocument() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        try click(h, "disclosure.display.advanced"); try click(h, "disclosure.display.details"); try click(h, "disclosure.display.fine")
        let field = try XCTUnwrap(h.controller.numericFields[.minimumHitHeight])
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
            XCTAssertTrue(h.controller.numericFields[.minimumHitHeight] === field)
        }
        XCTAssertNotNil(field.accessibilityLabel())
        XCTAssertFalse(field.accessibilityLabel()!.isEmpty)
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

    init() throws {
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
                case .clearVisible: actions.append("clearVisible")
                case .revealDataFolder: actions.append("revealDataFolder")
                case .loginEnabled(let value): actions.append("login:\(value)")
                case .appearance(let value): actions.append("appearance:\(value.rawValue)")
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
        case .layout, .placement, .display, .desktopForm, .windChimeArrangement, .trayTheme, .trayFollowsSaytile, .trayFavorite:
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
        snapshot.accessibility = accessibility; snapshot.login = login; snapshot.appearance = appearance
        snapshot.capabilities.initialized = true; snapshot.capabilities.canChangeCollection = true
        snapshot.capabilities.canChangeVisibility = true; snapshot.capabilities.canEditPreferences = true
        snapshot.capabilities.canClearVisible = true; snapshot.capabilities.canOpenHistory = true
        snapshot.capabilities.canCheckStorage = true; snapshot.capabilities.canRecheck = true
        snapshot.capabilities.canChooseSource = true; snapshot.capabilities.canCapture = true
        controller.update(snapshot)
    }
}
