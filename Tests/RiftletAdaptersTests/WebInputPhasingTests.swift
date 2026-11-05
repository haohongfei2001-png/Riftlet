import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Synthetic transport timing only; these are not platform continuation or
/// upload-completion evidence. Each operation owns separate bytes and events.
final class WebInputPhasingTests: XCTestCase {
    private var directory: URL!
    private let program = WebPageProgram(sourceID: "synthetic-input-phasing",
                                         functionSource: "function () { return null; }")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-phasing-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func target(tab: String, document: String? = nil, businessID: UUID = UUID(),
                        profile: String? = "chatgpt-composer-react-persisted-20261027-v1") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "synthetic-process-session",
            windowID: "window-\(tab)", tabID: tab, documentID: document ?? "document-\(tab)",
            composerID: "composer-\(tab)", draftGeneration: "generation-\(tab)",
            logicalDraftIdentity: profile.map { .init(profileID: $0,
                id: $0 == "chatgpt-composer-react-20261027-v1" ? "local-chatgpt:\(businessID)" : businessID.uuidString) },
            clickBindingID: UUID())
    }

    private func request(_ target: TargetLease) async throws -> TransferRequest {
        let seed = Array(UUID().uuidString.utf8)
        let bytes = Data((0..<200).map { seed[$0 % seed.count] })
        let file = directory.appendingPathComponent("\(UUID()).png")
        try bytes.write(to: file)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 4, pixelHeight: 4, mediaType: "image/png", origin: .synthetic)
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        _ = try await store.importAsset(asset)
        let operation = try await store.prepare(assetID: asset.id, target: target)
        try await store.markDispatchIntent(operation.id)
        let dispatched = try await store.operation(id: operation.id)
        return TransferRequest(operation: try XCTUnwrap(dispatched),
            asset: asset, fileURL: file, invocationID: UUID())
    }

    private func adapter(_ bridge: PhasedInputBridge, polling: WebObservationPolling = .init(timeout: 5, interval: 0.005)) -> WebAttachmentAdapter {
        WebAttachmentAdapter(mediaDirectory: directory, executor: bridge, program: program,
            mode: .syntheticDevelopment,
            profile: .init(adapterID: "chatgpt-web", surface: .webChat,
                profileID: "phasing-complete", completionSignal: .attached, uploadStartProfileID: "phasing-start"),
            polling: polling)
    }

    func testIndependentInputCanFinishBeforeOriginalStartWithoutReplacingItsObserver() async throws {
        let a = try await request(target(tab: "A")), b = try await request(target(tab: "B"))
        let bridge = PhasedInputBridge(), client = adapter(bridge), confirmations = InputConfirmationLog()
        await bridge.configure(a, initial: .input)
        await bridge.configure(b, initial: .started)
        let confirmed = expectation(description: "A original input observed")
        let first = Task { try await client.append(a, onInputConfirmed: {
            await confirmations.append($0); confirmed.fulfill()
        }) }
        await fulfillment(of: [confirmed], timeout: 2)
        let second = try await client.append(b, onInputConfirmed: { await confirmations.append($0) })
        XCTAssertEqual(second.outcome, .uploadStarted)
        let beforeStart = await bridge.events()
        XCTAssertEqual(beforeStart.filter { $0.operation == a.operation.id && $0.action == .commit }.count, 1)
        XCTAssertEqual(beforeStart.filter { $0.operation == b.operation.id && $0.action == .commit }.count, 1)
        let startedBeforeRelease = await bridge.didProduceStart(a.operation.id)
        XCTAssertFalse(startedBeforeRelease)
        await bridge.allowStart(a.operation.id)
        let firstReceipt = try await first.value
        XCTAssertEqual(firstReceipt.outcome, .uploadStarted)
        XCTAssertEqual(firstReceipt.operationID, a.operation.id)
        let receipts = await confirmations.receipts()
        XCTAssertEqual(receipts.map(\.operationID), [a.operation.id, b.operation.id])
        XCTAssertEqual(receipts.map(\.outcome), [.inputTriggered, .uploadStarted])
        let originalBytes = try Data(contentsOf: a.fileURL)
        let receivedA = await bridge.bytes(a.operation.id)
        XCTAssertEqual(receivedA, originalBytes)
        let receivedB = await bridge.bytes(b.operation.id)
        XCTAssertEqual(receivedB, try Data(contentsOf: b.fileURL))
    }

    func testHeldCommitExcludesConcurrentInputButReturnedUnknownDoesNotWaitForOriginalStart() async throws {
        let sameTarget = target(tab: "A")
        let a = try await request(sameTarget), b = try await request(sameTarget)
        let commit = expectation(description: "A entered held commit")
        let returned = expectation(description: "A input execution returned")
        let bridge = PhasedInputBridge(onCommit: { if $0 == a.operation.id { commit.fulfill() } })
        let client = adapter(bridge), confirmations = InputConfirmationLog()
        await bridge.configure(a, initial: .hashing, holdCommit: true)
        await bridge.configure(b, initial: .started)
        let first = Task { try await client.append(a, onInputExecutionReturned: {
            returned.fulfill()
        }) }
        do {
            await fulfillment(of: [commit], timeout: 2)
            do { _ = try await client.append(b, onInputConfirmed: { _ in }); XCTFail("Held commit released input") }
            catch WebAdapterError.inputInFlight {}
            let bCommandsBeforeReturn = await bridge.inputCommands(b.operation.id)
            XCTAssertEqual(bCommandsBeforeReturn, 0)

            await bridge.releaseCommit(a.operation.id)
            await fulfillment(of: [returned], timeout: 2)
            // A still returns UNKNOWN: neither its input nor START has been allowed.
            let second = try await client.append(b, onInputConfirmed: { await confirmations.append($0) })
            XCTAssertEqual(second.outcome, .uploadStarted)
            XCTAssertEqual(second.operationID, b.operation.id)
            XCTAssertEqual(second.target, a.operation.target)
            let aStartedBeforeB = await bridge.didProduceStart(a.operation.id)
            XCTAssertFalse(aStartedBeforeB)
            let receipts = await confirmations.receipts()
            XCTAssertEqual(receipts.map(\.operationID), [b.operation.id])
            XCTAssertEqual(receipts.map(\.outcome), [.uploadStarted])

            await bridge.allowInput(a.operation.id)
            await bridge.allowStart(a.operation.id)
            let firstReceipt = try await first.value
            XCTAssertEqual(firstReceipt.outcome, .uploadStarted)
            XCTAssertEqual(firstReceipt.operationID, a.operation.id)
        } catch {
            await bridge.releaseCommit(a.operation.id)
            await bridge.allowInput(a.operation.id)
            await bridge.allowStart(a.operation.id)
            _ = try? await first.value
            throw error
        }
        let aCommits = await bridge.commitCount(a.operation.id)
        XCTAssertEqual(aCommits, 1)
        let bCommits = await bridge.commitCount(b.operation.id)
        XCTAssertEqual(bCommits, 1)
    }

    func testLostCommitReceiptAndWrongIdentityNeverConfirmInputOrPermitOriginalReplay() async throws {
        for mode in [PhasedInputBridge.Initial.lostCommit, .wrongIdentity] {
            let a = try await request(target(tab: "A")), bridge = PhasedInputBridge()
            let client = adapter(bridge, polling: .disabled), confirmations = InputConfirmationLog()
            await bridge.configure(a, initial: mode)
            if mode == .lostCommit {
                let recovered = try await client.append(a, onInputConfirmed: { await confirmations.append($0) })
                XCTAssertEqual(recovered.outcome, .unknown)
            } else {
                do { _ = try await client.append(a, onInputConfirmed: { await confirmations.append($0) }); XCTFail("Wrong identity accepted") }
                catch ObservationError.identityMismatch { XCTAssertEqual(mode, .wrongIdentity) }
            }
            do { _ = try await client.append(a, onInputConfirmed: { await confirmations.append($0) }); XCTFail("Original replayed") }
            catch WebAdapterError.invalidRequest {}
            let observed = try await client.reconcile(a)
            XCTAssertEqual(observed.outcome, .unknown)
            let confirmedInvalidReply = await confirmations.receipts().isEmpty
            XCTAssertTrue(confirmedInvalidReply)
            let aCommits = await bridge.commitCount(a.operation.id)
            XCTAssertEqual(aCommits, 1)
        }
    }

    func testDelayedNoInputRetirementStaysWithOriginalLiveAppendAndNeverConfirmsInput() async throws {
        let a = try await request(target(tab: "A")), bridge = PhasedInputBridge()
        let client = adapter(bridge), confirmations = InputConfirmationLog()
        await bridge.configure(a, initial: .retiredBeforeInput)
        do {
            _ = try await client.append(a, onInputConfirmed: { await confirmations.append($0) })
            XCTFail("Original no-input retirement was lost")
        } catch let proof as PreInputRejection {
            XCTAssertEqual(proof.operationID, a.operation.id)
            XCTAssertEqual(proof.invocationID, a.invocationID)
            XCTAssertEqual(proof.stage, .pageRetiredBeforeFileInput)
        }
        let values = await confirmations.receipts(), actions = await bridge.events()
        XCTAssertTrue(values.isEmpty)
        XCTAssertEqual(actions.map(\.action), [.begin, .chunk, .commit, .observe])
        do { _ = try await client.append(a, onInputConfirmed: { _ in }); XCTFail("Retired invocation replayed") }
        catch WebAdapterError.invalidRequest {}
        let counts = await bridge.commitCount(a.operation.id)
        XCTAssertEqual(counts, 1)
    }

    func testReturnedInputDoesNotConstrainNewClicksByPriorDraftProof() async throws {
        let business = UUID(), originalTarget = target(tab: "A", businessID: business)
        let a = try await request(originalTarget), bridge = PhasedInputBridge(), client = adapter(bridge)
        await bridge.configure(a, initial: .input)
        let confirmed = expectation(description: "A input confirmed")
        let first = Task { try await client.append(a, onInputConfirmed: { _ in confirmed.fulfill() }) }
        await fulfillment(of: [confirmed], timeout: 2)
        let nextTargets = [
            target(tab: "A", businessID: business), // Same draft, new pin.
            target(tab: "B", businessID: business), // Same logical draft in another tab.
            target(tab: "A", document: "replacement-A"), // Same tab, ambiguous navigation.
            target(tab: "B", document: originalTarget.documentID),
            target(tab: "B", profile: nil),
            target(tab: "B", profile: "chatgpt-composer-react-20261027-v1")
        ]
        for candidate in nextTargets {
            let other = try await request(candidate)
            await bridge.configure(other, initial: .started)
            let receipt = try await client.append(other, onInputConfirmed: { _ in })
            XCTAssertEqual(receipt.outcome, .uploadStarted)
            let commits = await bridge.commitCount(other.operation.id)
            XCTAssertEqual(commits, 1)
        }
        await bridge.allowStart(a.operation.id)
        _ = try await first.value
        do { _ = try await client.append(a, onInputConfirmed: { _ in }); XCTFail("Original operation replayed") }
        catch WebAdapterError.invalidRequest {}
    }

    func testOriginalObserverDeferCannotReleaseLaterInputOwner() async throws {
        let a = try await request(target(tab: "A")), b = try await request(target(tab: "B"))
        let c = try await request(target(tab: "B"))
        let bCommit = expectation(description: "B entered held commit")
        let bridge = PhasedInputBridge(onCommit: { if $0 == b.operation.id { bCommit.fulfill() } })
        let client = adapter(bridge), aInput = expectation(description: "A input confirmed")
        await bridge.configure(a, initial: .input)
        await bridge.configure(b, initial: .started, holdCommit: true)
        await bridge.configure(c, initial: .started)
        let first = Task { try await client.append(a, onInputConfirmed: { _ in aInput.fulfill() }) }
        await fulfillment(of: [aInput], timeout: 2)
        let second = Task { try await client.append(b, onInputConfirmed: { _ in }) }
        await fulfillment(of: [bCommit], timeout: 2)
        await bridge.allowStart(a.operation.id)
        _ = try await first.value
        do { _ = try await client.append(c, onInputConfirmed: { _ in }); XCTFail("A observer released B transport") }
        catch WebAdapterError.inputInFlight {}
        let cCommandsBeforeRelease = await bridge.inputCommands(c.operation.id)
        XCTAssertEqual(cCommandsBeforeRelease, 0)
        await bridge.releaseCommit(b.operation.id)
        _ = try await second.value
        _ = try await client.append(c, onInputConfirmed: { _ in })
        for original in [a, b, c] {
            let count = await bridge.commitCount(original.operation.id)
            XCTAssertEqual(count, 1)
        }
    }

    func testStandaloneAppendAlsoReleasesExecutionBeforeStartObservation() async throws {
        let a = try await request(target(tab: "A")), b = try await request(target(tab: "B"))
        let commit = expectation(description: "Legacy A input entered")
        let bridge = PhasedInputBridge(onCommit: { if $0 == a.operation.id { commit.fulfill() } })
        let client = adapter(bridge)
        await bridge.configure(a, initial: .input)
        await bridge.configure(b, initial: .started)
        let first = Task { try await client.append(a) }
        await fulfillment(of: [commit], timeout: 2)
        for _ in 0..<200 {
            if await bridge.events().contains(where: { $0.action == .observe && $0.operation == a.operation.id }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let second = try await client.append(b, onInputConfirmed: { _ in })
        XCTAssertEqual(second.outcome, .uploadStarted)
        await bridge.allowStart(a.operation.id)
        _ = try await first.value
        let aCommits = await bridge.commitCount(a.operation.id)
        XCTAssertEqual(aCommits, 1)
        let bCommits = await bridge.commitCount(b.operation.id)
        XCTAssertEqual(bCommits, 1)
    }
}

private actor InputConfirmationLog {
    private var values: [TransferReceipt] = []
    func append(_ receipt: TransferReceipt) { values.append(receipt) }
    func receipts() -> [TransferReceipt] { values }
}

private actor PhasedInputBridge: WebBridgeExecutor {
    enum Initial: Sendable, Equatable { case input, hashing, started, lostCommit, wrongIdentity, retiredBeforeInput }
    struct Event: Sendable { let operation: UUID; let action: WebBridgeAction }
    private struct Entry {
        let request: TransferRequest
        let initial: Initial
        var inputAllowed: Bool
        var startAllowed: Bool
        var holdCommit: Bool
        var commitWaiter: CheckedContinuation<Void, Never>?
        var bytes = Data()
        var producedStart = false
    }
    private var entries: [UUID: Entry] = [:]
    private var recorded: [Event] = []
    private let onCommit: @Sendable (UUID) -> Void
    init(onCommit: @escaping @Sendable (UUID) -> Void = { _ in }) { self.onCommit = onCommit }
    func configure(_ request: TransferRequest, initial: Initial, holdCommit: Bool = false) {
        entries[request.operation.id] = Entry(request: request, initial: initial,
            inputAllowed: initial == .input || initial == .started,
            startAllowed: initial == .started, holdCommit: holdCommit)
    }
    func events() -> [Event] { recorded }
    func bytes(_ id: UUID) -> Data { entries[id]?.bytes ?? Data() }
    func didProduceStart(_ id: UUID) -> Bool { entries[id]?.producedStart ?? false }
    func commitCount(_ id: UUID) -> Int { recorded.filter { $0.operation == id && $0.action == .commit }.count }
    func inputCommands(_ id: UUID) -> Int { recorded.filter { $0.operation == id && [.begin, .chunk, .commit].contains($0.action) }.count }
    func allowInput(_ id: UUID) { entries[id]?.inputAllowed = true }
    func allowStart(_ id: UUID) { entries[id]?.startAllowed = true }
    func releaseCommit(_ id: UUID) {
        let waiter = entries[id]?.commitWaiter
        entries[id]?.holdCommit = false; entries[id]?.commitWaiter = nil
        waiter?.resume()
    }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        let identity = try XCTUnwrap(command.identity), id = identity.operationID
        recorded.append(.init(operation: id, action: command.action))
        let entry = try XCTUnwrap(entries[id])
        switch command.action {
        case .begin, .chunk:
            if command.action == .chunk { entries[id]?.bytes.append(try XCTUnwrap(Data(base64Encoded: command.chunkBase64 ?? ""))) }
            return try JSONSerialization.data(withJSONObject: ["operationID": id.uuidString,
                "attempt": identity.attempt, "nextChunk": command.action == .begin ? 0 : (command.chunkIndex ?? 0) + 1])
        case .commit:
            onCommit(id)
            if entry.holdCommit { await withCheckedContinuation { entries[id]?.commitWaiter = $0 } }
            if entry.initial == .lostCommit { throw WebAdapterError.nativeExecutionFailed }
            if entry.initial == .wrongIdentity {
                return try observation(.init(operationID: UUID(), assetID: identity.assetID, attempt: identity.attempt,
                    assetSHA256: identity.assetSHA256, target: identity.target), state: .inputTriggered)
            }
            return try currentObservation(identity)
        case .observe:
            if entry.initial == .retiredBeforeInput {
                return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 3,
                    provenance: .init(source: .integratedDevelopment, evidenceID: "synthetic-retirement-fixture"),
                    observation: .init(identity: identity, state: .invalidated,
                        belongsToOriginalDraft: true,
                        preInputRetirement: .init(invocationID: try XCTUnwrap(entry.request.invocationID),
                            commitInvoked: true, commitWorkSettled: true, irreversiblyRetired: true,
                            inputSideEffectEntered: false, inputCount: 0, reason: .inputHashMismatch))))
            }
            return try currentObservation(identity)
        default: throw WebAdapterError.invalidRequest
        }
    }
    private func currentObservation(_ identity: ObservationIdentity) throws -> Data {
        let entry = try XCTUnwrap(entries[identity.operationID])
        let state: AttachmentObservedState = entry.startAllowed ? .uploadStarted : entry.inputAllowed ? .inputTriggered : .unknown
        if state == .uploadStarted { entries[identity.operationID]?.producedStart = true }
        return try observation(identity, state: state)
    }
    private func observation(_ identity: ObservationIdentity, state: AttachmentObservedState) throws -> Data {
        let start: ObservedUploadStart? = state == .uploadStarted ? .init(version: 1,
            signal: .correlatedProgress, evidenceID: identity.operationID.uuidString, inputCount: 1,
            inputSequence: 1, startSequence: 4, previousProgress: 20, currentProgress: 40,
            inputObservedAtMS: 10, startObservedAtMS: 25) : nil
        return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: start == nil ? 1 : 2,
            provenance: .init(source: .syntheticFixture, evidenceID: "deterministic-input-phasing"),
            observation: .init(identity: identity, state: state,
                attachmentID: "attachment-\(identity.operationID)", exactImageIdentity: true,
                belongsToOriginalDraft: true, isUploading: start != nil, uploadStart: start)))
    }
}
