import XCTest
import Foundation
import RiftletUI
@testable import RiftletApp

final class ArrivalMotionPreferencesTests: XCTestCase {
    private func directory() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-arrival-preferences-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }

    func testFormalChoiceSetContainsOnlyNoneAndMagnet() throws {
        XCTAssertEqual(ArrivalMotionMode.allCases.map(\.rawValue), ["none", "magnet"])
        XCTAssertEqual(ArrivalMotionMode.allCases.map(\.title), ["无", "磁力吸引"])
        XCTAssertNil(ArrivalMotionMode(rawValue: "quantum"))
        XCTAssertEqual(ArrivalMotionMode.provisionalFallback, .none)
    }

    func testMissingPreferenceUsesUnselectedFallbackWithoutWritingAProductDefault() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("arrival.json")
        let preferences = ArrivalMotionPreferences(url: file)
        XCTAssertEqual(preferences.mode, .none)
        XCTAssertNil(preferences.selectedMode)
        XCTAssertEqual(preferences.loadState, .unselected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testBothExplicitModesPersistAcrossReloadAndRemainDistinctFromUnselected() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("arrival.json")
        var preferences = ArrivalMotionPreferences(url: file)
        for mode in [ArrivalMotionMode.magnet, .none, .magnet] {
            try preferences.select(mode)
            let reloaded = ArrivalMotionPreferences(url: file)
            XCTAssertEqual(reloaded.selectedMode, mode)
            XCTAssertEqual(reloaded.mode, mode)
            XCTAssertEqual(reloaded.loadState, .selected)
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(Set(document.keys), ["version", "mode"])
            XCTAssertEqual(document["version"] as? Int, 1)
            XCTAssertEqual(document["mode"] as? String, mode.rawValue)
        }
    }

    func testCorruptFutureAndRetiredModesFallBackWithoutChangingBytes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("arrival.json")
        let fixtures = [
            Data("not-json".utf8),
            Data(#"{"version":2,"mode":"magnet"}"#.utf8),
            Data(#"{"version":1,"mode":"quantum"}"#.utf8),
            Data(#"{"version":1}"#.utf8),
            Data(repeating: 0, count: 4_097)
        ]
        for bytes in fixtures {
            try bytes.write(to: file)
            let preferences = ArrivalMotionPreferences(url: file)
            XCTAssertEqual(preferences.mode, .none)
            XCTAssertNil(preferences.selectedMode)
            XCTAssertEqual(preferences.loadState, .unreadable)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testReduceMotionIsEffectivePolicyAndDoesNotRewriteTheSelection() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("arrival.json")
        var preferences = ArrivalMotionPreferences(url: file)
        try preferences.select(.magnet)
        let bytes = try Data(contentsOf: file)
        XCTAssertEqual(preferences.mode.effective(reduceMotion: true), .none)
        XCTAssertEqual(preferences.mode.effective(reduceMotion: false), .magnet)
        XCTAssertEqual(preferences.selectedMode, .magnet)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(ArrivalMotionPreferences(url: file).selectedMode, .magnet)
    }

    func testFailedInitialSaveKeepsUnselectedStateAndCreatesNoFile() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("missing-parent/arrival.json")
        var preferences = ArrivalMotionPreferences(url: file)
        XCTAssertThrowsError(try preferences.select(.magnet))
        XCTAssertNil(preferences.selectedMode)
        XCTAssertEqual(preferences.mode, .none)
        XCTAssertEqual(preferences.loadState, .unselected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFailedReplacementDoesNotPublishAnUnsavedInMemoryChoice() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("arrival.json")
        var preferences = ArrivalMotionPreferences(url: file)
        try preferences.select(.magnet)
        // Deterministic I/O failure even for a privileged test user: an existing
        // nonempty directory cannot be replaced by Data's atomic file write.
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try Data([1]).write(to: file.appendingPathComponent("sentinel"))
        XCTAssertThrowsError(try preferences.select(.none))
        XCTAssertEqual(preferences.selectedMode, .magnet)
        XCTAssertEqual(preferences.loadState, .selected)
        XCTAssertEqual(preferences.mode, .magnet)
        XCTAssertEqual(try Data(contentsOf: file.appendingPathComponent("sentinel")), Data([1]))
    }

    func testSuccessfulExplicitChoiceCanReplacePreviouslyUnreadableSettings() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("arrival.json")
        try Data(#"{"version":99,"mode":"future-mode"}"#.utf8).write(to: file)
        var preferences = ArrivalMotionPreferences(url: file)
        XCTAssertEqual(preferences.loadState, .unreadable)
        try preferences.select(.none)
        XCTAssertEqual(preferences.selectedMode, ArrivalMotionMode.none)
        XCTAssertEqual(preferences.loadState, .selected)
        XCTAssertEqual(ArrivalMotionPreferences(url: file).selectedMode, ArrivalMotionMode.none)
    }

    func testUnverifiedOSBuildsDoNotEnableOrdinarySourceGeometry() {
        XCTAssertTrue(ArrivalSourceProfile.admittedOSBuilds.isEmpty,
                      "Real OS/source metadata acceptance must be separately evidenced before adding a build")
        XCTAssertFalse(ArrivalSourceProfile.allowsMetadata(arguments: []))
        XCTAssertFalse(ArrivalSourceProfile.allowsMetadata(arguments: ["--system-screenshot-candidate"]))
        XCTAssertFalse(ArrivalSourceProfile.allowsMetadata(arguments: ["--simulate"]))
    }

    func testMetadataCandidateFlagDoesNotChangeAnyExistingApplicationModeOrItsCapabilities() throws {
        let cases: [([String], ApplicationMode)] = [([], .capture), (["--simulate"], .simulation),
            (["--web-acceptance"], .webAcceptance), (["--system-screenshot-candidate"], .systemScreenshotCandidate)]
        for (arguments, expected) in cases {
            let unchanged = try ApplicationMode.resolve(arguments)
            let withGeometry = arguments + [ArrivalSourceProfile.candidateArgument]
            let resolved = try ApplicationMode.resolve(withGeometry)
            XCTAssertEqual(resolved, expected)
            XCTAssertEqual(resolved, unchanged)
            XCTAssertEqual(resolved.collectsSystemScreenshots, unchanged.collectsSystemScreenshots)
            XCTAssertEqual(resolved.usesWebAdapter, unchanged.usesWebAdapter)
            XCTAssertEqual(resolved.generatesSyntheticImages, unchanged.generatesSyntheticImages)
            XCTAssertEqual(resolved.storeMode, unchanged.storeMode)
            XCTAssertEqual(resolved.directoryName, unchanged.directoryName)
            XCTAssertEqual(resolved.attachmentState, unchanged.attachmentState)
            XCTAssertTrue(ArrivalSourceProfile.allowsMetadata(arguments: withGeometry))
        }
    }

    func testMetadataCandidateIsExactAndDoesNotResolveConflictingApplicationModes() {
        XCTAssertFalse(ArrivalSourceProfile.allowsMetadata(arguments: ["--arrival-metadata-candidate=true"]))
        XCTAssertFalse(ArrivalSourceProfile.allowsMetadata(arguments: ["--arrival-metadata-candidate "]))
        XCTAssertThrowsError(try ApplicationMode.resolve(["--simulate", "--system-screenshot-candidate",
                                                        ArrivalSourceProfile.candidateArgument]))
    }
}
