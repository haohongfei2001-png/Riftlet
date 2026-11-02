import Foundation
import XCTest
@testable import RiftletCore

/// These are deterministic transport scheduling tests. The manual clock models
/// network START deadlines; it is not a substitute for AppKit latency evidence.
final class InputObservationPipelineTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("input-pipeline-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func store() throws -> QueueStore {
        try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
    }

    private func asset(_ store: QueueStore) async throws -> ImportedAsset {
        let id = UUID(), bytes = Data("isolated pipeline fixture \(UUID())".utf8)
        let image = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count),
            pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        try bytes.write(to: directory.appendingPathComponent(image.fileName))
        _ = try await store.importAsset(image)
        return image
    }

    private func target(draft: Int = 1, tab: String = "1", document: String = "document-1",
                        window: String = "1", recognized: Bool = true, pin: UUID? = UUID()) -> TargetLease {
        TargetLease(adapterID: "input-pipeline-fixture", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "fixture-process", windowID: window, tabID: tab, documentID: document,
            composerID: "composer-\(document)", draftGeneration: "generation-\(document)",
            logicalDraftIdentity: recognized ? .init(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                id: "00000000-0000-0000-0000-" + String(format: "%012d", draft)) : nil,
            clickBindingID: pin)
    }

    private func selection(_ image: ImportedAsset, target: TargetLease) -> AcceptedSelection {
        let now = ProcessInfo.processInfo.systemUptime, pinned = target.clickBindingID != nil
        return AcceptedSelection(assetID: image.id, target: target, hostEpoch: UUID(),
            acknowledgedUptime: now - (pinned ? 0.005 : 0.02), eventUptime: now - 0.01,
            acceptedUptime: now, visibilityRevision: 0, deadlineUptime: now + 30,
            authorization: pinned ? .nativeClickPin : .preEventAcknowledgement)
    }

    private func coordinator(_ store: QueueStore, _ adapter: PipelineAdapter,
                             _ changes: PipelinePersistence,
                             validator: @escaping @Sendable (AcceptedSelection) async -> Bool = { $0.isValid() }) -> TransferCoordinator {
        TransferCoordinator(store: store, adapter: adapter, mediaDirectory: directory,
            policy: ReceiptPolicy(syntheticAcceptanceProfiles: ["pipeline-ready": .webChat],
                syntheticUploadStartProfiles: ["pipeline-start": .webChat]),
            onChange: { await changes.changed() }, validateAcceptedSelection: validator)
    }

    private func operation(_ image: ImportedAsset, _ store: QueueStore) async throws -> TransferOperation {
        let record = try await store.asset(id: image.id)
        let id = try XCTUnwrap(record?.activeOperationID)
        let operation = try await store.operation(id: id)
        return try XCTUnwrap(operation)
    }

    private func call(_ operation: TransferOperation, _ store: QueueStore) async throws -> DispatchCallRecord {
        let data = try await store.checkpoint(for: "transfer-dispatch-call-v1:" + operation.id.uuidString)
        return try JSONDecoder().decode(DispatchCallRecord.self, from: XCTUnwrap(data))
    }

    func testIndependentBInputsBeforeAStartAt1001000And3000MillisecondDeadlines() async throws {
        for delay: UInt64 in [100, 1_000, 3_000] {
            let store = try store(), a = try await asset(store), b = try await asset(store)
            let clock = PipelineClock(), changes = PipelinePersistence(store: store)
            let bInput = expectation(description: "B input before A START at \(delay) ms")
            let adapter = PipelineAdapter(clock: clock) { event, asset in
                if event == .input && asset == b.id { bInput.fulfill() }
            }
            await adapter.configure(a.id, .init(confirmation: delay == 1_000 ? .started : .exact, startAt: delay))
            await adapter.configure(b.id, .init(final: .verifiedReady))
            let coordinator = coordinator(store, adapter, changes)
            let aReturned = expectation(description: "A selection ends at its input boundary")
            let first = Task {
                try await coordinator.select(selection(a, target: target(pin: delay == 3_000 ? nil : UUID())))
                aReturned.fulfill()
            }
            await fulfillment(of: [aReturned], timeout: 5)
            let second = Task {
                try await coordinator.select(selection(b,
                    target: target(draft: 2, tab: "2", document: "document-2",
                        window: delay == 1_000 ? "2" : "1", pin: delay == 3_000 ? nil : UUID())))
            }
            await fulfillment(of: [bInput], timeout: 5)
            let bFinished = await changes.expect(b.id, .phase(.succeeded))
            await fulfillment(of: [bFinished], timeout: 5)
            let beforeA = try await operation(a, store), aRecord = try await store.asset(id: a.id)
            let beforeCall = try await call(beforeA, store), beforeStart = try await store.uploadStartReceipt(for: beforeA.id)
            let inputs = await adapter.inputs(), elapsed = await clock.now
            XCTAssertEqual(inputs, [a.id, b.id]); XCTAssertEqual(elapsed, 0)
            XCTAssertEqual(beforeA.phase, .dispatchIntent)
            XCTAssertEqual(aRecord?.visibility, .visible, "Input confirmation is not upload-start admission")
            XCTAssertNil(beforeStart); XCTAssertNil(beforeCall.returnedReceipt)

            let aStarted = await changes.expect(a.id, .started)
            await clock.advance(to: delay)
            await fulfillment(of: [aStarted], timeout: 5)
            try await first.value; try await second.value
            let afterA = try await operation(a, store), originalCall = try await call(afterA, store)
            let originalStart = try await store.uploadStartReceipt(for: afterA.id)
            XCTAssertEqual(originalCall.returnedReceipt, originalStart)
            XCTAssertEqual(originalCall.returnedReceipt?.outcome, .uploadStarted)
            XCTAssertEqual(originalCall.target, beforeA.target)
            XCTAssertEqual(originalCall.invocationID, beforeCall.invocationID)
        }
    }

    func testUnconfirmedCommitCannotBeOvertakenByIndependentB() async throws {
        let store = try store(), a = try await asset(store), b = try await asset(store)
        let clock = PipelineClock(), changes = PipelinePersistence(store: store)
        let entered = expectation(description: "A uncertain input entered")
        let bInput = expectation(description: "B runs only after original append settles")
        let adapter = PipelineAdapter(clock: clock) { event, asset in
            if event == .input && asset == a.id { entered.fulfill() }
            if event == .input && asset == b.id { bInput.fulfill() }
        }
        await adapter.configure(a.id, .init(confirmation: .none, startAt: 1_000, final: .unknown))
        await adapter.configure(b.id, .init(final: .verifiedReady))
        let coordinator = coordinator(store, adapter, changes)
        let first = Task { try await coordinator.select(selection(a, target: target())) }
        await fulfillment(of: [entered], timeout: 5)
        try await coordinator.select(selection(b, target: target(draft: 2, tab: "2", document: "document-2")))
        let before = await adapter.inputs(), bPrepared = try await operation(b, store)
        XCTAssertEqual(before, [a.id]); XCTAssertEqual(bPrepared.phase, .prepared)
        let bCall = try await store.dispatchInvocationID(for: bPrepared.id)
        XCTAssertNil(bCall)
        await clock.advance(to: 1_000)
        await fulfillment(of: [bInput], timeout: 5)
        let aUnknown = await changes.expect(a.id, .phase(.unknown))
        let bFinished = await changes.expect(b.id, .phase(.succeeded))
        await fulfillment(of: [aUnknown, bFinished], timeout: 5)
        try await first.value
        let after = await adapter.inputs()
        XCTAssertEqual(after, [a.id, b.id])
    }

    func testMismatchedAndNonInputCallbacksCannotReleaseInputBoundary() async throws {
        for invalid in [PipelineConfirmation.wrongOperation, .wrongAsset, .wrongAttempt, .wrongHash,
                        .wrongTarget, .notOriginal, .unknown, .error] {
            let store = try store(), a = try await asset(store), b = try await asset(store)
            let clock = PipelineClock(), changes = PipelinePersistence(store: store)
            let callback = expectation(description: "Invalid phase offered: \(invalid)")
            let adapter = PipelineAdapter(clock: clock) { event, asset in
                if event == .confirmed && asset == a.id { callback.fulfill() }
            }
            await adapter.configure(a.id, .init(confirmation: invalid, startAt: 1_000, final: .unknown))
            await adapter.configure(b.id, .init(final: .verifiedReady))
            let coordinator = coordinator(store, adapter, changes)
            let first = Task { try await coordinator.select(selection(a, target: target())) }
            await fulfillment(of: [callback], timeout: 5)
            try await coordinator.select(selection(b, target: target(draft: 2, tab: "2", document: "document-2")))
            let inputs = await adapter.inputs(), before = try await operation(b, store)
            XCTAssertEqual(inputs, [a.id], "\(invalid)"); XCTAssertEqual(before.phase, .prepared)
            try await coordinator.cancelPendingSelections(reason: "Fixture cancels original unsubmitted B")
            let settled = await changes.expect(a.id, .phase(.unknown))
            await clock.advance(to: 1_000)
            await fulfillment(of: [settled], timeout: 5)
            try await first.value
        }
    }

    func testSharedOrUnprovenDraftsCannotCrossAnActiveAppend() async throws {
        let cases = [
            target(), // Same draft, different native click pin.
            target(tab: "2", document: "document-2"), // Same business ID in another tab.
            target(draft: 2, tab: "2", document: "document-2", recognized: false),
            target(draft: 2), // Another business spelling reusing the active input document.
            target(draft: 2, tab: "2") // Different tab alone does not prove another document.
        ]
        for heldTarget in cases {
            let store = try store(), a = try await asset(store), b = try await asset(store)
            let clock = PipelineClock(), changes = PipelinePersistence(store: store)
            let adapter = PipelineAdapter(clock: clock)
            await adapter.configure(a.id, .init(startAt: 3_000))
            let coordinator = coordinator(store, adapter, changes)
            let firstReturned = expectation(description: "A input phase released")
            let first = Task {
                try await coordinator.select(selection(a, target: target()))
                firstReturned.fulfill()
            }
            await fulfillment(of: [firstReturned], timeout: 5)
            try await coordinator.select(selection(b, target: heldTarget))
            let inputs = await adapter.inputs(), bOperation = try await operation(b, store)
            let bInvocation = try await store.dispatchInvocationID(for: bOperation.id)
            XCTAssertEqual(inputs, [a.id]); XCTAssertEqual(bOperation.phase, .prepared); XCTAssertNil(bInvocation)
            try await coordinator.cancelPendingSelections(reason: "Fixture cancels held B without input")
            let aStarted = await changes.expect(a.id, .started)
            await clock.advance(to: 3_000)
            await fulfillment(of: [aStarted], timeout: 5)
            try await first.value
            let after = await adapter.inputs()
            XCTAssertEqual(after, [a.id])
        }
    }

    func testDuplicateACallbackCannotReleaseBAndLetCOvertakeUnconfirmedB() async throws {
        let store = try store(), a = try await asset(store), b = try await asset(store), c = try await asset(store)
        let clock = PipelineClock(), changes = PipelinePersistence(store: store)
        let aReturned = expectation(description: "A confirmed"), bEntered = expectation(description: "B uncertain input")
        let cInput = expectation(description: "C only after B settles")
        let adapter = PipelineAdapter(clock: clock) { event, asset in
            if event == .input && asset == b.id { bEntered.fulfill() }
            if event == .input && asset == c.id { cInput.fulfill() }
        }
        await adapter.configure(a.id, .init(startAt: 3_000))
        await adapter.configure(b.id, .init(confirmation: .none, startAt: 1_000, final: .unknown))
        await adapter.configure(c.id, .init(final: .verifiedReady))
        let coordinator = coordinator(store, adapter, changes)
        let first = Task {
            try await coordinator.select(selection(a, target: target()))
            aReturned.fulfill()
        }
        await fulfillment(of: [aReturned], timeout: 5)
        let second = Task { try await coordinator.select(selection(b,
            target: target(draft: 2, tab: "2", document: "document-2"))) }
        await fulfillment(of: [bEntered], timeout: 5)
        try await coordinator.select(selection(c, target: target(draft: 3, tab: "3", document: "document-3")))
        await adapter.repeatConfirmation(a.id)
        let before = await adapter.inputs(), cOperation = try await operation(c, store)
        XCTAssertEqual(before, [a.id, b.id]); XCTAssertEqual(cOperation.phase, .prepared)
        await clock.advance(to: 1_000)
        await fulfillment(of: [cInput], timeout: 5)
        let aStarted = await changes.expect(a.id, .started), cFinished = await changes.expect(c.id, .phase(.succeeded))
        await clock.advance(to: 3_000)
        await fulfillment(of: [aStarted, cFinished], timeout: 5)
        try await first.value; try await second.value
        let after = await adapter.inputs()
        XCTAssertEqual(after, [a.id, b.id, c.id])
    }

    func testBackgroundObservationAndDuplicateClickCannotReenterLiveAppend() async throws {
        let store = try store(), a = try await asset(store), clock = PipelineClock()
        let changes = PipelinePersistence(store: store), adapter = PipelineAdapter(clock: clock)
        await adapter.configure(a.id, .init(startAt: 3_000))
        let coordinator = coordinator(store, adapter, changes)
        try await coordinator.select(selection(a, target: target()))
        let original = try await operation(a, store)
        try await coordinator.observePending()
        try await coordinator.select(selection(a, target: original.target))
        let inputs = await adapter.inputs(), observations = await adapter.observations()
        let same = try await operation(a, store), checkpoint = try await call(same, store)
        XCTAssertEqual(inputs, [a.id]); XCTAssertEqual(observations, [])
        XCTAssertEqual(same.id, original.id); XCTAssertEqual(same.attempt, 1)
        XCTAssertNil(checkpoint.returnedReceipt)
        let started = await changes.expect(a.id, .started)
        await clock.advance(to: 3_000)
        await fulfillment(of: [started], timeout: 5)
    }

    func testLateACompletionAndFailureCannotChangeSuccessfulBOrRepeatInput() async throws {
        let store = try store(), a = try await asset(store), b = try await asset(store)
        let clock = PipelineClock(), changes = PipelinePersistence(store: store), adapter = PipelineAdapter(clock: clock)
        await adapter.configure(a.id, .init(startAt: 1_000, final: .verifiedReady))
        await adapter.configure(b.id, .init(final: .verifiedReady))
        let coordinator = coordinator(store, adapter, changes)
        try await coordinator.select(selection(a, target: target()))
        try await coordinator.select(selection(b, target: target(draft: 2, tab: "2", document: "document-2")))
        let bFinished = await changes.expect(b.id, .phase(.succeeded))
        await fulfillment(of: [bFinished], timeout: 5)
        let bBefore = try await operation(b, store), aFinished = await changes.expect(a.id, .phase(.succeeded))
        await clock.advance(to: 1_000)
        await fulfillment(of: [aFinished], timeout: 5)
        await adapter.setObservation(a.id, .definitiveFailure)
        let aOperation = try await operation(a, store)
        _ = try await coordinator.observeCompleted(operationID: aOperation.id)
        let aAfter = try await operation(a, store), bAfter = try await operation(b, store), inputs = await adapter.inputs()
        XCTAssertEqual(aAfter.phase, .compensated); XCTAssertEqual(bAfter, bBefore)
        XCTAssertEqual(inputs, [a.id, b.id])
    }

    func testLostAppendReceiptRemainsUnknownAcrossRecoveryAndDuplicateClicks() async throws {
        let store = try store(), a = try await asset(store), b = try await asset(store)
        let clock = PipelineClock(), changes = PipelinePersistence(store: store), adapter = PipelineAdapter(clock: clock)
        await adapter.configure(a.id, .init(startAt: 1_000, throwsAfterInput: true))
        await adapter.configure(b.id, .init(final: .verifiedReady))
        let coordinator = coordinator(store, adapter, changes)
        try await coordinator.select(selection(a, target: target()))
        try await coordinator.select(selection(b, target: target(draft: 2, tab: "2", document: "document-2")))
        let aUnknown = await changes.expect(a.id, .phase(.unknown)), bFinished = await changes.expect(b.id, .phase(.succeeded))
        await clock.advance(to: 1_000)
        await fulfillment(of: [aUnknown, bFinished], timeout: 5)
        let original = try await operation(a, store), originalCall = try await call(original, store)
        XCTAssertNil(originalCall.returnedReceipt)
        let replacement = self.coordinator(store, adapter, changes)
        try await replacement.recover()
        try await replacement.select(selection(a, target: original.target))
        let after = try await operation(a, store), afterCall = try await call(after, store), inputs = await adapter.inputs()
        XCTAssertEqual(after.id, original.id); XCTAssertEqual(after.attempt, original.attempt)
        XCTAssertEqual(after.phase, .unknown); XCTAssertEqual(afterCall, originalCall)
        XCTAssertEqual(inputs, [a.id, b.id])
    }

    func testPostIntentAssetReadFailureRetainsUnknownWithoutInputAndDoesNotStrandIndependentB() async throws {
        let databaseURL = directory.appendingPathComponent("post-intent-read.sqlite")
        let store = try QueueStore(databaseURL: databaseURL), a = try await asset(store), b = try await asset(store)
        let fault = try SQLiteDatabase(url: databaseURL)
        let originalImage = try XCTUnwrap(fault.rows("SELECT image_json FROM assets WHERE id=?", [a.id.uuidString]).first?.first ?? nil)
        // The trigger runs inside the real dispatch-intent transaction, after
        // the original asset has passed validation but before its post-intent
        // reread. This touches only the disposable fixture, with no product hook.
        try fault.execute("""
            CREATE TRIGGER corrupt_original_image_after_intent AFTER UPDATE OF phase ON operations
            WHEN NEW.phase='dispatchIntent' AND NEW.asset_id='\(a.id.uuidString)'
            BEGIN UPDATE assets SET image_json='not-json' WHERE id=NEW.asset_id; END
            """)
        let clock = PipelineClock(), changes = PipelinePersistence(store: store), adapter = PipelineAdapter(clock: clock)
        await adapter.configure(b.id, .init(final: .verifiedReady))
        let coordinator = coordinator(store, adapter, changes)
        try await coordinator.select(selection(a, target: target()))
        let unresolved = try await store.unresolvedOperations()
        let aOperation = try XCTUnwrap(unresolved.first { $0.assetID == a.id })
        let beforeInputs = await adapter.inputs(), originalCall = try await call(aOperation, store)
        XCTAssertEqual(aOperation.phase, .unknown); XCTAssertEqual(beforeInputs, [])
        XCTAssertNil(originalCall.returnedReceipt)
        let reason = try await store.operationReason(for: aOperation.id)
        XCTAssertEqual(reason, "Original request unavailable after input intent")

        // Restore the faulted fixture row, not the operation. UNKNOWN and its
        // one-shot invocation remain intact while a new independent click runs.
        try fault.execute("DROP TRIGGER corrupt_original_image_after_intent")
        try fault.execute("UPDATE assets SET image_json=? WHERE id=?", [originalImage, a.id.uuidString])
        try await coordinator.select(selection(b, target: target(draft: 2, tab: "2", document: "document-2")))
        let bFinished = await changes.expect(b.id, .phase(.succeeded))
        await fulfillment(of: [bFinished], timeout: 5)
        let afterA = try await operation(a, store), afterCall = try await call(afterA, store), finalInputs = await adapter.inputs()
        XCTAssertEqual(afterA.id, aOperation.id); XCTAssertEqual(afterA.phase, .unknown)
        XCTAssertEqual(afterCall, originalCall); XCTAssertEqual(finalInputs, [b.id])
    }

    func testPreparedBRemovalCancellationAndPermissionLossSurviveLateAInputConfirmation() async throws {
        for change in ["remove", "cancel", "permission"] {
            let store = try store(), a = try await asset(store), b = try await asset(store)
            let clock = PipelineClock(), changes = PipelinePersistence(store: store), authority = PipelineAuthority()
            let aEntered = expectation(description: "A input entered before B \(change)")
            let adapter = PipelineAdapter(clock: clock) { event, asset in
                if event == .input && asset == a.id { aEntered.fulfill() }
            }
            await adapter.configure(a.id, .init(confirmation: .none, startAt: 1_000))
            let coordinator = coordinator(store, adapter, changes, validator: { await authority.allows($0) })
            let first = Task { try await coordinator.select(selection(a, target: target())) }
            await fulfillment(of: [aEntered], timeout: 5)
            let bSelection = selection(b, target: target(draft: 2, tab: "2", document: "document-2"))
            try await coordinator.select(bSelection)
            let prepared = try await operation(b, store)
            XCTAssertEqual(prepared.phase, .prepared)
            switch change {
            case "remove": try await store.removeFromQueue(b.id)
            case "cancel":
                bSelection.cancel()
                try await coordinator.cancelAcceptedSelections(ids: [bSelection.id], reason: "Original B cancelled")
            default: await authority.deny(b.id)
            }
            // A's authentic late phase callback releases only A's lane; it is
            // not renewed authority for the already prepared B transaction.
            await adapter.repeatConfirmation(a.id)
            let bRetired = await changes.expect(b.id, .phase(.failed))
            await fulfillment(of: [bRetired], timeout: 5)
            let retired = try await operation(b, store), bInvocation = try await store.dispatchInvocationID(for: retired.id)
            let inputs = await adapter.inputs()
            XCTAssertEqual(retired.id, prepared.id); XCTAssertNil(bInvocation); XCTAssertEqual(inputs, [a.id])
            let aStarted = await changes.expect(a.id, .started)
            await clock.advance(to: 1_000)
            await fulfillment(of: [aStarted], timeout: 5)
            try await first.value
            let finalInputs = await adapter.inputs()
            XCTAssertEqual(finalInputs, [a.id])
        }
    }
}

