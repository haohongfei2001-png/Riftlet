import Foundation
import RiftletCore

public enum SystemScreenshotObservationJournalError: Error, Equatable, Sendable {
    case wrongStoreMode, invalidOrigin, invalidProvenance, invalidOperation
    case identityMismatch, persistentIdentityMismatch, invalidCheckpoint, conflictingCheckpoint
}

/// Private candidate evidence, not a receipt policy or an upload-start fact.
/// The existing SQLite checkpoint transaction preserves the first observation in
/// each bounded category, including original byte-request observations. Nothing here changes queue visibility, marks
/// success, grants retry, reconstructs a selection, or reads image bytes.
public actor SystemScreenshotObservationJournal {
    private let store: QueueStore

    public nonisolated let scope: SystemScreenshotAdmissionScope

    public init(store: QueueStore, scope: SystemScreenshotAdmissionScope = .candidate) { self.store = store; self.scope = scope }

    public func record(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest) async throws {
        try await record(envelope, for: request, readOnly: false)
    }

    func record(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest, readOnly: Bool) async throws {
        guard await store.mode == .production else { throw SystemScreenshotObservationJournalError.wrongStoreMode }
        try Self.validate(envelope, for: request, scope: scope)
        // A self-consistent request is not proof that this journal belongs to
        // its durable queue. Verify the stored immutable identity as well. The
        // phase may advance while a read-only observation is in flight; it need
        // not equal the request snapshot, but must already have been dispatched.
        let asset = try await store.asset(id: request.asset.id)
        let operation = try await store.operation(id: request.operation.id)
        guard asset?.image == request.asset, let operation,
              operation.id == request.operation.id, operation.assetID == request.asset.id,
              operation.attempt == request.operation.attempt, operation.target == request.operation.target,
              operation.phase != .prepared,
              operation.phase.isUnresolved || operation.phase == .succeeded else {
            throw SystemScreenshotObservationJournalError.persistentIdentityMismatch
        }
        let invocations = [envelope.observation.requestEvidence?.invocationID,
            envelope.observation.completionEvidence?.binding.invocationID,
            envelope.observation.terminationEvidence?.binding.invocationID,
            envelope.observation.continuationEvidence?.binding.invocationID].compactMap { $0 }
        if !invocations.isEmpty {
            guard let original = try await store.dispatchInvocationID(for: operation.id),
                  invocations.allSatisfy({ $0 == original }) else {
                throw SystemScreenshotObservationJournalError.persistentIdentityMismatch
            }
        }
        let slots = Slot.classifyAll(envelope.observation)
        guard !slots.isEmpty else { return }
        let wrapper = Entry(schemaVersion: 1, envelope: envelope)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(wrapper)
        guard data.count <= ObservationDecoder.maximumPayloadBytes else {
            throw SystemScreenshotObservationJournalError.invalidCheckpoint
        }
        for slot in slots {
            let retained = try await store.saveCheckpointIfAbsent(data, for: Self.checkpointKey(request, slot: slot, scope: scope))
            // A corrupt or different-target first record is never replaced to
            // make a newer observation appear acceptable, even after restart.
            let original = try Self.decode(retained)
            try Self.validate(original.envelope, for: request, scope: scope)
            guard Slot.classifyAll(original.envelope.observation).contains(slot) else {
                throw SystemScreenshotObservationJournalError.conflictingCheckpoint
            }
            if original.envelope.provenance != envelope.provenance {
                // An upgraded observer can read an already journaled v15 slot.
                // Its first observation keeps its original bytes and source.
                guard readOnly,
                      original.envelope.provenance == .init(source: .integratedDevelopment, evidenceID: "attachment-entry-20261105-v15"),
                      envelope.provenance == .init(source: .integratedDevelopment, evidenceID: "attachment-handoff-20261105-v16"),
                      try await SystemScreenshotCandidateAdmission(store: store, scope: scope).observesPreviousEntrySource(request) else {
                    throw SystemScreenshotObservationJournalError.conflictingCheckpoint
                }
            }
        }
    }

    /// Only an exact original ordinary registration can retain its historical
    /// journal while observed by the successor internal scope. This cannot create
    /// registration or authorize input, and validates against this journal's store.
    func recordForOriginalOrdinary(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest) async throws {
        try await recordForOriginalScope(envelope, for: request, originalScope: .ordinary)
    }

    /// A new scope can preserve only an explicitly compatible original journal,
    /// using that exact registration. It never copies or upgrades an operation.
    func recordForOriginalScope(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest,
                                originalScope: SystemScreenshotAdmissionScope, readOnly: Bool = false) async throws {
        guard scope.originalObservationScopes.contains(originalScope),
              try await SystemScreenshotCandidateAdmission(store: store, scope: originalScope).admits(request) else {
            throw SystemScreenshotObservationJournalError.invalidOperation
        }
        try await SystemScreenshotObservationJournal(store: store, scope: originalScope).record(envelope, for: request, readOnly: readOnly)
    }

    /// These are code-owned audit categories, never values selected by page JSON.
    enum Slot: String, CaseIterable {
        case input, start, attached, ready, errorOrInvalidated, unknown
        case originalRequest, originalRequestTerminal, requestObservationClosed
        case terminationProof, independentTaskProof

        static func classifyAll(_ item: AttachmentObservation) -> [Slot] {
            var result = classify(item).map { [$0] } ?? []
            if let facts = item.requestEvidence {
                if !facts.requests.isEmpty { result.append(.originalRequest) }
                if facts.requests.contains(where: { $0.terminal != nil }) { result.append(.originalRequestTerminal) }
                if facts.observationClosed { result.append(.requestObservationClosed) }
            }
            if item.terminationEvidence != nil { result.append(.terminationProof) }
            if item.continuationEvidence != nil { result.append(.independentTaskProof) }
            return result
        }

        static func classify(_ item: AttachmentObservation) -> Slot? {
            if item.hasError || item.state == .invalidated { return .errorOrInvalidated }
            switch item.state {
            case .inputTriggered: return .input
            case .uploadStarted: return .start
            case .attached, .ready:
                guard item.exactImageIdentity, item.belongsToOriginalDraft,
                      item.attachmentID != nil, !item.attachmentAbsent, !item.isUploading else { return nil }
                return item.state == .attached ? .attached : .ready
            case .unknown: return .unknown
            case .failed, .invalidated: return nil
            }
        }
    }

    struct Entry: Codable, Equatable {
        let schemaVersion: Int
        let envelope: AttachmentObservationEnvelope
    }

    static func checkpointKey(_ request: TransferRequest, slot: Slot, scope: SystemScreenshotAdmissionScope = .candidate) -> String {
        "\(scope.journalPrefix):\(request.operation.id.uuidString.lowercased()):\(request.operation.attempt):\(slot.rawValue)"
    }

    private static func validate(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest,
                                 scope: SystemScreenshotAdmissionScope) throws {
        try ObservationDecoder.validate(envelope)
        guard request.asset.origin == scope.origin else { throw SystemScreenshotObservationJournalError.invalidOrigin }
        guard envelope.provenance.source == .integratedDevelopment else {
            throw SystemScreenshotObservationJournalError.invalidProvenance
        }
        let op = request.operation
        guard op.assetID == request.asset.id, op.phase != .prepared,
              op.phase.isUnresolved || op.phase == .succeeded else {
            throw SystemScreenshotObservationJournalError.invalidOperation
        }
        let expected = ObservationIdentity(operationID: op.id, assetID: request.asset.id,
            attempt: op.attempt, assetSHA256: request.asset.sha256, target: op.target)
        guard envelope.observation.identity == expected else {
            throw SystemScreenshotObservationJournalError.identityMismatch
        }
    }

    private static func decode(_ data: Data) throws -> Entry {
        guard data.count <= ObservationDecoder.maximumPayloadBytes else {
            throw SystemScreenshotObservationJournalError.invalidCheckpoint
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == Set(["schemaVersion", "envelope"]),
                  let envelope = object["envelope"] as? [String: Any] else {
                throw SystemScreenshotObservationJournalError.invalidCheckpoint
            }
            // Decode the nested payload through the same strict shape validator
            // as a live reply; Codable alone would ignore unexpected fields.
            _ = try ObservationDecoder.decode(JSONSerialization.data(withJSONObject: envelope))
            let entry = try JSONDecoder().decode(Entry.self, from: data)
            guard entry.schemaVersion == 1 else { throw SystemScreenshotObservationJournalError.invalidCheckpoint }
            return entry
        } catch let error as SystemScreenshotObservationJournalError { throw error }
        catch { throw SystemScreenshotObservationJournalError.invalidCheckpoint }
    }
}
