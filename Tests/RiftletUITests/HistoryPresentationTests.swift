import XCTest
import RiftletCore
@testable import RiftletUI

final class HistoryPresentationTests: XCTestCase {
    private func asset(sequence: Int64 = 1, status: QueueStatus = .pending,
                       visibility: QueueVisibility = .visible, operationID: UUID? = nil,
                       capturedAt: Date? = nil, firstSeenAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                       id: UUID = UUID()) -> AssetRecord {
        AssetRecord(image: ImportedAsset(id: id, sourceKey: "history-\(id.uuidString)",
                                         fileName: "\(id.uuidString).png", sha256: String(repeating: "a", count: 64),
                                         byteCount: 128, pixelWidth: 1200, pixelHeight: 800, mediaType: "image/png",
                                         capturedAt: capturedAt, firstSeenAt: firstSeenAt, origin: .synthetic),
                    sequence: sequence, status: status, activeOperationID: operationID, visibility: visibility)
    }

    private func target(documentID: String = "history") -> TargetLease {
        TargetLease(adapterID: "simulation", surface: .simulation, applicationID: "com.riftlet.simulation",
                    sessionID: "fixture", windowID: "fixture", documentID: documentID,
                    composerID: "fixture", draftGeneration: "1")
    }

    private func operation(for record: AssetRecord, phase: OperationPhase, attempt: Int = 1) throws -> TransferOperation {
        let targetObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target()))
        let object: [String: Any] = [
            "id": (record.activeOperationID ?? UUID()).uuidString,
            "assetID": record.id.uuidString, "attempt": attempt, "target": targetObject,
            "phase": phase.rawValue, "createdAt": 0, "updatedAt": 0
        ]
        return try JSONDecoder().decode(TransferOperation.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func failure(for record: AssetRecord, operation: TransferOperation,
                         assetID: UUID? = nil, attempt: Int? = nil, lease: TargetLease? = nil,
                         safeToRetry: Bool = true) -> TransferReceipt {
        TransferReceipt(operationID: operation.id, assetID: assetID ?? record.id,
                        attempt: attempt ?? operation.attempt, assetSHA256: record.image.sha256,
                        target: lease ?? operation.target, outcome: .definitiveFailure,
                        profileID: "simulation-v1", attachmentID: "synthetic-history", belongsToOriginalDraft: true,
                        hasError: true, safeToRetry: safeToRetry)
    }

    func testVisibilityAndVerificationRemainSeparateHistoryFilters() {
        let visible = RiftHistoryEntry(record: asset())
        let hiddenUnknown = RiftHistoryEntry(record: asset(status: .unknown, visibility: .swallowed))
        let hiddenSuccess = RiftHistoryEntry(record: asset(status: .used, visibility: .swallowed))
        let archived = RiftHistoryEntry(record: asset(visibility: .archived))
        let removedUnknown = RiftHistoryEntry(record: asset(status: .unknown, visibility: .removed))
        let input = [visible, hiddenUnknown, hiddenSuccess, archived, removedUnknown]
        XCTAssertEqual(Set(HistoryPresentation.matching(input, filter: .needsVerification).map(\.id)),
                       Set([hiddenUnknown.id, removedUnknown.id]))
        XCTAssertEqual(Set(HistoryPresentation.matching(input, filter: .swallowed).map(\.id)),
                       Set([hiddenUnknown.id, hiddenSuccess.id]))
        XCTAssertEqual(HistoryPresentation.matching(input, filter: .archived).map(\.id), [archived.id])
        XCTAssertEqual(HistoryPresentation.matching(input, filter: .removed).map(\.id), [removedUnknown.id])
        XCTAssertTrue(HistoryPresentation.stateText(for: hiddenUnknown).contains("Needs review"))
        XCTAssertFalse(HistoryPresentation.stateText(for: hiddenUnknown).contains("Attached"))
    }

    func testPreInputCancellationIsNotPresentedAsRemoteUploadFailure() throws {
        let record = asset(status: .failed, operationID: UUID())
        let op = try operation(for: record, phase: .failed)
        let entry = RiftHistoryEntry(record: record, operation: op)
        XCTAssertFalse(entry.isConfirmedFailure)
        XCTAssertFalse(RiftHistoryFilter.failed.includes(entry))
        XCTAssertEqual(HistoryPresentation.stateText(for: entry), "Not attached · ready to try again")
    }

    func testConfirmedFailureRequiresCurrentOperationAndCompleteReceiptIdentity() throws {
        let record = asset(status: .pending, operationID: UUID())
        let op = try operation(for: record, phase: .failed)
        let valid = RiftHistoryEntry(record: record, operation: op, lastReceipt: failure(for: record, operation: op))
        XCTAssertTrue(valid.isConfirmedFailure)
        XCTAssertTrue(RiftHistoryFilter.failed.includes(valid))
        XCTAssertEqual(HistoryPresentation.stateText(for: valid), "Upload failed · ready to try again")
        for receipt in [failure(for: record, operation: op, assetID: UUID()),
                        failure(for: record, operation: op, attempt: 2),
                        failure(for: record, operation: op, lease: target(documentID: "another")),
                        failure(for: record, operation: op, safeToRetry: false)] {
            XCTAssertFalse(RiftHistoryEntry(record: record, operation: op, lastReceipt: receipt).isConfirmedFailure)
        }
        let compensated = try operation(for: record, phase: .compensated)
        XCTAssertFalse(RiftHistoryEntry(record: record, operation: compensated,
                                       lastReceipt: failure(for: record, operation: compensated)).isConfirmedFailure)
    }

    func testRestoreRequiresCoreEligibilityAndDoesNotExposeSwallowedOrUnknownAsRetry() throws {
        for visibility in [QueueVisibility.archived, .removed] {
            let pending = asset(visibility: visibility)
            XCTAssertFalse(RiftHistoryEntry(record: pending).canRestoreToRift)
            XCTAssertTrue(RiftHistoryEntry(record: pending, canRestore: true).canRestoreToRift)
            for status in [QueueStatus.unknown, .transferring, .used, .missing] {
                XCTAssertFalse(RiftHistoryEntry(record: asset(status: status, visibility: visibility),
                                                canRestore: true).canRestoreToRift)
            }
        }
        for visibility in [QueueVisibility.visible, .swallowed] {
            XCTAssertFalse(RiftHistoryEntry(record: asset(visibility: visibility), canRestore: true).canRestoreToRift)
        }
        let failed = asset(status: .failed, visibility: .removed, operationID: UUID())
        let op = try operation(for: failed, phase: .failed)
        XCTAssertTrue(RiftHistoryEntry(record: failed, operation: op, canRestore: true).canRestoreToRift)
        XCTAssertFalse(RiftHistoryEntry(record: failed, canRestore: true).canRestoreToRift)
        XCTAssertFalse(RiftHistoryEntry(record: failed, operation: try operation(for: failed, phase: .unknown),
                                        canRestore: true).canRestoreToRift)
        let stale = asset(status: .pending, visibility: .removed, operationID: UUID())
        XCTAssertFalse(RiftHistoryEntry(record: stale, operation: op, canRestore: true).canRestoreToRift)
    }

    func testRemovalEligibilityIsVisibilityOnlyAndDoesNotPretendToRemoveAttachments() {
        for status in [QueueStatus.pending, .transferring, .unknown, .failed, .missing] {
            XCTAssertTrue(RiftHistoryEntry(record: asset(status: status)).canRemoveFromRift)
        }
        for visibility in [QueueVisibility.swallowed, .archived, .removed] {
            XCTAssertFalse(RiftHistoryEntry(record: asset(visibility: visibility)).canRemoveFromRift)
        }
    }

    func testHistoryOrderingUsesCaptureTimeThenSequenceWithoutChangingIdentity() {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let first = RiftHistoryEntry(record: asset(sequence: 1, capturedAt: time))
        let second = RiftHistoryEntry(record: asset(sequence: 2, capturedAt: time))
        let latest = RiftHistoryEntry(record: asset(sequence: 3, firstSeenAt: time.addingTimeInterval(60)))
        let result = HistoryPresentation.matching([first, latest, second])
        XCTAssertEqual(result.map(\.id), [latest.id, second.id, first.id])
        XCTAssertEqual(result.map(\.record.sequence), [3, 2, 1])
    }

    func testLocalPageSearchSupportsDateImageIdentityAndState() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let archived = RiftHistoryEntry(record: asset(visibility: .archived))
        let unknown = RiftHistoryEntry(record: asset(status: .unknown, visibility: .swallowed,
                                                     firstSeenAt: Date(timeIntervalSince1970: 1_700_086_400)))
        let input = [archived, unknown]
        XCTAssertEqual(HistoryPresentation.matching(input, query: "  archived  ", timeZone: utc).map(\.id), [archived.id])
        XCTAssertEqual(HistoryPresentation.matching(input, query: unknown.id.uuidString.lowercased(), timeZone: utc).map(\.id), [unknown.id])
        XCTAssertEqual(HistoryPresentation.matching(input, query: "2023-11-15", timeZone: utc).map(\.id), [unknown.id])
        XCTAssertTrue(HistoryPresentation.matching(input, filter: .archived, query: "Needs review", timeZone: utc).isEmpty)
        XCTAssertEqual(HistoryPresentation.dateText(for: archived, timeZone: utc), "2023-11-14 22:13")
    }

    func testUnknownCannotBeDisplayedAsConfirmedFailureFromAnInconsistentSnapshot() throws {
        let record = asset(status: .unknown, visibility: .swallowed, operationID: UUID())
        let op = try operation(for: record, phase: .failed)
        let entry = RiftHistoryEntry(record: record, operation: op,
                                     lastReceipt: failure(for: record, operation: op), canRestore: true)
        XCTAssertTrue(entry.needsVerification)
        XCTAssertFalse(entry.isConfirmedFailure)
        XCTAssertFalse(entry.canRestoreToRift)
    }

    func testNewUnresolvedOperationObservationOverridesStaleUsedAssetSnapshot() throws {
        let record = asset(status: .used, visibility: .swallowed, operationID: UUID())
        for phase in [OperationPhase.compensated, .unknown, .dispatchIntent, .prepared] {
            let op = try operation(for: record, phase: phase)
            let entry = RiftHistoryEntry(record: record, operation: op)
            XCTAssertTrue(entry.needsVerification)
            XCTAssertTrue(HistoryPresentation.stateText(for: entry).contains("Needs review"))
            XCTAssertFalse(HistoryPresentation.stateText(for: entry).contains("Attached"))
            XCTAssertFalse(entry.canRestoreToRift)
        }
    }
}
