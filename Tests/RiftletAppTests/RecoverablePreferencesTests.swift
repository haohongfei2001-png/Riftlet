import Foundation
import XCTest
import RiftletUI
@testable import RiftletApp

final class RecoverablePreferencesTests: XCTestCase {
    private var root: URL!
    private var layout: URL { root.appendingPathComponent("rift-configuration.json") }
    private var archive: URL { root.appendingPathComponent("lifecycle-settings.json") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func load() -> RecoverablePreferences { RecoverablePreferences(root: root, defaultLayout: .init()) }

    func testDamagedLayoutLeavesArchiveAndOriginalUntouchedUntilExplicitRecovery() throws {
        let other = Data(#"{"archiveAfterSeconds":91,"next":"preserve"}"#.utf8)
        try other.write(to: archive)
        for text in ["{", #"{"fitWidth":"wide"}"#, #"{"fitWidth":0}"#] {
            let broken = Data(text.utf8)
            try broken.write(to: layout)
            let prefs = load()
            XCTAssertEqual(prefs.recoveryDomains, [.layout])
            XCTAssertEqual(prefs.layout, .init())
            XCTAssertEqual(prefs.lifecycle.archiveAfterSeconds, 91)
            XCTAssertThrowsError(try prefs.saveLayout(.init()))
            XCTAssertEqual(try Data(contentsOf: layout), broken)
            try prefs.restore(.layout)
            XCTAssertTrue(prefs.recoveryDomains.isEmpty)
            let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("rift-configuration.json.backup-") }
            XCTAssertTrue(try backups.contains { try Data(contentsOf: $0) == broken })
            XCTAssertEqual(try Data(contentsOf: archive), other)
            XCTAssertEqual(load().recoveryDomains, [])
        }
    }

    func testBadArchivePausesUntilRestoredAndUnreadableTargetCanRetry() throws {
        try Data(#"{"fitWidth":96,"future":[1,2]}"#.utf8).write(to: layout)
        try Data(#"{"archiveAfterSeconds":-1}"#.utf8).write(to: archive)
        let prefs = load()
        XCTAssertNil(prefs.lifecycle.archiveAfterSeconds)
        XCTAssertEqual(prefs.layout.fitWidth, 96)
        XCTAssertEqual(prefs.recoveryDomains, [.archive])
        XCTAssertThrowsError(try prefs.saveLifecycle(.init()))
        let preserved = root.appendingPathComponent("saved-test-original")
        try FileManager.default.moveItem(at: archive, to: preserved)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
        XCTAssertThrowsError(try prefs.restore(.archive))
        XCTAssertNil(prefs.lifecycle.archiveAfterSeconds)
        XCTAssertEqual(prefs.recoveryFailure, .archive)
        try FileManager.default.removeItem(at: archive)
        try FileManager.default.moveItem(at: preserved, to: archive)
        try prefs.restore(.archive)
        XCTAssertNil(prefs.recoveryFailure)
        XCTAssertEqual(load().lifecycle.archiveAfterSeconds, LifecycleSettings.defaultSeconds)
        XCTAssertEqual(try String(contentsOf: layout, encoding: .utf8), #"{"fitWidth":96,"future":[1,2]}"#)
    }

    func testOrdinarySavesPatchOnlyExplicitChangedKeysAndRespectExternalChanges() throws {
        try Data(#"{"desktopForm":"future","future":{"item":false},"fitWidth":89}"#.utf8).write(to: layout)
        try Data(#"{"archiveAfterSeconds":9000,"extra":"keep"}"#.utf8).write(to: archive)
        let prefs = load()
        var new = prefs.layout
        new.outerInset = 25
        try prefs.saveLayout(new)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: layout)) as? NSDictionary)
        XCTAssertEqual(saved, ["desktopForm": "future", "future": ["item": false], "fitWidth": 89, "outerInset": 25])
        // Opening a legacy out-of-range preset accepts an effective default without rewriting its raw value.
        try prefs.saveLifecycle(prefs.lifecycle)
        XCTAssertEqual(try String(contentsOf: archive, encoding: .utf8), #"{"archiveAfterSeconds":9000,"extra":"keep"}"#)
        var off = prefs.lifecycle; off.archiveAfterSeconds = nil
        try prefs.saveLifecycle(off)
        XCTAssertNil(load().lifecycle.archiveAfterSeconds)
        XCTAssertEqual(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: archive)) as? NSDictionary), ["extra":"keep"])
        let external = Data(#"{"fitWidth":93}"#.utf8)
        try external.write(to: layout)
        XCTAssertThrowsError(try prefs.saveLayout(new))
        XCTAssertEqual(try Data(contentsOf: layout), external)
        try prefs.reloadLayout()
        XCTAssertEqual(prefs.layout.fitWidth, 93)
    }

    func testOversizeLayoutIsPreservedAndNeverLoadedAsDefaultDiskState() throws {
        let bytes = Data(repeating: 65, count: 1_048_577)
        try bytes.write(to: layout)
        let prefs = load()
        XCTAssertEqual(prefs.problems[.layout], .tooLarge)
        XCTAssertEqual(try Data(contentsOf: layout), bytes)
        try prefs.restore(.layout)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let backup = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("rift-configuration.json.backup-") })
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
        XCTAssertTrue(load().recoveryDomains.isEmpty)
    }
}
