import Foundation
import XCTest
@testable import RiftletCore

final class DispatchLifecycleTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dispatch-lifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func store() throws -> QueueStore { try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite")) }
    private func target(_ draft: String = "00000000-0000-0000-0000-000000000001", epoch: String = "1",
                        pin: UUID? = nil) -> TargetLease {
        TargetLease(adapterID: "lifecycle-fixture", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "fixture-process", windowID: "1", tabID: "1", documentID: "doc", composerID: "composer",
            draftGeneration: epoch, logicalDraftIdentity: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1", id: draft),
            clickBindingID: pin)
    }
    private func changed(_ target: TargetLease, _ field: String, _ value: Any) throws -> TargetLease {
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as? [String: Any])
        fields[field] = value
        return try JSONDecoder().decode(TargetLease.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private var policy: ReceiptPolicy {
        .init(syntheticAcceptanceProfiles: ["fixture-ready": .webChat],
              syntheticUploadStartProfiles: ["fixture-start": .webChat],
              syntheticContinuationProfiles: ["fixture-independent": .webChat])
    }
    private func asset(_ db: QueueStore) async throws -> ImportedAsset {
        let id = UUID(), bytes = Data("local fixture".utf8)
        let a = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1,
            mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: directory.appendingPathComponent(a.fileName)); _ = try await db.importAsset(a); return a
    }
    private func selection(_ a: ImportedAsset, target: TargetLease) -> AcceptedSelection {
        let now = ProcessInfo.processInfo.systemUptime
        let pinned = target.clickBindingID != nil
        return .init(assetID: a.id, target: target, hostEpoch: UUID(), acknowledgedUptime: now - (pinned ? 0.005 : 0.02),
            eventUptime: now - 0.01, acceptedUptime: now, visibilityRevision: 0, deadlineUptime: now + 30,
            authorization: pinned ? .nativeClickPin : .preEventAcknowledgement)
    }
    private func receipt(_ op: TransferOperation, _ a: ImportedAsset, _ nonce: UUID,
                         outcome: ReceiptOutcome = .uploadStarted, continuation: Bool = true,
                         attachment: String? = nil, target: TargetLease? = nil) -> TransferReceipt {
        .init(operationID: op.id, assetID: a.id, attempt: op.attempt, assetSHA256: a.sha256, target: target ?? op.target,
            outcome: outcome, profileID: "fixture-ready", attachmentID: attachment ?? "attachment-\(op.id)",
            positiveReady: outcome == .verifiedReady, belongsToOriginalDraft: true,
            hasError: outcome == .definitiveFailure, isUploading: outcome == .uploadStarted,
            uploadStartEvidence: outcome == .uploadStarted ? .init(profileID: "fixture-start", signal: .correlatedProgress, evidenceID: "start-\(op.id)") : nil,
            continuationEvidence: continuation && outcome == .uploadStarted ? .init(profileID: "fixture-independent", evidenceID: "isolation-\(op.id)", invocationID: nonce) : nil)
    }
    private func started(_ db: QueueStore, owner: UUID, continuation: Bool = true, returned: Bool = true,
                         target selected: TargetLease? = nil) async throws -> (ImportedAsset, TransferOperation, UUID) {
        let a = try await asset(db), t = selected ?? target()
        let op = try await db.prepare(assetID: a.id, target: t)
        let nonce = try await db.markDispatchIntent(op.id, ownerID: owner)
        let r = receipt(op, a, nonce, continuation: continuation)
        _ = try await db.apply(r, policy: policy)
        if returned { try await db.recordAppendReturned(r, invocationID: nonce, ownerID: owner) }
        try await db.markUnknown(op.id, reason: "fixture only")
        return (a, op, nonce)
    }
    private func expectBusy(_ db: QueueStore, owner: UUID, t: TargetLease? = nil, p: ReceiptPolicy? = nil) async throws {
        let a = try await asset(db), target = t ?? target()
        let b = try await db.prepare(assetID: a.id, target: target)
        do { try await db.markDispatchIntent(b.id, selection: selection(a, target: target), ownerID: owner, policy: p ?? policy); XCTFail("must retain original conflict") }
        catch RiftletError.targetBusy {}
    }

