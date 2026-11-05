import Foundation
import XCTest
@testable import RiftletCore

final class AcceptedAttachmentHistoryIsolationTests: XCTestCase {
    func testCurrentAcceptanceSwallowsWithoutDecodingHistoricalOwnership() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("accepted-history-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = ReceiptPolicy(syntheticUploadStartProfiles: ["current-acceptance": .webChat])

        for checkpointPrefix in ["transfer-input-isolation-v1:", "transfer-platform-task-v1:"] {
            let url = directory.appendingPathComponent("\(UUID()).sqlite")
            let store = try QueueStore(databaseURL: url), sql = try SQLiteDatabase(url: url)
            let oldAsset = asset(), currentAsset = asset()
            _ = try await store.importAsset(oldAsset)
            _ = try await store.importAsset(currentAsset)
            let old = try await store.prepare(assetID: oldAsset.id, target: target(document: "old-document"))
            _ = try await store.markIndependentFileInputIntent(old.id, ownerID: UUID())
            try await store.markUnknown(old.id, reason: "Historical UNKNOWN must stay untouched")
            let key = checkpointPrefix + old.id.uuidString
            let malformed = Data("{\"version\":".utf8)
            try await store.saveCheckpoint(malformed, for: key)

            func oldRows() throws -> [[[String?]]] {
                [try sql.rows("SELECT * FROM operations WHERE id=?", [old.id.uuidString]),
                 try sql.rows("SELECT * FROM assets WHERE id=?", [oldAsset.id.uuidString]),
                 try sql.rows("SELECT * FROM checkpoints WHERE key LIKE ? ORDER BY key", ["%" + old.id.uuidString]),
                 try sql.rows("SELECT * FROM upload_starts WHERE operation_id=?", [old.id.uuidString])]
            }
            let before = try oldRows()
            let current = try await store.prepare(assetID: currentAsset.id, target: target(document: "new-document"))
            XCTAssertTrue(old.target.conflictsForDispatch(with: current.target),
                          "The old scan must actually include this same native tab across documents")
            _ = try await store.markIndependentFileInputIntent(current.id, ownerID: UUID())
            func receipt(_ signal: UploadStartSignal) -> TransferReceipt {
                .init(operationID: current.id, assetID: currentAsset.id, attempt: current.attempt,
                      assetSHA256: currentAsset.sha256, target: current.target, outcome: .uploadStarted,
                      profileID: "current-input-fixture", attachmentID: "new-current-attachment",
                      belongsToOriginalDraft: true, isUploading: signal != .attachmentAccepted,
                      reason: "Current composer accepted the new file",
                      uploadStartEvidence: .init(profileID: "current-acceptance", signal: signal,
                                                evidenceID: "current-attachment-1"))
            }

            // The legacy path still reads its original ownership evidence. This
            // also reproduces the historical decode failure before exercising
            // the independent current-attachment START on the same database.
            do {
                _ = try await store.apply(receipt(.correlatedProgress), policy: policy)
                XCTFail("Legacy ownership validation unexpectedly ignored its malformed checkpoint")
            } catch is DecodingError {}
            let absentStart = try await store.uploadStartReceipt(for: current.id)
            let stillVisible = try await store.asset(id: currentAsset.id)
            XCTAssertNil(absentStart)
            XCTAssertEqual(stillVisible?.visibility, .visible)

            let accepted = receipt(.attachmentAccepted)
            let result = try await store.apply(accepted, policy: policy)
            let recordedStart = try await store.uploadStartReceipt(for: current.id)
            let unchangedOld = try await store.operation(id: old.id)
            let unchangedCheckpoint = try await store.checkpoint(for: key)
            XCTAssertEqual(result.visibility, .swallowed)
            XCTAssertEqual(recordedStart, accepted)
            XCTAssertEqual(unchangedOld?.phase, .unknown)
            XCTAssertEqual(unchangedCheckpoint, malformed)
            XCTAssertEqual(try oldRows(), before, "No historical row or proof bytes may be rewritten")
        }
    }

    private func asset() -> ImportedAsset {
        let id = UUID()
        return .init(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
                     sha256: String(repeating: "a", count: 64), byteCount: 1,
                     pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
    }

    private func target(document: String) -> TargetLease {
        .init(adapterID: "independent-file-fixture", surface: .webChat, applicationID: "com.google.Chrome",
              sessionID: "fixture-process", windowID: "1", tabID: "1", documentID: document,
              composerID: "composer", draftGeneration: "1", clickBindingID: UUID())
    }
}
