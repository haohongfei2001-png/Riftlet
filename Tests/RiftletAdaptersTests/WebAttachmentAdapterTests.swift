import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class WebAttachmentAdapterTests: XCTestCase {
    private var directory: URL!
    private let program = WebPageProgram(sourceID: "synthetic-fake-executor-only",
                                        functionSource: "function () { return null; }")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-web-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func fixture(origin: AssetOrigin = .synthetic, dispatch: Bool = true, byteCount: Int = 70_000) async throws -> (QueueStore, TransferRequest, Data) {
        let bytes = Data((0..<byteCount).map { UInt8($0 % 251) })
        let file = directory.appendingPathComponent("\(UUID()).png")
        try bytes.write(to: file)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
                                  sha256: hash, byteCount: Int64(bytes.count), pixelWidth: 4,
                                  pixelHeight: 4, mediaType: "image/png", origin: origin)
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        _ = try await store.importAsset(asset)
        let operation = try await store.prepare(assetID: asset.id, target: FakeWebBridge.target)
        if dispatch { try await store.markDispatchIntent(operation.id) }
        let persisted = try await store.operation(id: operation.id)
        return (store, TransferRequest(operation: try XCTUnwrap(persisted), asset: asset, fileURL: file), bytes)
    }

    private func adapter(_ executor: FakeWebBridge, mode: WebAdapterMode = .syntheticDevelopment,
                         withProgram: Bool = true) -> WebAttachmentAdapter {
        WebAttachmentAdapter(mediaDirectory: directory, executor: executor,
            program: withProgram ? program : nil, mode: mode, polling: .disabled)
    }

    func testRepeatedOriginalRequestCannotProduceLocalRejectionAfterInput() async throws {
        let (_, original, bytes) = try await fixture()
        let request = TransferRequest(operation: original.operation, asset: original.asset,
            fileURL: original.fileURL, invocationID: UUID())
        let bridge = FakeWebBridge()
        let client = adapter(bridge)
        _ = try await client.append(request)
        let before = await bridge.recordedActions()
        try Data(repeating: 42, count: bytes.count).write(to: request.fileURL)
        do { _ = try await client.append(request); XCTFail("Repeated request accepted") }
        catch WebAdapterError.invalidRequest {}
        let after = await bridge.recordedActions()
        XCTAssertEqual(after, before)
    }

    func testCorruptFileWithNewDispatchNonceRecoversBeforeAnyBridgeCommand() async throws {
        let (_, original, bytes) = try await fixture()
        try Data(repeating: 42, count: bytes.count).write(to: original.fileURL)
        let nonce = UUID()
        let request = TransferRequest(operation: original.operation, asset: original.asset,
            fileURL: original.fileURL, invocationID: nonce)
        let bridge = FakeWebBridge()
        do { _ = try await adapter(bridge).append(request); XCTFail("Corrupt file accepted") }
        catch let proof as PreInputRejection {
            XCTAssertEqual(proof.stage, .localBeforeBegin)
            XCTAssertEqual(proof.operationID, original.operation.id)
            XCTAssertEqual(proof.invocationID, nonce)
        }
        let actions = await bridge.recordedActions()
        XCTAssertTrue(actions.isEmpty)
    }

    func testOnlyFreshIdentityBoundRetirementCanProveNoInput() async throws {
        for fault in RetirementFault.allCases {
            let (_, original, _) = try await fixture()
            let nonce = UUID()
            let request = TransferRequest(operation: original.operation, asset: original.asset,
                fileURL: original.fileURL, invocationID: nonce)
            let bridge = RetirementBridge(fault: fault)
            let client = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge,
                program: program, mode: .syntheticDevelopment, polling: .disabled)
            do { _ = try await client.append(request); XCTFail("Expected rejection: \(fault)") }
            catch let proof as PreInputRejection {
                XCTAssertTrue(fault == .none || fault == .beginCapacity)
                XCTAssertEqual(proof.operationID, request.operation.id)
                XCTAssertEqual(proof.assetID, request.asset.id)
                XCTAssertEqual(proof.attempt, request.operation.attempt)
                XCTAssertEqual(proof.assetSHA256, request.asset.sha256)
                XCTAssertEqual(proof.target, request.operation.target)
                XCTAssertEqual(proof.invocationID, nonce)
                XCTAssertEqual(proof.stage, fault == .beginCapacity ? .pageRejectedBeforeBegin : .pageRetiredBeforeCommit)
            } catch { XCTAssertFalse(fault == .none || fault == .beginCapacity, "Exact proof should qualify") }
            let actions = await bridge.actions()
            XCTAssertEqual(actions.filter { $0 == .begin }.count, 1)
            XCTAssertEqual(actions.filter { $0 == .commit }.count, fault == .commitReplyLost ? 1 : 0)
            if fault == .commitReplyLost || fault == .beginReplyLost || fault == .beginCapacity {
                XCTAssertFalse(actions.contains(.discard))
            }
        }
    }

    func testLegacyRequestWithoutInvocationCannotRecoverFromRetirement() async throws {
        let (_, request, _) = try await fixture()
        let bridge = RetirementBridge(fault: .none)
        let client = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge,
            program: program, mode: .syntheticDevelopment, polling: .disabled)
        do { _ = try await client.append(request); XCTFail("Expected rejection") }
        catch is PreInputRejection { XCTFail("Legacy request was granted recovery") }
        catch {}
    }

    func testPositiveStartReturnsBeforeFinalAndReconcileNeverReinputs() async throws {
        let (store, request, _) = try await fixture()
        let executor = FakeWebBridge(behavior: .startedThenAttached)
        let profile = ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
            profileID: "test-completion", completionSignal: .attached, uploadStartProfileID: "test-start")
        let client = WebAttachmentAdapter(mediaDirectory: directory, executor: executor, program: program,
            mode: .syntheticDevelopment, profile: profile, polling: .init(timeout: 5, interval: 0.01))
        let start = try await client.append(request)
        XCTAssertEqual(start.outcome, .uploadStarted)
        XCTAssertFalse(start.positiveReady); XCTAssertFalse(start.safeToRetry)
        let before = await executor.recordedActions()
        XCTAssertEqual(before, [.begin, .chunk, .chunk, .commit], "append waited for final observation")
        let policy = ReceiptPolicy(syntheticAcceptanceProfiles: ["test-completion": .webChat],
                                   syntheticUploadStartProfiles: ["test-start": .webChat])
        let hidden = try await store.apply(start, policy: policy)
        XCTAssertEqual(hidden.visibility, .swallowed); XCTAssertNotEqual(hidden.status, .used)
        let saved = try await store.operation(id: request.operation.id)
        let original = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset, fileURL: request.fileURL)
        let ready = try await client.reconcile(original)
        XCTAssertEqual(ready.outcome, .verifiedReady)
        let complete = try await store.apply(ready, policy: policy)
        XCTAssertEqual(complete.status, .used); XCTAssertEqual(complete.visibility, .swallowed)
        let after = await executor.recordedActions()
        XCTAssertEqual(after, before + [.observe])
        let audit = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertEqual(audit, start)
    }

    func testDefaultDisabledAndMissingProgramDoNotExecuteAnyBrowserCommand() async throws {
        let executor = FakeWebBridge()
        let disabled = WebAttachmentAdapter(mediaDirectory: directory, executor: executor, program: program)
        do { _ = try await disabled.captureTarget(); XCTFail("Default adapter was enabled") }
        catch WebAdapterError.disabled {}
        do { _ = try await adapter(executor, withProgram: false).captureTarget(); XCTFail("Missing page source was fabricated") }
        catch WebAdapterError.programUnavailable {}
        let commands = await executor.recordedActions()
        XCTAssertTrue(commands.isEmpty)
    }

    func testCaptureValidateAndChunkedCommitPreserveExactBytesAndOperation() async throws {
        let executor = FakeWebBridge()
        let client = adapter(executor)
        let captured = try await client.captureTarget()
        XCTAssertEqual(captured, FakeWebBridge.target)
        let valid = try await client.validate(captured)
        XCTAssertTrue(valid)
        let (store, request, bytes) = try await fixture()
        let receipt = try await client.append(request)
        XCTAssertEqual(receipt.outcome, .attachedCandidate)
        XCTAssertEqual(receipt.operationID, request.operation.id)
        XCTAssertFalse(receipt.positiveReady)
        let commands = await executor.recordedActions()
        XCTAssertEqual(commands, [.captureTarget, .validate, .begin, .chunk, .chunk, .commit])
        let received = await executor.bytes()
        XCTAssertEqual(received, bytes)
        let record = try await store.apply(receipt)
        XCTAssertNotEqual(record.status, .used)
        let uploadName = await executor.uploadName()
        XCTAssertEqual(uploadName, "riftlet-\(request.operation.id.uuidString).png")
    }

    func testRealAssetAndPreIntentAreRejectedBeforeBridgeSideEffects() async throws {
        let executor = FakeWebBridge()
        let client = adapter(executor)
        let (_, real, _) = try await fixture(origin: .systemScreenshot)
        do { _ = try await client.append(real); XCTFail("Real image entered synthetic development bridge") }
        catch WebAdapterError.syntheticAssetsOnly {}
        let (_, prepared, _) = try await fixture(dispatch: false)
        do { _ = try await client.append(prepared); XCTFail("Input before intent") }
        catch WebAdapterError.invalidRequest {}
        let actions = await executor.recordedActions()
        XCTAssertTrue(actions.isEmpty)
    }

    func testCorruptOrSymlinkPrivateFileIsRejectedBeforeBegin() async throws {
        let executor = FakeWebBridge()
        let client = adapter(executor)
        let (_, corrupt, original) = try await fixture()
        try Data(repeating: 9, count: original.count).write(to: corrupt.fileURL)
        do { _ = try await client.append(corrupt); XCTFail("Hash mismatch uploaded") }
        catch WebAdapterError.invalidPrivateFile {}
        let (_, linked, _) = try await fixture()
        let source = directory.appendingPathComponent("symlink-source.png")
        try FileManager.default.moveItem(at: linked.fileURL, to: source)
        try FileManager.default.createSymbolicLink(at: linked.fileURL, withDestinationURL: source)
        do { _ = try await client.append(linked); XCTFail("Symlink uploaded") }
        catch WebAdapterError.invalidPrivateFile {}
        let actions = await executor.recordedActions()
        XCTAssertTrue(actions.isEmpty)
    }

    func testWrongChunkAcknowledgementDiscardsOnlyBufferAndNeverCommits() async throws {
        let executor = FakeWebBridge(behavior: .wrongChunkIdentity)
        let (_, request, _) = try await fixture()
        do { _ = try await adapter(executor).append(request); XCTFail("Wrong chunk ACK accepted") }
        catch WebAdapterError.invalidReply {}
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions, [.begin, .chunk, .discard])
    }

    func testFileMutationDuringTransferIsDetectedBeforeInputCommit() async throws {
        let (_, request, bytes) = try await fixture()
        let executor = FakeWebBridge(behavior: .replaceBytesAfterBegin(request.fileURL, bytes.count))
        do { _ = try await adapter(executor).append(request); XCTFail("Changed source committed") }
        catch WebAdapterError.invalidPrivateFile {}
        let actions = await executor.recordedActions()
        XCTAssertFalse(actions.contains(.commit))
        XCTAssertEqual(actions.last, .discard)
    }

    func testCommitErrorHasOneInputAttemptAndUnknownReconcileOnlyObserves() async throws {
        let (store, request, _) = try await fixture()
        let executor = FakeWebBridge(behavior: .throwOnCommit)
        let client = adapter(executor)
        do { _ = try await client.append(request); XCTFail("Commit exception hidden") }
        catch WebAdapterError.nativeExecutionFailed {}
        // Mirrors coordinator's existing durable error boundary, then uses original identity.
        try await store.markUnknown(request.operation.id, reason: "Synthetic uncertain commit")
        let operation = try await store.operation(id: request.operation.id)
        let original = TransferRequest(operation: try XCTUnwrap(operation), asset: request.asset, fileURL: request.fileURL)
        let receipt = try await client.reconcile(original)
        XCTAssertEqual(receipt.outcome, .unknown)
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions.filter { $0 == .commit }.count, 1)
        XCTAssertEqual(actions.last, .observe)
        XCTAssertFalse(actions.contains(.discard))
    }

    func testReconcileDoesNotNeedFileOrCauseAnotherInput() async throws {
        let (store, request, _) = try await fixture()
        try await store.markUnknown(request.operation.id, reason: "Synthetic restart")
        let operation = try await store.operation(id: request.operation.id)
        let original = TransferRequest(operation: try XCTUnwrap(operation), asset: request.asset, fileURL: request.fileURL)
        try FileManager.default.removeItem(at: request.fileURL)
        let executor = FakeWebBridge()
        _ = try await adapter(executor).reconcile(original)
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions, [.observe])
    }

    func testSucceededOperationChecksLateErrorWithoutFileOrAnyNewInput() async throws {
        let (store, request, _) = try await fixture()
        let ready = TransferReceipt(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
            target: request.operation.target, outcome: .verifiedReady, profileID: "web-unadmitted-v1",
            attachmentID: "synthetic-attachment", positiveReady: true, belongsToOriginalDraft: true)
        _ = try await store.apply(ready, policy: .init(syntheticAcceptanceProfiles: ["web-unadmitted-v1": .webChat]))
        let saved = try await store.operation(id: request.operation.id)
        let success = TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset, fileURL: request.fileURL)
        XCTAssertEqual(success.operation.phase, .succeeded)
        try FileManager.default.removeItem(at: request.fileURL)
        let executor = FakeWebBridge(behavior: .lateError)
        let receipt = try await adapter(executor).reconcile(success)
        XCTAssertEqual(receipt.outcome, .unknown)
        XCTAssertTrue(receipt.hasError)
        XCTAssertEqual(receipt.attachmentID, ready.attachmentID)
        XCTAssertFalse(receipt.safeToRetry)
        let result = try await store.apply(receipt)
        XCTAssertEqual(result.status, .unknown)
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions, [.observe])
        do { _ = try await adapter(executor).append(success); XCTFail("Succeeded operation uploaded again") }
        catch WebAdapterError.invalidRequest {}
    }

    func testBrowserReportedTargetChangeCannotValidateOldDraft() async throws {
        let executor = FakeWebBridge(behavior: .changedValidationTarget)
        let valid = try await adapter(executor).validate(FakeWebBridge.target)
        XCTAssertFalse(valid)
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions, [.validate])
    }

    func testBundledProgramAndBoundedObservationReachCompletionWithoutAnotherInput() async throws {
        let bundled = try ChatGPTWebPageProgram.load()
        XCTAssertEqual(bundled.sourceID, ChatGPTWebPageProgram.sourceID)
        XCTAssertEqual(bundled.maximumChunkBytes, 256 * 1024)
        XCTAssertLessThan(bundled.functionSource.utf8.count, 128 * 1024)
        let (_, request, _) = try await fixture()
        let executor = FakeWebBridge(behavior: .pendingThenAttached)
        let client = WebAttachmentAdapter(mediaDirectory: directory, executor: executor,
            program: bundled, mode: .syntheticDevelopment, profile: ChatGPTWebPageProgram.acceptanceProfile,
            polling: WebObservationPolling(timeout: 1, interval: 0.01))
        let receipt = try await client.append(request)
        XCTAssertEqual(receipt.outcome, .verifiedReady)
        XCTAssertTrue(receipt.positiveReady)
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions, [.begin, .chunk, .commit, .observe])
    }

    func testReviewedLargerChunksPreserveAllBytesAcknowledgementsAndFrozenIdentity() async throws {
        let (_, request, bytes) = try await fixture(byteCount: 3_147_775)
        let executor = FakeWebBridge()
        let client = WebAttachmentAdapter(mediaDirectory: directory, executor: executor,
            program: WebPageProgram(sourceID: "bounded-large-chunk-fixture", functionSource: program.functionSource,
                                    maximumChunkBytes: 256 * 1024), mode: .syntheticDevelopment, polling: .disabled)
        _ = try await client.append(request)
        let sizes = await executor.sizes(), indices = await executor.indices(), received = await executor.bytes()
        XCTAssertEqual(sizes, Array(repeating: 256 * 1024, count: 12) + [2_047])
        XCTAssertEqual(indices, Array(0..<13)); XCTAssertEqual(received, bytes)
        let identities = await executor.originalIdentities()
        XCTAssertTrue(identities.allSatisfy { $0.operationID == request.operation.id && $0.assetID == request.asset.id
            && $0.attempt == request.operation.attempt && $0.assetSHA256 == request.asset.sha256 && $0.target == request.operation.target })
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions, [.begin] + Array(repeating: .chunk, count: 13) + [.commit])
        XCTAssertEqual(program.maximumChunkBytes, 64 * 1024)
    }

    func testLargeChunkWrongAcknowledgementNeverSendsTheNextChunkOrCommit() async throws {
        let (_, request, _) = try await fixture(byteCount: 300_000)
        let executor = FakeWebBridge(behavior: .wrongChunkIdentity)
        let client = WebAttachmentAdapter(mediaDirectory: directory, executor: executor,
            program: WebPageProgram(sourceID: "large-chunk-wrong-ack", functionSource: program.functionSource,
                                    maximumChunkBytes: 256 * 1024), mode: .syntheticDevelopment, polling: .disabled)
        do { _ = try await client.append(request); XCTFail("Wrong ACK advanced transfer") }
        catch WebAdapterError.invalidReply {}
        let actions = await executor.recordedActions(), sizes = await executor.sizes()
        XCTAssertEqual(actions, [.begin, .chunk, .discard]); XCTAssertEqual(sizes, [256 * 1024])
    }

    func testLostLargeChunkReplyAndUncertainCommitNeverRetransmitOnReconcile() async throws {
        for behavior in [FakeWebBridge.Behavior.throwOnChunk, .throwOnCommit] {
            let (store, request, _) = try await fixture(byteCount: 300_000)
            let executor = FakeWebBridge(behavior: behavior)
            let client = WebAttachmentAdapter(mediaDirectory: directory, executor: executor,
                program: WebPageProgram(sourceID: "large-chunk-uncertain", functionSource: program.functionSource,
                                        maximumChunkBytes: 256 * 1024), mode: .syntheticDevelopment, polling: .disabled)
            do { _ = try await client.append(request); XCTFail("Lost response treated as success") }
            catch WebAdapterError.nativeExecutionFailed {}
            let before = await executor.recordedActions()
            if case .throwOnChunk = behavior { XCTAssertEqual(before, [.begin, .chunk, .discard]) }
            else { XCTAssertEqual(before, [.begin, .chunk, .chunk, .commit]) }
            try await store.markUnknown(request.operation.id, reason: "Bounded test lost original bridge response")
            let persisted = try await store.operation(id: request.operation.id)
            let original = TransferRequest(operation: try XCTUnwrap(persisted), asset: request.asset, fileURL: request.fileURL)
            _ = try await client.reconcile(original)
            let after = await executor.recordedActions(); XCTAssertEqual(after, before + [.observe])
        }
    }

    func testUnsupportedChunkCapacityAndOverEightMiBFileRefuseBeforeBridgeCommands() async throws {
        let executor = FakeWebBridge()
        for size in [0, 256 * 1024 + 1] {
            let client = WebAttachmentAdapter(mediaDirectory: directory, executor: executor,
                program: WebPageProgram(sourceID: "invalid-cap", functionSource: program.functionSource,
                                        maximumChunkBytes: size), mode: .syntheticDevelopment)
            do { _ = try await client.captureTarget(); XCTFail("Invalid cap accepted") }
            catch WebAdapterError.programUnavailable {}
        }
        let (_, request, _) = try await fixture(byteCount: 8 * 1024 * 1024 + 1)
        do { _ = try await adapter(executor).append(request); XCTFail("Over-limit file transferred") }
        catch WebAdapterError.invalidPrivateFile {}
        let actions = await executor.recordedActions(); XCTAssertTrue(actions.isEmpty)
    }

    func testObservationDeadlinePreservesUnknownAndNeverResubmits() async throws {
        let (store, request, _) = try await fixture()
        let executor = FakeWebBridge(behavior: .alwaysPending)
        let client = WebAttachmentAdapter(mediaDirectory: directory, executor: executor,
            program: program, mode: .syntheticDevelopment,
            polling: WebObservationPolling(timeout: 0.05, interval: 0.01))
        let receipt = try await client.append(request)
        XCTAssertEqual(receipt.outcome, .unknown)
        let record = try await store.apply(receipt)
        XCTAssertNotEqual(record.status, .used)
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions.filter { $0 == .commit }.count, 1)
        XCTAssertTrue(actions.dropFirst(4).allSatisfy { $0 == .observe })
    }
}

