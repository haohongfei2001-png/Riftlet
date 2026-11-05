import Foundation

/// Optional page instrumentation for one attachment entry. It is read alongside
/// the observation and never becomes part of the receipt, journal or input decision.
struct AttachmentEntryDiagnostics: Decodable, Equatable {
    enum Stage: String, Decodable {
        case direct, entry, menu, picker, handoff, setter, change, observation, prepare
    }
    enum Cause: String, Decodable {
        case none, entryUnavailable, menuActionMissing, menuActionNotRun, pickerNotInvoked, pickerRejected
        case inputLost, ambiguous, userInterrupted, targetChanged, executionBusy, timeout, exception
        case invalidFile, unsupportedInput, deliveryUncertain
    }
    enum ExceptionType: String, Decodable {
        case none, Error, TypeError, RangeError, ReferenceError, SyntaxError, SecurityError, NotAllowedError
        case InvalidStateError, NotSupportedError, AbortError, DOMException, other
    }

    let version: Int
    let entryCandidates, entryActivations, openedContainers, menuActivations, pickerClicks, pickerShows: Int
    let inputSeen, inputConnected, setterEntered, changeReturned: Bool
    let stage: Stage
    let cause: Cause
    let exceptionType: ExceptionType

    static func read(_ value: Any?) -> Self? {
        guard let object = value as? [String: Any], object.count <= 32,
              let bytes = try? JSONSerialization.data(withJSONObject: object), bytes.count <= 2_048,
              let result = try? JSONDecoder().decode(Self.self, from: bytes), result.version == 1 else { return nil }
        return result
    }

    var traceFields: [String: Any] {
        let counts = ["entryCandidates": entryCandidates, "entryActivations": entryActivations,
            "openedContainers": openedContainers, "menuActivations": menuActivations,
            "pickerClicks": pickerClicks, "pickerShows": pickerShows]
        var fields: [String: Any] = counts.mapValues { min(65_535, max(0, $0)) }
        fields["inputSeen"] = inputSeen
        fields["inputConnected"] = inputConnected
        fields["setterEntered"] = setterEntered
        fields["changeReturned"] = changeReturned
        fields["entryStage"] = stage.rawValue
        fields["entryCause"] = cause.rawValue
        fields["exceptionType"] = exceptionType.rawValue
        return fields
    }
}
