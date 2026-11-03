import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Actual Swift adapter with a controlled bridge. These tests do not establish
/// current ChatGPT DOM behavior or real attachment-preservation acceptance.
final class WebInputResourceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("web-input-resource-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private struct Fixture {
        let store: QueueStore
        let request: TransferRequest
        let bytes: Data
    }

    private func fixture() async throws -> Fixture {
        let bytes = Data((0..<200).map { UInt8($0 % 251) })
        let file = directory.appendingPathComponent("\(UUID()).png")
        try bytes.write(to: file)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 4, pixelHeight: 4, mediaType: "image/png", origin: .synthetic)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "synthetic-resource-session",
            windowID: "1", tabID: "1", documentID: "synthetic-document",
            composerID: "synthetic-composer", draftGeneration: "synthetic-generation",
            logicalDraftIdentity: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                                       id: "00000000-0000-0000-0000-000000000001"), clickBindingID: UUID())
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        _ = try await store.importAsset(asset)
        let operation = try await store.prepare(assetID: asset.id, target: target)
        return Fixture(store: store, request: .init(operation: operation, asset: asset,
            fileURL: file, invocationID: UUID()), bytes: bytes)
    }

    private func commit(_ fixture: Fixture, resource: PreparedInputResource? = nil) async throws -> TransferRequest {
        let source = fixture.request, now = ProcessInfo.processInfo.systemUptime
        let record = try await fixture.store.asset(id: source.asset.id)
        let selection = AcceptedSelection(assetID: source.asset.id, target: source.operation.target,
            hostEpoch: UUID(), acknowledgedUptime: now - 0.005, eventUptime: now - 0.01,
            acceptedUptime: now, visibilityRevision: try XCTUnwrap(record?.visibilityRevision),
            deadlineUptime: now + 30, authorization: .nativeClickPin)
        let invocation = try await fixture.store.markDispatchIntent(source.operation.id,
            selection: selection, ownerID: UUID(), inputResource: resource)
        let operation = try await fixture.store.operation(id: source.operation.id)
        return .init(operation: try XCTUnwrap(operation), asset: source.asset, fileURL: source.fileURL,
                     invocationID: invocation, inputResource: resource)
    }

    private func adapter(_ bridge: InputResourceBridge) -> WebAttachmentAdapter {
        .init(mediaDirectory: directory, executor: bridge,
              program: .init(sourceID: "synthetic-input-resource-bridge", functionSource: "function () { return null; }"),
              mode: .syntheticDevelopment,
              profile: .init(adapterID: "chatgpt-web", surface: .webChat,
                             profileID: "resource-ready", completionSignal: .attached,
                             uploadStartProfileID: "resource-start"),
              polling: .init(timeout: 3, interval: 0.005))
    }

    func testPrepareBindsNextInvocationAndForwardsOneUseTokenToBegin() async throws {
        let value = try await fixture(), bridge = InputResourceBridge(), client = adapter(bridge)
        let resource = try await client.prepareInputResource(value.request)
        XCTAssertEqual(resource.operationID, value.request.operation.id)
        XCTAssertEqual(resource.assetID, value.request.asset.id)
        XCTAssertEqual(resource.target, value.request.operation.target)
        XCTAssertEqual(resource.invocationID, value.request.invocationID)
        let request = try await commit(value, resource: resource)
        let result = try await client.append(request)
        XCTAssertEqual(result.outcome, .uploadStarted)
        await client.releaseInputResource(resource)
        let commands = await bridge.commands(), bytes = await bridge.bytes(request.operation.id)
        XCTAssertEqual(commands.map(\.action), [.prepareInputResource, .begin, .chunk, .commit, .releaseInputResource])
        XCTAssertEqual(commands[1].inputResourceID, resource.resourceID)
        XCTAssertEqual(commands[1].invocationID, request.invocationID)
        XCTAssertEqual(commands.last?.inputResourceID, resource.resourceID)
        XCTAssertEqual(bytes, value.bytes)
        do { _ = try await client.append(request); XCTFail("Original input replayed") }
        catch WebAdapterError.invalidRequest {}
        let afterReplay = await bridge.commands()
        XCTAssertEqual(afterReplay.count, commands.count)
    }

    func testMalformedResourceRepliesCannotAuthorizeCurrentInput() async throws {
        for field in ["version", "identity", "invocation", "kind", "sequence", "negativeCount", "largeCount", "emptyInput", "largeInput", "resource"] {
            let value = try await fixture(), bridge = InputResourceBridge(badReplyField: field), client = adapter(bridge)
            do { _ = try await client.prepareInputResource(value.request); XCTFail("Malformed \(field) accepted") }
            catch WebAdapterError.invalidReply {}
            let commands = await bridge.commands()
            XCTAssertEqual(commands.map(\.action), [.prepareInputResource])
        }
    }

    func testStaleResourceBeginIsAnExactPreInputRejection() async throws {
        let value = try await fixture(), bridge = InputResourceBridge(refuseBegin: true), client = adapter(bridge)
        let resource = try await client.prepareInputResource(value.request)
        let request = try await commit(value, resource: resource)
        do { _ = try await client.append(request); XCTFail("Stale reservation input continued") }
        catch let rejection as PreInputRejection {
            XCTAssertEqual(rejection.stage, .pageRejectedBeforeBegin)
            XCTAssertEqual(rejection.operationID, request.operation.id)
            XCTAssertEqual(rejection.assetID, request.asset.id)
            XCTAssertEqual(rejection.target, request.operation.target)
            XCTAssertEqual(rejection.invocationID, request.invocationID)
        }
        let commands = await bridge.commands()
        XCTAssertEqual(commands.map(\.action), [.prepareInputResource, .begin])
    }

    func testUnsafeResourceRefusalClaimsNeverBecomeNoInputProof() async throws {
        for field in ["identity", "invocation", "retired", "commit", "inputCount", "reason"] {
            let value = try await fixture(), bridge = InputResourceBridge(refuseBegin: true, badRefusalField: field)
            let client = adapter(bridge), resource = try await client.prepareInputResource(value.request)
            let request = try await commit(value, resource: resource)
            do { _ = try await client.append(request); XCTFail("Invalid refusal \(field) accepted") }
            catch is PreInputRejection { XCTFail("Invalid refusal \(field) granted no-input authority") }
            catch WebAdapterError.invalidReply {}
            let commands = await bridge.commands()
            XCTAssertEqual(commands.map(\.action), [.prepareInputResource, .begin])
        }
    }

    func testResourceCannotBeBorrowedByAnotherRequestBeforeAnyBridgeCommand() async throws {
        for field in ["operation", "asset", "attempt", "hash", "target", "invocation"] {
            let value = try await fixture(), bridge = InputResourceBridge(), client = adapter(bridge)
            let request = try await commit(value)
            let otherFixture = try await fixture()
            let otherTarget = otherFixture.request.operation.target
            let invocation = try XCTUnwrap(request.invocationID)
            let resource = PreparedInputResource(operationID: field == "operation" ? UUID() : request.operation.id,
                assetID: field == "asset" ? UUID() : request.asset.id,
                attempt: field == "attempt" ? 2 : request.operation.attempt,
                assetSHA256: field == "hash" ? String(repeating: "b", count: 64) : request.asset.sha256,
                target: field == "target" ? otherTarget : request.operation.target,
                invocationID: field == "invocation" ? UUID() : invocation,
                resourceID: UUID(), inputElementID: "synthetic-empty-input")
            let wrong = TransferRequest(operation: request.operation, asset: request.asset, fileURL: request.fileURL,
                invocationID: request.invocationID, inputResource: resource)
            do { _ = try await client.append(wrong); XCTFail("Mismatched \(field) resource reached input") }
            catch WebAdapterError.invalidRequest {}
            let commands = await bridge.commands()
            XCTAssertTrue(commands.isEmpty)
        }
    }

    func testPreparedTokenCannotBypassTheCurrentNativeInputOwner() async throws {
        let a = try await fixture(), b = try await fixture()
        let entered = expectation(description: "A holds native commit")
        let bridge = InputResourceBridge(onCommit: { if $0 == a.request.operation.id { entered.fulfill() } })
        let client = adapter(bridge)
        let resource = try await client.prepareInputResource(b.request)
        let ar = try await commit(a), br = try await commit(b, resource: resource)
        await bridge.holdCommit(ar.operation.id)
        let first = Task { try await client.append(ar) }
        await fulfillment(of: [entered], timeout: 2)
        do { _ = try await client.append(br); XCTFail("A prepared token bypassed active input") }
        catch WebAdapterError.inputInFlight {}
        let c = try await fixture()
        do { _ = try await client.prepareInputResource(c.request); XCTFail("Preparation bypassed input owner") }
        catch WebAdapterError.inputInFlight {}
        let whileHeld = await bridge.commands()
        XCTAssertFalse(whileHeld.contains { $0.action == .begin && $0.identity?.operationID == br.operation.id })
        XCTAssertEqual(whileHeld.filter { $0.action == .prepareInputResource }.count, 1)
        await bridge.releaseCommit(ar.operation.id)
        _ = try await first.value
        _ = try await client.append(br)
        let commands = await bridge.commands()
        XCTAssertEqual(commands.filter { $0.action == .commit }.count, 2)
    }

    func testFreshResourceAllowsSameDraftBWhileAContinuesItsOwnStartObservation() async throws {
        let a = try await fixture(), b = try await fixture(), bridge = InputResourceBridge()
        let client = adapter(bridge), ar = try await commit(a)
        let confirmed = expectation(description: "A input execution ended before START")
        await bridge.holdStart(ar.operation.id)
        let first = Task { try await client.append(ar, onInputConfirmed: { _ in confirmed.fulfill() }) }
        await fulfillment(of: [confirmed], timeout: 2)
        let resource = try await client.prepareInputResource(b.request)
        let br = try await commit(b, resource: resource)
        let second = try await client.append(br, onInputConfirmed: { _ in })
        XCTAssertEqual(second.operationID, br.operation.id)
        XCTAssertEqual(second.outcome, .uploadStarted)
        await bridge.releaseStart(ar.operation.id)
        let original = try await first.value
        XCTAssertEqual(original.operationID, ar.operation.id)
        XCTAssertEqual(original.outcome, .uploadStarted)
        let commands = await bridge.commands(), aBytes = await bridge.bytes(ar.operation.id)
        let bBytes = await bridge.bytes(br.operation.id)
        XCTAssertEqual(commands.filter { $0.action == .commit && $0.identity?.operationID == ar.operation.id }.count, 1)
        XCTAssertEqual(commands.filter { $0.action == .commit && $0.identity?.operationID == br.operation.id }.count, 1)
        XCTAssertEqual(aBytes, a.bytes)
        XCTAssertEqual(bBytes, b.bytes)
    }
}

