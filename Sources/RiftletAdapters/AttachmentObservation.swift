import Foundation
import RiftletCore

/// Provenance is an audit label, never permission to consume a screenshot.
public enum ObservationSource: String, Codable, Sendable {
    case syntheticFixture, sanitizedReal
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
    case inputTriggered, attached, ready, failed, unknown, invalidated
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

    public init(identity: ObservationIdentity, state: AttachmentObservedState,
                attachmentID: String? = nil, exactImageIdentity: Bool = false,
                belongsToOriginalDraft: Bool = false, hasError: Bool = false,
                isUploading: Bool = false, attachmentAbsent: Bool = false,
                automaticRetryExcluded: Bool = false) {
        self.identity = identity; self.state = state; self.attachmentID = attachmentID
        self.exactImageIdentity = exactImageIdentity
        self.belongsToOriginalDraft = belongsToOriginalDraft
        self.hasError = hasError; self.isUploading = isUploading
        self.attachmentAbsent = attachmentAbsent
        self.automaticRetryExcluded = automaticRetryExcluded
    }
}

public struct AttachmentObservationEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let provenance: ObservationProvenance
    public let observation: AttachmentObservation

    public init(provenance: ObservationProvenance, observation: AttachmentObservation) {
        schemaVersion = 1; self.provenance = provenance; self.observation = observation
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
                    "attachmentAbsent", "automaticRetryExcluded"
                  ])),
                  let identity = observation["identity"] as? [String: Any],
                  Set(identity.keys) == Set(["operationID", "assetID", "attempt", "assetSHA256", "target"]),
                  let target = identity["target"] as? [String: Any],
                  Set(target.keys).isSubset(of: Set([
                    "adapterID", "surface", "applicationID", "sessionID", "windowID", "tabID",
                    "documentID", "composerID", "draftGeneration"
                  ])) else { throw ObservationError.invalidPayload }
            let envelope = try JSONDecoder().decode(AttachmentObservationEnvelope.self, from: data)
            try validate(envelope)
            return envelope
        } catch let error as ObservationError { throw error }
        catch { throw ObservationError.invalidPayload }
    }

    static func validate(_ envelope: AttachmentObservationEnvelope) throws {
        guard envelope.schemaVersion == 1 else { throw ObservationError.unsupportedSchema(envelope.schemaVersion) }
        let item = envelope.observation
        guard validToken(envelope.provenance.evidenceID) else { throw ObservationError.invalidField("evidenceID") }
        guard item.identity.attempt > 0,
              item.identity.assetSHA256.utf8.count == 64,
              item.identity.assetSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ObservationError.invalidField("image identity")
        }
        let target = item.identity.target
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
