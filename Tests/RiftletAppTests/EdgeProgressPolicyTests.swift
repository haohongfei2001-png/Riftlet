import Foundation
import XCTest
import RiftletCore
import RiftletAdapters
@testable import RiftletApp

final class EdgeProgressPolicyTests: XCTestCase {
    func testOrdinaryEntryGrantsOnlyEdgeSystemPNGCorrelatedStart() {
        let policy = OrdinaryAttachmentAdmission.unifiedProduct.receiptPolicy
        let edge = "com.microsoft.edgemac", chrome = "com.google.Chrome"
        let profile = OrdinaryProductScreenshotScope.edgeProgressProfile, id = OrdinaryProductScreenshotScope.edgeProgressStartProfileID
        func receipt(_ app: String, profile: ObservationProfile, signal: UploadStartSignal, pinned: Bool = true,
                     route: WebDraftRoute? = .chatGPTTemporaryHome) -> TransferReceipt {
            let lease = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: app, sessionID: "s",
                windowID: "1", tabID: "2", documentID: "d", composerID: "c", draftGeneration: "g",
                clickBindingID: pinned ? UUID() : nil, webDraftRoute: route)
            return TransferReceipt(operationID: UUID(), assetID: UUID(), attempt: 1, assetSHA256: String(repeating: "a", count: 64),
                target: lease, outcome: .uploadStarted, profileID: profile.profileID, attachmentID: "owned-card",
                belongsToOriginalDraft: true, isUploading: true,
                uploadStartEvidence: .init(profileID: profile.uploadStartProfileID!, signal: signal, evidenceID: UUID().uuidString))
        }
        func asset(_ origin: AssetOrigin, mime: String = "image/png") -> ImportedAsset {
            ImportedAsset(sourceKey: UUID().uuidString, fileName: "image.png", sha256: String(repeating: "a", count: 64),
                byteCount: 100, pixelWidth: 4, pixelHeight: 4, mediaType: mime, origin: origin)
        }
        let original = asset(.systemScreenshot)
        let start = receipt(edge, profile: profile, signal: .correlatedProgress)
        XCTAssertTrue(policy.allowsUploadStart(receipt: start, asset: original, mode: .production))
        for invalid in [receipt(chrome, profile: profile, signal: .correlatedProgress),
                        receipt(edge, profile: profile, signal: .attachmentAccepted),
                        receipt(edge, profile: profile, signal: .correlatedProgress, pinned: false),
                        receipt(edge, profile: profile, signal: .correlatedProgress, route: nil),
                        receipt(edge, profile: OrdinaryProductScreenshotScope.admittedSystemProfile, signal: .attachmentAccepted)] {
            XCTAssertFalse(policy.allowsUploadStart(receipt: invalid, asset: original, mode: .production))
        }
        for invalid in [asset(.applicationScreenshot), asset(.synthetic), asset(.systemScreenshot, mime: "image/jpeg")] {
            XCTAssertFalse(policy.allowsUploadStart(receipt: start, asset: invalid, mode: .production))
        }
        XCTAssertNil(policy.admittedProfiles[profile.profileID]); XCTAssertNil(policy.retrySafeProfiles[id])
        XCTAssertNil(policy.continuationProfiles[id]); XCTAssertNil(policy.platformCompletionProfiles[id])
        XCTAssertNil(profile.completionSignal); XCTAssertNil(profile.failureSignal); XCTAssertNil(profile.continuationProfileID)
        XCTAssertFalse(ReceiptPolicy().allowsUploadStart(receipt: start, asset: original, mode: .production))
    }
    func testNewDraftAcceptanceIsLocalToItsEdgeProfileAndCanAlsoUseEarlierObservedProgress() {
        let policy = OrdinaryAttachmentAdmission.unifiedProduct.receiptPolicy
        let profile = OrdinaryProductScreenshotScope.edgeAttachmentAcceptedProfile
        let startID = OrdinaryProductScreenshotScope.edgeAttachmentAcceptedStartProfileID
        let old = OrdinaryProductScreenshotScope.edgeProgressProfile
        let image = ImportedAsset(sourceKey: "test:edge", fileName: "image.png", sha256: String(repeating: "e", count: 64),
            byteCount: 100, pixelWidth: 3, pixelHeight: 4, mediaType: "image/png", origin: .systemScreenshot)

        func receipt(host: String = "com.microsoft.edgemac", receiptID: String = profile.profileID,
                     evidenceID: String = startID, signal: UploadStartSignal = .attachmentAccepted,
                     uploading: Bool = false) -> TransferReceipt {
            let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: host,
                sessionID: "process", windowID: "1", tabID: "2", documentID: "document", composerID: "editor",
                draftGeneration: "draft", clickBindingID: UUID(), webDraftRoute: .chatGPTTemporaryHome)
            return TransferReceipt(operationID: UUID(), assetID: image.id, attempt: 1, assetSHA256: image.sha256,
                target: target, outcome: .uploadStarted, profileID: receiptID, attachmentID: "original-draft-image",
                belongsToOriginalDraft: true, isUploading: uploading,
                uploadStartEvidence: .init(profileID: evidenceID, signal: signal, evidenceID: UUID().uuidString))
        }
        let accepted = receipt()
        XCTAssertTrue(policy.allowsUploadStart(receipt: accepted, asset: image, mode: .production))
        XCTAssertTrue(policy.allowsUploadStart(receipt: receipt(signal: .correlatedProgress, uploading: true), asset: image, mode: .production))
        XCTAssertFalse(policy.allowsConsumption(receipt: accepted, asset: image, mode: .production))
        XCTAssertFalse(policy.allowsContinuation(receipt: accepted, asset: image, mode: .production))
        XCTAssertFalse(policy.allowsRetry(receipt: accepted, asset: image, mode: .production))
        for invalid in [receipt(host: "com.google.Chrome"), receipt(receiptID: old.profileID),
                        receipt(evidenceID: OrdinaryProductScreenshotScope.edgeProgressStartProfileID),
                        receipt(uploading: true), receipt(signal: .correlatedProgress),
                        receipt(signal: .correlatedByteRequest, uploading: true)] {
            XCTAssertFalse(policy.allowsUploadStart(receipt: invalid, asset: image, mode: .production))
        }
    }

}
