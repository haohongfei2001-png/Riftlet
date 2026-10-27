import AppKit
import XCTest
@testable import RiftletUI

final class RiftSetupControllerTests: XCTestCase {
    @MainActor private func prepareAppKit() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else {
            throw XCTSkip("No window server; first-use software window needs AppKit, real permission UI remains NOT_RUN")
        }
    }

    @MainActor private func button(_ identifier: String) throws -> NSButton {
        let window = try XCTUnwrap(NSApp.windows.first { $0.identifier == RiftSetupController.windowIdentifier })
        func find(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.identifier?.rawValue == identifier { return button }
            for child in view.subviews { if let value = find(child) { return value } }
            return nil
        }
        return try XCTUnwrap(find(try XCTUnwrap(window.contentView)))
    }

    @MainActor func testBackgroundUpdatesNeverShowOrReopenGuidance() throws {
        try prepareAppKit()
        var dismissals = 0
        let controller = RiftSetupController(onRecheck: {}, onOpenSource: {}, onPermission: {},
                                            onDismiss: { dismissals += 1 })
        defer { controller.close() }
        controller.update(snapshot: .init(source: .accessible, collection: .collecting, visibleCount: 1))
        XCTAssertFalse(controller.isVisible)
        controller.show()
        XCTAssertTrue(controller.isVisible)
        try button("setup.done").performClick(nil)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(dismissals, 1)
        controller.update(snapshot: .init(source: .accessible, collection: .collecting,
                                          isHidden: true, visibleCount: 2, pendingCount: 1))
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(dismissals, 1)
        controller.show()
        controller.close()
        XCTAssertEqual(dismissals, 1, "Owner teardown must not count as a deliberate dismissal")
    }

    @MainActor func testStaleDeniedPermissionCannotOfferOrInvokeAuthorizationInCaptureOnlyMode() throws {
        try prepareAppKit()
        var requests = 0, sources = 0, rechecks = 0
        let controller = RiftSetupController(onRecheck: { rechecks += 1 }, onOpenSource: { sources += 1 },
                                            onPermission: { requests += 1 }, onDismiss: {})
        defer { controller.close() }
        controller.update(snapshot: .init(attachment: .productionDisabled, permission: .denied))
        let permission = try button("setup.permission")
        XCTAssertTrue(permission.isHidden)
        XCTAssertFalse(permission.isEnabled)
        permission.performClick(nil)
        try button("setup.source").performClick(nil)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(sources, 0)
        try button("setup.recheck").performClick(nil)
        XCTAssertEqual(rechecks, 1)
        XCTAssertFalse(controller.isVisible, "A status refresh must not open the window")
        controller.update(snapshot: .init(sourceLocation: "/tmp/synthetic-screenshots", attachment: .syntheticWeb,
                                          permission: .denied))
        XCTAssertFalse(permission.isHidden)
        XCTAssertTrue(permission.isEnabled)
        XCTAssertEqual(permission.title, "打开自动化设置…")
        permission.performClick(nil)
        try button("setup.source").performClick(nil)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(sources, 1)
        controller.update(snapshot: .init(attachment: .syntheticWeb, permission: .denied, isChecking: true))
        XCTAssertFalse(permission.isEnabled)
        permission.performClick(nil)
        XCTAssertEqual(requests, 1, "A check/consent already in flight cannot start another permission action")
    }

    @MainActor func testNativeControlsKeepHideAndPauseIndependentAndAccessible() throws {
        try prepareAppKit()
        var hidden = 0, paused = 0, history = 0, rechecks = 0, sourceGrants = 0
        let controller = RiftSetupController(onRecheck: { rechecks += 1 }, onOpenSource: {}, onPermission: {}, onDismiss: {},
            onChooseSourceAccess: { sourceGrants += 1 },
            onToggleHidden: { hidden += 1 }, onToggleCollection: { paused += 1 }, onOpenHistory: { history += 1 })
        defer { controller.close() }
        controller.update(snapshot: .init(collection: .paused, isHidden: true))
        let hide = try button("setup.hide"), pause = try button("setup.pause")
        XCTAssertEqual(hide.title, "显示裂缝")
        XCTAssertEqual(pause.title, "继续收录")
        XCTAssertEqual(hide.accessibilityLabel(), "显示裂缝")
        XCTAssertEqual(pause.accessibilityLabel(), "继续收录")
        XCTAssertEqual(try button("setup.done").keyEquivalent, "\r")
        hide.performClick(nil)
        XCTAssertEqual(hidden, 1)
        XCTAssertEqual(paused, 0)
        pause.performClick(nil)
        XCTAssertEqual(paused, 1)
        try button("setup.history").performClick(nil)
        XCTAssertEqual(history, 1)
        let window = try XCTUnwrap(NSApp.windows.first { $0.identifier == RiftSetupController.windowIdentifier })
        XCTAssertEqual(window.animationBehavior, .none)
        XCTAssertFalse(controller.isVisible)
        controller.update(snapshot: .init(sourceLocation: "/tmp/synthetic-source", collection: .paused,
            isHidden: true, isChecking: true))
        let recheck = try button("setup.recheck"), access = try button("setup.sourceAccess")
        XCTAssertFalse(recheck.isEnabled)
        XCTAssertFalse(pause.isEnabled)
        XCTAssertFalse(access.isEnabled)
        XCTAssertEqual(recheck.title, "正在检查…")
        XCTAssertEqual(recheck.accessibilityLabel(), "正在检查…")
        recheck.performClick(nil); pause.performClick(nil); access.performClick(nil)
        XCTAssertEqual(rechecks, 0)
        XCTAssertEqual(paused, 1)
        XCTAssertEqual(sourceGrants, 0)
        XCTAssertTrue(hide.isEnabled)
        hide.performClick(nil)
        XCTAssertEqual(hidden, 2, "Hiding remains independent of collection/recheck work")
    }
}
