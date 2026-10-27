import Foundation
import XCTest
@testable import RiftletCore

/// Synthetic Core/SQLite contracts, not proof of live React continuity or
/// production upload admission. Frozen identities are never rewritten here.
final class PersistedLogicalDraftIdentityTests: XCTestCase {
    private let persistedProfile = "chatgpt-composer-react-persisted-20261027-v1"
    private let localProfile = "chatgpt-composer-react-20261027-v1"
    private let draftA = "ABCDEF01-2345-4678-9ABC-DEF012345678"
    private let draftB = "22222222-2222-4222-8222-222222222222"
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftlet-persisted-draft-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func databaseURL(_ name: String = "queue") -> URL {
        directory.appendingPathComponent("\(name).sqlite")
    }
    private func store(_ name: String = "queue") throws -> QueueStore {
        try QueueStore(databaseURL: databaseURL(name))
    }
    private func identity(_ id: String, profile: String? = nil) -> LogicalDraftIdentity {
        LogicalDraftIdentity(profileID: profile ?? persistedProfile, id: id)
    }
    private func target(_ logical: LogicalDraftIdentity? = nil,
                        window: String = "original-window", document: String = "original-document",
                        composer: String = "original-composer", generation: String = "original-generation") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "original-session",
            windowID: window, tabID: "original-tab", documentID: document,
            composerID: composer, draftGeneration: generation, logicalDraftIdentity: logical)
    }
    private func assertConflict(_ a: TargetLease, _ b: TargetLease, _ expected: Bool,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.conflictsForDispatch(with: b), expected, file: file, line: line)
        XCTAssertEqual(b.conflictsForDispatch(with: a), expected,
                       "Conflict must remain symmetric", file: file, line: line)
    }
    private func prepare(_ db: QueueStore, _ lease: TargetLease) async throws -> (ImportedAsset, TransferOperation) {
        let id = UUID()
        let image = ImportedAsset(id: id, sourceKey: "synthetic-persisted-\(id)",
            fileName: "\(id).png", sha256: String(repeating: "a", count: 64),
            byteCount: 32, pixelWidth: 2, pixelHeight: 2, mediaType: "image/png", origin: .synthetic)
        _ = try await db.importAsset(image)
        return (image, try await db.prepare(assetID: id, target: lease))
    }
    private func makeUnknown(_ db: QueueStore, _ lease: TargetLease) async throws -> TransferOperation {
        let (_, op) = try await prepare(db, lease)
        try await db.markDispatchIntent(op.id)
        try await db.markUnknown(op.id, reason: "Synthetic retained original operation")
        return op
    }
    private func assertBusy(_ db: QueueStore, _ lease: TargetLease,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let (_, op) = try await prepare(db, lease)
        do {
            try await db.markDispatchIntent(op.id)
            XCTFail("Unresolved original draft lost its lock", file: file, line: line)
        } catch RiftletError.targetBusy {}
        let saved = try await db.operation(id: op.id)
        XCTAssertEqual(saved?.phase, .prepared, file: file, line: line)
    }

    func testRecognitionAcceptsOnlyExactProfileAndUnmodifiedUUIDFormat() {
        XCTAssertTrue(identity(draftA).isRecognized)
        XCTAssertTrue(identity(draftA.lowercased()).isRecognized)
        XCTAssertTrue(identity("local-chatgpt:\(draftA)", profile: localProfile).isRecognized)
        let invalidIDs = ["", "local-chatgpt:\(draftA)", " \(draftA)", "\(draftA) ",
            "\(draftA)\n", "\n\(draftA)", draftA.replacingOccurrences(of: "-", with: ""),
            "GBCDEF01-2345-4678-9ABC-DEF012345678", String(draftA.dropLast()),
            "\(draftA)0", "{\(draftA)}", "urn:uuid:\(draftA)"]
        for id in invalidIDs { XCTAssertFalse(identity(id).isRecognized, id) }
        XCTAssertFalse(identity(draftA, profile: localProfile).isRecognized)
        XCTAssertFalse(identity("local-chatgpt:\(draftA) ", profile: localProfile).isRecognized)
        for profile in ["", "unknown", persistedProfile + " ", persistedProfile + "-future"] {
            XCTAssertFalse(identity(draftA, profile: profile).isRecognized, profile)
        }
    }

    func testPersistedDraftConflictIsCaseInsensitiveAcrossRearmWindowAndDocumentChanges() {
        let a = target(identity(draftA))
        for other in [target(identity(draftA.lowercased())),
                      target(identity(draftA), window: "moved-window"),
                      target(identity(draftA), document: "replacement-document"),
                      target(identity(draftA), generation: "rearmed-generation"),
                      target(identity(draftA.lowercased()), window: "moved-window",
                             document: "replacement-document", composer: "new-composer", generation: "rearmed")] {
            XCTAssertNotEqual(a, other)
            assertConflict(a, other, true)
        }
        assertConflict(a, target(identity(draftB)), false)
        assertConflict(a, target(identity(draftB), window: "moved-window", generation: "rearmed"), false)
    }

    func testCrossProfileNilUnknownAndMalformedIdentitiesRemainConservative() {
        let a = target(identity(draftA))
        let b = target(identity(draftB))
        for old in [target(),
                    target(identity("local-chatgpt:\(draftA)", profile: localProfile)),
                    target(identity("local-chatgpt:\(draftB)", profile: localProfile)),
                    target(identity(draftA, profile: "unreviewed-profile")),
                    target(identity("\(draftA) ")),
                    target(identity("malformed"))] {
            assertConflict(old, a, true)
            assertConflict(old, b, true)
        }
    }

    func testFrozenStoredPersistedIdentitySurvivesReopenAndRecoveryWithoutRewritingOriginalFacts() async throws {
        // This is the pre-lifecycle TargetLease wire shape, retained literally
        // rather than regenerated from today's encoder or a URL-derived ID.
        let frozenTargetJSON = #"{"surface":"webChat","adapterID":"chatgpt-web","applicationID":"com.google.Chrome","sessionID":"original-session","windowID":"original-window","tabID":"original-tab","documentID":"original-document","composerID":"original-composer","draftGeneration":"original-generation","logicalDraftIdentity":{"id":"ABCDEF01-2345-4678-9ABC-DEF012345678","profileID":"chatgpt-composer-react-persisted-20261027-v1"}}"#
        let original = try JSONDecoder().decode(TargetLease.self, from: Data(frozenTargetJSON.utf8))
        XCTAssertEqual(original, target(identity(draftA)))
        let db = try store()
        let (image, op) = try await prepare(db, original)
        try await db.markDispatchIntent(op.id)
        let unknown = TransferReceipt(operationID: op.id, assetID: image.id, attempt: 1,
            assetSHA256: image.sha256, target: original, outcome: .unknown,
            profileID: "fixture-original-observation", attachmentID: "original-attachment",
            belongsToOriginalDraft: true, reason: "Original unknown; do not replay")
        _ = try await db.apply(unknown)

        let sql = try SQLiteDatabase(url: databaseURL())
        try sql.execute("UPDATE operations SET target_json=? WHERE id=?", [frozenTargetJSON, op.id.uuidString])
        let originalColumns = "id,asset_id,attempt,target_key,target_json,phase,created_at,receipt_json"
        let before = try sql.rows("SELECT \(originalColumns) FROM operations WHERE id=?", [op.id.uuidString])
        let beforeImage = try sql.rows("SELECT image_json FROM assets WHERE id=?", [image.id.uuidString])
        let reopened = try store()
        try await reopened.recoverInterruptedOperations()
        try await assertBusy(reopened, target(identity(draftA.lowercased()), window: "moved-window",
            document: "replacement-document", generation: "rearmed"))
        let (_, next) = try await prepare(reopened, target(identity(draftB)))
        try await reopened.markDispatchIntent(next.id)

        let saved = try await reopened.operation(id: op.id)
        let savedReceipt = try await reopened.receipt(for: op.id)
        let savedImage = try await reopened.asset(id: image.id)
        let savedStart = try await reopened.uploadStartReceipt(for: op.id)
        let savedCompensation = try await reopened.compensation(for: op.id)
        let entered = try await reopened.operation(id: next.id)
        XCTAssertEqual(saved?.id, op.id); XCTAssertEqual(saved?.attempt, 1)
        XCTAssertEqual(saved?.target, original); XCTAssertEqual(saved?.phase, .unknown)
        XCTAssertEqual(savedReceipt, unknown)
        XCTAssertEqual(savedImage?.visibility, .visible); XCTAssertEqual(savedImage?.status, .unknown)
        XCTAssertNil(savedStart); XCTAssertNil(savedCompensation)
        XCTAssertEqual(entered?.phase, .dispatchIntent)
        XCTAssertEqual(try sql.rows("SELECT \(originalColumns) FROM operations WHERE id=?", [op.id.uuidString]), before)
        XCTAssertEqual(try sql.rows("SELECT target_json FROM operations WHERE id=?", [op.id.uuidString]), [[frozenTargetJSON]])
        XCTAssertEqual(try sql.rows("SELECT image_json FROM assets WHERE id=?", [image.id.uuidString]), beforeImage)
        XCTAssertEqual(try sql.rows("SELECT COUNT(*) FROM operations WHERE asset_id=?", [image.id.uuidString]), [["1"]])
        XCTAssertEqual(try sql.rows("PRAGMA user_version"), [["3"]])
        XCTAssertEqual(try sql.rows("PRAGMA quick_check"), [["ok"]])
    }

    func testOldUnknownRowsKeepWholeTabProtectionAgainstPersistedDraftAfterReopen() async throws {
        let fixtures: [LogicalDraftIdentity?] = [nil,
            identity("local-chatgpt:\(draftA)", profile: localProfile),
            identity(draftA, profile: "old-unknown-profile"), identity("\(draftA) ")]
        for (index, logical) in fixtures.enumerated() {
            let name = "legacy-unknown-\(index)"
            let db = try store(name)
            let original = target(logical)
            let old = try await makeUnknown(db, original)
            let reopened = try store(name)
            try await reopened.recoverInterruptedOperations()
            try await assertBusy(reopened, target(identity(draftB), window: "moved-window", generation: "rearmed"))
            let saved = try await reopened.operation(id: old.id)
            XCTAssertEqual(saved?.id, old.id); XCTAssertEqual(saved?.target, original)
            XCTAssertEqual(saved?.attempt, 1); XCTAssertEqual(saved?.phase, .unknown)
            let sql = try SQLiteDatabase(url: databaseURL(name))
            XCTAssertEqual(try sql.rows("SELECT COUNT(*) FROM operations WHERE asset_id=?", [old.assetID.uuidString]), [["1"]])
        }
    }

    func testLegacyAndCrossProfileCompensationKeepAuditAndLockAfterReopen() async throws {
        let fixtures: [LogicalDraftIdentity?] = [nil, identity("local-chatgpt:\(draftA)", profile: localProfile)]
        for (index, logical) in fixtures.enumerated() {
            let name = "legacy-compensated-\(index)"
            let db = try store(name), original = target(logical)
            let (image, op) = try await prepare(db, original)
            try await db.markDispatchIntent(op.id)
            let success = TransferReceipt(operationID: op.id, assetID: image.id, attempt: 1,
                assetSHA256: image.sha256, target: original, outcome: .verifiedReady,
                profileID: "synthetic-completion", attachmentID: "original-attachment",
                positiveReady: true, belongsToOriginalDraft: true)
            _ = try await db.apply(success, policy: .init(syntheticAcceptanceProfiles: ["synthetic-completion": .webChat]))
            let failure = TransferReceipt(operationID: op.id, assetID: image.id, attempt: 1,
                assetSHA256: image.sha256, target: original, outcome: .unknown,
                profileID: success.profileID, attachmentID: success.attachmentID,
                belongsToOriginalDraft: true, hasError: true)
            _ = try await db.apply(failure)
            let audit = try await db.compensation(for: op.id)
            XCTAssertNotNil(audit)
            let sql = try SQLiteDatabase(url: databaseURL(name))
            let beforeAudit = try sql.rows("SELECT evidence_json FROM compensations WHERE operation_id=?", [op.id.uuidString])
            let reopened = try store(name)
            try await reopened.recoverInterruptedOperations()
            try await assertBusy(reopened, target(identity(draftB), generation: "fresh-arm"))
            let saved = try await reopened.operation(id: op.id)
            let savedAudit = try await reopened.compensation(for: op.id)
            let savedImage = try await reopened.asset(id: image.id)
            XCTAssertEqual(saved?.target, original); XCTAssertEqual(saved?.attempt, 1)
            XCTAssertEqual(saved?.phase, .compensated)
            XCTAssertEqual(savedAudit, audit)
            XCTAssertEqual(savedImage?.visibility, .swallowed); XCTAssertEqual(savedImage?.status, .unknown)
            XCTAssertEqual(try sql.rows("SELECT evidence_json FROM compensations WHERE operation_id=?", [op.id.uuidString]), beforeAudit)
        }
    }

    func testPersistedIdentityNeverRelaxesFullTargetEqualityForStartOrCompletion() async throws {
        let db = try store(), original = target(identity(draftA))
        let (image, op) = try await prepare(db, original)
        try await db.markDispatchIntent(op.id)
        let policy = ReceiptPolicy(syntheticAcceptanceProfiles: ["synthetic-completion": .webChat],
            syntheticUploadStartProfiles: ["synthetic-start": .webChat])
        let wrongTargets = [target(identity(draftA.lowercased())),
            target(identity(draftA), window: "moved-window"),
            target(identity(draftA), document: "replacement-document"),
            target(identity(draftA), composer: "replacement-composer"),
            target(identity(draftA), generation: "rearmed-generation"),
            target(identity(draftB)), target(identity("local-chatgpt:\(draftA)", profile: localProfile)]
        for wrongTarget in wrongTargets {
            for outcome in [ReceiptOutcome.uploadStarted, .verifiedReady] {
                let isStart = outcome == .uploadStarted
                let wrong = TransferReceipt(operationID: op.id, assetID: image.id, attempt: 1,
                    assetSHA256: image.sha256, target: wrongTarget, outcome: outcome,
                    profileID: "synthetic-completion", attachmentID: "original-attachment",
                    positiveReady: !isStart, belongsToOriginalDraft: true, isUploading: isStart,
                    uploadStartEvidence: isStart ? UploadStartEvidence(profileID: "synthetic-start",
                        signal: .correlatedProgress, evidenceID: "synthetic-original-start") : nil)
                do {
                    _ = try await db.apply(wrong, policy: policy)
                    XCTFail("A business draft match must not replace complete original target equality")
                } catch RiftletError.mismatchedReceipt {}
            }
        }
        let saved = try await db.operation(id: op.id)
        let record = try await db.asset(id: image.id)
        let receipt = try await db.receipt(for: op.id)
        let start = try await db.uploadStartReceipt(for: op.id)
        XCTAssertEqual(saved?.phase, .dispatchIntent)
        XCTAssertEqual(record?.visibility, .visible); XCTAssertEqual(record?.status, .transferring)
        XCTAssertNil(receipt); XCTAssertNil(start)
    }
}
