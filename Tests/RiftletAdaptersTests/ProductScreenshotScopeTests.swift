import CryptoKit
import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// Generated files/disposable SQLite only, not live screenshot or upload evidence.
final class ProductScreenshotScopeTests: XCTestCase {
    private var root: URL!
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGNQ9q5oQMYMpAsAAO8CFmEhXyLHAAAAAElFTkSuQmCC")!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-product-scope-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func target(local: Bool = false) -> TargetLease {
        let uuid = "00000000-0000-4000-8000-000000000001"
        let logical = LogicalDraftIdentity(
            profileID: local ? "chatgpt-composer-react-20261027-v1" : "chatgpt-composer-react-persisted-20261027-v1",
            id: local ? "local-chatgpt:" + uuid : uuid)
        return TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "constructed-product-session", windowID: "1", tabID: "2",
            documentID: "original-document", composerID: "original-composer", draftGeneration: "original-epoch",
            logicalDraftIdentity: logical, clickBindingID: UUID())
    }
    private func fixture(origin: AssetOrigin = .systemScreenshot, local: Bool = false)
        async throws -> (QueueStore, TransferRequest, URL) {
        let database = root.appendingPathComponent("\(UUID()).sqlite")
        let store = try QueueStore(databaseURL: database)
        let file = root.appendingPathComponent("\(UUID()).png"); try png.write(to: file)
        let asset = ImportedAsset(sourceKey: "constructed-product-source-\(UUID())", fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(png.count),
            pixelWidth: 4, pixelHeight: 4, mediaType: "image/png", origin: origin)
        _ = try await store.importAsset(asset)
        let prepared = try await store.prepare(assetID: asset.id, target: target(local: local))
        try await store.markDispatchIntent(prepared.id)
        let operation = try await store.operation(id: prepared.id)
        return (store, TransferRequest(operation: try XCTUnwrap(operation), asset: asset, fileURL: file), database)
    }
    private func envelope(_ request: TransferRequest) -> AttachmentObservationEnvelope {
        AttachmentObservationEnvelope(
            provenance: .init(source: .integratedDevelopment, evidenceID: "constructed-product-journal"),
            observation: .init(identity: .init(operationID: request.operation.id, assetID: request.asset.id,
                attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target),
                state: .inputTriggered, belongsToOriginalDraft: true))
    }
    private func refreshed(_ request: TransferRequest, store: QueueStore) async throws -> TransferRequest {
        let operation = try await store.operation(id: request.operation.id)
        return TransferRequest(operation: try XCTUnwrap(operation), asset: request.asset, fileURL: request.fileURL)
    }
    private func reject<T>(_ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await body(); XCTFail("Unqualified source/operation accepted", file: file, line: line) } catch {}
    }

    func testOlderFencedRowsAndFirstJournalEntriesSurviveV17ReadOnlyReconciliation() async throws {
        let program = try ChatGPTWebPageProgram.load()
        XCTAssertEqual(program.sourceID, "chatgpt-web-screenshot-handoff-20261105-v17")
        let scopes: [SystemScreenshotAdmissionScope] = [.candidate, .ordinary, .ordinaryCurrentDraftInternal, .productSystem, .productApplication]
        let versions = [("chatgpt-web-attachment-entry-20261105-v15", "attachment-entry-20261105-v15"),
                        ("chatgpt-web-attachment-handoff-20261105-v16", "attachment-handoff-20261105-v16")]
        for (scope, (source, evidence)) in scopes.flatMap({ scope in versions.map { (scope, $0) } }) {
            let (store, request, database) = try await fixture(origin: scope.origin)
            let identity = envelope(request).observation.identity
            // The v15 writer encoded these fields using JSONEncoder.sortedKeys
            // into both the scoped key and the original cross-scope fence.
            var registration: [String: Any] = ["version": scope.isProduct ? 2 : 1, "sourceID": source,
                "startProfileID": try XCTUnwrap(scope.admittedProfile.uploadStartProfileID),
                "completionProfileID": scope.admittedProfile.profileID, "enrollmentID": UUID().uuidString,
                "identity": try JSONSerialization.jsonObject(with: JSONEncoder().encode(identity))]
            if scope.isProduct { registration["assetOrigin"] = scope.origin.rawValue }
            let bytes = try JSONSerialization.data(withJSONObject: registration, options: [.sortedKeys])
            let key = SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: scope)
            let fence = SystemScreenshotCandidateAdmission.checkpointKey(for: request)
            for name in Set([key, fence]) {
                _ = try await store.claimDispatchCheckpoint(bytes, for: name, operation: request.operation, asset: request.asset)
            }
            let admission = SystemScreenshotCandidateAdmission(store: store, scope: scope)
            await reject { try await admission.enroll(request) }
            let item = AttachmentObservation(identity: identity, state: .unknown, belongsToOriginalDraft: true)
            let prior = AttachmentObservationEnvelope(provenance: .init(source: .integratedDevelopment,
                evidenceID: evidence), observation: item)
            let current = AttachmentObservationEnvelope(provenance: .init(source: .integratedDevelopment,
                evidenceID: "screenshot-handoff-20261105-v17"), observation: item)
            let journal = SystemScreenshotObservationJournal(store: store, scope: scope)
            try await journal.record(prior, for: request)
            let journalKey = SystemScreenshotObservationJournal.checkpointKey(request, slot: .unknown, scope: scope)
            let priorJournal = try await store.checkpoint(for: journalKey)
            XCTAssertNotNil(priorJournal)
            await reject { try await journal.record(current, for: request) } // A live write never uses the compatibility path.
            try await store.markUnknown(request.operation.id, reason: "existing v15 observation")
            let reopened = try QueueStore(databaseURL: database)
            let original = try await refreshed(request, store: reopened)
            let bridge = V15ReadOnlyBridge(response: try JSONEncoder().encode(current))
            let client = WebAttachmentAdapter(mediaDirectory: root, executor: bridge, program: program,
                mode: scope.isProduct ? .ordinaryProduct : scope == .candidate ? .systemScreenshotCandidate : .ordinarySystemScreenshot,
                profile: scope.isProduct ? OrdinaryProductScreenshotScope.systemProfile : scope.legacyProfile, polling: .disabled,
                candidateJournal: scope.isProduct ? nil : SystemScreenshotObservationJournal(store: reopened, scope: scope),
                candidateAdmission: scope.isProduct ? nil : SystemScreenshotCandidateAdmission(store: reopened, scope: scope),
                productStore: scope.isProduct ? reopened : nil, productOrigins: scope.isProduct ? [scope.origin] : [])
            let receipt = try await client.reconcile(original)
            XCTAssertEqual(receipt.outcome, .unknown); XCTAssertEqual(receipt.profileID, scope.admittedProfile.profileID)
            let actions = await bridge.actions; XCTAssertEqual(actions, [.observe])
            for name in Set([key, fence]) { let saved = try await reopened.checkpoint(for: name); XCTAssertEqual(saved, bytes) }
            let savedJournal = try await reopened.checkpoint(for: journalKey), saved = try await reopened.operation(id: request.operation.id)
            XCTAssertEqual(savedJournal, priorJournal); XCTAssertEqual(saved, original.operation)
            XCTAssertEqual(try Data(contentsOf: request.fileURL), png)
        }
    }

    func testProductUsesCollectorCapacityWhileRestrictedCandidateKeepsItsOwnBounds() async throws {
        let scopes: [SystemScreenshotAdmissionScope] = [.productSystem, .productApplication]
        XCTAssertNotEqual(scopes[0].admittedProfile.profileID, scopes[1].admittedProfile.profileID)
        XCTAssertNotEqual(scopes[0].admittedProfile.uploadStartProfileID, scopes[1].admittedProfile.uploadStartProfileID)
        for scope in scopes {
            let (_, request, _) = try await fixture(origin: scope.origin)
            try scope.validateMetadata(request.asset)
            try SystemScreenshotWebCandidate.preflight(request.asset, fileURL: request.fileURL, mediaDirectory: root,
                restrictedAdmission: true, expectedOrigin: scope.origin)
            XCTAssertEqual(try Data(contentsOf: request.fileURL), png)
            let tooLarge = ImportedAsset(sourceKey: "large", fileName: "large.png", sha256: request.asset.sha256,
                byteCount: SystemScreenshotWebCandidate.maximumBytes + 1, pixelWidth: 4, pixelHeight: 4,
                mediaType: "image/png", origin: scope.origin)
            XCTAssertNoThrow(try scope.validateMetadata(tooLarge))
            XCTAssertThrowsError(try SystemScreenshotWebCandidate.validateMetadata(tooLarge, expectedOrigin: scope.origin)) {
                XCTAssertEqual($0 as? SystemScreenshotInputError, .byteLimit)
            }
            let tooManyPixels = ImportedAsset(sourceKey: "pixels", fileName: "pixels.png", sha256: request.asset.sha256,
                byteCount: request.asset.byteCount, pixelWidth: 4097, pixelHeight: 4096,
                mediaType: "image/png", origin: scope.origin)
            XCTAssertNoThrow(try scope.validateMetadata(tooManyPixels))
            XCTAssertThrowsError(try SystemScreenshotWebCandidate.validateMetadata(tooManyPixels, expectedOrigin: scope.origin)) {
                XCTAssertEqual($0 as? SystemScreenshotInputError, .pixelLimit)
            }
            var header = Array(png.prefix(33))
            for (index, invalid) in [(24, UInt8(16)), (25, UInt8(2)), (28, UInt8(1))] {
                let old = header[index]; header[index] = invalid
                XCTAssertThrowsError(try SystemScreenshotWebCandidate.validateHeader(header, asset: request.asset, restrictedAdmission: true))
                header[index] = old
            }
        }
    }

    func testEachSourceRegistersOriginalOriginAndReopensWithoutMutation() async throws {
        for scope in [SystemScreenshotAdmissionScope.productSystem, .productApplication] {
            for local in [false, true] {
                let (store, request, database) = try await fixture(origin: scope.origin, local: local)
                let admission = SystemScreenshotCandidateAdmission(store: store, scope: scope)
                try await admission.enroll(request)
                let key = SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: scope)
                let saved = try await store.checkpoint(for: key), bytes = try XCTUnwrap(saved)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                XCTAssertEqual(object["version"] as? Int, 2)
                XCTAssertEqual(object["sourceID"] as? String, "chatgpt-web-screenshot-handoff-20261105-v17")
                XCTAssertEqual(object["assetOrigin"] as? String, scope.origin.rawValue)
                let fence = try await store.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: request))
                XCTAssertEqual(fence, bytes)
                await reject { try await admission.enroll(request) }
                try await store.markUnknown(request.operation.id, reason: "constructed original pending")
                let reopened = try QueueStore(databaseURL: database)
                let original = try await refreshed(request, store: reopened)
                let recovered = SystemScreenshotCandidateAdmission(store: reopened, scope: scope)
                let accepted = try await recovered.admittedObservationScope(for: original)
                XCTAssertEqual(accepted, scope)
                await reject { try await recovered.enroll(original) }
                let retained = try await reopened.checkpoint(for: key)
                XCTAssertEqual(retained, bytes)
                let asset = try await reopened.asset(id: request.asset.id)
                XCTAssertEqual(asset?.image.origin, scope.origin)
                XCTAssertEqual(asset?.activeOperationID, request.operation.id)
                XCTAssertEqual(asset?.status, .unknown)
                try await SystemScreenshotObservationJournal(store: reopened, scope: scope).record(envelope(original), for: original)
                let observation = try await reopened.checkpoint(for: SystemScreenshotObservationJournal.checkpointKey(original, slot: .input, scope: scope))
                XCTAssertNotNil(observation)
                let afterJournal = try await reopened.asset(id: request.asset.id)
                XCTAssertEqual(afterJournal, asset, "A source-specific journal cannot grant completion or change queue state")
            }
        }
    }

    func testCrossSourceAndSyntheticCannotAcquireRegistrationOrJournal() async throws {
        for origin in [AssetOrigin.systemScreenshot, .applicationScreenshot, .synthetic] {
            let (store, request, _) = try await fixture(origin: origin)
            for scope in [SystemScreenshotAdmissionScope.candidate, .ordinary, .ordinaryCurrentDraftInternal, .productSystem, .productApplication]
                where scope.origin != origin {
                await reject { try await SystemScreenshotCandidateAdmission(store: store, scope: scope).enroll(request) }
                await reject { try await SystemScreenshotObservationJournal(store: store, scope: scope).record(self.envelope(request), for: request) }
                let registration = try await store.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: scope))
                let journal = try await store.checkpoint(for: SystemScreenshotObservationJournal.checkpointKey(request, slot: .input, scope: scope))
                XCTAssertNil(registration); XCTAssertNil(journal)
            }
        }
    }

    func testCurrentDraftSupportCannotPromoteOriginalLocalIdentity() async throws {
        let (store, request, _) = try await fixture(local: true)
        let admission = SystemScreenshotCandidateAdmission(store: store, scope: .productSystem)
        try await admission.enroll(request)
        let old = request.operation.target
        let promoted = TargetLease(adapterID: old.adapterID, surface: old.surface, applicationID: old.applicationID,
            sessionID: old.sessionID, windowID: old.windowID, tabID: old.tabID, documentID: old.documentID,
            composerID: old.composerID, draftGeneration: old.draftGeneration,
            logicalDraftIdentity: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                id: "00000000-0000-4000-8000-000000000001"), clickBindingID: old.clickBindingID)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request.operation)) as? [String: Any])
        object["target"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(promoted))
        let changed = try JSONDecoder().decode(TransferOperation.self, from: JSONSerialization.data(withJSONObject: object))
        await reject { try await admission.admits(TransferRequest(operation: changed, asset: request.asset, fileURL: request.fileURL)) }
        let unbound = TargetLease(adapterID: old.adapterID, surface: old.surface, applicationID: old.applicationID,
            sessionID: old.sessionID, windowID: old.windowID, tabID: old.tabID, documentID: old.documentID,
            composerID: old.composerID, draftGeneration: old.draftGeneration)
        for scope in [SystemScreenshotAdmissionScope.productSystem, .productApplication] {
            XCTAssertNoThrow(try scope.validateTarget(unbound),
                "Current native document/composer binding needs no historical React identity")
        }
        XCTAssertThrowsError(try SystemScreenshotAdmissionScope.ordinary.validateTarget(old),
            "New current-draft support must not expand historical persisted-only scope")
    }

    func testLegacyOrdinaryRegistrationAndJournalStayReadOnlyInProductScope() async throws {
        for legacy in [SystemScreenshotAdmissionScope.ordinary, .ordinaryCurrentDraftInternal] {
            let (store, request, database) = try await fixture(local: legacy == .ordinaryCurrentDraftInternal)
            try await SystemScreenshotCandidateAdmission(store: store, scope: legacy).enroll(request)
            let key = SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: legacy)
            let before = try await store.checkpoint(for: key)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(before)) as? [String: Any])
            XCTAssertEqual(fields["version"] as? Int, 1); XCTAssertNil(fields["assetOrigin"])
            try await store.markUnknown(request.operation.id, reason: "legacy pending fixture")
            let reopened = try QueueStore(databaseURL: database)
            let original = try await refreshed(request, store: reopened)
            let successor = SystemScreenshotCandidateAdmission(store: reopened, scope: .productSystem)
            let scope = try await successor.admittedObservationScope(for: original)
            XCTAssertEqual(scope, legacy)
            try await SystemScreenshotObservationJournal(store: reopened, scope: .productSystem)
                .recordForOriginalScope(envelope(original), for: original, originalScope: legacy)
            await reject { try await successor.enroll(original) }
            let after = try await reopened.checkpoint(for: key)
            let newRegistration = try await reopened.checkpoint(for: SystemScreenshotCandidateAdmission.checkpointKey(for: original, scope: .productSystem))
            let oldJournal = try await reopened.checkpoint(for: SystemScreenshotObservationJournal.checkpointKey(original, slot: .input, scope: legacy))
            let newJournal = try await reopened.checkpoint(for: SystemScreenshotObservationJournal.checkpointKey(original, slot: .input, scope: .productSystem))
            XCTAssertEqual(after, before); XCTAssertNil(newRegistration); XCTAssertNotNil(oldJournal); XCTAssertNil(newJournal)
        }
    }

    func testProductCannotBorrowCandidateOrRepairPartialFence() async throws {
        let (store, request, _) = try await fixture()
        try await SystemScreenshotCandidateAdmission(store: store).enroll(request)
        try await store.markUnknown(request.operation.id, reason: "historical candidate")
        let original = try await refreshed(request, store: store)
        let successor = SystemScreenshotCandidateAdmission(store: store, scope: .productSystem)
        let recovered = try await successor.admittedObservationScope(for: original)
        XCTAssertNil(recovered)
        await reject {
            try await SystemScreenshotObservationJournal(store: store, scope: .productSystem)
                .recordForOriginalScope(self.envelope(original), for: original, originalScope: .candidate)
        }
        let (other, fresh, _) = try await fixture()
        let fenceKey = SystemScreenshotCandidateAdmission.checkpointKey(for: fresh)
        let partial = Data("incomplete-private-registration".utf8)
        try await other.saveCheckpoint(partial, for: fenceKey)
        let newAdmission = SystemScreenshotCandidateAdmission(store: other, scope: .productSystem)
        await reject { try await newAdmission.enroll(fresh) }
        let observed = try await newAdmission.admittedObservationScope(for: fresh)
        XCTAssertNil(observed)
        let retained = try await other.checkpoint(for: fenceKey)
        XCTAssertEqual(retained, partial)
    }

    func testRegistrationRejectsWrongOriginVersionAndUnknownFieldsWithoutRepair() async throws {
        let (store, request, _) = try await fixture(origin: .applicationScreenshot)
        let scope = SystemScreenshotAdmissionScope.productApplication
        let admission = SystemScreenshotCandidateAdmission(store: store, scope: scope)
        try await admission.enroll(request)
        let key = SystemScreenshotCandidateAdmission.checkpointKey(for: request, scope: scope)
        let saved = try await store.checkpoint(for: key)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(saved)) as? [String: Any])
        for (field, value) in [("assetOrigin", "systemScreenshot" as Any), ("version", 1 as Any), ("approved", true as Any)] {
            var modified = object; modified[field] = value
            let bytes = try JSONSerialization.data(withJSONObject: modified, options: [.sortedKeys])
            try await store.saveCheckpoint(bytes, for: key)
            try await store.saveCheckpoint(bytes, for: SystemScreenshotCandidateAdmission.checkpointKey(for: request))
            await reject { try await admission.admits(request) }
            let after = try await store.checkpoint(for: key); XCTAssertEqual(after, bytes)
        }
    }

    func testLegacyAndProductConcurrentRegistrationShareOneShotFence() async throws {
        let (store, request, database) = try await fixture()
        let second = try QueueStore(databaseURL: database)
        let admissions = [SystemScreenshotCandidateAdmission(store: store, scope: .ordinary),
                          SystemScreenshotCandidateAdmission(store: second, scope: .productSystem)]
        let winners = await withTaskGroup(of: Bool.self) { group in
            for admission in admissions {
                group.addTask { do { try await admission.enroll(request); return true } catch { return false } }
            }
            var result = [Bool](); for await value in group { result.append(value) }; return result
        }
        XCTAssertEqual(winners.filter { $0 }.count, 1)
        for admission in admissions { await reject { try await admission.enroll(request) } }
    }
}

private actor V15ReadOnlyBridge: WebBridgeExecutor {
    let response: Data
    private(set) var actions: [WebBridgeAction] = []
    init(response: Data) { self.response = response }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        actions.append(command.action)
        guard command.action == .observe else { throw WebAdapterError.invalidRequest }
        return response
    }
}
