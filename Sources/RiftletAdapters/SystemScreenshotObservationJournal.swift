import Foundation
import RiftletCore

public enum SystemScreenshotObservationJournalError: Error, Equatable, Sendable {
    case wrongStoreMode, invalidOrigin, invalidProvenance, invalidOperation
    case identityMismatch, persistentIdentityMismatch, invalidCheckpoint, conflictingCheckpoint
}

/// Private candidate evidence, not a receipt policy or an upload-start fact.
/// The existing SQLite checkpoint transaction preserves the first observation in
/// each of six bounded categories. Nothing here changes queue visibility, marks
/// success, grants retry, reconstructs a selection, or reads image bytes.
public actor SystemScreenshotObservationJournal {
    private let store: QueueStore

    public nonisolated let scope: SystemScreenshotAdmissionScope

    public init(store: QueueStore, scope: SystemScreenshotAdmissionScope = .candidate) { self.store = store; self.scope = scope }

    public func record(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest) async throws {
        guard await store.mode == .production else { throw SystemScreenshotObservationJournalError.wrongStoreMode }
        try Self.validate(envelope, for: request)
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
        guard let slot = Slot.classify(envelope.observation) else { return }
        let wrapper = Entry(schemaVersion: 1, envelope: envelope)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(wrapper)
        guard data.count <= ObservationDecoder.maximumPayloadBytes else {
            throw SystemScreenshotObservationJournalError.invalidCheckpoint
        }
        let retained = try await store.saveCheckpointIfAbsent(data, for: Self.checkpointKey(request, slot: slot, scope: scope))
        // This also checks a first record loaded after restart or written by a
        // second observer. A corrupt or different-target first record is never
        // replaced to make a newer observation appear acceptable.
        let original = try Self.decode(retained)
        try Self.validate(original.envelope, for: request)
        guard Slot.classify(original.envelope.observation) == slot,
              original.envelope.provenance == envelope.provenance else {
            throw SystemScreenshotObservationJournalError.conflictingCheckpoint
        }
    }

    /// Only an exact original ordinary registration can retain its historical
    /// journal while observed by the successor internal scope. This cannot create
    /// registration or authorize input, and validates against this journal's store.
    func recordForOriginalOrdinary(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest) async throws {
        guard scope == .ordinaryCurrentDraftInternal,
              try await SystemScreenshotCandidateAdmission(store: store, scope: .ordinary).admits(request) else {
            throw SystemScreenshotObservationJournalError.invalidOperation
        }
        try await SystemScreenshotObservationJournal(store: store, scope: .ordinary).record(envelope, for: request)
    }

    /// These are code-owned audit categories, never values selected by page JSON.
    enum Slot: String, CaseIterable {
        case input, start, attached, ready, errorOrInvalidated, unknown

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

    private static func validate(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest) throws {
        try ObservationDecoder.validate(envelope)
        guard request.asset.origin == .systemScreenshot else { throw SystemScreenshotObservationJournalError.invalidOrigin }
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
