import XCTest
import Foundation
import RiftletCore
import RiftletAdapters
import RiftletUI
@testable import RiftletApp

/// Software only: no real capture, Chrome, TCC, network or physical click.
final class SystemScreenshotCandidateIntegrationTests: XCTestCase {
    func testExplicitModesRemainIsolatedAndOrdinaryLaunchDoesNotEnableWeb() throws {
        XCTAssertEqual(try ApplicationMode.resolve([]), .capture)
        XCTAssertFalse(ApplicationMode.capture.usesWebAdapter)
        XCTAssertTrue(ApplicationMode.capture.collectsSystemScreenshots)
        XCTAssertEqual(Set(ApplicationMode.allCases.map(\.directoryName)).count, 4)
        let flags = ["--simulate", "--web-acceptance", "--system-screenshot-candidate"]
        for a in 0..<flags.count {
            for b in (a + 1)..<flags.count {
                XCTAssertThrowsError(try ApplicationMode.resolve([flags[a], flags[b]]))
            }
        }
        let candidate = try ApplicationMode.resolve(["--system-screenshot-candidate"])
        XCTAssertTrue(candidate.collectsSystemScreenshots); XCTAssertTrue(candidate.usesWebAdapter)
        XCTAssertFalse(candidate.generatesSyntheticImages); XCTAssertEqual(candidate.storeMode, .production)
        XCTAssertEqual(candidate.attachmentState, .systemScreenshotCandidate)
        XCTAssertTrue(ApplicationMode.webAcceptance.generatesSyntheticImages)
        XCTAssertFalse(ApplicationMode.webAcceptance.collectsSystemScreenshots)
    }

    @MainActor func testPackagedCandidateCheckImportsOriginalBytesAndNeverReplaysAnUnadmittedOperation() async throws {
        try await SystemScreenshotCandidateSelfCheck.run()
    }

    @MainActor func testOrdinaryCompositionRemainsUnavailableAndCandidateRejectsMixedStore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("candidate-composition-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        let composition = try ApplicationAttachmentComposition.make(mode: .capture, root: root, store: store)
        do { _ = try await composition.adapter.captureTarget(); XCTFail("Ordinary mode enabled Web") }
        catch RiftletError.adapterUnavailable {}
        XCTAssertTrue(composition.policy.uploadStartProfiles.isEmpty)
        XCTAssertTrue(composition.policy.admittedProfiles.isEmpty)
        XCTAssertTrue(composition.policy.retrySafeProfiles.isEmpty)
        try await SystemScreenshotCandidateConfiguration.validateStore(store)
        _ = try await store.importAsset(image(origin: .synthetic))
        do { try await SystemScreenshotCandidateConfiguration.validateStore(store); XCTFail("Mixed candidate accepted") }
        catch RiftletError.modeMismatch {}
    }

    func testCandidateObservationHasNoImplicitStartSuccessOrRetryAdmission() {
        let asset = image(origin: .systemScreenshot)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "software", windowID: "1", tabID: "2", documentID: "doc", composerID: "composer", draftGeneration: "1")
        let id = UUID()
        let start = TransferReceipt(operationID: id, assetID: asset.id, attempt: 1, assetSHA256: asset.sha256,
            target: target, outcome: .uploadStarted, profileID: SystemScreenshotWebCandidate.completionProfileID,
            attachmentID: "card", belongsToOriginalDraft: true, isUploading: true,
            uploadStartEvidence: .init(profileID: SystemScreenshotWebCandidate.uploadStartProfileID,
                signal: .correlatedProgress, evidenceID: UUID().uuidString))
        let ready = TransferReceipt(operationID: id, assetID: asset.id, attempt: 1, assetSHA256: asset.sha256,
            target: target, outcome: .verifiedReady, profileID: SystemScreenshotWebCandidate.completionProfileID,
            attachmentID: "card", positiveReady: true, belongsToOriginalDraft: true)
        let failure = TransferReceipt(operationID: id, assetID: asset.id, attempt: 1, assetSHA256: asset.sha256,
            target: target, outcome: .definitiveFailure, profileID: "software-only-independent-safe-failure",
            attachmentID: "card", belongsToOriginalDraft: true, hasError: true, safeToRetry: true)
        for policy in [ReceiptPolicy(), SystemScreenshotCandidateConfiguration.receiptPolicy, WebAcceptanceConfiguration.receiptPolicy] {
            XCTAssertFalse(policy.allowsUploadStart(receipt: start, asset: asset, mode: .production))
            XCTAssertFalse(policy.allowsConsumption(receipt: ready, asset: asset, mode: .production))
            XCTAssertFalse(policy.allowsRetry(receipt: failure, asset: asset, mode: .production))
        }
        // Counterfactual software policies prove that future admissions remain
        // independent. None of these maps is used in the application composition.
        let onlyStart = ReceiptPolicy(uploadStartProfiles: [SystemScreenshotWebCandidate.uploadStartProfileID: .webChat])
        let onlyReady = ReceiptPolicy(admittedProfiles: [SystemScreenshotWebCandidate.completionProfileID: .webChat])
        let onlyFailure = ReceiptPolicy(retrySafeProfiles: [failure.profileID: .webChat])
        XCTAssertTrue(onlyStart.allowsUploadStart(receipt: start, asset: asset, mode: .production))
        XCTAssertFalse(onlyStart.allowsConsumption(receipt: ready, asset: asset, mode: .production))
        XCTAssertFalse(onlyStart.allowsRetry(receipt: failure, asset: asset, mode: .production))
        XCTAssertFalse(onlyReady.allowsUploadStart(receipt: start, asset: asset, mode: .production))
        XCTAssertTrue(onlyReady.allowsConsumption(receipt: ready, asset: asset, mode: .production))
        XCTAssertFalse(onlyReady.allowsRetry(receipt: failure, asset: asset, mode: .production))
        XCTAssertFalse(onlyFailure.allowsUploadStart(receipt: start, asset: asset, mode: .production))
        XCTAssertFalse(onlyFailure.allowsConsumption(receipt: ready, asset: asset, mode: .production))
        XCTAssertTrue(onlyFailure.allowsRetry(receipt: failure, asset: asset, mode: .production))
    }

    func testCandidateFeedbackDistinguishesSavedButUnsupportedFromCaptureFailure() {
        let presentation = SetupPresentation(snapshot: .init(attachment: .systemScreenshotCandidate,
            permission: .notRequested, issue: .attachmentFormat))
        XCTAssertTrue(presentation.canRequestPermission)
        XCTAssertTrue(presentation.attachmentText.contains("不自动吞噬"))
        XCTAssertTrue(presentation.attachmentText.contains("普通模式仍未启用"))
        XCTAssertTrue(presentation.issueText?.contains("已保存在本机") == true)
        XCTAssertFalse(presentation.issueText?.contains("未收录") == true)
        XCTAssertEqual(ProductStatus.clickIssue(SystemScreenshotInputError.byteLimit,
            frontmostBundleID: "com.google.Chrome", webAcceptance: true), .attachmentBytes)
        XCTAssertEqual(ProductStatus.clickIssue(SystemScreenshotInputError.pixelLimit,
            frontmostBundleID: "com.google.Chrome", webAcceptance: true), .attachmentPixels)
    }

    private func image(origin: AssetOrigin) -> ImportedAsset {
        ImportedAsset(sourceKey: UUID().uuidString, fileName: "fixture.png", sha256: String(repeating: "a", count: 64),
            byteCount: 64, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: origin)
    }
}
