import ApplicationServices
import CryptoKit
import Darwin
import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class NativeMacAXDriverTests: XCTestCase {
    @MainActor func testNativePrimitiveConfigurationAndOpaqueObjectsWithoutPermissionPrompt() throws {
        XCTAssertThrowsError(try NativeMacAXDriver(messagingTimeout: 0))
        XCTAssertThrowsError(try NativeMacAXDriver(messagingTimeout: .infinity))
        let driver = try NativeMacAXDriver()
        XCTAssertThrowsError(try driver.applicationElement(processID: 0))
        // Object creation/GetPid are local native primitives, not a client query.
        let object = try driver.applicationElement(processID: getpid())
        XCTAssertEqual(try driver.processID(of: object), getpid())
        XCTAssertEqual(object, try driver.applicationElement(processID: getpid()))
        XCTAssertThrowsError(try driver.elementsAttribute("AXChildren", of: object, maximumCount: 0))
        XCTAssertTrue(NativeMacAttachmentExecutor.supportedProfiles.isEmpty)
    }

    @MainActor func testDisabledMissingProfileAndPermissionNeverReachProviderOrInput() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let disabled = fixture.executor(mode: .disabled)
        do { _ = try await disabled.captureTarget(); XCTFail("Default disabled gate bypassed") }
        catch MacAdapterError.disabled {}
        let unsupported = NativeMacAttachmentExecutor(driver: fixture.driver, clipboardOwner: fixture.clipboard,
            coordinator: fixture.coordinator, mediaDirectory: fixture.directory, mode: .syntheticDevelopment)
        do { _ = try await unsupported.captureTarget(); XCTFail("Unobserved client selected") }
        catch NativeMacAXError.unsupportedClient {}
        XCTAssertEqual(fixture.driver.trustReads, 0)
        fixture.driver.trusted = false
        do { _ = try await fixture.executor().captureTarget(); XCTFail("Permission unavailable ignored") }
        catch NativeMacAXError.permissionUnavailable {}
        XCTAssertEqual(fixture.provider.captureCalls, 0)
        XCTAssertEqual(fixture.driver.pressCalls, 0)
    }

    @MainActor func testBindingRejectsLaunchVersionWindowComposerDraftAndUnadvertisedAction() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let executor = fixture.executor()
        let original = try await executor.captureTarget()
        XCTAssertEqual(original, fixture.session)
        let expected = fixture.driver.identity
        fixture.driver.identity = .init(processID: expected.processID, launchedAt: expected.launchedAt.addingTimeInterval(1),
            bundleID: expected.bundleID, version: expected.version, build: expected.build)
        let changedLaunch = try await executor.inspectTarget(original.target)
        XCTAssertNil(changedLaunch)
        fixture.driver.identity = .init(processID: expected.processID, launchedAt: expected.launchedAt,
            bundleID: expected.bundleID, version: "unobserved-version", build: expected.build)
        let changedVersion = try await executor.inspectTarget(original.target)
        XCTAssertNil(changedVersion)
        fixture.driver.identity = expected
        fixture.driver.focusedWindow = fixture.driver.other
        await assertTargetChanged { _ = try await executor.captureTarget() }
        fixture.driver.focusedWindow = fixture.driver.window
        fixture.driver.focusedComposer = fixture.driver.other
        await assertTargetChanged { _ = try await executor.captureTarget() }
        fixture.driver.focusedComposer = fixture.driver.composer
        fixture.provider.draftMatches = false
        let changedDraft = try await executor.inspectTarget(original.target)
        XCTAssertNil(changedDraft)
        fixture.provider.draftMatches = true
        fixture.driver.actions = []
        await assertTargetChanged { _ = try await executor.captureTarget() }
        XCTAssertEqual(fixture.driver.pressCalls, 0)
    }

    @MainActor func testOneAXActionIsUnknownAndRepeatedExecutorCannotRepeatDurableIntent() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        try fixture.reserve()
        let executor = fixture.executor()
        let result = try ObservationDecoder.decode(await executor.paste(fixture.request, owner: fixture.owner))
        XCTAssertEqual(result.observation.state, .unknown)
        XCTAssertFalse(result.observation.exactImageIdentity)
        XCTAssertEqual(result.provenance.source, .integratedDevelopment)
        XCTAssertEqual(fixture.driver.pressCalls, 1)
        do { _ = try await executor.paste(fixture.request, owner: fixture.owner); XCTFail("Repeated input") }
        catch NativeMacAXError.inputAlreadyAttempted {}
        let second = fixture.executor()
        do { _ = try await second.paste(fixture.request, owner: fixture.owner); XCTFail("New executor bypassed durable intent") }
        catch MacClipboardCoordinationError.invalidTransition {}
        XCTAssertEqual(fixture.driver.pressCalls, 1)
        _ = try await executor.observe(fixture.request)
        XCTAssertEqual(fixture.driver.pressCalls, 1)
        XCTAssertEqual(fixture.provider.observationCalls, 2)
    }

    @MainActor func testAXCannotCompleteKeepsUnknownAndNeverFallsBackOrRepeats() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        try fixture.reserve()
        fixture.driver.actionError = .accessibility(AXError.cannotComplete.rawValue)
        let executor = fixture.executor()
        let result = try ObservationDecoder.decode(await executor.paste(fixture.request, owner: fixture.owner))
        XCTAssertEqual(result.observation.state, .unknown)
        XCTAssertEqual(fixture.driver.pressCalls, 1)
        XCTAssertEqual(fixture.provider.observationCalls, 0)
        _ = try await executor.observe(fixture.request)
        XCTAssertEqual(fixture.driver.pressCalls, 1)
        let second = fixture.executor()
        do { _ = try await second.paste(fixture.request, owner: fixture.owner); XCTFail("Ambiguous action repeated") }
        catch MacClipboardCoordinationError.invalidTransition {}
        XCTAssertEqual(fixture.driver.pressCalls, 1)
    }

    @MainActor func testInputRequiresDurableReservationAndExactCurrentClipboardOwner() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let executor = fixture.executor()
        do { _ = try await executor.paste(fixture.request, owner: fixture.owner); XCTFail("Unjournaled input") }
        catch MacClipboardCoordinationError.identityMismatch {}
        try fixture.reserve()
        fixture.clipboard.value = .init(changeCount: fixture.owner.changeCount + 1, marker: "user-copy")
        do { _ = try await executor.paste(fixture.request, owner: fixture.owner); XCTFail("Later copy replaced") }
        catch NativeMacAXError.clipboardChanged {}
        XCTAssertEqual(fixture.driver.pressCalls, 0)
        fixture.clipboard.value = fixture.owner
        fixture.clipboard.reads = 0
        fixture.clipboard.copyOnRead = 2
        do { _ = try await executor.paste(fixture.request, owner: fixture.owner); XCTFail("Final boundary copy ignored") }
        catch NativeMacAXError.clipboardChanged {}
        XCTAssertEqual(fixture.driver.pressCalls, 0)
    }

    @MainActor func testFinalDraftChangeAfterFirstCheckAndIntentDoesNotPasteOrRetry() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        try fixture.reserve()
        fixture.provider.invalidateAtDraftCheck = 2
        let executor = fixture.executor()
        await assertTargetChanged { _ = try await executor.paste(fixture.request, owner: fixture.owner) }
        XCTAssertEqual(fixture.driver.pressCalls, 0)
        fixture.provider.invalidateAtDraftCheck = nil
        do { _ = try await executor.paste(fixture.request, owner: fixture.owner); XCTFail("Input intent cleared") }
        catch NativeMacAXError.inputAlreadyAttempted {}
        XCTAssertEqual(fixture.driver.pressCalls, 0)
    }

    @MainActor func testChangedBytesSymlinkAndFIFOAreRejectedWithoutAXInput() async throws {
        for kind in ["changed", "symlink", "fifo"] {
            let fixture = try await Fixture.make()
            defer { fixture.cleanUp() }
            try fixture.reserve()
            switch kind {
            case "changed": try Data([9, 8, 7, 6]).write(to: fixture.request.fileURL)
            case "symlink":
                let moved = fixture.directory.appendingPathComponent("actual.png")
                try FileManager.default.moveItem(at: fixture.request.fileURL, to: moved)
                try FileManager.default.createSymbolicLink(at: fixture.request.fileURL, withDestinationURL: moved)
            default:
                try FileManager.default.removeItem(at: fixture.request.fileURL)
                XCTAssertEqual(mkfifo(fixture.request.fileURL.path, 0o600), 0)
            }
            do { _ = try await fixture.executor().paste(fixture.request, owner: fixture.owner); XCTFail("Invalid private file: \(kind)") }
            catch NativeMacAXError.invalidPrivateFile {}
            XCTAssertEqual(fixture.driver.pressCalls, 0)
        }
        let replaced = try await Fixture.make()
        defer { replaced.cleanUp() }
        try replaced.reserve()
        let replacedFile = replaced.request.fileURL
        replaced.provider.onDraftCheck = { number in
            if number == 2 {
                // Same bytes, different inode after the original FD was hashed.
                try FileManager.default.removeItem(at: replacedFile)
                try Data([1, 2, 3, 4]).write(to: replacedFile)
            }
        }
        do { _ = try await replaced.executor().paste(replaced.request, owner: replaced.owner); XCTFail("Late private path replacement") }
        catch NativeMacAXError.invalidPrivateFile {}
        XCTAssertEqual(replaced.driver.pressCalls, 0)
    }

    @MainActor func testObserveLostBindingAndWrongIdentityCannotAttachOrPaste() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let executor = fixture.executor()
        fixture.provider.bindingAvailable = false
        let lost = try ObservationDecoder.decode(await executor.observe(fixture.request))
        XCTAssertEqual(lost.observation.state, .unknown)
        fixture.provider.bindingAvailable = true
        fixture.provider.observedIdentity = ObservationIdentity(operationID: UUID(), assetID: fixture.request.asset.id,
            attempt: fixture.request.operation.attempt, assetSHA256: fixture.request.asset.sha256, target: fixture.session.target)
        let wrong = try ObservationDecoder.decode(await executor.observe(fixture.request))
        XCTAssertEqual(wrong.observation.state, .unknown)
        fixture.provider.observedIdentity = ObservationIdentity(operationID: fixture.request.operation.id,
            assetID: fixture.request.asset.id, attempt: fixture.request.operation.attempt,
            assetSHA256: fixture.request.asset.sha256, target: fixture.session.target)
        fixture.provider.invalidateDraftAfterObservation = true
        let changedAfterRead = try ObservationDecoder.decode(await executor.observe(fixture.request))
        XCTAssertEqual(changedAfterRead.observation.state, .unknown)
        XCTAssertEqual(fixture.driver.pressCalls, 0)
        XCTAssertEqual(fixture.clipboard.reads, 0)
        XCTAssertTrue(try fixture.coordinator.canReserve())
    }

    @MainActor func testRealScreenshotOriginIsRefusedByNativeExecutor() async throws {
        let fixture = try await Fixture.make(origin: .systemScreenshot)
        defer { fixture.cleanUp() }
        let executor = fixture.executor()
        do { _ = try await executor.paste(fixture.request, owner: fixture.owner); XCTFail("Real screenshot input") }
        catch MacAdapterError.syntheticAssetsOnly {}
        do { _ = try await executor.observe(fixture.request); XCTFail("Real screenshot development observation") }
        catch MacAdapterError.syntheticAssetsOnly {}
        XCTAssertEqual(fixture.driver.pressCalls, 0)
        XCTAssertEqual(fixture.clipboard.reads, 0)
    }

    @MainActor func testCompletedAndCompensatedObserveNeverAcquireClipboardOrPermitPaste() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanUp() }
        let executor = fixture.executor()
        for phase in [OperationPhase.succeeded, .compensated] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.request.operation)) as? [String: Any])
            object["phase"] = phase.rawValue
            let operation = try JSONDecoder().decode(TransferOperation.self, from: JSONSerialization.data(withJSONObject: object))
            let request = TransferRequest(operation: operation, asset: fixture.request.asset, fileURL: fixture.request.fileURL)
            let result = try ObservationDecoder.decode(await executor.observe(request))
            XCTAssertEqual(result.observation.state, .unknown)
            do { _ = try await executor.paste(request, owner: fixture.owner); XCTFail("Completed operation replay") }
            catch MacAdapterError.invalidRequest {}
        }
        XCTAssertEqual(fixture.provider.observationCalls, 2)
        XCTAssertEqual(fixture.driver.pressCalls, 0)
        XCTAssertEqual(fixture.clipboard.reads, 0)
        XCTAssertTrue(try fixture.coordinator.canReserve())
    }

    @MainActor private func assertTargetChanged(_ body: () async throws -> Void,
                                              file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Changed target accepted", file: file, line: line) }
        catch NativeMacAXError.targetChanged {}
        catch { XCTFail("Unexpected error \(error)", file: file, line: line) }
    }
}

