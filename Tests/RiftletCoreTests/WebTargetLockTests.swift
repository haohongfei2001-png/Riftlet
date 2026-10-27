import Foundation
import XCTest
@testable import RiftletCore

/// A new page arm changes receipt identity, but cannot erase an unresolved
/// transport side effect in that same browser tab. These are synthetic fixtures.
final class WebTargetLockTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-web-target-lock-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func store(_ name: String = "queue") throws -> QueueStore {
        try QueueStore(databaseURL: root.appendingPathComponent("\(name).sqlite"))
    }
    private func target(surface: TargetSurface = .webChat, app: String = "com.google.Chrome",
                        session: String = "browser-session", tab: String? = "tab-1",
                        window: String = "window-1", document: String = "document-1",
                        composer: String = "composer-1", generation: String = "generation-1") -> TargetLease {
        TargetLease(adapterID: "web-lock-fixture", surface: surface, applicationID: app,
            sessionID: session, windowID: window, tabID: tab, documentID: document,
            composerID: composer, draftGeneration: generation)
    }
    private func prepare(_ db: QueueStore, _ lease: TargetLease) async throws -> (ImportedAsset, TransferOperation) {
        let id = UUID()
        let image = ImportedAsset(id: id, sourceKey: "fixture-\(id)", fileName: "\(id).png",
            sha256: String(repeating: "b", count: 64), byteCount: 100, pixelWidth: 8,
            pixelHeight: 8, mediaType: "image/png", origin: .synthetic)
        _ = try await db.importAsset(image)
        return (image, try await db.prepare(assetID: image.id, target: lease))
    }
    private func makeUnknown(_ db: QueueStore, _ lease: TargetLease) async throws -> TransferOperation {
        let (_, op) = try await prepare(db, lease)
        try await db.markDispatchIntent(op.id)
        try await db.markUnknown(op.id, reason: "Synthetic observer interruption")
        return op
    }
    private func assertBusy(_ db: QueueStore, _ lease: TargetLease,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let (_, op) = try await prepare(db, lease)
        do { try await db.markDispatchIntent(op.id); XCTFail("Unresolved tab admitted another input", file: file, line: line) }
        catch RiftletError.targetBusy {}
        let retained = try await db.operation(id: op.id)
        XCTAssertEqual(retained?.phase, .prepared, file: file, line: line)
    }

    func testUnknownBlocksSameTabAfterRearmWindowMoveAndDocumentReplacement() async throws {
        let db = try store(); let original = target()
        let old = try await makeUnknown(db, original)
        let changes = [target(generation: "rearmed"), target(window: "moved-window"),
                       target(document: "new-document", composer: "new-composer", generation: "new-thread"),
                       target(window: "new-window", document: "new-document", composer: "new-composer", generation: "rearmed")]
        for lease in changes {
            XCTAssertNotEqual(lease.stableKey, original.stableKey)
            XCTAssertEqual(lease.serializationKey, original.serializationKey)
            try await assertBusy(db, lease)
        }
        let persisted = try await db.operation(id: old.id)
        XCTAssertEqual(persisted?.phase, .unknown); XCTAssertEqual(persisted?.target, original)
        let reopened = try store()
        try await assertBusy(reopened, target(window: "restart-window", generation: "restart-arm"))
    }

    func testUnknownDoesNotLockAnotherTabOrBrowserSession() async throws {
        let db = try store(); let original = target()
        _ = try await makeUnknown(db, original)
        for lease in [target(tab: "tab-2"), target(session: "another-browser-session")] {
            XCTAssertNotEqual(lease.serializationKey, original.serializationKey)
            let (_, op) = try await prepare(db, lease)
            try await db.markDispatchIntent(op.id)
            let entered = try await db.operation(id: op.id)
            XCTAssertEqual(entered?.phase, .dispatchIntent)
        }
    }

    func testCompensatedSameTabRearmRemainsLockedAcrossRestart() async throws {
        let db = try store(); let original = target()
        let (image, op) = try await prepare(db, original)
        try await db.markDispatchIntent(op.id)
        let success = TransferReceipt(operationID: op.id, assetID: image.id, attempt: op.attempt,
            assetSHA256: image.sha256, target: original, outcome: .verifiedReady,
            profileID: "web-lock-synthetic", attachmentID: "observed-attachment",
            positiveReady: true, belongsToOriginalDraft: true)
        _ = try await db.apply(success, policy: .init(syntheticAcceptanceProfiles: ["web-lock-synthetic": .webChat]))
        let failure = TransferReceipt(operationID: op.id, assetID: image.id, attempt: op.attempt,
            assetSHA256: image.sha256, target: original, outcome: .unknown,
            profileID: success.profileID, attachmentID: success.attachmentID,
            belongsToOriginalDraft: true, hasError: true)
        _ = try await db.apply(failure)
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        try await assertBusy(reopened, target(window: "moved", document: "refreshed", generation: "rearmed"))
        let restored = try await reopened.operation(id: op.id)
        let audit = try await reopened.compensation(for: op.id)
        XCTAssertEqual(restored?.phase, .compensated); XCTAssertEqual(restored?.attempt, 1)
        XCTAssertEqual(audit?.originalSuccess, success); XCTAssertEqual(audit?.failure, failure)
    }

    func testOtherSurfacesAndUnidentifiedChromeTabsKeepExactTargetLock() async throws {
        let fixtures: [(TargetSurface, String, String?)] = [
            (.webWork, "com.google.Chrome", "tab-1"),
            (.macChat, "com.openai.chat", nil),
            (.webChat, "fixture.other.browser", "tab-1"),
            (.webChat, "com.google.Chrome", nil),
            (.webChat, "com.google.Chrome", "")
        ]
        for (index, fixture) in fixtures.enumerated() {
            let db = try store("exact-\(index)")
            let old = target(surface: fixture.0, app: fixture.1, tab: fixture.2)
            let changed = target(surface: fixture.0, app: fixture.1, tab: fixture.2, generation: "new")
            XCTAssertEqual(old.serializationKey, old.stableKey)
            XCTAssertEqual(changed.serializationKey, changed.stableKey)
            _ = try await makeUnknown(db, old)
            try await assertBusy(db, old)
            let (_, op) = try await prepare(db, changed)
            try await db.markDispatchIntent(op.id)
            let entered = try await db.operation(id: op.id)
            XCTAssertEqual(entered?.phase, .dispatchIntent)
        }
    }

    func testPreparedLeaseDoesNotLockDispatchOfAnotherAsset() async throws {
        let db = try store()
        _ = try await prepare(db, target())
        let (_, second) = try await prepare(db, target(generation: "rearmed"))
        try await db.markDispatchIntent(second.id)
        let entered = try await db.operation(id: second.id)
        XCTAssertEqual(entered?.phase, .dispatchIntent)
    }
}
