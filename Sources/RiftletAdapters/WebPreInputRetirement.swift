import Foundation
import RiftletCore

/// Called only by append while it owns the original durable invocation. This
/// never consumes an observation as upload success or permits UNKNOWN replay.
enum WebPreInputRetirement {
    static func rejection(from envelope: AttachmentObservationEnvelope,
                          for request: TransferRequest) throws -> PreInputRejection? {
        try ObservationDecoder.validate(envelope)
        guard let proof = envelope.observation.preInputRetirement else { return nil }
        guard request.operation.phase == .dispatchIntent,
              let invocationID = request.invocationID else { return nil }
        let identity = envelope.observation.identity
        guard envelope.provenance.source == .integratedDevelopment,
              identity.operationID == request.operation.id,
              identity.assetID == request.asset.id, request.operation.assetID == request.asset.id,
              identity.attempt == request.operation.attempt,
              identity.assetSHA256 == request.asset.sha256, identity.target == request.operation.target,
              proof.invocationID == invocationID else { throw ObservationError.identityMismatch }
        return PreInputRejection(operationID: identity.operationID, assetID: identity.assetID,
            attempt: identity.attempt, assetSHA256: identity.assetSHA256, target: identity.target,
            invocationID: invocationID, stage: .pageRetiredBeforeFileInput)
    }
}
