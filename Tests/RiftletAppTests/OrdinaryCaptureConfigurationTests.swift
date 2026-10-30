import Foundation
import XCTest
import RiftletCore
import RiftletAdapters
import RiftletUI
@testable import RiftletApp

private actor OrdinaryBridgeSpy: WebBridgeExecutor {
    private(set) var calls = 0
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        calls += 1
        throw WebAdapterError.browserNotFrontmost
    }
}

/// Isolated SQLite/files and a fake executor only. No user DB, Chrome or TCC.
final class OrdinaryCaptureConfigurationTests: XCTestCase {
    private func evidence(app: String = String(repeating: "b", count: 64)) -> OrdinaryAttachmentEvidence {
        .init(sourceRevision: String(repeating: "a", count: 40), appSHA256: app,
              evidenceSHA256: String(repeating: "c", count: 64), reviewSHA256: String(repeating: "d", count: 64))
    }

    func testDefaultOrdinaryEntryCannotBeEnabledByRuntimeArgumentsOrCandidatePolicy() throws {
        #if RIFTLET_ORDINARY_ACCEPTANCE
        XCTAssertEqual(try ApplicationMode.resolve([]), .capture)
        XCTAssertEqual(ApplicationMode.capture.directoryName, "Riftlet-Ordinary-Acceptance")
        XCTAssertEqual(ApplicationMode.capture.menuTitle, "Riftlet ORDINARY TEST")
        XCTAssertTrue(ApplicationMode.capture.usesWebAdapter)
        XCTAssertTrue(ApplicationMode.capture.observesAttachments)
        for option in ["--simulate", "--web-acceptance", "--system-screenshot-candidate"] {
            XCTAssertThrowsError(try ApplicationMode.resolve([option]))
        }
        XCTAssertEqual(OrdinaryCaptureConfiguration.admission.purpose, .internalAcceptance)
        XCTAssertTrue(ProductStatus.supportDescription.contains("非生产准入"))
        #else
        for arguments in [[], ["--acceptance-trace"], ["--enable-production-upload"], ["--ordinary-upload"]] {
            let mode = try ApplicationMode.resolve(arguments)
            XCTAssertEqual(mode, .capture)
            XCTAssertFalse(mode.usesWebAdapter)
            XCTAssertFalse(mode.observesAttachments)
            XCTAssertEqual(mode.attachmentState, .productionDisabled)
        }
        let ordinary = OrdinaryCaptureConfiguration.admission
        XCTAssertFalse(ordinary.allowsInput)
        XCTAssertTrue(ordinary.receiptPolicy.admittedProfiles.isEmpty)
        XCTAssertTrue(ordinary.receiptPolicy.uploadStartProfiles.isEmpty)
        XCTAssertTrue(ordinary.receiptPolicy.retrySafeProfiles.isEmpty)
        XCTAssertFalse(SystemScreenshotCandidateConfiguration.completedAttachmentProfiles.isEmpty)
        XCTAssertTrue(ProductStatus.supportDescription.contains("尚待最终 App"))
        XCTAssertEqual(ApplicationMode.capture.directoryName, "Riftlet")
        XCTAssertEqual(ApplicationMode.systemScreenshotCandidate.directoryName, "Riftlet-System-Screenshot-Candidate")
        #endif
    }

