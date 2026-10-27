import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Constructed observations only: these tests do not collect a system screenshot,
/// contact Chrome, prove an upload, or admit a production profile.
final class SystemScreenshotObservationJournalTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-candidate-audit-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture(origin: AssetOrigin = .systemScreenshot, dispatch: Bool = true) async throws -> (QueueStore, TransferRequest, URL) {
        let database = root.appendingPathComponent("\(UUID()).sqlite")
        let store = try QueueStore(databaseURL: database)
        let asset = ImportedAsset(sourceKey: "constructed-audit-fixture-\(UUID())", fileName: "fixture.png",
            sha256: String(repeating: "a", count: 64), byteCount: 100, pixelWidth: 4,
            pixelHeight: 4, mediaType: "image/png", origin: origin)
        _ = try await store.importAsset(asset)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "fixture-process", windowID: "fixture-window",
            tabID: "fixture-tab", documentID: "fixture-document", composerID: "fixture-composer",
            draftGeneration: "fixture-generation")
        let op = try await store.prepare(assetID: asset.id, target: target)
        if dispatch { try await store.markDispatchIntent(op.id) }
        let saved = try await store.operation(id: op.id)
        return (store, TransferRequest(operation: try XCTUnwrap(saved), asset: asset,
                                      fileURL: root.appendingPathComponent(asset.fileName)), database)
    }

    private func envelope(_ request: TransferRequest, state: AttachmentObservedState,
                          attachment: String = "fixture-attachment",
                          source: ObservationSource = .integratedDevelopment,
                          evidence: String = "constructed-journal-fixture-only",
                          exact: Bool = true) -> AttachmentObservationEnvelope {
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        let start = state == .uploadStarted ? ObservedUploadStart(version: 1, signal: .correlatedProgress,
            evidenceID: UUID().uuidString, inputCount: 1, inputSequence: 1, startSequence: 2,
            previousProgress: 10, currentProgress: 20, inputObservedAtMS: 10, startObservedAtMS: 20) : nil
        let item = AttachmentObservation(identity: identity, state: state,
            attachmentID: state == .unknown ? nil : attachment, exactImageIdentity: exact,
            belongsToOriginalDraft: true, hasError: state == .failed,
            isUploading: state == .uploadStarted, uploadStart: start)
        return AttachmentObservationEnvelope(schemaVersion: 2,
            provenance: .init(source: source, evidenceID: evidence), observation: item)
    }

    private func raw(_ store: QueueStore, _ request: TransferRequest,
                     _ slot: SystemScreenshotObservationJournal.Slot) async throws -> Data? {
        try await store.checkpoint(for: SystemScreenshotObservationJournal.checkpointKey(request, slot: slot))
    }

    private func saved(_ store: QueueStore, _ request: TransferRequest,
                       _ slot: SystemScreenshotObservationJournal.Slot) async throws -> AttachmentObservationEnvelope {
        let data = try await raw(store, request, slot)
        return try JSONDecoder().decode(SystemScreenshotObservationJournal.Entry.self,
                                        from: XCTUnwrap(data)).envelope
    }

    func testPreservesFirstSixCategoriesAcrossRestartWithoutChangingQueue() async throws {
        let (store, request, database) = try await fixture()
        let journal = SystemScreenshotObservationJournal(store: store)
        let originalAsset = try await store.asset(id: request.asset.id)
        let originalOperation = try await store.operation(id: request.operation.id)
        let states: [(AttachmentObservedState, SystemScreenshotObservationJournal.Slot)] = [
            (.inputTriggered, .input), (.uploadStarted, .start), (.attached, .attached),
            (.ready, .ready), (.failed, .errorOrInvalidated), (.unknown, .unknown)
        ]
        var first: [SystemScreenshotObservationJournal.Slot: AttachmentObservationEnvelope] = [:]
        for (state, slot) in states {
            let observation = envelope(request, state: state)
            first[slot] = observation
            try await journal.record(observation, for: request)
        }
        let reopened = try QueueStore(databaseURL: database)
        let recoveredJournal = SystemScreenshotObservationJournal(store: reopened)
        for (state, slot) in states {
            try await recoveredJournal.record(envelope(request, state: state, attachment: "later-observed-attachment"), for: request)
            let retained = try await saved(reopened, request, slot)
            XCTAssertEqual(retained, first[slot], "A later poll replaced the first candidate observation")
            XCTAssertEqual(retained.provenance.source, .integratedDevelopment)
        }
        let currentAsset = try await reopened.asset(id: request.asset.id)
        let currentOperation = try await reopened.operation(id: request.operation.id)
        let receipt = try await reopened.receipt(for: request.operation.id)
        let admittedStart = try await reopened.uploadStartReceipt(for: request.operation.id)
        XCTAssertEqual(currentAsset, originalAsset); XCTAssertEqual(currentOperation, originalOperation)
        XCTAssertNil(receipt); XCTAssertNil(admittedStart)
        XCTAssertEqual(currentAsset?.visibility, .visible)
        XCTAssertTrue(ReceiptPolicy().admittedProfiles.isEmpty)
        XCTAssertTrue(ReceiptPolicy().uploadStartProfiles.isEmpty)
        XCTAssertTrue(ReceiptPolicy().retrySafeProfiles.isEmpty)
    }

    func testWrongOriginProvenanceAndOriginalIdentityAreRejectedBeforeStorage() async throws {
        let (store, request, _) = try await fixture()
        let journal = SystemScreenshotObservationJournal(store: store)
        for source in [ObservationSource.syntheticFixture, .sanitizedReal] {
            do {
                try await journal.record(envelope(request, state: .attached, source: source), for: request)
                XCTFail("Wrong provenance admitted")
            } catch SystemScreenshotObservationJournalError.invalidProvenance {}
        }
        let (syntheticStore, synthetic, _) = try await fixture(origin: .synthetic)
        do {
            try await SystemScreenshotObservationJournal(store: syntheticStore).record(envelope(synthetic, state: .attached), for: synthetic)
            XCTFail("Generated origin entered real-capture audit")
        } catch SystemScreenshotObservationJournalError.invalidOrigin {}
        let base = envelope(request, state: .attached)
        for field in ["operationID", "assetID", "attempt", "assetSHA256", "target"] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
            var item = object["observation"] as! [String: Any]
            var identity = item["identity"] as! [String: Any]
            switch field {
            case "attempt": identity[field] = request.operation.attempt + 1
            case "assetSHA256": identity[field] = String(repeating: "b", count: 64)
            case "target":
                var target = identity[field] as! [String: Any]
                target["draftGeneration"] = "different-draft"; identity[field] = target
            default: identity[field] = UUID().uuidString
            }
            item["identity"] = identity; object["observation"] = item
            let changed = try ObservationDecoder.decode(JSONSerialization.data(withJSONObject: object))
            do { try await journal.record(changed, for: request); XCTFail(field) }
            catch SystemScreenshotObservationJournalError.identityMismatch {}
        }
        for slot in SystemScreenshotObservationJournal.Slot.allCases {
            let absent = try await raw(store, request, slot); XCTAssertNil(absent)
        }
    }

    func testCorruptConflictingOrDifferentCategoryCheckpointIsNeverOverwritten() async throws {
        let variants: [(AttachmentObservedState, (AttachmentObservationEnvelope) throws -> Data)] = [
            (.attached, { _ in Data("invalid-json".utf8) }),
            (.attached, { value in
                try JSONEncoder().encode(SystemScreenshotObservationJournal.Entry(schemaVersion: 2, envelope: value))
            }),
            (.attached, { value in
                let changed = AttachmentObservationEnvelope(schemaVersion: 2,
                    provenance: .init(source: .integratedDevelopment, evidenceID: "another-program-evidence"),
                    observation: value.observation)
                return try JSONEncoder().encode(SystemScreenshotObservationJournal.Entry(schemaVersion: 1, envelope: changed))
            }),
            (.attached, { value in
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
                var item = object["observation"] as! [String: Any]
                var identity = item["identity"] as! [String: Any]
                var target = identity["target"] as! [String: Any]
                target["sessionID"] = "different-process"
                identity["target"] = target; item["identity"] = identity; object["observation"] = item
                let changed = try ObservationDecoder.decode(JSONSerialization.data(withJSONObject: object))
                return try JSONEncoder().encode(SystemScreenshotObservationJournal.Entry(schemaVersion: 1, envelope: changed))
            }),
            (.ready, { value in
                try JSONEncoder().encode(SystemScreenshotObservationJournal.Entry(schemaVersion: 1, envelope: value))
            }),
            (.attached, { value in
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
                    SystemScreenshotObservationJournal.Entry(schemaVersion: 1, envelope: value))) as! [String: Any]
                var packet = object["envelope"] as! [String: Any]
                packet["safeToRetry"] = true; object["envelope"] = packet
                return try JSONSerialization.data(withJSONObject: object)
            })
        ]
        for (state, bytes) in variants {
            let (store, request, _) = try await fixture()
            let retained = try bytes(envelope(request, state: state))
            let key = SystemScreenshotObservationJournal.checkpointKey(request, slot: .attached)
            try await store.saveCheckpoint(retained, for: key)
            do {
                try await SystemScreenshotObservationJournal(store: store).record(envelope(request, state: .attached), for: request)
                XCTFail("Invalid first checkpoint was replaced")
            } catch is SystemScreenshotObservationJournalError {}
            let actual = try await raw(store, request, .attached)
            XCTAssertEqual(actual, retained)
        }
    }

    func testConcurrentObserversKeepOneAtomicFirstStart() async throws {
        let (store, request, _) = try await fixture()
        let first = envelope(request, state: .uploadStarted)
        let second = envelope(request, state: .uploadStarted)
        let a = SystemScreenshotObservationJournal(store: store)
        let b = SystemScreenshotObservationJournal(store: store)
        async let left: Void = a.record(first, for: request)
        async let right: Void = b.record(second, for: request)
        _ = try await (left, right)
        let retained = try await saved(store, request, .start)
        XCTAssertTrue(retained == first || retained == second)
        let originalBytes = try await raw(store, request, .start)
        for _ in 0..<20 { try await a.record(envelope(request, state: .uploadStarted), for: request) }
        let afterPolling = try await raw(store, request, .start)
        XCTAssertEqual(afterPolling, originalBytes)
    }

    func testUnprovedAttachmentDoesNotBecomeCleanCompletionEvidence() async throws {
        let (store, request, _) = try await fixture()
        let journal = SystemScreenshotObservationJournal(store: store)
        try await journal.record(envelope(request, state: .attached, exact: false), for: request)
        let absent = try await raw(store, request, .attached); XCTAssertNil(absent)
        let firstUnknown = envelope(request, state: .unknown)
        try await journal.record(firstUnknown, for: request)
        for _ in 0..<20 { try await journal.record(envelope(request, state: .unknown), for: request) }
        let retained = try await saved(store, request, .unknown)
        XCTAssertEqual(retained, firstUnknown)
        let invalidated = envelope(request, state: .invalidated)
        try await journal.record(invalidated, for: request)
        try await journal.record(envelope(request, state: .failed), for: request)
        let firstError = try await saved(store, request, .errorOrInvalidated)
        XCTAssertEqual(firstError, invalidated)
        let asset = try await store.asset(id: request.asset.id)
        XCTAssertEqual(asset?.visibility, .visible)
        XCTAssertEqual(asset?.status, .transferring)
    }

    func testSimulationStoreCannotHostSystemCandidateEvidence() async throws {
        let (_, request, _) = try await fixture()
        let store = try QueueStore(databaseURL: root.appendingPathComponent("simulation.sqlite"), mode: .simulation)
        do {
            try await SystemScreenshotObservationJournal(store: store).record(envelope(request, state: .attached), for: request)
            XCTFail("Simulation store accepted a real-capture audit")
        } catch SystemScreenshotObservationJournalError.wrongStoreMode {}
    }

    func testPreparedSelectionCannotManufactureAnUploadObservation() async throws {
        let (store, request, _) = try await fixture(dispatch: false)
        do {
            try await SystemScreenshotObservationJournal(store: store).record(envelope(request, state: .uploadStarted), for: request)
            XCTFail("A not-yet-dispatched selection acquired an upload observation")
        } catch SystemScreenshotObservationJournalError.invalidOperation {}
        let absent = try await raw(store, request, .start); XCTAssertNil(absent)
        let operation = try await store.operation(id: request.operation.id)
        XCTAssertEqual(operation?.phase, .prepared)
    }

    func testMissingOrDifferentStoreIdentityCannotRecordOrReplaceEvidence() async throws {
        let (store, request, _) = try await fixture()
        let journal = SystemScreenshotObservationJournal(store: store)
        let first = envelope(request, state: .uploadStarted)
        try await journal.record(first, for: request)
        let firstBytes = try await raw(store, request, .start)

        let empty = try QueueStore(databaseURL: root.appendingPathComponent("empty.sqlite"))
        let other = try QueueStore(databaseURL: root.appendingPathComponent("other.sqlite"))
        _ = try await other.importAsset(request.asset)
        let otherOperation = try await other.prepare(assetID: request.asset.id, target: request.operation.target)
        try await other.markDispatchIntent(otherOperation.id)
        for wrongStore in [empty, other] {
            do {
                try await SystemScreenshotObservationJournal(store: wrongStore).record(first, for: request)
                XCTFail("An unpersisted operation entered another queue's audit")
            } catch SystemScreenshotObservationJournalError.persistentIdentityMismatch {}
            let absent = try await raw(wrongStore, request, .start)
            XCTAssertNil(absent)
        }

        // The receipt identity omits pixel metadata. A self-consistent forged
        // request still must match the exact immutable ImportedAsset in SQLite.
        let image = request.asset
        let differentImage = ImportedAsset(id: image.id, sourceKey: image.sourceKey,
            fileName: image.fileName, sha256: image.sha256, byteCount: image.byteCount,
            pixelWidth: image.pixelWidth + 1, pixelHeight: image.pixelHeight, mediaType: image.mediaType,
            capturedAt: image.capturedAt, firstSeenAt: image.firstSeenAt,
            importedAt: image.importedAt, origin: image.origin)
        let forged = TransferRequest(operation: request.operation, asset: differentImage, fileURL: request.fileURL)
        do {
            try await journal.record(envelope(forged, state: .uploadStarted), for: forged)
            XCTFail("Receipt-shaped identity hid different persisted asset metadata")
        } catch SystemScreenshotObservationJournalError.persistentIdentityMismatch {}

        // A later durable phase is valid; only immutable identity must match the
        // in-flight request snapshot, not its previous dispatchIntent phase.
        try await store.markUnknown(request.operation.id, reason: "constructed recovery boundary")
        try await journal.record(envelope(request, state: .uploadStarted), for: request)
        let retained = try await raw(store, request, .start)
        XCTAssertEqual(retained, firstBytes)
    }
}
