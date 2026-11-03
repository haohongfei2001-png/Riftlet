import Foundation

/// Ownership of a browser request body and its independently observed attachment.
/// These are document-local identities, NOT server task IDs or finalization.
/// A source-reviewed adapter also has to establish the platform's append behavior;
/// FileList assignment, change returning, or an HTTP status alone is insufficient.
public struct AttachmentInputIsolationEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case originalRequestBodyOwned }
    public enum Transport: String, Codable, Sendable { case xhr, fetch }
    public let version: Int
    public let ownershipID: String
    public let inputElementID: String
    public let kind: Kind
    public let requestID: Int
    public let requestSequence: Int
    public let requestTransport: Transport
    public let originalSHA256: String
    public let originalByteCount: Int64
    public let startEvidenceID: String
    public let inputSequence: Int
    public let callSettledSequence: Int
    public let startSequence: Int
    public let observedSequence: Int

    public init(version: Int = 1, ownershipID: String, inputElementID: String,
                kind: Kind = .originalRequestBodyOwned, requestID: Int, requestSequence: Int,
                requestTransport: Transport, originalSHA256: String, originalByteCount: Int64,
                startEvidenceID: String, inputSequence: Int, callSettledSequence: Int,
                startSequence: Int, observedSequence: Int) {
        self.version = version; self.ownershipID = ownershipID; self.inputElementID = inputElementID
        self.kind = kind; self.requestID = requestID; self.requestSequence = requestSequence
        self.requestTransport = requestTransport; self.originalSHA256 = originalSHA256
        self.originalByteCount = originalByteCount; self.startEvidenceID = startEvidenceID
        self.inputSequence = inputSequence; self.callSettledSequence = callSettledSequence
        self.startSequence = startSequence; self.observedSequence = observedSequence
    }

    public func validates(receipt: TransferReceipt, asset: ImportedAsset) -> Bool {
        version == 1 && kind == .originalRequestBodyOwned
            && AttachmentEvidenceValidation.token(ownershipID)
            && AttachmentEvidenceValidation.token(inputElementID)
            && AttachmentEvidenceValidation.token(startEvidenceID)
            && requestID > 0 && inputSequence > 0 && requestSequence > inputSequence
            && requestSequence < startSequence
            && callSettledSequence > inputSequence && startSequence > inputSequence
            && observedSequence >= max(requestSequence, max(callSettledSequence, startSequence))
            && AttachmentEvidenceValidation.sha256(originalSHA256)
            && originalSHA256 == asset.sha256 && originalByteCount == asset.byteCount
            && originalByteCount > 0 && originalByteCount <= AttachmentEvidenceValidation.maximumBytes
            && receipt.outcome == .uploadStarted && receipt.uploadStartEvidence?.inputCount == 1
            && receipt.uploadStartEvidence?.evidenceID == startEvidenceID
    }

    /// Request counters belong to one document-wide observer, not to a click pin.
    /// The caller compares only continuously observed scopes in that document.
    func conflicts(with other: Self) -> Bool {
        ownershipID == other.ownershipID || requestID == other.requestID
    }
}
