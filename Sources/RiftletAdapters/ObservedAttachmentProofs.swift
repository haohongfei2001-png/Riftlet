import Foundation
import RiftletCore

/// Internal normalized facts, NOT a claimed ChatGPT response schema. Only a
/// source-reviewed platform decoder may produce these. The present page has no
/// decoder for irreversible retirement or independent platform task ownership.
/// Native configuration selects profiles; page payloads cannot select admission.
public struct ObservedAttachmentTermination: Codable, Equatable, Sendable {
    public let version: Int
    public let evidenceID: String
    public let binding: AttachmentOperationBinding
    public let task: PlatformAttachmentTaskIdentity
    public let retirementID: String
    public let kind: AttachmentTerminationEvidence.Kind
}

public struct ObservedAttachmentContinuation: Codable, Equatable, Sendable {
    public let version: Int
    public let evidenceID: String
    public let binding: AttachmentOperationBinding
    public let taskIsolation: AttachmentTaskIsolationEvidence?
    public let inputIsolation: AttachmentInputIsolationEvidence?

    public init(version: Int = 1, evidenceID: String, binding: AttachmentOperationBinding,
                taskIsolation: AttachmentTaskIsolationEvidence? = nil,
                inputIsolation: AttachmentInputIsolationEvidence? = nil) {
        self.version = version; self.evidenceID = evidenceID; self.binding = binding
        self.taskIsolation = taskIsolation; self.inputIsolation = inputIsolation
    }
}

enum ObservedAttachmentProofs {
    static func validate(_ envelope: AttachmentObservationEnvelope) throws {
        let item = envelope.observation
        let extended = item.requestEvidence != nil || item.completionEvidence != nil
            || item.terminationEvidence != nil || item.continuationEvidence != nil
        guard extended == (envelope.schemaVersion == 4), !extended || item.preInputRetirement == nil else {
            throw ObservationError.invalidField("proof schema")
        }
        if let facts = item.requestEvidence { try facts.validate(identity: item.identity) }
        func token(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 256
                && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
        }
        func taskMatches(_ task: PlatformAttachmentTaskIdentity) -> Bool {
            task.version == 1 && token(task.requestID) && token(task.taskID) && token(task.attachmentReference)
                && task.originalSHA256 == item.identity.assetSHA256
                && task.originalByteCount > 0 && task.originalByteCount <= 8 * 1024 * 1024
        }
        func bindingMatches(_ binding: AttachmentOperationBinding) -> Bool {
            binding.version == 1 && binding.operationID == item.identity.operationID
                && binding.assetID == item.identity.assetID && binding.attempt == item.identity.attempt
                && binding.assetSHA256 == item.identity.assetSHA256 && binding.target == item.identity.target
                && binding.attachmentID == item.attachmentID && !binding.attachmentID.isEmpty
                && (item.requestEvidence.map { $0.invocationID == binding.invocationID } ?? true)
        }
        if let proof = item.completionEvidence {
            guard proof.version == 1, bindingMatches(proof.binding),
                  item.state == .attached || item.state == .ready,
                  item.exactImageIdentity, item.belongsToOriginalDraft,
                  !item.hasError, !item.isUploading, !item.attachmentAbsent,
                  item.terminationEvidence == nil, item.continuationEvidence == nil else {
                throw ObservationError.invalidField("completion proof")
            }
        } else if envelope.schemaVersion == 4 && (item.state == .attached || item.state == .ready) {
            throw ObservationError.invalidField("missing completion proof")
        }
        if let proof = item.terminationEvidence {
            guard proof.version == 1, token(proof.evidenceID), token(proof.retirementID),
                  taskMatches(proof.task), proof.kind == .irreversibleRetirementNoAutomaticRetry,
                  bindingMatches(proof.binding), item.state == .failed,
                  item.exactImageIdentity, item.belongsToOriginalDraft, item.hasError,
                  item.attachmentAbsent, item.automaticRetryExcluded, !item.isUploading,
                  item.completionEvidence == nil, item.continuationEvidence == nil else {
                throw ObservationError.invalidField("termination proof")
            }
        } else if envelope.schemaVersion == 4 && item.state == .failed {
            throw ObservationError.invalidField("missing termination proof")
        }
        if let proof = item.continuationEvidence {
            guard proof.version == 1, token(proof.evidenceID), bindingMatches(proof.binding), item.state == .uploadStarted,
                  let start = item.uploadStart,
                  (proof.taskIsolation == nil) != (proof.inputIsolation == nil),
                  item.completionEvidence == nil, item.terminationEvidence == nil else {
                throw ObservationError.invalidField("continuation proof")
            }
            if let isolation = proof.taskIsolation {
                guard isolation.version == 1, taskMatches(isolation.task), token(isolation.ownershipID),
                      isolation.kind == .independentTaskSurvivesSubsequentInput,
                      isolation.inputSequence > 0, isolation.callSettledSequence > isolation.inputSequence,
                      isolation.startSequence > isolation.inputSequence,
                      isolation.observedSequence >= max(isolation.callSettledSequence, isolation.startSequence),
                      isolation.startEvidenceID == start.evidenceID,
                      isolation.inputSequence == start.inputSequence,
                      isolation.startSequence == start.startSequence else {
                    throw ObservationError.invalidField("continuation task proof")
                }
            }
            if let isolation = proof.inputIsolation {
                // These are local browser request facts, not invented server task
                // IDs. Every field must describe the sole original-file request.
                guard isolation.version == 1, isolation.kind == .originalRequestBodyOwned,
                      token(isolation.ownershipID), token(isolation.inputElementID),
                      isolation.originalSHA256 == item.identity.assetSHA256,
                      isolation.originalByteCount > 0, isolation.originalByteCount <= 8 * 1024 * 1024,
                      isolation.startEvidenceID == start.evidenceID,
                      isolation.inputSequence == start.inputSequence,
                      isolation.startSequence == start.startSequence,
                      isolation.inputSequence > 0, isolation.callSettledSequence > isolation.inputSequence,
                      isolation.startSequence > isolation.inputSequence,
                      isolation.requestSequence > isolation.inputSequence,
                      isolation.requestSequence < isolation.startSequence,
                      isolation.observedSequence >= max(isolation.callSettledSequence, isolation.startSequence),
                      isolation.observedSequence >= isolation.requestSequence,
                      let facts = item.requestEvidence, !facts.observationClosed, facts.closeReason == nil,
                      facts.invocationID == proof.binding.invocationID, facts.inputCount == 1,
                      facts.inputSequence == isolation.inputSequence,
                      facts.inputObservedAtMS == start.inputObservedAtMS,
                      facts.fileSHA256 == isolation.originalSHA256,
                      facts.requests.count == 1, let request = facts.requests.first,
                      request.requestID == isolation.requestID,
                      request.requestSequence == isolation.requestSequence,
                      request.transport.rawValue == isolation.requestTransport.rawValue,
                      request.requestedAtMS >= facts.inputObservedAtMS,
                      request.terminal == nil || request.terminal == .response,
                      request.terminalSequence.map({ $0 <= isolation.observedSequence }) ?? true,
                      request.progress.map({ $0.sequence <= isolation.observedSequence }) ?? true else {
                    throw ObservationError.invalidField("continuation input proof")
                }
            }
        }
    }

