import CryptoKit
import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class MacAttachmentAdapterTests: XCTestCase {
    private var directory: URL!
    private let profileID = "mac-flow-synthetic-v1"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-mac-flow-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func session(pid: Int32 = 123, launch: TimeInterval = 2_500,
                         surface: TargetSurface = .macChat, window: String = "window",
                         composer: String = "composer", generation: String = "1") throws -> MacTargetSession {
        let date = Date(timeIntervalSince1970: launch)
        let target = TargetLease(adapterID: "mac-test", surface: surface, applicationID: "fixture.mac",
            sessionID: MacTargetSession.sessionID(processID: pid, launchedAt: date),
            windowID: window, documentID: "document", composerID: composer, draftGeneration: generation)
        return try MacTargetSession(processID: pid, launchedAt: date, target: target)
    }

    private func makeRequest(_ session: MacTargetSession, origin: AssetOrigin = .synthetic) async throws -> (QueueStore, TransferRequest) {
        let file = directory.appendingPathComponent("\(UUID()).png")
        let data = Data([1, 2, 3, 4]) // Only transport/ownership identity, not image-decoder evidence.
        try data.write(to: file)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            byteCount: 4, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: origin)
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        _ = try await store.importAsset(asset)
        let op = try await store.prepare(assetID: asset.id, target: session.target)
        try await store.markDispatchIntent(op.id)
        let committed = try await store.operation(id: op.id)
        return (store, TransferRequest(operation: try XCTUnwrap(committed), asset: asset, fileURL: file))
    }

    private func adapter(_ executor: FakeMacExecutor, _ board: FakeMacPasteboard,
                         admitted: Bool = true, admitRetry: Bool = false,
                         mode: MacAdapterMode = .syntheticDevelopment) -> MacAttachmentAdapter {
        MacAttachmentAdapter(applicationID: "fixture.mac", executor: executor, clipboard: board,
            profile: .init(adapterID: "mac-test", surface: .macChat, profileID: profileID,
                           completionSignal: .attached, failureSignal: .terminalErrorAndNoResidual),
            policy: .init(admittedProfiles: admitted ? [profileID: .macChat] : [:],
                           retrySafeProfiles: admitRetry ? [profileID: .macChat] : [:]), mode: mode)
    }

    func testDisabledAdapterNeverReadsClipboardOrApplicationState() async throws {
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let executor = FakeMacExecutor(session: try session(), trace: trace, clipboard: board)
        do { _ = try await adapter(executor, board, mode: .disabled).captureTarget(); XCTFail("Enabled by default") }
        catch MacAdapterError.disabled {}
        XCTAssertTrue(trace.events().isEmpty)
    }

    func testPIDLaunchWindowComposerAndDraftAreDistinctSessionBindings() async throws {
        let initial = try session()
        XCTAssertThrowsError(try MacTargetSession(processID: 124, launchedAt: initial.launchedAt, target: initial.target))
        XCTAssertThrowsError(try MacTargetSession(processID: 123, launchedAt: Date(timeIntervalSince1970: 2_501), target: initial.target))
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let executor = FakeMacExecutor(session: initial, trace: trace, clipboard: board)
        let client = adapter(executor, board)
        let captured = try await client.captureTarget()
        XCTAssertEqual(captured, initial.target)
        for changed in [try session(pid: 124), try session(launch: 2_501), try session(window: "other"),
                        try session(composer: "other"), try session(generation: "2")] {
            await executor.setSession(changed)
            let valid = try await client.validate(initial.target)
            XCTAssertFalse(valid)
        }
        XCTAssertFalse(trace.events().contains("clipboard.write"))
    }

    func testMacSurfacesAreNotInterchangeable() async throws {
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        for surface in [TargetSurface.macWork, .macClassic] {
            let executor = FakeMacExecutor(session: try session(surface: surface), trace: trace, clipboard: board)
            do { _ = try await adapter(executor, board).captureTarget(); XCTFail("Other surface accepted") }
            catch MacAdapterError.invalidTarget {}
        }
        XCTAssertFalse(trace.events().contains("clipboard.capture"))
    }

    func testSnapshotWritePasteAndAdmittedCompletionRestoreOriginalClipboard() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let old = await board.contents()
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board, pasteState: .attached)
        let client = adapter(executor, board)
        let (store, request) = try await makeRequest(target)
        let receipt = try await client.append(request)
        let final = try await store.apply(receipt, policy: .init(admittedProfiles: [profileID: .macChat]))
        let restored = await board.contents()
        XCTAssertEqual(restored, old)
        XCTAssertEqual(final.status, .used)
        XCTAssertEqual(trace.events(), ["target.inspect", "clipboard.capture", "clipboard.write",
                                        "target.paste", "clipboard.owner", "clipboard.restore"])
        let valid = try await client.validate(target.target)
        XCTAssertTrue(valid)
    }

    func testUnknownKeepsLeaseAndReconcileOnlyObservesWithoutSecondPaste() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let old = await board.contents()
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board)
        let client = adapter(executor, board)
        let (store, request) = try await makeRequest(target)
        let unknown = try await client.append(request)
        _ = try await store.apply(unknown)
        let mayStartAnother = try await client.validate(target.target)
        XCTAssertFalse(mayStartAnother)
        XCTAssertFalse(trace.events().contains("clipboard.restore"))
        let saved = try await store.operation(id: request.operation.id)
        let recovery = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset, fileURL: request.fileURL)
        let completed = try await client.reconcile(recovery)
        XCTAssertEqual(completed.outcome, .verifiedReady)
        let restored = await board.contents()
        XCTAssertEqual(restored, old)
        XCTAssertEqual(trace.events().filter { $0 == "target.paste" }.count, 1)
        XCTAssertEqual(trace.events().filter { $0 == "target.observe" }.count, 1)
        XCTAssertEqual(trace.events().filter { $0 == "clipboard.write" }.count, 1)
    }

    func testUserCopyBeforeCompletionIsPreserved() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board)
        let client = adapter(executor, board)
        let (_, request) = try await makeRequest(target)
        _ = try await client.append(request)
        try await board.userCopy("new user copy")
        let userCopy = await board.contents()
        _ = try await client.reconcile(request)
        let preserved = await board.contents()
        XCTAssertEqual(preserved, userCopy)
        XCTAssertFalse(trace.events().contains("clipboard.restore"))
    }

    func testUserCopyBetweenOwnerReadAndGuardedRestoreIsAlsoPreserved() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace, copyBeforeRestore: true)
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board, pasteState: .attached)
        let (_, request) = try await makeRequest(target)
        let result = try await adapter(executor, board).append(request)
        let final = await board.contents()
        XCTAssertEqual(result.outcome, .verifiedReady)
        XCTAssertEqual(final.items.first?["public.utf8-plain-text"], Data("copy during restore boundary".utf8))
        let count = await board.restoreWrites()
        XCTAssertEqual(count, 0)
    }

    func testOldTargetOrWrongReceiptCannotRestoreTheClipboard() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board)
        let client = adapter(executor, board)
        let (_, request) = try await makeRequest(target)
        _ = try await client.append(request)
        await executor.setSession(try session(launch: 2_501))
        do { _ = try await client.reconcile(request); XCTFail("Restarted PID reused original target") }
        catch MacAdapterError.invalidTarget {}
        XCTAssertFalse(trace.events().contains("target.observe"))
        await executor.setSession(target)
        await executor.setWrongObservedTarget(try session(generation: "different").target)
        do { _ = try await client.reconcile(request); XCTFail("Wrong draft receipt accepted") }
        catch ObservationError.identityMismatch {}
        XCTAssertFalse(trace.events().contains("clipboard.restore"))
    }

    func testUnadmittedCompletionAndRealAssetsNeverGainClipboardAuthority() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board, pasteState: .attached)
        let client = adapter(executor, board, admitted: false)
        let (_, real) = try await makeRequest(target, origin: .systemScreenshot)
        do { _ = try await client.append(real); XCTFail("Real screenshot accepted") }
        catch MacAdapterError.syntheticAssetsOnly {}
        XCTAssertTrue(trace.events().isEmpty)
        let (_, synthetic) = try await makeRequest(target)
        _ = try await client.append(synthetic)
        XCTAssertFalse(trace.events().contains("clipboard.owner"))
        XCTAssertFalse(trace.events().contains("clipboard.restore"))
    }

    func testUserCopyBetweenSnapshotAndWritePreventsPaste() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace, copyBeforeWrite: true)
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board)
        let (_, request) = try await makeRequest(target)
        do { _ = try await adapter(executor, board).append(request); XCTFail("Concurrent copy replaced") }
        catch MacAdapterError.clipboardChanged {}
        let final = await board.contents()
        XCTAssertEqual(final.items.first?["public.utf8-plain-text"], Data("copy during write boundary".utf8))
        XCTAssertFalse(trace.events().contains("target.paste"))
    }

    func testUnadmittedFailureRetainsClipboardLeaseAndCannotRetry() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board, pasteState: .failed)
        let client = adapter(executor, board)
        let (store, request) = try await makeRequest(target)
        let receipt = try await client.append(request)
        XCTAssertEqual(receipt.outcome, .definitiveFailure)
        let result = try await store.apply(receipt, policy: .init(admittedProfiles: [profileID: .macChat]))
        XCTAssertEqual(result.status, .unknown)
        let canRetry = try await client.validate(target.target)
        XCTAssertFalse(canRetry)
        XCTAssertFalse(trace.events().contains("clipboard.restore"))
        XCTAssertEqual(trace.events().filter { $0 == "target.paste" }.count, 1)
    }

    func testAbsenceOnlyFailureCannotReleaseClipboardOrRetryEvenWithProfileAdmission() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board, pasteState: .failed)
        let client = adapter(executor, board, admitRetry: true)
        let (store, request) = try await makeRequest(target)
        let failure = try await client.append(request)
        XCTAssertNil(failure.attachmentID, "The legacy observer proves absence, not original attachment retirement")
        let unresolved = try await store.apply(failure, policy: .init(retrySafeProfiles: [profileID: .macChat]))
        XCTAssertEqual(unresolved.status, .unknown)
        let canRetry = try await client.validate(target.target)
        XCTAssertFalse(canRetry)
        XCTAssertFalse(trace.events().contains("clipboard.owner"))
        XCTAssertFalse(trace.events().contains("clipboard.restore"))
        XCTAssertEqual(trace.events().filter { $0 == "target.paste" }.count, 1)
        let retained = try await store.prepare(assetID: request.asset.id, target: target.target)
        XCTAssertEqual(retained.id, request.operation.id)
        XCTAssertEqual(retained.attempt, 1)
        _ = try await client.reconcile(request) // Observe only; never a second paste.
        XCTAssertEqual(trace.events().filter { $0 == "target.paste" }.count, 1)
        XCTAssertFalse(trace.events().contains("clipboard.restore"))
    }

    func testWrongTargetFailureObservationCannotReleasePendingClipboardLease() async throws {
        let target = try session()
        let trace = MacFlowTrace()
        let board = try FakeMacPasteboard(trace: trace)
        let executor = FakeMacExecutor(session: target, trace: trace, clipboard: board, observeState: .failed)
        let client = adapter(executor, board, admitRetry: true)
        let (_, request) = try await makeRequest(target)
        _ = try await client.append(request)
        await executor.setWrongObservedTarget(try session(generation: "another-draft").target)
        do { _ = try await client.reconcile(request); XCTFail("Wrong target failure released input") }
        catch ObservationError.identityMismatch {}
        let canRetry = try await client.validate(target.target)
        XCTAssertFalse(canRetry)
        XCTAssertEqual(trace.events().filter { $0 == "target.paste" }.count, 1)
        XCTAssertFalse(trace.events().contains("clipboard.restore"))
    }
}

