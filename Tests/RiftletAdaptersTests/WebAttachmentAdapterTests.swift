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

    private func fixture(origin: AssetOrigin = .synthetic, dispatch: Bool = true) async throws -> (QueueStore, TransferRequest, Data) {
        let bytes = Data((0..<70_000).map { UInt8($0 % 251) })
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
            program: withProgram ? program : nil, mode: mode)
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

    func testBrowserReportedTargetChangeCannotValidateOldDraft() async throws {
        let executor = FakeWebBridge(behavior: .changedValidationTarget)
        let valid = try await adapter(executor).validate(FakeWebBridge.target)
        XCTAssertFalse(valid)
        let actions = await executor.recordedActions()
        XCTAssertEqual(actions, [.validate])
    }
}

private actor FakeWebBridge: WebBridgeExecutor {
    enum Behavior: Sendable {
        case normal, wrongChunkIdentity, throwOnCommit, changedValidationTarget
        case replaceBytesAfterBegin(URL, Int)
    }
    static let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
        applicationID: "com.google.Chrome", sessionID: "synthetic-session",
        windowID: "1", tabID: "2", documentID: "synthetic-document",
        composerID: "synthetic-composer", draftGeneration: "1")
    private let behavior: Behavior
    private var actions: [WebBridgeAction] = []
    private var received = Data()
    private var name: String?
    init(behavior: Behavior = .normal) { self.behavior = behavior }
    func recordedActions() -> [WebBridgeAction] { actions }
    func bytes() -> Data { received }
    func uploadName() -> String? { name }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        actions.append(command.action)
        switch command.action {
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
            received.append(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(command.chunkBase64))))
            return try acknowledgement(command, next: try XCTUnwrap(command.chunkIndex) + 1)
        case .commit:
            if case .throwOnCommit = behavior { throw WebAdapterError.nativeExecutionFailed }
            return try observation(command, state: .attached)
        case .observe:
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
        let item = AttachmentObservation(identity: identity, state: state,
            attachmentID: "synthetic-attachment", exactImageIdentity: true, belongsToOriginalDraft: true)
        return try JSONEncoder().encode(AttachmentObservationEnvelope(
            provenance: .init(source: .syntheticFixture, evidenceID: "W1-fake-bridge"), observation: item))
    }
}