    func testFortyEightIndependentStartedOperationsRetainOriginalIdentities() async throws {
        let db = try store(), owner = UUID(), t = target()
        var ids = Set<UUID>(), attachments = Set<String>()
        for _ in 0..<48 {
            let a = try await asset(db), op = try await db.prepare(assetID: a.id, target: t)
            let nonce = try await db.markIndependentFileInputIntent(op.id, selection: selection(a, target: t), ownerID: owner)
            let r = receipt(op, a, nonce); _ = try await db.apply(r, policy: policy)
            try await db.recordAppendReturned(r, invocationID: nonce, ownerID: owner)
            try await db.markUnknown(op.id, reason: "independently observed fixture remains pending")
            ids.insert(op.id); attachments.insert(r.attachmentID!)
        }
        let unresolved = try await db.unresolvedOperations()
        XCTAssertEqual(ids.count, 48); XCTAssertEqual(attachments.count, 48); XCTAssertEqual(unresolved.count, 48)
        for op in unresolved { let start = try await db.uploadStartReceipt(for: op.id); XCTAssertNotNil(start); XCTAssertEqual(op.phase, .unknown) }
    }

    func testDistinctNativePinsContinueWithoutChangingOriginalReceiptIdentity() async throws {
        let db = try store(), owner = UUID(), at = target(pin: UUID()), bt = target(pin: UUID())
        let (a, ao, an) = try await started(db, owner: owner, target: at)
        let b = try await asset(db), bo = try await db.prepare(assetID: b.id, target: bt)
        let click = selection(b, target: bt)
        let bn = try await db.markIndependentFileInputIntent(bo.id, selection: click, ownerID: owner)
        let br = receipt(bo, b, bn)
        _ = try await db.apply(br, policy: policy)
        try await db.recordAppendReturned(br, invocationID: bn, ownerID: owner)
        XCTAssertNotEqual(at, bt); XCTAssertNotEqual(at.stableKey, bt.stableKey)
        let originalA = try await db.uploadStartReceipt(for: ao.id), originalB = try await db.uploadStartReceipt(for: bo.id)
        XCTAssertEqual(originalA?.target, at); XCTAssertEqual(originalB?.target, bt)
        XCTAssertNotEqual(originalA?.attachmentID, originalB?.attachmentID)

        // A sibling pin is a different capability even inside the same scope.
        do {
            _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady, target: bt), policy: policy)
            XCTFail("Sibling pin admitted for the original operation")
        } catch RiftletError.mismatchedReceipt {}
        do {
            _ = try await db.markIndependentFileInputIntent(bo.id, selection: click, ownerID: owner)
            XCTFail("Dispatched click replayed")
        } catch RiftletError.invalidTransition {}
        let retainedA = try await db.prepare(assetID: a.id, target: target(pin: UUID()))
        XCTAssertEqual(retainedA.id, ao.id); XCTAssertEqual(retainedA.target, at)

        _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady), policy: policy)
        _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy)
        _ = try await db.apply(receipt(ao, a, an, outcome: .definitiveFailure), policy: policy)
        let finalA = try await db.operation(id: ao.id), finalB = try await db.operation(id: bo.id)
        XCTAssertEqual(finalA?.phase, .compensated); XCTAssertEqual(finalB?.phase, .succeeded)
        XCTAssertEqual(finalB?.target, bt)
        // A's later compensated result cannot revoke its already-established
        // independent input ownership or block a different screenshot C.
        let c = try await asset(db), ct = target(pin: UUID())
        let co = try await db.prepare(assetID: c.id, target: ct)
        _ = try await db.markIndependentFileInputIntent(co.id, selection: selection(c, target: ct), ownerID: owner)
    }

    func testContinuationScopeRequiresExactObservedDraftAndDoesNotPromoteLegacyPins() throws {
        let a = target(pin: UUID()), b = target(pin: UUID())
        XCTAssertTrue(a.sharesContinuationDraft(with: b))
        XCTAssertFalse(a.sharesContinuationDraft(with: target()))
        XCTAssertFalse(target().sharesContinuationDraft(with: a))
        XCTAssertTrue(target().sharesContinuationDraft(with: target()))
        let mutations: [(String, Any)] = [
            ("adapterID", "other"), ("adapterID", ""), ("surface", "webWork"),
            ("applicationID", "other.browser"), ("sessionID", "other-process"), ("sessionID", ""),
            ("windowID", "2"), ("windowID", ""), ("tabID", "2"), ("tabID", ""), ("tabID", NSNull()),
            ("documentID", "new-document"), ("documentID", ""), ("composerID", "new-composer"), ("composerID", ""),
            ("draftGeneration", "2"), ("draftGeneration", ""), ("logicalDraftIdentity", NSNull()),
            ("logicalDraftIdentity", ["profileID": "unknown-profile", "id": "00000000-0000-0000-0000-000000000001"]),
            ("logicalDraftIdentity", ["profileID": "chatgpt-composer-react-persisted-20261027-v1", "id": "invalid"]),
            ("logicalDraftIdentity", ["profileID": "chatgpt-composer-react-persisted-20261027-v1", "id": "00000000-0000-0000-0000-000000000002"]),
            ("logicalDraftIdentity", ["profileID": "chatgpt-composer-react-20261027-v1", "id": "local-chatgpt:00000000-0000-0000-0000-000000000001"])
        ]
        for (field, value) in mutations {
            let changedTarget = try changed(b, field, value)
            XCTAssertFalse(a.sharesContinuationDraft(with: changedTarget), field)
            XCTAssertFalse(changedTarget.sharesContinuationDraft(with: a), field)
        }
        // Equality alone must never authorize a malformed/unrecognized scope.
        for field in ["sessionID", "windowID", "tabID", "documentID", "composerID", "draftGeneration"] {
            let empty = try changed(a, field, "")
            XCTAssertFalse(empty.sharesContinuationDraft(with: empty), field)
        }
        let local = try changed(a, "logicalDraftIdentity", ["profileID": "chatgpt-composer-react-20261027-v1", "id": "local-chatgpt:00000000-0000-0000-0000-000000000001"])
        XCTAssertTrue(local.sharesContinuationDraft(with: try changed(local, "clickBindingID", UUID().uuidString)))
    }

    func testNativePinCannotCrossNavigationComposerEpochOrMissingBusinessIdentity() async throws {
        let db = try store(), owner = UUID(), a = target(pin: UUID())
        _ = try await started(db, owner: owner, target: a)
        for (field, value) in [("documentID", "navigated"), ("composerID", "replaced"), ("draftGeneration", "2"), ("windowID", "moved")] {
            let next = try changed(target(pin: UUID()), field, value)
            try await expectBusy(db, owner: owner, t: next)
        }
        try await expectBusy(db, owner: owner, t: try changed(target(pin: UUID()), "logicalDraftIdentity", NSNull()))
        try await expectBusy(db, owner: owner, t: target())
        // Returning to the old business ID with a later epoch is not continuity.
        try await expectBusy(db, owner: owner, t: target(epoch: "after-A-B-A", pin: UUID()))
    }

    func testNativePinFollowingStillRequiresAppendReturnProofAndLiveOwner() async throws {
        for failure in ["unreturned", "no-continuation", "owner", "restarted", "profile"] {
            let db = try QueueStore(databaseURL: directory.appendingPathComponent(failure + ".sqlite"))
            let owner = UUID()
            _ = try await started(db, owner: owner, continuation: failure != "no-continuation",
                                  returned: failure != "unreturned", target: target(pin: UUID()))
            if failure == "restarted" { try await db.recoverInterruptedOperations() }
            try await expectBusy(db, owner: failure == "owner" || failure == "restarted" ? UUID() : owner,
                                 t: target(pin: UUID()),
                                 p: failure == "profile" ? .init(syntheticUploadStartProfiles: ["fixture-start": .webChat]) : policy)
        }
        let db = try store(), owner = UUID(), a = try await asset(db), at = target(pin: UUID())
        let ao = try await db.prepare(assetID: a.id, target: at)
        _ = try await db.markDispatchIntent(ao.id, selection: selection(a, target: at), ownerID: owner, policy: policy)
        try await db.markUnknown(ao.id, reason: "Commit reply lost; no proven start")
        try await expectBusy(db, owner: owner, t: target(pin: UUID()))
    }

    func testCrossPinAttachmentAliasIsRejectedBeforeAndAfterOriginalCompletion() async throws {
        for completed in [false, true] {
            let db = try QueueStore(databaseURL: directory.appendingPathComponent("alias-\(completed).sqlite")), owner = UUID()
            let (a, ao, an) = try await started(db, owner: owner, target: target(pin: UUID()))
            if completed { _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy) }
            let bt = target(pin: UUID()), b = try await asset(db), bo = try await db.prepare(assetID: b.id, target: bt)
            let bn = try await db.markIndependentFileInputIntent(bo.id, selection: selection(b, target: bt), ownerID: owner)
            for outcome in [ReceiptOutcome.uploadStarted, .verifiedReady] {
                do {
                    _ = try await db.apply(receipt(bo, b, bn, outcome: outcome, attachment: "attachment-\(ao.id)"), policy: policy)
                    XCTFail("Original A attachment reused by another native pin")
                } catch RiftletError.mismatchedReceipt {}
            }
            let rejected = try await db.uploadStartReceipt(for: bo.id), bBefore = try await db.operation(id: bo.id)
            XCTAssertNil(rejected); XCTAssertEqual(bBefore?.phase, .dispatchIntent)
            _ = try await db.apply(receipt(bo, b, bn), policy: policy)
            _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady), policy: policy)
            let bAfter = try await db.operation(id: bo.id); XCTAssertEqual(bAfter?.phase, .succeeded)
            let aAfter = try await db.operation(id: ao.id)
            XCTAssertEqual(aAfter?.phase, completed ? .succeeded : .unknown)
        }
    }

    func testCompletedAttachmentIdentityDoesNotAliasAnUnrelatedBusinessDraft() async throws {
        let db = try store(), owner = UUID()
        let (a, ao, an) = try await started(db, owner: owner, target: target(pin: UUID()))
        _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy)
        let bt = try changed(target("00000000-0000-0000-0000-000000000002", pin: UUID()),
                             "documentID", "independent-document")
        let b = try await asset(db), bo = try await db.prepare(assetID: b.id, target: bt)
        let bn = try await db.markDispatchIntent(bo.id, selection: selection(b, target: bt), ownerID: owner, policy: policy)
        _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady, attachment: "attachment-\(ao.id)"), policy: policy)
        let result = try await db.operation(id: bo.id)
        XCTAssertEqual(result?.phase, .succeeded); XCTAssertEqual(result?.target, bt)
    }

    func testRenewedDocumentInSameBusinessDraftCannotBorrowACompletedAttachment() async throws {
        let db = try store(), owner = UUID()
        let (a, ao, an) = try await started(db, owner: owner, target: target(pin: UUID()))
        _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy)
        let bt = try changed(target(pin: UUID()), "documentID", "renewed-same-chat-document")
        let b = try await asset(db), bo = try await db.prepare(assetID: b.id, target: bt)
        let bn = try await db.markDispatchIntent(bo.id, selection: selection(b, target: bt), ownerID: owner, policy: policy)
        do {
            _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady,
                attachment: "attachment-\(ao.id)"), policy: policy)
            XCTFail("A new document identifier is not permission to borrow A's attachment")
        } catch RiftletError.mismatchedReceipt {}
        let bReceipt = try await db.receipt(for: bo.id)
        let original = try await db.operation(id: ao.id)
        XCTAssertNil(bReceipt); XCTAssertEqual(original?.phase, .succeeded)
    }

    func testCompletionOnlyAttachmentOwnershipSurvivesCompensationWithoutInventingStart() async throws {
        for compensated in [false, true] {
            let db = try QueueStore(databaseURL: directory.appendingPathComponent("completion-only-\(compensated).sqlite")), owner = UUID()
            let a = try await asset(db), at = target(pin: UUID()), ao = try await db.prepare(assetID: a.id, target: at)
            let an = try await db.markDispatchIntent(ao.id, selection: selection(a, target: at), ownerID: owner, policy: policy)
            _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy)
            let noStart = try await db.uploadStartReceipt(for: ao.id); XCTAssertNil(noStart)

            let b = try await asset(db), bt = target(pin: UUID()), bo = try await db.prepare(assetID: b.id, target: bt)
            let bn = try await db.markDispatchIntent(bo.id, selection: selection(b, target: bt), ownerID: owner, policy: policy)
            // A late failure may arrive after B's already-authorized dispatch.
            if compensated { _ = try await db.apply(receipt(ao, a, an, outcome: .definitiveFailure), policy: policy) }
            for outcome in [ReceiptOutcome.uploadStarted, .verifiedReady] {
                do {
                    _ = try await db.apply(receipt(bo, b, bn, outcome: outcome, attachment: "attachment-\(ao.id)"), policy: policy)
                    XCTFail("Completion-only A's original attachment reused")
                } catch RiftletError.mismatchedReceipt {}
            }
            let beforeB = try await db.operation(id: bo.id); XCTAssertEqual(beforeB?.phase, .dispatchIntent)
            _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady), policy: policy)
            let finalA = try await db.operation(id: ao.id), finalB = try await db.operation(id: bo.id)
            XCTAssertEqual(finalA?.phase, compensated ? .compensated : .succeeded)
            XCTAssertEqual(finalB?.phase, .succeeded)
            let stillNoStart = try await db.uploadStartReceipt(for: ao.id); XCTAssertNil(stillNoStart)
            if compensated {
                let audit = try await db.compensation(for: ao.id)
                XCTAssertEqual(audit?.originalSuccess, receipt(ao, a, an, outcome: .verifiedReady))
            }
        }
    }

    func testLegacyUnadmittedObservationCannotMintAttachmentOwnership() async throws {
        let db = try store(), owner = UUID(), b = try await asset(db), bt = target(pin: UUID())
        let bo = try await db.prepare(assetID: b.id, target: bt)
        let bn = try await db.markDispatchIntent(bo.id, selection: selection(b, target: bt), ownerID: owner, policy: policy)

        let a = try await asset(db), at = target(pin: UUID()), ao = try await db.prepare(assetID: a.id, target: at)
        // Isolated legacy overlapping operation fixture, never a current user
        // row. B already owns its dispatch; no new input is granted over UNKNOWN.
        let legacy = try SQLiteDatabase(url: directory.appendingPathComponent("queue.sqlite"))
        try legacy.execute("UPDATE operations SET phase='unknown' WHERE id=?", [ao.id.uuidString])
        let allegedAttachment = "unadmitted-attachment"
        _ = try await db.apply(receipt(ao, a, UUID(), outcome: .verifiedReady, attachment: allegedAttachment), policy: .init())
        let oldState = try await db.operation(id: ao.id); XCTAssertEqual(oldState?.phase, .unknown)
        _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady, attachment: allegedAttachment), policy: policy)
        let finalB = try await db.operation(id: bo.id); XCTAssertEqual(finalB?.phase, .succeeded)
        let noStart = try await db.uploadStartReceipt(for: ao.id); XCTAssertNil(noStart)
        try await expectBusy(db, owner: owner, t: target(pin: UUID()))
    }

    func testAttachmentOwnershipSearchDoesNotTruncateAtMetadataBatchBoundary() async throws {
        let db = try store(), owner = UUID()
        // Terminal records outside this draft fill one metadata batch. Their
        // payloads need not be decoded, but a later matching owner is not lost.
        for index in 0..<64 {
            let t = try changed(target(pin: UUID()), "documentID", "unrelated-\(index)")
            let a = try await asset(db), op = try await db.prepare(assetID: a.id, target: t)
            let nonce = try await db.markDispatchIntent(op.id, selection: selection(a, target: t), ownerID: owner, policy: policy)
            _ = try await db.apply(receipt(op, a, nonce, outcome: .verifiedReady), policy: policy)
        }
        let a = try await asset(db), at = target(pin: UUID()), ao = try await db.prepare(assetID: a.id, target: at)
        let an = try await db.markDispatchIntent(ao.id, selection: selection(a, target: at), ownerID: owner, policy: policy)
        _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy)
        let b = try await asset(db), bt = target(pin: UUID()), bo = try await db.prepare(assetID: b.id, target: bt)
        let bn = try await db.markDispatchIntent(bo.id, selection: selection(b, target: bt), ownerID: owner, policy: policy)
        do {
            _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady, attachment: "attachment-\(ao.id)"), policy: policy)
            XCTFail("Alias beyond first metadata batch admitted")
        } catch RiftletError.mismatchedReceipt {}
        _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady), policy: policy)
        let finalB = try await db.operation(id: bo.id); XCTAssertEqual(finalB?.phase, .succeeded)
    }

    func testContinuationCannotBorrowAnotherInvocationWithDistinctPins() async throws {
        let db = try store(), owner = UUID(), at = target(pin: UUID()), a = try await asset(db)
        let ao = try await db.prepare(assetID: a.id, target: at)
        let actual = try await db.markDispatchIntent(ao.id, selection: selection(a, target: at), ownerID: owner, policy: policy)
        let wrongInvocation = receipt(ao, a, UUID())
        _ = try await db.apply(wrongInvocation, policy: policy)
        try await db.recordAppendReturned(wrongInvocation, invocationID: actual, ownerID: owner)
        try await expectBusy(db, owner: owner, t: target(pin: UUID()))
    }

    func testStartAloneAndAppendStillRunningCannotReleaseConflict() async throws {
        let db = try store(), owner = UUID(); _ = try await started(db, owner: owner, returned: false)
        try await expectBusy(db, owner: owner)
    }
    func testNoIndependentProfileAndWrongOwnerAndNewEpochRemainLocked() async throws {
        let db = try store(), owner = UUID(); _ = try await started(db, owner: owner)
        try await expectBusy(db, owner: UUID()) // restarted coordinator cannot inherit authority
        try await expectBusy(db, owner: owner, t: target(epoch: "2"))
        try await expectBusy(db, owner: owner, p: .init(syntheticUploadStartProfiles: ["fixture-start": .webChat]))
    }
    func testNoContinuationEvidenceRemainsLocked() async throws {
        let db = try store(), owner = UUID(); _ = try await started(db, owner: owner, continuation: false)
        try await expectBusy(db, owner: owner)
    }
    func testUnownedInvocationAndUnknownCommitRemainLocked() async throws {
        let db = try store(), owner = UUID(), a = try await asset(db)
        let op = try await db.prepare(assetID: a.id, target: target())
        _ = try await db.markDispatchIntent(op.id) // no continuing runtime owner, no start
        try await db.markUnknown(op.id, reason: "commit reply lost")
        try await expectBusy(db, owner: owner)
        try await db.recoverInterruptedOperations()
        try await expectBusy(db, owner: UUID())
    }
    func testLegacyV3OperationWithoutCallCheckpointStaysLocked() async throws {
        let db = try store(), a = try await asset(db)
        let op = try await db.prepare(assetID: a.id, target: target())
        // Construct an isolated historical v3 row without calling the new intent
        // writer. No current or user operation/checkpoint is removed.
        let legacy = try SQLiteDatabase(url: directory.appendingPathComponent("queue.sqlite"))
        try legacy.execute("UPDATE operations SET phase='unknown' WHERE id=?", [op.id.uuidString])
        try legacy.execute("UPDATE assets SET status='unknown' WHERE id=?", [a.id.uuidString])
        let nonce = try await db.dispatchInvocationID(for: op.id); XCTAssertNil(nonce)
        try await expectBusy(db, owner: UUID())
        try await db.recoverInterruptedOperations()
        let after = try await db.dispatchInvocationID(for: op.id); XCTAssertNil(after)
    }

    func testTwoConnectionsCannotDispatchTheSameOperationTwice() async throws {
        let db = try store(), second = try store(), owner = UUID()
        let image = try await asset(db), t = target(pin: UUID())
        let op = try await db.prepare(assetID: image.id, target: t)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { do { try await db.markIndependentFileInputIntent(op.id, ownerID: owner); return true } catch { return false } }
            group.addTask { do { try await second.markIndependentFileInputIntent(op.id, ownerID: owner); return true } catch { return false } }
            var all: [Bool] = []; for await result in group { all.append(result) }; return all
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let recorded = try await db.dispatchInvocationID(for: op.id); XCTAssertNotNil(recorded)
    }

    func testLateACompensationDoesNotReassignBOrBlockIndependentNextInput() async throws {
        let db = try store(), owner = UUID(); let (a, ao, an) = try await started(db, owner: owner)
        let b = try await asset(db), bo = try await db.prepare(assetID: b.id, target: target())
        let bn = try await db.markIndependentFileInputIntent(bo.id, selection: selection(b, target: target()), ownerID: owner)
        _ = try await db.apply(receipt(bo, b, bn, outcome: .verifiedReady), policy: policy)
        _ = try await db.apply(receipt(ao, a, an, outcome: .verifiedReady), policy: policy)
        _ = try await db.apply(receipt(ao, a, an, outcome: .definitiveFailure), policy: policy)
        let aa = try await db.operation(id: ao.id), bb = try await db.operation(id: bo.id)
        XCTAssertEqual(aa?.phase, .compensated); XCTAssertEqual(bb?.phase, .succeeded)
        let c = try await asset(db), co = try await db.prepare(assetID: c.id, target: target())
        _ = try await db.markIndependentFileInputIntent(co.id, selection: selection(c, target: target()), ownerID: owner)
        let startedA = try await db.uploadStartReceipt(for: ao.id)
        XCTAssertEqual(startedA?.assetID, a.id)
        XCTAssertEqual(startedA?.operationID, ao.id)
    }

    func testRejectionNeedsOriginalNonceAndCannotClearUnknown() async throws {
        let db = try store(), a = try await asset(db), op = try await db.prepare(assetID: a.id, target: target())
        let nonce = try await db.markDispatchIntent(op.id)
        func proof(_ n: UUID) -> PreInputRejection { .init(operationID: op.id, assetID: a.id, attempt: op.attempt, assetSHA256: a.sha256, target: op.target, invocationID: n, stage: .pageRetiredBeforeCommit) }
        do { try await db.recordPreInputRejection(proof(UUID())); XCTFail("nonce") } catch RiftletError.mismatchedReceipt {}
        try await db.recordPreInputRejection(proof(nonce))
        let first = try await db.operation(id: op.id); XCTAssertEqual(first?.phase, .failed)
        let next = try await db.prepare(assetID: a.id, target: target()); XCTAssertNotEqual(next.id, op.id); XCTAssertEqual(next.attempt, 2)
        let nextNonce = try await db.markDispatchIntent(next.id)
        try await db.markUnknown(next.id, reason: "commit uncertain")
        do { try await db.recordPreInputRejection(.init(operationID: next.id, assetID: a.id, attempt: next.attempt, assetSHA256: a.sha256, target: next.target, invocationID: nextNonce, stage: .localBeforeBegin)); XCTFail("unknown") }
        catch RiftletError.mismatchedReceipt {}
        let same = try await db.prepare(assetID: a.id, target: target()); XCTAssertEqual(same.id, next.id)
    }
    func testCoordinatorStartedAThenIndependentBSuccessOrFailureNeverReplaysA() async throws {
        for bFails in [false, true] {
            let root = directory.appendingPathComponent(UUID().uuidString)
            let db = try QueueStore(databaseURL: root)
            let a = try await asset(db), b = try await asset(db)
            let adapter = LifecycleContinuingAdapter(bFails: bFails)
            let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory,
                policy: policy, validateAcceptedSelection: { _ in true })
            try await coordinator.select(selection(a, target: target()))
            try await coordinator.select(selection(b, target: target()))
            let calls = await adapter.calls
            XCTAssertEqual(calls, [a.id, b.id])
            let ar = try await db.asset(id: a.id)!, br = try await db.asset(id: b.id)!
            // select releases the independent input boundary before apply and
            // recordAppendReturned finish. Wait for each original receipt to be
            // durable before checking its phase; adapter.calls only counts entry.
            for operationID in [try XCTUnwrap(ar.activeOperationID), try XCTUnwrap(br.activeOperationID)] {
                let deadline = ProcessInfo.processInfo.systemUptime + 5
                var returnedReceipt: TransferReceipt?
                repeat {
                    if let data = try await db.checkpoint(for: "transfer-dispatch-call-v1:" + operationID.uuidString) {
                        returnedReceipt = try JSONDecoder().decode(DispatchCallRecord.self, from: data).returnedReceipt
                    }
                    if returnedReceipt != nil { break }
                    await Task.yield()
                } while ProcessInfo.processInfo.systemUptime < deadline
                XCTAssertEqual(returnedReceipt?.operationID, operationID,
                               "Original append must durably record its receipt within five seconds")
            }
            let ao = try await db.operation(id: ar.activeOperationID!)!, bo = try await db.operation(id: br.activeOperationID!)!
            XCTAssertNotEqual(ao.id, bo.id)
            XCTAssertEqual(ao.phase, .inputTriggered)
            XCTAssertEqual(bo.phase, bFails ? .unknown : .succeeded)
            try await coordinator.observePending()
            let afterObservation = await adapter.calls; XCTAssertEqual(afterObservation, [a.id, b.id])
        }
    }

    func testCoordinatorRetiresOnlyCurrentTypedRejection() async throws {
        let db = try store(), a = try await asset(db), ao = try await db.prepare(assetID: a.id, target: target())
        let nonce = try await db.markDispatchIntent(ao.id)
        let proof = PreInputRejection(operationID: ao.id, assetID: a.id, attempt: ao.attempt, assetSHA256: a.sha256, target: ao.target, invocationID: nonce, stage: .localBeforeBegin)
        let b = try await asset(db), adapter = LifecycleRejectAdapter(other: proof)
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory)
        try await coordinator.select(b.id, frozenTarget: target("00000000-0000-0000-0000-000000000002"))
        let aFinal = try await db.operation(id: ao.id), bRecord = try await db.asset(id: b.id)!
        let bFinal = try await db.operation(id: bRecord.activeOperationID!)
        XCTAssertEqual(aFinal?.phase, .dispatchIntent); XCTAssertEqual(bFinal?.phase, .unknown)
    }
    func testCoordinatorNoInputRejectionPreservesImageAndRequiresNewClick() async throws {
        let db = try store(), a = try await asset(db), adapter = LifecycleRejectAdapter(other: nil)
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory)
        try await coordinator.select(a.id, frozenTarget: target())
        let first = try await db.asset(id: a.id)!; XCTAssertEqual(first.status, .failed); XCTAssertEqual(first.visibility, .visible)
        let firstCount = await adapter.count; XCTAssertEqual(firstCount, 1)
        try await coordinator.observePending(); let unchanged = await adapter.count; XCTAssertEqual(unchanged, 1)
        try await coordinator.select(a.id, frozenTarget: target())
        let second = try await db.asset(id: a.id)!; XCTAssertNotEqual(first.activeOperationID, second.activeOperationID)
        let secondCount = await adapter.count; XCTAssertEqual(secondCount, 2)
    }
}

