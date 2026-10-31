import Foundation
import XCTest
@testable import RiftletCore

/// Synthetic Core contracts. Real React property observation/admission is a
/// separate Web acceptance requirement; fixtures cannot prove page identity.
final class LogicalDraftIdentityTests: XCTestCase {
    private let admittedProfile = "chatgpt-composer-react-20261027-v1"
    private let draftA = "local-chatgpt:11111111-1111-4111-8111-111111111111"
    private let draftB = "local-chatgpt:22222222-2222-4222-8222-222222222222"
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-logical-draft-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func identity(_ id: String, profile: String? = nil) -> LogicalDraftIdentity {
        LogicalDraftIdentity(profileID: profile ?? admittedProfile, id: id)
    }
    private func target(_ logical: LogicalDraftIdentity? = nil, surface: TargetSurface = .webChat,
                        app: String = "com.google.Chrome", tab: String? = "tab-1",
                        window: String = "window-1", document: String = "document-1",
                        generation: String = "focus-1") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: surface, applicationID: app,
            sessionID: "browser-session", windowID: window, tabID: tab, documentID: document,
            composerID: "composer-1", draftGeneration: generation, logicalDraftIdentity: logical)
    }
    private func assertConflict(_ a: TargetLease, _ b: TargetLease, _ expected: Bool,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.conflictsForDispatch(with: b), expected, file: file, line: line)
        XCTAssertEqual(b.conflictsForDispatch(with: a), expected, "Conflict relation must be symmetric", file: file, line: line)
    }
    private func store() throws -> QueueStore { try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite")) }
    private func prepare(_ db: QueueStore, _ lease: TargetLease) async throws -> (ImportedAsset, TransferOperation) {
        let id = UUID()
        let image = ImportedAsset(id: id, sourceKey: "synthetic-\(id)", fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: 100, pixelWidth: 8,
            pixelHeight: 8, mediaType: "image/png", origin: .synthetic)
        _ = try await db.importAsset(image)
        return (image, try await db.prepare(assetID: image.id, target: lease))
    }
    private func unknown(_ db: QueueStore, _ lease: TargetLease) async throws -> TransferOperation {
        let (_, op) = try await prepare(db, lease)
        try await db.markDispatchIntent(op.id)
        try await db.markUnknown(op.id, reason: "Synthetic observation interruption")
        return op
    }
    private func assertBusy(_ db: QueueStore, _ lease: TargetLease,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let (_, op) = try await prepare(db, lease)
        do { try await db.markDispatchIntent(op.id); XCTFail("Dispatch bypassed unresolved draft", file: file, line: line) }
        catch RiftletError.targetBusy {}
        let preserved = try await db.operation(id: op.id)
        XCTAssertEqual(preserved?.phase, .prepared, file: file, line: line)
    }

    func testLegacyNilAndProvedIdentityConflictInBothDirections() {
        let legacy = target()
        assertConflict(legacy, target(identity(draftA)), true)
        assertConflict(legacy, target(identity(draftB), window: "moved", generation: "rearmed"), true)
    }

    func testDifferentAdmittedDraftsInSameTabDoNotConflict() {
        assertConflict(target(identity(draftA)), target(identity(draftB)), false)
    }

    func testSameLogicalDraftSurvivesRearmWindowMoveAndDocumentChange() {
        let original = target(identity(draftA))
        let rearmed = target(identity(draftA), window: "moved-window", document: "new-document", generation: "new-focus")
        XCTAssertNotEqual(original, rearmed)
        XCTAssertNotEqual(original.stableKey, rearmed.stableKey)
        assertConflict(original, rearmed, true)
    }

    func testUnknownProfileOrInvalidIDFallsBackToWholeTabConflict() {
        let valid = target(identity(draftA))
        let invalid = [identity(draftB, profile: "unknown-profile"), identity(draftB, profile: ""),
                       identity(""), identity("thread-guessed-from-url"), identity("local-chatgpt:not-a-uuid"),
                       identity("local-chatgpt:"), identity(" local-chatgpt:22222222-2222-4222-8222-222222222222"),
                       identity("local-chatgpt:22222222-2222-4222-8222-222222222222\n")]
        for candidate in invalid {
            assertConflict(valid, target(candidate, generation: "changed"), true)
        }
    }

    func testDifferentTabsRemainIndependentIncludingLegacyFallback() {
        assertConflict(target(), target(identity(draftA), tab: "tab-2"), false)
        assertConflict(target(identity(draftA)), target(identity(draftA), tab: "tab-2"), false)
    }

    func testOtherSurfacesAndMissingTabKeepExactStableKeyBehavior() {
        let fixtures: [(TargetSurface, String, String?)] = [
            (.webWork, "com.google.Chrome", "tab-1"),
            (.macChat, "com.openai.chat", nil),
            (.webChat, "fixture.browser", "tab-1"),
            (.webChat, "com.google.Chrome", nil),
            (.webChat, "com.google.Chrome", "")
        ]
        for fixture in fixtures {
            let original = target(identity(draftA), surface: fixture.0, app: fixture.1, tab: fixture.2)
            let other = target(identity(draftA), surface: fixture.0, app: fixture.1, tab: fixture.2, generation: "different")
            assertConflict(original, original, true)
            assertConflict(original, other, original.stableKey == other.stableKey)
        }
    }

    func testLegacyJSONDecodesNilWithoutInventingLogicalIdentity() throws {
        let original = target()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "logicalDraftIdentity")
        let legacyBytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let restored = try JSONDecoder().decode(TargetLease.self, from: legacyBytes)
        XCTAssertNil(restored.logicalDraftIdentity)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.stableKey, String(decoding: legacyBytes, as: UTF8.self))
        assertConflict(restored, target(identity(draftB)), true)
    }

    func testLegacyUnknownKeepsWildcardLockAfterDatabaseReopen() async throws {
        let db = try store(); let legacy = target()
        let old = try await unknown(db, legacy)
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        try await assertBusy(reopened, target(identity(draftB), generation: "fresh-arm"))
        let preserved = try await reopened.operation(id: old.id)
        XCTAssertEqual(preserved?.target, legacy); XCTAssertNil(preserved?.target.logicalDraftIdentity)
        XCTAssertEqual(preserved?.phase, .unknown); XCTAssertEqual(preserved?.attempt, 1)
    }

    func testProvedUnknownAllowsDifferentDraftButStillBlocksSameDraftAfterReopen() async throws {
        let db = try store(); let a = target(identity(draftA))
        let first = try await unknown(db, a)
        let reopened = try store()
        try await assertBusy(reopened, target(identity(draftA), window: "moved", generation: "rearmed"))
        let (_, second) = try await prepare(reopened, target(identity(draftB)))
        try await reopened.markDispatchIntent(second.id)
        let old = try await reopened.operation(id: first.id)
        let next = try await reopened.operation(id: second.id)
        XCTAssertEqual(old?.phase, .unknown); XCTAssertEqual(old?.target, a)
        XCTAssertEqual(next?.phase, .dispatchIntent)
    }

    func testLegacyCompensationKeepsWildcardLockAndOriginalAuditAfterReopen() async throws {
        let db = try store(); let legacy = target()
        let (image, op) = try await prepare(db, legacy)
        try await db.markDispatchIntent(op.id)
        let success = TransferReceipt(operationID: op.id, assetID: image.id, attempt: op.attempt,
            assetSHA256: image.sha256, target: legacy, outcome: .verifiedReady, profileID: "fixture-completion",
            attachmentID: "fixture-attachment", positiveReady: true, belongsToOriginalDraft: true)
        _ = try await db.apply(success, policy: .init(syntheticAcceptanceProfiles: ["fixture-completion": .webChat]))
        let failure = TransferReceipt(operationID: op.id, assetID: image.id, attempt: op.attempt,
            assetSHA256: image.sha256, target: legacy, outcome: .unknown, profileID: success.profileID,
            attachmentID: success.attachmentID, belongsToOriginalDraft: true, hasError: true)
        _ = try await db.apply(failure)
        let audit = try await db.compensation(for: op.id)
        let reopened = try store(); try await reopened.recoverInterruptedOperations()
        try await assertBusy(reopened, target(identity(draftB), generation: "rearmed"))
        let savedAudit = try await reopened.compensation(for: op.id)
        let restored = try await reopened.operation(id: op.id)
        XCTAssertEqual(savedAudit, audit)
        XCTAssertEqual(restored?.phase, .compensated); XCTAssertEqual(restored?.target, legacy)
        XCTAssertNil(restored?.target.logicalDraftIdentity)
    }

    func testLogicalDraftIdentityDoesNotRelaxReceiptTargetEquality() async throws {
        let db = try store(); let original = target(identity(draftA))
        let (image, op) = try await prepare(db, original)
        try await db.markDispatchIntent(op.id)
        let wrong = TransferReceipt(operationID: op.id, assetID: image.id, attempt: op.attempt,
            assetSHA256: image.sha256, target: target(identity(draftB)), outcome: .verifiedReady,
            profileID: "fixture-completion", attachmentID: "fixture-attachment", positiveReady: true,
            belongsToOriginalDraft: true)
        do {
            _ = try await db.apply(wrong, policy: .init(syntheticAcceptanceProfiles: ["fixture-completion": .webChat]))
            XCTFail("Different logical identity was accepted as the original target")
        } catch RiftletError.mismatchedReceipt {}
        let preserved = try await db.asset(id: image.id)
        let saved = try await db.receipt(for: op.id)
        XCTAssertEqual(preserved?.status, .transferring); XCTAssertNil(saved)
    }
}
