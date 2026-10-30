import Foundation
import CryptoKit
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Generated PNGs and a constructed bridge exercise the prospective admission
/// boundary only. These tests never collect a screenshot, contact Chrome, or
/// constitute real-Mac input/start/completion evidence.
final class SystemScreenshotCandidateAdmissionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-admission-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testOrdinaryScopeRegistrationIsIndependentAndCandidatePolicyCannotConsumeIt() async throws {
        let (store, request, _) = try await fixture()
        let bridge = AdmissionTestBridge(states: [.uploadStarted, .attached])
        let client = try ordinaryAdapter(store, bridge)
        let start = try await client.append(request)
        XCTAssertEqual(start.profileID, OrdinarySystemScreenshotScope.admittedCompletionProfileID)
        XCTAssertEqual(start.uploadStartEvidence?.profileID, OrdinarySystemScreenshotScope.admittedUploadStartProfileID)
        XCTAssertFalse(policy().allowsUploadStart(receipt: start, asset: request.asset, mode: .production))
        XCTAssertFalse(ReceiptPolicy().allowsUploadStart(receipt: start, asset: request.asset, mode: .production))
        let fence = try await checkpoint(store, request)
        let ordinary = try await store.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: .ordinary))
        XCTAssertNotNil(ordinary); XCTAssertEqual(fence, ordinary)
        await assertRejected { try await adapter(store, bridge).append(request) }
        try await store.markUnknown(request.operation.id, reason: "software-only pending")
        let original = try await refreshed(request, in: store)
        let complete = try await ordinaryAdapter(store, bridge).reconcile(original)
        XCTAssertEqual(complete.profileID, OrdinarySystemScreenshotScope.admittedCompletionProfileID)
        let ordinaryObservation = try await store.checkpoint(for: SystemScreenshotObservationJournal.checkpointKey(original, slot: .attached, scope: .ordinary))
        let candidateObservation = try await store.checkpoint(for: SystemScreenshotObservationJournal.checkpointKey(original, slot: .attached))
        XCTAssertNotNil(ordinaryObservation); XCTAssertNil(candidateObservation)
        XCTAssertFalse(policy().allowsConsumption(receipt: complete, asset: request.asset, mode: .production))
        let actions = await bridge.actions
        XCTAssertEqual(actions, [.begin, .chunk, .commit, .observe])
    }

    func testOrdinaryLegacyUnknownIsObserveOnlyAndCannotBorrowCandidateRegistration() async throws {
        let (store, request, _) = try await fixture()
        try await SystemScreenshotCandidateAdmission(store: store).enroll(request)
        try await store.markUnknown(request.operation.id, reason: "legacy candidate")
        let original = try await refreshed(request, in: store)
        let bridge = AdmissionTestBridge(states: [.attached])
        let receipt = try await ordinaryAdapter(store, bridge).reconcile(original)
        XCTAssertEqual(receipt.profileID, OrdinarySystemScreenshotScope.completionProfileID)
        let marker = try await store.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: .ordinary))
        XCTAssertNil(marker)
        let actions = await bridge.actions
        XCTAssertEqual(actions, [.observe])
        await assertRejected { try await ordinaryAdapter(store, bridge).append(original) }
    }

    func testCrossScopeConcurrentRegistrationHasOnlyOneWinner() async throws {
        let (store, request, database) = try await fixture()
        let second = try QueueStore(databaseURL: database)
        let candidate = SystemScreenshotCandidateAdmission(store: store)
        let ordinary = SystemScreenshotCandidateAdmission(store: second, scope: .ordinary)
        let winners = await withTaskGroup(of: Bool.self) { group in
            group.addTask { do { try await candidate.enroll(request); return true } catch { return false } }
            group.addTask { do { try await ordinary.enroll(request); return true } catch { return false } }
            var values: [Bool] = []; for await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(winners.filter { $0 }.count, 1)
        await assertRejected { try await candidate.enroll(request) }
        await assertRejected { try await ordinary.enroll(request) }
    }

    func testPartialOrdinaryFenceCannotBeReenrolledOrPromotedByObservation() async throws {
        let (store, request, _) = try await fixture()
        try await SystemScreenshotCandidateAdmission(store: store).enroll(request)
        let old = try await checkpoint(store, request)
        var marker = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(old)) as? [String: Any])
        marker["startProfileID"] = OrdinarySystemScreenshotScope.admittedUploadStartProfileID
        marker["completionProfileID"] = OrdinarySystemScreenshotScope.admittedCompletionProfileID
        try await store.saveCheckpoint(JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys]),
            for: SystemScreenshotCandidateAdmission.checkpointKey(for: request))
        let ordinary = SystemScreenshotCandidateAdmission(store: store, scope: .ordinary)
        await assertRejected { try await ordinary.enroll(request) }
        await assertRejected { try await SystemScreenshotCandidateAdmission(store: store).enroll(request) }
        try await store.markUnknown(request.operation.id, reason: "partial ordinary reservation")
        let original = try await refreshed(request, in: store)
        let bridge = AdmissionTestBridge(states: [.attached])
        let receipt = try await ordinaryAdapter(store, bridge).reconcile(original)
        XCTAssertEqual(receipt.profileID, OrdinarySystemScreenshotScope.completionProfileID)
        let after = try await store.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: .ordinary))
        XCTAssertNil(after)
        await assertRejected { try await SystemScreenshotCandidateAdmission(store: store).admits(original) }
        let actions = await bridge.actions; XCTAssertEqual(actions, [.observe])
    }

    func testOrdinaryRejectsWrongProfileOrCandidateComponentsBeforeAnyBridgeCall() async throws {
        let (store, request, _) = try await fixture()
        let bridge = AdmissionTestBridge(states: [.attached])
        for profile in [
            ObservationProfile(adapterID: "wrong", surface: .webChat, profileID: OrdinarySystemScreenshotScope.completionProfileID,
                completionSignal: .attached, uploadStartProfileID: OrdinarySystemScreenshotScope.uploadStartProfileID),
            ObservationProfile(adapterID: "chatgpt-web", surface: .simulation, profileID: OrdinarySystemScreenshotScope.completionProfileID,
                completionSignal: .attached, uploadStartProfileID: OrdinarySystemScreenshotScope.uploadStartProfileID),
            SystemScreenshotWebCandidate.profile] {
            let client = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge, program: try ChatGPTWebPageProgram.load(),
                mode: .ordinarySystemScreenshot, profile: profile, polling: .disabled,
                candidateJournal: SystemScreenshotObservationJournal(store: store, scope: .ordinary),
                candidateAdmission: SystemScreenshotCandidateAdmission(store: store, scope: .ordinary))
            await assertRejected { try await client.append(request) }
        }
        let wrongJournal = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge, program: try ChatGPTWebPageProgram.load(),
            mode: .ordinarySystemScreenshot, profile: OrdinarySystemScreenshotScope.profile, polling: .disabled,
            candidateJournal: SystemScreenshotObservationJournal(store: store),
            candidateAdmission: SystemScreenshotCandidateAdmission(store: store, scope: .ordinary))
        await assertRejected { try await wrongJournal.append(request) }
        let wrongOrigin = try replacing(request.asset, "origin", with: AssetOrigin.applicationScreenshot.rawValue)
        await assertRejected { try await ordinaryAdapter(store, bridge).preflight(asset: wrongOrigin, fileURL: request.fileURL) }
        let actions = await bridge.actions; XCTAssertTrue(actions.isEmpty)
    }

    private func ordinaryAdapter(_ store: QueueStore, _ bridge: AdmissionTestBridge) throws -> WebAttachmentAdapter {
        WebAttachmentAdapter(mediaDirectory: directory, executor: bridge,
            program: try ChatGPTWebPageProgram.load(), mode: .ordinarySystemScreenshot,
            profile: OrdinarySystemScreenshotScope.profile, polling: .disabled,
            candidateJournal: SystemScreenshotObservationJournal(store: store, scope: .ordinary),
            candidateAdmission: SystemScreenshotCandidateAdmission(store: store, scope: .ordinary))
    }

    func testNewAppendStartsOnceAndRestartedCompletionNeedsItsSeparateAdmission() async throws {
        let (store, request, database) = try await fixture()
        let bridge = AdmissionTestBridge(states: [.uploadStarted, .attached, .attached])
        let client = try adapter(store, bridge)
        let start = try await client.append(request)
        XCTAssertEqual(start.outcome, .uploadStarted)
        XCTAssertEqual(start.profileID, SystemScreenshotWebCandidate.admittedCompletionProfileID)
        XCTAssertEqual(start.uploadStartEvidence?.profileID, SystemScreenshotWebCandidate.admittedUploadStartProfileID)
        XCTAssertFalse(start.positiveReady); XCTAssertFalse(start.safeToRetry)
        let firstActions = await bridge.actions
        XCTAssertEqual(firstActions, [.begin, .chunk, .commit])
        let transferred = await bridge.received
        XCTAssertEqual(transferred, AdmissionTestPNG.rgba8)
        let marker = try await checkpoint(store, request)
        XCTAssertNotNil(marker)

        // The original dispatch snapshot and an existing marker never authorize
        // a second append, even before QueueStore applies the first receipt.
        await assertRejected { try await client.append(request) }
        let afterDuplicate = await bridge.actions
        XCTAssertEqual(afterDuplicate, firstActions)
        let hidden = try await store.apply(start, policy: policy(start: true, completion: false))
        XCTAssertEqual(hidden.visibility, .swallowed)
        XCTAssertNotEqual(hidden.status, .used)
        XCTAssertEqual(hidden.visibilityReason, .uploadStarted)

        let reopened = try QueueStore(databaseURL: database)
        try await reopened.recoverInterruptedOperations()
        let recovered = try await refreshed(request, in: reopened)
        XCTAssertEqual(recovered.operation.phase, .unknown)
        let recoveredAdmission = SystemScreenshotCandidateAdmission(store: reopened)
        let admittedAfterRestart = try await recoveredAdmission.admits(recovered)
        XCTAssertTrue(admittedAfterRestart)
        let observer = try adapter(reopened, bridge)
        let complete = try await observer.reconcile(recovered)
        XCTAssertEqual(complete.outcome, .verifiedReady)
        XCTAssertEqual(complete.profileID, SystemScreenshotWebCandidate.admittedCompletionProfileID)
        XCTAssertTrue(complete.positiveReady)
        XCTAssertFalse(complete.safeToRetry)
        XCTAssertNil(complete.uploadStartEvidence)

        let stillUnresolved = try await reopened.apply(complete, policy: policy(start: true, completion: false))
        XCTAssertEqual(stillUnresolved.status, .unknown, "Start admission must not grant completion")
        XCTAssertEqual(stillUnresolved.visibility, .swallowed)
        let succeeded = try await reopened.apply(complete, policy: policy())
        XCTAssertEqual(succeeded.status, .used)
        XCTAssertEqual(succeeded.visibility, .swallowed)
        XCTAssertEqual(succeeded.visibilityRevision, hidden.visibilityRevision,
                       "Background completion must not perform another visual exit")
        let terminal = try await refreshed(request, in: reopened)
        XCTAssertEqual(terminal.operation.phase, .succeeded)
        let admittedTerminal = try await recoveredAdmission.admits(terminal)
        XCTAssertTrue(admittedTerminal)
        _ = try await observer.reconcile(terminal)
        let allActions = await bridge.actions
        XCTAssertEqual(allActions, firstActions + [.observe, .observe])
        let identities = await bridge.identities
        XCTAssertTrue(identities.allSatisfy { $0 == identity(request) })
        let retainedMarker = try await checkpoint(reopened, request)
        let savedStart = try await reopened.uploadStartReceipt(for: request.operation.id)
        XCTAssertEqual(retainedMarker, marker)
        XCTAssertEqual(savedStart, start)
    }

    func testCompletionOnlyPolicyCannotAdmitStartAndProductionDefaultsRemainClosed() async throws {
        let (store, request, _) = try await fixture()
        let bridge = AdmissionTestBridge(states: [.uploadStarted])
        let receipt = try await adapter(store, bridge).append(request)
        let result = try await store.apply(receipt, policy: policy(start: false, completion: true))
        XCTAssertEqual(result.status, .unknown); XCTAssertEqual(result.visibility, .visible)
        let recordedStart = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertNil(recordedStart)
        XCTAssertFalse(ReceiptPolicy().allowsUploadStart(receipt: receipt, asset: request.asset, mode: .production))
        XCTAssertTrue(ReceiptPolicy().admittedProfiles.isEmpty)
        XCTAssertTrue(ReceiptPolicy().uploadStartProfiles.isEmpty)
        XCTAssertTrue(policy().retrySafeProfiles.isEmpty)
    }

    func testAdapterWithoutExplicitAdmissionRetainsObservationOnlyProfiles() async throws {
        let (store, request, _) = try await fixture()
        let bridge = AdmissionTestBridge(states: [.uploadStarted, .attached])
        let client = try adapter(store, bridge, admitted: false)
        let start = try await client.append(request)
        XCTAssertEqual(start.uploadStartEvidence?.profileID, SystemScreenshotWebCandidate.uploadStartProfileID)
        let first = try await store.apply(start, policy: policy())
        XCTAssertEqual(first.status, .unknown); XCTAssertEqual(first.visibility, .visible)
        let complete = try await client.reconcile(try await refreshed(request, in: store))
        XCTAssertEqual(complete.profileID, SystemScreenshotWebCandidate.completionProfileID)
        let final = try await store.apply(complete, policy: policy())
        XCTAssertEqual(final.status, .unknown); XCTAssertEqual(final.visibility, .visible)
        let marker = try await checkpoint(store, request)
        let recordedStart = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertNil(marker); XCTAssertNil(recordedStart)
    }

    func testLegacyUnknownStartAndAttachedNeverAcquireAdmissionOrReleaseOriginalLock() async throws {
        let (store, original, _) = try await fixture()
        try await store.markUnknown(original.operation.id, reason: "Constructed F-style legacy UNKNOWN; never reinput")
        let bridge = AdmissionTestBridge(states: [.uploadStarted, .attached])
        let client = try adapter(store, bridge)
        for expected in [AttachmentObservedState.uploadStarted, .attached] {
            let request = try await refreshed(original, in: store)
            let receipt = try await client.reconcile(request)
            XCTAssertEqual(receipt.profileID, SystemScreenshotWebCandidate.completionProfileID)
            if expected == .uploadStarted {
                XCTAssertEqual(receipt.uploadStartEvidence?.profileID, SystemScreenshotWebCandidate.uploadStartProfileID)
            } else { XCTAssertTrue(receipt.positiveReady) }
            let record = try await store.apply(receipt, policy: policy())
            XCTAssertEqual(record.status, .unknown); XCTAssertEqual(record.visibility, .visible)
            XCTAssertEqual(record.activeOperationID, original.operation.id)
            XCTAssertFalse(receipt.safeToRetry)
        }
        let retained = try await refreshed(original, in: store)
        XCTAssertEqual(retained.operation.phase, .unknown)
        XCTAssertEqual(retained.operation.attempt, original.operation.attempt)
        await assertRejected { try await client.append(retained) }
        let actions = await bridge.actions
        XCTAssertEqual(actions, [.observe, .observe])
        let marker = try await checkpoint(store, original)
        let admittedStart = try await store.uploadStartReceipt(for: original.operation.id)
        let compensation = try await store.compensation(for: original.operation.id)
        XCTAssertNil(marker); XCTAssertNil(admittedStart); XCTAssertNil(compensation)
        let next = try await makeRequest(in: store, target: original.operation.target, dispatch: false)
        do { try await store.markDispatchIntent(next.operation.id); XCTFail("Legacy UNKNOWN released its target lock") }
        catch RiftletError.targetBusy {}
        let oldAfterBlockedClick = try await refreshed(original, in: store)
        XCTAssertEqual(oldAfterBlockedClick.operation, retained.operation)
    }

    func testLegacyReconcileDoesNotApplyNewInputTargetOrPNGScope() async throws {
        let local = LogicalDraftIdentity(profileID: "chatgpt-composer-react-20261027-v1",
            id: "local-chatgpt:00000000-0000-4000-8000-000000000002")
        for target in [AdmissionTestBridge.target(logical: nil), AdmissionTestBridge.target(logical: local)] {
            let (store, request, _) = try await fixture(target: target, bytes: AdmissionTestPNG.rgba16)
            try await store.markUnknown(request.operation.id, reason: "Constructed legacy scope fixture")
            let bridge = AdmissionTestBridge(states: [.attached])
            let receipt = try await adapter(store, bridge).reconcile(try await refreshed(request, in: store))
            XCTAssertEqual(receipt.profileID, SystemScreenshotWebCandidate.completionProfileID)
            let result = try await store.apply(receipt, policy: policy())
            XCTAssertEqual(result.status, .unknown); XCTAssertEqual(result.visibility, .visible)
            let actions = await bridge.actions
            let marker = try await checkpoint(store, request)
            XCTAssertEqual(actions, [.observe]); XCTAssertNil(marker)
        }
    }

    func testPreparedAndStaleDispatchSnapshotsCannotEnrollActualUnknown() async throws {
        let (preparedStore, prepared, _) = try await fixture(dispatch: false)
        let preparedAdmission = SystemScreenshotCandidateAdmission(store: preparedStore)
        await assertRejected { try await preparedAdmission.enroll(prepared) }
        let preparedMarker = try await checkpoint(preparedStore, prepared)
        XCTAssertNil(preparedMarker)

        // A forged dispatch snapshot must also be checked against actual SQLite.
        let forgedOperation = try replacing(prepared.operation, "phase", with: OperationPhase.dispatchIntent.rawValue)
        let forged = TransferRequest(operation: forgedOperation, asset: prepared.asset, fileURL: prepared.fileURL)
        await assertRejected { try await preparedAdmission.enroll(forged) }
        let actualPrepared = try await preparedStore.operation(id: prepared.operation.id)
        XCTAssertEqual(actualPrepared?.phase, .prepared)

        let (store, stale, _) = try await fixture()
        try await store.markUnknown(stale.operation.id, reason: "Actual phase advanced after captured request")
        let admission = SystemScreenshotCandidateAdmission(store: store)
        await assertRejected { try await admission.enroll(stale) }
        let current = try await refreshed(stale, in: store)
        await assertRejected { try await admission.enroll(current) }
        let bridge = AdmissionTestBridge(states: [.uploadStarted])
        await assertRejected { try await self.adapter(store, bridge).append(stale) }
        let marker = try await checkpoint(store, stale)
        let actions = await bridge.actions
        let record = try await store.asset(id: stale.asset.id)
        XCTAssertNil(marker); XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(record?.status, .unknown); XCTAssertEqual(record?.visibility, .visible)
        XCTAssertEqual(record?.activeOperationID, stale.operation.id)
    }

    func testEnrollmentChecksPersistentAssetAttemptEntireTargetAndStore() async throws {
        let (store, request, _) = try await fixture()
        let admission = SystemScreenshotCandidateAdmission(store: store)
        var altered: [TransferRequest] = []
        let operationChanges: [(String, Any)] = [("attempt", request.operation.attempt + 1),
                                                  ("assetID", UUID().uuidString)]
        for (field, value) in operationChanges {
            let operation = try replacing(request.operation, field, with: value)
            altered.append(TransferRequest(operation: operation, asset: request.asset, fileURL: request.fileURL))
        }
        for field in ["sessionID", "windowID", "tabID", "documentID", "composerID", "draftGeneration"] {
            let target = try replacing(request.operation.target, field, with: "changed-\(field)")
            let operation = try replacing(request.operation, "target", with: object(target))
            altered.append(TransferRequest(operation: operation, asset: request.asset, fileURL: request.fileURL))
        }
        let otherDraft = LogicalDraftIdentity(profileID: "chatgpt-composer-react-persisted-20261027-v1", id: UUID().uuidString)
        let target = try replacing(request.operation.target, "logicalDraftIdentity", with: object(otherDraft))
        let operation = try replacing(request.operation, "target", with: object(target))
        altered.append(TransferRequest(operation: operation, asset: request.asset, fileURL: request.fileURL))
        let assetChanges: [(String, Any)] = [("sha256", String(repeating: "b", count: 64)),
                                            ("pixelWidth", request.asset.pixelWidth + 1),
                                            ("id", UUID().uuidString)]
        for (field, value) in assetChanges {
            let asset = try replacing(request.asset, field, with: value)
            altered.append(TransferRequest(operation: request.operation, asset: asset, fileURL: request.fileURL))
        }
        for changed in altered {
            await assertRejected { try await admission.enroll(changed) }
            let marker = try await checkpoint(store, changed)
            XCTAssertNil(marker)
        }
        let otherStore = try QueueStore(databaseURL: directory.appendingPathComponent("foreign.sqlite"))
        let foreign = SystemScreenshotCandidateAdmission(store: otherStore)
        await assertRejected { try await foreign.enroll(request) }
        _ = try await otherStore.importAsset(request.asset)
        _ = try await otherStore.prepare(assetID: request.asset.id, target: request.operation.target)
        await assertRejected { try await foreign.enroll(request) }
        let foreignMarker = try await checkpoint(otherStore, request)
        let originalMarker = try await checkpoint(store, request)
        XCTAssertNil(foreignMarker); XCTAssertNil(originalMarker)

        try await admission.enroll(request)
        // These changes keep the same checkpoint key: a present marker must not
        // fall back to "legacy" or silently authorize a different full identity.
        for changed in altered where changed.operation.attempt == request.operation.attempt {
            await assertInvalidRequest { try await admission.admits(changed) }
        }
    }

    func testMissingCorruptAndForeignMarkersNeverAuthorizeInputOrGetReplaced() async throws {
        let (sourceStore, source, _) = try await fixture()
        try await SystemScreenshotCandidateAdmission(store: sourceStore).enroll(source)
        let savedForeignMarker = try await checkpoint(sourceStore, source)
        let foreignMarker = try XCTUnwrap(savedForeignMarker)
        for badMarker in [Data("invalid-json".utf8), Data("{}".utf8), foreignMarker] {
            let (store, request, _) = try await fixture()
            let admission = SystemScreenshotCandidateAdmission(store: store)
            let missing = try await admission.admits(request)
            XCTAssertFalse(missing)
            let key = SystemScreenshotCandidateAdmission.checkpointKey(for: request)
            try await store.saveCheckpoint(badMarker, for: key)
            await assertInvalidRequest { try await admission.admits(request) }
            await assertInvalidRequest { try await admission.enroll(request) }
            let bridge = AdmissionTestBridge(states: [.uploadStarted])
            await assertRejected { try await self.adapter(store, bridge).append(request) }
            let actions = await bridge.actions
            let retained = try await checkpoint(store, request)
            XCTAssertTrue(actions.isEmpty); XCTAssertEqual(retained, badMarker)
        }
    }

    func testConcurrentAdmissionInstancesClaimOnceAndCannotReplayAppend() async throws {
        let (store, request, _) = try await fixture()
        let first = SystemScreenshotCandidateAdmission(store: store)
        let second = SystemScreenshotCandidateAdmission(store: store)
        async let left = enrollmentSucceeded(first, request)
        async let right = enrollmentSucceeded(second, request)
        let (leftWon, rightWon) = await (left, right)
        XCTAssertEqual([leftWon, rightWon].filter { $0 }.count, 1)
        let before = try await checkpoint(store, request)
        XCTAssertNotNil(before)
        let accepted = try await first.admits(request)
        XCTAssertTrue(accepted)
        let bridge = AdmissionTestBridge(states: [.uploadStarted])
        await assertRejected { try await self.adapter(store, bridge).append(request) }
        let actions = await bridge.actions
        let after = try await checkpoint(store, request)
        XCTAssertTrue(actions.isEmpty); XCTAssertEqual(after, before)
    }

    func testExtendedNoncanonicalAndDuplicateKeyMarkersFailClosedOnReadOnlyObservation() async throws {
        let (store, request, _) = try await fixture()
        let admission = SystemScreenshotCandidateAdmission(store: store)
        try await admission.enroll(request)
        let saved = try await checkpoint(store, request)
        let canonical = try XCTUnwrap(saved)
        var extended = try XCTUnwrap(try JSONSerialization.jsonObject(with: canonical) as? [String: Any])
        extended["unreviewedAdmission"] = true
        let extraField = try JSONSerialization.data(withJSONObject: extended, options: [.sortedKeys])
        let whitespace = Data((" \n" + String(decoding: canonical, as: UTF8.self)).utf8)
        let duplicateKey = Data(("{\"version\":1," + String(decoding: canonical.dropFirst(), as: UTF8.self)).utf8)
        let bridge = AdmissionTestBridge(states: [.attached, .attached, .attached])
        let client = try adapter(store, bridge)
        for malformed in [extraField, whitespace, duplicateKey] {
            try await store.saveCheckpoint(malformed, for: SystemScreenshotCandidateAdmission.checkpointKey(for: request))
            await assertInvalidRequest { try await admission.admits(request) }
            await assertInvalidRequest { try await client.reconcile(request) }
            await assertInvalidRequest { try await client.append(request) }
            let retained = try await checkpoint(store, request)
            XCTAssertEqual(retained, malformed, "A bad registration must not be repaired or replaced during observation")
        }
        let actions = await bridge.actions
        XCTAssertEqual(actions, [.observe, .observe, .observe])
        let start = try await store.uploadStartReceipt(for: request.operation.id)
        XCTAssertNil(start)
    }

    func testUnsupportedHomeLocalUnknownDraftWorkAndNonChromeTargetsRefuseBeforeInput() async throws {
        let targets = [
            AdmissionTestBridge.target(logical: nil),
            AdmissionTestBridge.target(logical: .init(profileID: "chatgpt-composer-react-20261027-v1",
                id: "local-chatgpt:00000000-0000-4000-8000-000000000002")),
            AdmissionTestBridge.target(logical: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1", id: "not-a-uuid")),
            AdmissionTestBridge.target(logical: .init(profileID: "unreviewed-draft-profile", id: UUID().uuidString)),
            AdmissionTestBridge.target(surface: .webWork),
            AdmissionTestBridge.target(application: "com.apple.Safari"),
            AdmissionTestBridge.target(application: "com.google.Chrome.canary")
        ]
        for target in targets {
            let (store, request, _) = try await fixture(target: target)
            let bridge = AdmissionTestBridge(states: [.uploadStarted])
            await assertRejected { try await self.adapter(store, bridge).append(request) }
            let actions = await bridge.actions
            let marker = try await checkpoint(store, request)
            XCTAssertTrue(actions.isEmpty); XCTAssertNil(marker)
        }
    }

    func testUnsupportedPNGDepthColorAndCorruptFileRefuseBeforeEnrollmentOrInput() async throws {
        for bytes in [AdmissionTestPNG.rgb8, AdmissionTestPNG.rgba16, AdmissionTestPNG.gray8,
                      AdmissionTestPNG.rgba8Interlaced] {
            let (store, request, _) = try await fixture(bytes: bytes)
            let bridge = AdmissionTestBridge(states: [.uploadStarted])
            await assertRejected { try await self.adapter(store, bridge).append(request) }
            let actions = await bridge.actions
            let marker = try await checkpoint(store, request)
            XCTAssertTrue(actions.isEmpty); XCTAssertNil(marker)
        }
        let (store, request, _) = try await fixture()
        var damaged = AdmissionTestPNG.rgba8
        damaged[damaged.count - 1] ^= 1
        try damaged.write(to: request.fileURL)
        let bridge = AdmissionTestBridge(states: [.uploadStarted])
        await assertRejected { try await self.adapter(store, bridge).append(request) }
        let actions = await bridge.actions
        let marker = try await checkpoint(store, request)
        XCTAssertTrue(actions.isEmpty); XCTAssertNil(marker, "Full SHA verification must precede enrollment")
    }

    func testPassingAdmittedProfileDirectlyCannotBypassPerOperationAdmission() async throws {
        let (store, request, _) = try await fixture()
        let bridge = AdmissionTestBridge(states: [.uploadStarted])
        let client = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge,
            program: try ChatGPTWebPageProgram.load(), mode: .systemScreenshotCandidate,
            profile: SystemScreenshotWebCandidate.admittedProfile, polling: .disabled,
            candidateJournal: SystemScreenshotObservationJournal(store: store),
            candidateAdmission: SystemScreenshotCandidateAdmission(store: store))
        do { _ = try await client.append(request); XCTFail("Caller bypassed operation admission with a profile") }
        catch WebAdapterError.programUnavailable {}
        let actions = await bridge.actions
        let marker = try await checkpoint(store, request)
        XCTAssertTrue(actions.isEmpty); XCTAssertNil(marker)
    }

    private func policy(start: Bool = true, completion: Bool = true) -> ReceiptPolicy {
        ReceiptPolicy(admittedProfiles: completion ? [SystemScreenshotWebCandidate.admittedCompletionProfileID: .webChat] : [:],
            uploadStartProfiles: start ? [SystemScreenshotWebCandidate.admittedUploadStartProfileID: .webChat] : [:])
    }

    private func adapter(_ store: QueueStore, _ bridge: AdmissionTestBridge, admitted: Bool = true) throws -> WebAttachmentAdapter {
        WebAttachmentAdapter(mediaDirectory: directory, executor: bridge, program: try ChatGPTWebPageProgram.load(),
            mode: .systemScreenshotCandidate, profile: SystemScreenshotWebCandidate.profile, polling: .disabled,
            candidateJournal: SystemScreenshotObservationJournal(store: store),
            candidateAdmission: admitted ? SystemScreenshotCandidateAdmission(store: store) : nil)
    }

    private func fixture(target: TargetLease = AdmissionTestBridge.target(), bytes: Data = AdmissionTestPNG.rgba8,
                         dispatch: Bool = true) async throws -> (QueueStore, TransferRequest, URL) {
        let database = directory.appendingPathComponent("\(UUID()).sqlite")
        let store = try QueueStore(databaseURL: database)
        return (store, try await makeRequest(in: store, target: target, bytes: bytes, dispatch: dispatch), database)
    }

    private func makeRequest(in store: QueueStore, target: TargetLease, bytes: Data = AdmissionTestPNG.rgba8,
                             dispatch: Bool = true) async throws -> TransferRequest {
        let file = directory.appendingPathComponent("\(UUID()).png")
        try bytes.write(to: file)
        let image = ImportedAsset(sourceKey: "generated-admission-fixture-\(UUID())", fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(bytes.count),
            pixelWidth: 4, pixelHeight: 4, mediaType: "image/png", origin: .systemScreenshot)
        _ = try await store.importAsset(image)
        let prepared = try await store.prepare(assetID: image.id, target: target)
        if dispatch { try await store.markDispatchIntent(prepared.id) }
        let saved = try await store.operation(id: prepared.id)
        return TransferRequest(operation: try XCTUnwrap(saved), asset: image, fileURL: file)
    }

    private func refreshed(_ request: TransferRequest, in store: QueueStore) async throws -> TransferRequest {
        let saved = try await store.operation(id: request.operation.id)
        return TransferRequest(operation: try XCTUnwrap(saved), asset: request.asset, fileURL: request.fileURL)
    }

    private func checkpoint(_ store: QueueStore, _ request: TransferRequest) async throws -> Data? {
        try await store.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: request))
    }

    private func identity(_ request: TransferRequest) -> ObservationIdentity {
        ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
    }

    private func object<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private func replacing<T: Codable>(_ original: T, _ field: String, with value: Any) throws -> T {
        var encoded = try XCTUnwrap(try object(original) as? [String: Any])
        encoded[field] = value
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: encoded))
    }

    private func enrollmentSucceeded(_ admission: SystemScreenshotCandidateAdmission, _ request: TransferRequest) async -> Bool {
        do { try await admission.enroll(request); return true }
        catch { return false }
    }

    private func assertRejected<T>(_ action: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await action(); XCTFail("Unsafe action was accepted", file: file, line: line) }
        catch {}
    }

    private func assertInvalidRequest<T>(_ action: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await action(); XCTFail("Invalid identity/marker was accepted", file: file, line: line) }
        catch let error as WebAdapterError { XCTAssertEqual(error, .invalidRequest, file: file, line: line) }
        catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }
}

