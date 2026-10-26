import XCTest
@testable import RiftletCore

final class QueueStoreTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-core-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func store(_ mode: StoreMode = .production) throws -> QueueStore {
        try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"), mode: mode)
    }
    private func image(_ source: String = UUID().uuidString, origin: AssetOrigin = .systemScreenshot, time: TimeInterval = 100) -> ImportedAsset {
        let id = UUID()
        return ImportedAsset(id: id, sourceKey: source, fileName: "\(id).png", sha256: String(repeating: "a", count: 64),
                             byteCount: 128, pixelWidth: 100, pixelHeight: 80, mediaType: "image/png",
                             capturedAt: Date(timeIntervalSince1970: time), origin: origin)
    }
    private func target(_ generation: String = "1", simulated: Bool = false) -> TargetLease {
        TargetLease(adapterID: simulated ? "simulation" : "web", surface: simulated ? .simulation : .webChat,
                    applicationID: "browser", sessionID: "session", windowID: "window", tabID: "tab",
                    documentID: "document", composerID: "composer", draftGeneration: generation)
    }
    private func receipt(_ op: TransferOperation, _ image: ImportedAsset, outcome: ReceiptOutcome = .verifiedReady,
                         target: TargetLease? = nil, safeToRetry: Bool = false, uploading: Bool = false,
                         error: Bool = false, positive: Bool? = nil) -> TransferReceipt {
        TransferReceipt(operationID: op.id, assetID: image.id, attempt: op.attempt, assetSHA256: image.sha256,
                        target: target ?? op.target, outcome: outcome,
                        profileID: op.target.surface == .simulation ? "simulation-v1" : "fixture-ready-v1",
                        attachmentID: "attachment-\(op.id)", positiveReady: positive ?? (outcome == .verifiedReady), belongsToOriginalDraft: true,
                        hasError: error, isUploading: uploading, safeToRetry: safeToRetry)
    }

    func testFileEventsDeduplicateButSamePixelsRemainTwoCaptures() async throws {
        let db = try store(); let first = image("source-a"); let second = image("source-b")
        let a = try await db.importAsset(first)
        let duplicate = try await db.importAsset(image("source-a"))
        _ = try await db.importAsset(second)
        XCTAssertEqual(a.id, duplicate.id)
        let queue = try await db.assets()
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.map(\.image.sha256), [first.sha256, first.sha256])
    }

    func testCaptureOrderAndSequenceTieBreakerSurviveReopen() async throws {
        let db = try store()
        let later = image(time: 200); let earlier = image(time: 100); let tie = image(time: 100)
        for entry in [later, earlier, tie] { _ = try await db.importAsset(entry) }
        let reopened = try store()
        let queue = try await reopened.assets()
        XCTAssertEqual(queue.map(\.id), [earlier.id, tie.id, later.id])
    }

    func testDuplicateClicksAllocateOnlyOneAttempt() async throws {
        let db = try store(); let asset = image(); _ = try await db.importAsset(asset)
        let a = try await db.prepare(assetID: asset.id, target: target())
        let b = try await db.prepare(assetID: asset.id, target: target("changed"))
        XCTAssertEqual(a, b)
        try await db.markDispatchIntent(a.id)
        let operations = try await db.unresolvedOperations()
        XCTAssertEqual(operations.count, 1)
    }

    func testCandidateAttachedCannotConsumeEvenAdmittedProfile() async throws {
        let db = try store(); let asset = image(); _ = try await db.importAsset(asset)
        let op = try await db.prepare(assetID: asset.id, target: target()); try await db.markDispatchIntent(op.id)
        let result = try await db.apply(receipt(op, asset, outcome: .attachedCandidate), policy: .init(admittedProfiles: ["fixture-ready-v1": .webChat]))
        XCTAssertEqual(result.status, .transferring)
        let queue = try await db.assets(); XCTAssertEqual(queue.count, 1)
    }

    func testUnadmittedReadyBecomesUnknownAndKeepsPrivateIdentity() async throws {
        let db = try store(); let asset = image(); _ = try await db.importAsset(asset)
        let op = try await db.prepare(assetID: asset.id, target: target()); try await db.markDispatchIntent(op.id)
        let result = try await db.apply(receipt(op, asset))
        XCTAssertEqual(result.status, .unknown); XCTAssertEqual(result.activeOperationID, op.id)
        let retry = try await db.prepare(assetID: asset.id, target: target())
        XCTAssertEqual(retry.id, op.id)
    }

    func testWrongDraftReceiptRejectedWithoutStateMutation() async throws {
        let db = try store(); let asset = image(); _ = try await db.importAsset(asset)
        let op = try await db.prepare(assetID: asset.id, target: target()); try await db.markDispatchIntent(op.id)
        do {
            _ = try await db.apply(receipt(op, asset, target: target("new-draft")))
            XCTFail("Mismatched draft was accepted")
        } catch RiftletError.mismatchedReceipt {}
        let result = try await db.asset(id: asset.id); XCTAssertEqual(result?.status, .transferring)
    }

    func testApprovedEvidenceStillRejectsErrorAndUploading() async throws {
        for (index, uploading, error) in [(0, true, false), (1, false, true), (2, false, false)] {
            let db = try QueueStore(databaseURL: directory.appendingPathComponent("\(index).sqlite"))
            let asset = image(); _ = try await db.importAsset(asset)
            let op = try await db.prepare(assetID: asset.id, target: target()); try await db.markDispatchIntent(op.id)
            let result = try await db.apply(receipt(op, asset, uploading: uploading, error: error, positive: index != 2),
                                            policy: .init(admittedProfiles: ["fixture-ready-v1": .webChat]))
            XCTAssertEqual(result.status, .unknown)
        }
    }

    func testSuccessTransactionPersistsUsedAndReceiptBeforeUIDisappears() async throws {
        let db = try store(); let asset = image(); _ = try await db.importAsset(asset)
        let op = try await db.prepare(assetID: asset.id, target: target()); try await db.markDispatchIntent(op.id)
        _ = try await db.apply(receipt(op, asset), policy: .init(admittedProfiles: ["fixture-ready-v1": .webChat]))
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        let queue = try await reopened.assets(); let all = try await reopened.assets(includeUsed: true)
        let savedOperation = try await reopened.operation(id: op.id)
        XCTAssertTrue(queue.isEmpty); XCTAssertEqual(all.first?.status, .used)
        XCTAssertEqual(savedOperation?.phase, .succeeded)
    }

    func testIntentCrashBecomesUnknownButPreIntentIsRetryable() async throws {
        let db = try store(); let a = image(); let b = image()
        _ = try await db.importAsset(a); _ = try await db.importAsset(b)
        let intent = try await db.prepare(assetID: a.id, target: target()); try await db.markDispatchIntent(intent.id)
        let pending = try await db.prepare(assetID: b.id, target: target())
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        let recoveredA = try await reopened.asset(id: a.id); let recoveredB = try await reopened.asset(id: b.id)
        let persisted = try await reopened.operation(id: pending.id)
        XCTAssertEqual(recoveredA?.status, .unknown); XCTAssertEqual(recoveredB?.status, .failed)
        XCTAssertEqual(persisted?.phase, .failed)
    }

    func testUnknownLocksTargetAndFailureMustBeSafeToRetry() async throws {
        let db = try store(); let a = image(); let b = image()
        _ = try await db.importAsset(a); _ = try await db.importAsset(b)
        let first = try await db.prepare(assetID: a.id, target: target()); try await db.markDispatchIntent(first.id)
        _ = try await db.apply(receipt(first, a, outcome: .definitiveFailure, safeToRetry: false))
        let second = try await db.prepare(assetID: b.id, target: target())
        do { try await db.markDispatchIntent(second.id); XCTFail("Unresolved target was unlocked") }
        catch RiftletError.targetBusy {}
        let unadmitted = try await db.apply(receipt(first, a, outcome: .definitiveFailure, safeToRetry: true))
        XCTAssertEqual(unadmitted.status, .unknown)
        _ = try await db.apply(receipt(first, a, outcome: .definitiveFailure, safeToRetry: true),
                               policy: .init(retrySafeProfiles: ["fixture-ready-v1": .webChat]))
        try await db.markDispatchIntent(second.id)
        let retry = try await db.prepare(assetID: a.id, target: target())
        XCTAssertEqual(retry.attempt, 2); XCTAssertNotEqual(retry.id, first.id)
        do { _ = try await db.apply(receipt(first, a)); XCTFail("Stale attempt receipt accepted") }
        catch RiftletError.mismatchedReceipt {}
    }

    func testSimulationCannotOpenProductionStoreOrAcceptRealImage() async throws {
        _ = try store()
        do { _ = try store(.simulation); XCTFail("Mode changed") } catch RiftletError.modeMismatch {}
        let isolated = try QueueStore(databaseURL: directory.appendingPathComponent("sim.sqlite"), mode: .simulation)
        do { _ = try await isolated.importAsset(image()); XCTFail("Real screenshot accepted in simulation") }
        catch RiftletError.modeMismatch {}
        let synthetic = image(origin: .synthetic); _ = try await isolated.importAsset(synthetic)
        let op = try await isolated.prepare(assetID: synthetic.id, target: target(simulated: true)); try await isolated.markDispatchIntent(op.id)
        let result = try await isolated.apply(receipt(op, synthetic))
        XCTAssertEqual(result.status, .used)
    }

    func testMetadataRejectsTraversalAndCheckpointPersists() async throws {
        let db = try store(); let asset = image()
        let invalid = ImportedAsset(sourceKey: "bad", fileName: "../outside.png", sha256: asset.sha256,
                                    byteCount: 1, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png")
        do { _ = try await db.importAsset(invalid); XCTFail("Traversal accepted") }
        catch RiftletError.invalidAsset {}
        let data = Data([0, 1, 2, 255]); try await db.saveCheckpoint(data, for: "source")
        let reopened = try store(); let saved = try await reopened.checkpoint(for: "source")
        XCTAssertEqual(saved, data)
    }
}
