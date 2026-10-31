import XCTest
import RiftletCore
import RiftletUI
import RiftletCapture
import RiftletAdapters
@testable import RiftletApp

final class ScreenshotEntryIntegrationTests: XCTestCase {
    func testExistingEntryPreferenceStaysEnabledAndExplicitDisableRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try Data(#"{"version":1,"defaultMode":"region"}"#.utf8).write(to: url)
        var value = try ScreenshotEntryPreferences.load(from: url)
        XCTAssertTrue(value.builtInScreenshotEnabled, "An existing installation cannot silently lose its entry")
        XCTAssertEqual(value.defaultMode, .region)
        value.builtInScreenshotEnabled = false; try value.save(to: url)
        let reopened = try ScreenshotEntryPreferences.load(from: url)
        XCTAssertFalse(reopened.builtInScreenshotEnabled)
        XCTAssertEqual(reopened.defaultMode, .region)
    }

    func testDefaultModePersistsWithPrivatePermissionsAndUnknownVersionIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        var preferences = try ScreenshotEntryPreferences.load(from: url)
        XCTAssertEqual(preferences.defaultMode, .window)
        preferences.defaultMode = .region
        try preferences.save(to: url)
        XCTAssertEqual(try ScreenshotEntryPreferences.load(from: url).defaultMode, .region)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        preferences.version = 99; try preferences.save(to: url)
        XCTAssertThrowsError(try ScreenshotEntryPreferences.load(from: url))
    }

    func testRealApplicationImageCanSurviveCandidateRestartWithoutBeingAdmitted() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("queue.sqlite")
        let store = try QueueStore(databaseURL: url)
        let image = ImportedAsset(sourceKey: "application-fixture", fileName: "fixture.png",
            sha256: String(repeating: "a", count: 64), byteCount: 128,
            pixelWidth: 10, pixelHeight: 10, mediaType: "image/png", origin: .applicationScreenshot)
        _ = try await store.importAsset(image)
        let reopened = try QueueStore(databaseURL: url)
        try await SystemScreenshotCandidateConfiguration.validateStore(reopened)
        let recovered = try await reopened.asset(id: image.id)
        XCTAssertEqual(recovered?.image.origin, .applicationScreenshot)
        XCTAssertEqual(recovered?.visibility, .visible)
        XCTAssertThrowsError(try SystemScreenshotWebCandidate.validateMetadata(image))
        let synthetic = ImportedAsset(sourceKey: "synthetic-fixture", fileName: "fake.png",
            sha256: String(repeating: "b", count: 64), byteCount: 128,
            pixelWidth: 10, pixelHeight: 10, mediaType: "image/png", origin: .synthetic)
        _ = try await reopened.importAsset(synthetic)
        do { try await SystemScreenshotCandidateConfiguration.validateStore(reopened); XCTFail("Synthetic contamination accepted") }
        catch RiftletError.modeMismatch {}
    }

    func testApplicationImagesCannotBorrowAnyOriginalScreenshotReceipt() {
        let image = ImportedAsset(sourceKey: "edited", fileName: "edited.png",
            sha256: String(repeating: "c", count: 64), byteCount: 128,
            pixelWidth: 10, pixelHeight: 10, mediaType: "image/png", origin: .applicationScreenshot)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "fixture", windowID: "1", tabID: "1", documentID: "doc", composerID: "composer", draftGeneration: "1")
        let policy = ReceiptPolicy(admittedProfiles: ["ready": .webChat], retrySafeProfiles: ["failure": .webChat],
            uploadStartProfiles: ["start": .webChat])
        let start = TransferReceipt(operationID: UUID(), assetID: image.id, attempt: 1,
            assetSHA256: image.sha256, target: target, outcome: .uploadStarted, profileID: "ready",
            attachmentID: "card", belongsToOriginalDraft: true, isUploading: true,
            uploadStartEvidence: .init(profileID: "start", signal: .correlatedProgress, evidenceID: "evidence"))
        let ready = TransferReceipt(operationID: UUID(), assetID: image.id, attempt: 1,
            assetSHA256: image.sha256, target: target, outcome: .verifiedReady, profileID: "ready",
            attachmentID: "card", positiveReady: true, belongsToOriginalDraft: true)
        let failure = TransferReceipt(operationID: UUID(), assetID: image.id, attempt: 1,
            assetSHA256: image.sha256, target: target, outcome: .definitiveFailure, profileID: "failure",
            attachmentID: "card", belongsToOriginalDraft: true, hasError: true, safeToRetry: true)
        XCTAssertFalse(policy.allowsUploadStart(receipt: start, asset: image, mode: .production))
        XCTAssertFalse(policy.allowsConsumption(receipt: ready, asset: image, mode: .production))
        XCTAssertFalse(policy.allowsRetry(receipt: failure, asset: image, mode: .production))
    }
}
