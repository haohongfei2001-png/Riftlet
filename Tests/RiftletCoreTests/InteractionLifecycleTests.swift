import Foundation
import XCTest
@testable import RiftletCore

/// Product lifecycle regressions use temporary SQLite and synthetic file bytes.
/// They grant fixture-only profiles, never production ChatGPT admission.
final class InteractionLifecycleTests: XCTestCase {
    private var directory: URL!
    private let profile = "lifecycle-fixture-v1"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftlet-interaction-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func store(_ name: String = "queue.sqlite", mode: StoreMode = .production) throws -> QueueStore {
        try QueueStore(databaseURL: directory.appendingPathComponent(name), mode: mode)
    }

    private var admitted: ReceiptPolicy {
        ReceiptPolicy(admittedProfiles: [profile: .webChat], retrySafeProfiles: [profile: .webChat],
            uploadStartProfiles: [profile: .webChat])
    }

    private func target(_ draft: String = "draft") -> TargetLease {
        TargetLease(adapterID: "lifecycle-fixture", surface: .webChat,
            applicationID: "fixture.browser", sessionID: "session", windowID: "window", tabID: "tab",
            documentID: "document", composerID: "composer", draftGeneration: draft)
    }

    private func image(_ order: TimeInterval = 1, origin: AssetOrigin = .synthetic) throws -> ImportedAsset {
        let id = UUID()
        // Not an image decoder fixture: these bytes verify preservation only.
        let bytes = Data("synthetic lifecycle fixture \(id)".utf8)
        let image = ImportedAsset(id: id, sourceKey: "lifecycle-\(id)", fileName: "\(id).fixture",
            sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count),
            pixelWidth: 2, pixelHeight: 2, mediaType: "image/png",
            capturedAt: Date(timeIntervalSince1970: order),
            firstSeenAt: Date(timeIntervalSince1970: 100),
            importedAt: Date(timeIntervalSince1970: 101), origin: origin)
        try bytes.write(to: directory.appendingPathComponent(image.fileName))
        return image
    }

    private func prepare(_ store: QueueStore, _ image: ImportedAsset,
                         target: TargetLease? = nil, dispatched: Bool = true) async throws -> TransferOperation {
        _ = try await store.importAsset(image)
        let op = try await store.prepare(assetID: image.id, target: target ?? self.target())
        if dispatched { try await store.markDispatchIntent(op.id) }
        return op
    }

    private func evidence(version: Int = 1, profileID: String? = nil,
                          evidenceID: String = "bound-progress-fixture", inputCount: Int = 1) -> UploadStartEvidence {
        UploadStartEvidence(version: version, profileID: profileID ?? profile, signal: .correlatedProgress,
            evidenceID: evidenceID, inputCount: inputCount)
    }

    private func receipt(_ op: TransferOperation, _ image: ImportedAsset, outcome: ReceiptOutcome,
                         attachmentID: String? = nil, profileID: String? = nil,
                         error: Bool? = nil, uploading: Bool? = nil, ready: Bool? = nil,
                         retry: Bool? = nil, belongs: Bool = true,
                         start: UploadStartEvidence? = nil, target: TargetLease? = nil,
                         assetID: UUID? = nil, attempt: Int? = nil, hash: String? = nil) -> TransferReceipt {
        TransferReceipt(operationID: op.id, assetID: assetID ?? image.id,
            attempt: attempt ?? op.attempt, assetSHA256: hash ?? image.sha256,
            target: target ?? op.target, outcome: outcome, profileID: profileID ?? profile,
            attachmentID: attachmentID ?? "attachment-\(op.id)",
            positiveReady: ready ?? (outcome == .verifiedReady), belongsToOriginalDraft: belongs,
            hasError: error ?? (outcome == .definitiveFailure),
            isUploading: uploading ?? (outcome == .uploadStarted),
            safeToRetry: retry ?? (outcome == .definitiveFailure), reason: "SYNTHETIC lifecycle fixture",
            uploadStartEvidence: start)
    }

    private func begin(_ store: QueueStore, _ image: ImportedAsset,
                       op: TransferOperation) async throws -> AssetRecord {
        try await store.apply(receipt(op, image, outcome: .uploadStarted, start: evidence()), policy: admitted)
    }

    func testClickIntentInputAndPlaceholderDoNotSwallowWithoutPositiveStart() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset, dispatched: false)
        let prepared = try await db.asset(id: asset.id)
        XCTAssertEqual(prepared?.visibility, .visible)
        try await db.markDispatchIntent(op.id)
        for outcome in [ReceiptOutcome.inputTriggered, .attachedCandidate, .unknown] {
            let record = try await db.apply(receipt(op, asset, outcome: outcome), policy: admitted)
            XCTAssertEqual(record.visibility, .visible)
            XCTAssertNotEqual(record.status, .used)
        }
        let savedStart = try await db.uploadStartReceipt(for: op.id)
        XCTAssertNil(savedStart)
    }

    func testUnadmittedStartAndMalformedStartCannotAcquireVisualPermission() async throws {
        let combinations: [(UploadStartEvidence?, ReceiptPolicy)] = [
            (evidence(), .init()), (nil, admitted), (evidence(version: 2), admitted),
            (evidence(profileID: "unadmitted"), admitted), (evidence(evidenceID: ""), admitted),
            (evidence(inputCount: 2), admitted)
        ]
        for (index, combination) in combinations.enumerated() {
            let db = try store("rejected-\(index).sqlite"), asset = try image()
            let op = try await prepare(db, asset)
            let record = try await db.apply(receipt(op, asset, outcome: .uploadStarted, start: combination.0),
                policy: combination.1)
            let saved = try await db.uploadStartReceipt(for: op.id)
            XCTAssertEqual(record.visibility, .visible)
            XCTAssertNotEqual(record.status, .used)
            XCTAssertNil(saved)
        }
    }

    func testSyntheticStartAdmissionCannotHideSystemScreenshot() async throws {
        let db = try store(), asset = try image(origin: .systemScreenshot)
        let op = try await prepare(db, asset)
        let policy = ReceiptPolicy(syntheticUploadStartProfiles: [profile: .webChat])
        let result = try await db.apply(receipt(op, asset, outcome: .uploadStarted, start: evidence()), policy: policy)
        let saved = try await db.uploadStartReceipt(for: op.id)
        XCTAssertEqual(result.visibility, .visible)
        XCTAssertNil(saved)
    }

    func testSyntheticRetryAdmissionIsIndependentAndCannotRebirthSystemScreenshot() async throws {
        let retryOnly = ReceiptPolicy(syntheticRetrySafeProfiles: [profile: .webChat])
        let withoutRetry = ReceiptPolicy(syntheticAcceptanceProfiles: [profile: .webChat],
            syntheticUploadStartProfiles: [profile: .webChat])
        let withRetry = ReceiptPolicy(syntheticAcceptanceProfiles: [profile: .webChat],
            syntheticUploadStartProfiles: [profile: .webChat], syntheticRetrySafeProfiles: [profile: .webChat])
        XCTAssertTrue(ReceiptPolicy().syntheticRetrySafeProfiles.isEmpty)
        for origin in [AssetOrigin.synthetic, .systemScreenshot] {
            let db = try store("synthetic-retry-\(origin.rawValue).sqlite"), asset = try image(origin: origin)
            let op = try await prepare(db, asset)
            // A separate fixture start grant supplies the same hidden state for
            // both origins; this does not authorize any real transport or image.
            _ = try await begin(db, asset, op: op)
            let failure = receipt(op, asset, outcome: .definitiveFailure)
            XCTAssertFalse(ReceiptPolicy().allowsRetry(receipt: failure, asset: asset, mode: .production))
            XCTAssertFalse(withoutRetry.allowsRetry(receipt: failure, asset: asset, mode: .production))
            XCTAssertEqual(retryOnly.allowsRetry(receipt: failure, asset: asset, mode: .production), origin == .synthetic)
            XCTAssertFalse(retryOnly.allowsUploadStart(receipt: receipt(op, asset, outcome: .uploadStarted, start: evidence()),
                asset: asset, mode: .production))
            XCTAssertFalse(retryOnly.allowsConsumption(receipt: receipt(op, asset, outcome: .verifiedReady),
                asset: asset, mode: .production))
            let unadmitted = try await db.apply(failure, policy: withoutRetry)
            XCTAssertEqual(unadmitted.status, .unknown)
            XCTAssertEqual(unadmitted.visibility, .swallowed)
            let result = try await db.apply(failure, policy: withRetry)
            XCTAssertEqual(result.status, origin == .synthetic ? .failed : .unknown)
            XCTAssertEqual(result.visibility, origin == .synthetic ? .visible : .swallowed)
            let selected = try await db.prepare(assetID: asset.id, target: target())
            XCTAssertEqual(selected.attempt, origin == .synthetic ? 2 : 1)
            if origin == .synthetic { XCTAssertNotEqual(selected.id, op.id) }
            else { XCTAssertEqual(selected.id, op.id) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.fileName).path))
        }
    }

    func testStartAdmissionRejectsConflictingFlagsAndMissingAttachment() async throws {
        for index in 0..<6 {
            let db = try store("flags-\(index).sqlite"), asset = try image()
            let op = try await prepare(db, asset)
            let incoming = receipt(op, asset, outcome: .uploadStarted,
                attachmentID: index == 0 ? "" : nil,
                error: index == 1, uploading: index != 2, ready: index == 3,
                retry: index == 4, belongs: index != 5, start: evidence())
            let record = try await db.apply(incoming, policy: admitted)
            let saved = try await db.uploadStartReceipt(for: op.id)
            XCTAssertEqual(record.visibility, .visible)
            XCTAssertNil(saved)
        }
    }

    func testAdmittedStartHidesBeforeSuccessAndPersistsItsOwnEvidence() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        let start = receipt(op, asset, outcome: .uploadStarted, start: evidence())
        let hidden = try await db.apply(start, policy: admitted)
        let phase = try await db.operation(id: op.id)
        let saved = try await db.uploadStartReceipt(for: op.id)
        let visible = try await db.assets()
        XCTAssertEqual(hidden.visibility, .swallowed)
        XCTAssertEqual(hidden.visibilityReason, .uploadStarted)
        XCTAssertEqual(hidden.status, .transferring)
        XCTAssertEqual(phase?.phase, .inputTriggered)
        XCTAssertEqual(saved, start)
        XCTAssertTrue(visible.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.fileName).path))
    }

    func testUnknownAfterStartStaysInternalAcrossRestartWithoutNewAttempt() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        let hidden = try await begin(db, asset, op: op)
        let start = try await db.uploadStartReceipt(for: op.id)
        _ = try await db.apply(receipt(op, asset, outcome: .unknown), policy: admitted)
        let reopened = try store()
        try await reopened.recoverInterruptedOperations()
        let record = try await reopened.asset(id: asset.id)
        let visible = try await reopened.assets()
        let same = try await reopened.prepare(assetID: asset.id, target: target("new-target-must-not-win"))
        let retained = try await reopened.uploadStartReceipt(for: op.id)
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(record?.status, .unknown)
        XCTAssertEqual(record?.visibility, .swallowed)
        XCTAssertEqual(record?.visibilityRevision, hidden.visibilityRevision)
        XCTAssertEqual(record?.activeOperationID, op.id)
        XCTAssertEqual(same.id, op.id)
        XCTAssertEqual(same.attempt, 1)
        XCTAssertEqual(same.target, op.target)
        XCTAssertEqual(retained, start)
    }

    func testFinalReadyDoesNotRepeatVisibleTransitionOrEraseStartedEvidence() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        let hidden = try await begin(db, asset, op: op)
        let start = try await db.uploadStartReceipt(for: op.id)
        let complete = try await db.apply(receipt(op, asset, outcome: .verifiedReady), policy: admitted)
        let phase = try await db.operation(id: op.id)
        let retained = try await db.uploadStartReceipt(for: op.id)
        XCTAssertEqual(complete.status, .used)
        XCTAssertEqual(phase?.phase, .succeeded)
        XCTAssertEqual(complete.visibility, .swallowed)
        XCTAssertEqual(complete.visibilityRevision, hidden.visibilityRevision)
        XCTAssertEqual(complete.visibilityReason, .uploadStarted)
        XCTAssertEqual(retained, start)
    }

    func testRepeatedStartKeepsFirstAuditAndDoesNotRepeatVisualTransition() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        let hidden = try await begin(db, asset, op: op)
        let first = try await db.uploadStartReceipt(for: op.id)
        let repeated = try await db.apply(receipt(op, asset, outcome: .uploadStarted,
            start: evidence(evidenceID: "later-observation-of-same-upload")), policy: admitted)
        let retained = try await db.uploadStartReceipt(for: op.id)
        XCTAssertEqual(retained, first)
        XCTAssertEqual(repeated.visibilityRevision, hidden.visibilityRevision)
        XCTAssertEqual(repeated.visibility, .swallowed)
    }

    func testLegacyReadyExitsSilentlyWithoutInventingAnEarlierStart() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        let complete = try await db.apply(receipt(op, asset, outcome: .verifiedReady), policy: admitted)
        let start = try await db.uploadStartReceipt(for: op.id)
        XCTAssertEqual(complete.status, .used)
        XCTAssertEqual(complete.visibility, .swallowed)
        XCTAssertEqual(complete.visibilityReason, .legacyCompletion)
        XCTAssertNil(start)
    }

    func testEveryStartIdentityMismatchCannotHideAnotherImage() async throws {
        let db = try store(), first = try image(1), second = try image(2)
        let op = try await prepare(db, first)
        _ = try await db.importAsset(second)
        let before = try await db.asset(id: first.id)
        let invalid = [
            receipt(op, first, outcome: .uploadStarted, start: evidence(), assetID: second.id),
            receipt(op, first, outcome: .uploadStarted, start: evidence(), attempt: 2),
            receipt(op, first, outcome: .uploadStarted, start: evidence(), hash: String(repeating: "b", count: 64)),
            receipt(op, first, outcome: .uploadStarted, start: evidence(), target: target("other"))
        ]
        for observation in invalid {
            do { _ = try await db.apply(observation, policy: admitted); XCTFail("Wrong start identity accepted") }
            catch RiftletError.mismatchedReceipt {}
        }
        let after = try await db.asset(id: first.id), other = try await db.asset(id: second.id)
        let start = try await db.uploadStartReceipt(for: op.id)
        XCTAssertEqual(after, before)
        XCTAssertEqual(other?.visibility, .visible)
        XCTAssertNil(start)
    }

    func testStrongSafeFailureRebirthsAnOrdinaryClickableScreenshot() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        _ = try await begin(db, asset, op: op)
        let failed = try await db.apply(receipt(op, asset, outcome: .definitiveFailure), policy: admitted)
        XCTAssertEqual(failed.visibility, .visible)
        XCTAssertEqual(failed.visibilityReason, .safeFailure)
        XCTAssertEqual(failed.status, .failed)
        let next = try await db.prepare(assetID: asset.id, target: target())
        XCTAssertEqual(next.attempt, 2)
        XCTAssertNotEqual(next.id, op.id)
        do {
            _ = try await db.apply(receipt(op, asset, outcome: .definitiveFailure), policy: admitted)
            XCTFail("Old failure changed a new user attempt")
        } catch RiftletError.mismatchedReceipt {}
        let current = try await db.asset(id: asset.id)
        XCTAssertEqual(current?.activeOperationID, next.id)
        XCTAssertEqual(current?.status, .transferring)
    }

    func testUnsafeOrWrongAttachmentFailureCannotReviveStartedImage() async throws {
        for index in 0..<4 {
            let db = try store("unsafe-\(index).sqlite"), asset = try image()
            let op = try await prepare(db, asset)
            _ = try await begin(db, asset, op: op)
            let before = try await db.asset(id: asset.id)
            let failure = receipt(op, asset, outcome: .definitiveFailure,
                attachmentID: index == 0 ? "another-attachment" : nil,
                error: index != 1, retry: index != 2)
            let policy = index == 3 ? ReceiptPolicy(uploadStartProfiles: [profile: .webChat]) : admitted
            if index == 0 {
                do { _ = try await db.apply(failure, policy: policy); XCTFail("Wrong attachment accepted") }
                catch RiftletError.mismatchedReceipt {}
            } else { _ = try await db.apply(failure, policy: policy) }
            let record = try await db.asset(id: asset.id)
            let phase = try await db.operation(id: op.id)
            XCTAssertEqual(record?.visibility, .swallowed)
            if index == 0 { XCTAssertEqual(record, before) }
            else { XCTAssertEqual(record?.status, .unknown) }
            XCTAssertTrue(phase?.phase.isUnresolved == true)
        }
    }

    func testLateUnsafeFailureKeepsCompensationInternalUntilRetryIsProved() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        _ = try await begin(db, asset, op: op)
        _ = try await db.apply(receipt(op, asset, outcome: .verifiedReady), policy: admitted)
        let unsafe = receipt(op, asset, outcome: .unknown, error: true)
        let compensated = try await db.apply(unsafe, policy: admitted)
        let audit = try await db.compensation(for: op.id)
        let phase = try await db.operation(id: op.id)
        XCTAssertEqual(compensated.visibility, .swallowed)
        XCTAssertEqual(compensated.status, .unknown)
        XCTAssertEqual(phase?.phase, .compensated)
        XCTAssertNotNil(audit)
        let restored = try await db.apply(receipt(op, asset, outcome: .definitiveFailure), policy: admitted)
        let retainedAudit = try await db.compensation(for: op.id)
        XCTAssertEqual(restored.visibility, .visible)
        XCTAssertEqual(restored.status, .failed)
        XCTAssertEqual(retainedAudit, audit)
    }

    func testAlreadySafeLateFailureRebirthsOnItsFirstProvedObservation() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        _ = try await begin(db, asset, op: op)
        _ = try await db.apply(receipt(op, asset, outcome: .verifiedReady), policy: admitted)
        let restored = try await db.apply(receipt(op, asset, outcome: .definitiveFailure), policy: admitted)
        let audit = try await db.compensation(for: op.id)
        let phase = try await db.operation(id: op.id)
        XCTAssertEqual(restored.visibility, .visible)
        XCTAssertEqual(restored.status, .failed)
        XCTAssertEqual(phase?.phase, .failed)
        XCTAssertNotNil(audit)
        let next = try await db.prepare(assetID: asset.id, target: target())
        XCTAssertEqual(next.attempt, 2)
    }

    func testExplicitRemovalOverridesLateStartSuccessAndSafeFailure() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        try await db.removeFromQueue(asset.id)
        for observation in [receipt(op, asset, outcome: .uploadStarted, start: evidence()),
                            receipt(op, asset, outcome: .verifiedReady),
                            receipt(op, asset, outcome: .definitiveFailure)] {
            _ = try await db.apply(observation, policy: admitted)
            let current = try await db.asset(id: asset.id)
            XCTAssertEqual(current?.visibility, .removed)
        }
        let start = try await db.uploadStartReceipt(for: op.id)
        XCTAssertNotNil(start)
        let canRestore = try await db.canRestoreToQueue(asset.id)
        XCTAssertTrue(canRestore, "Safe failure may be explicitly restored, never automatically resurrected after user removal")
        try await db.restoreToQueue(asset.id)
        let restored = try await db.asset(id: asset.id)
        XCTAssertEqual(restored?.visibility, .visible)
    }

    func testClearVisibleQueueDoesNotDeletePrivateBytesOrRewriteExternalFacts() async throws {
        let db = try store(), pending = try image(1), inFlight = try image(2), alreadyHidden = try image(3)
        _ = try await db.importAsset(pending)
        let active = try await prepare(db, inFlight, target: target("in-flight"))
        let hiddenOp = try await prepare(db, alreadyHidden, target: target("hidden"))
        _ = try await begin(db, alreadyHidden, op: hiddenOp)
        let beforeOp = try await db.operation(id: active.id)
        let beforeStart = try await db.uploadStartReceipt(for: hiddenOp.id)
        try await db.clearVisibleQueue()
        let visible = try await db.assets(), all = try await db.assets(includeUsed: true)
        let afterOp = try await db.operation(id: active.id)
        let afterStart = try await db.uploadStartReceipt(for: hiddenOp.id)
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(all.map(\.visibility), [.removed, .removed, .swallowed])
        XCTAssertEqual(afterOp, beforeOp)
        XCTAssertEqual(afterStart, beforeStart)
        for asset in [pending, inFlight, alreadyHidden] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.fileName).path))
        }
    }

    func testRemovedPreparedSelectionCannotDispatchAfterUserClear() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset, dispatched: false)
        try await db.clearVisibleQueue()
        do { try await db.markDispatchIntent(op.id); XCTFail("User-cleared prepared selection dispatched") }
        catch RiftletError.invalidTransition {}
        let current = try await db.asset(id: asset.id)
        XCTAssertEqual(current?.visibility, .removed)
    }

    func testHistoryRestoreCannotReinputSwallowedUnknownOrSuccessfulImage() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        _ = try await begin(db, asset, op: op)
        for observation in [receipt(op, asset, outcome: .unknown), receipt(op, asset, outcome: .verifiedReady)] {
            _ = try await db.apply(observation, policy: admitted)
            let allowed = try await db.canRestoreToQueue(asset.id)
            XCTAssertFalse(allowed)
            do { try await db.restoreToQueue(asset.id); XCTFail("Internal consumed operation was made retryable") }
            catch RiftletError.invalidTransition {}
        }
    }

    func testHiddenIntentPersistsThroughNewImportsAndIsSeparateFromCapturePause() async throws {
        let db = try store()
        try await db.setUserHidden(true)
        try await db.setCapturePaused(false)
        let asset = try image()
        _ = try await db.importAsset(asset)
        let reopened = try store()
        let hidden = try await reopened.userHidden(), paused = try await reopened.capturePaused()
        let queue = try await reopened.assets()
        XCTAssertTrue(hidden)
        XCTAssertFalse(paused)
        XCTAssertEqual(queue.map(\.id), [asset.id])
        try await reopened.setCapturePaused(true)
        try await reopened.setUserHidden(false)
        let finalPaused = try await reopened.capturePaused(), finalHidden = try await reopened.userHidden()
        XCTAssertTrue(finalPaused)
        XCTAssertFalse(finalHidden)
    }

    func testStartVisibilityAndAuditCommitAtomicallyUnderStorageFailure() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        let before = try await db.asset(id: asset.id), beforeOp = try await db.operation(id: op.id)
        let sql = try SQLiteDatabase(url: directory.appendingPathComponent("queue.sqlite"))
        try sql.execute("CREATE TRIGGER reject_lifecycle BEFORE UPDATE ON assets BEGIN SELECT RAISE(ABORT,'synthetic storage fault'); END")
        do { _ = try await begin(db, asset, op: op); XCTFail("Fault did not roll back start") }
        catch RiftletError.database {}
        let after = try await db.asset(id: asset.id), afterOp = try await db.operation(id: op.id)
        let start = try await db.uploadStartReceipt(for: op.id)
        XCTAssertEqual(after, before)
        XCTAssertEqual(afterOp, beforeOp)
        XCTAssertNil(start)
        try sql.execute("DROP TRIGGER reject_lifecycle")
        let accepted = try await begin(db, asset, op: op)
        XCTAssertEqual(accepted.visibility, .swallowed)
    }

    func testBlockedOrStaleInteractionFencePreventsIdleArchive() async throws {
        let db = try store(), asset = try image()
        _ = try await db.importAsset(asset)
        let fence = QueueInteractionFence()
        let initiallyIdle = fence.snapshot()
        fence.update(blocked: true) // hover, mouse-down or animation began
        let busy = fence.snapshot()
        let blocked = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200),
            fence: fence, revision: busy.revision)
        XCTAssertTrue(blocked.isEmpty)
        fence.update(blocked: false)
        let stale = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200),
            fence: fence, revision: initiallyIdle.revision)
        let visible = try await db.asset(id: asset.id)
        XCTAssertTrue(stale.isEmpty)
        XCTAssertEqual(visible?.visibility, .visible)
        let current = fence.snapshot()
        let accepted = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200),
            fence: fence, revision: current.revision)
        XCTAssertEqual(accepted, [asset.id])
    }

    func testSelectionReservationSurvivesTargetAwaitEvenWithIdleUISnapshot() async throws {
        let db = try store(), selected = try image(1), other = try image(2)
        let selectedRecord = try await db.importAsset(selected)
        _ = try await db.importAsset(other)
        try await db.reserveSelection(selected.id, visibilityRevision: selectedRecord.visibilityRevision,
            now: Date(timeIntervalSince1970: 150))
        let fence = QueueInteractionFence(), snapshot = fence.snapshot()
        // The cutoff includes the new interaction time, proving the reservation
        // itself, rather than just a timestamp, protects the async gap.
        let archived = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200),
            fence: fence, revision: snapshot.revision)
        XCTAssertEqual(archived, [other.id])
        let op = try await db.prepare(assetID: selected.id, target: target())
        await db.releaseSelection(selected.id)
        let afterPrepare = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200),
            fence: fence, revision: snapshot.revision)
        let selectedState = try await db.asset(id: selected.id)
        XCTAssertTrue(afterPrepare.isEmpty)
        XCTAssertEqual(selectedState?.visibility, .visible)
        XCTAssertEqual(selectedState?.activeOperationID, op.id)
    }

    func testAcceptedPressCanUndoOnlyItsImmediatelyPrecedingAutomaticArchive() async throws {
        let db = try store(), asset = try image()
        let original = try await db.importAsset(asset)
        let fence = QueueInteractionFence(), snapshot = fence.snapshot()
        _ = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200), fence: fence,
            revision: snapshot.revision)
        // Archive committed before AppKit's accepted press reached the actor;
        // the on-screen row still carries its original visibility revision.
        try await db.reserveSelection(asset.id, visibilityRevision: original.visibilityRevision,
            now: Date(timeIntervalSince1970: 300))
        let restored = try await db.asset(id: asset.id)
        XCTAssertEqual(restored?.visibility, .visible)
        XCTAssertEqual(restored?.visibilityReason, .userRestored)
        XCTAssertEqual(restored?.lastInteractionAt, Date(timeIntervalSince1970: 300))
        let op = try await db.prepare(assetID: asset.id, target: target())
        XCTAssertEqual(op.attempt, 1)
        await db.releaseSelection(asset.id)
    }

    func testStalePressCannotUndoUserRemovalOrUnrelatedArchiveRevision() async throws {
        let db = try store(), removed = try image(1), archived = try image(2)
        let removeRecord = try await db.importAsset(removed)
        let archiveRecord = try await db.importAsset(archived)
        try await db.removeFromQueue(removed.id)
        let fence = QueueInteractionFence(), snapshot = fence.snapshot()
        _ = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200), fence: fence,
            revision: snapshot.revision)
        do {
            try await db.reserveSelection(removed.id, visibilityRevision: removeRecord.visibilityRevision)
            XCTFail("An old press undid explicit user removal")
        } catch RiftletError.invalidTransition {}
        do {
            try await db.reserveSelection(archived.id, visibilityRevision: archiveRecord.visibilityRevision + 10)
            XCTFail("Unrelated revision undid an archive")
        } catch RiftletError.invalidTransition {}
        do {
            try await db.reserveSelection(archived.id)
            XCTFail("No original on-screen revision was treated as a press")
        } catch RiftletError.invalidTransition {}
        let removedState = try await db.asset(id: removed.id), archivedState = try await db.asset(id: archived.id)
        XCTAssertEqual(removedState?.visibility, .removed)
        XCTAssertEqual(archivedState?.visibility, .archived)
    }

    func testCancelledSelectionReleasesArchiveReservation() async throws {
        let db = try store(), asset = try image()
        let original = try await db.importAsset(asset)
        try await db.reserveSelection(asset.id, visibilityRevision: original.visibilityRevision,
            now: Date(timeIntervalSince1970: 150))
        await db.releaseSelection(asset.id)
        let fence = QueueInteractionFence(), snapshot = fence.snapshot()
        let archived = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200),
            fence: fence, revision: snapshot.revision)
        XCTAssertEqual(archived, [asset.id])
    }

    func testSafeFailureResetsIdleLifetimeBeforeNormalArchiveCanRun() async throws {
        let db = try store(), asset = try image()
        let op = try await prepare(db, asset)
        _ = try await begin(db, asset, op: op)
        let beforeFailure = Date().addingTimeInterval(-1)
        let failed = try await db.apply(receipt(op, asset, outcome: .definitiveFailure), policy: admitted)
        let fence = QueueInteractionFence(), snapshot = fence.snapshot()
        let archived = try await db.archiveIdle(before: beforeFailure, fence: fence,
            revision: snapshot.revision)
        XCTAssertTrue(archived.isEmpty)
        XCTAssertGreaterThan(failed.lastInteractionAt, beforeFailure)
        let later = try await db.archiveIdle(before: Date().addingTimeInterval(60), fence: fence,
            revision: snapshot.revision)
        let record = try await db.asset(id: asset.id)
        let restorable = try await db.canRestoreToQueue(asset.id)
        XCTAssertEqual(later, [asset.id])
        XCTAssertEqual(record?.visibility, .archived)
        XCTAssertEqual(record?.status, .failed)
        XCTAssertTrue(restorable)
    }

    func testArchiveIsBoundedDurableAndDoesNotChangeHiddenIntentOrDeleteFiles() async throws {
        let db = try store(), first = try image(1), second = try image(2), third = try image(3)
        for asset in [first, second, third] { _ = try await db.importAsset(asset) }
        try await db.setUserHidden(true)
        let fence = QueueInteractionFence(), snapshot = fence.snapshot()
        let archived = try await db.archiveIdle(before: Date(timeIntervalSince1970: 200), fence: fence,
            revision: snapshot.revision, limit: 2)
        XCTAssertEqual(archived, [first.id, second.id])
        let reopened = try store()
        let all = try await reopened.assets(includeUsed: true), hidden = try await reopened.userHidden()
        XCTAssertEqual(all.map(\.visibility), [.archived, .archived, .visible])
        XCTAssertTrue(hidden)
        try await reopened.restoreToQueue(first.id)
        let restored = try await reopened.asset(id: first.id), stillHidden = try await reopened.userHidden()
        XCTAssertEqual(restored?.visibility, .visible)
        XCTAssertTrue(stillHidden)
        for asset in [first, second, third] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.fileName).path))
        }
    }

    func testRunnableSimulationSeparatesEarlyExitFinalSuccessFailureAndUnknown() async throws {
        let db = try store(mode: .simulation)
        let images = try [image(1), image(2), image(3)]
        for asset in images { _ = try await db.importAsset(asset) }
        let adapter = LifecycleCountingAdapter()
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory)
        for asset in images { try await coordinator.select(asset.id) }
        let started = try await db.assets(includeUsed: true)
        let before = await adapter.counts()
        XCTAssertEqual(started.map(\.visibility), [.swallowed, .swallowed, .swallowed])
        XCTAssertEqual(started.map(\.status), [.transferring, .transferring, .transferring])
        XCTAssertEqual(before.append, 3)
        XCTAssertEqual(before.reconcile, 0)

        try await coordinator.observePending()
        let settled = try await db.assets(includeUsed: true)
        XCTAssertEqual(settled.map(\.status), [.used, .failed, .unknown])
        XCTAssertEqual(settled.map(\.visibility), [.swallowed, .visible, .swallowed])
        // The independent third fixture's UNKNOWN never blocks an explicit
        // new user attempt for the safely failed second fixture.
        try await coordinator.select(images[1].id)
        try await coordinator.observePending()
        let retried = try await db.asset(id: images[1].id)
        let operationID = try XCTUnwrap(retried?.activeOperationID)
        let operation = try await db.operation(id: operationID)
        let calls = await adapter.counts()
        XCTAssertEqual(operation?.attempt, 2)
        XCTAssertEqual(retried?.status, .used)
        XCTAssertEqual(calls.append, 4)
    }

    func testBackgroundUnknownRecoveryOnlyObservesOriginalOperationAcrossRestart() async throws {
        let db = try store(mode: .simulation)
        let images = try [image(1), image(2), image(3)]
        for asset in images { _ = try await db.importAsset(asset) }
        let adapter = LifecycleCountingAdapter()
        let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory)
        for asset in images { try await coordinator.select(asset.id) }
        try await coordinator.observePending()
        let unknown = try await db.asset(id: images[2].id)
        let originalID = try XCTUnwrap(unknown?.activeOperationID)
        let start = try await db.uploadStartReceipt(for: originalID)
        try await coordinator.select(images[2].id, frozenTarget: nil)
        try await coordinator.observePending()
        let calls = await adapter.counts()
        XCTAssertEqual(calls.append, 3)
        XCTAssertGreaterThan(calls.reconcile, 3)

        let reopened = try store(mode: .simulation)
        let restartedAdapter = LifecycleCountingAdapter()
        let restarted = TransferCoordinator(store: reopened, adapter: restartedAdapter, mediaDirectory: directory)
        try await restarted.recover()
        try await restarted.observePending()
        let recovered = try await reopened.asset(id: images[2].id)
        let recoveredStart = try await reopened.uploadStartReceipt(for: originalID)
        let afterRestart = await restartedAdapter.counts()
        XCTAssertEqual(recovered?.visibility, .swallowed)
        XCTAssertEqual(recovered?.status, .unknown)
        XCTAssertEqual(recovered?.activeOperationID, originalID)
        XCTAssertEqual(recoveredStart, start)
        XCTAssertEqual(afterRestart.capture, 0)
        XCTAssertEqual(afterRestart.append, 0)
        XCTAssertGreaterThan(afterRestart.reconcile, 0)
    }

    func testInvalidSelectionSettlesAndReleasesArchiveProtectionWithoutInput() async throws {
        let db = try store(), asset = try image()
        let original = try await db.importAsset(asset)
        let settled = LifecycleSettlementRecorder()
        let coordinator = TransferCoordinator(store: db, adapter: UnavailableAdapter(), mediaDirectory: directory,
            onSelectionSettled: { id in await settled.record(id) })
        do {
            try await coordinator.select(asset.id, frozenTarget: nil, visibilityRevision: original.visibilityRevision)
            XCTFail("Selection without a frozen target was accepted")
        } catch RiftletError.adapterUnavailable {}
        let notifications = await settled.values()
        let record = try await db.asset(id: asset.id)
        let operations = try await db.unresolvedOperations()
        XCTAssertEqual(notifications, [asset.id])
        XCTAssertEqual(record?.visibility, .visible)
        XCTAssertNil(record?.activeOperationID)
        XCTAssertTrue(operations.isEmpty)
        let fence = QueueInteractionFence(), snapshot = fence.snapshot()
        let archived = try await db.archiveIdle(before: Date().addingTimeInterval(60), fence: fence,
            revision: snapshot.revision)
        XCTAssertEqual(archived, [asset.id], "Rejected selection leaked its archive reservation")
    }

    func testDuplicateSelectionCannotSettleOwnerWhileTargetCaptureIsSuspended() async throws {
        for failsCapture in [false, true] {
            let db = try store("selection-owner-\(failsCapture).sqlite"), asset = try image()
            _ = try await db.importAsset(asset)
            let started = expectation(description: "Owner target capture suspended: \(failsCapture)")
            let adapter = LifecycleSuspendedTargetAdapter(target: target(), captureStarted: started,
                failsCapture: failsCapture)
            let settled = LifecycleSettlementRecorder()
            let coordinator = TransferCoordinator(store: db, adapter: adapter, mediaDirectory: directory,
                onSelectionSettled: { id in await settled.record(id) })
            let owner = Task { try await coordinator.select(asset.id) }
            await fulfillment(of: [started], timeout: 3)

            // This call completes while the original target await is still held.
            // It owns no reservation and must not release the owner's UI guard.
            try await coordinator.select(asset.id)
            let before = await settled.values()
            let unprepared = try await db.asset(id: asset.id)
            XCTAssertTrue(before.isEmpty)
            XCTAssertNil(unprepared?.activeOperationID)

            await adapter.releaseCapture()
            if failsCapture {
                do { try await owner.value; XCTFail("Fixture capture failure was ignored") }
                catch RiftletError.adapterUnavailable {}
            } else { try await owner.value }
            let notifications = await settled.values()
            let calls = await adapter.counts()
            let record = try await db.asset(id: asset.id)
            XCTAssertEqual(notifications, [asset.id])
            XCTAssertEqual(calls.capture, 1)
            XCTAssertEqual(calls.append, 0)
            XCTAssertEqual(record?.visibility, .visible)
            if failsCapture { XCTAssertNil(record?.activeOperationID) }
            else {
                let operationID = try XCTUnwrap(record?.activeOperationID)
                let operation = try await db.operation(id: operationID)
                XCTAssertEqual(operation?.phase, .failed, "Validation cancels only after durable prepare")
            }
        }
    }
}

