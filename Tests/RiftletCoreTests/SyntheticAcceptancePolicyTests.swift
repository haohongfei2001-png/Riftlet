import XCTest
@testable import RiftletCore

final class SyntheticAcceptancePolicyTests: XCTestCase {
    private let profileID = "web-attached-development-fixture"

    private func image(origin: AssetOrigin) -> ImportedAsset {
        ImportedAsset(sourceKey: UUID().uuidString, fileName: "fixture.png",
            sha256: String(repeating: "a", count: 64), byteCount: 128,
            pixelWidth: 10, pixelHeight: 10, mediaType: "image/png", origin: origin)
    }

    private func target(surface: TargetSurface = .webChat) -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: surface, applicationID: "com.google.Chrome",
            sessionID: "fixture", windowID: "1", tabID: "1", documentID: "doc",
            composerID: "composer", draftGeneration: "1")
    }

    private func receipt(image: ImportedAsset, operationID: UUID = UUID(),
                         surface: TargetSurface = .webChat, failure: Bool = false) -> TransferReceipt {
        TransferReceipt(operationID: operationID, assetID: image.id, attempt: 1,
            assetSHA256: image.sha256, target: target(surface: surface),
            outcome: failure ? .definitiveFailure : .verifiedReady, profileID: profileID,
            attachmentID: "observed-test-card", positiveReady: !failure,
            belongsToOriginalDraft: true, hasError: failure, safeToRetry: failure)
    }

    func testDevelopmentReceiptCanOnlyConsumeSyntheticAssetAndPersistsThatBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-web-policy-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Even a duplicated general registration cannot erase the development
        // profile's explicit synthetic-only restriction.
        let policy = ReceiptPolicy(admittedProfiles: [profileID: .webChat],
            syntheticAcceptanceProfiles: [profileID: .webChat])
        for origin in [AssetOrigin.synthetic, .systemScreenshot] {
            let url = directory.appendingPathComponent("\(origin.rawValue).sqlite")
            let store = try QueueStore(databaseURL: url)
            let asset = image(origin: origin)
            _ = try await store.importAsset(asset)
            let op = try await store.prepare(assetID: asset.id, target: target())
            try await store.markDispatchIntent(op.id)
            _ = try await store.apply(receipt(image: asset, operationID: op.id), policy: policy)
            let reopened = try QueueStore(databaseURL: url)
            try await reopened.recoverInterruptedOperations()
            let saved = try await reopened.asset(id: asset.id)
            let savedReceipt = try await reopened.receipt(for: op.id)
            XCTAssertEqual(saved?.status, origin == .synthetic ? .used : .unknown)
            XCTAssertEqual(saved?.activeOperationID, op.id)
            XCTAssertEqual(savedReceipt?.operationID, op.id)
        }
    }

    func testSyntheticAcceptanceNeverGrantsRetryEvenWithCollidingFailureRegistration() {
        let asset = image(origin: .synthetic)
        let policy = ReceiptPolicy(retrySafeProfiles: [profileID: .webChat],
            syntheticAcceptanceProfiles: [profileID: .webChat])
        XCTAssertFalse(policy.allowsRetry(receipt: receipt(image: asset, failure: true),
                                          asset: asset, mode: .production))
    }

    func testDevelopmentProfileDoesNotApplyToShippingDefaultAnotherSurfaceOrSimulation() {
        let asset = image(origin: .synthetic)
        let policy = ReceiptPolicy(syntheticAcceptanceProfiles: [profileID: .webChat])
        XCTAssertTrue(policy.admittedProfiles.isEmpty)
        XCTAssertTrue(policy.retrySafeProfiles.isEmpty)
        XCTAssertFalse(ReceiptPolicy().allowsConsumption(receipt: receipt(image: asset), asset: asset, mode: .production))
        XCTAssertFalse(policy.allowsConsumption(receipt: receipt(image: asset, surface: .webWork), asset: asset, mode: .production))
        XCTAssertFalse(policy.allowsConsumption(receipt: receipt(image: asset), asset: asset, mode: .simulation))
    }
}
