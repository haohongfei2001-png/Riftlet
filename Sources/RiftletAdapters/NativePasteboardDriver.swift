import AppKit
import Foundation

public enum NativePasteboardError: Error, Equatable {
    case invalidLimit, unreadableRepresentation, promisedRepresentation, changedDuringRead
    case invalidMarker, itemPreparationFailed, writeUncertain
}

/// The AX input fragment uses this on MainActor without suspending between its
/// final ownership check and the evidence-selected Paste action.
@MainActor
public protocol SynchronousClipboardOwner: Sendable {
    func currentOwnerSynchronously() throws -> ClipboardOwnerState
}

/// Native implementation of M0's existing transaction boundary. The caller must
/// explicitly supply a pasteboard; construction does not read it or request OS
/// permission. Tests use unique named boards, never the user's general board.
///
/// MainActor serializes Riftlet's synchronous native fragments, not other apps.
/// NSPasteboard has no atomic compare-and-swap: another app can copy between any
/// two native calls. The process coordinator must additionally hold its lease.
/// A native data(forType:) may allocate before its size is known; our byte bound
/// limits retained snapshots, not the system API's allocation or provider time.
@MainActor
public final class NativePasteboardDriver: ClipboardTransactionDriver, SynchronousClipboardOwner {
    private let pasteboard: NSPasteboard
    private let maximumSnapshotBytes: Int

    public init(pasteboard: NSPasteboard, maximumSnapshotBytes: Int = 8 * 1024 * 1024) throws {
        guard maximumSnapshotBytes >= 0, maximumSnapshotBytes <= 16 * 1024 * 1024 else {
            throw NativePasteboardError.invalidLimit
        }
        self.pasteboard = pasteboard
        self.maximumSnapshotBytes = maximumSnapshotBytes
    }

    public func capture() async throws -> ClipboardCapturedState {
        try captureSynchronously()
    }

    public func owner() async throws -> ClipboardOwnerState {
        try currentOwnerSynchronously()
    }

    public func currentOwnerSynchronously() throws -> ClipboardOwnerState {
        let before = pasteboard.changeCount
        let items = try readableItems()
        var marker: String?
        // An operation payload is exactly one item. Never recognize a marker in
        // one item of an otherwise unrelated or ambiguous multi-item clipboard.
        if items.count == 1 {
            let types = try checkedTypes(items[0])
            let markerType = NSPasteboard.PasteboardType(ClipboardAttachmentPayload.markerType)
            if types.contains(markerType) {
                guard let bytes = items[0].data(forType: markerType), bytes.count <= 128,
                      let value = String(data: bytes, encoding: .utf8), validMarker(value) else {
                    throw NativePasteboardError.invalidMarker
                }
                marker = value
            }
        }
        guard before >= 0, pasteboard.changeCount == before else {
            throw NativePasteboardError.changedDuringRead
        }
        return ClipboardOwnerState(changeCount: before, marker: marker)
    }

    public func writeIfUnchanged(_ payload: ClipboardAttachmentPayload,
                                 expectedChangeCount: Int) async throws -> ClipboardOwnerState? {
        guard validMarker(payload.marker),
              payload.item[ClipboardAttachmentPayload.markerType] == Data(payload.marker.utf8) else {
            throw NativePasteboardError.invalidMarker
        }
        let snapshot = try ClipboardSnapshot(items: [payload.item], maximumBytes: maximumSnapshotBytes)
        let prepared = try prepare(snapshot)
        // Prepare every native representation before the last ownership check.
        guard expectedChangeCount >= 0, pasteboard.changeCount == expectedChangeCount else { return nil }
        let writtenCount = try replace(prepared, expected: snapshot)
        let owner = try currentOwnerSynchronously()
        guard owner.changeCount == writtenCount, owner.changeCount > expectedChangeCount,
              owner.marker == payload.marker else { throw NativePasteboardError.writeUncertain }
        return owner
    }

