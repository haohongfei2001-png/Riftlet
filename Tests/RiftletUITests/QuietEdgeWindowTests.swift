import AppKit
import XCTest
@testable import RiftletUI

final class QuietEdgeWindowTests: XCTestCase {
    @MainActor private func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
    @MainActor private func setupWindow() throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0.identifier == RiftSetupController.windowIdentifier })
    }
    @MainActor private func button(_ id: String) throws -> NSButton {
        let content = try XCTUnwrap(try setupWindow().contentView)
        return try XCTUnwrap(descendants(content).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id })
    }
    @MainActor func testOnboardingPagesDoNotRequestPermissionOrUploadAndDismissOnce() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit window server unavailable") }
        var permission = 0, dismissed = 0
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: { permission += 1 }, onDismiss: { dismissed += 1 })
        defer { controller.close() }
        controller.update(snapshot: .init(attachment: .systemScreenshotCandidate, permission: .notRequested))
        controller.showOnboarding()
        XCTAssertEqual(try setupWindow().frame.size, NSSize(width: 560, height: 520))
        XCTAssertEqual(permission, 0)
        try button("setup.next").performClick(nil)
        XCTAssertEqual(permission, 0, "Entering the connection page is not consent")
        XCTAssertTrue(try button("setup.permission").isEnabled)
        try button("setup.next").performClick(nil)
        XCTAssertEqual(try button("setup.next").title, "开始使用")
        XCTAssertEqual(try button("setup.next").accessibilityLabel(), "开始使用")
        try button("setup.next").performClick(nil)
        XCTAssertEqual(dismissed, 1)
        XCTAssertFalse(controller.isVisible)
        controller.update(snapshot: .init(source: .unavailable, issue: .sourceAccess))
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(permission, 0)
    }
    @MainActor func testSettingsActionIsExplicitAndOnboardingDoesNotReplaceStatusCallbacks() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit window server unavailable") }
        var hidden = 0, paused = 0
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {}, onDismiss: {},
            onToggleHidden: { hidden += 1 }, onToggleCollection: { paused += 1 })
        defer { controller.close() }
        controller.showOnboarding()
        try button("setup.later").performClick(nil)
        controller.show()
        XCTAssertEqual(try setupWindow().frame.size, NSSize(width: 680, height: 520))
        try button("setup.hide").performClick(nil)
        XCTAssertEqual(hidden, 1); XCTAssertEqual(paused, 0)
        try button("setup.pause").performClick(nil)
        XCTAssertEqual(paused, 1)
    }
}
