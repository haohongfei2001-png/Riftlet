import XCTest
import Foundation
import CryptoKit
import RiftletCore
import RiftletAdapters
@testable import RiftletApp

/// Complete ordinary composition with a deterministic page boundary. No browser,
/// user database or actual upload; fixture facts never assert platform acceptance.
private actor ProductPageFixture: WebBridgeExecutor {
    let target: TargetLease
    private(set) var actions: [WebBridgeAction] = []
    init(local: Bool) {
        target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "test-process", windowID: "1", tabID: "2", documentID: "doc", composerID: "composer",
            draftGeneration: "epoch",
            logicalDraftIdentity: .init(profileID: local ? "chatgpt-composer-react-20261027-v1" : "chatgpt-composer-react-persisted-20261027-v1",
                id: local ? "local-chatgpt:11111111-1111-4111-8111-111111111111" : "11111111-1111-4111-8111-111111111111"),
            clickBindingID: UUID())
    }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        actions.append(command.action)
        switch command.action {
        case .captureTarget: return try JSONEncoder().encode(target)
        case .validate:
            return try JSONSerialization.data(withJSONObject: ["valid": command.target == target,
                "target": JSONSerialization.jsonObject(with: JSONEncoder().encode(target))])
        case .begin, .chunk:
            let i = command.identity!
            return try JSONSerialization.data(withJSONObject: ["operationID": i.operationID.uuidString, "attempt": i.attempt,
                "nextChunk": command.action == .begin ? 0 : command.chunkIndex! + 1])
        case .commit, .observe:
            let i = command.identity!, start = command.action == .commit
            var observation: [String: Any] = [
                "identity": try JSONSerialization.jsonObject(with: JSONEncoder().encode(i)),
                "state": start ? "uploadStarted" : "attached", "attachmentID": "card-" + i.operationID.uuidString,
                "exactImageIdentity": true, "belongsToOriginalDraft": true, "hasError": false,
                "isUploading": start, "attachmentAbsent": false, "automaticRetryExcluded": false
            ]
            if start {
                observation["uploadStart"] = ["version": 1, "signal": "correlatedProgress", "evidenceID": UUID().uuidString,
                    "inputCount": 1, "inputSequence": 1, "startSequence": 3, "previousProgress": 10,
                    "currentProgress": 30, "inputObservedAtMS": 10, "startObservedAtMS": 20]
            }
            return try JSONSerialization.data(withJSONObject: ["schemaVersion": 2,
                "provenance": ["source": "integratedDevelopment", "evidenceID": "isolated-product-fixture"],
                "observation": observation])
        default: throw WebAdapterError.invalidRequest
        }
    }
}

