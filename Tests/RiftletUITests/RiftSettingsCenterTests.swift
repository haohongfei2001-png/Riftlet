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
    @MainActor private func settle() async {
        for _ in 0..<8 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    @MainActor private func control<T: NSControl>(_ host: SettingsCenterTestHost, _ id: String, as type: T.Type = T.self) throws -> T {
        try XCTUnwrap(host.controller.controls[id] as? T)
    }
    @MainActor private func click(_ host: SettingsCenterTestHost, _ id: String) throws {
        let button: NSButton = try control(host, id)
        button.performClick(nil)
    }
    @MainActor private func change(_ host: SettingsCenterTestHost, _ id: String, index: Int) throws {
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
    @MainActor private func answerClose(_ host: SettingsCenterTestHost, _ response: NSApplication.ModalResponse) async throws {
        let alert = try XCTUnwrap(host.controller.pendingCloseAlert)
        alert.window.animationBehavior = .none
        host.controller.window.endSheet(alert.window, returnCode: response)
        for _ in 0..<100 {
            if host.controller.pendingCloseAlert == nil { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(host.controller.pendingCloseAlert, "Native sheet completion must arrive before asserting the selected outcome")
        await settle()
    }

    @MainActor func testSixPagesShareOneWindowAndViewingNeverPersists() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        let window = h.controller.window
        XCTAssertFalse(h.controller.isVisible)
        for page in SettingsPage.allCases {
            h.controller.show(page: page)
            XCTAssertTrue(h.controller.window === window)
            XCTAssertEqual(h.controller.selectedPage, page)
            XCTAssertTrue(h.controller.scroll.documentView === h.controller.pages[page])
        }
        h.publish()
        XCTAssertTrue(h.actions.isEmpty)
        XCTAssertTrue(h.requests.isEmpty)
        h.controller.closeForTeardown(); h.publish()
        XCTAssertFalse(h.controller.isVisible, "Background updates do not open a closed settings window")
    }

    @MainActor func testNativeFieldsKeepIdentityRawTextAndSelectionAcrossOwnerRefresh() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        try click(h, "disclosure.display.details")
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
        try click(h, "archive.save")
        await settle()
        XCTAssertEqual(h.requests.map(\.intent), [.archiveHours(1.5)])
        XCTAssertEqual(h.owner.settings.archiveAfterHours, 1.5)
        XCTAssertTrue(h.controller.isVisible)
    }

    @MainActor func testArchivePresetIsDraftAndZeroDisablesOnlyOnSave() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        try change(h, "archive.preset", index: 0)
        XCTAssertTrue(h.requests.isEmpty)
        XCTAssertEqual(h.owner.settings.archiveAfterHours, 24)
        XCTAssertTrue(h.model.hasArchiveDraft)
        try click(h, "archive.save"); await settle()
        XCTAssertEqual(h.requests.map(\.intent), [.archiveHours(nil)])
        XCTAssertNil(h.owner.settings.archiveAfterHours)
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
        XCTAssertEqual(alert.buttons[0].keyEquivalent, "\u{1b}")
        XCTAssertTrue(h.controller.isVisible)
        try await answerClose(h, .alertFirstButtonReturn)
        XCTAssertEqual(h.model.archiveDraftText, "2.25")
        XCTAssertTrue(h.controller.isVisible)
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testApplyAndCloseWaitsForActualConfirmation() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .history)
        try change(h, "archive.preset", index: 1)
        h.controller.window.performClose(nil)
        try await answerClose(h, .alertThirdButtonReturn)
        XCTAssertEqual(h.owner.settings.archiveAfterHours, 1)
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertEqual(h.requests.count, 1)
    }

    @MainActor func testFailedApplyAndCloseRetainsWindowAndDraft() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.failures = [.archive]
        h.controller.show(page: .history)
        try change(h, "archive.preset", index: 1)
        h.controller.window.performClose(nil)
        try await answerClose(h, .alertThirdButtonReturn)
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
        try await answerClose(h, .alertThirdButtonReturn)
        XCTAssertEqual(h.owner.settings.configuration.fitWidth, 81)
        XCTAssertTrue(h.controller.isVisible)
        h.failures = []
        h.controller.window.performClose(nil)
        try await answerClose(h, .alertThirdButtonReturn)
        XCTAssertFalse(h.controller.isVisible)
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .layout }.count, 1)
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .archive }.count, 2)
    }

    @MainActor func testThreeStopErrorsStayIndependentAndRetryOriginalDirection() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.failures = [.collection, .visibility, .entry]
        h.controller.show()
        try click(h, "paused"); await settle()
        try click(h, "hidden"); await settle()
        h.controller.show(page: .capture)
        try click(h, "entry"); await settle()
        XCTAssertTrue(h.owner.collectionPaused); XCTAssertTrue(h.owner.isHidden); XCTAssertFalse(h.owner.settings.entryEnabled)
        for domain in [SettingsDomain.collection, .visibility, .entry] { XCTAssertTrue(h.model.snapshot.domains[domain]?.hasIssue == true) }
        _ = await h.model.perform(.setArrival(.magnet))
        for domain in [SettingsDomain.collection, .visibility, .entry] { XCTAssertTrue(h.model.snapshot.domains[domain]?.hasIssue == true) }
        h.failures = []
        try click(h, "retry.entry"); await settle()
        XCTAssertFalse(h.model.snapshot.domains[.entry]!.hasIssue)
        XCTAssertTrue(h.model.snapshot.domains[.collection]!.hasIssue)
        h.controller.show()
        try click(h, "retry.collection"); await settle()
        try click(h, "retry.visibility"); await settle()
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .entry }.map(\.intent), [.entryEnabled(false), .entryEnabled(false)])
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .collection }.map(\.intent), [.collectionPaused(true), .collectionPaused(true)])
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .visibility }.map(\.intent), [.hidden(true), .hidden(true)])
    }

    @MainActor func testFailedResumeKeepsActualStoppedSwitchAndRetryUsesResume() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        _ = await h.model.perform(.setCollectionPaused(true))
        h.failures = [.collection]
        h.controller.show()
        try click(h, "paused"); await settle()
        let pause: NSButton = try control(h, "paused")
        XCTAssertEqual(pause.state, .on)
        XCTAssertEqual(h.model.snapshot.domains[.collection]?.pending, .collectionPaused(false))
        XCTAssertTrue(h.controller.errorLabels[.collection]!.stringValue.contains("继续收录"))
        h.failures = []; try click(h, "retry.collection"); await settle()
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
        try click(h, "layout.apply.display"); await settle()
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
        _ = display.sendAction(display.action, to: display.target)
        await settle()
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
        XCTAssertEqual(display.itemArray.compactMap { ($0.representedObject as? NSNumber)?.uint32Value }, [1, 2])
        try change(h, "display", index: 1); await settle()
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
        try click(h, "layout.defaults.display"); await settle()
        try click(h, "layout.apply.display"); await settle()
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
        try change(h, "arrival", index: ArrivalMotionMode.allCases.firstIndex(of: .magnet)!)
        await settle(); h.publish()
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
        let login: NSButton = try control(h, "login")
        XCTAssertEqual(login.state, .on)
        XCTAssertTrue(h.controller.labels["login.detail"]!.stringValue.contains("尚未获准"))
        XCTAssertFalse(h.controller.controls["login.system"]!.isHidden)
        XCTAssertTrue(h.actions.isEmpty)
        h.login.status = .unknown; h.publish()
        XCTAssertFalse(login.isEnabled)
    }

    @MainActor func testLoginOperationErrorDoesNotEraseEnabledOrPendingApprovalReadback() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.login.available = true; h.login.errorCode = 7
        h.controller.show()
        for status in [SettingsLoginStatus.enabled, .requiresApproval] {
            h.login.status = status; h.login.failedTarget = nil; h.login.notConfirmed = false; h.publish()
            let login: NSButton = try control(h, "login")
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
        try click(h, "history.clear")
        await settle()
        XCTAssertEqual(h.actions, ["clearVisible"])
        XCTAssertNil(h.controller.window.attachedSheet, "The shared host owns the only confirmation; this surface cannot clear a store")
        XCTAssertTrue(h.requests.isEmpty)
    }

    @MainActor func testInFlightSaveKeepsOtherDomainsAvailableAndNewDraftSurvives() async throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.delayDomain = .layout
        h.model.setDraftText("80", for: .fitWidth)
        h.controller.show(page: .display)
        try click(h, "layout.apply.display"); await settle()
        XCTAssertTrue(h.model.snapshot.domains[.layout]!.isSaving)
        h.model.setDraftText("89", for: .fitWidth)
        h.controller.show()
        let pause: NSButton = try control(h, "paused")
        XCTAssertTrue(pause.isEnabled)
        try click(h, "paused"); await settle()
        XCTAssertTrue(h.owner.collectionPaused)
        h.controller.window.performClose(nil)
        let alert = try XCTUnwrap(h.controller.pendingCloseAlert)
        XCTAssertFalse(alert.buttons[1].isEnabled, "Discard cannot cancel an in-flight write")
        try await answerClose(h, .alertFirstButtonReturn)
        h.resumeSave(); await settle()
        XCTAssertEqual(h.model.text(for: .fitWidth), "89")
        XCTAssertTrue(h.model.hasLayoutDraft)
        XCTAssertEqual(h.requests.filter { $0.intent.domain == .layout }.count, 1)
    }

    @MainActor func testResizeRetainsFieldsAndScrollableDocument() throws {
        let h = try host(); defer { h.controller.closeForTeardown() }
        h.controller.show(page: .display)
        try click(h, "disclosure.display.details"); try click(h, "disclosure.display.fine")
        let field = try XCTUnwrap(h.controller.numericFields[.minimumHitHeight])
        let size = SettingsNativeStyle.settingsMinimumSize
        h.controller.window.setContentSize(size)
        h.controller.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(h.controller.numericFields[.minimumHitHeight] === field)
        XCTAssertTrue(h.controller.scroll.hasVerticalScroller)
        XCTAssertGreaterThan(h.controller.pages[.display]!.frame.height, h.controller.scroll.contentView.bounds.height)
        XCTAssertEqual(h.controller.scroll.scrollerStyle, .legacy)
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
            archiveAfterHours: 24, configuration: configuration)
        owner = .init(revision: 1, settings: settings, collectionPaused: false, isHidden: false, mainDisplayID: 1, effectiveDisplayID: 1)
        model = try SettingsStateModel(owner: owner, decimalSeparator: ".", adapter: SettingsPersistenceClosures { [weak self] request in
            guard let self else { return .unconfirmed(nil, .ownerUnavailable) }
            return await save(request)
        })
        controller = RiftSettingsCenterController(model: model) { [weak self] action in
            guard let self else { return }
            if case .settings(let command) = action { _ = await model.perform(command) }
            else {
                switch action {
                case .clearVisible: actions.append("clearVisible")
                case .loginEnabled(let value): actions.append("login:\(value)")
                case .appearance(let value): actions.append("appearance:\(value.rawValue)")
                default: actions.append("hostAction")
                }
            }
            publish()
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
        case .archiveHours(let value): if !failure { settings.archiveAfterHours = value }
        case .layout, .placement, .display:
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
