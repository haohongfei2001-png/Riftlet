import Foundation
import RiftletCore

/// Provenance is an audit label, never permission to consume a screenshot.
public enum ObservationSource: String, Codable, Sendable {
    case syntheticFixture, sanitizedReal
    /// Output of the integrated development program; this labels code provenance,
    /// not a successful live test. Native scopes distinguish generated acceptance
    /// assets from the explicit original-screenshot candidate; neither label grants admission.
    case integratedDevelopment
}

public struct ObservationProvenance: Codable, Equatable, Sendable {
    public let source: ObservationSource
    /// Public-safe case/environment reference. No page text, URL, tokens or local paths.
    public let evidenceID: String

    public init(source: ObservationSource, evidenceID: String) {
        self.source = source; self.evidenceID = evidenceID
    }
}

public struct ObservationIdentity: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let assetID: UUID
    public let attempt: Int
    public let assetSHA256: String
    public let target: TargetLease

    public init(operationID: UUID, assetID: UUID, attempt: Int,
                assetSHA256: String, target: TargetLease) {
        self.operationID = operationID; self.assetID = assetID; self.attempt = attempt
        self.assetSHA256 = assetSHA256; self.target = target
    }
}

/// These are observer facts, not queue states or admission decisions.
public enum AttachmentObservedState: String, Codable, Sendable {
    case inputTriggered, uploadStarted, attached, ready, failed, unknown, invalidated
}

/// Page facts only. Identity and attachment are supplied by the enclosing
/// observation; a trusted start profile is chosen by native code, never JSON.
public struct ObservedUploadStart: Codable, Equatable, Sendable {
    public let version: Int
    public let signal: UploadStartSignal
    public let evidenceID: String
    public let inputCount: Int
    public let inputSequence: Int
    public let startSequence: Int
    public let previousProgress: Double
    public let currentProgress: Double
    public let inputObservedAtMS: Double
    public let startObservedAtMS: Double
}

public struct AttachmentObservation: Codable, Equatable, Sendable {
    public let identity: ObservationIdentity
    public let state: AttachmentObservedState
    public let attachmentID: String?
    /// Must come from the independently validated observer, not an echoed request name.
    public let exactImageIdentity: Bool
    public let belongsToOriginalDraft: Bool
    public let hasError: Bool
    public let isUploading: Bool
    public let attachmentAbsent: Bool
    public let automaticRetryExcluded: Bool
    public let uploadStart: ObservedUploadStart?

    public init(identity: ObservationIdentity, state: AttachmentObservedState,
                attachmentID: String? = nil, exactImageIdentity: Bool = false,
                belongsToOriginalDraft: Bool = false, hasError: Bool = false,
                isUploading: Bool = false, attachmentAbsent: Bool = false,
                automaticRetryExcluded: Bool = false, uploadStart: ObservedUploadStart? = nil) {
        self.identity = identity; self.state = state; self.attachmentID = attachmentID
        self.exactImageIdentity = exactImageIdentity
        self.belongsToOriginalDraft = belongsToOriginalDraft
        self.hasError = hasError; self.isUploading = isUploading
        self.attachmentAbsent = attachmentAbsent
        self.automaticRetryExcluded = automaticRetryExcluded
        self.uploadStart = uploadStart
    }
}

public struct AttachmentObservationEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let provenance: ObservationProvenance
    public let observation: AttachmentObservation

    public init(schemaVersion: Int = 1, provenance: ObservationProvenance, observation: AttachmentObservation) {
        self.schemaVersion = schemaVersion; self.provenance = provenance; self.observation = observation
    }
}

public enum ObservationError: Error, Equatable {
    case oversizedPayload, invalidPayload, unsupportedSchema(Int), invalidField(String)
    case identityMismatch, profileTargetMismatch, operationNotDispatched
    case syntheticEvidenceForRealAsset
}

/// Bounded, versioned interchange for fixtures and the future narrow browser bridge.
/// Payloads cannot supply a profile, outcome, positiveReady or safeToRetry decision.
public enum ObservationDecoder {
    public static let maximumPayloadBytes = 64 * 1024

