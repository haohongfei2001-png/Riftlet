import Foundation
import RiftletCore

/// A read-only page of local history. Eligibility is supplied by Core and is
/// checked again by Core when an action runs; this value never grants input.
public struct RiftHistoryEntry: Identifiable, Equatable, Sendable {
    public var id: UUID { record.id }
    public let record: AssetRecord
    public let operation: TransferOperation?
    public let lastReceipt: TransferReceipt?
    public let attachmentState: HistoryAttachmentState
    public let canRestore: Bool
    public let detail: String?

    public init(record: AssetRecord, operation: TransferOperation? = nil,
                lastReceipt: TransferReceipt? = nil, startReceipt: TransferReceipt? = nil, canRestore: Bool = false,
                detail: String? = nil) {
        self.record = record; self.operation = operation; self.lastReceipt = lastReceipt
        attachmentState = HistoryAttachmentState(record: record, operation: operation, receipt: lastReceipt, startReceipt: startReceipt)
        self.canRestore = canRestore; self.detail = detail.map { String($0.prefix(512)) }
    }

    public init(snapshot: QueueHistoryRecord) {
        self.init(record: snapshot.record, operation: snapshot.operation, lastReceipt: snapshot.receipt,
                  startReceipt: snapshot.startReceipt, canRestore: snapshot.canRestore, detail: snapshot.reason)
    }

    private var currentOperation: TransferOperation? {
        guard let operation, record.activeOperationID == operation.id,
              operation.assetID == record.id else { return nil }
        return operation
    }

    public var isConfirmedFailure: Bool { attachmentState == .confirmedFailure }
    public var needsVerification: Bool { attachmentState.needsVerification }

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
    case all, needsVerification, swallowed, archived, failed, removed, handedOff, attached

    static let menuFilters: [Self] = [.all, .needsVerification, .attached, .archived, .failed, .removed, .handedOff]

    public var title: String {
        switch self {
        case .all: return "全部截图"
        case .needsVerification: return "待核实"
        case .swallowed: return "已收起"
        case .attached: return "已附加"
        case .handedOff: return "已交给 ChatGPT"
        case .archived: return "已归档"
        case .failed: return "明确失败"
        case .removed: return "已移除"
        }
    }

    public func includes(_ entry: RiftHistoryEntry) -> Bool {
        switch self {
        case .all: return true
        case .needsVerification: return entry.needsVerification
        case .swallowed: return entry.record.visibility == .swallowed
        case .attached: return entry.record.status != .missing && entry.attachmentState == .attached
        case .handedOff: return entry.record.status != .missing && entry.attachmentState == .handedOff
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
        else {
            switch entry.attachmentState {
            case .handedOff: state = "Handed to ChatGPT"
            case .attached: state = "Attached"
            case .confirmedFailure: state = "Upload failed · ready to try again"
            case .notAttached: state = "Not attached · ready to try again"
            case .needsReview: state = "Needs review · kept locally"
            case .checkDraft: state = "Needs review · check original draft"
            case .preparing: state = "Preparing"
            case .available: state = "Ready"
            }
        }

        switch entry.record.visibility {
        case .visible: return state
        case .swallowed: return "Swallowed · \(state)"
        case .archived: return "Archived · \(state)"
        case .removed: return "Removed from rift · \(state)"
        }
    }

    public static func localizedState(for entry: RiftHistoryEntry) -> String {
        if entry.record.status == .missing { return "本地副本不可用" }
        switch entry.attachmentState {
        case .handedOff: return "已交给 ChatGPT"
        case .attached: return "已附加"
        case .needsReview: return "结果待核实"
        case .checkDraft: return "需要检查原对话"
        case .confirmedFailure: return "已确认失败 · 图片保留"
        case .preparing: return "准备附加"
        case .notAttached: return "未附加 · 图片保留"
        case .available:
            switch entry.record.visibility {
            case .archived: return "已归档"
            case .removed: return "已移出裂缝"
            default: return "待附加"
            }
        }
    }

    public static func detailText(for entry: RiftHistoryEntry) -> String {
        if entry.record.status == .missing {
            switch entry.attachmentState {
            case .handedOff: return "这张截图已交给 ChatGPT。上传结果见原对话。"
            case .attached: return "这张截图已附加。"
            case .checkDraft, .needsReview: return "请到原对话核对附件。"
            default: return "请检查本地截图文件。"
            }
        }
        switch entry.attachmentState {
        case .handedOff: return "上传结果见原对话。"
        case .checkDraft: return "原附件报告异常，请到原对话核对。"
        case .needsReview: return "请到原对话核对附件。Riftlet 不会自动重传。"
        case .attached: return "原始系统截图仍然保留。"
        case .confirmedFailure, .notAttached: return "图片仍保存在本机。"
        case .preparing, .available: return ""
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
                        formatter.string(from: captureDate(for: entry)), stateText(for: entry), localizedState(for: entry),
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
