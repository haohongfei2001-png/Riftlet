import Foundation
import XCTest
@testable import RiftletCore

/// Protocol/SQLite fixtures only. The platform IDs below are not ChatGPT facts
/// and do not register any shipping completion, termination or continuation.
final class AttachmentTerminalEvidenceTests: XCTestCase {
    private var directory: URL!
    private let readyProfile = "terminal-fixture-completion"
    private let startProfile = "terminal-fixture-start"
    private let continuationProfile = "terminal-fixture-continuation"
    private let terminationProfile = "terminal-fixture-retirement"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-evidence-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private struct Fixture {
        let store: QueueStore
        let asset: ImportedAsset
        let operation: TransferOperation
        let invocation: UUID
        let owner: UUID
    }
    private func target() -> TargetLease {
        .init(adapterID: "terminal-fixture", surface: .webChat, applicationID: "com.google.Chrome",
              sessionID: "fixture-session", windowID: "1", tabID: "1", documentID: "document",
              composerID: "composer", draftGeneration: "epoch",
              logicalDraftIdentity: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                                         id: "00000000-0000-0000-0000-000000000001"), clickBindingID: UUID())
    }
    private func policy(platform: Bool = false, retirement: Bool = true) -> ReceiptPolicy {
        .init(admittedProfiles: [readyProfile: .webChat], retrySafeProfiles: [readyProfile: .webChat],
              uploadStartProfiles: [startProfile: .webChat], continuationProfiles: [continuationProfile: .webChat],
              profileOrigins: [readyProfile: [.systemScreenshot], startProfile: [.systemScreenshot],
                               continuationProfile: [.systemScreenshot], terminationProfile: [.systemScreenshot]],
              requiredCompletionEvidenceProfiles: [readyProfile], requiredTerminationEvidenceProfiles: [readyProfile],
              platformCompletionProfiles: platform ? [readyProfile: .webChat] : [:],
              terminationProfiles: retirement ? [terminationProfile: .webChat] : [:])
    }
    private func newAsset(_ store: QueueStore) async throws -> ImportedAsset {
        let id = UUID()
        let asset = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: id.uuidString + ".png",
                                  sha256: String(repeating: "a", count: 64), byteCount: 123,
                                  pixelWidth: 4, pixelHeight: 4, mediaType: "image/png")
        _ = try await store.importAsset(asset); return asset
    }
    private func selection(_ asset: ImportedAsset, target: TargetLease) -> AcceptedSelection {
        let now = ProcessInfo.processInfo.systemUptime
        return .init(assetID: asset.id, target: target, hostEpoch: UUID(), acknowledgedUptime: now - 0.005,
                     eventUptime: now - 0.01, acceptedUptime: now, visibilityRevision: 0,
                     deadlineUptime: now + 30, authorization: .nativeClickPin)
    }
    private func fixture(store: QueueStore? = nil, owner: UUID = UUID()) async throws -> Fixture {
        let store = try store ?? QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        let asset = try await newAsset(store), target = target()
        let op = try await store.prepare(assetID: asset.id, target: target)
        let invocation = try await store.markDispatchIntent(op.id, selection: selection(asset, target: target),
                                                           ownerID: owner, policy: policy())
        return Fixture(store: store, asset: asset, operation: op, invocation: invocation, owner: owner)
    }
    private func binding(_ f: Fixture) -> AttachmentOperationBinding {
        .init(operationID: f.operation.id, assetID: f.asset.id, attempt: f.operation.attempt,
              assetSHA256: f.asset.sha256, target: f.operation.target, invocationID: f.invocation,
              attachmentID: "attachment-\(f.operation.id)")
    }
    private func task(_ f: Fixture) -> PlatformAttachmentTaskIdentity {
        .init(requestID: "request-\(f.operation.id)", taskID: "task-\(f.operation.id)",
              attachmentReference: "platform-attachment-\(f.operation.id)", originalSHA256: f.asset.sha256,
              originalByteCount: f.asset.byteCount)
    }
    private func completion(_ f: Fixture, kind: AttachmentCompletionEvidence.Kind = .exactOriginalBytes) -> AttachmentCompletionEvidence {
        switch kind {
        case .exactOriginalBytes:
            return .init(evidenceID: "completion-\(f.operation.id)", binding: binding(f), kind: kind,
                         originalByteCount: f.asset.byteCount, originalSHA256: f.asset.sha256,
                         observedByteCount: f.asset.byteCount, observedSHA256: f.asset.sha256)
        case .exactSRGBPixels:
            return .init(evidenceID: "completion-\(f.operation.id)", binding: binding(f), kind: kind,
                         originalByteCount: f.asset.byteCount, originalSHA256: f.asset.sha256,
                         originalWidth: 4, originalHeight: 4, originalPixelSHA256: String(repeating: "b", count: 64),
                         previewWidth: 4, previewHeight: 4, previewPixelSHA256: String(repeating: "b", count: 64))
        case .platformFinalizedOriginal:
            return .init(evidenceID: "completion-\(f.operation.id)", binding: binding(f), kind: kind,
                         originalByteCount: f.asset.byteCount, originalSHA256: f.asset.sha256,
                         platform: .init(task: task(f), finalizationID: "finalized-\(f.operation.id)"))
        }
    }
    private func termination(_ f: Fixture) -> AttachmentTerminationEvidence {
        .init(profileID: terminationProfile, evidenceID: "termination-\(f.operation.id)", binding: binding(f),
              task: task(f), retirementID: "retired-\(f.operation.id)")
    }
    private func continuation(_ f: Fixture) -> AttachmentContinuationEvidence {
        .init(version: 2, profileID: continuationProfile, evidenceID: "continuation-\(f.operation.id)",
              invocationID: f.invocation, binding: binding(f),
              taskIsolation: .init(task: task(f), ownershipID: "independent-\(f.operation.id)",
                                   startEvidenceID: "start-\(f.operation.id)", inputSequence: 1,
                                   callSettledSequence: 2, startSequence: 3, observedSequence: 4))
    }
    private func receipt(_ f: Fixture, outcome: ReceiptOutcome = .verifiedReady,
                         completion: AttachmentCompletionEvidence? = nil,
                         termination: AttachmentTerminationEvidence? = nil,
                         continuation: AttachmentContinuationEvidence? = nil,
                         error: Bool = false) -> TransferReceipt {
        .init(operationID: f.operation.id, assetID: f.asset.id, attempt: f.operation.attempt, assetSHA256: f.asset.sha256,
              target: f.operation.target, outcome: outcome, profileID: readyProfile,
              attachmentID: binding(f).attachmentID, positiveReady: outcome == .verifiedReady,
              belongsToOriginalDraft: true, hasError: error || outcome == .definitiveFailure,
              isUploading: outcome == .uploadStarted, safeToRetry: outcome == .definitiveFailure,
              uploadStartEvidence: outcome == .uploadStarted
                ? .init(profileID: startProfile, signal: .correlatedProgress, evidenceID: "start-\(f.operation.id)") : nil,
              continuationEvidence: continuation, completionEvidence: completion, terminationEvidence: termination)
    }
    private func changed<T: Codable>(_ value: T, _ mutate: (inout [String: Any]) -> Void) throws -> T {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        mutate(&json)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func reject(_ receipt: TransferReceipt, fixture: Fixture) async throws {
        do { _ = try await fixture.store.apply(receipt, policy: policy(platform: true)); XCTFail("Invalid original proof admitted") }
        catch RiftletError.mismatchedReceipt {}
    }

    func testExactByteAndPixelProofsAreSeparateAndRoundTrip() async throws {
        for kind in [AttachmentCompletionEvidence.Kind.exactOriginalBytes, .exactSRGBPixels] {
            let f = try await fixture(), proof = completion(f, kind: kind)
            let r = receipt(f, completion: proof)
            XCTAssertTrue(proof.validates(receipt: r, asset: f.asset))
            XCTAssertTrue(policy().allowsConsumption(receipt: r, asset: f.asset, mode: .production))
            XCTAssertEqual(try JSONDecoder().decode(TransferReceipt.self, from: JSONEncoder().encode(r)), r)
            let result = try await f.store.apply(r, policy: policy())
            XCTAssertEqual(result.status, .used)
        }
    }

    func testScaledPixelsWrongHashAndMixedProofKindsNeverComplete() async throws {
        let f = try await fixture(), exact = completion(f), pixels = completion(f, kind: .exactSRGBPixels)
        let invalid = try [changed(exact) { $0["observedSHA256"] = String(repeating: "b", count: 64) },
                           changed(exact) { $0["observedByteCount"] = 124 },
                           changed(exact) { $0["originalByteCount"] = 8 * 1024 * 1024 + 1 },
                           changed(exact) { $0["previewWidth"] = 4 },
                           changed(exact) { $0["version"] = 2 },
                           changed(pixels) { $0["previewWidth"] = 2; $0["previewHeight"] = 2 },
                           changed(pixels) { $0["previewPixelSHA256"] = String(repeating: "c", count: 64) },
                           changed(pixels) { $0["originalWidth"] = Int.max; $0["originalHeight"] = Int.max },
                           changed(pixels) { $0["observedSHA256"] = f.asset.sha256 }]
        for proof in invalid {
            let r = receipt(f, completion: proof)
            XCTAssertFalse(policy().allowsConsumption(receipt: r, asset: f.asset, mode: .production))
            try await reject(r, fixture: f)
        }
        let op = try await f.store.operation(id: f.operation.id); XCTAssertEqual(op?.phase, .dispatchIntent)
    }

    func testPlatformFinalizationNeedsIndependentAdmissionAndCandidateCannotConsume() async throws {
        let f = try await fixture(), proof = completion(f, kind: .platformFinalizedOriginal)
        let candidate = receipt(f, outcome: .attachedCandidate, completion: proof)
        XCTAssertTrue(proof.validates(receipt: candidate, asset: f.asset))
        XCTAssertFalse(policy(platform: true).allowsConsumption(receipt: candidate, asset: f.asset, mode: .production))
        let candidateResult = try await f.store.apply(candidate, policy: policy(platform: true))
        XCTAssertNotEqual(candidateResult.status, .used)
        let ready = receipt(f, completion: proof)
        XCTAssertFalse(policy().allowsConsumption(receipt: ready, asset: f.asset, mode: .production))
        let unknown = try await f.store.apply(ready, policy: policy()); XCTAssertEqual(unknown.status, .unknown)
        let used = try await f.store.apply(ready, policy: policy(platform: true)); XCTAssertEqual(used.status, .used)
    }

    func testSizeCapsAndUnknownSemanticCannotBeBypassedByConsistentMetadata() async throws {
        let f = try await fixture()
        let oversized = try changed(f.asset) { $0["byteCount"] = 8 * 1024 * 1024 + 1 }
        let tooManyBytes = try changed(completion(f)) {
            $0["originalByteCount"] = oversized.byteCount; $0["observedByteCount"] = oversized.byteCount
        }
        XCTAssertFalse(tooManyBytes.validates(receipt: receipt(f, completion: tooManyBytes), asset: oversized))
        let largePixels = try changed(f.asset) { $0["pixelWidth"] = 4097; $0["pixelHeight"] = 4096 }
        let tooManyPixels = try changed(completion(f, kind: .exactSRGBPixels)) {
            $0["originalWidth"] = 4097; $0["previewWidth"] = 4097
            $0["originalHeight"] = 4096; $0["previewHeight"] = 4096
        }
        XCTAssertFalse(tooManyPixels.validates(receipt: receipt(f, completion: tooManyPixels), asset: largePixels))
        XCTAssertThrowsError(try changed(completion(f)) { $0["kind"] = "progress100" })
        XCTAssertThrowsError(try changed(termination(f)) { $0["kind"] = "noCardVisible" })
        let absent = try changed(termination(f)) { $0["retirementID"] = "" }
        XCTAssertFalse(absent.validates(receipt: receipt(f, outcome: .definitiveFailure, termination: absent), asset: f.asset))
    }

    func testLegacyReceiptDecodesWithoutInventingNewEvidence() async throws {
        let f = try await fixture(), legacy = receipt(f)
        let decoded = try JSONDecoder().decode(TransferReceipt.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.completionEvidence); XCTAssertNil(decoded.terminationEvidence)
        XCTAssertNil(decoded.continuationEvidence)
        XCTAssertFalse(policy().allowsConsumption(receipt: decoded, asset: f.asset, mode: .production))
        XCTAssertTrue(ReceiptPolicy().platformCompletionProfiles.isEmpty)
        XCTAssertTrue(ReceiptPolicy().terminationProfiles.isEmpty)
        XCTAssertTrue(ReceiptPolicy().continuationProfiles.isEmpty)
    }

    func testNewProofMustMatchEveryOriginalBindingAndDispatchInvocation() async throws {
        let f = try await fixture(), original = completion(f)
        let changes: [(String, Any)] = [("operationID", UUID().uuidString), ("assetID", UUID().uuidString),
                                      ("attempt", 2), ("assetSHA256", String(repeating: "c", count: 64)),
                                      ("invocationID", UUID().uuidString), ("attachmentID", "other-attachment"), ("version", 2)]
        for (key, value) in changes {
            let bad = try changed(original) { json in
                var binding = json["binding"] as! [String: Any]; binding[key] = value; json["binding"] = binding
            }
            try await reject(receipt(f, completion: bad), fixture: f)
        }
        let targetMismatch = try changed(original) { json in
            var binding = json["binding"] as! [String: Any]
            var target = binding["target"] as! [String: Any]; target["clickBindingID"] = UUID().uuidString
            binding["target"] = target; json["binding"] = binding
        }
        try await reject(receipt(f, completion: targetMismatch), fixture: f)
    }

    func testLegacyMissingCallAndProoflessUnknownCannotBeUpgraded() async throws {
        let url = directory.appendingPathComponent("legacy.sqlite"), store = try QueueStore(databaseURL: url)
        let f = try await fixture(store: store)
        let sqlite = try SQLiteDatabase(url: url)
        try sqlite.execute("DELETE FROM checkpoints WHERE key=?", ["transfer-dispatch-call-v1:" + f.operation.id.uuidString])
        try await store.markUnknown(f.operation.id, reason: "legacy missing invocation")
        try await reject(receipt(f, completion: completion(f)), fixture: f)
        let result = try await store.apply(receipt(f), policy: policy())
        XCTAssertEqual(result.status, .unknown)
        let call = try await store.dispatchInvocationID(for: f.operation.id); XCTAssertNil(call)
    }

    func testRetirementNeedsIndependentProfileAndRevivesOnlyExactOriginal() async throws {
        let f = try await fixture()
        _ = try await f.store.apply(receipt(f, outcome: .uploadStarted), policy: policy())
        let noProof = try await f.store.apply(receipt(f, outcome: .definitiveFailure), policy: policy())
        XCTAssertEqual(noProof.status, .unknown); XCTAssertEqual(noProof.visibility, .swallowed)
        let failure = receipt(f, outcome: .definitiveFailure, termination: termination(f))
        let notAdmitted = try await f.store.apply(failure, policy: policy(retirement: false))
        XCTAssertEqual(notAdmitted.status, .unknown); XCTAssertEqual(notAdmitted.visibility, .swallowed)
        let revived = try await f.store.apply(failure, policy: policy())
        XCTAssertEqual(revived.status, .failed); XCTAssertEqual(revived.visibility, .visible)
        let retry = try await f.store.prepare(assetID: f.asset.id, target: target())
        XCTAssertNotEqual(retry.id, f.operation.id); XCTAssertEqual(retry.attempt, 2)
        try await reject(receipt(f, completion: completion(f)), fixture: f)
    }

    func testLateFailureCompensationCannotSwitchPlatformTask() async throws {
        let f = try await fixture(), proof = completion(f, kind: .platformFinalizedOriginal)
        _ = try await f.store.apply(receipt(f, completion: proof), policy: policy(platform: true))
        _ = try await f.store.apply(receipt(f, outcome: .unknown, error: true), policy: policy(platform: true))
        let compensation = try await f.store.compensation(for: f.operation.id)
        XCTAssertEqual(compensation?.originalSuccess.completionEvidence, proof)
        let different = try changed(termination(f)) { json in
            var task = json["task"] as! [String: Any]; task["taskID"] = "other-task"; json["task"] = task
        }
        try await reject(receipt(f, outcome: .definitiveFailure, termination: different), fixture: f)
        let restored = try await f.store.apply(receipt(f, outcome: .definitiveFailure, termination: termination(f)), policy: policy())
        XCTAssertEqual(restored.status, .failed); XCTAssertEqual(restored.visibility, .visible)
        let retained = try await f.store.compensation(for: f.operation.id)
        XCTAssertEqual(retained?.originalSuccess, compensation?.originalSuccess)
    }

    func testContinuationV2RequiresSettledOriginalCallBeforeNewPinDispatch() async throws {
        let f = try await fixture(), start = receipt(f, outcome: .uploadStarted, continuation: continuation(f))
        _ = try await f.store.apply(start, policy: policy())
        let b = try await newAsset(f.store), targetB = target()
        let opB = try await f.store.prepare(assetID: b.id, target: targetB)
        do {
            _ = try await f.store.markDispatchIntent(opB.id, selection: selection(b, target: targetB), ownerID: f.owner, policy: policy())
            XCTFail("append has not returned")
        } catch RiftletError.targetBusy {}
        try await f.store.recordAppendReturned(start, invocationID: f.invocation, ownerID: f.owner)
        let nonceB = try await f.store.markDispatchIntent(opB.id, selection: selection(b, target: targetB), ownerID: f.owner, policy: policy())
        let following = Fixture(store: f.store, asset: b, operation: opB, invocation: nonceB, owner: f.owner)
        let result = try await f.store.apply(receipt(following, outcome: .uploadStarted, continuation: continuation(following)), policy: policy())
        XCTAssertEqual(result.visibility, .swallowed)
    }

    func testSnapshotOnlyLegacyOrWrongSequenceCannotGrantRealContinuation() async throws {
        let f = try await fixture(), correct = continuation(f)
        let legacy = AttachmentContinuationEvidence(profileID: continuationProfile, evidenceID: "legacy", invocationID: f.invocation)
        var invalid = [legacy, try changed(correct) { $0.removeValue(forKey: "taskIsolation") }]
        for (key, value) in [("callSettledSequence", 1), ("startSequence", 1), ("observedSequence", 1)] {
            invalid.append(try changed(correct) { json in
                var isolation = json["taskIsolation"] as! [String: Any]; isolation[key] = value; json["taskIsolation"] = isolation
            })
        }
        invalid.append(try changed(correct) { json in
            var isolation = json["taskIsolation"] as! [String: Any]; isolation["startEvidenceID"] = "another-start"; json["taskIsolation"] = isolation
        })
        for proof in invalid {
            let r = receipt(f, outcome: .uploadStarted, continuation: proof)
            XCTAssertFalse(policy().allowsContinuation(receipt: r, asset: f.asset, mode: .production))
        }
        let valid = receipt(f, outcome: .uploadStarted, continuation: correct)
        XCTAssertTrue(policy().allowsContinuation(receipt: valid, asset: f.asset, mode: .production))
        XCTAssertFalse(ReceiptPolicy().allowsContinuation(receipt: valid, asset: f.asset, mode: .production))
    }

    func testRestartCompletesOriginalWithoutInheritingContinuationOwner() async throws {
        let url = directory.appendingPathComponent("restart.sqlite"), db = try QueueStore(databaseURL: url)
        let f = try await fixture(store: db), start = receipt(f, outcome: .uploadStarted, continuation: continuation(f))
        _ = try await db.apply(start, policy: policy())
        try await db.recordAppendReturned(start, invocationID: f.invocation, ownerID: f.owner)
        let reopened = try QueueStore(databaseURL: url); try await reopened.recoverInterruptedOperations()
        let b = try await newAsset(reopened), tb = target(), bo = try await reopened.prepare(assetID: b.id, target: tb)
        do {
            _ = try await reopened.markDispatchIntent(bo.id, selection: selection(b, target: tb), ownerID: UUID(), policy: policy())
            XCTFail("restarted owner inherited continuation")
        } catch RiftletError.targetBusy {}
        let completed = try await reopened.apply(receipt(f, completion: completion(f)), policy: policy())
        XCTAssertEqual(completed.status, .used)
        let original = try await reopened.uploadStartReceipt(for: f.operation.id); XCTAssertEqual(original, start)
    }

    func testLateIsolationNeverBackfillsFirstStartOrAppendReturn() async throws {
        let f = try await fixture(), original = receipt(f, outcome: .uploadStarted)
        _ = try await f.store.apply(original, policy: policy())
        try await f.store.recordAppendReturned(original, invocationID: f.invocation, ownerID: f.owner)
        let later = receipt(f, outcome: .uploadStarted, continuation: continuation(f))
        _ = try await f.store.apply(later, policy: policy())
        let retained = try await f.store.uploadStartReceipt(for: f.operation.id); XCTAssertEqual(retained, original)
        do { try await f.store.recordAppendReturned(later, invocationID: f.invocation, ownerID: f.owner); XCTFail("old return changed") }
        catch RiftletError.invalidTransition {}
        let b = try await newAsset(f.store), tb = target(), bo = try await f.store.prepare(assetID: b.id, target: tb)
        do {
            _ = try await f.store.markDispatchIntent(bo.id, selection: selection(b, target: tb), ownerID: f.owner, policy: policy())
            XCTFail("late isolation upgraded original click")
        } catch RiftletError.targetBusy {}
    }

    func testImmutablePlatformTaskSurvivesProoflessUnknownAndCannotBeReplaced() async throws {
        let url = directory.appendingPathComponent("immutable-platform.sqlite")
        let f = try await fixture(store: QueueStore(databaseURL: url)), original = completion(f, kind: .platformFinalizedOriginal)
        _ = try await f.store.apply(receipt(f, outcome: .uploadStarted, continuation: continuation(f)), policy: policy())
        let key = "transfer-platform-task-v1:" + f.operation.id.uuidString
        let stored = try await f.store.checkpoint(for: key); XCTAssertNotNil(stored)
        _ = try await f.store.apply(receipt(f, outcome: .unknown), policy: policy())
        let reopened = try QueueStore(databaseURL: url)
        try await reopened.recoverInterruptedOperations()
        let afterRestart = Fixture(store: reopened, asset: f.asset, operation: f.operation,
                                   invocation: f.invocation, owner: f.owner)
        let wrong = try changed(original) { json in
            var platform = json["platform"] as! [String: Any], task = platform["task"] as! [String: Any]
            task["taskID"] = "replacement"; platform["task"] = task; json["platform"] = platform
        }
        try await reject(receipt(f, completion: wrong), fixture: afterRestart)
        let unchanged = try await reopened.checkpoint(for: key); XCTAssertEqual(unchanged, stored)
    }

    func testUnadmittedCandidateCannotPoisonOriginalOrReserveAnotherOperationsTask() async throws {
        let f = try await fixture(), b = try await newAsset(f.store), tb = target()
        let bo = try await f.store.prepare(assetID: b.id, target: tb)
        let provisionalB = Fixture(store: f.store, asset: b, operation: bo, invocation: UUID(), owner: f.owner)
        let allegedTask = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task(provisionalB)))
        let alleged = try changed(completion(f, kind: .platformFinalizedOriginal)) { json in
            var platform = json["platform"] as! [String: Any]
            platform["task"] = allegedTask
            json["platform"] = platform
        }
        _ = try await f.store.apply(receipt(f, outcome: .attachedCandidate, completion: alleged), policy: policy())
        let notOwned = try await f.store.checkpoint(for: "transfer-platform-task-v1:" + f.operation.id.uuidString)
        XCTAssertNil(notOwned)
        let originalStart = receipt(f, outcome: .uploadStarted, continuation: continuation(f))
        _ = try await f.store.apply(originalStart, policy: policy())
        try await f.store.recordAppendReturned(originalStart, invocationID: f.invocation, ownerID: f.owner)
        let bn = try await f.store.markDispatchIntent(bo.id, selection: selection(b, target: tb), ownerID: f.owner, policy: policy())
        let following = Fixture(store: f.store, asset: b, operation: bo, invocation: bn, owner: f.owner)
        let accepted = try await f.store.apply(receipt(following, outcome: .uploadStarted, continuation: continuation(following)), policy: policy())
        XCTAssertEqual(accepted.visibility, .swallowed)
    }

    func testPlatformRequestTaskAndAttachmentCannotAliasAcrossPins() async throws {
        for field in ["requestID", "taskID", "attachmentReference"] {
            let f = try await fixture(), start = receipt(f, outcome: .uploadStarted, continuation: continuation(f))
            _ = try await f.store.apply(start, policy: policy())
            try await f.store.recordAppendReturned(start, invocationID: f.invocation, ownerID: f.owner)
            let b = try await fixture(store: f.store, owner: f.owner)
            let originalTask = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task(f))) as? [String: Any])
            let aliased = try changed(continuation(b)) { json in
                var isolation = json["taskIsolation"] as! [String: Any], task = isolation["task"] as! [String: Any]
                task[field] = originalTask[field]; isolation["task"] = task; json["taskIsolation"] = isolation
            }
            try await reject(receipt(b, outcome: .uploadStarted, continuation: aliased), fixture: b)
            let checkpoint = try await b.store.checkpoint(for: "transfer-platform-task-v1:" + b.operation.id.uuidString)
            XCTAssertNil(checkpoint, "Rejected alias must roll back its first-task checkpoint")
        }
    }

    func testAdmittedStartDoesNotPromoteUnadmittedContinuationTaskIntoOwnership() async throws {
        let f = try await fixture(), b = try await newAsset(f.store), tb = target()
        let bo = try await f.store.prepare(assetID: b.id, target: tb)
        let provisionalB = Fixture(store: f.store, asset: b, operation: bo, invocation: UUID(), owner: f.owner)
        let allegedTask = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task(provisionalB)))
        let unadmittedIsolation = try changed(continuation(f)) { json in
            var isolation = json["taskIsolation"] as! [String: Any]
            isolation["task"] = allegedTask; json["taskIsolation"] = isolation
        }
        // A's positive START is independently admitted, but the continuation
        // semantics are not. Preserve A's real attachment ownership only.
        let startOnly = ReceiptPolicy(admittedProfiles: [readyProfile: .webChat],
            uploadStartProfiles: [startProfile: .webChat],
            requiredCompletionEvidenceProfiles: [readyProfile])
        let started = try await f.store.apply(receipt(f, outcome: .uploadStarted, continuation: unadmittedIsolation), policy: startOnly)
        XCTAssertEqual(started.visibility, .swallowed)
        let noPlatformOwnership = try await f.store.checkpoint(for: "transfer-platform-task-v1:" + f.operation.id.uuidString)
        XCTAssertNil(noPlatformOwnership)
        _ = try await f.store.apply(receipt(f, completion: completion(f)), policy: startOnly)
        let bn = try await f.store.markDispatchIntent(bo.id, selection: selection(b, target: tb), ownerID: f.owner, policy: policy())
        let following = Fixture(store: f.store, asset: b, operation: bo, invocation: bn, owner: f.owner)
        let accepted = try await f.store.apply(receipt(following, outcome: .uploadStarted, continuation: continuation(following)), policy: policy())
        XCTAssertEqual(accepted.visibility, .swallowed)
        let bPlatformOwnership = try await f.store.checkpoint(for: "transfer-platform-task-v1:" + bo.id.uuidString)
        XCTAssertNotNil(bPlatformOwnership)
    }

    func testLaterPolicyCannotRetroactivelyAdmitOriginalUnqualifiedStart() async throws {
        let f = try await fixture(), original = receipt(f, outcome: .uploadStarted, continuation: continuation(f))
        let startOnly = ReceiptPolicy(uploadStartProfiles: [startProfile: .webChat])
        _ = try await f.store.apply(original, policy: startOnly)
        try await f.store.recordAppendReturned(original, invocationID: f.invocation, ownerID: f.owner)
        // Even replaying this same observation under a later, broader policy is
        // observation only; it cannot qualify the already stored first START.
        _ = try await f.store.apply(original, policy: policy())
        let b = try await newAsset(f.store), tb = target(), bo = try await f.store.prepare(assetID: b.id, target: tb)
        do {
            _ = try await f.store.markDispatchIntent(bo.id, selection: selection(b, target: tb), ownerID: f.owner, policy: policy())
            XCTFail("New policy promoted the old unqualified START")
        } catch RiftletError.targetBusy {}
        let originalTask = try await f.store.checkpoint(for: "transfer-platform-task-v1:" + f.operation.id.uuidString)
        XCTAssertNil(originalTask)
        let preserved = try await f.store.uploadStartReceipt(for: f.operation.id)
        XCTAssertEqual(preserved, original)
    }
}
