import Foundation
import XCTest
@testable import RiftletApp

final class PreClickQAEnvironmentTests: XCTestCase {
    private func base() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return directory.resolvingSymlinksInPath().standardizedFileURL
    }

    private func environment(_ base: URL, id: UUID = UUID()) throws -> SettingsReviewEnvironment {
        try XCTUnwrap(PreClickQAEnvironment.resolve(arguments: ["Riftlet", "--preclick-qa-profile", id.uuidString, "--acceptance-trace"],
                                                    mode: .capture, applicationSupport: base))
    }

    func testOrdinaryLaunchAndConflictingArguments() throws {
        let base = try base(); defer { try? FileManager.default.removeItem(at: base) }
        let id = UUID(), flag = "--preclick-qa-profile"
        XCTAssertNil(try PreClickQAEnvironment.resolve(arguments: ["Riftlet", "--acceptance-trace"], mode: .capture, applicationSupport: base))
        for mode in ApplicationMode.allCases where mode != .capture {
            XCTAssertThrowsError(try PreClickQAEnvironment.resolve(arguments: [flag,id.uuidString],mode: mode,applicationSupport: base))
        }
        for args in [[flag], [flag,"../Riftlet"], [flag,""], [flag,id.uuidString,flag,id.uuidString],
                     [flag+"="+id.uuidString], [flag,id.uuidString,"--simulate"], [flag,id.uuidString,"--root","/tmp"],
                     ["--preclick-qa", id.uuidString], ["--preclick", id.uuidString], ["--PreClick-QA-Profile", id.uuidString], [flag,id.uuidString,"extra"], ["--settings-review",id.uuidString,flag,id.uuidString]] {
            XCTAssertThrowsError(try PreClickQAEnvironment.resolve(arguments: args, mode: .capture, applicationSupport: base), "\(args)")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    }

    #if !RIFTLET_ORDINARY_ACCEPTANCE
    func testIsolatedIdentityPreferencesAndImmutableCaptureSource() async throws {
        let base = try base(); defer { try? FileManager.default.removeItem(at: base) }
        let id = UUID(), qa = try environment(base, id: id), other = try environment(base)
        let settings = SettingsReviewEnvironment(identifier: id, applicationSupport: base)
        defer { qa.defaults.removePersistentDomain(forName: qa.suiteName) }
        XCTAssertTrue(qa.isPreClickQA); XCTAssertFalse(settings.isPreClickQA)
        XCTAssertNotEqual(qa.root, settings.root); XCTAssertNotEqual(qa.root, other.root)
        XCTAssertNotEqual(qa.root.lastPathComponent, OrdinaryCaptureConfiguration.dataDirectoryName)
        XCTAssertNotEqual(qa.suiteName, settings.suiteName); XCTAssertNotEqual(qa.suiteName, other.suiteName)
        XCTAssertTrue(ApplicationMode.capture.usesWebAdapter)
        try qa.prepare()
        let owner = try ApplicationInstanceOwnership(root: qa.root); defer { owner.close() }
        try qa.prepareFixtures()
        XCTAssertEqual(qa.source.deletingLastPathComponent().path, qa.root.path)
        // This file configures the existing settings-review environment. It must
        // never change the source of an ordinary product under QA isolation.
        let foreign = base.appendingPathComponent("unrelated")
        let config = try PropertyListSerialization.data(fromPropertyList: ["location":foreign.path], format: .xml, options: 0)
        try config.write(to: qa.root.appendingPathComponent("fixture-location.plist"))
        let source = try await qa.captureLocation.currentDirectory()
        XCTAssertEqual(source.path, qa.source.path); XCTAssertNotEqual(source.path, foreign.path)
        let key = "preclick.test." + UUID().uuidString
        qa.defaults.set(true, forKey: key); XCTAssertNil(other.defaults.object(forKey: key)); XCTAssertNil(settings.defaults.object(forKey: key))
        let restart = try environment(base,id: id); try restart.prepare()
        XCTAssertEqual(restart.defaults.bool(forKey: key), true)
        XCTAssertThrowsError(try ApplicationInstanceOwnership(root: restart.root))
    }

    func testForeignStorageAndLinkedSourceAreRefusedBeforeOpeningData() async throws {
        let base = try base(); defer { try? FileManager.default.removeItem(at: base) }
        let qa = try environment(base), manager = FileManager.default
        let foreign = base.appendingPathComponent("foreign", isDirectory: true)
        try manager.createDirectory(at: foreign, withIntermediateDirectories: false)
        let original = foreign.appendingPathComponent("sentinel"); try Data([2, 4, 6]).write(to: original)
        try manager.createSymbolicLink(at: qa.root, withDestinationURL: foreign)
        XCTAssertThrowsError(try qa.prepare()); try manager.removeItem(at: qa.root)
        try qa.prepare(); let owner = try ApplicationInstanceOwnership(root: qa.root); defer { owner.close() }
        let linkedStore = qa.root.appendingPathComponent("queue.sqlite")
        try manager.linkItem(at: original, to: linkedStore)
        XCTAssertThrowsError(try qa.prepareFixtures()); try manager.removeItem(at: linkedStore)
        try manager.createSymbolicLink(at: qa.source, withDestinationURL: foreign)
        XCTAssertThrowsError(try qa.prepareFixtures())
        do { _ = try await qa.captureLocation.currentDirectory(); XCTFail("A linked capture directory was accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: original), Data([2, 4, 6]))
    }
    #endif
}
