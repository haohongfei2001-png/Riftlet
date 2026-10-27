import Foundation
import RiftletCore

/// A read-only page of local history. Eligibility is supplied by Core and is
/// checked again by Core when an action runs; this value never grants input.
public struct RiftHistoryEntry: Identifiable, Equatable, Sendable {
    public var id: UUID { record.id }
    public let record: AssetRecord
    public let operation: TransferOperation?
    public let lastReceipt: TransferReceipt?
    public let canRestore: Bool
    public let detail: String?

    public init(record: AssetRecord, operation: TransferOperation? = nil,
                lastReceipt: TransferReceipt? = nil, canRestore: Bool = false,
                detail: String? = nil) {
        self.record = record; self.operation = operation; self.lastReceipt = lastReceipt
        self.canRestore = canRestore; self.detail = detail.map { String($0.prefix(512)) }
    }

    private var currentOperation: TransferOperation? {
        guard let operation, record.activeOperationID == operation.id,
              operation.assetID == record.id else { return nil }
        return operation
    }

    /// Pre-input cancellations also use QueueStatus.failed. They must not be
    /// described as a proved remote upload failure in the history interface.
    public var isConfirmedFailure: Bool {
        guard record.status == .pending || record.status == .failed || record.status == .missing,
              let operation = currentOperation, operation.phase == .failed,
              let receipt = lastReceipt,
              receipt.operationID == operation.id, receipt.assetID == record.id,
              receipt.attempt == operation.attempt, receipt.target == operation.target,
              receipt.assetSHA256 == record.image.sha256,
              receipt.outcome == .definitiveFailure, receipt.hasError,
              receipt.safeToRetry, receipt.belongsToOriginalDraft,
              !receipt.isUploading, !receipt.positiveReady else { return false }
        return true
    }

    public var needsVerification: Bool {
        record.status == .unknown || record.status == .transferring
            || (currentOperation.map { $0.phase.isUnresolved } ?? false)
    }

    public var canRestoreToRift: Bool {
        guard canRestore,
              record.visibility == .archived || record.visibility == .removed,
              record.status == .pending || record.status == .failed else { return false }
        if record.activeOperationID != nil {
            guard let operation = currentOperation, operation.phase == .failed else { return false }
        } else if operation != nil || record.status != .pending { return false }
        return true
    }

    public var canRemoveFromRift: Bool { record.visibility == .visible }
}

public enum RiftHistoryFilter: String, CaseIterable, Sendable {
    case all, needsVerification, swallowed, archived, failed, removed

    public var title: String {
        switch self {
        case .all: return "All"
        case .needsVerification: return "Needs review"
        case .swallowed: return "Swallowed"
        case .archived: return "Archived"
        case .failed: return "Failed"
        case .removed: return "Removed"
        }
    }

    public func includes(_ entry: RiftHistoryEntry) -> Bool {
        switch self {
        case .all: return true
        case .needsVerification: return entry.needsVerification
        case .swallowed: return entry.record.visibility == .swallowed
        case .archived: return entry.record.visibility == .archived
        case .failed: return entry.isConfirmedFailure
        case .removed: return entry.record.visibility == .removed
        }
    }
}

/// Pure presentation: never mutates the durable queue or an attachment.
public enum HistoryPresentation {
    public static let pageSize = 200

    public static func stateText(for entry: RiftHistoryEntry) -> String {
        let state: String
        if entry.record.status == .missing { state = "Private copy unavailable" }
        else if entry.isConfirmedFailure { state = "Upload failed · ready to try again" }
        else if entry.needsVerification {
            state = entry.record.status == .transferring ? "Checking attachment" : "Needs review · kept locally"
        } else if entry.record.status == .used { state = "Attached" }
        else if entry.record.status == .failed { state = "Not attached · ready to try again" }
        else { state = "Ready" }

        switch entry.record.visibility {
        case .visible: return state
        case .swallowed: return "Swallowed · \(state)"
        case .archived: return "Archived · \(state)"
        case .removed: return "Removed from rift · \(state)"
        }
    }

    public static func captureDate(for entry: RiftHistoryEntry) -> Date {
        entry.record.image.capturedAt ?? entry.record.image.firstSeenAt
    }

    public static func dateText(for entry: RiftHistoryEntry, timeZone: TimeZone = .current) -> String {
        dateFormatter(timeZone: timeZone).string(from: captureDate(for: entry))
    }

    public static func matching(_ entries: [RiftHistoryEntry], filter: RiftHistoryFilter = .all,
                                query: String = "", timeZone: TimeZone = .current) -> [RiftHistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = dateFormatter(timeZone: timeZone)
        return entries.filter { entry in
            guard filter.includes(entry) else { return false }
            guard !query.isEmpty else { return true }
            let asset = entry.record.image
            let text = [entry.id.uuidString, asset.fileName, String(entry.record.sequence),
                        formatter.string(from: captureDate(for: entry)), stateText(for: entry),
                        "\(asset.pixelWidth)×\(asset.pixelHeight)", entry.detail ?? ""].joined(separator: " ")
            return text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.sorted { lhs, rhs in
            let a = captureDate(for: lhs), b = captureDate(for: rhs)
            if a != b { return a > b }
            if lhs.record.sequence != rhs.record.sequence { return lhs.record.sequence > rhs.record.sequence }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}