private actor LifecycleRejectAdapter: AttachmentAdapter {
    nonisolated let id = "lifecycle-fixture"
    let other: PreInputRejection?
    var count = 0
    init(other: PreInputRejection?) { self.other = other }
    func captureTarget() async throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) async throws -> Bool { true }
    func append(_ r: TransferRequest) async throws -> TransferReceipt {
        count += 1
        if let other { throw other }
        throw PreInputRejection(operationID: r.operation.id, assetID: r.asset.id, attempt: r.operation.attempt,
            assetSHA256: r.asset.sha256, target: r.operation.target, invocationID: r.invocationID!, stage: .localBeforeBegin)
    }
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt { throw RiftletError.invalidTransition }
}

private actor LifecycleContinuingAdapter: IndependentFileInputAdapter {
    nonisolated let id = "lifecycle-fixture"
    let bFails: Bool
    var calls: [UUID] = []
    init(bFails: Bool) { self.bFails = bFails }
    func captureTarget() async throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) async throws -> Bool { true }
    func append(_ r: TransferRequest) async throws -> TransferReceipt {
        calls.append(r.asset.id)
        let first = calls.count == 1
        return TransferReceipt(operationID: r.operation.id, assetID: r.asset.id, attempt: r.operation.attempt,
            assetSHA256: r.asset.sha256, target: r.operation.target,
            outcome: first ? .uploadStarted : (bFails ? .definitiveFailure : .verifiedReady),
            profileID: "fixture-ready", attachmentID: "attachment-\(r.operation.id)",
            positiveReady: !first && !bFails, belongsToOriginalDraft: true,
            hasError: !first && bFails, isUploading: first,
            uploadStartEvidence: first ? .init(profileID: "fixture-start", signal: .correlatedProgress, evidenceID: "start-\(r.operation.id)") : nil,
            continuationEvidence: first ? .init(profileID: "fixture-independent", evidenceID: "independent-\(r.operation.id)", invocationID: r.invocationID!) : nil)
    }
    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt {
        try await append(request)
    }
    func reconcile(_ r: TransferRequest) async throws -> TransferReceipt {
        .init(operationID: r.operation.id, assetID: r.asset.id, attempt: r.operation.attempt,
            assetSHA256: r.asset.sha256, target: r.operation.target, outcome: .unknown,
            profileID: "fixture-ready", attachmentID: "attachment-\(r.operation.id)", belongsToOriginalDraft: true)
    }
}
