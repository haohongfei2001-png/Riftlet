import CSQLite
import Foundation

public struct LibraryHistoryPage: Sendable {
    public let records: [QueueHistoryRecord]
    public let hasNext: Bool
    public let throughSequence: Int64
    public let hasNewCaptures: Bool
}

/// Text, status and half-open date range are all applied before returning a bounded page.
public struct HistoryQuery: Equatable, Sendable {
    public enum Filter: String, CaseIterable, Sendable {
        case all, desktop, needsAttention, needsVerification, swallowed, archived, failed, removed, handedOff, attached, missing, available, preparing, notAttached

        fileprivate var predicate: String {
            switch self {
            case .all: return "1"
            case .desktop: return "a.visibility='visible'"
            case .needsAttention: return "(a.status='missing' OR \(state) IN ('needsReview','checkDraft','confirmedFailure','notAttached'))"
            case .swallowed, .archived, .removed: return "a.visibility='\(rawValue)'"
            case .missing: return "a.status='missing'"
            case .needsVerification: return "\(state) IN ('needsReview','checkDraft')"
            case .failed: return "\(state)='confirmedFailure'"
            case .attached, .handedOff, .preparing, .notAttached, .available:
                return "(a.status!='missing' AND \(state)='\(rawValue)')"
            }
        }
        private var state: String { HistoryQuery.stateSQL }

        fileprivate var terms: String {
            switch self {
            case .all: return ""
            case .desktop: return "桌面中 on desktop"
            case .needsAttention: return "需要处理 needs attention"
            case .available: return "待附加 ready to attach"
            case .preparing: return "准备附加 preparing attachment"
            case .notAttached: return "未附加 not attached"
            case .missing: return "本地副本不可用 local copy unavailable missing"
            case .needsVerification: return "待核实 结果待核实 需要检查原对话 needs review check original conversation"
            case .failed: return "明确失败 已确认失败 confirmed failure failed"
            case .archived: return "已归档 archived"
            case .removed: return "已移出 从桌面收起 removed from desktop"
            case .swallowed: return "已收起 hidden swallowed"
            case .attached: return "已附加 attached"
            case .handedOff: return "已交给 ChatGPT handed to ChatGPT"
            }
        }
    }

    public var text: String
    public var filter: Filter
    public var dateRange: DateInterval?
    public init(text: String = "", filter: Filter = .all, dateRange: DateInterval? = nil) {
        self.text = text; self.filter = filter; self.dateRange = dateRange
    }