private actor AdmissionTestBridge: WebBridgeExecutor {
    private(set) var actions: [WebBridgeAction] = []
    private(set) var identities: [ObservationIdentity] = []
    private(set) var received = Data()
    private var states: [AttachmentObservedState]

    init(states: [AttachmentObservedState]) { self.states = states }

    static func target(surface: TargetSurface = .webChat, application: String = "com.google.Chrome",
                       logical: LogicalDraftIdentity? = .init(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                           id: "00000000-0000-4000-8000-000000000001")) -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: surface, applicationID: application,
            sessionID: "constructed-admission-session", windowID: "1", tabID: "2",
            documentID: "constructed-document", composerID: "constructed-composer", draftGeneration: "original-click",
            logicalDraftIdentity: logical)
    }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        actions.append(command.action)
        if let identity = command.identity { identities.append(identity) }
        switch command.action {
        case .begin: return try acknowledgement(command, next: 0)
        case .chunk:
            let chunk = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(command.chunkBase64)))
            received.append(chunk)
            return try acknowledgement(command, next: try XCTUnwrap(command.chunkIndex) + 1)
        case .commit, .observe:
            let state = states.isEmpty ? .unknown : states.removeFirst()
            let identity = try XCTUnwrap(command.identity)
            let start: ObservedUploadStart? = state == .uploadStarted ? .init(version: 1,
                signal: .correlatedProgress, evidenceID: "00000000-0000-4000-8000-000000000003", inputCount: 1,
                inputSequence: 1, startSequence: 3, previousProgress: 10, currentProgress: 20,
                inputObservedAtMS: 10, startObservedAtMS: 30) : nil
            let item = AttachmentObservation(identity: identity, state: state,
                attachmentID: "constructed-admission-attachment", exactImageIdentity: true,
                belongsToOriginalDraft: true, hasError: false, isUploading: start != nil, uploadStart: start)
            return try JSONEncoder().encode(AttachmentObservationEnvelope(schemaVersion: 2,
                provenance: .init(source: .integratedDevelopment, evidenceID: "constructed-admission-only"), observation: item))
        case .discard: return Data("{}".utf8)
        case .captureTarget, .validate:
            XCTFail("Direct append/reconcile test unexpectedly captured or validated another target")
            throw WebAdapterError.invalidRequest
        }
    }

    private func acknowledgement(_ command: WebBridgeCommand, next: Int) throws -> Data {
        let identity = try XCTUnwrap(command.identity)
        return try JSONSerialization.data(withJSONObject: [
            "operationID": identity.operationID.uuidString, "attempt": identity.attempt, "nextChunk": next
        ])
    }
}

private enum AdmissionTestPNG {
    // Independently generated 4 x 4 PNG fixtures with valid PNG chunks/CRCs and
    // zlib payloads. The RGBA fixture has alpha 128, so it is not an RGB image.
    static let rgba8 = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGNQ9q5oQMYMpAsAAO8CFmEhXyLHAAAAAElFTkSuQmCC")!
    static let rgb8 = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGNQ9q6AIwbiOABwsw5h98iXlgAAAABJRU5ErkJggg==")!
    static let rgba16 = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEEAYAAAD5YUI9AAAAFklEQVR4nGNQVvb2rqhoaMBFM9BeAQBiKSzB5Bi+NgAAAABJRU5ErkJggg==")!
    static let gray8 = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAAAAACMmsGiAAAADklEQVR4nGNQBgIGVAIAFfQCMTaM1KgAAAAASUVORK5CYII=")!
    static let rgba8Interlaced = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAAHe9q7oAAAAE0lEQVR4nGNQ9q5oYIATBBg4BQD7mxZhGFfEIAAAAABJRU5ErkJggg==")!
}