private actor LifecycleSuspendedTargetAdapter: AttachmentAdapter {
    nonisolated let id = "lifecycle-fixture"
    private let target: TargetLease
    private let captureStarted: XCTestExpectation
    private let failsCapture: Bool
    private var captureGate: CheckedContinuation<Void, Never>?
    private var captureReleased = false
    private var captureCount = 0
    private var appendCount = 0

    init(target: TargetLease, captureStarted: XCTestExpectation, failsCapture: Bool) {
        self.target = target; self.captureStarted = captureStarted; self.failsCapture = failsCapture
    }
    func captureTarget() async throws -> TargetLease {
        captureCount += 1
        captureStarted.fulfill()
        if !captureReleased { await withCheckedContinuation { captureGate = $0 } }
        if failsCapture { throw RiftletError.adapterUnavailable("Controlled target capture cancellation") }
        return target
    }
    func releaseCapture() {
        captureReleased = true
        captureGate?.resume(); captureGate = nil
    }
    func validate(_ target: TargetLease) async throws -> Bool { false }
    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        appendCount += 1
        throw RiftletError.invalidTransition
    }
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        throw RiftletError.invalidTransition
    }
    func counts() -> (capture: Int, append: Int) { (captureCount, appendCount) }
}

private actor LifecycleCountingAdapter: AttachmentAdapter {
    nonisolated let id = "simulation"
    private let implementation = SimulationAdapter(settlementDelay: 0)
    private var captureCount = 0
    private var appendCount = 0
    private var reconcileCount = 0

    func captureTarget() async throws -> TargetLease {
        captureCount += 1
        return try await implementation.captureTarget()
    }
    func validate(_ target: TargetLease) async throws -> Bool { try await implementation.validate(target) }
    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        appendCount += 1
        return try await implementation.append(request)
    }
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        reconcileCount += 1
        return try await implementation.reconcile(request)
    }
    func counts() -> (capture: Int, append: Int, reconcile: Int) {
        (captureCount, appendCount, reconcileCount)
    }
}

private actor LifecycleSettlementRecorder {
    private var assets: [UUID] = []
    func record(_ id: UUID) { assets.append(id) }
    func values() -> [UUID] { assets }
}
