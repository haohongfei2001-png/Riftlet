import AppKit
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
        // Riftlet provides a native application menu as well as a status-item context menu.
        let menu = app.menuBars.menuBarItems.matching(identifier: "Riftlet").firstMatch
        let check = find(app.menuItems, "(Check for Updates.*|检查更新.*)")
        if menu.exists && menu.isHittable { menu.click() }
        let direct = app.buttons["control.update"]
        if !check.waitForExistence(timeout: 2) && !direct.exists {
            // A status-bar extra and the application menu can have the same visible title.
            let item = find(app.statusItems, ".*Riftlet.*")
            let extra = find(app.menuBars.menuBarItems, ".*Riftlet.*")
            if item.exists { item.rightClick() }
            else if extra.exists { extra.rightClick() }
        }
        if !check.waitForExistence(timeout: 3) {
            guard direct.exists && direct.isEnabled else { XCTFail(app.debugDescription); return }
            direct.click()
        } else {
            XCTAssertTrue(check.isEnabled)
            check.click()
        }
        try record("user-check")
        if qaMode == "preflight" {
            let status = find(app.descendants(matching: .any),
                              ".*(up.to.date|newest version|latest version|最新版|最新版本).*")
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