private enum PipelineConfirmation: Equatable, Sendable {
    case exact, started, none, wrongOperation, wrongAsset, wrongAttempt, wrongHash, wrongTarget, notOriginal, unknown, error
}

private struct PipelinePlan: Sendable {
    var confirmation: PipelineConfirmation = .exact
    var startAt: UInt64 = 0
    var final: ReceiptOutcome = .uploadStarted
    var throwsAfterInput = false
}

private enum PipelineEvent: Equatable, Sendable { case input, confirmed }

private actor PipelineClock {
    private(set) var now: UInt64 = 0
    private var waiting: [(UInt64, CheckedContinuation<Void, Never>)] = []
    func wait(until deadline: UInt64) async {
        guard deadline > now else { return }
        await withCheckedContinuation { waiting.append((deadline, $0)) }
    }
    func advance(to time: UInt64) {
        now = max(time, now)
        let ready = waiting.filter { $0.0 <= now }
        waiting.removeAll { $0.0 <= now }
        for (_, continuation) in ready { continuation.resume() }
    }
}

private actor PipelineAuthority {
    private var denied = Set<UUID>()
    func deny(_ asset: UUID) { denied.insert(asset) }
    func allows(_ selection: AcceptedSelection) -> Bool {
        selection.isValid() && !denied.contains(selection.assetID)
    }
}

