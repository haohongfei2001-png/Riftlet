import AppKit
import XCTest
import RiftletCapture
import RiftletCore
@testable import RiftletUI

/// Real AppKit callbacks in a software window-server session. These tests do
/// not prove rendered pixels, physical input or live ChatGPT attachment state.
final class PresentationBoundaryTests: XCTestCase {
    private func record(_ sequence: Int64 = 1, image: ImportedAsset? = nil,
                        origin: AssetOrigin = .synthetic, status: QueueStatus = .pending,
                        operationID: UUID? = nil, visibility: QueueVisibility = .visible,
                        revision: Int64 = 0, reason: QueueVisibilityReason = .capture) -> AssetRecord {
        let id = UUID()
        let asset = image ?? ImportedAsset(id: id, sourceKey: "presentation-\(id)",
            fileName: "\(id).png", sha256: String(repeating: "d", count: 64),
            byteCount: 80, pixelWidth: 160, pixelHeight: 100,
            mediaType: "image/png", origin: origin)
        return AssetRecord(image: asset, sequence: sequence, status: status,
            activeOperationID: operationID, visibility: visibility,
            visibilityRevision: revision, visibilityReason: reason)
    }

    @MainActor private func controller(
        holdsSelection: Bool = false,
        onBoundary: @escaping (RiftPresentationBoundary) -> Void = { _ in },
        onSelection: @escaping (RiftSelectionBoundary) -> Void = { _ in },
        onSelect: @escaping (UUID) -> Void = { _ in }
    ) throws -> RiftPanelController {
        _ = NSApplication.shared
        guard NSScreen.screens.contains(where: { $0.visibleFrame.height >= 400 }) else {
            throw XCTSkip("No window-server screen for software presentation boundaries; physical GUI remains separate")
        }
        var configuration = RiftConfiguration()
        configuration.arrivalDuration = 0.01
        configuration.pressDuration = 0.01
        configuration.swallowDuration = 0.02
        configuration.shiftDuration = 0.01
        configuration.reducedMotionDuration = 0.02
        return RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
            configuration: configuration, arrivalMode: .magnet, onSelectionBoundary: onSelection,
            onPresentationBoundary: onBoundary, holdsSelectionUntilFinished: holdsSelection,
            onSelect: onSelect)
    }

    @MainActor private func rowView(_ id: UUID, in panel: RiftPanelController) throws -> NSView {
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == id })
        let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.windowNumber })
        return try XCTUnwrap(window.contentView)
    }

    @MainActor func testWaitingFeedbackIsAccessibleAndStaleClearPreservesNewCancellation() throws {
        var selected = 0
        let panel = try controller(onSelect: { _ in selected += 1 }); defer { panel.close() }
        let asset = record(); panel.render([asset])
        let geometry = panel.diagnosticSnapshot.rows
        let view = try rowView(asset.id, in: panel)
        let waiting = "已接收，正在等待附加；本次尚未上传。"
        let cancelled = "此次附加已取消，图片保留；本次未上传。"
        panel.setFeedback(waiting, for: asset.id)
        XCTAssertTrue(view.accessibilityLabel()?.contains(waiting) == true)
        XCTAssertEqual(view.accessibilityHelp(), waiting)
        panel.setFeedback(cancelled, for: asset.id)
        panel.clearFeedback(matching: waiting, for: asset.id)
        XCTAssertEqual(view.toolTip, cancelled)
        XCTAssertTrue(view.accessibilityLabel()?.contains(cancelled) == true)
        panel.clearFeedback(matching: cancelled, for: asset.id)
        XCTAssertFalse(view.accessibilityLabel()?.contains(cancelled) == true)
        XCTAssertEqual(panel.diagnosticSnapshot.rows, geometry)
        XCTAssertEqual(selected, 0, "Presentation feedback cannot dispatch an input")
    }

    @MainActor func testFeedbackOwnerAndRevisionRejectIdenticalOldClearAndOldOperation() throws {
        var selected = 0
        let panel = try controller(onSelect: { _ in selected += 1 }); defer { panel.close() }
        let operation = UUID(), nextOperation = UUID()
        let asset = record(operationID: operation, revision: 7)
        panel.render([asset])
        let view = try rowView(asset.id, in: panel)
        let text = "附加处理中，结果尚待确认。", oldOwner = UUID(), newOwner = UUID()
        panel.setFeedback(text, for: asset.id, owner: .selection(oldOwner), visibilityRevision: 7)
        panel.setFeedback(text, for: asset.id, owner: .selection(newOwner), visibilityRevision: 7)
        panel.clearFeedback(matching: text, for: asset.id, owner: .selection(oldOwner))
        XCTAssertEqual(view.accessibilityHelp(), text, "Matching words cannot clear another selection owner")
        panel.setFeedback("迟到的旧版本", for: asset.id, owner: .selection(oldOwner), visibilityRevision: 6)
        XCTAssertEqual(view.accessibilityHelp(), text)
        panel.render([record(image: asset.image, operationID: nextOperation, revision: 7)])
        XCTAssertNotEqual(view.accessibilityHelp(), text, "A new operation clears the previous projection")
        panel.setFeedback(text, for: asset.id, owner: .operation(operation), visibilityRevision: 7)
        XCTAssertNotEqual(view.accessibilityHelp(), text, "The previous operation cannot reappear on the same asset")
        panel.setFeedback(text, for: asset.id, owner: .operation(nextOperation), visibilityRevision: 7)
        XCTAssertEqual(view.accessibilityHelp(), text)
        panel.clearFeedback(matching: text, for: asset.id, owner: .operation(operation))
        XCTAssertEqual(view.accessibilityHelp(), text)
        panel.clearFeedback(matching: text, for: asset.id, owner: .operation(nextOperation))
        XCTAssertNotEqual(view.accessibilityHelp(), text)
        XCTAssertEqual(selected, 0)
    }

    @MainActor func testPreparedFeedbackWaitsForSelectionReleaseThenUsesCommittedOperation() throws {
        var selected = 0
        let panel = try controller(holdsSelection: true, onSelect: { _ in selected += 1 })
        defer { panel.close() }
        let asset = record(revision: 3), operation = UUID()
        panel.render([asset])
        let view = try rowView(asset.id, in: panel)
        XCTAssertTrue(view.accessibilityPerformPress())
        panel.render([record(image: asset.image, status: .transferring, operationID: operation, revision: 3)])
        let text = "附加处理中，结果尚待确认。"
        panel.setFeedback(text, for: asset.id, owner: .operation(operation), visibilityRevision: 3, timing: .waiting)
        XCTAssertNotEqual(view.accessibilityHelp(), text, "A deferred old row cannot accept a newer operation yet")
        panel.finishSelection(asset.id)
        // The host refreshes after release, instead of letting an old operation
        // bypass the live selection guard during the first committed refresh.
        panel.setFeedback(text, for: asset.id, owner: .operation(operation), visibilityRevision: 3, timing: .waiting)
        XCTAssertEqual(view.accessibilityHelp(), text)
        XCTAssertEqual(selected, 1, "Reprojection never replays the user's selection")
    }

    @MainActor func testTrayMenuCannotRecreateASwallowedInputWindow() throws {
        var seen: [RiftPresentationBoundary] = []
        let panel = try controller(onBoundary: { seen.append($0) })
        defer { panel.close() }
        var config = panel.requestedConfiguration
        config.desktopForm = .tray
        try panel.updateConfiguration(config)
        panel.setTrayCapture(enabled: true, defaultMode: .window)
        let a = record(), b = record(2), operation = UUID()
        panel.render([a, b])
        panel.render([record(image: a.image, status: .transferring, operationID: operation,
                             visibility: .swallowed, revision: 1, reason: .uploadStarted), b])
        panel.setTrayExpanded(true)
        XCTAssertEqual(seen.map(\.phase), [.swallowScheduled, .swallowActualStart, .swallowClose])
        XCTAssertTrue(seen.allSatisfy { $0.assetID == a.id && $0.operationID == operation })
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [b.id])
        advanceQuietEdgeRefill(panel)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [b.id])
    }

    @MainActor private func coldTray() throws -> RiftPanelController {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer required for the cold tray") }
        var configuration = RiftConfiguration()
        configuration.desktopForm = .tray
        configuration.shiftDuration = 0
        return RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory, configuration: configuration,
                                   reduceMotionOverride: { false }, onSelect: { _ in XCTFail("Opening the camera selected a screenshot") })
    }

    @MainActor private func visibleTrayWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView is RiftTraySurfaceView }
    }

    @MainActor func testColdTrayPublishesOneActionableCameraAtTheFirstQueueSnapshot() throws {
        for count in [0, 1, 3] {
            let panel = try coldTray()
            defer { panel.close() }
            panel.onTrayCapture = { _ in XCTFail("Opening the menu invoked a capture mode") }
            panel.setTrayCapture(enabled: true, defaultMode: .window)
            XCTAssertNil(visibleTrayWindow(), "Configuration precedes the first real queue snapshot")

            let records = (0..<count).map { record(Int64($0 + 1)) }
            panel.render(records)
            let glass = try XCTUnwrap(visibleTrayWindow())
            let view = try XCTUnwrap(glass.contentView)
            let buttons = view.subviews.compactMap { $0 as? NSButton }
            let first = buttons.filter { !$0.isHidden }
            XCTAssertEqual(first.compactMap { $0.accessibilityLabel() }, [ProductCopy.text("展开截图方式", "Show Capture Modes")])
            let camera = try XCTUnwrap(first.first)
            XCTAssertTrue(camera.isEnabled)
            XCTAssertNil(camera.layer?.animation(forKey: "rift.tray.morph"), "The first visible camera must already accept its action")
            XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), records.map(\.id))
            let original = glass.frame
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(camera.action), to: camera.target, from: camera))
            XCTAssertEqual(buttons.filter { !$0.isHidden }.count, 4)
            XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), records.dropFirst().map(\.id))
            XCTAssertEqual(glass.frame, original)
            if count == 0 {
                let arrived = record()
                panel.render([arrived])
                XCTAssertGreaterThan(glass.frame.height, original.height)
                XCTAssertEqual(buttons.filter { !$0.isHidden }.count, 4)
                XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [arrived.id])
                panel.setTrayExpanded(false)
                XCTAssertEqual(glass.frame, original)
                XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [arrived.id])
            }
        }
    }

    @MainActor func testTrayCardAndHitWindowsStayAboveGlassAndRestoreLevelsAfterScreenCapture() throws {
        let panel = try coldTray()
        defer { panel.close() }
        let records = [record(), record(2), record(3)]
        panel.setTrayCapture(enabled: true, defaultMode: .window)
        panel.render(records)
        let glass = try XCTUnwrap(visibleTrayWindow())
        XCTAssertTrue(glass.hasShadow, "The glass panel owns the only exterior tray shadow")
        let rows = panel.diagnosticSnapshot.rows
        XCTAssertEqual(rows.map(\.assetID), records.map(\.id))
        let cardWindows = try rows.flatMap { row in
            [try XCTUnwrap(NSApp.window(withWindowNumber: row.windowNumber)),
             try XCTUnwrap(NSApp.window(withWindowNumber: row.imageInputWindowNumber))]
        }
        XCTAssertEqual(glass.level.rawValue, NSWindow.Level.floating.rawValue - 1)
        XCTAssertFalse(NSApp.windows.contains { $0 !== glass && $0.isVisible && $0.ignoresMouseEvents && $0.level == glass.level && $0.frame.contains(glass.frame) })
        XCTAssertTrue(cardWindows.allSatisfy { $0.isVisible && $0.level == .floating })
        let windows = [glass] + cardWindows
        let previousLevels = windows.map(\.level)
        panel.setCaptureSessionActive(true)
        panel.render(records)
        let captureLevel = InteractiveScreenshotController.controlsWindowLevel
        XCTAssertEqual(captureLevel.rawValue, NSWindow.Level.statusBar.rawValue + 1)
        XCTAssertTrue(windows.allSatisfy { $0.isVisible && $0.level == captureLevel })
        panel.setCaptureSessionActive(false)
        XCTAssertEqual(windows.map(\.level), previousLevels)
        panel.render(records)
        XCTAssertEqual(windows.map(\.level), previousLevels)
    }

    @MainActor func testAppearancePreviewAndCommitKeepActualButtonsAndVisibleCardWindows() throws {
        let panel = try coldTray()
        defer { panel.close() }
        let records = [record(), record(2), record(3)]
        panel.setTrayCapture(enabled: true, defaultMode: .window)
        panel.render(records)
        panel.setTrayExpanded(true)
        let surface = try XCTUnwrap(visibleTrayWindow())
        let before = panel.diagnosticSnapshot.rows
        let keys = try XCTUnwrap(surface.contentView).subviews.compactMap { $0 as? NSButton }
        let previous = panel.requestedConfiguration
        panel.previewTrayAppearance(transparency: 0.75, cameraBodyColor: "#FFFFFF")
        XCTAssertEqual(panel.requestedConfiguration, previous)
        panel.clearTrayAppearancePreview()
        var persisted = previous
        persisted.trayCameraBodyColor = "#367DD9"
        panel.applyTrayAppearance(persisted)
        XCTAssertEqual(panel.requestedConfiguration, persisted)
        XCTAssertIdentical(surface, visibleTrayWindow())
        XCTAssertEqual(surface.alphaValue, 1)
        XCTAssertEqual(keys.filter { !$0.isHidden }.count, 4)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.windowNumber), before.map(\.windowNumber))
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.imageInputWindowNumber), before.map(\.imageInputWindowNumber))
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), before.map(\.assetID))
    }

    @MainActor func testCommittedSelectionLeavesTrayBeforeFinishAndOnlyExplicitHistoryClickAttachesAgain() throws {
        var selections: [UUID] = []
        let panel = try controller(holdsSelection: true, onSelect: { selections.append($0) })
        defer { panel.close() }
        let asset = record(revision: 7)
        panel.render([asset], recentHistory: [])
        XCTAssertTrue(try rowView(asset.id, in: panel).accessibilityPerformPress())
        let retained = record(image: asset.image, status: .failed, operationID: UUID(),
            visibility: .swallowed, revision: 8, reason: .traySelection)
        panel.render([], recentHistory: [retained])
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(panel.selectionRevision(for: asset.id), 7)
        XCTAssertFalse(panel.selectionIsFromRecentHistory(for: asset.id))
        panel.showRecentHistory(true)
        XCTAssertFalse(try rowView(asset.id, in: panel).accessibilityPerformPress())
        XCTAssertEqual(selections, [asset.id])
        panel.finishSelection(asset.id)
        XCTAssertTrue(try rowView(asset.id, in: panel).accessibilityPerformPress())
        XCTAssertEqual(panel.selectionRevision(for: asset.id), 8)
        XCTAssertTrue(panel.selectionIsFromRecentHistory(for: asset.id))
        panel.render([], recentHistory: [retained])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [asset.id])
        XCTAssertEqual(selections, [asset.id, asset.id])
        panel.finishSelection(asset.id)
        XCTAssertNil(panel.selectionRevision(for: asset.id))
        XCTAssertFalse(panel.selectionIsFromRecentHistory(for: asset.id))
    }

    @MainActor func testSwitchFormsRetainsAcceptedSelectionUntilItsOwnerFinishes() throws {
        var selected: [UUID] = []
        let panel = try controller(holdsSelection: true, onSelect: { selected.append($0) })
        defer { panel.close() }
        let a = record(revision: 7), b = record(2)
        var config = panel.requestedConfiguration
        config.desktopForm = .microSlit
        try panel.updateConfiguration(config)
        panel.render([a, b])
        let original = try rowView(a.id, in: panel)
        XCTAssertTrue(original.accessibilityPerformPress())
        config.desktopForm = .tray
        try panel.updateConfiguration(config)
        XCTAssertEqual(panel.selectionRevision(for: a.id), 7)
        XCTAssertEqual(selected, [a.id])
        panel.finishSelection(a.id)
        XCTAssertEqual(panel.configuration.desktopForm, .tray)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [a.id, b.id])
        XCTAssertFalse(original.accessibilityPerformPress())
        XCTAssertEqual(selected, [a.id])
    }

    func testOldActiveCardDoesNotPretendUnloadedHistoryIsAdjacent() {
        let old = record(1), current = record(50), earlier = record(49, visibility: .archived, reason: .automaticArchive)
        let state = RiftTimelineSnapshot(active: [old, current], page: [current, earlier], hasOlder: true)
        XCTAssertEqual(state.records.map(\.sequence), [50, 49])
        XCTAssertEqual(state.oldestPageSequence, 49)
        XCTAssertEqual(state.byID[old.id], old)
    }

    @MainActor func testNativeScrollingKeepsCaptureOrderAndPagesPastTwentyWithoutSelecting() throws {
        func inputWindow(in panel: RiftPanelController) throws -> NSWindow {
            let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
            return try XCTUnwrap(NSApp.window(withWindowNumber: row.imageInputWindowNumber))
        }
        func wheel(_ points: Int32, in panel: RiftPanelController) throws {
            panel.scrollTimeline(with: try TimelineWheelFixture.event(in: inputWindow(in: panel),
                                                                       units: .pixel, delta: points))
        }
        for form in RiftDesktopForm.allCases where form.isAvailable {
            _ = NSApplication.shared
            guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer required") }
            var configuration = RiftConfiguration()
            configuration.desktopForm = form
            var selections: [UUID] = []
            let panel = RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
                configuration: configuration, reduceMotionOverride: { true }, holdsSelectionUntilFinished: true,
                onSelect: { selections.append($0) })
            defer { panel.close() }
            panel.setTrayCapture(enabled: true, defaultMode: .window)
            let a = record(39), c = record(41)
            let b = record(40, status: .used, visibility: .swallowed, revision: 1, reason: .traySelection)
            let earlier = (1...38).map { record(Int64($0), visibility: .archived, reason: .automaticArchive) }
            let all = earlier + [a, b, c]
            var cursors: [Int64] = []
            var pendingPage: Int64?
            panel.onLoadOlderTimeline = { cursor in
                cursors.append(cursor)
                pendingPage = cursor
            }
            panel.render([a, c], timeline: Array(all.suffix(24)), hasOlder: true)
            XCTAssertEqual(Set(panel.diagnosticSnapshot.rows.map(\.assetID)), [a.id, c.id])
            try TimelineWheelFixture.trackpad(in: inputWindow(in: panel), delta: 2,
                                               deliver: panel.scrollTimeline(with:))
            _ = TimelineWheelFixture.wait(until: { panel.timelineOffset > 0 })
            XCTAssertGreaterThan(panel.timelineOffset, 0)
            XCTAssertLessThan(panel.timelineOffset, 8, "The first scroll must move by pixels")
            var seen = Set(panel.diagnosticSnapshot.rows.map(\.assetID))
            func sampleRows() {
                let rows = panel.diagnosticSnapshot.rows.map(\.assetID)
                XCTAssertEqual(Set(rows).count, rows.count)
                seen.formUnion(rows)
            }
            var checkedOrigins = false
            for _ in 0..<1200 {
                let before = panel.timelineOffset
                try wheel(8, in: panel)
                guard TimelineWheelFixture.wait(until: { panel.timelineOffset > before }, sampling: sampleRows)
                else { XCTFail("Forward trackpad motion stopped at \(before) of \(panel.maximumTimelineOffset)"); break }
                if let cursor = pendingPage {
                    // Main loads the older rows asynchronously from SQLite. Deliver
                    // them after AppKit returns from the triggering wheel event.
                    pendingPage = nil
                    XCTAssertEqual(cursor, 18)
                    let offset = panel.timelineOffset
                    let visible = Set(panel.diagnosticSnapshot.rows.map(\.assetID))
                    let oldMaximum = panel.maximumTimelineOffset
                    panel.render([a, c], timeline: all, hasOlder: false)
                    XCTAssertGreaterThan(panel.maximumTimelineOffset, oldMaximum)
                    XCTAssertEqual(panel.timelineOffset, offset, accuracy: 1)
                    XCTAssertTrue(visible.isSubset(of: Set(panel.diagnosticSnapshot.rows.map(\.assetID))))
                    sampleRows()
                }
                let rows = panel.diagnosticSnapshot.rows.map(\.assetID)
                if !checkedOrigins && Set(rows).isSuperset(of: [a.id, b.id, c.id]) {
                    for item in [a, b] {
                        XCTAssertTrue(try rowView(item.id, in: panel).accessibilityPerformPress())
                        XCTAssertEqual(panel.selectionIsFromRecentHistory(for: item.id), item.id == b.id)
                        panel.finishSelection(item.id)
                    }
                    checkedOrigins = true
                }
                if panel.maximumTimelineOffset - panel.timelineOffset < 1 { break }
            }
            XCTAssertEqual(panel.timelineOffset, panel.maximumTimelineOffset, accuracy: 1)
            XCTAssertEqual(cursors, [18])
            let missingSequences = all.filter { !seen.contains($0.id) }.map(\.sequence)
            XCTAssertEqual(seen, Set(all.map(\.id)), "\(form.rawValue) missing sequences \(missingSequences)")
            XCTAssertEqual(selections, [a.id, b.id])
            for _ in 0..<500 where panel.timelineOffset > 0 {
                let before = panel.timelineOffset
                try wheel(-40, in: panel)
                guard TimelineWheelFixture.wait(until: { panel.timelineOffset < before })
                else { XCTFail("Reverse trackpad motion stopped at \(before)"); break }
            }
            XCTAssertEqual(panel.timelineOffset, 0)
            XCTAssertEqual(Set(panel.diagnosticSnapshot.rows.map(\.assetID)), [a.id, c.id])
        }
    }

    @MainActor func testTimelineReadFailureCanRetrySameCursorAtClampedEdge() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer required") }
        var configuration = RiftConfiguration()
        configuration.desktopForm = .tray
        var pressed: [UUID] = [], selected: [UUID] = []
        let panel = RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
            configuration: configuration, reduceMotionOverride: { true },
            onPress: { id, _ in pressed.append(id) }, onSelect: { selected.append($0) })
        defer { panel.close() }
        panel.setTrayCapture(enabled: true, defaultMode: .window)
        let all = (1...41).map { record(Int64($0), visibility: .archived, reason: .automaticArchive) }
        var cursors: [Int64] = []
        panel.onLoadOlderTimeline = { cursors.append($0) }
        panel.render([], timeline: Array(all.suffix(24)), hasOlder: true)
        panel.showOldest()
        XCTAssertEqual(panel.timelineOffset, panel.maximumTimelineOffset)
        XCTAssertGreaterThan(panel.timelineOffset, 0)
        XCTAssertEqual(cursors, [18])

        func continueScrollingOlder() throws {
            let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
            let window = try XCTUnwrap(NSApp.window(withWindowNumber: row.imageInputWindowNumber))
            panel.scrollTimeline(with: try TimelineWheelFixture.event(in: window, units: .line, delta: 1))
        }

        panel.olderTimelineReadFailed(before: 17)
        try continueScrollingOlder()
        XCTAssertEqual(cursors, [18], "An unrelated completion must not unlock the current read")

        panel.olderTimelineReadFailed(before: 18)
        XCTAssertEqual(cursors, [18], "Reporting a failure must not immediately retry")
        try continueScrollingOlder()
        XCTAssertEqual(cursors, [18, 18], "A new explicit scroll can retry the same cursor without moving the clip")
        try continueScrollingOlder()
        XCTAssertEqual(cursors, [18, 18], "A second gesture cannot duplicate the in-flight read")
        let oldMaximum = panel.maximumTimelineOffset
        panel.render([], timeline: all, hasOlder: false)
        XCTAssertGreaterThan(panel.maximumTimelineOffset, oldMaximum)
        panel.olderTimelineReadFailed(before: 18)
        panel.showOldest()
        XCTAssertEqual(cursors, [18, 18])
        XCTAssertTrue(pressed.isEmpty)
        XCTAssertTrue(selected.isEmpty)
    }

    @MainActor func testTimelineRetryNeedsFreshGestureAfterMomentumAndReflow() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer required") }
        var configuration = RiftConfiguration()
        configuration.desktopForm = .tray
        var pressed: [UUID] = [], selected: [UUID] = []
        let panel = RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
            configuration: configuration, reduceMotionOverride: { true },
            onPress: { id, _ in pressed.append(id) }, onSelect: { selected.append($0) })
        defer { panel.close() }
        panel.setTrayCapture(enabled: true, defaultMode: .window)
        let all = (1...44).map { record(Int64($0), visibility: .archived, reason: .automaticArchive) }
        let original = Array(all[17..<41])
        var cursors: [Int64] = []
        panel.onLoadOlderTimeline = { cursors.append($0) }
        panel.render([], timeline: original, hasOlder: true)
        panel.showOldest()
        XCTAssertEqual(cursors, [18])
        panel.navigate(up: false)
        XCTAssertGreaterThan(panel.timelineOffset, 0)
        XCTAssertLessThan(panel.timelineOffset, panel.maximumTimelineOffset)

        func inputWindow() throws -> NSWindow {
            let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
            return try XCTUnwrap(NSApp.window(withWindowNumber: row.imageInputWindowNumber))
        }
        func olderWheel(_ delta: Int32, phase: CGScrollPhase? = nil,
                        momentum: Int64? = nil) throws {
            let event = try TimelineWheelFixture.event(in: inputWindow(), units: .pixel, delta: delta,
                                                       phase: phase, momentum: momentum)
            if momentum != nil { XCTAssertFalse(event.momentumPhase.isEmpty) }
            panel.scrollTimeline(with: event)
        }

        panel.olderTimelineReadFailed(before: 18)
        try olderWheel(8, phase: .changed)
        XCTAssertEqual(cursors, [18], "An old trackpad change is not a fresh gesture")
        let beforeMomentum = panel.timelineOffset
        try olderWheel(0, momentum: 1) // kCGMomentumScrollPhaseBegin
        try olderWheel(8, momentum: 2) // kCGMomentumScrollPhaseContinue
        try olderWheel(0, momentum: 3) // kCGMomentumScrollPhaseEnd
        XCTAssertTrue(TimelineWheelFixture.wait(until: { panel.timelineOffset > beforeMomentum }))
        XCTAssertEqual(cursors, [18], "Even moving momentum must not retry a failed cursor")

        let beforeReflow = panel.timelineOffset
        panel.render([], timeline: original + Array(all.suffix(3)), hasOlder: true)
        XCTAssertGreaterThan(panel.timelineOffset, beforeReflow, "Retaining an anchor shifts the scroll offset")
        XCTAssertEqual(cursors, [18], "A programmatic anchor change cannot retry")
        try TimelineWheelFixture.trackpad(in: inputWindow(), delta: -8, deliver: panel.scrollTimeline(with:))
        XCTAssertEqual(cursors, [18], "A fresh gesture toward the latest end cannot retry")
        try TimelineWheelFixture.trackpad(in: inputWindow(), delta: 1, horizontal: 16, deliver: panel.scrollTimeline(with:))
        XCTAssertEqual(cursors, [18], "Horizontal motion with a small older-bound component cannot retry")
        // The fixture begins with zero delta and continues with native .changed.
        try TimelineWheelFixture.trackpad(in: inputWindow(), delta: 24, deliver: panel.scrollTimeline(with:))
        XCTAssertEqual(cursors, [18, 18], "A fresh older-bound trackpad gesture retries exactly once")
        panel.showOldest()
        XCTAssertEqual(cursors, [18, 18], "An in-flight retry stays latched")
        panel.olderTimelineReadFailed(before: 18)
        panel.showOldest()
        XCTAssertEqual(cursors, [18, 18, 18], "The explicit Oldest action may retry")

        panel.render([], timeline: Array(all[9...]), hasOlder: true)
        panel.showOldest()
        XCTAssertEqual(cursors, [18, 18, 18, 10])
        panel.olderTimelineReadFailed(before: 18)
        panel.showOldest()
        XCTAssertEqual(cursors, [18, 18, 18, 10], "A late prior-cursor failure cannot unlock the new request")
        XCTAssertTrue(pressed.isEmpty)
        XCTAssertTrue(selected.isEmpty)
    }

    @MainActor func testExplicitPagingAfterSwallowKeepsItsPageOnLaterFailure() throws {
        let panel = try controller()
        defer { panel.close() }
        var config = panel.configuration
        config.swallowDuration = 0
        config.shiftDuration = 0
        try panel.updateConfiguration(config)
        let first = record(), rest = (2...10).map { record(Int64($0)) }
        panel.render([first] + rest)
        let op = UUID()
        panel.render([record(image: first.image, status: .transferring, operationID: op,
                             visibility: .swallowed, revision: 1, reason: .uploadStarted)] + rest)
        advanceQuietEdgeRefill(panel)
        panel.showLatest()
        let page = panel.diagnosticSnapshot.rows.map(\.assetID)
        XCTAssertFalse(page.contains(first.id))
        let failed = record(image: first.image, status: .failed, operationID: op,
                            visibility: .swallowed, revision: 2, reason: .uploadStarted)
        panel.render(rest, recentHistory: [failed])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), page)
    }

    @MainActor func testOriginalStartIdentitySurvivesDeferredReadyAndClosesOnlyOnce() async throws {
        var boundaries: [RiftPresentationBoundary] = []
        let panel = try controller(onBoundary: { boundaries.append($0) })
        defer { panel.close() }
        let first = record(revision: 3), other = record(2), operation = UUID()
        panel.render([first, other])
        panel.render([record(image: first.image, status: .transferring,
                             operationID: operation, revision: 3), other])
        XCTAssertTrue(boundaries.isEmpty, "Click/input-pending state cannot claim visual swallowing")

        let started = record(image: first.image, status: .transferring,
            operationID: operation, visibility: .swallowed, revision: 4, reason: .uploadStarted)
        panel.render([started, other])
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart])
        let ready = record(image: first.image, status: .used,
            operationID: operation, visibility: .swallowed, revision: 4, reason: .uploadStarted)
        // A later committed backend snapshot arrives before the close callback.
        panel.render([ready, other])
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart, .swallowClose])
        XCTAssertTrue(boundaries.allSatisfy { $0.assetID == first.id && $0.operationID == operation
            && $0.visibilityRevision == 4 })
        XCTAssertEqual(Set(boundaries.map(\.generation)).count, 1)
        XCTAssertTrue(boundaries.allSatisfy { $0.uptime.isFinite && $0.uptime > 0 })
        for boundary in boundaries { XCTAssertEqual(boundary.actualDuration, 0.02, accuracy: 0.000_001) }
        for (earlier, later) in zip(boundaries, boundaries.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.uptime, later.uptime)
        }
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [other.id])
        panel.render([ready, other])
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(boundaries.count, 3, "Final READY must not replay start or close for an already hidden asset")
    }

    @MainActor func testHideCancelsCloseAndHiddenSnapshotsDoNotInventPresentation() async throws {
        var boundaries: [RiftPresentationBoundary] = []
        let panel = try controller(onBoundary: { boundaries.append($0) })
        defer { panel.close() }
        let first = record(), operation = UUID()
        panel.render([first])
        panel.render([record(image: first.image, status: .transferring,
            operationID: operation, visibility: .swallowed, revision: 1, reason: .uploadStarted)])
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart])
        panel.setUserHidden(true)
        let unknown = record(image: first.image, status: .unknown,
            operationID: operation, visibility: .swallowed, revision: 1, reason: .uploadStarted)
        let neverShown = record(2), otherOperation = UUID()
        panel.render([unknown, neverShown])
        panel.render([unknown, record(2, image: neverShown.image, status: .transferring,
            operationID: otherOperation, visibility: .swallowed, revision: 1, reason: .uploadStarted)])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart],
                       "User hiding closes windows, but is not a completed swallow animation")
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        panel.setUserHidden(false)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(boundaries.count, 2, "An upload that started while hidden has no synthetic presentation history")
    }

    @MainActor func testControllerCloseCancelsPendingSwallowCloseCallback() async throws {
        var boundaries: [RiftPresentationBoundary] = []
        let panel = try controller(onBoundary: { boundaries.append($0) })
        defer { panel.close() }
        let first = record(), operation = UUID()
        panel.render([first])
        let started = record(image: first.image, status: .unknown,
            operationID: operation, visibility: .swallowed, revision: 8, reason: .uploadStarted)
        panel.render([started])
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart])
        panel.close()
        panel.render([started])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart])
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
    }

    @MainActor func testSyntheticAXIdentityRequiresVisibleRowAndPreservesSelectionGuard() async throws {
        var selected: [UUID] = [], selections: [RiftSelectionBoundary] = []
        let panel = try controller(holdsSelection: true,
            onSelection: { selections.append($0) }, onSelect: { selected.append($0) })
        defer { panel.close() }
        let synthetic = record(revision: 6)
        let real = record(2, origin: .systemScreenshot, revision: 2)
        let transferring = record(3, status: .transferring, operationID: UUID())
        panel.render([synthetic, real, transferring])
        let syntheticView = try rowView(synthetic.id, in: panel)
        let realView = try rowView(real.id, in: panel)
        let transferringView = try rowView(transferring.id, in: panel)
        XCTAssertEqual(syntheticView.accessibilityIdentifier(), "riftlet-synthetic-\(synthetic.id.uuidString)")
        XCTAssertEqual(realView.accessibilityIdentifier(), "", "A real screenshot cannot expose an acceptance target ID")
        XCTAssertTrue(syntheticView.isAccessibilityEnabled())
        XCTAssertFalse(transferringView.isAccessibilityEnabled())
        XCTAssertFalse(transferringView.accessibilityPerformPress())

        XCTAssertTrue(syntheticView.accessibilityPerformPress())
        XCTAssertFalse(syntheticView.accessibilityPerformPress(), "The AX identifier cannot bypass an in-flight selection")
        XCTAssertEqual(selected, [synthetic.id])
        XCTAssertEqual(panel.selectionRevision(for: synthetic.id), 6)
        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(selections.first?.source, .accessibility)
        XCTAssertNil(selections.first?.eventNumber)
        XCTAssertNil(selections.first?.windowNumber)
        XCTAssertNil(selections.first?.clickCount)
        panel.finishSelection(synthetic.id)

        // Adding the synthetic selector must not replace the original real-row
        // accessibility selection path. Core/adapter eligibility remains separate.
        XCTAssertTrue(realView.accessibilityPerformPress())
        XCTAssertEqual(selected, [synthetic.id, real.id])
        XCTAssertFalse(realView.accessibilityPerformPress())
        panel.finishSelection(real.id)
        panel.render([record(image: synthetic.image, status: .transferring,
            operationID: UUID(), visibility: .swallowed, revision: 7, reason: .uploadStarted), real, transferring])
        XCTAssertEqual(syntheticView.accessibilityIdentifier(), "")
        XCTAssertFalse(syntheticView.isAccessibilityEnabled())
        XCTAssertFalse(syntheticView.accessibilityPerformPress())

        panel.setUserHidden(true)
        XCTAssertEqual(transferringView.accessibilityIdentifier(), "")
        XCTAssertFalse(transferringView.isAccessibilityEnabled())
        XCTAssertFalse(realView.accessibilityPerformPress())
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(selected, [synthetic.id, real.id])
    }
}
