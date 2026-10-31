import Foundation
import XCTest
@testable import RiftletCore

final class ChromeSessionMigrationTests: XCTestCase {
    private let legacy = "11:100.5"
    private let kernel = "chrome-kernel-v1:11:200:4"
    private let a = LogicalDraftIdentity(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                                        id: "11111111-1111-4111-8111-111111111111")
    private let b = LogicalDraftIdentity(profileID: "chatgpt-composer-react-persisted-20261027-v1",
                                        id: "22222222-2222-4222-8222-222222222222")
    private func target(_ session: String, _ logical: LogicalDraftIdentity?, tab: String = "1",
                        adapter: String = "chatgpt-web", app: String = "com.google.Chrome",
                        surface: TargetSurface = .webChat) -> TargetLease {
        .init(adapterID: adapter, surface: surface, applicationID: app, sessionID: session,
              windowID: "1", tabID: tab, documentID: "original-document", composerID: "original-composer",
              draftGeneration: "original-generation", logicalDraftIdentity: logical)
    }
    private func conflict(_ x: TargetLease, _ y: TargetLease, _ expected: Bool,
                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(x.conflictsForDispatch(with: y), expected, file: file, line: line)
        XCTAssertEqual(y.conflictsForDispatch(with: x), expected, file: file, line: line)
    }
    private func root() throws -> URL {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-session-migration-\(UUID())")
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
    }
    private func prepare(_ db: QueueStore, _ lease: TargetLease) async throws -> TransferOperation {
        let id = UUID(), asset = ImportedAsset(id: id, sourceKey: "fixture-\(id)", fileName: "\(id).png",
            sha256: String(repeating: "a", count: 64), byteCount: 100, pixelWidth: 8, pixelHeight: 8,
            mediaType: "image/png", origin: .synthetic)
        _ = try await db.importAsset(asset)
        return try await db.prepare(assetID: id, target: lease)
    }
    private func blocked(_ db: QueueStore, _ op: TransferOperation) async throws {
        do { try await db.markDispatchIntent(op.id); XCTFail("Mixed session spelling bypassed unresolved operation") }
        catch RiftletError.targetBusy {}
        let after = try await db.operation(id: op.id)
        XCTAssertEqual(after?.phase, .prepared)
    }