    static func validateShape(_ observation: [String: Any]) throws {
        func fields(_ value: Any?, allowed: Set<String>) throws -> [String: Any] {
            guard let value = value as? [String: Any], Set(value.keys).isSubset(of: allowed) else {
                throw ObservationError.invalidPayload
            }
            return value
        }
        func task(_ value: Any?) throws {
            _ = try fields(value, allowed: ["version", "requestID", "taskID", "attachmentReference",
                "originalSHA256", "originalByteCount"])
        }
        func binding(_ value: Any?) throws {
            let binding = try fields(value, allowed: ["version", "operationID", "assetID", "attempt",
                "assetSHA256", "target", "invocationID", "attachmentID"])
            let target = try fields(binding["target"], allowed: ["adapterID", "surface", "applicationID",
                "sessionID", "windowID", "tabID", "documentID", "composerID", "draftGeneration",
                "logicalDraftIdentity", "clickBindingID"])
            if let logical = target["logicalDraftIdentity"] {
                _ = try fields(logical, allowed: ["profileID", "id"])
            }
        }
        if let value = observation["completionEvidence"] {
            let proof = try fields(value, allowed: ["version", "evidenceID", "binding", "kind", "originalByteCount",
                "originalSHA256", "observedByteCount", "observedSHA256", "originalWidth", "originalHeight",
                "originalPixelSHA256", "previewWidth", "previewHeight", "previewPixelSHA256", "platform"])
            try binding(proof["binding"])
            if let platform = proof["platform"] {
                let platform = try fields(platform, allowed: ["version", "task", "finalizationID", "kind"])
                try task(platform["task"])
            }
        }
        if let value = observation["terminationEvidence"] {
            let proof = try fields(value, allowed: ["version", "evidenceID", "binding", "task", "retirementID", "kind"])
            try binding(proof["binding"]); try task(proof["task"])
        }
        if let value = observation["continuationEvidence"] {
            let proof = try fields(value, allowed: ["version", "evidenceID", "binding", "taskIsolation", "inputIsolation"])
            try binding(proof["binding"])
            guard (proof["taskIsolation"] == nil) != (proof["inputIsolation"] == nil) else {
                throw ObservationError.invalidPayload
            }
            if let value = proof["taskIsolation"] {
                let isolation = try fields(value, allowed: ["version", "task", "ownershipID", "kind",
                    "startEvidenceID", "inputSequence", "callSettledSequence", "startSequence", "observedSequence"])
                try task(isolation["task"])
            }
            if let value = proof["inputIsolation"] {
                _ = try fields(value, allowed: ["version", "ownershipID", "inputElementID", "kind", "requestID",
                    "requestSequence", "requestTransport", "originalSHA256", "originalByteCount", "startEvidenceID",
                    "inputSequence", "callSettledSequence", "startSequence", "observedSequence"])
            }
        }
    }
}
