import AppKit
import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

/// These exercise actual NSPasteboard named-board I/O on the macOS runner.
/// They never use NSPasteboard.general, input events or a ChatGPT process.
final class NativePasteboardDriverTests: XCTestCase {
    @MainActor
    private func board() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.riftlet.tests.\(UUID().uuidString)"))
    }

    @MainActor
    private func write(_ items: [[String: Data]], to board: NSPasteboard) throws {
        let native = try items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (rawType, data) in types {
                guard item.setData(data, forType: NSPasteboard.PasteboardType(rawType)) else {
                    throw NativePasteboardError.itemPreparationFailed
                }
            }
            return item
        }
        board.clearContents()
        if !native.isEmpty { XCTAssertTrue(board.writeObjects(native)) }
    }

    private func payload() async throws -> ClipboardAttachmentPayload {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-native-payload-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "synthetic.png",
            sha256: String(repeating: "a", count: 64), byteCount: 4,
            pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        let target = TargetLease(adapterID: "mac-test", surface: .macChat, applicationID: "synthetic.fixture",
            sessionID: "fixture-session", windowID: "fixture-window", documentID: "fixture-document",
            composerID: "fixture-composer", draftGeneration: "fixture-generation")
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        _ = try await store.importAsset(asset)
        let operation = try await store.prepare(assetID: asset.id, target: target)
        try await store.markDispatchIntent(operation.id)
        let saved = try await store.operation(id: operation.id)
        let request = TransferRequest(operation: try XCTUnwrap(saved), asset: asset,
            fileURL: directory.appendingPathComponent(asset.fileName))
        return try ClipboardAttachmentPayload(request: request)
    }

    @MainActor
    func testNativeRoundTripPreservesEveryMaterializedItemAndRepresentation() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        let old: [[String: Data]] = [
            [NSPasteboard.PasteboardType.string.rawValue: Data("old synthetic text".utf8),
             NSPasteboard.PasteboardType.rtf.rawValue: Data("{\\rtf1 old}".utf8)],
            ["com.riftlet.tests.binary": Data([0, 1, 2, 255])]
        ]
        try write(old, to: board)
        let driver = try NativePasteboardDriver(pasteboard: board)
        let before = try await driver.capture()
        XCTAssertEqual(before.snapshot.items, old)
        let payload = try await payload()
        let written = try await driver.writeIfUnchanged(payload, expectedChangeCount: before.changeCount)
        let owner = try XCTUnwrap(written)
        XCTAssertEqual(owner.marker, payload.marker)
        XCTAssertEqual(try driver.currentOwnerSynchronously(), owner)
        let current = try await driver.capture()
        XCTAssertEqual(current.snapshot.items, [payload.item])
        let restored = try await driver.restoreIfOwned(before.snapshot, expectedOwner: owner)
        XCTAssertTrue(restored)
        let after = try await driver.capture()
        XCTAssertEqual(after.snapshot, before.snapshot)
        XCTAssertNil(try driver.currentOwnerSynchronously().marker)
    }

    @MainActor
    func testEmptyBoardCanBeRestoredAfterOwnedWrite() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        board.clearContents()
        let driver = try NativePasteboardDriver(pasteboard: board)
        let before = try await driver.capture()
        XCTAssertEqual(before.snapshot.items, [])
        let payload = try await payload()
        let written = try await driver.writeIfUnchanged(payload, expectedChangeCount: before.changeCount)
        let owner = try XCTUnwrap(written)
        let restored = try await driver.restoreIfOwned(before.snapshot, expectedOwner: owner)
        XCTAssertTrue(restored)
        let after = try await driver.capture()
        XCTAssertTrue(after.snapshot.items.isEmpty)
    }

    @MainActor
    func testInterveningCopyPreventsAttachmentWriteAndLeavesNewCopy() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        try write([["public.utf8-plain-text": Data("first".utf8)]], to: board)
        let driver = try NativePasteboardDriver(pasteboard: board)
        let before = try await driver.capture()
        let later = [["public.utf8-plain-text": Data("later user copy".utf8)]]
        try write(later, to: board)
        let latestCount = board.changeCount
        let payload = try await payload()
        let result = try await driver.writeIfUnchanged(payload, expectedChangeCount: before.changeCount)
        XCTAssertNil(result)
        XCTAssertEqual(board.changeCount, latestCount)
        let final = try await driver.capture()
        XCTAssertEqual(final.snapshot.items, later)
    }

    @MainActor
    func testInterveningCopyAndForgedSameMarkerCannotAuthorizeRestoration() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        try write([["public.utf8-plain-text": Data("first".utf8)]], to: board)
        let driver = try NativePasteboardDriver(pasteboard: board)
        let before = try await driver.capture()
        let payload = try await payload()
        let written = try await driver.writeIfUnchanged(payload, expectedChangeCount: before.changeCount)
        let owner = try XCTUnwrap(written)
        // The marker alone is insufficient: a later copy has a different count.
        let later = [["public.utf8-plain-text": Data("later".utf8),
                      ClipboardAttachmentPayload.markerType: Data(payload.marker.utf8)]]
        try write(later, to: board)
        let latestCount = board.changeCount
        let result = try await driver.restoreIfOwned(before.snapshot, expectedOwner: owner)
        XCTAssertFalse(result)
        XCTAssertEqual(board.changeCount, latestCount)
        let final = try await driver.capture()
        XCTAssertEqual(final.snapshot.items, later)
    }

    @MainActor
    func testUnreadablePromisedAndOversizedCaptureDeclineBeforeMutation() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        let driver = try NativePasteboardDriver(pasteboard: board, maximumSnapshotBytes: 3)
        board.declareTypes([NSPasteboard.PasteboardType("com.riftlet.tests.unavailable")], owner: nil)
        var count = board.changeCount
        do { _ = try await driver.capture(); XCTFail("Unreadable declared data silently omitted") }
        catch NativePasteboardError.unreadableRepresentation {}
        XCTAssertEqual(board.changeCount, count)

        try write([[NSPasteboard.PasteboardType.filePromise.rawValue: Data([1])]], to: board)
        count = board.changeCount
        do { _ = try await driver.capture(); XCTFail("File promise treated as materialized data") }
        catch NativePasteboardError.promisedRepresentation {}
        XCTAssertEqual(board.changeCount, count)

        try write([["com.riftlet.tests.binary": Data([1, 2, 3, 4])]], to: board)
        count = board.changeCount
        do { _ = try await driver.capture(); XCTFail("Oversized clipboard accepted") }
        catch ClipboardOwnershipError.snapshotTooLarge {}
        XCTAssertEqual(board.changeCount, count)
    }

    @MainActor
    func testAmbiguousOrMalformedMarkersNeverBecomeAnOwner() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        let driver = try NativePasteboardDriver(pasteboard: board)
        let payload = try await payload()
        try write([payload.item, ["public.utf8-plain-text": Data("another item".utf8)]], to: board)
        XCTAssertNil(try driver.currentOwnerSynchronously().marker)
        try write([[ClipboardAttachmentPayload.markerType: Data("not-an-operation-marker".utf8)]], to: board)
        XCTAssertThrowsError(try driver.currentOwnerSynchronously()) {
            XCTAssertEqual($0 as? NativePasteboardError, .invalidMarker)
        }
    }

    @MainActor
    func testOversizedOrPromiseRestorePreparationCannotClearOwnedPayload() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        let driver = try NativePasteboardDriver(pasteboard: board, maximumSnapshotBytes: 1_024)
        let payload = try await payload()
        let written = try await driver.writeIfUnchanged(payload, expectedChangeCount: board.changeCount)
        let owner = try XCTUnwrap(written)
        let oversized = try ClipboardSnapshot(items: [["com.riftlet.tests.binary": Data(repeating: 1, count: 1_025)]])
        do { _ = try await driver.restoreIfOwned(oversized, expectedOwner: owner); XCTFail("Oversized restore") }
        catch ClipboardOwnershipError.snapshotTooLarge {}
        XCTAssertEqual(try driver.currentOwnerSynchronously(), owner)
        let promised = try ClipboardSnapshot(items: [[NSPasteboard.PasteboardType.filePromise.rawValue: Data([1])]])
        do { _ = try await driver.restoreIfOwned(promised, expectedOwner: owner); XCTFail("Promise restore") }
        catch NativePasteboardError.promisedRepresentation {}
        XCTAssertEqual(try driver.currentOwnerSynchronously(), owner)
        let final = try await driver.capture()
        XCTAssertEqual(final.snapshot.items, [payload.item])
    }

    @MainActor
    func testInvalidBoundsAndUnownedRestoreDoNotReadOrWriteClipboard() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        try write([["public.utf8-plain-text": Data("synthetic user copy".utf8)]], to: board)
        let count = board.changeCount
        XCTAssertThrowsError(try NativePasteboardDriver(pasteboard: board, maximumSnapshotBytes: -1))
        XCTAssertThrowsError(try NativePasteboardDriver(pasteboard: board, maximumSnapshotBytes: 16 * 1024 * 1024 + 1))
        let driver = try NativePasteboardDriver(pasteboard: board)
        let result = try await driver.restoreIfOwned(ClipboardSnapshot(items: []),
            expectedOwner: .init(changeCount: count, marker: nil))
        XCTAssertFalse(result)
        XCTAssertEqual(board.changeCount, count)
    }
}
