import Foundation
import CryptoKit

// Compile beside the frozen RiftletCore sources; never run against a live profile.
// The site's in-memory Document no longer exists in these historical captures.
// Only the adapter is a fixture. All selections, dispatches and SQLite writes use Core.
private struct AuditError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw AuditError(message) }
}

private let startProfile = "chatgpt-web-product-system-start-20261102-v1"
private let receiptProfile = "chatgpt-web-product-system-attached-20261102-v1"

private actor FixtureAdapter: OriginalAttachmentRecoveryChecking {
    nonisolated let id = "chatgpt-web"
    let source: AttachmentRecoverySource
    let bridge: URL?
    let validatesDestination: Bool
    private(set) var calls = [UUID]()
    init(_ source: AttachmentRecoverySource, allowInput: Bool, bridge: URL?) {
        self.source = source
        self.bridge = bridge
        self.validatesDestination = allowInput
    }
    func captureTarget() throws -> TargetLease { throw AuditError("Unexpected automatic target capture") }
    func validate(_ target: TargetLease) -> Bool { validatesDestination && source.permitsDestination(target) }
    func checkRecovery(_ original: TransferRequest, destination: TargetLease) -> Bool {
        original.requireLiveOriginal && original.operation == source.operation &&
            original.recoverySource == source && original.invocationID == source.invocationID &&
            source.permitsDestination(destination)
    }
    func reconcile(_ request: TransferRequest) throws -> TransferReceipt {
        throw AuditError("Fixture never recreates the archived site's observer")
    }
    func append(_ request: TransferRequest, onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) throws -> TransferReceipt {
        try append(request)
    }
    func append(_ request: TransferRequest) throws -> TransferReceipt {
        let op = request.operation
        try require(source == request.recoverySource && op.assetID == source.operation.assetID &&
                    source.permitsDestination(op.target) && request.invocationID != nil &&
                    request.invocationID != source.invocationID, "Fixture received a foreign source or invocation")
        let bytes = try Data(contentsOf: request.fileURL)
        let digest = SHA256.hash(data: bytes).map { String(format:"%02x", $0) }.joined()
        try require(digest == request.asset.sha256 && bytes.count == request.asset.byteCount, "Input PNG changed")
        calls.append(op.id)
        let member: String, evidence: String
        if let bridge {
            (member, evidence) = try verifyInHeadlessBrowser(request, script: bridge)
        } else {
            member = "controlled-card-" + op.id.uuidString
            evidence = "controlled-evidence-" + op.id.uuidString
        }
        return TransferReceipt(operationID: op.id, assetID: op.assetID, attempt: op.attempt,
            assetSHA256: digest, target: op.target, outcome: .uploadStarted, profileID: receiptProfile,
            attachmentID: member, belongsToOriginalDraft: true,
            uploadStartEvidence: .init(profileID: startProfile, signal: .attachmentAccepted,
                evidenceID: evidence, inputCount: 1))
    }
    // Core and the loopback page identify the same asset/operation/invocation and
    // click IDs. Both original and successor on that page use its fresh real DOM
    // identities. The bridge never passes off the local Document as the historic site.
    private func verifyInHeadlessBrowser(_ request: TransferRequest, script: URL) throws -> (String,String) {
        func identity(_ op: TransferOperation, invocation: UUID) throws -> [String:Any] {
            guard let pin = op.target.clickBindingID else { throw AuditError("Missing click binding") }
            return ["id":op.id.uuidString.lowercased(), "attempt":op.attempt,
                    "invocation":invocation.uuidString.lowercased(), "clickBindingID":pin.uuidString.lowercased()]
        }
        guard let invocation = request.invocationID else { throw AuditError("Missing dispatch") }
        let old = source.operation, new = request.operation, file = request.fileURL
        let root = file.deletingLastPathComponent()
        let config: [String:Any] = ["old":try identity(old, invocation: source.invocationID),
            "next":try identity(new, invocation: invocation), "asset":old.assetID.uuidString.lowercased(),
            "filename":file.lastPathComponent, "sha":request.asset.sha256]
        try JSONSerialization.data(withJSONObject: config).write(to: root.appendingPathComponent("browser-request.json"), options:.withoutOverwriting)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.arguments = ["node",script.path,root.path]
        try child.run()
        child.waitUntilExit()
        try require(child.terminationStatus == 0, "Fresh browser did not prove the controlled input")
        let raw = try Data(contentsOf: root.appendingPathComponent("browser-receipt.json"))
        guard let r = try JSONSerialization.jsonObject(with: raw) as? [String:Any],
              let counts = r["counts"] as? [String:Int], counts == ["setters":2,"inputs":2,"changes":2,"submits":0,"sends":0],
              r["historicalCardLifecycleSimulated"] as? Bool == true, r["sameBytes"] as? Bool == true,
              r["priorMemberPreserved"] as? Bool == true,
              r["originalOperationID"] as? String == old.id.uuidString.lowercased(),
              r["newOperationID"] as? String == new.id.uuidString.lowercased(),
              r["newInvocationID"] as? String == invocation.uuidString.lowercased(),
              let document = r["localOriginalDocument"] as? String, !document.isEmpty, document == r["localNewDocument"] as? String,
              let editor = r["localOriginalComposer"] as? String, !editor.isEmpty, editor == r["localNewComposer"] as? String,
              let member = r["attachmentID"] as? String, !member.isEmpty,
              let evidence = r["evidenceID"] as? String, !evidence.isEmpty else { throw AuditError("Incomplete controlled renderer receipt") }
        return (member, evidence)
    }
}

