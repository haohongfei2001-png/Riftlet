import Foundation
import XCTest
@testable import RiftletCore

final class AcceptedSelectionQueueTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("accepted-selection-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func store() throws -> QueueStore { try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite")) }
    private func asset(_ store: QueueStore) async throws -> ImportedAsset {
        let id = UUID(), data = Data("synthetic fixture".utf8)
        let image = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: Int64(data.count), pixelWidth: 1,
            pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try data.write(to: directory.appendingPathComponent(image.fileName))
        _ = try await store.importAsset(image); return image
    }
    private func target(_ generation: String = "original") -> TargetLease {
        TargetLease(adapterID: "accepted-fixture", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "fixture-session", windowID: "1", tabID: "2", documentID: "document",
            composerID: "composer", draftGeneration: generation)
    }
    private func token(_ image: ImportedAsset, target: TargetLease? = nil, duration: Double = 10,
                       revision: Int64 = 0) -> AcceptedSelection {
        let now = ProcessInfo.processInfo.systemUptime
        return AcceptedSelection(assetID: image.id, target: target ?? self.target(), hostEpoch: UUID(),
            acknowledgedUptime: now - 0.002, eventUptime: now - 0.001, acceptedUptime: now, visibilityRevision: revision,
            deadlineUptime: now + duration, captureRequestID: UUID(), armAttemptID: UUID())
    }
    private func coordinator(_ store: QueueStore, _ adapter: ParkAdapter, capacity: Int = 12,
                             change: @escaping @Sendable () async -> Void = {},
                             validator: @escaping @Sendable (AcceptedSelection) async -> Bool = { $0.isValid() }) -> TransferCoordinator {
        TransferCoordinator(store: store, adapter: adapter, mediaDirectory: directory,
            policy: ReceiptPolicy(admittedProfiles: ["ready": .webChat],
                                  syntheticUploadStartProfiles: ["start": .webChat]), onChange: change,
            maximumPendingSelections: capacity, validateAcceptedSelection: validator)
    }
    private func operation(_ image: ImportedAsset, _ store: QueueStore) async throws -> TransferOperation {
        let record = try await store.asset(id: image.id)
        let id = try XCTUnwrap(record?.activeOperationID)
        let op = try await store.operation(id: id); return try XCTUnwrap(op)
    }

    func testACKMustStrictlyPrecedeOriginalEventAndCannotBeFilledAfterward() async throws {
        let s = try store(), image = try await asset(s), now = ProcessInfo.processInfo.systemUptime
        for ack in [now, now + 0.001, Double.nan, -1] {
            let invalid = AcceptedSelection(assetID: image.id, target: target(), hostEpoch: UUID(),
                acknowledgedUptime: ack, eventUptime: now, acceptedUptime: now,
                visibilityRevision: 0, deadlineUptime: now + 10)
            XCTAssertFalse(invalid.isValid(at: now))
            let adapter = ParkAdapter(), coordinator = coordinator(s, adapter)
            do { try await coordinator.select(invalid); XCTFail("Late/missing ACK accepted") } catch {}
            let record = try await s.asset(id: image.id), inputs = await adapter.inputs()
            XCTAssertNil(record?.activeOperationID); XCTAssertEqual(inputs, [])
        }
        let prior = AcceptedSelection(assetID: image.id, target: target(), hostEpoch: UUID(),
            acknowledgedUptime: now - 0.000001, eventUptime: now, acceptedUptime: now,
            visibilityRevision: 0, deadlineUptime: now + 10)
        XCTAssertTrue(prior.isValid(at: now))
    }

    func testSameDraftParksVisibleThenReconcileReleasesOriginalFIFOWithoutCapture() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), c = try await asset(s)
        let adapter = ParkAdapter(), coordinator = coordinator(s, adapter)
        try await coordinator.select(token(a)); let second = token(b), third = token(c)
        try await coordinator.select(second); try await coordinator.select(third)
        let before = try await operation(b, s), bRecord = try await s.asset(id: b.id)
        XCTAssertEqual(before.phase, .prepared); XCTAssertEqual(bRecord?.visibility, .visible)
        let initial = await adapter.inputs(); XCTAssertEqual(initial, [a.id])
        await adapter.complete(a.id); try await coordinator.observePending()
        let after = try await operation(b, s), stillWaiting = try await operation(c, s)
        XCTAssertEqual(after.id, before.id); XCTAssertEqual(after.attempt, 1); XCTAssertEqual(after.target, second.target)
        XCTAssertEqual(stillWaiting.phase, .prepared)
        let middle = await adapter.inputs(); XCTAssertEqual(middle, [a.id, b.id])
        await adapter.complete(b.id); try await coordinator.observePending()
        let final = await adapter.inputs(), captures = await adapter.captures
        XCTAssertEqual(final, [a.id, b.id, c.id]); XCTAssertEqual(captures, 0)
    }

    func testUnknownAndWrongIdentityCannotReleaseDraftOrCreateAnotherAttempt() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), adapter = ParkAdapter()
        let coordinator = coordinator(s, adapter)
        try await coordinator.select(token(a)); try await coordinator.select(token(b))
        await adapter.wrongIdentity(a.id); try await coordinator.observePending()
        let aOp = try await operation(a, s), bOp = try await operation(b, s)
        XCTAssertEqual(aOp.phase, .unknown); XCTAssertEqual(bOp.phase, .prepared)
        do { try await coordinator.select(a.id, frozenTarget: nil) } catch {}
        let nextA = try await operation(a, s), inputs = await adapter.inputs()
        XCTAssertEqual(nextA.id, aOp.id); XCTAssertEqual(nextA.attempt, 1); XCTAssertEqual(inputs, [a.id])
        try await coordinator.cancelPendingSelections(reason: "test cleanup")
    }

    func testCancellationDuringSuspendedValidationPreventsIntentEvenWithoutActorCancelDelivery() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), adapter = ParkAdapter()
        let coordinator = coordinator(s, adapter); try await coordinator.select(token(a))
        let gate = ParkGate(); await adapter.suspendValidation(gate)
        let selection = token(b), task = Task { try await coordinator.select(selection) }
        await gate.waitForEntry(); selection.cancel() // synchronous App epoch/permission revocation
        await gate.release(); try await task.value
        let bOp = try await operation(b, s), inputs = await adapter.inputs()
        XCTAssertEqual(bOp.phase, .failed); XCTAssertEqual(inputs, [a.id])
    }

    func testAcceptedReclickChecksPermissionBeforeObservingOriginalUnknown() async throws {
        let s = try store(), image = try await asset(s), adapter = ParkAdapter()
        let original = try await s.prepare(assetID: image.id, target: target())
        try await s.markDispatchIntent(original.id)
        try await s.markUnknown(original.id, reason: "Original input has no conclusive receipt")
        let before = try await operation(image, s), record = try await s.asset(id: image.id)
        let reason = try await s.operationReason(for: original.id)
        let denied = coordinator(s, adapter, validator: { _ in false })
        let refusedClick = token(image)
        do { try await denied.select(refusedClick); XCTFail("Revoked permission observed the old operation") }
        catch RiftletError.invalidTransition { }
        XCTAssertFalse(refusedClick.isValid())
        let after = try await operation(image, s), unchanged = try await s.asset(id: image.id)
        let afterReason = try await s.operationReason(for: original.id)
        let observations = await adapter.observations, inputs = await adapter.inputs(), captures = await adapter.captures
        XCTAssertEqual(after, before); XCTAssertEqual(unchanged, record); XCTAssertEqual(afterReason, reason)
        XCTAssertEqual(observations, 0); XCTAssertEqual(inputs, []); XCTAssertEqual(captures, 0)

        // A later genuine click with fresh permission may observe the same
        // operation. It neither revives the cancelled token nor inputs again.
        let allowed = coordinator(s, adapter)
        await adapter.complete(image.id)
        try await allowed.select(token(image))
        let completed = try await operation(image, s), finalInputs = await adapter.inputs()
        let finalObservations = await adapter.observations
        XCTAssertEqual(completed.id, original.id); XCTAssertEqual(completed.attempt, 1)
        XCTAssertEqual(completed.phase, .succeeded); XCTAssertEqual(finalInputs, [])
        XCTAssertEqual(finalObservations, 1); XCTAssertFalse(refusedClick.isValid())
    }

    func testRemovedOrHiddenWaitingSelectionDoesNotDispatchAfterACompletes() async throws {
        for remove in [true, false] {
            let sub = directory.appendingPathComponent(UUID().uuidString)
            let s = try QueueStore(databaseURL: sub), a = try await asset(s), b = try await asset(s)
            let adapter = ParkAdapter(), coordinator = coordinator(s, adapter)
            try await coordinator.select(token(a)); try await coordinator.select(token(b))
            if remove { try await s.removeFromQueue(b.id) } else { try await s.setUserHidden(true) }
            await adapter.complete(a.id); try await coordinator.observePending()
            let bOp = try await operation(b, s), record = try await s.asset(id: b.id), inputs = await adapter.inputs()
            XCTAssertEqual(bOp.phase, .failed); XCTAssertEqual(inputs, [a.id])
            XCTAssertEqual(record?.visibility, remove ? .removed : .visible)
        }
    }

    func testChangedTargetAndRevokedHostPermissionCancelOriginalPrepared() async throws {
        for hostRevocation in [true, false] {
            let s = try QueueStore(databaseURL: directory.appendingPathComponent(UUID().uuidString))
            let a = try await asset(s), b = try await asset(s), adapter = ParkAdapter(), authority = ParkAuthority()
            let coordinator = coordinator(s, adapter, validator: { token in await authority.allows(token) })
            try await coordinator.select(token(a)); try await coordinator.select(token(b))
            if hostRevocation { await authority.revoke() } else { await adapter.invalidateTarget() }
            await adapter.complete(a.id); try await coordinator.observePending()
            let bOp = try await operation(b, s), inputs = await adapter.inputs()
            XCTAssertEqual(bOp.phase, .failed); XCTAssertEqual(inputs, [a.id]); XCTAssertEqual(bOp.target, target())
        }
    }

    func testDeadlineCancelsPreparedWhileOriginalUnknownRemainsLocked() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), adapter = ParkAdapter()
        let coordinator = coordinator(s, adapter)
        try await coordinator.select(token(a)); try await coordinator.select(token(b, duration: 0.05))
        try await Task.sleep(nanoseconds: 150_000_000)
        let bOp = try await operation(b, s), aOp = try await operation(a, s), inputs = await adapter.inputs()
        XCTAssertEqual(bOp.phase, .failed); XCTAssertTrue(aOp.phase.isUnresolved); XCTAssertEqual(inputs, [a.id])
        await adapter.complete(a.id); try await coordinator.observePending()
        let after = await adapter.inputs(); XCTAssertEqual(after, [a.id])
    }

    func testRestartCancelsPreparedWithoutRestoringTokenOrInput() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), adapter = ParkAdapter()
        let first = coordinator(s, adapter); try await first.select(token(a)); try await first.select(token(b))
        let before = try await operation(b, s)
        let reopened = try store(), freshAdapter = ParkAdapter(), restarted = coordinator(reopened, freshAdapter)
        try await restarted.recover()
        let after = try await operation(b, reopened), inputs = await freshAdapter.inputs()
        XCTAssertEqual(after.id, before.id); XCTAssertEqual(after.attempt, 1); XCTAssertEqual(after.phase, .failed)
        XCTAssertTrue(inputs.isEmpty)
        try await first.cancelPendingSelections(reason: "old runtime stopped")
    }

    func testBoundedCapacityRejectsExtraClickBeforePreparationAndStopCancelsWaiting() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), c = try await asset(s), adapter = ParkAdapter()
        let coordinator = coordinator(s, adapter, capacity: 1)
        try await coordinator.select(token(a)); try await coordinator.select(token(b))
        do { try await coordinator.select(token(c)); XCTFail("Unbounded waiting") } catch {}
        let record = try await s.asset(id: c.id); XCTAssertNil(record?.activeOperationID)
        try await coordinator.cancelPendingSelections(reason: "host stopped")
        await adapter.complete(a.id); try await coordinator.observePending()
        let bOp = try await operation(b, s), inputs = await adapter.inputs()
        XCTAssertEqual(bOp.phase, .failed); XCTAssertEqual(inputs, [a.id])
    }

    func testCompletionDuringParkedOnChangeDoesNotLoseDrainWake() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), adapter = ParkAdapter(), gate = ParkChangeGate()
        let coordinator = coordinator(s, adapter, change: { await gate.changed() })
        try await coordinator.select(token(a))
        let resumedInput = expectation(description: "Original B input resumes after reentrant terminal receipt")
        await adapter.observeInputs { id in if id == b.id { resumedInput.fulfill() } }
        await gate.blockAfterChanges(2) // preparation refresh, then targetBusy refresh
        let selection = Task { try await coordinator.select(self.token(b)) }
        await gate.waitForEntry()
        await adapter.complete(a.id)
        try await coordinator.observePending() // drain re-enters while its previous onChange awaits
        await gate.release(); try await selection.value
        // Task.yield is not a scheduling/completion fence under parallel CI.
        // Await the actual resumed append event, with a bounded failure timeout.
        await fulfillment(of: [resumedInput], timeout: 5)
        let inputs = await adapter.inputs(); XCTAssertEqual(inputs, [a.id, b.id])
    }

    func testOriginalRecoverySnapshotDoesNotResetNewPreparedSelection() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), adapter = ParkAdapter()
        let coordinator = coordinator(s, adapter)
        try await coordinator.select(token(a))
        let original = try await operation(a, s)
        try await s.recoverInterruptedOperations()
        try await coordinator.select(token(b))
        let before = try await operation(b, s)
        try await coordinator.recoverOriginalObservations(operationIDs: [original.id])
        let after = try await operation(b, s), inputs = await adapter.inputs()
        XCTAssertEqual(before.id, after.id); XCTAssertEqual(after.phase, .prepared)
        XCTAssertEqual(inputs, [a.id])
        try await coordinator.cancelPendingSelections(reason: "cleanup")
    }

    func testLateCancellationIDsDoNotCancelNewAcceptedClick() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), adapter = ParkAdapter()
        let coordinator = coordinator(s, adapter)
        try await coordinator.select(token(a)); let old = token(b)
        try await coordinator.select(old); old.cancel()
        try await coordinator.cancelAcceptedSelections(ids: [old.id], reason: "epoch changed")
        let fresh = token(b); try await coordinator.select(fresh)
        try await coordinator.cancelAcceptedSelections(ids: [old.id], reason: "late repeated cancellation")
        await adapter.complete(a.id); try await coordinator.observePending()
        let inputs = await adapter.inputs(), op = try await operation(b, s)
        XCTAssertEqual(inputs, [a.id, b.id]); XCTAssertEqual(op.attempt, 2)
    }

    func testIntentDatabaseFailureCannotDowngradeRevokedAcceptedSlotToLegacyDispatch() async throws {
        let s = try store(), b = try await asset(s), c = try await asset(s), adapter = ParkAdapter()
        let db = try SQLiteDatabase(url: directory.appendingPathComponent("queue.sqlite"))
        try db.execute("CREATE TRIGGER fail_intent BEFORE UPDATE OF phase ON operations WHEN NEW.phase='dispatchIntent' BEGIN SELECT RAISE(ABORT,'injected intent failure'); END")
        let coordinator = coordinator(s, adapter), original = token(b)
        do { try await coordinator.select(original); XCTFail("Injected transaction error disappeared") } catch {}
        let prepared = try await operation(b, s)
        XCTAssertEqual(prepared.phase, .prepared); XCTAssertFalse(original.isValid())
        try db.execute("DROP TRIGGER fail_intent")
        // A new independent click wakes the old FIFO slot after the DB recovers.
        try await coordinator.select(token(c))
        let retired = try await operation(b, s), inputs = await adapter.inputs()
        XCTAssertEqual(retired.id, prepared.id); XCTAssertEqual(retired.attempt, 1)
        XCTAssertEqual(retired.phase, .failed); XCTAssertEqual(inputs, [c.id])
    }

    func testAcceptedSettledCallbackCarriesExactTokenAndNeverLegacyAssetOnlyCallback() async throws {
        let s = try store(), a = try await asset(s), b = try await asset(s), adapter = ParkAdapter()
        let calls = ParkSettledCalls()
        let coordinator = TransferCoordinator(store: s, adapter: adapter, mediaDirectory: directory,
            policy: ReceiptPolicy(admittedProfiles: ["ready": .webChat], syntheticUploadStartProfiles: ["start": .webChat]),
            onSelectionSettled: { await calls.legacy($0) },
            onAcceptedSelectionSettled: { await calls.accepted($0.id) },
            validateAcceptedSelection: { $0.isValid() })
        let first = token(a), second = token(b)
        try await coordinator.select(first); try await coordinator.select(second)
        let accepted = await calls.tokens, legacy = await calls.assets
        XCTAssertEqual(accepted, [first.id, second.id]); XCTAssertEqual(legacy, [])
        try await coordinator.cancelPendingSelections(reason: "cleanup")
    }

    func testStoreChecksRevisionAndExactTargetInsideIntentAndRevokedTokenStaysUnusable() async throws {
        let s = try store(), b = try await asset(s)
        let op = try await s.prepare(assetID: b.id, target: target())
        for bad in [token(b, target: target("new-generation")), token(b, revision: 1)] {
            do { try await s.markDispatchIntent(op.id, selection: bad); XCTFail("Wrong original binding admitted") } catch {}
        }
        let revoked = token(b); revoked.cancel()
        do { try await s.markDispatchIntent(op.id, selection: revoked); XCTFail("Revoked token admitted") } catch {}
        let current = try await s.operation(id: op.id); XCTAssertEqual(current?.phase, .prepared)
        let original = token(b); try await s.markDispatchIntent(op.id, selection: original)
        XCTAssertFalse(original.isValid())
    }
}

