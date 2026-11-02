import Foundation

/// Browser transport facts, not platform attachment state. A 2xx response or an
/// aborted request cannot certify completion, retirement, or independent input.
/// IDs are local to this original document; no URL, headers or bodies are kept.
public struct ObservedRequestEvidence: Codable, Equatable, Sendable {
    public enum CloseReason: String, Codable, Sendable {
        case hookReplaced, identityInvalid, requestBound, documentEnded
        case duplicateSend, reentry, invalidEvent
    }
    public struct Request: Codable, Equatable, Sendable {
        public enum Transport: String, Codable, Sendable { case fetch, xhr }
        public enum Terminal: String, Codable, Sendable {
            case response, rejected, aborted, error, timeout, threw
        }
        public struct Progress: Codable, Equatable, Sendable {
            public let loaded: Int64
            public let total: Int64
            public let lengthComputable: Bool
            public let sequence: Int
            public let observedAtMS: Double
        }
        public let requestID: Int
        public let transport: Transport
        public let requestSequence: Int
        public let requestedAtMS: Double
        public let terminal: Terminal?
        public let terminalSequence: Int?
        public let terminalAtMS: Double?
        public let status: Int?
        public let progress: Progress?
    }
    public let version: Int
    public let invocationID: UUID
    public let inputCount: Int
    public let inputSequence: Int
    public let inputObservedAtMS: Double
    public let fileSHA256: String
    public let coverage: String
    public let observationClosed: Bool
    public let closeReason: CloseReason?
    public let requests: [Request]

    func validate(identity: ObservationIdentity) throws {
        func validTime(_ time: Double) -> Bool { time.isFinite && time >= 0 }
        guard version == 1, inputCount == 1, inputSequence > 0,
              validTime(inputObservedAtMS), fileSHA256 == identity.assetSHA256,
              coverage == "exactOriginalFileOnly", requests.count <= 8,
              observationClosed == (closeReason != nil),
              Set(requests.map(\.requestID)).count == requests.count else {
            throw ObservationError.invalidField("request evidence")
        }
        for request in requests {
            guard request.requestID > 0, request.requestSequence > 0,
                  validTime(request.requestedAtMS) else {
                throw ObservationError.invalidField("request identity")
            }
            if let terminal = request.terminal {
                guard let sequence = request.terminalSequence, sequence > request.requestSequence,
                      let time = request.terminalAtMS, validTime(time), time >= request.requestedAtMS,
                      request.status.map({ (0...599).contains($0) }) ?? true,
                      terminal != .response || request.status != nil else {
                    throw ObservationError.invalidField("request terminal")
                }
            } else if request.terminalSequence != nil || request.terminalAtMS != nil || request.status != nil {
                throw ObservationError.invalidField("unexpected request terminal")
            }
            if let progress = request.progress {
                guard request.transport == .xhr, progress.loaded >= 0, progress.total >= 0,
                      progress.loaded <= 9_007_199_254_740_991, progress.total <= 9_007_199_254_740_991,
                      !progress.lengthComputable || progress.loaded <= progress.total,
                      progress.sequence > request.requestSequence,
                      request.terminalSequence.map({ progress.sequence < $0 }) ?? true,
                      validTime(progress.observedAtMS), progress.observedAtMS >= request.requestedAtMS,
                      request.terminalAtMS.map({ progress.observedAtMS <= $0 }) ?? true else {
                    throw ObservationError.invalidField("request progress")
                }
            }
        }
    }

    static func validateShape(_ value: Any) throws {
        guard let object = value as? [String: Any], Set(object.keys).isSubset(of: [
            "version", "invocationID", "inputCount", "inputSequence", "inputObservedAtMS",
            "fileSHA256", "coverage", "observationClosed", "closeReason", "requests"
        ]), let requests = object["requests"] as? [[String: Any]], requests.count <= 8 else {
            throw ObservationError.invalidPayload
        }
        for request in requests {
            guard Set(request.keys).isSubset(of: ["requestID", "transport", "requestSequence", "requestedAtMS",
                "terminal", "terminalSequence", "terminalAtMS", "status", "progress"]) else {
                throw ObservationError.invalidPayload
            }
            if let value = request["progress"], !(value is NSNull) {
                guard let progress = value as? [String: Any], Set(progress.keys) == [
                    "loaded", "total", "lengthComputable", "sequence", "observedAtMS"
                ] else { throw ObservationError.invalidPayload }
            }
        }
    }
}
