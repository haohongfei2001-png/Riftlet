import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Full Swift transport with controlled page receipts. Native Chrome File and
/// application append behavior are tested separately by the browser fixture.
final class WebIndependentInputTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("independent-input-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func request(byteSeed: Int = 0, tab: String = "1") async throws -> TransferRequest {
        let bytes = Data((0..<200).map { UInt8(($0 + byteSeed) % 251) })
        let file = directory.appendingPathComponent("\(UUID()).png")
        try bytes.write(to: file)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 4, pixelHeight: 4, mediaType: "image/png", origin: .synthetic)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "same-session", windowID: "1", tabID: tab,
            documentID: "document-\(tab)", composerID: "same-composer", draftGeneration: "same-draft",
            clickBindingID: UUID())
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        _ = try await store.importAsset(asset)
        let prepared = try await store.prepare(assetID: asset.id, target: target)
        try await store.markDispatchIntent(prepared.id)
        let operation = try await store.operation(id: prepared.id)
        return .init(operation: try XCTUnwrap(operation), asset: asset, fileURL: file, invocationID: UUID())
    }

    private func adapter(_ bridge: IndependentInputBridge, timeout: TimeInterval = 1) -> WebAttachmentAdapter {
        .init(mediaDirectory: directory, executor: bridge,
            program: .init(sourceID: "controlled-independent-input", functionSource: "function(){return null}"),
            mode: .syntheticDevelopment,
            profile: .init(adapterID: "chatgpt-web", surface: .webChat,
                profileID: "controlled-ready", completionSignal: .attached, uploadStartProfileID: "controlled-start"),
            polling: .init(timeout: timeout, interval: 0.01))
    }

    func testTwoThreeAndFiveScreenshotsEachSendOneCurrentFileAndStartWithoutPreparation() async throws {
        for count in [2, 3, 5] {
            let bridge = IndependentInputBridge(), client = adapter(bridge)
            for _ in 0..<count {
                let current = try await request(), receipt = try await client.append(current)
                XCTAssertEqual(receipt.outcome, .uploadStarted)
                let bytes = await bridge.bytes(current.operation.id)
                XCTAssertEqual(bytes, try Data(contentsOf: current.fileURL))
                do { _ = try await client.append(current); XCTFail("One click replayed") }
                catch WebAdapterError.invalidRequest {}
            }
            let commands = await bridge.commands()
            XCTAssertEqual(commands.filter { $0.action == .commit }.count, count)
            XCTAssertEqual(commands.filter { $0.action == .begin }.count, count)
            XCTAssertTrue(commands.allSatisfy { [.begin, .chunk, .commit].contains($0.action) })
        }
    }

    func testSecondInputWhileFirstStillObservesStartDoesNotWaitForUpload() async throws {
        let a = try await request(), b = try await request(), bridge = IndependentInputBridge()
        let client = adapter(bridge), confirmed = expectation(description: "A setter/change returned")
        await bridge.holdStart(a.operation.id)
        let first = Task { try await client.append(a) { _ in confirmed.fulfill() } }
        await fulfillment(of: [confirmed], timeout: 2)
        let second = try await client.append(b)
        XCTAssertEqual(second.outcome, .uploadStarted)
        let commands = await bridge.commands()
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 2)
        await bridge.releaseStart(a.operation.id)
        let firstReceipt = try await first.value
        XCTAssertEqual(firstReceipt.outcome, .uploadStarted)
    }

    func testUnknownFirstResultCannotBlockNewScreenshotOrReplayTheOldOne() async throws {
        let a = try await request(), b = try await request(), bridge = IndependentInputBridge()
        let client = adapter(bridge, timeout: 0)
        await bridge.makeUnknown(a.operation.id)
        let first = try await client.append(a)
        XCTAssertEqual(first.outcome, .unknown)
        let second = try await client.append(b)
        XCTAssertEqual(second.outcome, .uploadStarted)
        do { _ = try await client.append(a); XCTFail("UNKNOWN replayed") }
        catch WebAdapterError.invalidRequest {}
        let commands = await bridge.commands()
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 2)
    }

    func testSettledUnknownInputReleasesExecutionBeforeItsStartObservationFinishes() async throws {
        let a = try await request(), b = try await request(), bridge = IndependentInputBridge()
        let client = adapter(bridge, timeout: 10)
        await bridge.makeUnknown(a.operation.id)
        let returned = expectation(description: "A synchronous input returned without START")
        let first = Task { try await client.append(a, onInputExecutionReturned: { returned.fulfill() }) }
        await fulfillment(of: [returned], timeout: 2)
        let second = try await client.append(b)
        XCTAssertEqual(second.outcome, .uploadStarted)
        let commands = await bridge.commands()
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 2)
        await bridge.releaseUnknown(a.operation.id)
        let recovered = try await first.value
        XCTAssertEqual(recovered.outcome, .uploadStarted)
    }

    func testLostOrMalformedCommitReceiptRecoversByObservationWithNoSecondInput() async throws {
        for malformed in [false, true] {
            let a = try await request(), b = try await request(), bridge = IndependentInputBridge()
            let client = adapter(bridge)
            await bridge.loseCommitReply(a.operation.id, malformed: malformed)
            let first = try await client.append(a)
            XCTAssertEqual(first.outcome, .uploadStarted)
            let second = try await client.append(b)
            XCTAssertEqual(second.outcome, .uploadStarted)
            let commands = await bridge.commands()
            XCTAssertEqual(commands.filter { $0.action == .commit && $0.identity?.operationID == a.operation.id }.count, 1)
            XCTAssertEqual(commands.filter { $0.action == .observe && $0.identity?.operationID == a.operation.id }.count, 1)
            XCTAssertEqual(commands.filter { $0.action == .commit }.count, 2)
        }
    }

    func testLostCommitReplyReleasesInputBeforeTheFirstRecoveryObservationReturns() async throws {
        let a = try await request(), b = try await request(byteSeed: 1)
        let returned = expectation(description: "A commit execution returned despite its lost reply")
        let observing = expectation(description: "A first recovery observation is suspended")
        let bridge = IndependentInputBridge(onObserve: { if $0 == a.operation.id { observing.fulfill() } })
        let client = adapter(bridge)
        await bridge.loseCommitReply(a.operation.id, malformed: false)
        await bridge.holdObservation(a.operation.id)
        let first = Task { try await client.append(a, onInputExecutionReturned: { returned.fulfill() }) }
        do {
            await fulfillment(of: [returned, observing], timeout: 2, enforceOrder: true)
            // The first recovery observe has not returned. B must still perform
            // its own file handoff and START through the same adapter instance.
            let second = try await client.append(b)
            XCTAssertEqual(second.outcome, .uploadStarted)
            XCTAssertEqual(second.assetID, b.asset.id)
            let commands = await bridge.commands(), inputs = await bridge.inputOperations()
            XCTAssertEqual(commands.filter { $0.identity?.operationID == a.operation.id }.map(\.action),
                           [.begin, .chunk, .commit, .observe])
            XCTAssertEqual(commands.filter { $0.identity?.operationID == b.operation.id }.map(\.action),
                           [.begin, .chunk, .commit])
            XCTAssertEqual(inputs, [a.operation.id, b.operation.id], "Each controlled setter runs once")
            let aBytes = await bridge.bytes(a.operation.id), bBytes = await bridge.bytes(b.operation.id)
            XCTAssertNotEqual(aBytes, bBytes)
            XCTAssertEqual(aBytes, try Data(contentsOf: a.fileURL))
            XCTAssertEqual(bBytes, try Data(contentsOf: b.fileURL))

            await bridge.releaseObservation(a.operation.id)
            let recovered = try await first.value
            XCTAssertEqual(recovered.outcome, .uploadStarted)
            do { _ = try await client.append(a); XCTFail("Lost-reply invocation was submitted again") }
            catch WebAdapterError.invalidRequest {}
            let finalCommands = await bridge.commands(), finalInputs = await bridge.inputOperations()
            XCTAssertEqual(finalCommands.map(\.action), commands.map(\.action))
            XCTAssertEqual(finalInputs, inputs)
        } catch {
            // A regressed inputInFlight result must fail cleanly, without
            // leaving the held fixture or its append task behind.
            await bridge.releaseObservation(a.operation.id)
            _ = try? await first.value
            throw error
        }
    }

    func testLostReplyAndUnavailableObservationDoNotLockFutureInput() async throws {
        let a = try await request(), b = try await request(), bridge = IndependentInputBridge()
        let client = adapter(bridge)
        await bridge.loseCommitReply(a.operation.id, malformed: false, loseObservation: true)
        do { _ = try await client.append(a); XCTFail("Missing observation fabricated START") }
        catch WebAdapterError.invalidReply {}
        let second = try await client.append(b)
        XCTAssertEqual(second.outcome, .uploadStarted)
        do { _ = try await client.append(a); XCTFail("Uncertain commit replayed") }
        catch WebAdapterError.invalidRequest {}
        let commands = await bridge.commands()
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 2)
    }

    func testAnotherTabCanExecuteWhileOriginalTabCommitIsPending() async throws {
        let a = try await request(), b = try await request(tab: "2")
        let entered = expectation(description: "A commit held")
        let bridge = IndependentInputBridge(onCommit: { if $0 == a.operation.id { entered.fulfill() } })
        let client = adapter(bridge)
        await bridge.holdCommit(a.operation.id)
        let first = Task { try await client.append(a) }
        await fulfillment(of: [entered], timeout: 2)
        do {
            let second = try await client.append(b)
            XCTAssertEqual(second.outcome, .uploadStarted)
        } catch {
            await bridge.releaseCommit(a.operation.id)
            _ = try? await first.value
            throw error
        }
        await bridge.releaseCommit(a.operation.id)
        _ = try await first.value
        let commands = await bridge.commands()
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 2)
    }

    func testActuallyExecutingInputExcludesSecondSetterOnlyUntilItReturns() async throws {
        let a = try await request(), b = try await request()
        let entered = expectation(description: "A executing commit")
        let bridge = IndependentInputBridge(onCommit: { if $0 == a.operation.id { entered.fulfill() } })
        let client = adapter(bridge)
        await bridge.holdCommit(a.operation.id)
        let first = Task { try await client.append(a) }
        await fulfillment(of: [entered], timeout: 2)
        do { _ = try await client.append(b); XCTFail("Concurrent setter allowed") }
        catch WebAdapterError.inputInFlight {}
        let whileExecuting = await bridge.commands()
        XCTAssertFalse(whileExecuting.contains { $0.action == .begin && $0.identity?.operationID == b.operation.id })
        await bridge.releaseCommit(a.operation.id)
        _ = try await first.value
        let second = try await client.append(b)
        XCTAssertEqual(second.outcome, .uploadStarted)
        let commands = await bridge.commands()
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 2)
    }
}