private actor ParkAuthority {
    private var valid = true
    func revoke() { valid = false }
    func allows(_ token: AcceptedSelection) -> Bool { valid && token.isValid() }
}

private actor ParkGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func waitForEntry() async { while !entered { await Task.yield() } }
    func release() { continuation?.resume(); continuation = nil }
}

private actor ParkChangeGate {
    private let gate = ParkGate()
    private var remaining: Int?
    func blockAfterChanges(_ n: Int) { remaining = n }
    func changed() async {
        guard let n = remaining else { return }
        remaining = n - 1
        if n == 1 { remaining = nil; await gate.pause() }
    }
    func waitForEntry() async { await gate.waitForEntry() }
    func release() async { await gate.release() }
}

private actor ParkAdapter: AttachmentAdapter {
    nonisolated let id = "accepted-fixture"
    private var appended: [UUID] = []
    private var inputObserver: (@Sendable (UUID) -> Void)?
    func observeInputs(_ observer: @escaping @Sendable (UUID) -> Void) { inputObserver = observer }
    private var finished = Set<UUID>()
    private var wrong = Set<UUID>()
    private var targetValid = true
    private var validationGate: ParkGate?
    private(set) var captures = 0
    private(set) var observations = 0
    func captureTarget() throws -> TargetLease { captures += 1; throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) async -> Bool {
        if let gate = validationGate { validationGate = nil; await gate.pause() }
        return targetValid
    }
    func suspendValidation(_ gate: ParkGate) { validationGate = gate }
    func invalidateTarget() { targetValid = false }
    func complete(_ asset: UUID) { finished.insert(asset) }
    func wrongIdentity(_ asset: UUID) { wrong.insert(asset) }
    func inputs() -> [UUID] { appended }
    func append(_ request: TransferRequest) -> TransferReceipt {
        appended.append(request.asset.id)
        inputObserver?(request.asset.id)
        return receipt(request)
    }
    func reconcile(_ request: TransferRequest) -> TransferReceipt { observations += 1; return receipt(request) }
    private func receipt(_ request: TransferRequest) -> TransferReceipt {
        let ready = finished.contains(request.asset.id)
        return TransferReceipt(operationID: wrong.contains(request.asset.id) ? UUID() : request.operation.id,
            assetID: request.asset.id, attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
            target: request.operation.target, outcome: ready ? .verifiedReady : .uploadStarted,
            profileID: "ready", attachmentID: "attachment-\(request.operation.id)", positiveReady: ready,
            belongsToOriginalDraft: true, isUploading: !ready,
            uploadStartEvidence: ready ? nil : UploadStartEvidence(profileID: "start", signal: .correlatedProgress,
                                                                  evidenceID: request.operation.id.uuidString))
    }
}

private actor ParkSettledCalls {
    private(set) var tokens: [UUID] = []
    private(set) var assets: [UUID] = []
    func accepted(_ id: UUID) { tokens.append(id) }
    func legacy(_ id: UUID) { assets.append(id) }
}
