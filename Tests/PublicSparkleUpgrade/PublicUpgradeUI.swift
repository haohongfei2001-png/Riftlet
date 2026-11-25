import AppKit
import ApplicationServices
import Darwin
import XCTest

final class PublicUpgradeUI: XCTestCase {
    private let witness = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("RiftletPublicUpgradeWitness")
    private func record(_ stage: String) throws {
        let f = witness.appendingPathComponent(stage)
        try Data(Date().ISO8601Format().utf8).write(to: f, options: .withoutOverwriting)
    }
    private func find(_ query: XCUIElementQuery, _ pattern: String) -> XCUIElement {
        query.matching(NSPredicate(format:
            "identifier MATCHES[c] %@ OR label MATCHES[c] %@ OR title MATCHES[c] %@",
            pattern, pattern, pattern)).firstMatch
    }
    private func statusButtonPoint(pid: pid_t) -> CGPoint? {
        guard AXIsProcessTrusted() else { return nil }
        func property(_ item: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(item, name as CFString, &value) == .success ? value : nil
        }
        let owner = AXUIElementCreateApplication(pid)
        guard let bar = property(owner, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID(),
              let items = property(bar as! AXUIElement, "AXChildren") as? [AXUIElement] else { return nil }
        let matches = items.filter { item in
            var owningPID: pid_t = 0
            let names = ["AXTitle", "AXDescription", "AXIdentifier"].compactMap { property(item, $0) as? String }
            return AXUIElementGetPid(item, &owningPID) == .success && owningPID == pid && names.contains("Riftlet")
        }
        guard matches.count == 1, let item = matches.first,
              let p = property(item, "AXPosition"), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = property(item, "AXSize"), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pos), AXValueGetValue(s as! AXValue, .cgSize, &size),
              size.width >= 10 && size.width < 90, size.height >= 10 && size.height < 52,
              pos.y >= 0 && pos.y < 45 else { return nil }
        return CGPoint(x:pos.x + size.width / 2, y:pos.y + size.height / 2)
    }
    @MainActor
    func testCurrentVersion() throws { try operate(mode: "preflight") }
    @MainActor
    func testPublicUpgrade() throws { try operate(mode: "upgrade") }
    @MainActor
    private func operate(mode qaMode: String) throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: witness, withIntermediateDirectories: false)
        guard let directory = getpwuid(getuid())?.pointee.pw_dir else { XCTFail("Missing login directory"); return }
        let expected = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
            .appendingPathComponent("Applications/Riftlet.app").standardizedFileURL
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.riftlet.app")
        XCTAssertEqual(running.count, 1)
        XCTAssertEqual(running[0].bundleURL?.standardizedFileURL, expected)
        let app = XCUIApplication(bundleIdentifier: "com.riftlet.app")
        app.activate()
        // Riftlet is a status-item app. The accessibility tree can list an application
        // main menu even when that menu is not on screen. Use the visible status icon
        // and its actual control-center button, never menu traversal.
        let extras = app.statusItems.matching(NSPredicate(format: "label == 'Riftlet' OR identifier == 'Riftlet'"))
        let statusPoint = statusButtonPoint(pid: running[0].processIdentifier)
        if let point = statusPoint {
            let frame = app.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - frame.minX, dy: point.y - frame.minY)).click()
        } else if extras.count == 1 && extras.element.isHittable {
            extras.element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        } else {
            XCTFail("No verified visible Riftlet status icon; tree: \(app.debugDescription)")
            return
        }
        let direct = app.buttons["control.update"]
        XCTAssertTrue(direct.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(direct.isHittable && direct.isEnabled)
        direct.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        try record("user-check")
        if qaMode == "preflight" {
            let sheet = app.dialogs.containing(.button, identifier: "action-button-1").firstMatch
            let status = sheet.staticTexts.matching(NSPredicate(format:
                "value MATCHES[c] %@", ".*(up.to.date|newest version|latest version|最新版).*")).firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 50), app.debugDescription)
            try record("up-to-date")
            return
        }
        let install = find(app.buttons, "(SUUpdateAlertInstall|Install Update|安装更新)")
        XCTAssertTrue(install.waitForExistence(timeout: 55), app.debugDescription)
        XCTAssertTrue(install.isEnabled)
        install.click()
        try record("user-install")
        let relaunch = find(app.buttons,"(SUStatusInstallAndRelaunch|Install and Relaunch|安装并重新启动|安装并重启)")
        XCTAssertTrue(relaunch.waitForExistence(timeout: 150), app.debugDescription)
        XCTAssertTrue(relaunch.isEnabled)
        relaunch.click()
        try record("user-relaunch")
    }
}
