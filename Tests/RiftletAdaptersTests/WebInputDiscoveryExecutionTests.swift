import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Exercises the production Swift lane around a lost reply while the controlled
/// page still discovers its attachment entry. Browser DOM behavior is separate.
final class WebInputDiscoveryExecutionTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("input-discovery-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func request() async throws -> TransferRequest {
        let data = Data(UUID().uuidString.utf8), file = directory.appendingPathComponent("\(UUID()).png")
        try data.write(to: file)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(data.count),
            pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        _ = try await store.importAsset(asset)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "controlled-session", windowID: "1", tabID: "2",
            documentID: "same-document", composerID: "same-composer", draftGeneration: "same-draft")
        let prepared = try await store.prepare(assetID: asset.id, target: target)
        let invocation = try await store.markDispatchIntent(prepared.id)
        let saved = try await store.operation(id: prepared.id)
        return .init(operation: try XCTUnwrap(saved), asset: asset, fileURL: file, invocationID: invocation)
    }

    private func adapter(_ bridge: DiscoveryExecutionBridge, discoveryTimeout: TimeInterval = 3) -> WebAttachmentAdapter {
        .init(mediaDirectory: directory, executor: bridge,
            program: .init(sourceID: "controlled-async-discovery", functionSource: "function(){return null}",
                           inputDiscoveryTimeout: discoveryTimeout), mode: .syntheticDevelopment,
            profile: .init(adapterID: "chatgpt-web", surface: .webChat,
                           profileID: "discovery-ready", uploadStartProfileID: "discovery-start"),
            polling: .init(timeout: 3, interval: 0.01))
    }

    func testLostCommitReplyDoesNotReleaseLaneWhileCurrentDiscoveryStillRuns() async throws {
        let a = try await request(), b = try await request()
        let pending = expectation(description: "Original discovery remains active after lost native reply")
        let returned = expectation(description: "Execution returned after discovery settled")
        let bridge = DiscoveryExecutionBridge(pending: a, onFirstObserve: { pending.fulfill() })
        let client = adapter(bridge), notifications = DiscoveryExecutionNotifications()
        let first = Task { try await client.append(a, onInputExecutionReturned: {
            await notifications.record(); returned.fulfill()
        }) }
        await fulfillment(of: [pending], timeout: 2)
        let before = await notifications.count()
        XCTAssertEqual(before, 0)
        do { _ = try await client.append(b); XCTFail("Pending entry discovery released the next input") }
        catch WebAdapterError.inputInFlight {}
        let beforeCommands = await bridge.commands()
        XCTAssertFalse(beforeCommands.contains { $0.identity?.operationID == b.operation.id })

        await bridge.finishInput()
        await fulfillment(of: [returned], timeout: 2)
        let second = try await client.append(b)
        XCTAssertEqual(second.outcome, .uploadStarted)
        let beforeStart = await bridge.inputs()
        XCTAssertEqual(beforeStart, [a.operation.id, b.operation.id], "Each controlled setter executes once")
        await bridge.finishStart()
        let original = try await first.value
        XCTAssertEqual(original.outcome, .uploadStarted)
        do { _ = try await client.append(a); XCTFail("A lost-reply commit was resent") }
        catch WebAdapterError.invalidRequest {}
        let commands = await bridge.commands(), notificationCount = await notifications.count()
        XCTAssertEqual(commands.filter { $0.action == .commit && $0.identity?.operationID == a.operation.id }.count, 1)
        XCTAssertEqual(notificationCount, 1)
    }

    func testRecoveryDeadlineCannotBeExtendedByAStalledObservation() async throws {
        let a = try await request(), b = try await request()
        let observing = expectation(description: "Recovery read is held without returning")
        let returned = expectation(description: "Execution recovery obeys its absolute budget")
        let bridge = DiscoveryExecutionBridge(pending: a, holdObservation: true,
                                             onFirstObserve: { observing.fulfill() })
        let client = adapter(bridge, discoveryTimeout: 0.05)
        let first = Task { try await client.append(a, onInputExecutionReturned: { returned.fulfill() }) }
        await fulfillment(of: [observing, returned], timeout: 2, enforceOrder: true)
        let second = try await client.append(b)
        XCTAssertEqual(second.outcome, .uploadStarted)
        await bridge.expireAndReleaseObservations()
        do { _ = try await first.value; XCTFail("Expired no-input discovery claimed success") }
        catch let rejection as PreInputRejection { XCTAssertEqual(rejection.reason, "attachmentInputNotCreated") }
        let inputs = await bridge.inputs(), commands = await bridge.commands()
        XCTAssertEqual(inputs, [b.operation.id], "The expired first input never executes later")
        XCTAssertEqual(commands.filter { $0.action == .commit && $0.identity?.operationID == a.operation.id }.count, 1)
        do { _ = try await client.append(a); XCTFail("Expired invocation was replayed") }
        catch WebAdapterError.invalidRequest {}
    }

    func testCancellationEndsOnlyCurrentRecoveryWaitWithoutRepeatingCommit() async throws {
        let a = try await request()
        let observing = expectation(description: "Recovery read has started")
        let returned = expectation(description: "Cancellation releases bounded recovery")
        let bridge = DiscoveryExecutionBridge(pending: a, holdObservation: true,
                                             onFirstObserve: { observing.fulfill() })
        let client = adapter(bridge)
        let first = Task { try await client.append(a, onInputExecutionReturned: { returned.fulfill() }) }
        await fulfillment(of: [observing], timeout: 2)
        first.cancel()
        await fulfillment(of: [returned], timeout: 1)
        await bridge.expireAndReleaseObservations()
        _ = try? await first.value
        let inputs = await bridge.inputs(), commands = await bridge.commands()
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 1)
        do { _ = try await client.append(a); XCTFail("Cancellation allowed original commit replay") }
        catch WebAdapterError.invalidRequest {}
    }
}

