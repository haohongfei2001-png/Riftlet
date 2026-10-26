import Foundation

/// The only writer of durable queue and operation state.
public actor QueueStore {
    public let mode: StoreMode
    private let database: SQLiteDatabase

    public init(databaseURL: URL, mode: StoreMode = .production) throws {
        self.mode = mode
        let db = try SQLiteDatabase(url: databaseURL)
        let storedMode = try db.rows("SELECT value FROM metadata WHERE key='mode'").first?.first ?? nil
        if let storedMode, storedMode != mode.rawValue { throw RiftletError.modeMismatch }
        try db.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('mode',?)", [mode.rawValue])
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
            if let row = try database.rows("SELECT sequence,image_json,status,active_operation_id FROM assets WHERE source_key=?", [image.sourceKey]).first {
                return try decodeAsset(row)
            }
            try database.execute("INSERT INTO assets(id,source_key,file_name,sort_at,image_json,status) VALUES(?,?,?,?,?,'pending')", [
                image.id.uuidString, image.sourceKey, image.fileName,
                String((image.capturedAt ?? image.firstSeenAt).timeIntervalSince1970), try json(image)
            ])
            guard let inserted = try asset(id: image.id) else { throw RiftletError.assetNotFound }
            return inserted
        }
    }

    public func containsSource(key: String) throws -> Bool {
        try !database.rows("SELECT id FROM assets WHERE source_key=? LIMIT 1", [key]).isEmpty
    }

    public func assets(includeUsed: Bool = false) throws -> [AssetRecord] {
        let filter = includeUsed ? "" : "WHERE status != 'used'"
        return try database.rows("SELECT sequence,image_json,status,active_operation_id FROM assets \(filter) ORDER BY sort_at,sequence").map(decodeAsset)
    }

    public func asset(id: UUID) throws -> AssetRecord? {
        try database.rows("SELECT sequence,image_json,status,active_operation_id FROM assets WHERE id=?", [id.uuidString]).first.map(decodeAsset)
    }

    public func asset(sourceKey: String) throws -> AssetRecord? {
        try database.rows("SELECT sequence,image_json,status,active_operation_id FROM assets WHERE source_key=?", [sourceKey]).first.map(decodeAsset)
    }

    public func checkpoint(for key: String) throws -> Data? {
        guard let value = try database.rows("SELECT value FROM checkpoints WHERE key=?", [key]).first?.first ?? nil else { return nil }
        guard let data = Data(base64Encoded: value) else { throw RiftletError.database("Corrupt checkpoint") }
        return data
    }

    public func saveCheckpoint(_ data: Data, for key: String) throws {
        try database.execute("INSERT INTO checkpoints(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key, data.base64EncodedString()])
    }

    /// Duplicate clicks return the unresolved operation instead of allocating a new attempt.
    public func prepare(assetID: UUID, target: TargetLease) throws -> TransferOperation {
        try database.transaction {
            guard let record = try asset(id: assetID) else { throw RiftletError.assetNotFound }
            if let activeID = record.activeOperationID, let existing = try operation(id: activeID), existing.phase.isUnresolved {
                return existing
            }
            guard record.status == .pending || record.status == .failed else { throw RiftletError.invalidTransition }
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

    public func unresolvedOperations() throws -> [TransferOperation] {
        try database.rows("SELECT id,asset_id,attempt,target_json,phase,created_at,updated_at FROM operations WHERE phase NOT IN ('failed','succeeded') ORDER BY sequence").map(decodeOperation)
    }

    /// Commit intent BEFORE the caller performs any external input.
    public func markDispatchIntent(_ id: UUID) throws {
        try database.transaction {
            let op = try requiredOperation(id)
            guard op.phase == .prepared else { throw RiftletError.invalidTransition }
            guard try database.rows("SELECT id FROM operations WHERE target_key=? AND phase IN ('dispatchIntent','inputTriggered','attachmentPresent','unknown')", [op.target.stableKey]).isEmpty else { throw RiftletError.targetBusy }
            try update(op, phase: .dispatchIntent, status: .transferring, reason: "dispatch-intent committed")
        }
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
            try update(op, phase: .unknown, status: .unknown, reason: reason)
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
            // A delayed result cannot change an already terminal attempt.
            guard op.phase.isUnresolved else { return record }
            guard op.phase != .prepared else { throw RiftletError.invalidTransition }
            var phase = op.phase; var status = record.status
            switch receipt.outcome {
            case .inputTriggered:
                if op.phase == .dispatchIntent { phase = .inputTriggered }
            case .attachedCandidate:
                if op.phase == .dispatchIntent || op.phase == .inputTriggered { phase = .attachmentPresent }
            case .verifiedReady:
                if policy.allowsConsumption(receipt: receipt, asset: record.image, mode: mode) {
                    phase = .succeeded; status = .used
                } else { phase = .unknown; status = .unknown }
            case .definitiveFailure:
                if policy.allowsRetry(receipt: receipt, asset: record.image, mode: mode) {
                    phase = .failed; status = .failed
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

    private func update(_ op: TransferOperation, phase: OperationPhase, status: QueueStatus, reason: String) throws {
        try database.execute("UPDATE operations SET phase=?,updated_at=?,reason=? WHERE id=?", [phase.rawValue, String(Date().timeIntervalSince1970), String(reason.prefix(512)), op.id.uuidString])
        try database.execute("UPDATE assets SET status=? WHERE id=?", [status.rawValue, op.assetID.uuidString])
    }

    private func requiredOperation(_ id: UUID) throws -> TransferOperation {
        guard let op = try operation(id: id) else { throw RiftletError.operationNotFound }; return op
    }

    private func decodeAsset(_ row: [String?]) throws -> AssetRecord {
        guard row.count == 4, let sequence = row[0].flatMap(Int64.init), let raw = row[1],
              let status = row[2].flatMap(QueueStatus.init(rawValue:)) else { throw RiftletError.database("Invalid asset row") }
        let image = try JSONDecoder().decode(ImportedAsset.self, from: Data(raw.utf8))
        return AssetRecord(image: image, sequence: sequence, status: status, activeOperationID: row[3].flatMap(UUID.init(uuidString:)))
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