private actor InputResourceBridge: WebBridgeExecutor {
    private let badReplyField: String?
    private let refuseBegin: Bool
    private let badRefusalField: String?
    private let onCommit: @Sendable (UUID) -> Void
    private var recorded: [WebBridgeCommand] = []
    private var received: [UUID: Data] = [:]
    private var held = Set<UUID>()
    private var heldStarts = Set<UUID>()
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(badReplyField: String? = nil, refuseBegin: Bool = false, badRefusalField: String? = nil,
         onCommit: @escaping @Sendable (UUID) -> Void = { _ in }) {
        self.badReplyField = badReplyField; self.refuseBegin = refuseBegin
        self.badRefusalField = badRefusalField; self.onCommit = onCommit
    }
    func commands() -> [WebBridgeCommand] { recorded }
    func bytes(_ id: UUID) -> Data { received[id] ?? Data() }
    func holdCommit(_ id: UUID) { held.insert(id) }
    func releaseCommit(_ id: UUID) { held.remove(id); waiters.removeValue(forKey: id)?.resume() }
    func holdStart(_ id: UUID) { heldStarts.insert(id) }
    func releaseStart(_ id: UUID) { heldStarts.remove(id) }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        recorded.append(command)
        let identity = try XCTUnwrap(command.identity)
        let identityJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(identity))
        switch command.action {
        case .prepareInputResource:
            let invocation = try XCTUnwrap(command.invocationID)
            var body: [String: Any] = ["version": 1, "identity": identityJSON, "invocationID": invocation.uuidString,
                "resourceID": UUID().uuidString, "inputElementID": "synthetic-empty-input", "kind": "emptyNativeFileInput",
                "observedSequence": 7, "baselineAttachmentCount": 1]
            switch badReplyField {
            case "version": body["version"] = 2
            case "identity": var wrong = identityJSON as! [String: Any]; wrong["operationID"] = UUID().uuidString; body["identity"] = wrong
            case "invocation": body["invocationID"] = UUID().uuidString
            case "kind": body["kind"] = "fileListReplacement"
            case "sequence": body["observedSequence"] = 0
            case "negativeCount": body["baselineAttachmentCount"] = -1
            case "largeCount": body["baselineAttachmentCount"] = 4097
            case "emptyInput": body["inputElementID"] = ""
            case "largeInput": body["inputElementID"] = String(repeating: "a", count: 257)
            case "resource": body["resourceID"] = "not-a-uuid"
            default: break
            }
            return try JSONSerialization.data(withJSONObject: body)
        case .begin where refuseBegin:
            let invocation = try XCTUnwrap(command.invocationID)
            var body: [String: Any] = ["identity": identityJSON, "invocationID": invocation.uuidString,
                "rejectedBeforeBegin": true, "retiredBeforeInput": true, "commitInvoked": false,
                "inputCount": 0, "reason": "INPUT_RESOURCE_UNAVAILABLE"]
            switch badRefusalField {
            case "identity": var wrong = identityJSON as! [String: Any]; wrong["assetID"] = UUID().uuidString; body["identity"] = wrong
            case "invocation": body["invocationID"] = UUID().uuidString
            case "retired": body["retiredBeforeInput"] = false
            case "commit": body["commitInvoked"] = true
            case "inputCount": body["inputCount"] = 1
            case "reason": body["reason"] = "UNPROVEN"
            default: break
            }
            return try JSONSerialization.data(withJSONObject: body)
        case .begin, .chunk:
            if command.action == .chunk {
                received[identity.operationID, default: Data()].append(try XCTUnwrap(Data(base64Encoded: command.chunkBase64 ?? "")))
            }
            return try JSONSerialization.data(withJSONObject: ["operationID": identity.operationID.uuidString,
                "attempt": identity.attempt, "nextChunk": command.action == .begin ? 0 : (command.chunkIndex ?? 0) + 1])
        case .commit:
            onCommit(identity.operationID)
            if held.contains(identity.operationID) { await withCheckedContinuation { waiters[identity.operationID] = $0 } }
            return try observation(identity)
        case .observe:
            return try observation(identity)
        case .releaseInputResource:
            return Data("{\"released\":true}".utf8)
        default: throw WebAdapterError.invalidRequest
        }
    }

    private func observation(_ identity: ObservationIdentity) throws -> Data {
        let started = !heldStarts.contains(identity.operationID)
        let start: ObservedUploadStart? = started ? .init(version: 1, signal: .correlatedProgress,
            evidenceID: identity.operationID.uuidString, inputCount: 1,
            inputSequence: 1, startSequence: 4, previousProgress: 20, currentProgress: 40,
            inputObservedAtMS: 10, startObservedAtMS: 25) : nil
        return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: started ? 2 : 1,
            provenance: .init(source: .syntheticFixture, evidenceID: "controlled-input-resource"),
            observation: .init(identity: identity, state: started ? .uploadStarted : .inputTriggered,
                attachmentID: "attachment-\(identity.operationID)", exactImageIdentity: true,
                belongsToOriginalDraft: true, isUploading: started, uploadStart: start)))
    }
}