    func predicate(through ceiling: Int64) -> (sql: String, values: [String?]) {
        var conditions = ["a.sequence<=?"]
        var values: [String?] = [String(ceiling)]
        if let dateRange {
            conditions.append("a.sort_at>=? AND a.sort_at<?")
            values += [String(dateRange.start.timeIntervalSince1970), String(dateRange.end.timeIntervalSince1970)]
        }
        if filter != .all { conditions.append(filter.predicate) }
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            // Bind literal substrings (including % and _) instead of SQL wildcard patterns.
            let folded = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            // Native SQLite lower() handles ASCII. Use Foundation folding only for
            // non-ASCII filenames and for the bounded, occasionally present reason.
            var matches = [
                "instr(lower(a.file_name),?)>0",
                "(length(CAST(a.file_name AS BLOB))!=length(a.file_name) AND riftlet_history_contains(a.file_name,?))",
                "instr(lower(a.id),?)>0", "instr(CAST(a.sequence AS TEXT),?)>0",
                "(o.reason IS NOT NULL AND riftlet_history_contains(substr(o.reason,1,512),?))"
            ]
            values += [folded, term, folded, term, term]
            if term.allSatisfy({ $0.isASCII && $0.isNumber || $0 == "×" }) {
                matches.append("instr(json_extract(a.image_json,'$.pixelWidth')||'×'||json_extract(a.image_json,'$.pixelHeight'),?)>0")
                values.append(term)
            }
            // Formatting a local date for every row is expensive; other characters
            // cannot occur in this numeric date/time representation.
            if term.utf8.count <= 16 && term.utf8.allSatisfy({ (48...57).contains($0) || [32, 45, 58].contains($0) }) {
                matches.append("instr(strftime('%Y-%m-%d %H:%M',a.sort_at,'unixepoch','localtime'),?)>0")
                values.append(term)
            }
            for prefix in ["#", "＃", "编号", "No.", "Screenshot #"] where term.lowercased().hasPrefix(prefix.lowercased()) {
                if let sequence = Int64(term.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)) {
                    matches.append("a.sequence=?"); values.append(String(sequence))
                }
                break
            }
            for candidate in Filter.allCases where candidate != .all && candidate.terms.localizedCaseInsensitiveContains(term) {
                matches.append(candidate.predicate)
            }
            conditions.append("(" + matches.joined(separator: " OR ") + ")")
        }
        return (conditions.joined(separator: " AND "), values)
    }

    private static let stateSQL = """
        riftlet_history_state(a.status,a.id,o.id,o.phase,o.attempt,
        CASE WHEN o.receipt_json IS NOT NULL OR s.receipt_json IS NOT NULL THEN json_extract(a.image_json,'$.sha256') END,
        o.target_json,o.receipt_json,s.receipt_json)
        """

    /// Run the same receipt checks as the detail pane for a status predicate. The
    /// ordinary listing and filename/date lookups do not decode historical operations.
    /// No media bytes or target data leave SQLite's read-only call.
    static func registerStateFunction(on handle: OpaquePointer?) throws {
        let result = sqlite3_create_function_v2(handle, "riftlet_history_state", 9, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            nil, historyStateSQLValue, nil, nil, nil)
        guard result == SQLITE_OK else { throw RiftletError.database("Cannot register library query") }
        let contains = sqlite3_create_function_v2(handle, "riftlet_history_contains", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            nil, { context, _, arguments in
                guard let arguments, let raw = sqlite3_value_text(arguments[0]), let query = sqlite3_value_text(arguments[1]) else {
                    sqlite3_result_int(context, 0)
                    return
                }
                let found = String(cString: raw).range(of: String(cString: query), options: [.caseInsensitive, .diacriticInsensitive]) != nil
                sqlite3_result_int(context, found ? 1 : 0)
            }, nil, nil, nil)
        guard contains == SQLITE_OK else { throw RiftletError.database("Cannot register library text search") }
    }
}

private func historyStateSQLValue(_ context: OpaquePointer?, _ count: Int32,
                                  _ arguments: UnsafeMutablePointer<OpaquePointer?>?) {
    guard let arguments else { return }
    func string(_ index: Int) -> String? {
        sqlite3_value_text(arguments[index]).map { String(cString: $0) }
    }
    func decode<T: Decodable>(_ type: T.Type, _ index: Int) throws -> T? {
        guard let string = string(index) else { return nil }
        return try JSONDecoder().decode(type, from: Data(string.utf8))
    }
    do {
        guard let status = string(0).flatMap(QueueStatus.init(rawValue:)),
              let id = string(1).flatMap(UUID.init(uuidString:)) else {
            throw RiftletError.database("Unreadable history state")
        }
        let receipt = try decode(TransferReceipt.self, 7)
        let start = try decode(TransferReceipt.self, 8)
        let target = receipt == nil && start == nil ? nil : try decode(TargetLease.self, 6)
        let state = HistoryAttachmentState(status: status, assetID: id, sha: string(5),
            operationID: string(2).flatMap(UUID.init(uuidString:)), phase: string(3).flatMap(OperationPhase.init(rawValue:)),
            attempt: Int(sqlite3_value_int64(arguments[4])), target: target, receipt: receipt, startReceipt: start)
        sqlite3_result_text(context, state.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    } catch {
        sqlite3_result_error(context, "Unreadable history state", -1)
    }
}