private actor IndependentInputBridge: WebBridgeExecutor {
    private var recorded: [WebBridgeCommand] = []
    private var received: [UUID: Data] = [:]
    private var held = Set<UUID>(), heldStarts = Set<UUID>(), unknown = Set<UUID>()
    private var lostReplies: [UUID: Bool] = [:]
    private var lostObservations = Set<UUID>()
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var heldObservations = Set<UUID>()
    private var observationWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var inputOrder: [UUID] = []
    private let onCommit: @Sendable (UUID) -> Void
    private let onObserve: @Sendable (UUID) -> Void
    init(onCommit: @escaping @Sendable (UUID) -> Void = { _ in },
         onObserve: @escaping @Sendable (UUID) -> Void = { _ in }) {
        self.onCommit = onCommit; self.onObserve = onObserve
    }
    func commands() -> [WebBridgeCommand] { recorded }
    func bytes(_ id: UUID) -> Data { received[id] ?? Data() }
    func inputOperations() -> [UUID] { inputOrder }
    func holdCommit(_ id: UUID) { held.insert(id) }
    func releaseCommit(_ id: UUID) { held.remove(id); waiters.removeValue(forKey: id)?.resume() }
    func holdStart(_ id: UUID) { heldStarts.insert(id) }
    func releaseStart(_ id: UUID) { heldStarts.remove(id) }
    func makeUnknown(_ id: UUID) { unknown.insert(id) }
    func releaseUnknown(_ id: UUID) { unknown.remove(id) }
    func holdObservation(_ id: UUID) { heldObservations.insert(id) }
    func releaseObservation(_ id: UUID) { heldObservations.remove(id); observationWaiters.removeValue(forKey: id)?.resume() }
    func loseCommitReply(_ id: UUID, malformed: Bool, loseObservation: Bool = false) {
        lostReplies[id] = malformed
        if loseObservation { lostObservations.insert(id) }
    }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        recorded.append(command)
        let identity = try XCTUnwrap(command.identity)
        switch command.action {
        case .begin, .chunk:
            if command.action == .chunk {
                received[identity.operationID, default: Data()].append(try XCTUnwrap(Data(base64Encoded: command.chunkBase64 ?? "")))
            }
            return try JSONSerialization.data(withJSONObject: ["operationID": identity.operationID.uuidString,
                "attempt": identity.attempt, "nextChunk": command.action == .begin ? 0 : (command.chunkIndex ?? 0) + 1])
        case .commit:
            onCommit(identity.operationID)
            if held.contains(identity.operationID) { await withCheckedContinuation { waiters[identity.operationID] = $0 } }
            // Controlled fixture side effect, independent of reply delivery.
            inputOrder.append(identity.operationID)
            if let malformed = lostReplies[identity.operationID] {
                if malformed { return Data("{}".utf8) }
                throw WebAdapterError.invalidReply
            }
            return try observation(identity)
        case .observe:
            onObserve(identity.operationID)
            if heldObservations.contains(identity.operationID) {
                await withCheckedContinuation { observationWaiters[identity.operationID] = $0 }
            }
            if lostObservations.contains(identity.operationID) { throw WebAdapterError.invalidReply }
            return try observation(identity)
        default: throw WebAdapterError.invalidRequest
        }
    }
    private func observation(_ identity: ObservationIdentity) throws -> Data {
        let started = !heldStarts.contains(identity.operationID) && !unknown.contains(identity.operationID)
        let start: ObservedUploadStart? = started ? .init(version: 1, signal: .correlatedProgress,
            evidenceID: identity.operationID.uuidString, inputCount: 1, inputSequence: 1, startSequence: 4,
            previousProgress: 20, currentProgress: 40, inputObservedAtMS: 10, startObservedAtMS: 25) : nil
        return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: started ? 2 : 1,
            provenance: .init(source: .syntheticFixture, evidenceID: "controlled-independent-input"),
            observation: .init(identity: identity,
                state: unknown.contains(identity.operationID) ? .unknown : started ? .uploadStarted : .inputTriggered,
                attachmentID: "attachment-\(identity.operationID)", exactImageIdentity: true,
                belongsToOriginalDraft: true, isUploading: started, uploadStart: start)))
    }
}