private actor FakeWebBridge: WebBridgeExecutor {
    enum Behavior: Sendable {
        case startedThenAttached, normal, wrongChunkIdentity, throwOnChunk, throwOnCommit, changedValidationTarget, pendingThenAttached, alwaysPending, lateError
        case replaceBytesAfterBegin(URL, Int)
    }
    static let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
        applicationID: "com.google.Chrome", sessionID: "synthetic-session",
        windowID: "1", tabID: "2", documentID: "synthetic-document",
        composerID: "synthetic-composer", draftGeneration: "1")
    private let behavior: Behavior
    private var actions: [WebBridgeAction] = []
    private var received = Data()
    private var chunkSizes: [Int] = []
    private var chunkIndices: [Int] = []
    private var identities: [ObservationIdentity] = []
    private var name: String?
    init(behavior: Behavior = .normal) { self.behavior = behavior }
    func recordedActions() -> [WebBridgeAction] { actions }
    func bytes() -> Data { received }
    func sizes() -> [Int] { chunkSizes }
    func indices() -> [Int] { chunkIndices }
    func originalIdentities() -> [ObservationIdentity] { identities }
    func uploadName() -> String? { name }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        actions.append(command.action)
        if let identity = command.identity { identities.append(identity) }
        switch command.action {
        case .pinTarget: throw WebAdapterError.invalidRequest
        case .captureTarget:
            return try JSONEncoder().encode(Self.target)
        case .validate:
            var target = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.target)) as! [String: Any]
            if case .changedValidationTarget = behavior { target["draftGeneration"] = "changed" }
            return try JSONSerialization.data(withJSONObject: ["valid": true, "target": target])
        case .begin:
            name = command.uploadName
            if case let .replaceBytesAfterBegin(url, count) = behavior {
                let handle = try FileHandle(forWritingTo: url)
                try handle.write(contentsOf: Data(repeating: 33, count: count))
                try handle.close()
            }
            return try acknowledgement(command, next: 0)
        case .chunk:
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(command.chunkBase64)))
            chunkSizes.append(bytes.count); chunkIndices.append(try XCTUnwrap(command.chunkIndex))
            received.append(bytes)
            if case .throwOnChunk = behavior { throw WebAdapterError.nativeExecutionFailed }
            return try acknowledgement(command, next: try XCTUnwrap(command.chunkIndex) + 1)
        case .commit:
            if case .startedThenAttached = behavior { return try observation(command, state: .uploadStarted) }
            if case .throwOnCommit = behavior { throw WebAdapterError.nativeExecutionFailed }
            if case .pendingThenAttached = behavior { return try observation(command, state: .inputTriggered) }
            if case .alwaysPending = behavior { return try observation(command, state: .unknown) }
            return try observation(command, state: .attached)
        case .observe:
            if case .startedThenAttached = behavior { return try observation(command, state: .attached) }
            if case .lateError = behavior { return try observation(command, state: .invalidated) }
            if case .pendingThenAttached = behavior { return try observation(command, state: .attached) }
            return try observation(command, state: .unknown)
        case .discard:
            return Data("{}".utf8)
        }
    }

    private func acknowledgement(_ command: WebBridgeCommand, next: Int) throws -> Data {
        let identity = try XCTUnwrap(command.identity)
        var id = identity.operationID
        if command.action == .chunk, case .wrongChunkIdentity = behavior { id = UUID() }
        return try JSONSerialization.data(withJSONObject: [
            "operationID": id.uuidString, "attempt": identity.attempt, "nextChunk": next
        ])
    }

    private func observation(_ command: WebBridgeCommand, state: AttachmentObservedState) throws -> Data {
        let identity = try XCTUnwrap(command.identity)
        let start: ObservedUploadStart? = state == .uploadStarted ? .init(version: 1,
            signal: .correlatedProgress, evidenceID: UUID().uuidString, inputCount: 1,
            inputSequence: 1, startSequence: 4, previousProgress: 20, currentProgress: 40,
            inputObservedAtMS: 10, startObservedAtMS: 25) : nil
        let item = AttachmentObservation(identity: identity, state: state,
            attachmentID: "synthetic-attachment", exactImageIdentity: true, belongsToOriginalDraft: true,
            hasError: state == .invalidated, isUploading: start != nil, uploadStart: start)
        return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: start == nil ? 1 : 2,
            provenance: .init(source: .syntheticFixture, evidenceID: "W1-fake-bridge"), observation: item))
    }
}

