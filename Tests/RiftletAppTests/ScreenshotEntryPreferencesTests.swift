import XCTest
import RiftletCapture
@testable import RiftletApp

final class ScreenshotEntryPreferencesTests: XCTestCase {
    private func settingsURL() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent("capture-entry-settings.json"))
    }

    func testLegacyPreferencesKeepEnabledStateAndTheirChosenDefaultMode() throws {
        for mode in [ScreenshotMode.window, .region, .fullScreen] {
            let (root, url) = try settingsURL()
            defer { try? FileManager.default.removeItem(at: root) }
            let legacy: [String: Any] = ["version": 1, "defaultMode": mode.rawValue]
            try JSONSerialization.data(withJSONObject: legacy).write(to: url)
            let preferences = try ScreenshotEntryPreferences.load(from: url)
            XCTAssertTrue(preferences.builtInScreenshotEnabled)
            XCTAssertEqual(preferences.defaultMode, mode)
            try preferences.save(to: url)
            XCTAssertEqual(try ScreenshotEntryPreferences.load(from: url), preferences)
        }
    }

    func testDisableSurvivesReloadAndModeChangeWithoutOverwritingOtherSettings() throws {
        let (root, url) = try settingsURL()
        defer { try? FileManager.default.removeItem(at: root) }
        // The pause/visibility files belong to other preferences, not this switch.
        let unrelated = root.appendingPathComponent("lifecycle-settings.json")
        let original = Data(#"{"collectionPaused":true,"riftHidden":true}"#.utf8)
        try original.write(to: unrelated)
        var preferences = try ScreenshotEntryPreferences.load(from: url)
        preferences.defaultMode = .region
        preferences.builtInScreenshotEnabled = false
        try preferences.save(to: url)
        var reopened = try ScreenshotEntryPreferences.load(from: url)
        XCTAssertFalse(reopened.builtInScreenshotEnabled)
        XCTAssertEqual(reopened.defaultMode, .region)
        reopened.defaultMode = .fullScreen
        try reopened.save(to: url)
        let final = try ScreenshotEntryPreferences.load(from: url)
        XCTAssertFalse(final.builtInScreenshotEnabled)
        XCTAssertEqual(final.defaultMode, .fullScreen)
        XCTAssertEqual(try Data(contentsOf: unrelated), original)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        reopened.builtInScreenshotEnabled = true
        try reopened.save(to: url)
        XCTAssertTrue(try ScreenshotEntryPreferences.load(from: url).builtInScreenshotEnabled)
        XCTAssertEqual(try Data(contentsOf: unrelated), original)
    }

    func testLegacyIsEnabledMigratesWithoutChangingModeAndSavesOnlyCanonicalKey() throws {
        let (root, url) = try settingsURL()
        defer { try? FileManager.default.removeItem(at: root) }
        for enabled in [false, true] {
            for mode in [ScreenshotMode.window, .region, .fullScreen] {
                let legacy: [String: Any] = ["version": 1, "defaultMode": mode.rawValue, "isEnabled": enabled]
                try JSONSerialization.data(withJSONObject: legacy).write(to: url)
                let preferences = try ScreenshotEntryPreferences.load(from: url)
                XCTAssertEqual(preferences.builtInScreenshotEnabled, enabled)
                XCTAssertEqual(preferences.defaultMode, mode)
                try preferences.save(to: url)
                let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                XCTAssertEqual(Set(saved.keys), ["version", "defaultMode", "builtInScreenshotEnabled"])
                XCTAssertEqual(saved["builtInScreenshotEnabled"] as? Bool, enabled)
                XCTAssertEqual(try ScreenshotEntryPreferences.load(from: url), preferences)
            }
        }
    }

    func testCanonicalToggleWinsOverConflictingOrMalformedLegacyValues() throws {
        let (root, url) = try settingsURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyValues: [Any] = [true, false, "invalid", NSNull()]
        for canonical in [false, true] {
            for legacy in legacyValues {
                let values: [String: Any] = ["version": 1, "defaultMode": "region",
                    "builtInScreenshotEnabled": canonical, "isEnabled": legacy]
                try JSONSerialization.data(withJSONObject: values).write(to: url)
                let preferences = try ScreenshotEntryPreferences.load(from: url)
                XCTAssertEqual(preferences.builtInScreenshotEnabled, canonical)
                XCTAssertEqual(preferences.defaultMode, .region)
            }
        }
    }

    func testInvalidExplicitToggleIsRejectedInsteadOfSilentlyEnablingCapture() throws {
        let (root, url) = try settingsURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalidValues: [Any] = ["false", 1, NSNull()]
        for invalid in invalidValues {
            // A malformed canonical value cannot fall back to a valid legacy
            // value; a malformed legacy value cannot become the enabled default.
            for toggles in [["builtInScreenshotEnabled": invalid, "isEnabled": false], ["isEnabled": invalid]] {
                var values: [String: Any] = ["version": 1, "defaultMode": "window"]
                values.merge(toggles) { _, new in new }
                try JSONSerialization.data(withJSONObject: values).write(to: url)
                XCTAssertThrowsError(try ScreenshotEntryPreferences.load(from: url))
            }
        }
    }
}