    public static func decode(_ data: Data) throws -> AttachmentObservationEnvelope {
        guard data.count <= maximumPayloadBytes else { throw ObservationError.oversizedPayload }
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(root.keys) == Set(["schemaVersion", "provenance", "observation"]),
                  let provenance = root["provenance"] as? [String: Any],
                  Set(provenance.keys) == Set(["source", "evidenceID"]),
                  let observation = root["observation"] as? [String: Any],
                  Set(observation.keys).isSubset(of: Set([
                    "identity", "state", "attachmentID", "exactImageIdentity",
                    "belongsToOriginalDraft", "hasError", "isUploading",
                    "attachmentAbsent", "automaticRetryExcluded", "uploadStart"
                  ])),
                  let identity = observation["identity"] as? [String: Any],
                  Set(identity.keys) == Set(["operationID", "assetID", "attempt", "assetSHA256", "target"]),
                  let target = identity["target"] as? [String: Any],
                  Set(target.keys).isSubset(of: Set([
                    "adapterID", "surface", "applicationID", "sessionID", "windowID", "tabID",
                    "documentID", "composerID", "draftGeneration", "logicalDraftIdentity"
                  ])) else { throw ObservationError.invalidPayload }
            if let logical = target["logicalDraftIdentity"] {
                guard let fields = logical as? [String: Any],
                      Set(fields.keys) == Set(["profileID", "id"]) else { throw ObservationError.invalidPayload }
            }
            if let rawStart = observation["uploadStart"] {
                guard let fields = rawStart as? [String: Any], Set(fields.keys) == Set([
                    "version", "signal", "evidenceID", "inputCount", "inputSequence", "startSequence",
                    "previousProgress", "currentProgress", "inputObservedAtMS", "startObservedAtMS"
                ]) else { throw ObservationError.invalidPayload }
            }
            let envelope = try JSONDecoder().decode(AttachmentObservationEnvelope.self, from: data)
            try validate(envelope)
            return envelope
        } catch let error as ObservationError { throw error }
        catch { throw ObservationError.invalidPayload }
    }

    static func validate(_ envelope: AttachmentObservationEnvelope) throws {
        guard [1, 2].contains(envelope.schemaVersion) else { throw ObservationError.unsupportedSchema(envelope.schemaVersion) }
        let item = envelope.observation
        if envelope.schemaVersion == 1, item.uploadStart != nil || item.state == .uploadStarted {
            throw ObservationError.invalidField("legacy upload start")
        }
        if item.state == .uploadStarted {
            guard envelope.schemaVersion == 2, let start = item.uploadStart,
                  start.version == 1, start.signal == .correlatedProgress,
                  start.evidenceID.utf8.count == 36, UUID(uuidString: start.evidenceID) != nil,
                  start.inputCount == 1, start.inputSequence > 0, start.startSequence > start.inputSequence,
                  start.previousProgress.isFinite, start.currentProgress.isFinite,
                  start.previousProgress >= 0, start.currentProgress > start.previousProgress,
                  start.currentProgress < 100,
                  start.inputObservedAtMS.isFinite, start.startObservedAtMS.isFinite,
                  start.inputObservedAtMS >= 0, start.startObservedAtMS > start.inputObservedAtMS,
                  item.attachmentID != nil, item.exactImageIdentity, item.belongsToOriginalDraft,
                  item.isUploading, !item.hasError, !item.attachmentAbsent, !item.automaticRetryExcluded else {
                throw ObservationError.invalidField("upload start")
            }
        } else if item.uploadStart != nil {
            throw ObservationError.invalidField("unexpected upload start")
        }
        guard validToken(envelope.provenance.evidenceID) else { throw ObservationError.invalidField("evidenceID") }
        guard item.identity.attempt > 0,
              item.identity.assetSHA256.utf8.count == 64,
              item.identity.assetSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ObservationError.invalidField("image identity")
        }
        let target = item.identity.target
        if let logical = target.logicalDraftIdentity,
           !validToken(logical.profileID) || !validToken(logical.id) {
            throw ObservationError.invalidField("logical draft identity")
        }
        let tokens = [target.adapterID, target.applicationID, target.sessionID, target.windowID,
                      target.documentID, target.composerID, target.draftGeneration]
        guard tokens.allSatisfy(validToken), target.tabID.map(validToken) ?? true else {
            throw ObservationError.invalidField("target identity")
        }
        if target.surface == .webChat || target.surface == .webWork {
            guard let tabID = target.tabID, validToken(tabID) else { throw ObservationError.invalidField("tab identity") }
        }
        if let attachmentID = item.attachmentID, !validToken(attachmentID) {
            throw ObservationError.invalidField("attachment identity")
        }
    }

    private static func validToken(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= 512 && !value.unicodeScalars.contains(where: { $0.value < 32 })
    }
}