private actor PipelineAdapter: InputPhasedAttachmentAdapter {
    nonisolated let id = "input-pipeline-fixture"
    private let clock: PipelineClock
    private let event: @Sendable (PipelineEvent, UUID) -> Void
    private var plans: [UUID: PipelinePlan] = [:]
    private var appended: [UUID] = []
    private var observed: [UUID] = []
    private var observationOutcomes: [UUID: ReceiptOutcome] = [:]
    private var callbacks: [UUID: (@Sendable (TransferReceipt) async -> Void)] = [:]
    private var requests: [UUID: TransferRequest] = [:]

    init(clock: PipelineClock, event: @escaping @Sendable (PipelineEvent, UUID) -> Void = { _, _ in }) {
        self.clock = clock; self.event = event
    }
    func configure(_ asset: UUID, _ plan: PipelinePlan) { plans[asset] = plan }
    func inputs() -> [UUID] { appended }
    func observations() -> [UUID] { observed }
    func setObservation(_ asset: UUID, _ outcome: ReceiptOutcome) { observationOutcomes[asset] = outcome }
    func captureTarget() throws -> TargetLease { XCTFail("Frozen clicks cannot recapture"); throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { true }
    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try await append(request, onInputConfirmed: { _ in })
    }
    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt {
        let plan = plans[request.asset.id] ?? PipelinePlan()
        requests[request.asset.id] = request; callbacks[request.asset.id] = onInputConfirmed
        appended.append(request.asset.id); event(.input, request.asset.id)
        if plan.confirmation != .none {
            let phaseOutcome: ReceiptOutcome = plan.confirmation == .unknown ? .unknown
                : plan.confirmation == .started ? .uploadStarted : .inputTriggered
            await onInputConfirmed(receipt(request, outcome: phaseOutcome,
                confirmation: plan.confirmation))
            event(.confirmed, request.asset.id)
        }
        await clock.wait(until: plan.startAt)
        if plan.throwsAfterInput { throw RiftletError.invalidTransition }
        return receipt(request, outcome: plan.final)
    }
    func repeatConfirmation(_ asset: UUID) async {
        guard let request = requests[asset], let callback = callbacks[asset] else { return }
        await callback(receipt(request, outcome: .inputTriggered))
    }
    func reconcile(_ request: TransferRequest) -> TransferReceipt {
        observed.append(request.asset.id)
        return receipt(request, outcome: observationOutcomes[request.asset.id] ?? .unknown)
    }
    private func receipt(_ request: TransferRequest, outcome: ReceiptOutcome,
                         confirmation: PipelineConfirmation = .exact) -> TransferReceipt {
        let target = request.operation.target
        let invalidTarget = TargetLease(adapterID: target.adapterID, surface: target.surface,
            applicationID: target.applicationID, sessionID: target.sessionID, windowID: "not-original-window",
            tabID: target.tabID, documentID: target.documentID, composerID: target.composerID,
            draftGeneration: target.draftGeneration, logicalDraftIdentity: target.logicalDraftIdentity,
            clickBindingID: target.clickBindingID)
        return TransferReceipt(operationID: confirmation == .wrongOperation ? UUID() : request.operation.id,
            assetID: confirmation == .wrongAsset ? UUID() : request.asset.id,
            attempt: request.operation.attempt + (confirmation == .wrongAttempt ? 1 : 0),
            assetSHA256: confirmation == .wrongHash ? String(repeating: "b", count: 64) : request.asset.sha256,
            target: confirmation == .wrongTarget ? invalidTarget : target,
            outcome: outcome, profileID: "pipeline-ready", attachmentID: "attachment-\(request.operation.id)",
            positiveReady: outcome == .verifiedReady, belongsToOriginalDraft: confirmation != .notOriginal,
            hasError: confirmation == .error || outcome == .definitiveFailure,
            isUploading: outcome == .uploadStarted,
            uploadStartEvidence: outcome == .uploadStarted ? .init(profileID: "pipeline-start",
                signal: .correlatedProgress, evidenceID: "start-\(request.operation.id)") : nil)
    }
}