    func testInputStartAndCompletionDecisionsAreIndependentAndBuildBound() {
        let proof = evidence()
        let input = OrdinaryAttachmentAdmission.internalAcceptance(start: false, completion: false)
        XCTAssertTrue(input.allowsInput)
        XCTAssertTrue(ApplicationMode.capture.usesWebAdapter(ordinary: input))
        XCTAssertTrue(input.receiptPolicy.uploadStartProfiles.isEmpty)
        XCTAssertTrue(input.receiptPolicy.admittedProfiles.isEmpty)
        let start = OrdinaryAttachmentAdmission.internalAcceptance(start: true, completion: false)
        XCTAssertEqual(Set(start.receiptPolicy.uploadStartProfiles.keys), [OrdinarySystemScreenshotScope.admittedUploadStartProfileID])
        XCTAssertTrue(start.receiptPolicy.admittedProfiles.isEmpty)
        let complete = OrdinaryAttachmentAdmission.internalAcceptance(start: false, completion: true)
        XCTAssertTrue(complete.receiptPolicy.uploadStartProfiles.isEmpty)
        XCTAssertEqual(Set(complete.receiptPolicy.admittedProfiles.keys), [OrdinarySystemScreenshotScope.admittedCompletionProfileID])
        XCTAssertTrue(complete.receiptPolicy.retrySafeProfiles.isEmpty)
        let fakeApproval = OrdinaryAttachmentAdmission(input: proof, start: proof, completion: proof)
        XCTAssertFalse(fakeApproval.allowsInput); XCTAssertFalse(fakeApproval.allowsStart); XCTAssertFalse(fakeApproval.allowsCompletion)
        XCTAssertEqual(fakeApproval.purpose, .production)
        XCTAssertTrue(complete.receiptPolicy.continuationProfiles.isEmpty)
        let noInput = OrdinaryAttachmentAdmission(input: nil, start: proof, completion: proof)
        XCTAssertFalse(noInput.allowsInput); XCTAssertFalse(noInput.allowsStart); XCTAssertFalse(noInput.allowsCompletion)
        let different = OrdinaryAttachmentAdmission(input: proof, start: evidence(app: String(repeating: "e", count: 64)), completion: evidence(app: "malformed"))
        XCTAssertFalse(different.allowsStart); XCTAssertFalse(different.allowsCompletion)
        XCTAssertTrue(Set(complete.receiptPolicy.admittedProfiles.keys).isDisjoint(with: SystemScreenshotCandidateConfiguration.completedAttachmentProfiles.keys))
    }