final class UnifiedProductCompositionTests: XCTestCase {
    @MainActor func testBothSourcesNewAndPersistedDraftsUseOneTransportAndIndependentProfiles() async throws {
        for origin in [AssetOrigin.systemScreenshot, .applicationScreenshot] {
            for local in [false, true] {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: root) }
                let media = root.appendingPathComponent("media")
                try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
                let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==")!
                // Real file validation, original bytes and private path are used;
                // only the browser's boundary is a controlled fixture.
                let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), id = UUID()
                let asset = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: id.uuidString + ".png",
                    sha256: hash, byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: origin)
                try bytes.write(to: media.appendingPathComponent(asset.fileName))
                let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
                _ = try await store.importAsset(asset)
                let page = ProductPageFixture(local: local)
                let composition = try ApplicationAttachmentComposition.make(mode: .capture, root: root, store: store,
                    executor: page, ordinary: .unifiedProduct)
                let target = try await composition.adapter.captureTarget()
                let valid = try await composition.adapter.validate(target)
                XCTAssertTrue(valid)
                let operation = try await store.prepare(assetID: asset.id, target: target)
                let invocation = try await store.markDispatchIntent(operation.id)
                let dispatched = try await store.operation(id: operation.id)!
                let request = TransferRequest(operation: dispatched, asset: asset,
                    fileURL: media.appendingPathComponent(asset.fileName), invocationID: invocation)
                let start = try await composition.adapter.append(request)
                XCTAssertTrue(composition.policy.allowsUploadStart(receipt: start, asset: asset, mode: .production))
                let expected = origin == .systemScreenshot ? OrdinaryProductScreenshotScope.admittedSystemProfile : OrdinaryProductScreenshotScope.admittedApplicationProfile
                XCTAssertEqual(start.profileID, expected.profileID)
                let hidden = try await store.apply(start, policy: composition.policy)
                XCTAssertEqual(hidden.visibility, .swallowed)
                XCTAssertNotEqual(hidden.status, .used)
                let final = try await composition.adapter.reconcile(request)
                let used = try await store.apply(final, policy: composition.policy)
                XCTAssertEqual(used.status, .used)
                XCTAssertTrue(composition.policy.retrySafeProfiles.isEmpty)
                XCTAssertTrue(composition.policy.continuationProfiles.isEmpty)
                do { _ = try await composition.adapter.append(request); XCTFail("original input reused") } catch {}
                let actions = await page.actions
                XCTAssertEqual(actions.filter { $0 == .commit }.count, 1)
                XCTAssertEqual(actions.filter { $0 == .begin }.count, 1)
                XCTAssertEqual(actions.filter { $0 == .observe }.count, 1)
                let reopened = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
                let persisted = try await reopened.asset(id: asset.id)
                XCTAssertEqual(persisted?.status, .used)
                XCTAssertEqual(persisted?.image.origin, origin)
            }
        }
    }

    @MainActor func testInputOnlyLegacyUnknownIsNotPromotedByProductUpgrade() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==")!
        let id = UUID(), asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "legacy.png",
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1, mediaType: "image/png")
        let file = media.appendingPathComponent(asset.fileName); try bytes.write(to: file)
        let dbURL = root.appendingPathComponent("queue.sqlite")
        let store = try QueueStore(databaseURL: dbURL); _ = try await store.importAsset(asset)
        let page = ProductPageFixture(local: true)
        let prior = try ApplicationAttachmentComposition.make(mode: .capture, root: root, store: store, executor: page,
            ordinary: .internalAcceptance(start: false, completion: false, currentDrafts: true))
        let target = try await prior.adapter.captureTarget()
        let operation = try await store.prepare(assetID: asset.id, target: target)
        let invocation = try await store.markDispatchIntent(operation.id, ownerID: id)
        let original = try await store.operation(id: operation.id)!
        let request = TransferRequest(operation: original, asset: asset, fileURL: file, invocationID: invocation)
        let start = try await prior.adapter.append(request)
        let oldUnknown = try await store.apply(start, policy: prior.policy)
        XCTAssertEqual(oldUnknown.status, .unknown)
        let reopened = try QueueStore(databaseURL: dbURL)
        let product = try ApplicationAttachmentComposition.make(mode: .capture, root: root, store: reopened, executor: page,
            ordinary: .unifiedProduct)
        let unknown = try await reopened.operation(id: operation.id)!
        let observed = try await product.adapter.reconcile(.init(operation: unknown, asset: asset, fileURL: file))
        XCTAssertEqual(observed.outcome, .verifiedReady, "Observation remains available under its original profile")
        XCTAssertFalse(product.policy.allowsConsumption(receipt: observed, asset: asset, mode: .production))
        let retained = try await reopened.apply(observed, policy: product.policy)
        XCTAssertEqual(retained.status, .unknown)
        XCTAssertEqual(retained.activeOperationID, operation.id)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let actions = await page.actions
        XCTAssertEqual(actions.filter { $0 == .commit }.count, 1)
        XCTAssertEqual(actions.filter { $0 == .begin }.count, 1)
    }

    func testSourceProfilesCannotBorrowEachOtherOrSyntheticOrRetryApproval() {
        let policy = OrdinaryAttachmentAdmission.unifiedProduct.receiptPolicy
        for profile in [OrdinaryProductScreenshotScope.admittedSystemProfile, .init(adapterID: "chatgpt-web", surface: .webChat,
                profileID: OrdinaryProductScreenshotScope.applicationCompletionProfileID, completionSignal: .attached,
                uploadStartProfileID: OrdinaryProductScreenshotScope.applicationUploadStartProfileID)] {
            let expected: AssetOrigin = profile.profileID == OrdinaryProductScreenshotScope.systemCompletionProfileID ? .systemScreenshot : .applicationScreenshot
            for origin in [AssetOrigin.systemScreenshot, .applicationScreenshot, .synthetic] {
                let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "image.png", sha256: String(repeating: "a", count: 64),
                    byteCount: 64, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: origin)
                let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
                    sessionID: "s", windowID: "1", tabID: "2", documentID: "d", composerID: "c", draftGeneration: "e")
                let start = TransferReceipt(operationID: UUID(), assetID: asset.id, attempt: 1, assetSHA256: asset.sha256,
                    target: target, outcome: .uploadStarted, profileID: profile.profileID, attachmentID: "card",
                    belongsToOriginalDraft: true, isUploading: true,
                    uploadStartEvidence: .init(profileID: profile.uploadStartProfileID!, signal: .correlatedProgress, evidenceID: UUID().uuidString))
                XCTAssertEqual(policy.allowsUploadStart(receipt: start, asset: asset, mode: .production), origin == expected)
                XCTAssertFalse(policy.allowsContinuation(receipt: start, asset: asset, mode: .production))
                let ready = TransferReceipt(operationID: start.operationID, assetID: asset.id, attempt: 1, assetSHA256: asset.sha256,
                    target: target, outcome: .verifiedReady, profileID: profile.profileID, attachmentID: "card",
                    positiveReady: true, belongsToOriginalDraft: true)
                XCTAssertEqual(policy.allowsConsumption(receipt: ready, asset: asset, mode: .production), origin == expected)
                XCTAssertFalse(policy.allowsRetry(receipt: ready, asset: asset, mode: .production))
            }
        }
    }
}