    public func restoreIfOwned(_ snapshot: ClipboardSnapshot,
                               expectedOwner: ClipboardOwnerState) async throws -> Bool {
        guard let marker = expectedOwner.marker, validMarker(marker), expectedOwner.changeCount >= 0 else {
            return false
        }
        // Validate the persisted/in-memory snapshot and materialize all native
        // items before the final check. Failure here cannot clear the clipboard.
        let bounded = try ClipboardSnapshot(items: snapshot.items, maximumBytes: maximumSnapshotBytes)
        let prepared = try prepare(bounded)
        guard try currentOwnerSynchronously() == expectedOwner else { return false }
        _ = try replace(prepared, expected: bounded)
        return true
    }

    private func captureSynchronously() throws -> ClipboardCapturedState {
        let before = pasteboard.changeCount
        let nativeItems = try readableItems()
        var items: [[String: Data]] = []
        var total = 0
        for nativeItem in nativeItems {
            let types = try checkedTypes(nativeItem)
            // Reject file promises before asking their providers for data. A
            // promise is not a materialized file/representation we can restore.
            guard !types.contains(where: isFilePromise) else { throw NativePasteboardError.promisedRepresentation }
            var item: [String: Data] = [:]
            for type in types {
                guard let data = nativeItem.data(forType: type) else {
                    throw NativePasteboardError.unreadableRepresentation
                }
                guard data.count <= maximumSnapshotBytes - total else {
                    throw ClipboardOwnershipError.snapshotTooLarge
                }
                total += data.count
                item[type.rawValue] = data
                guard pasteboard.changeCount == before else { throw NativePasteboardError.changedDuringRead }
            }
            items.append(item)
        }
        guard before >= 0, pasteboard.changeCount == before else {
            throw NativePasteboardError.changedDuringRead
        }
        return ClipboardCapturedState(changeCount: before,
            snapshot: try ClipboardSnapshot(items: items, maximumBytes: maximumSnapshotBytes))
    }

    private func readableItems() throws -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else {
            // Apple documents nil as a retrieval error. Even nil/empty types
            // cannot prove that unreadable clipboard data was actually empty.
            throw NativePasteboardError.unreadableRepresentation
        }
        guard items.count <= 64 else { throw ClipboardOwnershipError.snapshotTooLarge }
        if items.isEmpty, pasteboard.types?.isEmpty == false { throw NativePasteboardError.unreadableRepresentation }
        return items
    }

    private func checkedTypes(_ item: NSPasteboardItem) throws -> [NSPasteboard.PasteboardType] {
        let types = item.types
        guard !types.isEmpty, types.count <= 64, Set(types).count == types.count,
              types.allSatisfy({ !$0.rawValue.isEmpty && $0.rawValue.utf8.count <= 512 }) else {
            throw ClipboardOwnershipError.invalidSnapshot
        }
        return types
    }

    private func prepare(_ snapshot: ClipboardSnapshot) throws -> [NSPasteboardItem] {
        try snapshot.items.map { representations in
            let item = NSPasteboardItem()
            for rawType in representations.keys.sorted() {
                let type = NSPasteboard.PasteboardType(rawType)
                guard !isFilePromise(type) else { throw NativePasteboardError.promisedRepresentation }
                guard let data = representations[rawType], item.setData(data, forType: type) else {
                    throw NativePasteboardError.itemPreparationFailed
                }
            }
            return item
        }
    }

    /// Once clearing begins, errors are uncertain side effects. No catch path
    /// restores old bytes or retries a write over a potentially newer user copy.
    private func replace(_ items: [NSPasteboardItem], expected: ClipboardSnapshot) throws -> Int {
        let clearedCount = pasteboard.clearContents()
        guard clearedCount >= 0, pasteboard.changeCount == clearedCount else {
            throw NativePasteboardError.writeUncertain
        }
        if !items.isEmpty {
            guard pasteboard.writeObjects(items) else { throw NativePasteboardError.writeUncertain }
        }
        do {
            let verified = try captureSynchronously()
            guard verified.changeCount == clearedCount, verified.snapshot == expected else {
                throw NativePasteboardError.writeUncertain
            }
            return verified.changeCount
        } catch {
            throw NativePasteboardError.writeUncertain
        }
    }

    private func validMarker(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { UUID(uuidString: String($0)) != nil }
    }

    private func isFilePromise(_ type: NSPasteboard.PasteboardType) -> Bool {
        type == .filePromise || NSFilePromiseReceiver.readableDraggedTypes.contains(type.rawValue)
    }
}