@MainActor private final class Fixture {
    let directory: URL
    let session: MacTargetSession
    let request: TransferRequest
    let owner: ClipboardOwnerState
    let driver: FixtureAXDriver
    let provider: FixtureBindingProvider
    let clipboard: FixtureClipboardOwner
    let coordinator: MacClipboardCoordinator
    let profile: MacAXClientProfile

    private init(directory: URL, session: MacTargetSession, request: TransferRequest, profile: MacAXClientProfile,
                 driver: FixtureAXDriver, coordinator: MacClipboardCoordinator) throws {
        self.directory = directory; self.session = session; self.request = request; self.profile = profile
        self.driver = driver; self.coordinator = coordinator
        let payload = try ClipboardAttachmentPayload(request: request)
        owner = .init(changeCount: 12, marker: payload.marker)
        clipboard = FixtureClipboardOwner(owner)
        provider = FixtureBindingProvider(binding: MacAXTargetBinding(session: session, profile: profile,
            application: driver.application, window: driver.window, composer: driver.composer, pasteMenuItem: driver.menu))
    }

    static func make(origin: AssetOrigin = .synthetic) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-native-ax-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let profile = try MacAXClientProfile(adapterID: "mac-native-test", bundleID: "fixture.native.client",
            version: "fixture-1", build: "fixture-1", surface: .macChat, evidenceID: "M1-deterministic-driver-tests")
        let driver = FixtureAXDriver()
        let target = TargetLease(adapterID: profile.adapterID, surface: profile.surface, applicationID: profile.bundleID,
            sessionID: MacTargetSession.sessionID(processID: driver.identity.processID, launchedAt: driver.identity.launchedAt),
            windowID: "fixture-window", documentID: "fixture-document", composerID: "fixture-composer", draftGeneration: "fixture-draft-1")
        let session = try MacTargetSession(processID: driver.identity.processID, launchedAt: driver.identity.launchedAt, target: target)
        let file = directory.appendingPathComponent("\(UUID()).png")
        // Transport identity fixture; ImageIO codec acceptance is tested in Capture.
        let data = Data([1, 2, 3, 4])
        try data.write(to: file)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(data.count),
            pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: origin)
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        _ = try await store.importAsset(asset)
        let operation = try await store.prepare(assetID: asset.id, target: target)
        try await store.markDispatchIntent(operation.id)
        let saved = try await store.operation(id: operation.id)
        let request = TransferRequest(operation: try XCTUnwrap(saved), asset: asset, fileURL: file)
        return try Fixture(directory: directory, session: session, request: request, profile: profile,
            driver: driver, coordinator: MacClipboardCoordinator(directoryURL: directory.appendingPathComponent("coordination")))
    }

    func reserve() throws {
        try coordinator.reserve(request)
        try coordinator.markClipboardWriteIntent(for: request)
        try coordinator.clipboardWritten(for: request, owner: owner)
    }
    func executor(mode: MacAdapterMode = .syntheticDevelopment) -> NativeMacAttachmentExecutor {
        NativeMacAttachmentExecutor(driver: driver, clipboardOwner: clipboard, coordinator: coordinator,
            mediaDirectory: directory, profile: profile, mode: mode, bindingProvider: provider)
    }
    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor private final class FixtureClipboardOwner: SynchronousClipboardOwner {
    var value: ClipboardOwnerState
    var reads = 0
    var copyOnRead: Int?
    init(_ value: ClipboardOwnerState) { self.value = value }
    func currentOwnerSynchronously() throws -> ClipboardOwnerState {
        reads += 1
        if reads == copyOnRead { value = .init(changeCount: value.changeCount + 1, marker: "new-user-copy") }
        return value
    }
}

