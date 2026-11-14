import AppKit
import XCTest
@testable import RiftletUI

final class RiftControlCenterControllerTests: XCTestCase {
    @MainActor private final class OutsideMouseMonitorSpy {
        final class Token: NSObject {
            let mask: NSEvent.EventTypeMask
            let handler: (NSEvent) -> Void
            init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
                self.mask = mask; self.handler = handler
            }
        }
        var installed: [Token] = []
        var removed: [Token] = []
        func install(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) -> Any? {
            let token = Token(mask: mask, handler: handler)
            installed.append(token)
            return token
        }
        func remove(_ value: Any) { removed.append(value as! Token) }
    }

    @MainActor private func outsideMouseDown(_ type: NSEvent.EventType = .leftMouseDown) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
    }

    @MainActor private func fixture(revision: UInt64 = 1, paused: Bool = false, hidden: Bool = false,
                                    source: SetupSourceState = .accessible,
                                    collection: SetupCollectionState = .collecting,
                                    issue: SetupIssue? = nil, attachment: SetupAttachmentState = .available, entryEnabled: Bool = true,
                                    entryAvailable: Bool = true, review: Bool = false) -> SettingsProductSnapshot {
        let settings = RiftSettingsSnapshot(entryAvailable: entryAvailable, entryEnabled: entryEnabled,
            displays: [.init(id: 1, name: "合成显示器", uuid: "synthetic-display")])
        let model = try! SettingsStateModel(owner: .init(revision: revision, settings: settings,
            collectionPaused: paused, isHidden: hidden, mainDisplayID: 1),
            adapter: SettingsPersistenceClosures { _ in .unconfirmed(nil, .ownerUnavailable) })
        var value = SettingsProductSnapshot(revision: revision,
            setup: .init(source: source, collection: collection, isHidden: hidden, visibleCount: 3,
                         attachment: attachment, permission: .granted, issue: issue), state: model.snapshot)
        value.capabilities.initialized = true
        value.capabilities.canChangeCollection = true
        value.capabilities.canChangeVisibility = true
        value.capabilities.canCapture = !hidden && entryEnabled && entryAvailable && !review
        value.capabilities.canOpenHistory = true
        value.capabilities.canClearVisible = true
        value.capabilities.canEditPreferences = true
        value.reviewEnvironment = review
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
        let normal = RiftControlCenterPresentation(fixture(), copy: .simplifiedChinese)
        XCTAssertEqual(normal.state, .collecting)
        XCTAssertEqual(normal.primaryTitle, "截图…")
        let paused = RiftControlCenterPresentation(fixture(paused: true, hidden: true, collection: .paused), copy: .simplifiedChinese)
        XCTAssertEqual(paused.state, .paused)
        XCTAssertTrue(paused.detail.contains("也已隐藏"))
        XCTAssertEqual(paused.primaryTitle, "截图…")
        XCTAssertFalse(paused.primaryEnabled)
        let hidden = RiftControlCenterPresentation(fixture(hidden: true), copy: .simplifiedChinese)
        XCTAssertEqual(hidden.state, .hidden)
        XCTAssertTrue(hidden.detail.contains("仍在收录"))
        let fault = RiftControlCenterPresentation(fixture(paused: true, hidden: true, source: .unavailable, collection: .paused), copy: .simplifiedChinese)
        XCTAssertEqual(fault.state, .attention)
        XCTAssertEqual(fault.recoveryPage, .capture)
    }

    @MainActor func testTransientAttachmentContextIsNotPersistentAttentionOrFalseRunning() {
        for issue in [SetupIssue.targetUnavailable, .unsupportedBrowser, .unsupportedFormat, .imageUnavailable] {
            let projection = RiftControlCenterPresentation(fixture(issue: issue), copy: .simplifiedChinese)
            XCTAssertEqual(projection.state, .collecting)
            if issue == .targetUnavailable || issue == .unsupportedBrowser {
                XCTAssertEqual(projection.detail, issue.text(in: .simplifiedChinese))
                XCTAssertNil(projection.recoveryPage)
            }
        }
        let stopped = RiftControlCenterPresentation(fixture(collection: .stopped), copy: .simplifiedChinese)
        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertFalse(stopped.title.contains("正在收录"))
        let waiting = RiftControlCenterPresentation(fixture(hidden: true, source: .notChecked, collection: .waitingForSource), copy: .simplifiedChinese)
        XCTAssertFalse(waiting.detail.contains("仍在收录"))
    }

    @MainActor func testConnectionCheckRefusalLeadsToHelpWithoutPausingCollection() {
        var snapshot = fixture()
        snapshot.chromeConnection = .javaScriptDisabled
        let failure = RiftControlCenterPresentation(snapshot, copy: .simplifiedChinese)
        XCTAssertEqual(failure.state, .attention)
        XCTAssertEqual(failure.recoveryPage, .help)
        XCTAssertTrue(failure.detail.contains("显示 → 开发者 → 允许 Apple 事件中的 JavaScript"))
        XCTAssertFalse(snapshot.state.owner.collectionPaused)
        snapshot.chromeConnection = .ready
        XCTAssertEqual(RiftControlCenterPresentation(snapshot, copy: .simplifiedChinese).state, .collecting)
    }

    @MainActor func testLocalCollectionModesPointToHistoryWithoutInvitingChromeInput() {
        for mode in [SetupAttachmentState.productionDisabled, .offlineSimulation] {
            let projection = RiftControlCenterPresentation(fixture(issue: .targetUnavailable, attachment: mode), copy: .simplifiedChinese)
            XCTAssertEqual(projection.state, .collecting)
            XCTAssertTrue(projection.detail.contains("截图历史"))
            XCTAssertFalse(projection.detail.contains("Chrome"))
        }
    }

    @MainActor func testSaveIssueProjectsCompactRecoveryWithoutClaimingRollback() {
        var value = fixture(paused: true, hidden: true)
        value.appearance.unreadable = true
        let projection = RiftControlCenterPresentation(value, copy: .simplifiedChinese)
        XCTAssertEqual(projection.state, .attention)
        XCTAssertEqual(projection.recoveryPage, .general)
        XCTAssertTrue(projection.title.contains("确认保存"))
        XCTAssertFalse(projection.detail.contains("回滚"))
    }

    @MainActor func testEnglishControlCenterDistinguishesVisibilityFromCollectionAndKeepsRecoveryAction() {
        let hidden = RiftControlCenterPresentation(fixture(hidden: true), copy: .english)
        XCTAssertEqual(hidden.title, "Desktop Screenshots Hidden")
        XCTAssertEqual(hidden.detail, "New screenshots are still being collected.")
        let denied = RiftControlCenterPresentation(fixture(issue: .permissionDenied), copy: .english)
        XCTAssertEqual(denied.recoveryPage, .help)
        XCTAssertEqual(denied.recoveryTitle, "Check Chrome Connection")
        XCTAssertEqual(denied.primaryTitle, "Take Screenshot…")
    }

    @MainActor func testUnavailableSettingsOffersRecoveryOutsideTheFailedWindow() {
        let projection = RiftControlCenterPresentation(fixture(issue: .configurationUnavailable), copy: .simplifiedChinese)
        XCTAssertEqual(projection.state, .attention)
        XCTAssertEqual(projection.detail, SetupIssue.configurationUnavailable.text(in: .simplifiedChinese))
        XCTAssertTrue(projection.detail.contains("重新打开 Riftlet"))
        XCTAssertNil(projection.recoveryPage)
        XCTAssertNil(projection.recoveryTitle)
    }

    @MainActor func testSaveRecoveryOpensThePageThatOwnsTheFailedSetting() async throws {
        var value = fixture()
        let model = try SettingsStateModel(owner: value.state.owner,
            adapter: SettingsPersistenceClosures { _ in .unconfirmed(nil, .writeUnconfirmed) })
        _ = await model.perform(.setCollectionPaused(true))
        value.state = model.snapshot
        XCTAssertEqual(RiftControlCenterPresentation(value, copy: .simplifiedChinese).recoveryPage, .capture)
        _ = await model.perform(.setEntryEnabled(false))
        value.state = model.snapshot
        XCTAssertEqual(RiftControlCenterPresentation(value, copy: .simplifiedChinese).recoveryPage, .capture)
        _ = await model.perform(.selectPlacement(.rightBottom))
        value.state = model.snapshot
        XCTAssertEqual(RiftControlCenterPresentation(value, copy: .simplifiedChinese).recoveryPage, .display)
        XCTAssertEqual(Set(value.state.domains.compactMap { $0.value.saveFailure == nil ? nil : $0.key }),
                       [.collection, .entry, .placement], "Routing cannot clear another pending retry")
        for (issue, page): (SetupIssue, SettingsPage) in [(.screenshotPreferenceUnsaved, .capture),
                (.collectionPreferenceUnsaved, .capture), (.visibilityPreferenceUnsaved, .capture)] {
            XCTAssertEqual(RiftControlCenterPresentation(fixture(issue: issue), copy: .simplifiedChinese).recoveryPage, page)
        }
        var login = fixture()
        login.login.notConfirmed = true
        XCTAssertEqual(RiftControlCenterPresentation(login, copy: .simplifiedChinese).recoveryPage, .general)
    }

    @MainActor func testCaptureHintRetainsDisabledEntryReasonWhenVisibilityAlsoBlocksCapture() {
        for hidden in [false, true] {
            for available in [false, true] {
                let closed = RiftControlCenterPresentation(fixture(hidden: hidden,
                    entryEnabled: false, entryAvailable: available), copy: .simplifiedChinese)
                XCTAssertFalse(closed.primaryEnabled)
                XCTAssertTrue(closed.captureHint?.contains("已关闭") == true)
                XCTAssertFalse(closed.captureHint?.contains("显示桌面截图后，可以使用") == true)
            }
        }
        let unavailable = RiftControlCenterPresentation(fixture(hidden: true, entryAvailable: false), copy: .simplifiedChinese)
        XCTAssertTrue(unavailable.captureHint?.contains("当前不可用") == true)
        let hidden = RiftControlCenterPresentation(fixture(hidden: true), copy: .simplifiedChinese)
        XCTAssertTrue(hidden.captureHint?.contains("暂不可用") == true)
        XCTAssertNil(RiftControlCenterPresentation(fixture(), copy: .simplifiedChinese).captureHint)
    }

    @MainActor func testReviewStatusExplainsLocalExamplesWithoutPromisingAttachmentOrCapture() {
        let value = RiftControlCenterPresentation(fixture(hidden: false, entryEnabled: false, review: true), copy: .simplifiedChinese)
        XCTAssertEqual(value.state, .collecting)
        XCTAssertEqual(value.primaryTitle, "截图…")
        XCTAssertFalse(value.primaryEnabled)
        XCTAssertTrue(value.detail.contains("审核示例"))
        XCTAssertTrue(value.detail.contains("不会上传"))
        XCTAssertFalse(value.detail.contains("即可附加"))
        XCTAssertTrue(value.captureHint?.contains("隔离审核") == true)
    }

    @MainActor func testStatusItemUsesOfficialRiftletForegroundAsTemplate() throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = RiftControlCenterController(statusItem: item) { _ in }
        defer { controller.close() }
        let image = try XCTUnwrap(item.button?.image)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))

        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let svg = try XMLDocument(contentsOf: repo.appendingPathComponent("website-assets/riftlet.svg"))
        let paths = try svg.nodes(forXPath: "//*[local-name()='g']/*[local-name()='path']")
        XCTAssertEqual(paths.count, 2)
        let artwork = paths.map(\.xmlString).joined()
        let foreground = """
            <svg xmlns="http://www.w3.org/2000/svg" width="72" height="72" viewBox="-2 4 72 72">
              \(artwork)
            </svg>
            """
        let reference = try XCTUnwrap(NSImage(data: Data(foreground.utf8)))
        // Compare per-pixel coverage of the actual button image and canonical mark.
        for scale in [1, 2] {
            let side = 18 * scale
            func alpha(_ source: NSImage) throws -> [UInt8] {
                let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                NSGraphicsContext.saveGraphicsState()
                defer { NSGraphicsContext.restoreGraphicsState() }
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                source.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                            from: .zero, operation: .copy, fraction: 1)
                let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                return (0..<(side * side)).map { bytes[$0 * 4 + 3] }
            }
            let expected = try alpha(reference)
            let actual = try alpha(image)
            XCTAssertGreaterThan(expected.filter { $0 > 127 }.count, side * side / 4)
            let error = zip(expected, actual).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            XCTAssertLessThan(Double(error) / Double(255 * side * side), 0.025, "Scale \(scale)×")
        }
    }

    @MainActor func testHeaderKeepsWholeWordsAndFullCaptureTargetAtFixedPopoverWidth() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false // Layout only: never expose a test icon or popover.
        defer { NSStatusBar.system.removeStatusItem(item) }
        var captures = 0
        let controller = RiftControlCenterController(statusItem: item) { action in
            if case .capture = action { captures += 1 } else { XCTFail("Header issued another action") }
        }
        defer { controller.close() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsNativeStyle.controlCenterWidth, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = controller.contentView
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let title = try XCTUnwrap(descendants(controller.contentView).first { $0.identifier?.rawValue == "control.status" } as? NSTextField)
        let capture = try XCTUnwrap(controller.control(identifier: "control.capture") as? NSButton)
        let states = [fixture(), fixture(revision: 2, paused: true, collection: .paused),
                      fixture(revision: 3, hidden: true), fixture(revision: 4, source: .unavailable),
                      fixture(revision: 5, issue: .chromeJavaScriptDisabled)]
        for state in states {
            controller.update(state)
            controller.contentView.layoutSubtreeIfNeeded()
            let font = try XCTUnwrap(title.font)
            // Measure actual localized words with the real heading font. A
            // word may wrap as a unit, but never split because the action stole its width.
            let words = title.stringValue.split(whereSeparator: \.isWhitespace)
            let requiredWordWidth = words.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            if ProductCopy.current == .english {
                XCTAssertGreaterThanOrEqual(title.bounds.width + 1, requiredWordWidth + 4, title.stringValue)
            }
            if state.revision == 1 {
                let full = (title.stringValue as NSString).size(withAttributes: [.font: font])
                XCTAssertGreaterThanOrEqual(title.bounds.width + 1, full.width + 4, "Ordinary collecting status fits without splitting words")
            }
            XCTAssertGreaterThanOrEqual(capture.bounds.width + 1, capture.intrinsicContentSize.width)
            XCTAssertGreaterThanOrEqual(capture.bounds.height + 1, capture.intrinsicContentSize.height)
            let titleRect = title.convert(title.bounds, to: controller.contentView)
            let captureRect = capture.convert(capture.bounds, to: controller.contentView)
            XCTAssertFalse(titleRect.intersects(captureRect))
            // Stack layout uses the button's alignment rect. Some macOS
            // versions extend its rounded bezel/hit frame beyond that rect.
            let captureParent = try XCTUnwrap(capture.superview)
            let captureAlignmentRect = captureParent.convert(capture.alignmentRect(forFrame: capture.frame),
                                                             to: controller.contentView)
            XCTAssertGreaterThanOrEqual(captureAlignmentRect.minX, 17)
            XCTAssertLessThanOrEqual(captureAlignmentRect.maxX, SettingsNativeStyle.controlCenterWidth - 17)
            XCTAssertGreaterThanOrEqual(captureRect.minX, 0)
            XCTAssertLessThanOrEqual(captureRect.maxX, SettingsNativeStyle.controlCenterWidth)
            XCTAssertEqual(capture.accessibilityLabel(), capture.title)
            XCTAssertEqual(controller.contentView.bounds.width, SettingsNativeStyle.controlCenterWidth)
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(controller.isShown)
        }
        controller.update(fixture(revision: 6))
        controller.contentView.layoutSubtreeIfNeeded()
        let parent = try XCTUnwrap(capture.superview)
        for point in [CGPoint(x: 2, y: capture.bounds.midY), CGPoint(x: capture.bounds.maxX - 2, y: capture.bounds.midY)] {
            let hit = capture.hitTest(capture.convert(point, to: parent))
            XCTAssertTrue(hit === capture || hit?.isDescendant(of: capture) == true)
        }
        capture.performClick(nil)
        await assertReceived { captures == 1 }
        XCTAssertEqual(captures, 1)
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
        let originalPause = try XCTUnwrap(controller.contextMenu.items.first { $0.title == ProductCopy.text("暂停收录", "Pause Collection") })
        controller.update(fixture(revision: 2, paused: true, collection: .paused))
        XCTAssertNotNil(controller.contextMenu.items.first { $0.title == ProductCopy.text("继续收录", "Resume Collection") })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(originalPause.action), to: originalPause.target, from: originalPause))
        await assertReceived { values.count == 1 }
        XCTAssertEqual(values, [true], "An already displayed command must not invert a newer owner state")
        XCTAssertNotNil(controller.contextMenu.items.first { $0.title == ProductCopy.text("定位最早截图", "Locate Oldest Screenshot") })
        XCTAssertEqual(controller.contextMenu.items.first { $0.title == ProductCopy.text("设置…", "Settings…") }?.keyEquivalent, ",")
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
        var openedSettings = 0
        var transitions: [String] = []
        let controller = RiftControlCenterController(statusItem: item) { action in
            if case .openSettings = action {
                XCTAssertEqual(transitions, ["willClose"], "Native close must begin before the host action is dispatched")
                transitions.append("openSettings")
                openedSettings += 1
            }
        }
        let closeObserver = NotificationCenter.default.addObserver(forName: NSPopover.willCloseNotification,
                                                                   object: nil, queue: .main) { [weak controller] notification in
            MainActor.assumeIsolated {
                guard let controller, let popover = notification.object as? NSPopover,
                      popover.contentViewController?.view === controller.contentView else { return }
                transitions.append("willClose")
            }
        }
        defer {
            NotificationCenter.default.removeObserver(closeObserver)
            controller.close()
        }
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
            // Auto Layout constrains alignment rects; the native switch's
            // ornamental frame may extend beyond its constrained width.
            let copyRect = copy.alignmentRect(forFrame: copy.frame)
            let toggleRect = toggle.alignmentRect(forFrame: toggle.frame)
            let rowWidth = row.alignmentRect(forFrame: row.frame).width
            XCTAssertEqual(copyRect.width + toggleRect.width + row.spacing, rowWidth, accuracy: 1)
            XCTAssertEqual(toggleRect.minX - copyRect.maxX, row.spacing, accuracy: 1)
        }
        let firstWindow = controller.window
        button.performClick(nil)
        await assertReceived { !controller.isShown && controller.window?.isVisible != true }
        XCTAssertFalse(controller.isShown)
        XCTAssertFalse(controller.window?.isVisible == true)
        button.performClick(nil)
        XCTAssertTrue(controller.isShown)
        await assertReceived { controller.isShown && controller.window?.isVisible == true }
        XCTAssertTrue(controller.window === firstWindow)
        let settings = try XCTUnwrap(controller.control(identifier: "control.settings") as? NSButton)
        transitions.removeAll()
        settings.performClick(nil)
        await assertReceived { openedSettings == 1 }
        XCTAssertEqual(transitions, ["willClose", "openSettings"])
        // isShown can remain true during close animation. Separately verify
        // both ordering above and the native window's eventual disappearance.
        await assertReceived { !controller.isShown && controller.window?.isVisible != true }
        XCTAssertFalse(controller.isShown)
        XCTAssertFalse(controller.window?.isVisible == true)
    }

    @MainActor func testExplicitShowMakesPopoverKeyAndNativeEscapeRetiresItsPresentation() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let monitor = OutsideMouseMonitorSpy()
        var actions = 0
        let controller = RiftControlCenterController(statusItem: item, onAction: { _ in actions += 1 },
            installOutsideMouseMonitor: monitor.install, removeOutsideMouseMonitor: monitor.remove)
        defer { controller.close() }
        var value = fixture()
        value.accessibility.reduceMotion = true
        controller.update(value)
        let button = try XCTUnwrap(item.button)
        guard button.window?.isVisible == true else { throw XCTSkip("No usable native status-bar anchor") }

        button.performClick(nil)
        await assertReceived { controller.isShown && controller.window?.isKeyWindow == true }
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(NSApp.keyWindow === window, "The explicitly opened popover must own its native keyboard route")
        XCTAssertEqual(monitor.installed.count, 1)

        // Route Escape through NSApplication/NSWindow rather than invoking the
        // controller's close/cancel handler. Cross-App hardware routing remains
        // a separate full-App acceptance check.
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        await assertReceived { !controller.isShown && !window.isVisible }
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertEqual(monitor.removed.count, 1, "Native keyboard dismissal retires the outside observer")
        XCTAssertTrue(monitor.removed.first === monitor.installed.first)
        XCTAssertEqual(actions, 0, "Dismissal must not issue a host command")

        button.performClick(nil)
        await assertReceived { controller.isShown && controller.window?.isKeyWindow == true }
        XCTAssertTrue(NSApp.keyWindow === controller.window)
        XCTAssertEqual(monitor.installed.count, 2)
        button.performClick(nil)
        await assertReceived { !controller.isShown && controller.window?.isVisible != true }
        XCTAssertEqual(monitor.removed.count, 2, "Repeated status activation still closes the new presentation")
        XCTAssertEqual(actions, 0)
    }

    @MainActor func testOutsideMouseObserverClosesWithoutCommandsAndExistsOnlyWhileShown() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let monitor = OutsideMouseMonitorSpy()
        var actions = 0
        let controller = RiftControlCenterController(statusItem: item, onAction: { _ in actions += 1 },
            installOutsideMouseMonitor: monitor.install, removeOutsideMouseMonitor: monitor.remove)
        defer { controller.close() }
        controller.update(fixture())
        XCTAssertTrue(monitor.installed.isEmpty, "Passive snapshots must not start cross-application observation")
        let button = try XCTUnwrap(item.button)
        guard button.window?.isVisible == true else { throw XCTSkip("No usable native status-bar anchor") }
        button.performClick(nil)
        await assertReceived { controller.isShown && controller.window?.isVisible == true }
        XCTAssertEqual(monitor.installed.count, 1)
        let token = try XCTUnwrap(monitor.installed.first)
        XCTAssertEqual(token.mask, [.leftMouseDown, .rightMouseDown, .otherMouseDown], "No keys, movement, or mouse-up observation")
        controller.update(fixture(revision: 2))
        XCTAssertEqual(monitor.installed.count, 1, "A shown snapshot refresh must not add another monitor")

        // Deliver a copy through the installed callback. Real WindowServer
        // cross-App delivery is separately verified by the owned native fixture.
        token.handler(try outsideMouseDown())
        XCTAssertEqual(monitor.removed.count, 1, "Close retires observation immediately, before any animation completes")
        XCTAssertTrue(monitor.removed.first === token)
        await assertReceived { !controller.isShown && controller.window?.isVisible != true }
        controller.close()
        controller.update(fixture(revision: 3))
        XCTAssertEqual(monitor.removed.count, 1)
        XCTAssertEqual(monitor.installed.count, 1)
        XCTAssertEqual(actions, 0, "Outside dismissal cannot issue capture, preferences, or other host commands")
    }

    @MainActor func testQueuedOutsideMouseCallbackCannotCloseAReopenedPopover() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let monitor = OutsideMouseMonitorSpy()
        var actions = 0
        let controller = RiftControlCenterController(statusItem: item, onAction: { _ in actions += 1 },
            installOutsideMouseMonitor: monitor.install, removeOutsideMouseMonitor: monitor.remove)
        defer { controller.close() }
        controller.update(fixture())
        let button = try XCTUnwrap(item.button)
        guard button.window?.isVisible == true else { throw XCTSkip("No usable native status-bar anchor") }
        button.performClick(nil)
        await assertReceived { controller.isShown && controller.window?.isVisible == true }
        let old = try XCTUnwrap(monitor.installed.first)
        controller.close()
        await assertReceived { !controller.isShown && controller.window?.isVisible != true }
        button.performClick(nil)
        await assertReceived { controller.isShown && controller.window?.isVisible == true }
        XCTAssertEqual(monitor.installed.count, 2)
        let current = try XCTUnwrap(monitor.installed.last)
        XCTAssertFalse(old === current)

        old.handler(try outsideMouseDown())
        XCTAssertTrue(controller.isShown, "An asynchronously retained event belongs only to its old presentation")
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertEqual(monitor.removed.count, 1)
        current.handler(try outsideMouseDown(.rightMouseDown))
        await assertReceived { !controller.isShown && controller.window?.isVisible != true }
        XCTAssertEqual(monitor.removed.count, 2)
        XCTAssertTrue(monitor.removed.last === current)
        XCTAssertEqual(actions, 0)
    }

    @MainActor func testNaturalCloseSuspensionAndDeinitRemoveOutsideMouseObservation() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let monitor = OutsideMouseMonitorSpy()
        var controller: RiftControlCenterController? = RiftControlCenterController(statusItem: item, onAction: { _ in },
            installOutsideMouseMonitor: monitor.install, removeOutsideMouseMonitor: monitor.remove)
        weak var released = controller
        var nativePopover: NSPopover?
        let observer = NotificationCenter.default.addObserver(forName: NSPopover.didShowNotification, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated {
                guard let popover = notification.object as? NSPopover,
                      popover.contentViewController?.view === controller?.contentView else { return }
                nativePopover = popover
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            controller?.close(); nativePopover?.close()
        }
        controller?.update(fixture())
        let button = try XCTUnwrap(item.button)
        guard button.window?.isVisible == true else { throw XCTSkip("No usable native status-bar anchor") }
        button.performClick(nil)
        await assertReceived { controller?.isShown == true && nativePopover != nil }
        let popover = try XCTUnwrap(nativePopover)
        popover.close() // Exercise the native delegate path, not controller.close().
        await assertReceived { controller?.isShown == false && monitor.removed.count == 1 }

        button.performClick(nil)
        await assertReceived { controller?.isShown == true && monitor.installed.count == 2 }
        controller?.setInteractionSuspended(true)
        XCTAssertEqual(monitor.removed.count, 2)
        await assertReceived { controller?.isShown == false }
        controller?.setInteractionSuspended(false)
        button.performClick(nil)
        await assertReceived { controller?.isShown == true && monitor.installed.count == 3 }
        controller = nil
        // Dropping our owner does not guarantee same-turn destruction after
        // native target-action/presentation work. Wait for actual deinit and
        // cleanup without closing the popover or clearing any callback/target;
        // a persistent retain cycle must still fail the bounded predicate.
        await assertReceived { released == nil && monitor.removed.count == 3 }
        XCTAssertNil(released, "Monitor callbacks must not retain the controller")
        XCTAssertEqual(monitor.removed.count, 3, "Deinit retires a still-shown presentation's observer")
        // A retained callback after owner destruction is harmless.
        try XCTUnwrap(monitor.installed.last).handler(try outsideMouseDown())
        XCTAssertEqual(monitor.removed.count, 3)
    }

    @MainActor func testApplicationResignNotificationDoesNotExplicitlyCloseStatusPopover() async throws {
        try prepareAppKit()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var actions = 0
        let controller = RiftControlCenterController(statusItem: item) { _ in actions += 1 }
        defer { controller.close() }
        controller.update(fixture())
        let button = try XCTUnwrap(item.button)
        guard button.window?.isVisible == true else { throw XCTSkip("No usable native status-bar anchor; real menu focus acceptance remains separate") }
        button.performClick(nil)
        let shown = await receive { controller.isShown && controller.window?.isVisible == true }
        XCTAssertTrue(shown)
        guard shown else { return }
        let shownWindow = try XCTUnwrap(controller.window)

        // A status-bar popover may hand application activation back without an
        // outside click. This isolates our notification handler from AppKit's
        // native transient interaction policy; it does not simulate OS focus.
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)

        XCTAssertTrue(controller.isShown, "A lifecycle notification alone must not invoke an unconditional close")
        XCTAssertTrue(controller.window === shownWindow)
        XCTAssertTrue(shownWindow.isVisible)
        XCTAssertEqual(actions, 0)
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
        let staleMenu = try XCTUnwrap(controller.contextMenu.items.first { $0.title == ProductCopy.text("暂停收录", "Pause Collection") })
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