    @MainActor func testClosedFactoryDoesNotUseBridgeAndDormantOrdinaryRouteUsesIndependentPolicy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let spy = OrdinaryBridgeSpy()
        let closed = try ApplicationAttachmentComposition.make(mode: .capture, root: root, store: store, executor: spy, ordinary: .closed)
        do { _ = try await closed.adapter.captureTarget(); XCTFail("Closed ordinary entry used Web") }
        catch RiftletError.adapterUnavailable {}
        let zero = await spy.calls; XCTAssertEqual(zero, 0)
        // Counterfactual source-owned admission tests wiring; never shipped as a runtime switch.
        let scoped = try ApplicationAttachmentComposition.make(mode: .capture, root: root, store: store, executor: spy,
            ordinary: .internalAcceptance())
        do { _ = try await scoped.adapter.captureTarget(); XCTFail("Fake executor should reject") }
        catch WebAdapterError.browserNotFrontmost {}
        let one = await spy.calls; XCTAssertEqual(one, 1)
        XCTAssertEqual(Set(scoped.policy.admittedProfiles.keys), [OrdinarySystemScreenshotScope.admittedCompletionProfileID])
        XCTAssertTrue(scoped.policy.retrySafeProfiles.isEmpty)
    }

    func testCurrentDraftInternalScopeCannotBorrowPersistedProductionOrCandidateApproval() {
        let current = OrdinaryAttachmentAdmission.internalAcceptance(currentDrafts: true)
        XCTAssertEqual(current.targetScope, .ordinaryCurrentDraftInternal)
        XCTAssertEqual(current.observationProfile.profileID, OrdinaryCurrentDraftInternalScope.profile.profileID)
        XCTAssertEqual(current.observationProfile.uploadStartProfileID, OrdinaryCurrentDraftInternalScope.profile.uploadStartProfileID)
        XCTAssertEqual(Set(current.receiptPolicy.uploadStartProfiles.keys), [OrdinaryCurrentDraftInternalScope.admittedUploadStartProfileID, OrdinarySystemScreenshotScope.admittedUploadStartProfileID])
        XCTAssertEqual(Set(current.receiptPolicy.admittedProfiles.keys), [OrdinaryCurrentDraftInternalScope.admittedCompletionProfileID, OrdinarySystemScreenshotScope.admittedCompletionProfileID])
        XCTAssertTrue(current.receiptPolicy.retrySafeProfiles.isEmpty)
        XCTAssertEqual(OrdinaryAttachmentAdmission.closed.targetScope, .ordinary)
        XCTAssertEqual(OrdinaryAttachmentAdmission.internalAcceptance().targetScope, .ordinary)
        XCTAssertTrue(Set(current.receiptPolicy.admittedProfiles.keys).isDisjoint(with: SystemScreenshotCandidateConfiguration.completedAttachmentProfiles.keys))
        XCTAssertTrue(current.supportText.contains("本地身份"))
        XCTAssertTrue(current.supportText.contains("新聊天及已有聊天"))
        let onlyInput = OrdinaryAttachmentAdmission.internalAcceptance(start: false, completion: false, currentDrafts: true)
        XCTAssertTrue(onlyInput.allowsInput)
        XCTAssertTrue(onlyInput.receiptPolicy.uploadStartProfiles.isEmpty)
        XCTAssertTrue(onlyInput.receiptPolicy.admittedProfiles.isEmpty)
    }

    @MainActor func testOrdinaryReopenPreservesUnknownMediaHistoryAndPreferencesWithoutRegistration() async throws {
        #if RIFTLET_ORDINARY_ACCEPTANCE
        throw XCTSkip("Closed ordinary startup is tested by the default build; internal variant intentionally observes its isolated root")
        #else
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent(ApplicationMode.capture.directoryName)
        let media = root.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let bytes = Data("private fixture bytes".utf8)
        let image = ImportedAsset(sourceKey: UUID().uuidString, fileName: "fixture.png", sha256: String(repeating: "1", count: 64),
            byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1, mediaType: "image/png")
        let file = media.appendingPathComponent(image.fileName); try bytes.write(to: file)
        let database = root.appendingPathComponent("queue.sqlite")
        let first = try QueueStore(databaseURL: database)
        _ = try await first.importAsset(image)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "fixture", windowID: "1", tabID: "2", documentID: "old-doc", composerID: "old-composer", draftGeneration: "1")
        let operation = try await first.prepare(assetID: image.id, target: target)
        try await first.markDispatchIntent(operation.id)
        try await first.markUnknown(operation.id, reason: "old unknown fixture")
        try await first.saveCheckpoint(Data("original audit".utf8), for: "ordinary-test-original-audit")
        try await first.setCapturePaused(true); try await first.setUserHidden(true)
        let before = try await first.operation(id: operation.id)
        let assetBefore = try await first.asset(id: image.id)
        let second = try QueueStore(databaseURL: database)
        let composition = try ApplicationAttachmentComposition.make(mode: .capture, root: root, store: second)
        XCTAssertTrue(composition.policy.admittedProfiles.isEmpty)
        // Actual closed host performs local crash recovery; page recovery is not scheduled.
        XCTAssertFalse(ApplicationMode.capture.observesAttachments)
        try await second.recoverInterruptedOperations()
        let after = try await second.operation(id: operation.id)
        let assetAfter = try await second.asset(id: image.id)
        XCTAssertEqual(after, before)
        let reason = try await second.operationReason(for: operation.id)
        XCTAssertEqual(reason, "old unknown fixture")
        XCTAssertEqual(after?.id, before?.id); XCTAssertEqual(after?.target, before?.target)
        XCTAssertEqual(after?.attempt, before?.attempt); XCTAssertEqual(after?.assetID, before?.assetID)
        XCTAssertEqual(after?.createdAt, before?.createdAt); XCTAssertEqual(after?.phase, .unknown)
        XCTAssertEqual(assetAfter?.image, assetBefore?.image)
        XCTAssertEqual(assetAfter?.activeOperationID, assetBefore?.activeOperationID)
        XCTAssertEqual(assetAfter?.visibility, assetBefore?.visibility)
        XCTAssertEqual(assetAfter?.visibilityRevision, assetBefore?.visibilityRevision)
        let hidden = try await second.userHidden(), paused = try await second.capturePaused()
        XCTAssertTrue(hidden); XCTAssertTrue(paused)
        let audit = try await second.checkpoint(for: "ordinary-test-original-audit")
        XCTAssertEqual(audit, Data("original audit".utf8))
        let history = try await second.history(); XCTAssertEqual(history.map(\.id), [image.id])
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let candidateRoot = base.appendingPathComponent(ApplicationMode.systemScreenshotCandidate.directoryName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidateRoot.path))
        do {
            let b = ImportedAsset(sourceKey: UUID().uuidString, fileName: "new.png", sha256: String(repeating: "2", count: 64), byteCount: 1, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png")
            _ = try await second.importAsset(b)
            let op = try await second.prepare(assetID: b.id, target: target)
            try await second.markDispatchIntent(op.id); XCTFail("Legacy UNKNOWN lock was released")
        } catch RiftletError.targetBusy {}
        #endif
    }
}