@MainActor private final class FixtureBindingProvider: MacAXBindingProvider {
    let binding: MacAXTargetBinding
    var bindingAvailable = true
    var draftMatches = true
    var draftChecks = 0
    var invalidateAtDraftCheck: Int?
    var onDraftCheck: ((Int) throws -> Void)?
    var captureCalls = 0
    var observationCalls = 0
    var observedIdentity: ObservationIdentity?
    var invalidateDraftAfterObservation = false
    init(binding: MacAXTargetBinding) { self.binding = binding }
    func capture(using driver: any MacAXDriver) throws -> MacAXTargetBinding? { captureCalls += 1; return bindingAvailable ? binding : nil }
    func resolve(_ original: TargetLease, using driver: any MacAXDriver) throws -> MacAXTargetBinding? {
        bindingAvailable && original == binding.session.target ? binding : nil
    }
    func isOriginalDraft(_ binding: MacAXTargetBinding, using driver: any MacAXDriver) throws -> Bool {
        draftChecks += 1
        try onDraftCheck?(draftChecks)
        return draftMatches && invalidateAtDraftCheck != draftChecks
    }
    func observation(for request: TransferRequest, binding: MacAXTargetBinding,
                     using driver: any MacAXDriver) throws -> AttachmentObservation? {
        observationCalls += 1
        if invalidateDraftAfterObservation { draftMatches = false }
        return observedIdentity.map { AttachmentObservation(identity: $0, state: .attached, attachmentID: "fixture-attachment",
                                                            exactImageIdentity: true, belongsToOriginalDraft: true) }
    }
}

