import Foundation
import XCTest
import RiftletCore
import RiftletCapture
import RiftletAdapters
@testable import RiftletApp

/// Isolated directories, suites and a never-executed Web spy. These tests never
/// inspect the real Screenshot preference domain or ordinary application data.
final class SettingsReviewEnvironmentTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("settings-review-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false)
        return value.resolvingSymlinksInPath().standardizedFileURL
    }
    private func marker(_ environment: SettingsReviewEnvironment) -> URL { environment.root.appendingPathComponent("settings-review-identity.txt") }
    private func locationFile(_ environment: SettingsReviewEnvironment) -> URL { environment.root.appendingPathComponent("fixture-location.plist") }
    private func prepare(_ environment: SettingsReviewEnvironment) throws {
        try environment.prepare()
        let ownership = try ApplicationInstanceOwnership(root: environment.root)
        defer { ownership.close() }
        try environment.prepareFixtures()
    }

    func testRequiresExactlyOneWellFormedUUIDArgument() throws {
        let id = UUID()
        XCTAssertEqual(try SettingsReviewEnvironment.identifier(in: ["Riftlet", "--settings-review", id.uuidString]), id)
        XCTAssertEqual(try SettingsReviewEnvironment.identifier(in: ["--settings-review", id.uuidString.lowercased()]), id)
        for arguments in [[], ["--settings-review"], ["--settings-review", ""], ["--settings-review", "../../Riftlet"],
                          ["--settings-review", "not-a-uuid"], ["--settings-review", id.uuidString, "--settings-review", id.uuidString]] {
            XCTAssertThrowsError(try SettingsReviewEnvironment.identifier(in: arguments))
        }
    }

    func testModeConflictsAreRejectedAndReviewCannotTurnOnWeb() throws {
        let id = UUID().uuidString
        #if RIFTLET_ORDINARY_ACCEPTANCE
        XCTAssertThrowsError(try ApplicationMode.resolve(["--settings-review", id]))
        #else
        XCTAssertEqual(try ApplicationMode.resolve(["--settings-review", id]), .settingsReview)
        #endif
        for other in ["--simulate", "--web-acceptance", "--system-screenshot-candidate"] {
            XCTAssertThrowsError(try ApplicationMode.resolve(["--settings-review", id, other]))
        }
        XCTAssertThrowsError(try ApplicationMode.resolve(["--settings-review", "invalid"]))
        let mode = ApplicationMode.settingsReview
        XCTAssertTrue(mode.collectsSystemScreenshots, "Collection is scoped to its fixture provider, not disabled wholesale")
        XCTAssertFalse(mode.usesWebAdapter(ordinary: .unifiedProduct))
        XCTAssertFalse(mode.usesWebAdapter(ordinary: .internalAcceptance()))
        XCTAssertFalse(mode.observesAttachments)
        XCTAssertFalse(mode.generatesSyntheticImages)
        XCTAssertEqual(mode.attachmentState, .productionDisabled)
    }

    func testUUIDRootsAndDefaultsSuitesAreIndependentFromOrdinaryAndEachOther() async throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let a = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        let b = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        defer {
            a.defaults.removePersistentDomain(forName: a.suiteName)
            b.defaults.removePersistentDomain(forName: b.suiteName)
        }
        XCTAssertNotEqual(a.root, b.root); XCTAssertNotEqual(a.suiteName, b.suiteName)
        XCTAssertNotEqual(a.root.lastPathComponent, OrdinaryCaptureConfiguration.dataDirectoryName)
        XCTAssertTrue(a.root.lastPathComponent.hasPrefix("Riftlet-Settings-Review-"))
        XCTAssertEqual(a.root.deletingLastPathComponent(), base)
        a.defaults.set("synthetic-value", forKey: "isolated-test-marker")
        XCTAssertNil(b.defaults.string(forKey: "isolated-test-marker"))
        try prepare(a); try prepare(b)
        XCTAssertEqual(try Data(contentsOf: marker(a)), Data((a.identifier.uuidString.lowercased() + "\n").utf8))
        let firstLocation = try await a.captureLocation.currentDirectory()
        let secondLocation = try await b.captureLocation.currentDirectory()
        XCTAssertEqual(firstLocation, a.source.standardizedFileURL)
        XCTAssertEqual(secondLocation, b.source.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent(OrdinaryCaptureConfiguration.dataDirectoryName).path))
    }

    func testIdentityPreparationDoesNotChangeFixturesBeforeWholeAppLockIsWon() throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let environment = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        try environment.prepare()
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locationFile(environment).path))
        let first = try ApplicationInstanceOwnership(root: environment.root); defer { first.close() }
        try environment.prepareFixtures()
        let location = locationFile(environment)
        let exact = try Data(contentsOf: location)
        try environment.prepare()
        XCTAssertThrowsError(try ApplicationInstanceOwnership(root: environment.root))
        XCTAssertEqual(try Data(contentsOf: location), exact, "The losing launch only validates its identity")
    }

    func testExistingUnownedOrMismatchedDirectoryIsRefusedWithoutChangingBytes() throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let environment = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        try FileManager.default.createDirectory(at: environment.root, withIntermediateDirectories: false)
        let sentinel = environment.root.appendingPathComponent("unrelated-data")
        let bytes = Data("synthetic-directory-owner".utf8); try bytes.write(to: sentinel)
        XCTAssertThrowsError(try environment.prepare())
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
        let wrong = Data((UUID().uuidString.lowercased() + "\n").utf8); try wrong.write(to: marker(environment))
        XCTAssertThrowsError(try environment.prepare())
        XCTAssertEqual(try Data(contentsOf: marker(environment)), wrong)
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.source.path))
    }

    func testExistingOwnedDirectoryPreservesSyntheticQueueMediaAndConfiguration() throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let environment = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        try prepare(environment)
        let names = ["queue-sentinel", "configuration-sentinel", "media-sentinel"]
        for name in names { try Data(("keep:" + name).utf8).write(to: environment.root.appendingPathComponent(name)) }
        let image = environment.source.appendingPathComponent("fixture-not-real-image")
        try Data([9, 8, 7]).write(to: image)
        try prepare(environment)
        for name in names { XCTAssertEqual(try Data(contentsOf: environment.root.appendingPathComponent(name)), Data(("keep:" + name).utf8)) }
        XCTAssertEqual(try Data(contentsOf: image), Data([9, 8, 7]))
        let permissions = try FileManager.default.attributesOfItem(atPath: environment.root.path)
        XCTAssertEqual((permissions[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testRootSymlinkCannotAdoptEvenAnExpectedIdentityMarker() throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let environment = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        let foreign = base.appendingPathComponent("foreign-root")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        let bytes = Data((environment.identifier.uuidString.lowercased() + "\n").utf8)
        try bytes.write(to: foreign.appendingPathComponent("settings-review-identity.txt"))
        try FileManager.default.createSymbolicLink(at: environment.root, withDestinationURL: foreign)
        XCTAssertThrowsError(try environment.prepare())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: foreign.path), ["settings-review-identity.txt"])
    }

    func testMarkerSymlinkIsNotAcceptedAndTargetIsNotRewritten() throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let environment = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        try FileManager.default.createDirectory(at: environment.root, withIntermediateDirectories: false)
        let foreign = base.appendingPathComponent("foreign-marker")
        let bytes = Data((environment.identifier.uuidString.lowercased() + "\n").utf8); try bytes.write(to: foreign)
        try FileManager.default.createSymbolicLink(at: marker(environment), withDestinationURL: foreign)
        XCTAssertThrowsError(try environment.prepare())
        XCTAssertEqual(try Data(contentsOf: foreign), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locationFile(environment).path))
    }

    func testSourceSymlinkIsRejectedAfterOwnershipWithoutTouchingDestination() throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let environment = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        try environment.prepare()
        let ownership = try ApplicationInstanceOwnership(root: environment.root); defer { ownership.close() }
        let foreign = base.appendingPathComponent("foreign-source")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        let marker = foreign.appendingPathComponent("keep"); try Data([4, 5, 6]).write(to: marker)
        try FileManager.default.createSymbolicLink(at: environment.source, withDestinationURL: foreign)
        XCTAssertThrowsError(try environment.prepareFixtures())
        XCTAssertEqual(try Data(contentsOf: marker), Data([4, 5, 6]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locationFile(environment).path))
    }

    func testFixtureProviderUsesOnlyItsExplicitLocationOrFixtureFallback() async throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let environment = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        try prepare(environment)
        let provider = environment.captureLocation
        let configured = try await provider.currentDirectory()
        XCTAssertEqual(configured, environment.source.standardizedFileURL)
        try FileManager.default.removeItem(at: locationFile(environment))
        let absent = try await provider.currentDirectory()
        XCTAssertEqual(absent, environment.source.standardizedFileURL)
        try Data("not-a-plist".utf8).write(to: locationFile(environment))
        do {
            _ = try await provider.currentDirectory()
            XCTFail("Malformed fixture preferences must not fall through to a real screenshot location")
        } catch CaptureError.invalidLocationPreference {}
        let empty = try PropertyListSerialization.data(fromPropertyList: [:], format: .binary, options: 0)
        try empty.write(to: locationFile(environment))
        let fallback = try await provider.currentDirectory()
        XCTAssertEqual(fallback, environment.source.standardizedFileURL)
    }

    @MainActor func testClosedCompositionIgnoresWebExecutorAndAllProductAdmission() async throws {
        let base = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: base) }
        let environment = SettingsReviewEnvironment(identifier: UUID(), applicationSupport: base)
        try prepare(environment)
        let store = try QueueStore(databaseURL: environment.root.appendingPathComponent("queue.sqlite"))
        let spy = SettingsReviewBridgeSpy()
        let composition = try ApplicationAttachmentComposition.make(mode: .settingsReview, root: environment.root, store: store,
            executor: spy, ordinary: .unifiedProduct)
        do { _ = try await composition.adapter.captureTarget(); XCTFail("Review mode must not create a Web target") }
        catch RiftletError.adapterUnavailable {}
        let calls = await spy.calls
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(composition.policy.admittedProfiles.isEmpty)
        XCTAssertTrue(composition.policy.uploadStartProfiles.isEmpty)
        XCTAssertTrue(composition.policy.retrySafeProfiles.isEmpty)
        XCTAssertTrue(composition.policy.continuationProfiles.isEmpty)
        let assets = try await store.assets(includeUsed: true)
        XCTAssertTrue(assets.isEmpty)
    }

    @MainActor func testReviewLoginAvailabilityNeverConstructsOrInvokesExecutableService() async {
        XCTAssertEqual(LoginItemPreferences.availability(mode: .settingsReview, isInternalAcceptance: false,
            isPackagedApplication: true, isTestProcess: false), .isolatedMode)
        let spy = ReviewLoginSpy()
        let owner = LoginItemPreferences(service: spy, availability: .isolatedMode)
        XCTAssertEqual(owner.refresh().availability, .isolatedMode)
        let on = await owner.setEnabled(true), off = await owner.setEnabled(false)
        XCTAssertEqual(on.disposition, .unavailable); XCTAssertEqual(off.disposition, .unavailable)
        XCTAssertFalse(owner.openSystemSettings())
        XCTAssertEqual(spy.calls, 0)
        XCTAssertNil(owner.snapshot.status)
    }
}

private actor SettingsReviewBridgeSpy: WebBridgeExecutor {
    private(set) var calls = 0
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        calls += 1
        throw WebAdapterError.browserNotFrontmost
    }
}

@MainActor
private final class ReviewLoginSpy: LoginItemService {
    var calls = 0
    var status: LoginItemStatus { calls += 1; return .enabled }
    func register() throws { calls += 1 }
    func unregister() async throws { calls += 1 }
    func openSystemSettings() { calls += 1 }
}
