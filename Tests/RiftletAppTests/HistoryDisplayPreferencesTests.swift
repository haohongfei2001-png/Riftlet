import Foundation
import XCTest
import RiftletUI
@testable import RiftletApp

final class HistoryDisplayPreferencesTests: XCTestCase {
    @MainActor private func withDefaults(_ body: (UserDefaults, String) throws -> Void) rethrows {
        let suite = "com.riftlet.tests.history-display." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, suite)
    }

    @MainActor func testMissingAndUnknownChoicesDefaultWithoutMigratingOrWriting() {
        withDefaults { defaults, suite in
            let missing = HistoryDisplayPreferences(defaults: defaults)
            XCTAssertEqual(missing.selection, .current)
            XCTAssertNil(defaults.object(forKey: HistoryDisplayPreferences.key))
            defaults.set("futureRenderer", forKey: HistoryDisplayPreferences.key)
            defaults.set("unchanged", forKey: "unrelated")
            let before = defaults.persistentDomain(forName: suite)! as NSDictionary
            let unknown = HistoryDisplayPreferences(defaults: defaults)
            XCTAssertEqual(unknown.selection, .current)
            unknown.refresh()
            XCTAssertEqual(defaults.persistentDomain(forName: suite)! as NSDictionary, before)
        }
    }

    @MainActor func testExplicitSelectionPublishesOnceAndReopensFromSameDomain() {
        withDefaults { defaults, suite in
            let preference = HistoryDisplayPreferences(defaults: defaults)
            var published: [HistoryDisplayStyle] = []
            preference.onChange = { published.append($0) }
            preference.select(.imageGrid)
            XCTAssertEqual(preference.selection, .imageGrid)
            XCTAssertEqual(defaults.string(forKey: "historyDisplayStyle"), "imageGrid")
            preference.select(.imageGrid); preference.refresh()
            XCTAssertEqual(published, [.imageGrid])
            let reopened = HistoryDisplayPreferences(defaults: UserDefaults(suiteName: suite)!)
            XCTAssertEqual(reopened.selection, .imageGrid)
            preference.select(.current)
            XCTAssertEqual(published, [.imageGrid, .current])
            XCTAssertEqual(HistoryDisplayPreferences(defaults: UserDefaults(suiteName: suite)!).selection, .current)
        }
    }

    @MainActor func testDefaultsNotificationRefreshesOnlyOwnedDomainAndActualChange() {
        withDefaults { defaults, _ in
            let preference = HistoryDisplayPreferences(defaults: defaults)
            var published: [HistoryDisplayStyle] = []
            preference.onChange = { published.append($0) }
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
            XCTAssertTrue(published.isEmpty)
            defaults.set("imageGrid", forKey: HistoryDisplayPreferences.key)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            XCTAssertEqual(preference.selection, .imageGrid)
            XCTAssertEqual(published, [.imageGrid])
            defaults.set("kept", forKey: "other")
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            XCTAssertEqual(published, [.imageGrid])
            defaults.removeObject(forKey: HistoryDisplayPreferences.key)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            XCTAssertEqual(published, [.imageGrid, .current])
        }
    }

    @MainActor func testExplicitSelectionPreservesEveryOtherPreference() {
        withDefaults { defaults, suite in
            defaults.set(["opaque": [1, 2, 3]], forKey: "legacy")
            defaults.set("archived", forKey: "history.state")
            let original = defaults.persistentDomain(forName: suite)! as NSDictionary
            let preference = HistoryDisplayPreferences(defaults: defaults)
            preference.select(.imageGrid); preference.select(.current)
            var after = defaults.persistentDomain(forName: suite)!
            after.removeValue(forKey: HistoryDisplayPreferences.key)
            XCTAssertEqual(after as NSDictionary, original)
            XCTAssertEqual(HistoryDisplayStyle.allCases.map(\.rawValue), ["current", "imageGrid"])
        }
    }

    @MainActor func testObserverDoesNotRetainOwner() {
        withDefaults { defaults, _ in
            var preference: HistoryDisplayPreferences? = HistoryDisplayPreferences(defaults: defaults)
            weak var released = preference
            preference = nil
            XCTAssertNil(released)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        }
    }

    @MainActor func testReviewFactorySeparatesRootsAndReopensWithoutChangingStandardPreference() {
        let before = UserDefaults.standard.object(forKey: HistoryDisplayPreferences.key) as? NSObject
        let roots = (0..<2).map { _ in FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
        defer {
            for root in roots {
                let suite = HistoryDisplayPreferences.reviewSuiteName(root: root)
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
        }
        let first = HistoryDisplayPreferences.make(mode: .settingsReview, root: roots[0])
        let other = HistoryDisplayPreferences.make(mode: .settingsReview, root: roots[1])
        XCTAssertEqual(first.selection, .current); XCTAssertEqual(other.selection, .current)
        first.select(.imageGrid)
        XCTAssertEqual(HistoryDisplayPreferences.make(mode: .settingsReview, root: roots[0]).selection, .imageGrid)
        XCTAssertEqual(other.selection, .current)
        for mode: ApplicationMode in [.simulation, .webAcceptance, .systemScreenshotCandidate] {
            let preference = HistoryDisplayPreferences.make(mode: mode, root: roots[1])
            preference.select(.imageGrid); preference.select(.current)
        }
        XCTAssertEqual(UserDefaults.standard.object(forKey: HistoryDisplayPreferences.key) as? NSObject, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: roots[0].path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: roots[1].path))
    }
}