private final class MacFlowTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    func events() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
}

private actor FakeMacPasteboard: ClipboardTransactionDriver {
    private let trace: MacFlowTrace
    private let copyBeforeWrite: Bool
    private let copyBeforeRestore: Bool
    private var value: ClipboardSnapshot
    private var count = 0
    private var restores = 0

    init(trace: MacFlowTrace, copyBeforeWrite: Bool = false, copyBeforeRestore: Bool = false) throws {
        self.trace = trace; self.copyBeforeWrite = copyBeforeWrite; self.copyBeforeRestore = copyBeforeRestore
        value = try ClipboardSnapshot(items: [["public.utf8-plain-text": Data("original user copy".utf8),
                                               "public.rtf": Data([7, 8, 9])]])
    }
    func contents() -> ClipboardSnapshot { value }
    func restoreWrites() -> Int { restores }
    func userCopy(_ text: String) throws {
        value = try ClipboardSnapshot(items: [["public.utf8-plain-text": Data(text.utf8)]])
        count += 1
    }
    private func state() -> ClipboardOwnerState {
        let data = value.items.first?[ClipboardAttachmentPayload.markerType]
        return ClipboardOwnerState(changeCount: count, marker: data.flatMap { String(data: $0, encoding: .utf8) })
    }
    func currentOwner() -> ClipboardOwnerState { state() }
    func capture() async throws -> ClipboardCapturedState {
        trace.append("clipboard.capture")
        return ClipboardCapturedState(changeCount: count, snapshot: value)
    }
    func writeIfUnchanged(_ payload: ClipboardAttachmentPayload, expectedChangeCount: Int) async throws -> ClipboardOwnerState? {
        trace.append("clipboard.write")
        if copyBeforeWrite { try userCopy("copy during write boundary") }
        guard count == expectedChangeCount else { return nil }
        value = try ClipboardSnapshot(items: [payload.item]); count += 1
        return state()
    }
    func owner() async throws -> ClipboardOwnerState { trace.append("clipboard.owner"); return state() }
    func restoreIfOwned(_ snapshot: ClipboardSnapshot, expectedOwner: ClipboardOwnerState) async throws -> Bool {
        trace.append("clipboard.restore")
        if copyBeforeRestore { try userCopy("copy during restore boundary") }
        guard state() == expectedOwner else { return false }
        value = snapshot; count += 1; restores += 1
        return true
    }
}