    func testMixedSpellingRetainsConflictWithoutRewritingReceiptIdentity() throws {
        let old = target(legacy, a), new = target(kernel, a)
        conflict(old, new, true)
        XCTAssertNotEqual(old.stableKey, new.stableKey)
        XCTAssertNotEqual(old.serializationKey, new.serializationKey)
        XCTAssertNotEqual(old, new)
        XCTAssertEqual(try JSONDecoder().decode(TargetLease.self, from: JSONEncoder().encode(old)), old)
    }
    func testOnlyRecognizedDifferentSameProfileDraftsNarrowMixedConflict() {
        conflict(target(legacy, a), target(kernel, b), false)
        for logical in [nil, LogicalDraftIdentity(profileID: "unknown", id: b.id),
                        LogicalDraftIdentity(profileID: a.profileID, id: "invalid"),
                        LogicalDraftIdentity(profileID: "chatgpt-composer-react-20261027-v1",
                                             id: "local-chatgpt:22222222-2222-4222-8222-222222222222")] {
            conflict(target(legacy, logical), target(kernel, a), true)
        }
    }
    func testDifferentReceiverAndSameFormatBirthRemainIndependent() {
        let old = target(legacy, a)
        conflict(old, target("chrome-kernel-v1:12:200:4", a), false)
        conflict(old, target(kernel, a, tab: "2"), false)
        conflict(old, target(kernel, a, tab: ""), false)
        conflict(old, target(kernel, a, adapter: "other"), false)
        conflict(old, target(kernel, a, app: "other"), false)
        conflict(old, target(kernel, a, surface: .webWork), false)
        conflict(target(kernel, a), target("chrome-kernel-v1:11:200:5", a), false)
        conflict(old, target("11:101.5", a), false)
    }
    func testMalformedOrAmbiguousSessionSpellingsNeverCreateAliases() {
        for bad in ["", "11:", ":100.5", "011:100.5", "-11:100.5", "2147483648:100.5",
                    "11:nan", "11:inf", "11:-1.0", "11:100.50", "11:1e2", "11:100.5:extra",
                    " 11:100.5", "11:100.5\n"] {
            conflict(target(bad, a), target(kernel, a), false)
        }
        for bad in ["chrome-kernel-v1:11:200:", "chrome-kernel-v1:011:200:4",
                    "chrome-kernel-v1:11:0200:4", "chrome-kernel-v1:11:0:4",
                    "chrome-kernel-v1:11:200:1000000", "chrome-kernel-v1:11:200:-1",
                    "chrome-kernel-v1:11:200:04", "chrome-kernel-v1:11:200:4:extra",
                    "chrome-kernel-v1:11:18446744073709551616:4", "chrome-kernel-v2:11:200:4"] {
            conflict(target(legacy, a), target(bad, a), false)
        }
    }
    func testUnknownSurvivesSecondConnectionReopenAndAToBToAInBothDirections() async throws {
        for (oldSession, newSession) in [(legacy, kernel), (kernel, legacy)] {
            let p = try root(); defer { try? FileManager.default.removeItem(at: p) }
            let url = p.appendingPathComponent("queue.sqlite")
            let first = try QueueStore(databaseURL: url)
            let old = try await prepare(first, target(oldSession, a))
            try await first.markDispatchIntent(old.id)
            try await first.markUnknown(old.id, reason: "fixture unresolved input; no replay")
            let second = try QueueStore(databaseURL: url)
            try await second.recoverInterruptedOperations()
            let same = try await prepare(second, target(newSession, a)); try await blocked(second, same)
            let different = try await prepare(second, target(newSession, b))
            try await second.markDispatchIntent(different.id)
            try await second.markUnknown(different.id, reason: "independent fixture B")
            let reopened = try QueueStore(databaseURL: url)
            let back = try await prepare(reopened, target(newSession, a)); try await blocked(reopened, back)
            let retained = try await reopened.operation(id: old.id)
            XCTAssertEqual(retained?.target, old.target); XCTAssertEqual(retained?.phase, .unknown)
            XCTAssertEqual(retained?.attempt, 1)
            let start = try await reopened.uploadStartReceipt(for: old.id)
            XCTAssertNil(start)
        }
    }
    func testUnknownWithoutLogicalIdentityRetainsWholeTabLock() async throws {
        let p = try root(); defer { try? FileManager.default.removeItem(at: p) }
        let url = p.appendingPathComponent("queue.sqlite"), db = try QueueStore(databaseURL: url)
        let old = try await prepare(db, target(legacy, nil))
        try await db.markDispatchIntent(old.id); try await db.markUnknown(old.id, reason: "legacy unknown")
        let reopened = try QueueStore(databaseURL: url)
        let next = try await prepare(reopened, target(kernel, b)); try await blocked(reopened, next)
        let retained = try await reopened.operation(id: old.id)
        XCTAssertNil(retained?.target.logicalDraftIdentity)
    }
    func testTwoConnectionsRaceDifferentSpellingsOnlyOneDispatches() async throws {
        let p = try root(); defer { try? FileManager.default.removeItem(at: p) }
        let url = p.appendingPathComponent("queue.sqlite")
        let first = try QueueStore(databaseURL: url), second = try QueueStore(databaseURL: url)
        let one = try await prepare(first, target(legacy, a)), two = try await prepare(second, target(kernel, a))
        @Sendable func attempt(_ store: QueueStore, _ id: UUID) async throws -> Bool {
            do { try await store.markDispatchIntent(id); return true }
            catch RiftletError.targetBusy { return false }
        }
        async let x = attempt(first, one.id), y = attempt(second, two.id)
        let results = try await [x, y]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let rows = try await [first.operation(id: one.id), second.operation(id: two.id)]
        XCTAssertEqual(rows.filter { $0?.phase == .dispatchIntent }.count, 1)
        XCTAssertEqual(rows.filter { $0?.phase == .prepared }.count, 1)
    }
}
