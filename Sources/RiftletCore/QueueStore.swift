import Foundation

/// The only writer of durable queue and operation state.
public actor QueueStore {
    public let mode: StoreMode
    private let database: SQLiteDatabase
    private var selectionReservations = Set<UUID>()
    private let assetColumns = "sequence,image_json,status,active_operation_id,visibility,visibility_revision,visibility_reason,last_interaction_at"

    public init(databaseURL: URL, mode: StoreMode = .production) throws {
        self.mode = mode
        let db = try SQLiteDatabase(url: databaseURL)
        try db.transaction {
            let storedMode = try db.rows("SELECT value FROM metadata WHERE key='mode'").first?.first ?? nil
            if let storedMode, storedMode != mode.rawValue { throw RiftletError.modeMismatch }
            try db.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('mode',?)", [mode.rawValue])
        }
        self.database = db
    }

    @discardableResult
    public func importAsset(_ image: ImportedAsset) throws -> AssetRecord {
        guard !image.sourceKey.isEmpty, !image.fileName.isEmpty,
              image.fileName == URL(fileURLWithPath: image.fileName).lastPathComponent,
              !image.fileName.contains("/"), !image.fileName.contains("\\"),
              image.fileName != ".", image.fileName != "..",
              image.sha256.count == 64, image.sha256.allSatisfy({ $0.isHexDigit }),
              image.byteCount > 0, image.pixelWidth > 0, image.pixelHeight > 0 else {
            throw RiftletError.invalidAsset("Invalid immutable asset metadata")
        }
        guard mode != .simulation || image.origin == .synthetic else { throw RiftletError.modeMismatch }
        return try database.transaction {
            if let row = try database.rows("SELECT \(assetColumns) FROM assets WHERE source_key=?", [image.sourceKey]).first {
                return try decodeAsset(row)
            }
            try database.execute("INSERT INTO assets(id,source_key,file_name,sort_at,image_json,status,last_interaction_at) VALUES(?,?,?,?,?,'pending',?)", [
                image.id.uuidString, image.sourceKey, image.fileName,
                String((image.capturedAt ?? image.firstSeenAt).timeIntervalSince1970), try json(image),
                String(image.importedAt.timeIntervalSince1970)
            ])
            guard let inserted = try asset(id: image.id) else { throw RiftletError.assetNotFound }
            return inserted
        }
    }

    public func containsSource(key: String) throws -> Bool {
        try !database.rows("SELECT id FROM assets WHERE source_key=? LIMIT 1", [key]).isEmpty
    }

    public func assets(includeUsed: Bool = false) throws -> [AssetRecord] {
        // Retain the old all-history option for capture recovery; the normal
        // queue is now selected exclusively by durable visibility.
        let filter = includeUsed ? "" : "WHERE visibility='visible'"
        return try database.rows("SELECT \(assetColumns) FROM assets \(filter) ORDER BY sort_at,sequence").map(decodeAsset)
    }

    public func asset(id: UUID) throws -> AssetRecord? {
        try database.rows("SELECT \(assetColumns) FROM assets WHERE id=?", [id.uuidString]).first.map(decodeAsset)
    }

    public func asset(sourceKey: String) throws -> AssetRecord? {
        try database.rows("SELECT \(assetColumns) FROM assets WHERE source_key=?", [sourceKey]).first.map(decodeAsset)
    }

    public func history(limit: Int = 200, offset: Int = 0) throws -> [AssetRecord] {
        try database.rows("SELECT \(assetColumns) FROM assets ORDER BY sort_at DESC,sequence DESC LIMIT ? OFFSET ?",
                          [String(max(0, min(limit, 201))), String(max(0, offset))]).map(decodeAsset)
    }

    public func historySnapshot(limit: Int = 200, offset: Int = 0) throws -> [QueueHistoryRecord] {
        try database.transaction {
            try history(limit: limit, offset: offset).map { record in
                let op = try record.activeOperationID.flatMap { try operation(id: $0) }
                return QueueHistoryRecord(record: record, operation: op,
                    receipt: try op.flatMap { try receipt(for: $0.id) }, canRestore: try canRestoreToQueue(record.id),
                    reason: try op.flatMap { try operationReason(for: $0.id) })
            }
        }
    }

    public func userHidden() throws -> Bool { try preference("user_hidden") }
    public func setUserHidden(_ hidden: Bool) throws { try setPreference("user_hidden", value: hidden) }
    public func capturePaused() throws -> Bool { try preference("capture_paused") }
    public func setCapturePaused(_ paused: Bool) throws { try setPreference("capture_paused", value: paused) }

    private func preference(_ name: String) throws -> Bool {
        try database.rows("SELECT value FROM metadata WHERE key=?", [name]).first?.first == "true"
    }
    private func setPreference(_ name: String, value: Bool) throws {
        try database.execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [name, value ? "true" : "false"])
    }

    /// Reserves an accepted UI selection before target resolution awaits. A
    /// delayed automatic-archive result cannot override that visible click.
    public func reserveSelection(_ id: UUID, visibilityRevision: Int64? = nil, now: Date = Date()) throws {
        guard now.timeIntervalSince1970.isFinite else { throw RiftletError.invalidTransition }
        try database.transaction {
            guard let record = try asset(id: id) else { throw RiftletError.assetNotFound }
            if record.visibility == .archived, record.visibilityReason == .automaticArchive,
               let revision = visibilityRevision, revision == record.visibilityRevision - 1,
               try canRestoreToQueue(id) {
                try setVisibility(record, .visible, reason: .userRestored, now: now)
            } else {
                guard record.visibility == .visible,
                      visibilityRevision == nil || visibilityRevision == record.visibilityRevision else {
                    throw RiftletError.invalidTransition
                }
            }
            try database.execute("UPDATE assets SET last_interaction_at=? WHERE id=?", [String(now.timeIntervalSince1970), id.uuidString])
        }
        selectionReservations.insert(id)
    }

    public func releaseSelection(_ id: UUID) { selectionReservations.remove(id) }

    public func removeFromQueue(_ id: UUID) throws {
        try database.transaction {
            guard let record = try asset(id: id) else { throw RiftletError.assetNotFound }
            try removeVisible(record)
        }
    }

    @discardableResult
    public func clearVisibleQueue() throws -> Int {
        try database.transaction {
            let records = try assets()
            for record in records { try removeVisible(record) }
            return records.count
        }
    }

    private func removeVisible(_ record: AssetRecord) throws {
        guard record.visibility == .visible else { return }
        if let id = record.activeOperationID, let op = try operation(id: id), op.phase == .prepared {
            try update(op, phase: .failed, status: .failed, reason: "Removed before external input intent")
        }
        try setVisibility(record, .removed, reason: .userRemoved)
    }

    public func canRestoreToQueue(_ id: UUID) throws -> Bool {
        guard let record = try asset(id: id), record.visibility == .archived || record.visibility == .removed,
              record.status == .pending || record.status == .failed else { return false }
        if let id = record.activeOperationID {
            guard let op = try operation(id: id), op.phase == .failed else { return false }
        }
        return true
    }

    public func restoreToQueue(_ id: UUID) throws {
        try database.transaction {
            guard try canRestoreToQueue(id), let record = try asset(id: id) else { throw RiftletError.invalidTransition }
            try setVisibility(record, .visible, reason: .userRestored)
        }
    }

    /// No deadline is a product constant: the App supplies its adjustable cutoff.
    /// All candidates are checked again in one transaction, under the UI fence.
    @discardableResult
    public func archiveIdle(before cutoff: Date, fence: QueueInteractionFence,
                            revision: UInt64, limit: Int = 32) throws -> [UUID] {
        guard cutoff.timeIntervalSince1970.isFinite else { throw RiftletError.invalidTransition }
        return try database.transaction {
            try fence.withArchivePermit(expectedRevision: revision) {
                let records = try database.rows("""
                    SELECT \(assetColumns) FROM assets
                    WHERE visibility='visible' AND status IN ('pending','failed') AND last_interaction_at<=?
                    ORDER BY sort_at,sequence LIMIT ?
                    """, [String(cutoff.timeIntervalSince1970), String(max(0, min(limit, 32)))]).map(decodeAsset)
                var archived: [UUID] = []
                for record in records where !selectionReservations.contains(record.id) {
                    if let id = record.activeOperationID, let op = try operation(id: id), op.phase.isUnresolved { continue }
                    try setVisibility(record, .archived, reason: .automaticArchive, touch: false)
                    archived.append(record.id)
                }
                return archived
            } ?? []
        }
    }

    public func checkpoint(for key: String) throws -> Data? {
        guard let value = try database.rows("SELECT value FROM checkpoints WHERE key=?", [key]).first?.first ?? nil else { return nil }
        guard let data = Data(base64Encoded: value) else { throw RiftletError.database("Corrupt checkpoint") }
        return data
    }

    public func saveCheckpoint(_ data: Data, for key: String) throws {
        try database.execute("INSERT INTO checkpoints(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key, data.base64EncodedString()])
    }

    /// Bounded first-observation storage in the existing v3 database. This is an
    /// audit checkpoint, never an admitted receipt or an input authorization.
    /// Returns the first durable value so concurrent/restarted writers can
    /// validate it without overwriting history. No schema or mode conversion.
    public func saveCheckpointIfAbsent(_ data: Data, for key: String) throws -> Data {
        guard !key.isEmpty, key.utf8.count <= 256, data.count <= 64 * 1024 else {
            throw RiftletError.invalidAsset("Checkpoint exceeds its bounded contract")
        }
        return try database.transaction {
            try database.execute("INSERT OR IGNORE INTO checkpoints(key,value) VALUES(?,?)", [key, data.base64EncodedString()])
            guard let saved = try checkpoint(for: key) else { throw RiftletError.database("Missing first checkpoint") }
            return saved
        }
    }

    /// Duplicate clicks return the unresolved operation instead of allocating a new attempt.
    public func prepare(assetID: UUID, target: TargetLease) throws -> TransferOperation {
        try database.transaction {
            guard let record = try asset(id: assetID) else { throw RiftletError.assetNotFound }
            if let activeID = record.activeOperationID, let existing = try operation(id: activeID), existing.phase.isUnresolved {
                return existing
            }
            guard record.visibility == .visible,
                  record.status == .pending || record.status == .failed else { throw RiftletError.invalidTransition }
            guard mode != .simulation || (target.surface == .simulation && target.adapterID == "simulation") else { throw RiftletError.modeMismatch }
            guard mode != .production || target.surface != .simulation else { throw RiftletError.modeMismatch }
            let count = try database.rows("SELECT COALESCE(MAX(attempt),0) FROM operations WHERE asset_id=?", [assetID.uuidString]).first?[0] ?? "0"
            let next = (Int(count) ?? 0) + 1
            let id = UUID(); let now = String(Date().timeIntervalSince1970)
            try database.execute("INSERT INTO operations(id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at) VALUES(?,?,?,?,?,'prepared',?,?)", [
                id.uuidString, assetID.uuidString, String(next), target.stableKey, try json(target), now, now
            ])
            try database.execute("UPDATE assets SET status='transferring',active_operation_id=? WHERE id=?", [id.uuidString, assetID.uuidString])
            return try requiredOperation(id)
        }
    }

    public func operation(id: UUID) throws -> TransferOperation? {
        try database.rows("SELECT id,asset_id,attempt,target_json,phase,created_at,updated_at FROM operations WHERE id=?", [id.uuidString]).first.map(decodeOperation)
    }

    /// The last admitted or nonterminal observation is committed with the queue state.
    /// Adapters may use its attachment identity for observation after restart, never replay input.
    public func receipt(for operationID: UUID) throws -> TransferReceipt? {
        guard let row = try database.rows("SELECT receipt_json FROM operations WHERE id=?", [operationID.uuidString]).first else {
            throw RiftletError.operationNotFound
        }
        guard let raw = row[0] else { return nil }
        return try JSONDecoder().decode(TransferReceipt.self, from: Data(raw.utf8))
    }

    public func uploadStartReceipt(for operationID: UUID) throws -> TransferReceipt? {
        guard let raw = try database.rows("SELECT receipt_json FROM upload_starts WHERE operation_id=?", [operationID.uuidString]).first?.first ?? nil else { return nil }
        return try JSONDecoder().decode(TransferReceipt.self, from: Data(raw.utf8))
    }

    public func operationReason(for operationID: UUID) throws -> String? {
        try database.rows("SELECT reason FROM operations WHERE id=?", [operationID.uuidString]).first?.first ?? nil
    }

    public func compensation(for operationID: UUID) throws -> TransferCompensation? {
        guard let raw = try database.rows("SELECT evidence_json FROM compensations WHERE operation_id=?", [operationID.uuidString]).first?.first ?? nil else { return nil }
        return try JSONDecoder().decode(TransferCompensation.self, from: Data(raw.utf8))
    }

    public func unresolvedOperations() throws -> [TransferOperation] {
        try database.rows("SELECT id,asset_id,attempt,target_json,phase,created_at,updated_at FROM operations WHERE phase NOT IN ('failed','succeeded') ORDER BY sequence").map(decodeOperation)
    }

    /// A bounded restart observation set; old receipt history is never replayed.
    public func successfulOperations(limit: Int = 64) throws -> [TransferOperation] {
        try database.rows("""
            SELECT o.id,o.asset_id,o.attempt,o.target_json,o.phase,o.created_at,o.updated_at
            FROM operations o JOIN assets a ON a.active_operation_id=o.id
            WHERE o.phase='succeeded' ORDER BY o.sequence DESC LIMIT ?
            """, [String(max(0, min(limit, 64)))]).map(decodeOperation)
    }

    /// Commit intent BEFORE the caller performs any external input.
    public func markDispatchIntent(_ id: UUID, selection: AcceptedSelection? = nil) throws {
        // Acquire SQLite's write transaction before taking the cancellation lock:
        // a contended BEGIN must not block synchronous MainActor revocation.
        try database.transaction {
            let op = try validatedDispatchOperation(id, selection: selection)
            if let selection {
                try selection.authorizeDispatch {
                    try update(op, phase: .dispatchIntent, status: .transferring, reason: "dispatch-intent committed")
                }
            } else {
                try update(op, phase: .dispatchIntent, status: .transferring, reason: "dispatch-intent committed")
            }
        }
    }

    private func validatedDispatchOperation(_ id: UUID, selection: AcceptedSelection?) throws -> TransferOperation {
        let op = try requiredOperation(id)
        guard op.phase == .prepared, let record = try asset(id: op.assetID),
              record.visibility == .visible else { throw RiftletError.invalidTransition }
        if let selection {
            guard selection.assetID == op.assetID, selection.target == op.target,
                  selection.visibilityRevision == record.visibilityRevision,
                  record.activeOperationID == op.id, try !userHidden() else { throw RiftletError.invalidTransition }
        }
        let active = try unresolvedOperations().filter { $0.phase != .prepared }
        guard !active.contains(where: { $0.target.conflictsForDispatch(with: op.target) }) else {
            throw RiftletError.targetBusy
        }
        return op
    }

    public func cancelPrepared(_ id: UUID, reason: String) throws {
        try database.transaction {
            let op = try requiredOperation(id)
            guard op.phase == .prepared else { throw RiftletError.invalidTransition }
            try update(op, phase: .failed, status: .failed, reason: reason)
        }
    }

    public func markUnknown(_ id: UUID, reason: String) throws {
        try database.transaction {
            let op = try requiredOperation(id)
            guard op.phase.isUnresolved, op.phase != .prepared else { throw RiftletError.invalidTransition }
            try update(op, phase: op.phase == .compensated ? .compensated : .unknown, status: .unknown, reason: reason)
        }
    }

    @discardableResult
    public func apply(_ receipt: TransferReceipt, policy: ReceiptPolicy = .init()) throws -> AssetRecord {
        try database.transaction {
            let op = try requiredOperation(receipt.operationID)
            guard let record = try asset(id: op.assetID) else { throw RiftletError.assetNotFound }
            guard op.assetID == receipt.assetID, op.attempt == receipt.attempt,
                  record.image.sha256 == receipt.assetSHA256, op.target == receipt.target,
                  record.activeOperationID == op.id else { throw RiftletError.mismatchedReceipt }
            if let started = try uploadStartReceipt(for: op.id), let attachmentID = receipt.attachmentID,
               attachmentID != started.attachmentID { throw RiftletError.mismatchedReceipt }
            // A positive terminal receipt is not immune to a later, independently
            // identified error. Preserve both facts atomically; never re-upload.
            if op.phase == .succeeded {
                guard let success = try self.receipt(for: op.id),
                      correlatedFailure(receipt, success: success) else { return record }
                let evidence = TransferCompensation(originalSuccess: success, failure: receipt, createdAt: Date())
                try database.execute("INSERT INTO compensations(operation_id,evidence_json) VALUES(?,?)", [op.id.uuidString, try json(evidence)])
                if policy.allowsRetry(receipt: receipt, asset: record.image, mode: mode) {
                    try update(op, phase: .failed, status: .failed, reason: receipt.reason)
                    try reviveSafely(record)
                } else {
                    try update(op, phase: .compensated, status: .unknown, reason: "Identity-correlated late error; termination not proved")
                    if record.visibility == .visible { try setVisibility(record, .swallowed, reason: .legacyCompletion) }
                }
                try database.execute("UPDATE operations SET receipt_json=? WHERE id=?", [try json(receipt), op.id.uuidString])
                guard let restored = try asset(id: op.assetID) else { throw RiftletError.assetNotFound }
                return restored
            }
            if op.phase == .compensated {
                // Preserve the internal audit and keep observing. Only a separately
                // admitted safe failure may revive a normal clickable screenshot.
                guard let evidence = try compensation(for: op.id),
                      correlatedFailure(receipt, success: evidence.originalSuccess),
                      policy.allowsRetry(receipt: receipt, asset: record.image, mode: mode) else { return record }
                try update(op, phase: .failed, status: .failed, reason: receipt.reason)
                try reviveSafely(record)
                try database.execute("UPDATE operations SET receipt_json=? WHERE id=?", [try json(receipt), op.id.uuidString])
                guard let restored = try asset(id: op.assetID) else { throw RiftletError.assetNotFound }
                return restored
            }
            guard op.phase.isUnresolved else { return record }
            guard op.phase != .prepared else { throw RiftletError.invalidTransition }
            var phase = op.phase; var status = record.status
            switch receipt.outcome {
            case .inputTriggered:
                if op.phase == .dispatchIntent { phase = .inputTriggered }
            case .attachedCandidate:
                if op.phase == .dispatchIntent || op.phase == .inputTriggered { phase = .attachmentPresent }
            case .uploadStarted:
                if policy.allowsUploadStart(receipt: receipt, asset: record.image, mode: mode) {
                    // Immutable first-start audit is independent of the latest
                    // observation, which UNKNOWN/READY may subsequently replace.
                    try database.execute("INSERT OR IGNORE INTO upload_starts(operation_id,receipt_json,started_at) VALUES(?,?,?)",
                                         [op.id.uuidString, try json(receipt), String(Date().timeIntervalSince1970)])
                    if op.phase == .dispatchIntent { phase = .inputTriggered }
                    if record.visibility == .visible { try setVisibility(record, .swallowed, reason: .uploadStarted) }
                } else { phase = .unknown; status = .unknown }
            case .verifiedReady:
                if policy.allowsConsumption(receipt: receipt, asset: record.image, mode: mode) {
                    phase = .succeeded; status = .used
                    // Legacy adapters may only return final proof. Preserve that
                    // fact and exit silently; never invent an earlier start event.
                    if record.visibility == .visible { try setVisibility(record, .swallowed, reason: .legacyCompletion) }
                } else { phase = .unknown; status = .unknown }
            case .definitiveFailure:
                if policy.allowsRetry(receipt: receipt, asset: record.image, mode: mode) {
                    phase = .failed; status = .failed
                    try reviveSafely(record)
                } else { phase = .unknown; status = .unknown }
            case .unknown:
                phase = .unknown; status = .unknown
            }
            try update(op, phase: phase, status: status, reason: receipt.reason)
            try database.execute("UPDATE operations SET receipt_json=? WHERE id=?", [try json(receipt), op.id.uuidString])
            guard let updated = try asset(id: op.assetID) else { throw RiftletError.assetNotFound }
            return updated
        }
    }

    /// Pending external side effects are queried later, never dispatched a second time.
    public func recoverInterruptedOperations() throws {
        try database.transaction {
            for op in try unresolvedOperations() {
                if op.phase == .compensated { continue }
                if op.phase == .prepared {
                    try update(op, phase: .failed, status: .failed, reason: "Restart before dispatch intent; no input occurred")
                } else {
                    try update(op, phase: .unknown, status: .unknown, reason: "Restart after dispatch intent; reconcile original operation")
                }
            }
        }
    }

    public func markMissingAsset(_ id: UUID) throws {
        guard let record = try asset(id: id) else { throw RiftletError.assetNotFound }
        // Used history must never reappear as a pending/missing screenshot.
        guard record.status != .used else { return }
        try database.execute("UPDATE assets SET status='missing' WHERE id=?", [id.uuidString])
    }

    /// Caller has verified the restored private file against its durable manifest.
    public func restoreMissingAsset(_ id: UUID) throws {
        try database.transaction {
            guard let record = try asset(id: id) else { throw RiftletError.assetNotFound }
            guard record.status == .missing else { return }
            let status: QueueStatus
            if let opID = record.activeOperationID, let op = try operation(id: opID) {
                switch op.phase {
                case .succeeded: status = .used
                case .failed: status = .failed
                case .prepared: status = .transferring
                default: status = .unknown
                }
            } else { status = .pending }
            try database.execute("UPDATE assets SET status=? WHERE id=?", [status.rawValue, id.uuidString])
        }
    }

    private func correlatedFailure(_ failure: TransferReceipt, success: TransferReceipt) -> Bool {
        success.outcome == .verifiedReady && success.positiveReady && success.belongsToOriginalDraft
            && !success.hasError && !success.isUploading
            && failure.hasError && !failure.positiveReady && failure.belongsToOriginalDraft
            && (failure.outcome == .unknown || failure.outcome == .definitiveFailure)
            && failure.profileID == success.profileID
            && failure.attachmentID == success.attachmentID
            && !(success.attachmentID?.isEmpty ?? true)
    }

    private func reviveSafely(_ record: AssetRecord) throws {
        // A user removal/archive overrides automatic visibility changes even
        // though the true failure fact is still recorded in operation history.
        if record.visibility == .visible || record.visibility == .swallowed {
            try setVisibility(record, .visible, reason: .safeFailure)
        }
    }

    private func setVisibility(_ record: AssetRecord, _ visibility: QueueVisibility,
                               reason: QueueVisibilityReason, now: Date = Date(), touch: Bool = true) throws {
        guard now.timeIntervalSince1970.isFinite else { throw RiftletError.invalidTransition }
        try database.execute("""
            UPDATE assets SET visibility=?,visibility_reason=?,visibility_revision=visibility_revision+1,
            last_interaction_at=CASE WHEN ?='true' THEN ? ELSE last_interaction_at END WHERE id=?
            """, [visibility.rawValue, reason.rawValue, touch ? "true" : "false", String(now.timeIntervalSince1970), record.id.uuidString])
    }

    private func update(_ op: TransferOperation, phase: OperationPhase, status: QueueStatus, reason: String) throws {
        try database.execute("UPDATE operations SET phase=?,updated_at=?,reason=? WHERE id=?", [phase.rawValue, String(Date().timeIntervalSince1970), String(reason.prefix(512)), op.id.uuidString])
        // Missing bytes are independent of an operation's progress. Recovery or a failed
        // observation must not make an unavailable file clickable. A verified remote
        // success may still commit used; only verified file recovery clears other cases.
        try database.execute("UPDATE assets SET status=CASE WHEN status='missing' AND ? != 'used' THEN 'missing' ELSE ? END WHERE id=?",
                             [status.rawValue, status.rawValue, op.assetID.uuidString])
    }

    private func requiredOperation(_ id: UUID) throws -> TransferOperation {
        guard let op = try operation(id: id) else { throw RiftletError.operationNotFound }; return op
    }

    private func decodeAsset(_ row: [String?]) throws -> AssetRecord {
        guard row.count == 8, let sequence = row[0].flatMap(Int64.init), let raw = row[1],
              let status = row[2].flatMap(QueueStatus.init(rawValue:)),
              let visibility = row[4].flatMap(QueueVisibility.init(rawValue:)),
              let revision = row[5].flatMap(Int64.init),
              let reason = row[6].flatMap(QueueVisibilityReason.init(rawValue:)),
              let interacted = row[7].flatMap(Double.init) else { throw RiftletError.database("Invalid asset row") }
        let image = try JSONDecoder().decode(ImportedAsset.self, from: Data(raw.utf8))
        return AssetRecord(image: image, sequence: sequence, status: status, activeOperationID: row[3].flatMap(UUID.init(uuidString:)),
                           visibility: visibility, visibilityRevision: revision, visibilityReason: reason,
                           lastInteractionAt: Date(timeIntervalSince1970: interacted))
    }

    private func decodeOperation(_ row: [String?]) throws -> TransferOperation {
        guard row.count == 7, let id = row[0].flatMap(UUID.init(uuidString:)), let assetID = row[1].flatMap(UUID.init(uuidString:)),
              let attempt = row[2].flatMap(Int.init), let target = row[3], let phase = row[4].flatMap(OperationPhase.init(rawValue:)),
              let created = row[5].flatMap(Double.init), let updated = row[6].flatMap(Double.init) else { throw RiftletError.database("Invalid operation row") }
        return TransferOperation(id: id, assetID: assetID, attempt: attempt,
                                 target: try JSONDecoder().decode(TargetLease.self, from: Data(target.utf8)),
                                 phase: phase, createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: updated))
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