private actor DiscoveryExecutionNotifications {
    private var value = 0
    func record() { value += 1 }
    func count() -> Int { value }
}

private actor DiscoveryExecutionBridge: WebBridgeExecutor {
    private let pending: TransferRequest
    private var discoveryPending = true, inputFinished = false, startFinished = false, expired = false
    private var holdObservation: Bool
    private let onFirstObserve: @Sendable () -> Void
    private var observed = false, recorded: [WebBridgeCommand] = [], inputOrder: [UUID] = []
    private var observationWaiters: [CheckedContinuation<Void, Never>] = []

    init(pending: TransferRequest, holdObservation: Bool = false,
         onFirstObserve: @escaping @Sendable () -> Void) {
        self.pending = pending; self.holdObservation = holdObservation; self.onFirstObserve = onFirstObserve
    }
    func commands() -> [WebBridgeCommand] { recorded }
    func inputs() -> [UUID] { inputOrder }
    func finishInput() {
        guard discoveryPending, !expired else { return }
        discoveryPending = false; inputFinished = true; inputOrder.append(pending.operation.id)
    }
    func finishStart() { startFinished = true }
    func expireAndReleaseObservations() {
        expired = true; discoveryPending = false; holdObservation = false
        let waiters = observationWaiters; observationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        recorded.append(command)
        let identity = try XCTUnwrap(command.identity), isOriginal = identity.operationID == pending.operation.id
        switch command.action {
        case .begin, .chunk:
            return try JSONSerialization.data(withJSONObject: ["operationID": identity.operationID.uuidString,
                "attempt": identity.attempt, "nextChunk": command.action == .begin ? 0 : (command.chunkIndex ?? 0) + 1])
        case .commit:
            if isOriginal { throw WebAdapterError.nativeEventFailed(-1712) }
            inputOrder.append(identity.operationID)
            return try observation(identity, started: true)
        case .observe:
            if isOriginal {
                if !observed { observed = true; onFirstObserve() }
                if holdObservation { await withCheckedContinuation { observationWaiters.append($0) } }
                if expired {
                    return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 3,
                        provenance: .init(source: .integratedDevelopment, evidenceID: "controlled-discovery-expired"),
                        observation: .init(identity: identity, state: .invalidated, belongsToOriginalDraft: true,
                            preInputRetirement: .init(invocationID: try XCTUnwrap(pending.invocationID), commitInvoked: true,
                                commitWorkSettled: true, irreversiblyRetired: true, inputSideEffectEntered: false,
                                inputCount: 0, reason: .attachmentInputNotCreated), inputExecutionPending: false)))
                }
                return try observation(identity, started: startFinished)
            }
            return try observation(identity, started: true)
        default: throw WebAdapterError.invalidRequest
        }
    }
    private func observation(_ identity: ObservationIdentity, started: Bool) throws -> Data {
        let isOriginal = identity.operationID == pending.operation.id
        let stillDiscovering = isOriginal && discoveryPending
        let start: ObservedUploadStart? = started ? .init(version: 1, signal: .attachmentAccepted,
            evidenceID: identity.operationID.uuidString, inputCount: 1, inputSequence: 1, startSequence: 2,
            previousProgress: 0, currentProgress: 0, inputObservedAtMS: 10, startObservedAtMS: 11) : nil
        return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 2,
            provenance: .init(source: .syntheticFixture, evidenceID: "controlled-discovery-execution"),
            observation: .init(identity: identity,
                state: stillDiscovering ? .unknown : started ? .uploadStarted : .inputTriggered,
                attachmentID: started ? "attachment-\(identity.operationID)" : nil,
                exactImageIdentity: started, belongsToOriginalDraft: true, uploadStart: start,
                inputExecutionPending: stillDiscovering)))
    }
}