@main private enum ArchiveRecovery {
    static func main() async throws {
        let argv = Array(CommandLine.arguments.dropFirst())
        guard (2...3).contains(argv.count), ["cancel", "complete"].contains(argv[0]) else { throw AuditError("Expected phase and private case directory") }
        let root = URL(fileURLWithPath: argv[1], isDirectory: true).standardizedFileURL
        let database = root.appendingPathComponent("working.sqlite")
        try require(FileManager.default.fileExists(atPath: root.appendingPathComponent("controlled-copy-only").path),
                    "Cannot open an unmarked directory")
        let store = try QueueStore(databaseURL: database, mode: .production)
        let originals = try await store.unresolvedOperations().filter { $0.phase == .unknown }
        guard originals.count == 1, let old = originals.first else { throw AuditError("Expected one historical UNKNOWN") }
        let source = try await store.attachmentRecoverySource(operationID: old.id)
        guard source.originalStart == nil, source.originalReceipt?.outcome == .inputTriggered,
              let image = try await store.asset(id: old.assetID)?.image else { throw AuditError("Unexpected historical case") }
        let sql = try SQLiteDatabase(url: database)
        func ledger(_ id: UUID) throws -> [[String?]] {
            try sql.rows("SELECT * FROM operations WHERE id=?", [id.uuidString]) +
                sql.rows("SELECT * FROM upload_starts WHERE operation_id=?", [id.uuidString]) +
                sql.rows("SELECT * FROM checkpoints WHERE key=?", ["transfer-dispatch-call-v1:" + id.uuidString])
        }
        let orig = try ledger(old.id)
        let allow = argv[0] == "complete"
        let bridge = argv.count == 3 ? URL(fileURLWithPath: argv[2]) : nil
        let adapter = FixtureAdapter(source, allowInput: allow, bridge: bridge)
        let policy = ReceiptPolicy(uploadStartProfiles: [startProfile: .webChat], profileOrigins: [startProfile: [.systemScreenshot]])
        let core = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root, policy: policy,
                                       validateAcceptedSelection: { $0.isValid() })
        try await core.recover()
        let restartCalls = await adapter.calls
        try require(try ledger(old.id) == orig && restartCalls.isEmpty, "Restart changed old operation or called append")
        let staged = try await store.stageAttachmentForReattach(operationID: old.id)
        let oldTarget = old.target
        func pin(document: String? = nil) -> TargetLease {
            TargetLease(adapterID: oldTarget.adapterID, surface: oldTarget.surface, applicationID: oldTarget.applicationID,
                sessionID: oldTarget.sessionID, windowID: oldTarget.windowID, tabID: oldTarget.tabID,
                documentID: document ?? oldTarget.documentID, composerID: oldTarget.composerID,
                draftGeneration: oldTarget.draftGeneration, logicalDraftIdentity: oldTarget.logicalDraftIdentity,
                clickBindingID: UUID(), historyConversationID: oldTarget.historyConversationID)
        }
        func selection(_ target: TargetLease) -> AcceptedSelection {
            AcceptedSelection(assetID: old.assetID, target: target, visibilityRevision: staged.visibilityRevision)
        }
        do {
            try await core.reattach(selection(pin(document: "other-document")), replacing: old.id)
            throw AuditError("A foreign original document passed")
        } catch RiftletError.invalidTransition {}
        let token = selection(pin())
        try await core.reattach(token, replacing: old.id)
        for _ in 0..<300 where await core.hasInFlightAttachmentWork { try await Task.sleep(nanoseconds: 5_000_000) }
        let calls = await adapter.calls
        let successors = try sql.rows("SELECT id,attempt,phase FROM operations WHERE asset_id=? AND id!=? ORDER BY attempt", [old.assetID.uuidString,old.id.uuidString])
        try require(successors.count == (allow ? 2 : 1), "Unexpected successor count")
        guard let id = successors.last?[0].flatMap(UUID.init(uuidString:)) else { throw AuditError("Missing successor") }
        try require(successors.first?[1] == String(old.attempt+1) && successors.first?[2] == "failed",
                    "Input-free attempt was lost")
        try require(try sql.rows("SELECT active_operation_id FROM assets WHERE id=?", [old.assetID.uuidString]) ==
                    [[allow ? id.uuidString : old.id.uuidString]], "Wrong active head")
        if allow {
            try require(calls == [id] && successors.last?[1] == String(old.attempt+2), "Missing sole fresh append")
            do {
                try await core.reattach(token, replacing: old.id)
                throw AuditError("Spent explicit selection entered twice")
            } catch RiftletError.invalidTransition {}
            try require(try await store.uploadStartReceipt(for: id)?.uploadStartEvidence?.signal == .attachmentAccepted,
                        "Missing controlled accepted START")
        } else {
            let cancelledInvocation = try await store.dispatchInvocationID(for: id)
            try require(calls.isEmpty && cancelledInvocation == nil, "Input during cancelled prepare")
        }
        let successorLedger = try ledger(id)
        let callRows = try sql.rows("SELECT value FROM checkpoints WHERE key=?", ["transfer-dispatch-call-v1:" + old.id.uuidString])
        guard let b64 = callRows.first?.first ?? nil, let data = Data(base64Encoded: b64),
              let call = try JSONSerialization.jsonObject(with: data) as? [String:Any],
              let owner = (call["ownerID"] as? String).flatMap(UUID.init(uuidString:)),
              let latest = source.originalReceipt else { throw AuditError("Missing archived invocation owner") }
        // The old writer has its real historical owner and invocation IDs, not random negatives.
        try await store.markUnknown(old.id, reason: "Controlled late fallback")
        if allow {
            do {
                _ = try await store.apply(latest, policy: policy)
                throw AuditError("Old receipt applied to a different active head")
            } catch RiftletError.mismatchedReceipt {}
        } else {
            _ = try await store.apply(latest, policy: policy)
        }
        do {
            try await store.recordAppendReturned(latest, invocationID: source.invocationID, ownerID: owner)
            throw AuditError("Late append-return mutated original")
        } catch RiftletError.mismatchedReceipt {}
        do {
            try await store.recordInputExecutionReturned(operationID: old.id, invocationID: source.invocationID, ownerID: owner)
            throw AuditError("Late input-return mutated original")
        } catch RiftletError.mismatchedReceipt {}
        let rejection = PreInputRejection(operationID: old.id, assetID: old.assetID, attempt: old.attempt,
            assetSHA256: image.sha256, target: old.target, invocationID: source.invocationID, stage: .pageRetiredBeforeCommit)
        do {
            try await store.recordPreInputRejection(rejection)
            throw AuditError("Late pre-input rejection revised old input")
        } catch RiftletError.mismatchedReceipt {}
        try require(try ledger(old.id) == orig && ledger(id) == successorLedger, "Late callbacks changed a ledger")
        try require(try sql.rows("SELECT count(*) FROM attachment_reselections WHERE predecessor_id=?", [old.id.uuidString]) ==
                    [[String(successors.count)]], "Historical relationships missing")
        try require(try sql.rows("PRAGMA foreign_key_check").isEmpty, "Invalid foreign keys")
        print("phase=\(argv[0]) controlledAppends=\(calls.count) persistedLinks=\(successors.count)")
    }
}
