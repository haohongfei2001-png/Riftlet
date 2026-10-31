import AppKit
import XCTest
@testable import RiftletUI

/// Software AppKit only; no screenshot, permission, browser or durable user data.
final class UnifiedSettingsTests: XCTestCase {
    @MainActor private func prepare() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer unavailable; physical settings acceptance NOT_RUN") }
    }
    @MainActor private func control<T: NSView>(_ id: String, as type: T.Type = T.self) throws -> T {
        let window = try XCTUnwrap(NSApp.windows.first { $0.identifier == RiftSetupController.windowIdentifier })
        func visit(_ view: NSView) -> T? {
            if view.identifier?.rawValue == id { return view as? T }
            for child in view.subviews { if let found = visit(child) { return found } }
            return nil
        }
        return try XCTUnwrap(visit(try XCTUnwrap(window.contentView)))
    }
    @MainActor private func send(_ control: NSControl) { _ = control.sendAction(control.action, to: control.target) }

    @MainActor func testAllPreferencePagesStayInOneWindowAndRefreshDoesNotSave() throws {
        try prepare()
        var changes: [RiftSettingsChange] = []
        var value = RiftSettingsSnapshot(entryAvailable: true, archiveAfterHours: 24)
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {}, onSettingsChange: { change in
            changes.append(change)
            if case .defaultCaptureMode(let mode) = change { value.defaultCaptureMode = mode }
            return value
        })
        defer { controller.close() }
        controller.updateSettings(value)
        XCTAssertFalse(controller.isVisible)
        for section in [RiftSettingsSection.captureEntry, .display, .privacy] { controller.show(section: section) }
        XCTAssertTrue(changes.isEmpty, "Viewing settings never starts capture or writes preferences")
        controller.show(section: .captureEntry)
        let mode: NSPopUpButton = try control("settings.captureMode")
        mode.selectItem(at: 1); send(mode)
        XCTAssertEqual(changes, [.defaultCaptureMode(.region)])
        controller.close(); controller.updateSettings(value)
        XCTAssertFalse(controller.isVisible, "Background preference refresh cannot reopen the window")
    }

    @MainActor func testFailedDisplayAndMotionWritesRestoreSavedSelections() throws {
        try prepare()
        let value = RiftSettingsSnapshot(entryAvailable: true, arrivalMode: .none,
            displays: [.init(id: 1, name: "Display A"), .init(id: 2, name: "Display B")], preferredDisplayID: 1)
        var attempts = 0
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {}, onSettingsChange: { _ in
            attempts += 1; throw CocoaError(.fileWriteNoPermission)
        })
        defer { controller.close() }
        controller.updateSettings(value); controller.show(section: .display)
        let display: NSPopUpButton = try control("settings.display")
        display.selectItem(at: 2); send(display)
        XCTAssertEqual(display.indexOfSelectedItem, 1, "The unchanged menu must still roll back an unsaved selection")
        let motion: NSPopUpButton = try control("settings.arrivalMode")
        motion.selectItem(at: 1); send(motion)
        XCTAssertEqual(motion.indexOfSelectedItem, 0)
        XCTAssertEqual(attempts, 2)
        let message: NSTextField = try control("settings.saveStatus")
        XCTAssertTrue(message.stringValue.contains("未能保存"))
    }


    @MainActor func testFailedPersistenceKeepsImmediateDisableVisibleAndNeverReportsSaved() throws {
        try prepare()
        var value = RiftSettingsSnapshot(entryAvailable: true, entryEnabled: true)
        var changes: [RiftSettingsChange] = []
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {}, onSettingsChange: { change in
            changes.append(change)
            guard case .entryEnabled(let enabled) = change else { XCTFail("Unrelated mutation"); return value }
            // Mirrors the host contract: off takes effect even if persistence
            // fails; enabling cannot take effect until the write succeeds.
            if !enabled { value.entryEnabled = false }
            value.capturePreferencesSaveFailed = true
            return value
        })
        defer { controller.close() }
        controller.update(snapshot: .init(collection: .paused, isHidden: true, isChecking: true))
        controller.updateSettings(value); controller.show(section: .captureEntry)
        let toggle: NSButton = try control("settings.entryEnabled")
        XCTAssertTrue(toggle.isEnabled, "A collection check must never block stopping built-in capture")
        toggle.performClick(nil)
        XCTAssertEqual(toggle.state, .off)
        let message: NSTextField = try control("settings.saveStatus")
        XCTAssertTrue(message.stringValue.contains("已关闭"))
        XCTAssertTrue(message.stringValue.contains("尚未保存"))
        XCTAssertFalse(message.stringValue == "已保存")
        toggle.performClick(nil)
        XCTAssertEqual(toggle.state, .off, "Failed enabling must not appear on")
        XCTAssertEqual(changes, [.entryEnabled(false), .entryEnabled(true)])
        controller.updateSettings(value)
        XCTAssertEqual(toggle.state, .off)
    }

    @MainActor func testArchiveRejectsPartialNumbersAndPreservesExplicitDisable() throws {
        try prepare()
        var changes: [RiftSettingsChange] = []
        var value = RiftSettingsSnapshot(archiveAfterHours: 24)
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {}, onSettingsChange: { change in
            changes.append(change)
            if case .archiveAfterHours(let hours) = change { value.archiveAfterHours = hours }
            return value
        })
        defer { controller.close() }
        controller.updateSettings(value); controller.show(section: .privacy)
        let hours: NSTextField = try control("settings.archiveHours")
        let save: NSButton = try control("settings.archiveSave")
        for invalid in ["1abc", "-1", "nan", "infinity", "1.2.3", ""] { hours.stringValue = invalid; save.performClick(nil) }
        XCTAssertTrue(changes.isEmpty)
        hours.stringValue = "0"; save.performClick(nil)
        hours.stringValue = "1.5"; save.performClick(nil)
        XCTAssertEqual(changes, [.archiveAfterHours(nil), .archiveAfterHours(1.5)])
    }

    @MainActor func testUnavailableEntryCannotInvokePreferenceActionAndDisconnectedDisplayIsRetained() throws {
        try prepare()
        var attempts = 0
        let value = RiftSettingsSnapshot(entryAvailable: false, displays: [.init(id: 2, name: "Available")], preferredDisplayID: 1)
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {}, onSettingsChange: { _ in
            attempts += 1; return value
        })
        defer { controller.close() }
        controller.updateSettings(value); controller.show(section: .captureEntry)
        let enabled: NSButton = try control("settings.entryEnabled")
        let capture: NSPopUpButton = try control("settings.captureMode")
        XCTAssertFalse(enabled.isEnabled); XCTAssertFalse(capture.isEnabled)
        enabled.performClick(nil); send(capture)
        XCTAssertEqual(attempts, 0)
        controller.show(section: .display)
        let display: NSPopUpButton = try control("settings.display")
        XCTAssertEqual(display.titleOfSelectedItem, "已选显示器（未连接）")
        XCTAssertEqual(attempts, 0, "Hotplug fallback must not silently change the saved display")
    }

    @MainActor func testReturnInArchiveFieldSavesWithoutDismissingSettings() async throws {
        try prepare()
        var dismissed = 0, changes: [RiftSettingsChange] = []
        var value = RiftSettingsSnapshot(archiveAfterHours: 24)
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: { dismissed += 1 }, onSettingsChange: { change in
            changes.append(change)
            if case .archiveAfterHours(let hours) = change { value.archiveAfterHours = hours.map { ($0 * 3600) / 3600 } }
            return value
        })
        defer { controller.close() }
        controller.updateSettings(value); controller.show(section: .privacy)
        let hours: NSTextField = try control("settings.archiveHours")
        hours.stringValue = "2"
        XCTAssertTrue(try XCTUnwrap(hours.window).makeFirstResponder(hours))
        let editor = try XCTUnwrap(hours.currentEditor() as? NSTextView)
        editor.insertNewline(nil)
        await Task.yield()
        XCTAssertEqual(changes, [.archiveAfterHours(2)])
        XCTAssertEqual(dismissed, 0)
        XCTAssertTrue(controller.isVisible)
        let save: NSButton = try control("settings.archiveSave")
        XCTAssertTrue(try XCTUnwrap(hours.window).makeFirstResponder(hours))
        let nextEditor = try XCTUnwrap(hours.currentEditor() as? NSTextView)
        nextEditor.string = "0.011"
        XCTAssertTrue(try XCTUnwrap(hours.window).makeFirstResponder(nil))
        await Task.yield()
        XCTAssertEqual(changes, [.archiveAfterHours(2)], "Leaving the field is not a save command")
        save.performClick(nil); save.performClick(nil)
        XCTAssertEqual(changes, [.archiveAfterHours(2), .archiveAfterHours(0.011)], "An already-saved fractional value cannot cause duplicate durable writes")
        XCTAssertTrue(controller.isVisible)
    }

    @MainActor func testBackgroundPreferenceRefreshAndUnchangedLayoutPreserveManualPreview() async throws {
        try prepare()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("System Reduce Motion correctly disables this visual preview")
        }
        var value = RiftSettingsSnapshot(entryAvailable: true, arrivalMode: .magnet, hasArrivalSelection: true)
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {}, onSettingsChange: { _ in value })
        defer { controller.close() }
        controller.updateSettings(value); controller.show(section: .display)
        let preview: ArrivalPreviewView = try control("settings.motionPreviewImage")
        var observations: [String] = [], droppedObservations = 0
        preview.diagnosticObserver = {
            if observations.count < 96 { observations.append($0) } else { droppedObservations += 1 }
        }
        defer { preview.diagnosticObserver = nil; print("PREVIEW_OBSERVATIONS_BEGIN\n" + observations.joined(separator: "\n") + "\nPREVIEW_OBSERVATIONS_END dropped=\(droppedObservations)") }
        preview.window?.contentView?.layoutSubtreeIfNeeded()
        let replay: NSButton = try control("settings.motionPreview")
        XCTAssertTrue(preview.window?.isVisible == true)
        XCTAssertGreaterThan(preview.bounds.width, 100)
        XCTAssertGreaterThan(preview.bounds.height, 80)
        let previewBoundsBeforeReplay = preview.bounds
        preview.recordDiagnostic("test.performClick.before")
        replay.performClick(nil)
        preview.recordDiagnostic("test.performClick.after")
        XCTAssertEqual(preview.bounds, previewBoundsBeforeReplay, "Replaying must not change the settings column as a native scroller appears")
        let imageLayer = try XCTUnwrap(preview.layer?.sublayers?.first?.sublayers?.first)
        preview.recordDiagnostic("test.assertLayer", observedLayer: imageLayer)
        let diagnostics = "bounds=\(preview.bounds), visible=\(preview.window?.isVisible == true), scale=\(preview.window?.backingScaleFactor ?? 0), layerKeys=\(imageLayer.animationKeys() ?? [])"
        XCTAssertNotNil(imageLayer.animation(forKey: "arrival.preview"), diagnostics)
        value.entryEnabled = false
        controller.updateSettings(value); preview.layout()
        XCTAssertNotNil(imageLayer.animation(forKey: "arrival.preview"), "An unrelated status or same-size layout cannot interrupt a deliberate preview")
        preview.viewDidChangeBackingProperties()
        XCTAssertNotNil(imageLayer.animation(forKey: "arrival.preview"), "A backing notification with unchanged physical scale cannot cancel the preview")
        controller.close()
        XCTAssertNil(imageLayer.animation(forKey: "arrival.preview"), "Closing still cancels preview work")
        // Let already delivered delegate observations be logged. This happens
        // after every original assertion; it cannot turn a missing animation
        // into a pass or extend its product duration.
        await Task.yield()
        await Task.yield()
    }

    @MainActor func testSettingsColumnKeepsItsWidthWhenNativeScrollingBecomesNecessary() async throws {
        try prepare()
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {},
            onSettingsChange: { _ in RiftSettingsSnapshot() })
        defer { controller.close() }
        controller.show(section: .display)
        let preview: ArrivalPreviewView = try control("settings.motionPreviewImage")
        let window = try XCTUnwrap(preview.window)
        let scroll = try XCTUnwrap(preview.enclosingScrollView)
        // R2's complete form exceeds small CI displays. Exercise the real
        // native scroll/form in an unconstrained test-only viewport rather
        // than asking WindowServer for an impossible off-screen tall window.
        window.contentView?.layoutSubtreeIfNeeded()
        let width = scroll.frame.width
        let canvas = NSView(frame:NSRect(x:0,y:0,width:width,height:1600))
        scroll.removeFromSuperview(); scroll.translatesAutoresizingMaskIntoConstraints = true
        canvas.addSubview(scroll)
        for style in [NSScroller.Style.legacy, .overlay] {
            scroll.scrollerStyle = style
            var expectedWidth: CGFloat?
            var overflow: [Bool] = []
            let document = try XCTUnwrap(scroll.documentView)
            scroll.frame = NSRect(x:0,y:0,width:width,height:400)
            scroll.layoutSubtreeIfNeeded(); document.layoutSubtreeIfNeeded()
            let fittingHeight = max(document.fittingSize.height,document.frame.height) + 40
            for height in [CGFloat(400), fittingHeight, CGFloat(440)] {
                scroll.frame = NSRect(x:0,y:0,width:width,height:height)
                scroll.tile(); scroll.layoutSubtreeIfNeeded(); document.layoutSubtreeIfNeeded()
                await Task.yield()
                scroll.reflectScrolledClipView(scroll.contentView)
                scroll.layoutSubtreeIfNeeded(); document.layoutSubtreeIfNeeded()
                overflow.append(document.frame.height > scroll.contentView.bounds.height)
                if let expectedWidth {
                    XCTAssertEqual(preview.bounds.width, expectedWidth,
                        "Changing scroll necessity must not shift the settings column")
                } else { expectedWidth = preview.bounds.width }
                XCTAssertGreaterThan(preview.bounds.width, 100)
            }
            XCTAssertTrue(overflow[0], "The compact viewport must actually exercise scrolling")
            XCTAssertFalse(overflow[1], "The fitting viewport must actually contain the R2 document")
        }
    }

    @MainActor func testWindowRecoveryUsesReachableTitleBarAndPreservesValidCrossDisplayPosition() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let left = NSRect(x: -1000, y: 0, width: 1000, height: 800)
        let across = NSRect(x: -200, y: 200, width: 680, height: 520)
        XCTAssertEqual(RiftVisualStyle.reachableWindowFrame(across, visibleFrames: [main, left], preferredFrame: main), across)
        let bottomSliver = NSRect(x: 100, y: 890, width: 680, height: 520)
        let recovered = RiftVisualStyle.reachableWindowFrame(bottomSliver, visibleFrames: [main], preferredFrame: main)
        XCTAssertEqual(recovered.origin, NSPoint(x: 100, y: 380))
        let sideSliver = NSRect(x: 1435, y: 100, width: 680, height: 520)
        XCTAssertEqual(RiftVisualStyle.reachableWindowFrame(sideSliver, visibleFrames: [main], preferredFrame: main).origin.x, 760)
        let oversized = NSRect(x: 9000, y: 9000, width: 1600, height: 1000)
        let accessible = RiftVisualStyle.reachableWindowFrame(oversized, visibleFrames: [main], preferredFrame: main)
        XCTAssertEqual(accessible.minX, main.minX)
        XCTAssertEqual(accessible.maxY, main.maxY)
    }
}