@MainActor private final class FixtureAXDriver: MacAXDriver {
    // AXUIElementCreateApplication constructs opaque handles without messaging
    // these fictional PIDs. All interactions below are deterministic test doubles.
    let application = MacAXElement(AXUIElementCreateApplication(900_001))
    let window = MacAXElement(AXUIElementCreateApplication(900_002))
    let composer = MacAXElement(AXUIElementCreateApplication(900_003))
    let menu = MacAXElement(AXUIElementCreateApplication(900_004))
    let other = MacAXElement(AXUIElementCreateApplication(900_005))
    var identity = MacAXApplicationIdentity(processID: 123, launchedAt: Date(timeIntervalSince1970: 5_000),
        bundleID: "fixture.native.client", version: "fixture-1", build: "fixture-1")
    var trusted = true
    var trustReads = 0
    var focusedWindow = MacAXElement(AXUIElementCreateApplication(900_002))
    var focusedComposer = MacAXElement(AXUIElementCreateApplication(900_003))
    var actions = [kAXPressAction as String]
    var actionError: NativeMacAXError?
    var pressCalls = 0
    func isTrusted() -> Bool { trustReads += 1; return trusted }
    func frontmostApplication() throws -> MacAXApplicationIdentity? { identity }
    func applicationIdentity(processID: Int32) throws -> MacAXApplicationIdentity? { identity }
    func applicationElement(processID: Int32) throws -> MacAXElement { application }
    func processID(of element: MacAXElement) throws -> Int32 { identity.processID }
    func elementAttribute(_ attribute: String, of element: MacAXElement) throws -> MacAXElement? {
        if element == application && attribute == (kAXFocusedWindowAttribute as String) { return focusedWindow }
        if element == application && attribute == (kAXFocusedUIElementAttribute as String) { return focusedComposer }
        if element == composer && attribute == (kAXWindowAttribute as String) { return window }
        return nil
    }
    func stringAttribute(_ attribute: String, of element: MacAXElement) throws -> String? {
        element == menu && attribute == (kAXRoleAttribute as String) ? (kAXMenuItemRole as String) : nil
    }
    func boolAttribute(_ attribute: String, of element: MacAXElement) throws -> Bool? {
        element == menu && attribute == (kAXEnabledAttribute as String) ? true : nil
    }
    func elementsAttribute(_ attribute: String, of element: MacAXElement, maximumCount: Int) throws -> [MacAXElement] { [] }
    func actionNames(of element: MacAXElement) throws -> [String] { actions }
    func press(_ element: MacAXElement) throws { pressCalls += 1; if let actionError { throw actionError } }
}
