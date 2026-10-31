import AppKit
import CryptoKit
import Foundation
import RiftletCore

public enum ClipboardOwnershipError: Error, Equatable {
    case snapshotTooLarge, invalidSnapshot, invalidImageRepresentation, invalidOperation
}

/// Preserve each item's complete set of materialized representations. Unsupported
/// or promised data must cause the future native reader to decline before writing,
/// rather than silently snapshotting only a text subset of the user's clipboard.
public struct ClipboardSnapshot: Equatable, Sendable {
    public let items: [[String: Data]]
    public let byteCount: Int

    public init(items: [[String: Data]], maximumBytes: Int = 8 * 1024 * 1024) throws {
        guard maximumBytes >= 0, items.count <= 64 else { throw ClipboardOwnershipError.snapshotTooLarge }
        var count = 0
        for item in items {
            guard !item.isEmpty, item.count <= 64,
                  item.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }) else {
                throw ClipboardOwnershipError.invalidSnapshot
            }
            for value in item.values {
                guard value.count <= maximumBytes - count else { throw ClipboardOwnershipError.snapshotTooLarge }
                count += value.count
            }
        }
        self.items = items; byteCount = count
    }
}

/// Pure payload construction. Merely constructing this value never touches the
/// general pasteboard, requests Accessibility, selects a window or pastes.
public struct ClipboardAttachmentPayload: Equatable, Sendable {
    public static let markerType = "com.riftlet.attachment-operation"
    public let marker: String
    public let item: [String: Data]

    public init(request: TransferRequest, pngRepresentation: Data? = nil) throws {
        guard request.operation.phase == .dispatchIntent,
              request.operation.assetID == request.asset.id else { throw ClipboardOwnershipError.invalidOperation }
        let file = request.fileURL.standardizedFileURL
        guard file.isFileURL, file.lastPathComponent == request.asset.fileName,
              file.host == nil || file.host == "" || file.host == "localhost" else {
            throw ClipboardOwnershipError.invalidImageRepresentation
        }
        let marker = "\(request.operation.id.uuidString):\(UUID().uuidString)"
        var item: [String: Data] = [
            NSPasteboard.PasteboardType.fileURL.rawValue: Data(file.absoluteString.utf8),
            Self.markerType: Data(marker.utf8)
        ]
        if let pngRepresentation {
            guard request.asset.mediaType == "image/png",
                  pngRepresentation.count <= 16 * 1024 * 1024,
                  Int64(pngRepresentation.count) == request.asset.byteCount,
                  SHA256.hash(data: pngRepresentation).map({ String(format: "%02x", $0) }).joined() == request.asset.sha256 else {
                throw ClipboardOwnershipError.invalidImageRepresentation
            }
            // The private importer has already validated the real codec. Do not
            // relabel JPEG bytes as PNG, re-encode silently or alter the image hash.
            item[NSPasteboard.PasteboardType.png.rawValue] = pngRepresentation
        }
        self.marker = marker; self.item = item
    }
}

/// Initial conservative Mac restore boundary: wait for already-admitted completion.
/// This reuses Core's receipt admission rather than trusting a timer or a bare
/// "consumed" boolean. Earlier restoration requires a separately proven native
/// consumption observer; no such observer is claimed by this foundation.
public struct ClipboardOwnershipLease: Sendable {
    public let writtenChangeCount: Int
    public let marker: String
    private let operation: TransferOperation
    private let asset: ImportedAsset
    private let previous: ClipboardSnapshot

    public init(request: TransferRequest, previous: ClipboardSnapshot,
                payload: ClipboardAttachmentPayload, writtenChangeCount: Int) throws {
        guard request.operation.phase == .dispatchIntent,
              request.operation.assetID == request.asset.id, writtenChangeCount >= 0,
              payload.marker.hasPrefix(request.operation.id.uuidString + ":"),
              payload.item[ClipboardAttachmentPayload.markerType] == Data(payload.marker.utf8) else {
            throw ClipboardOwnershipError.invalidOperation
        }
        operation = request.operation; asset = request.asset; self.previous = previous
        marker = payload.marker; self.writtenChangeCount = writtenChangeCount
    }

    /// Call inside the native writer's final ownership check immediately before
    /// restoration. This is a decision, not an atomic OS pasteboard compare-and-swap.
    /// A later copy or missing marker always leaves current contents alone.
    public func restoration(currentChangeCount: Int, currentMarker: String?,
                            receipt: TransferReceipt, policy: ReceiptPolicy,
                            mode: StoreMode = .production) -> ClipboardSnapshot? {
        guard currentChangeCount == writtenChangeCount, currentMarker == marker,
              matches(receipt),
              policy.allowsConsumption(receipt: receipt, asset: asset, mode: mode) else { return nil }
        return previous
    }

    /// Shared identity check for restoration and releasing a proved failed input.
    /// Identity alone does not admit either action.
    func matches(_ receipt: TransferReceipt) -> Bool {
        receipt.operationID == operation.id && receipt.assetID == asset.id
            && receipt.attempt == operation.attempt && receipt.assetSHA256 == asset.sha256
            && receipt.target == operation.target
    }
}
