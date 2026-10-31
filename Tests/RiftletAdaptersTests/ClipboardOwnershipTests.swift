import AppKit
import CryptoKit
import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class ClipboardOwnershipTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-clipboard-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func fixture() async throws -> (TransferRequest, Data) {
        // Synthetic byte identity only; this unit suite does not claim codec validation.
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent("\(UUID()).png")
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: hash, byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1,
            mediaType: "image/png", origin: .synthetic)
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        _ = try await store.importAsset(asset)
        let target = TargetLease(adapterID: "mac-fixture", surface: .macChat,
            applicationID: "synthetic.mac.app", sessionID: "pid-and-launch-fixture",
            windowID: "window", documentID: "document", composerID: "composer", draftGeneration: "1")
        let operation = try await store.prepare(assetID: asset.id, target: target)
        try await store.markDispatchIntent(operation.id)
        let saved = try await store.operation(id: operation.id)
        return (TransferRequest(operation: try XCTUnwrap(saved), asset: asset, fileURL: file), bytes)
    }

    private var oldClipboard: ClipboardSnapshot {
        get throws {
            try ClipboardSnapshot(items: [
                ["public.utf8-plain-text": Data("previous user copy".utf8), "public.rtf": Data([1, 2, 3])],
                ["public.file-url": Data("file:///synthetic/second-item".utf8)]
            ])
        }
    }
    private var policy: ReceiptPolicy { .init(admittedProfiles: ["clipboard-synthetic-v1": .macChat]) }
    private func receipt(_ request: TransferRequest, outcome: ReceiptOutcome = .verifiedReady,
                         target: TargetLease? = nil) -> TransferReceipt {
        TransferReceipt(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
            target: target ?? request.operation.target, outcome: outcome, profileID: "clipboard-synthetic-v1",
            attachmentID: "synthetic-attachment", positiveReady: outcome == .verifiedReady,
            belongsToOriginalDraft: true)
    }

    func testSnapshotPreservesAllMaterializedItemsAndRejectsOversizedCapture() throws {
        let snapshot = try oldClipboard
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].count, 2)
        XCTAssertEqual(snapshot.items[0]["public.rtf"], Data([1, 2, 3]))
        XCTAssertThrowsError(try ClipboardSnapshot(items: [["public.text": Data(repeating: 1, count: 10)]], maximumBytes: 9))
        XCTAssertThrowsError(try ClipboardSnapshot(items: [["": Data()]]))
        let empty = try ClipboardSnapshot(items: [])
        XCTAssertEqual(empty.byteCount, 0)
    }

    func testPayloadHasRealFileURLPNGBytesAndUniqueOperationMarkerWithoutSystemAccess() async throws {
        let (request, bytes) = try await fixture()
        let a = try ClipboardAttachmentPayload(request: request, pngRepresentation: bytes)
        let b = try ClipboardAttachmentPayload(request: request)
        XCTAssertEqual(a.item[NSPasteboard.PasteboardType.fileURL.rawValue], Data(request.fileURL.absoluteString.utf8))
        XCTAssertEqual(a.item[NSPasteboard.PasteboardType.png.rawValue], bytes)
        XCTAssertNil(b.item[NSPasteboard.PasteboardType.png.rawValue])
        XCTAssertNotEqual(a.marker, b.marker)
        XCTAssertEqual(a.item[ClipboardAttachmentPayload.markerType], Data(a.marker.utf8))
        XCTAssertThrowsError(try ClipboardAttachmentPayload(request: request, pngRepresentation: Data([0, 1])))
    }

    func testMatchingOwnerRestoresCompleteOriginalSnapshotAfterAdmittedCompletion() async throws {
        let (request, _) = try await fixture()
        let payload = try ClipboardAttachmentPayload(request: request)
        let previous = try oldClipboard
        let lease = try ClipboardOwnershipLease(request: request, previous: previous,
                                                 payload: payload, writtenChangeCount: 10)
        let result = lease.restoration(currentChangeCount: 10, currentMarker: payload.marker,
                                       receipt: receipt(request), policy: policy)
        XCTAssertEqual(result, previous)
        XCTAssertNil(lease.restoration(currentChangeCount: 10, currentMarker: payload.marker,
                                      receipt: receipt(request), policy: .init()))
    }

    func testLaterUserCopyOrLostMarkerNeverProducesRestorePlan() async throws {
        let (request, _) = try await fixture()
        let payload = try ClipboardAttachmentPayload(request: request)
        let lease = try ClipboardOwnershipLease(request: request, previous: oldClipboard,
                                                 payload: payload, writtenChangeCount: 10)
        for (count, marker) in [(11, Optional(payload.marker)), (10, nil), (10, Optional("another-operation"))] {
            XCTAssertNil(lease.restoration(currentChangeCount: count, currentMarker: marker,
                                          receipt: receipt(request), policy: policy))
        }
    }

    func testUnknownFailureInputAndWrongDraftNeverRestoreOnTimerAssumption() async throws {
        let (request, _) = try await fixture()
        let payload = try ClipboardAttachmentPayload(request: request)
        let lease = try ClipboardOwnershipLease(request: request, previous: oldClipboard,
                                                 payload: payload, writtenChangeCount: 10)
        for outcome in [ReceiptOutcome.unknown, .inputTriggered, .attachedCandidate, .definitiveFailure] {
            XCTAssertNil(lease.restoration(currentChangeCount: 10, currentMarker: payload.marker,
                                          receipt: receipt(request, outcome: outcome), policy: policy))
        }
        let other = TargetLease(adapterID: "mac-fixture", surface: .macChat, applicationID: "synthetic.mac.app",
            sessionID: "pid-and-launch-fixture", windowID: "other-window", documentID: "document",
            composerID: "composer", draftGeneration: "2")
        XCTAssertNil(lease.restoration(currentChangeCount: 10, currentMarker: payload.marker,
                                      receipt: receipt(request, target: other), policy: policy))
    }

    func testPayloadFromAnotherOperationCannotBecomeThisOperationsLease() async throws {
        let (first, _) = try await fixture()
        let (second, _) = try await fixture()
        let payload = try ClipboardAttachmentPayload(request: first)
        XCTAssertThrowsError(try ClipboardOwnershipLease(request: second, previous: oldClipboard,
                                                          payload: payload, writtenChangeCount: 10))
    }
}
