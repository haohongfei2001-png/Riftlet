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

    public var title: String { title(copy: .current) }

    public func title(copy: ProductCopy) -> String {
        switch self {
        case .all: return copy.text("全部截图", "All Screenshots")
        case .needsVerification: return copy.text("待核实", "Needs Review")
        case .swallowed: return copy.text("已收起", "Hidden")
        case .attached: return copy.text("已附加", "Attached")
        case .handedOff: return copy.text("已交给 ChatGPT", "Handed to ChatGPT")
        case .archived: return copy.text("已归档", "Archived")
        case .failed: return copy.text("明确失败", "Confirmed Failure")
        case .removed: return copy.text("已移除", "Removed")
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

    public static func localizedState(for entry: RiftHistoryEntry, copy: ProductCopy = .current) -> String {
        if entry.record.status == .missing { return copy.text("本地副本不可用", "Local copy unavailable") }
        switch entry.attachmentState {
        case .handedOff: return copy.text("已交给 ChatGPT", "Handed to ChatGPT")
        case .attached: return copy.text("已附加", "Attached")
        case .needsReview: return copy.text("结果待核实", "Needs review")
        case .checkDraft: return copy.text("需要检查原对话", "Check the original conversation")
        case .confirmedFailure: return copy.text("已确认失败 · 图片保留", "Failed · image kept")
        case .preparing: return copy.text("准备附加", "Preparing attachment")
        case .notAttached: return copy.text("未附加 · 图片保留", "Not attached · image kept")
        case .available:
            switch entry.record.visibility {
            case .archived: return copy.text("已归档", "Archived")
            case .removed: return copy.text("已移出裂缝", "Removed from desktop")
            default: return copy.text("待附加", "Ready to attach")
            }
        }
    }

    public static func detailText(for entry: RiftHistoryEntry, copy: ProductCopy = .current) -> String {
        if entry.record.status == .missing {
            switch entry.attachmentState {
            case .handedOff: return copy.text("这张截图已交给 ChatGPT。上传结果见原对话。", "This screenshot was handed to ChatGPT. Check the original conversation for the upload result.")
            case .attached: return copy.text("这张截图已附加。", "This screenshot was attached.")
            case .checkDraft, .needsReview: return copy.text("请到原对话核对附件。", "Check the attachment in the original conversation.")
            default: return copy.text("请检查本地截图文件。", "Check the local screenshot file.")
            }
        }
        switch entry.attachmentState {
        case .handedOff: return copy.text("上传结果见原对话。", "Check the original conversation for the upload result.")
        case .checkDraft: return copy.text("原附件报告异常，请到原对话核对。", "The attachment reported a problem. Check the original conversation.")
        case .needsReview: return copy.text("请到原对话核对附件。Riftlet 不会自动重传。", "Check the attachment in the original conversation. Riftlet will not upload it again automatically.")
        case .attached: return copy.text("原始系统截图仍然保留。", "The original system screenshot is still saved.")
        case .confirmedFailure, .notAttached: return copy.text("图片仍保存在本机。", "The image is still saved on this Mac.")
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
                        formatter.string(from: captureDate(for: entry)), stateText(for: entry), localizedState(for: entry, copy: .simplifiedChinese),
                        localizedState(for: entry, copy: .english),
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