private enum RetirementFault: CaseIterable, Sendable {
    case none, wrongInvocation, wrongIdentity, inputPresent, committed, missingProof
    case wrongAllocation, legacyAllocation, beginReplyLost, discardReplyLost, commitReplyLost
    case beginCapacity, beginCapacityWrongIdentity, beginCapacityWrongNonce, beginCapacityWrongReason
}

/// Deterministic transport fixture, not evidence of actual ChatGPT behavior.
private actor RetirementBridge: WebBridgeExecutor {
    let fault: RetirementFault
    var recorded: [WebBridgeAction] = []
    init(fault: RetirementFault) { self.fault = fault }
    func actions() -> [WebBridgeAction] { recorded }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        recorded.append(command.action)
        let identity = try XCTUnwrap(command.identity)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(identity))
        let nonce = command.invocationID ?? UUID()
        switch command.action {
        case .pinTarget: throw WebAdapterError.invalidRequest
        case .begin:
            if fault == .beginReplyLost { throw WebAdapterError.nativeExecutionFailed }
            if [.beginCapacity, .beginCapacityWrongIdentity, .beginCapacityWrongNonce, .beginCapacityWrongReason].contains(fault) {
                var bound = json as! [String: Any]
                if fault == .beginCapacityWrongIdentity { bound["assetID"] = UUID().uuidString }
                return try JSONSerialization.data(withJSONObject: ["identity": bound,
                    "invocationID": (fault == .beginCapacityWrongNonce ? UUID() : nonce).uuidString,
                    "retiredBeforeInput": true, "inputCount": 0, "commitInvoked": false,
                    "rejectedBeforeBegin": true,
                    "reason": fault == .beginCapacityWrongReason ? "BEGIN_REFUSED" : "ACTIVE_PAYLOAD_LIMIT"])
            }
            var ack: [String: Any] = ["operationID": identity.operationID.uuidString,
                "attempt": identity.attempt, "nextChunk": 0]
            if fault != .legacyAllocation {
                ack["allocated"] = fault != .wrongAllocation
                ack["identity"] = json; ack["invocationID"] = nonce.uuidString
            }
            return try JSONSerialization.data(withJSONObject: ack)
        case .chunk:
            if fault != .commitReplyLost { throw WebAdapterError.nativeExecutionFailed }
            return try JSONSerialization.data(withJSONObject: ["operationID": identity.operationID.uuidString,
                "attempt": identity.attempt, "nextChunk": (command.chunkIndex ?? 0) + 1])
        case .discard:
            if fault == .discardReplyLost { throw WebAdapterError.nativeExecutionFailed }
            if fault == .missingProof { return Data("{}".utf8) }
            var bound = json as! [String: Any]
            if fault == .wrongIdentity { bound["assetID"] = UUID().uuidString }
            return try JSONSerialization.data(withJSONObject: ["identity": bound,
                "invocationID": (fault == .wrongInvocation ? UUID() : nonce).uuidString,
                "retiredBeforeInput": true, "inputCount": fault == .inputPresent ? 1 : 0,
                "commitInvoked": fault == .committed])
        default: throw WebAdapterError.nativeExecutionFailed
        }
    }
}
