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
            if case .archiveAfterHours(let hours) = change { value.archiveAfterHours = hours }
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
    }

    @MainActor func testBackgroundPreferenceRefreshAndUnchangedLayoutPreserveManualPreview() throws {
        try prepare()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("System Reduce Motion correctly disables this visual preview")
        }
        var value = RiftSettingsSnapshot(entryAvailable: true, arrivalMode: .magnet, hasArrivalSelection: true)
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {}, onSettingsChange: { _ in value })
        defer { controller.close() }
        controller.updateSettings(value); controller.show(section: .display)
        let preview: ArrivalPreviewView = try control("settings.motionPreviewImage")
        preview.window?.contentView?.layoutSubtreeIfNeeded()
        let replay: NSButton = try control("settings.motionPreview")
        replay.performClick(nil)
        let imageLayer = try XCTUnwrap(preview.layer?.sublayers?.first?.sublayers?.first)
        XCTAssertNotNil(imageLayer.animation(forKey: "arrival.preview"))
        value.entryEnabled = false
        controller.updateSettings(value); preview.layout()
        XCTAssertNotNil(imageLayer.animation(forKey: "arrival.preview"), "An unrelated status or same-size layout cannot interrupt a deliberate preview")
        controller.close()
        XCTAssertNil(imageLayer.animation(forKey: "arrival.preview"), "Closing still cancels preview work")
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