private actor FakeMacExecutor: MacAttachmentExecutor {
    private var session: MacTargetSession
    private let trace: MacFlowTrace
    private let clipboard: FakeMacPasteboard
    private let pasteState: AttachmentObservedState
    private let observeState: AttachmentObservedState
    private var wrongObservedTarget: TargetLease?
    init(session: MacTargetSession, trace: MacFlowTrace, clipboard: FakeMacPasteboard,
         pasteState: AttachmentObservedState = .unknown, observeState: AttachmentObservedState = .attached) {
        self.session = session; self.trace = trace; self.clipboard = clipboard; self.pasteState = pasteState
        self.observeState = observeState
    }
    func setSession(_ value: MacTargetSession) { session = value }
    func setWrongObservedTarget(_ value: TargetLease) { wrongObservedTarget = value }
    func captureTarget() async throws -> MacTargetSession { trace.append("target.capture"); return session }
    func inspectTarget(_ original: TargetLease) async throws -> MacTargetSession? {
        trace.append("target.inspect"); return session
    }
    func paste(_ request: TransferRequest, owner: ClipboardOwnerState) async throws -> Data {
        trace.append("target.paste")
        let currentOwner = await clipboard.currentOwner()
        guard session.target == request.operation.target, currentOwner == owner else { throw MacAdapterError.invalidTarget }
        return try observation(request, state: pasteState)
    }
    func observe(_ request: TransferRequest) async throws -> Data {
        trace.append("target.observe")
        return try observation(request, state: observeState)
    }
    private func observation(_ request: TransferRequest, state: AttachmentObservedState) throws -> Data {
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
            target: wrongObservedTarget ?? session.target)
        let failed = state == .failed
        let item = AttachmentObservation(identity: identity, state: state,
            attachmentID: failed ? nil : "synthetic-mac-attachment",
            exactImageIdentity: true, belongsToOriginalDraft: true, hasError: failed,
            attachmentAbsent: failed, automaticRetryExcluded: failed)
        return try JSONEncoder().encode(AttachmentObservationEnvelope(
            provenance: .init(source: .syntheticFixture, evidenceID: "M0-fake-pasteboard-flow"), observation: item))
    }
}