private actor PipelinePersistence {
    enum Condition: Sendable { case phase(OperationPhase), started }
    private struct Goal { let asset: UUID; let condition: Condition; let expectation: XCTestExpectation }
    private let store: QueueStore
    private var goals: [UUID: Goal] = [:]
    init(store: QueueStore) { self.store = store }
    func expect(_ asset: UUID, _ condition: Condition) async -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Persisted \(condition) for \(asset)")
        goals[UUID()] = Goal(asset: asset, condition: condition, expectation: expectation)
        await changed()
        return expectation
    }
    func changed() async {
        for (id, goal) in goals {
            guard let record = try? await store.asset(id: goal.asset),
                  let operationID = record.activeOperationID,
                  let operation = try? await store.operation(id: operationID) else { continue }
            let matches: Bool
            switch goal.condition {
            case .phase(let phase): matches = operation.phase == phase
            case .started:
                let checkpoint = try? await store.checkpoint(for: "transfer-dispatch-call-v1:" + operationID.uuidString)
                let call = checkpoint.flatMap { try? JSONDecoder().decode(DispatchCallRecord.self, from: $0) }
                let start = try? await store.uploadStartReceipt(for: operationID)
                matches = start != nil && call?.returnedReceipt == start
            }
            if matches, goals.removeValue(forKey: id) != nil { goal.expectation.fulfill() }
        }
    }
}
