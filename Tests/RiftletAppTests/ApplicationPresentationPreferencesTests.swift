import AppKit
import Foundation
import XCTest
@testable import RiftletApp

final class ApplicationPresentationPreferencesTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftlet-appearance-preferences-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func document(_ choice: String) -> Data {
        Data("{\"version\":1,\"appearance\":\"\(choice)\"}".utf8)
    }

    @MainActor func testThreeChoicesPrepareSystemInheritanceAndCanonicalAppearances() throws {
        XCTAssertEqual(ApplicationAppearanceChoice.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertNil(ApplicationAppearanceChoice(rawValue: "automatic"))
        XCTAssertNil(try ApplicationPresentationPreferences.prepareAppearance(.system))
        XCTAssertEqual(try ApplicationPresentationPreferences.prepareAppearance(.light)?.name, .aqua)
        XCTAssertEqual(try ApplicationPresentationPreferences.prepareAppearance(.dark)?.name, .darkAqua)
    }

    @MainActor func testMissingFileUsesSystemWithoutWritingPreparingOrApplying() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        var calls: [String] = []
        let preferences = ApplicationPresentationPreferences(url: url,
            prepareAppearance: { _ in calls.append("prepare"); return nil },
            applyAppearance: { _ in calls.append("apply") },
            writeDocument: { _, _ in calls.append("write") })
        XCTAssertEqual(preferences.selection, .system)
        XCTAssertEqual(preferences.loadState, .unselected)
        XCTAssertNil(preferences.lastConfirmedSelection)
        XCTAssertNil(preferences.pendingSelection)
        XCTAssertNil(preferences.failure)
        XCTAssertNil(preferences.appliedSelection)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(try preferences.retry())
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor func testAllValidChoicesLoadWithoutRewritingOrApplyingTheirBytes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        for choice in ApplicationAppearanceChoice.allCases {
            let bytes = Data(" { \"appearance\" : \"\(choice.rawValue)\", \"version\" : 1 }\n".utf8)
            try bytes.write(to: url)
            let preferences = ApplicationPresentationPreferences(url: url,
                prepareAppearance: { _ in XCTFail("Load must not prepare an appearance"); return nil },
                applyAppearance: { _ in XCTFail("Load must not apply an appearance") },
                writeDocument: { _, _ in XCTFail("Load must not rewrite a document") })
            XCTAssertEqual(preferences.selection, choice)
            XCTAssertEqual(preferences.lastConfirmedSelection, choice)
            XCTAssertEqual(preferences.loadState, .selected)
            XCTAssertNil(preferences.appliedSelection)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    @MainActor func testInvalidFutureExtraAndOversizedDocumentsRemainUnreadableAndUnchanged() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        let invalid = [
            Data("not-json".utf8), Data("[]".utf8), Data("null".utf8),
            Data(#"{"version":2,"appearance":"dark"}"#.utf8),
            Data(#"{"version":0,"appearance":"dark"}"#.utf8),
            Data(#"{"version":"1","appearance":"dark"}"#.utf8),
            Data(#"{"version":true,"appearance":"dark"}"#.utf8),
            Data(#"{"version":1,"appearance":"future"}"#.utf8),
            Data(#"{"version":1,"appearance":null}"#.utf8),
            Data(#"{"version":1,"appearance":false}"#.utf8),
            Data(#"{"version":1}"#.utf8), Data(#"{"appearance":"system"}"#.utf8),
            Data(#"{"version":1,"appearance":"system","extra":null}"#.utf8),
            Data(#"{"version":1,"appearance":"dark","launchAtLogin":true}"#.utf8),
            Data(repeating: 32, count: 4_097)
        ]
        for bytes in invalid {
            try bytes.write(to: url)
            let preferences = ApplicationPresentationPreferences(url: url,
                prepareAppearance: { _ in XCTFail("Invalid cold load must not prepare"); return nil },
                applyAppearance: { _ in XCTFail("Invalid cold load must not apply") },
                writeDocument: { _, _ in XCTFail("Invalid cold load must not repair") })
            XCTAssertEqual(preferences.selection, .system)
            XCTAssertEqual(preferences.loadState, .unreadable)
            XCTAssertNil(preferences.lastConfirmedSelection)
            XCTAssertNil(preferences.pendingSelection)
            XCTAssertNil(preferences.appliedSelection)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    @MainActor func testExplicitSelectionPreparesThenSavesThenAppliesAndReloads() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        var events: [String] = []
        let preferences = ApplicationPresentationPreferences(url: url,
            prepareAppearance: { choice in
                events.append("prepare")
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                return try ApplicationPresentationPreferences.prepareAppearance(choice)
            },
            applyAppearance: { appearance in
                events.append("apply")
                XCTAssertEqual(appearance?.name, .darkAqua)
                let reopened = ApplicationPresentationPreferences(url: url, applyAppearance: { _ in })
                XCTAssertEqual(reopened.selection, .dark)
            },
            writeDocument: { data, destination in
                events.append("write")
                try ApplicationPresentationPreferences.writeDocument(data, to: destination)
            })
        try preferences.select(.dark)
        XCTAssertEqual(events, ["prepare", "write", "apply"])
        XCTAssertEqual(preferences.selection, .dark)
        XCTAssertEqual(preferences.lastConfirmedSelection, .dark)
        XCTAssertEqual(preferences.appliedSelection, .dark)
        XCTAssertEqual(preferences.loadState, .selected)
        XCTAssertNil(preferences.pendingSelection)
        XCTAssertNil(preferences.failure)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "appearance"])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["appearance"] as? String, "dark")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(try preferences.retry())
        XCTAssertEqual(events.count, 3)
    }

    @MainActor func testPreparationFailureNeverWritesOrAppliesAndRetainsSameRetryGoal() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        let bytes = document("light"); try bytes.write(to: url)
        var unavailable = true
        var prepared: [ApplicationAppearanceChoice] = []
        var applied: [NSAppearance.Name?] = []
        let preferences = ApplicationPresentationPreferences(url: url,
            prepareAppearance: { choice in
                prepared.append(choice)
                if unavailable { throw CocoaError(.featureUnsupported) }
                return try ApplicationPresentationPreferences.prepareAppearance(choice)
            }, applyAppearance: { applied.append($0?.name) })
        XCTAssertThrowsError(try preferences.select(.dark)) {
            XCTAssertEqual($0 as? ApplicationPresentationPreferences.Failure, .preparationFailed)
        }
        XCTAssertEqual(preferences.selection, .light)
        XCTAssertEqual(preferences.lastConfirmedSelection, .light)
        XCTAssertEqual(preferences.pendingSelection, .dark)
        XCTAssertEqual(preferences.failure, .preparationFailed)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(applied.isEmpty)
        unavailable = false
        XCTAssertTrue(try preferences.retry())
        XCTAssertEqual(prepared, [.dark, .dark])
        XCTAssertEqual(applied, [.darkAqua])
        XCTAssertEqual(preferences.selection, .dark)
        XCTAssertNil(preferences.pendingSelection)
        XCTAssertNil(preferences.failure)
    }

    @MainActor func testNilPreparedExplicitAppearanceCannotAccidentallySelectSystem() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        let preferences = ApplicationPresentationPreferences(url: url,
            prepareAppearance: { _ in nil },
            applyAppearance: { _ in XCTFail("Unavailable appearance must not be applied") })
        XCTAssertThrowsError(try preferences.select(.light))
        XCTAssertEqual(preferences.failure, .preparationFailed)
        XCTAssertEqual(preferences.pendingSelection, .light)
        XCTAssertEqual(preferences.selection, .system)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor func testRealMissingParentWriteFailureRetriesOriginalSelectionAfterRepair() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("not-created-by-preferences")
        let url = parent.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        var applied: [NSAppearance.Name?] = []
        let preferences = ApplicationPresentationPreferences(url: url, applyAppearance: { applied.append($0?.name) })
        XCTAssertThrowsError(try preferences.select(.light)) {
            XCTAssertEqual($0 as? ApplicationPresentationPreferences.Failure, .saveFailed)
        }
        XCTAssertEqual(preferences.selection, .system)
        XCTAssertEqual(preferences.loadState, .unselected)
        XCTAssertNil(preferences.lastConfirmedSelection)
        XCTAssertEqual(preferences.pendingSelection, .light)
        XCTAssertEqual(preferences.failure, .saveFailed)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        XCTAssertTrue(try preferences.retry())
        XCTAssertEqual(preferences.selection, .light)
        XCTAssertEqual(preferences.appliedSelection, .light)
        XCTAssertEqual(applied, [.aqua])
        XCTAssertNil(preferences.pendingSelection)
        XCTAssertNil(preferences.failure)
    }

    @MainActor func testRealReplacementFailurePreservesEffectiveChoiceAndDirectoryContents() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        var applied: [NSAppearance.Name?] = []
        let preferences = ApplicationPresentationPreferences(url: url, applyAppearance: { applied.append($0?.name) })
        try preferences.select(.light)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let sentinel = url.appendingPathComponent("sentinel")
        try Data([1, 2, 3]).write(to: sentinel)
        XCTAssertThrowsError(try preferences.select(.dark))
        XCTAssertEqual(preferences.selection, .light)
        XCTAssertEqual(preferences.lastConfirmedSelection, .light)
        XCTAssertEqual(preferences.appliedSelection, .light)
        XCTAssertEqual(preferences.pendingSelection, .dark)
        XCTAssertEqual(applied, [.aqua])
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([1, 2, 3]))
        // Repair only this isolated fixture; the owner never removes anything.
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(try preferences.retry())
        XCTAssertEqual(preferences.selection, .dark)
        XCTAssertEqual(applied, [.aqua, .darkAqua])
    }

    @MainActor func testLateWriteFailureDoesNotClaimDiskRollbackOrApplyUnconfirmedSelection() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        try document("light").write(to: url)
        var failAfterReplacement = true
        var applied: [NSAppearance.Name?] = []
        let preferences = ApplicationPresentationPreferences(url: url,
            applyAppearance: { applied.append($0?.name) },
            writeDocument: { data, destination in
                try ApplicationPresentationPreferences.writeDocument(data, to: destination)
                // Models a later chmod/metadata failure after successful rename.
                if failAfterReplacement { throw CocoaError(.fileWriteNoPermission) }
            })
        try preferences.applyAcceptedSelection()
        XCTAssertThrowsError(try preferences.select(.dark))
        XCTAssertEqual(preferences.selection, .light)
        XCTAssertEqual(preferences.appliedSelection, .light)
        XCTAssertEqual(preferences.lastConfirmedSelection, .light)
        XCTAssertEqual(preferences.pendingSelection, .dark)
        XCTAssertEqual(preferences.failure, .saveFailed)
        XCTAssertEqual(applied, [.aqua])
        let disk = ApplicationPresentationPreferences(url: url, applyAppearance: { _ in })
        XCTAssertEqual(disk.selection, .dark, "A thrown write is not evidence of old disk bytes")
        failAfterReplacement = false
        XCTAssertTrue(try preferences.retry())
        XCTAssertEqual(preferences.selection, .dark)
        XCTAssertEqual(preferences.lastConfirmedSelection, .dark)
        XCTAssertEqual(applied, [.aqua, .darkAqua])
        XCTAssertNil(preferences.pendingSelection)
        XCTAssertNil(preferences.failure)
    }

    @MainActor func testReturnToSystemClearsExplicitOverrideOnlyAfterSuccessfulSave() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        var fail = false
        var applied: [NSAppearance.Name?] = []
        let preferences = ApplicationPresentationPreferences(url: url,
            applyAppearance: { applied.append($0?.name) },
            writeDocument: { data, destination in
                if fail { throw CocoaError(.fileWriteNoPermission) }
                try ApplicationPresentationPreferences.writeDocument(data, to: destination)
            })
        try preferences.select(.dark)
        let before = try Data(contentsOf: url)
        fail = true
        XCTAssertThrowsError(try preferences.select(.system))
        XCTAssertEqual(preferences.selection, .dark)
        XCTAssertEqual(preferences.appliedSelection, .dark)
        XCTAssertEqual(preferences.pendingSelection, .system)
        XCTAssertEqual(applied, [.darkAqua])
        XCTAssertEqual(try Data(contentsOf: url), before)
        fail = false
        XCTAssertTrue(try preferences.retry())
        XCTAssertEqual(preferences.selection, .system)
        XCTAssertEqual(preferences.lastConfirmedSelection, .system)
        XCTAssertEqual(preferences.appliedSelection, .system)
        XCTAssertEqual(applied, [.darkAqua, nil])
        XCTAssertEqual(ApplicationPresentationPreferences(url: url, applyAppearance: { _ in }).selection, .system)
    }

    @MainActor func testExplicitChoiceReplacesUnreadableDocumentAndPreservesOtherDomains() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        let siblings = ["rift-configuration.json", "lifecycle-settings.json", "arrival-motion-settings.json",
                        "capture-entry-settings.json", "queue.sqlite", "original.png"]
        var original: [String: Data] = [:]
        for name in siblings {
            let bytes = Data(("existing personalized bytes: " + name).utf8)
            original[name] = bytes
            try bytes.write(to: root.appendingPathComponent(name))
        }
        let future = Data(#"{"version":99,"appearance":"future","extra":true}"#.utf8)
        try future.write(to: url)
        let preferences = ApplicationPresentationPreferences(url: url, applyAppearance: { _ in })
        XCTAssertEqual(preferences.loadState, .unreadable)
        XCTAssertEqual(try Data(contentsOf: url), future)
        try preferences.select(.light)
        XCTAssertEqual(preferences.loadState, .selected)
        XCTAssertEqual(preferences.selection, .light)
        for (name, bytes) in original {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), bytes)
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)),
                       Set(siblings + [ApplicationPresentationPreferences.fileName]))
    }

    @MainActor func testSymbolicLinkIsUnreadableAndExplicitChoiceDoesNotTouchItsTarget() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("other-domain.json")
        let bytes = document("dark"); try bytes.write(to: target)
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let preferences = ApplicationPresentationPreferences(url: url,
            applyAppearance: { _ in XCTFail("A symbolic-link destination must not apply") })
        XCTAssertEqual(preferences.loadState, .unreadable)
        XCTAssertEqual(preferences.selection, .system)
        XCTAssertThrowsError(try preferences.select(.light))
        XCTAssertEqual(preferences.pendingSelection, .light)
        XCTAssertEqual(preferences.failure, .saveFailed)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), target.path)
    }

    @MainActor func testExplicitStartupApplicationDoesNotWriteOrClearPendingSaveFailure() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        let bytes = document("light"); try bytes.write(to: url)
        var applied: [NSAppearance.Name?] = []
        var writes = 0
        let preferences = ApplicationPresentationPreferences(url: url,
            applyAppearance: { applied.append($0?.name) },
            writeDocument: { _, _ in writes += 1; throw CocoaError(.fileWriteNoPermission) })
        try preferences.applyAcceptedSelection()
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(applied, [.aqua])
        XCTAssertThrowsError(try preferences.select(.dark))
        try preferences.applyAcceptedSelection()
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(applied, [.aqua, .aqua])
        XCTAssertEqual(preferences.pendingSelection, .dark)
        XCTAssertEqual(preferences.failure, .saveFailed)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor func testNewExplicitSelectionReplacesFailedIntentInsteadOfReplayingIt() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(ApplicationPresentationPreferences.fileName)
        var fail = true
        var written: [String] = []
        let preferences = ApplicationPresentationPreferences(url: url, applyAppearance: { _ in },
            writeDocument: { data, destination in
                if fail { throw CocoaError(.fileWriteNoPermission) }
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                written.append(try XCTUnwrap(object["appearance"] as? String))
                try ApplicationPresentationPreferences.writeDocument(data, to: destination)
            })
        XCTAssertThrowsError(try preferences.select(.dark))
        XCTAssertEqual(preferences.pendingSelection, .dark)
        fail = false
        try preferences.select(.light)
        XCTAssertFalse(try preferences.retry())
        XCTAssertEqual(written, ["light"])
        XCTAssertEqual(preferences.selection, .light)
        XCTAssertNil(preferences.pendingSelection)
        XCTAssertNil(preferences.failure)
    }
}
