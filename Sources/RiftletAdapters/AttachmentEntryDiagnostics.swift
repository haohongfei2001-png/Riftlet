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
    var edgeCalibration: EdgeCalibration?

    /// Uncalibrated DOM facts. These fields never decode into an observation,
    /// receipt or policy, and do not assert upload START or final completion.
    struct EdgeCalibration: Decodable, Equatable {
        enum ProgressDecision: String, Decodable {
            case awaitingInput, fileBlobMissing, ownershipTopology, retainedBaseline, selectionChanged, draftChanged
            case previewEncoding, previewMismatch, previewUnavailable, encodedPreviewWithoutProgress
            case stagedProgressAwaitingPreview, previewWatcherUnavailable
            case conflictingFileLabel, nodeReused, progressUnavailable, firstProgress, historyUnavailable, inputCount, terminal, started
        }
        let progressDecision: ProgressDecision?
        let version, sampleNumber: Int
        let baselineAvailable, beforeInputBaselineAvailable, originalDraftCurrent, clickBound: Bool
        let originalTextUnchanged, selectionComparable, originalSelectionUnchanged: Bool
        let baselineAttachmentNodes, retainedBaselineAttachmentNodes: Int
        let matchedNodes, matchedOriginalFormNodes, newMatchedNodes, filenameMatchedNodes, blobMatchedNodes: Int
        let progressNodes: Int
        let progressValueKnown: Bool
        let progressPercentMinimum, progressPercentMaximum: Int
        let busyAttributeNodes, readyAttributeNodes, errorAttributeNodes, loadedImageNodes, changedMatchedPreviews: Int
        let scanLimited, samplingFailed: Bool

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case version, sampleNumber, baselineAvailable, beforeInputBaselineAvailable, originalDraftCurrent, clickBound
            case originalTextUnchanged, selectionComparable, originalSelectionUnchanged
            case baselineAttachmentNodes, retainedBaselineAttachmentNodes, matchedNodes, matchedOriginalFormNodes
            case newMatchedNodes, filenameMatchedNodes, blobMatchedNodes, progressNodes, progressValueKnown
            case progressPercentMinimum, progressPercentMaximum, busyAttributeNodes, readyAttributeNodes, errorAttributeNodes
            case loadedImageNodes, changedMatchedPreviews, scanLimited, samplingFailed, progressDecision
        }

        static func read(_ value: Any?) -> Self? {
            guard let fields = value as? [String: Any] else { return nil }
            let mandatory = Set(CodingKeys.allCases.map(\.rawValue)).subtracting(["progressDecision"])
            if let decision = fields["progressDecision"] {
                guard let name = decision as? String, ProgressDecision(rawValue: name) != nil else { return nil }
            }
            guard Set(fields.keys).subtracting(["progressDecision"]) == mandatory,
                  let bytes = try? JSONSerialization.data(withJSONObject: fields), bytes.count <= 1_536,
                  let result = try? JSONDecoder().decode(Self.self, from: bytes), result.version == 1,
                  (1...65_535).contains(result.sampleNumber),
                  result.nodeCounts.values.allSatisfy({ (0...512).contains($0) }),
                  (0...100).contains(result.progressPercentMinimum),
                  (result.progressPercentMinimum...100).contains(result.progressPercentMaximum) else { return nil }
            return result
        }

        private var nodeCounts: [String: Int] {
            ["baselineAttachmentNodes": baselineAttachmentNodes, "retainedBaselineAttachmentNodes": retainedBaselineAttachmentNodes,
             "matchedNodes": matchedNodes, "matchedOriginalFormNodes": matchedOriginalFormNodes, "newMatchedNodes": newMatchedNodes,
             "filenameMatchedNodes": filenameMatchedNodes, "blobMatchedNodes": blobMatchedNodes, "progressNodes": progressNodes,
             "busyAttributeNodes": busyAttributeNodes, "readyAttributeNodes": readyAttributeNodes, "errorAttributeNodes": errorAttributeNodes,
             "loadedImageNodes": loadedImageNodes, "changedMatchedPreviews": changedMatchedPreviews]
        }

        var traceFields: [String: Any] {
            var fields: [String: Any] = nodeCounts
            fields["version"] = version; fields["sampleNumber"] = sampleNumber
            fields["baselineAvailable"] = baselineAvailable; fields["beforeInputBaselineAvailable"] = beforeInputBaselineAvailable
            fields["originalDraftCurrent"] = originalDraftCurrent; fields["clickBound"] = clickBound
            fields["originalTextUnchanged"] = originalTextUnchanged; fields["selectionComparable"] = selectionComparable
            fields["originalSelectionUnchanged"] = originalSelectionUnchanged
            fields["progressValueKnown"] = progressValueKnown
            fields["progressPercentMinimum"] = progressPercentMinimum; fields["progressPercentMaximum"] = progressPercentMaximum
            fields["scanLimited"] = scanLimited; fields["samplingFailed"] = samplingFailed
            if let progressDecision { fields["progressDecision"] = progressDecision.rawValue }
            return Dictionary(uniqueKeysWithValues: fields.map { key, value in
                ("edge" + key.prefix(1).uppercased() + key.dropFirst(), value)
            })
        }
    }

    static func read(_ value: Any?) -> Self? {
        guard var object = value as? [String: Any], object.count <= 32,
              let bytes = try? JSONSerialization.data(withJSONObject: object), bytes.count <= 2_048,
              JSONSerialization.isValidJSONObject(object) else { return nil }
        // Invalid optional calibration drops only that sidecar; existing entry
        // diagnostics and the independently decoded observation remain usable.
        let calibration = object.removeValue(forKey: "edgeCalibration")
        guard let entryBytes = try? JSONSerialization.data(withJSONObject: object),
              var result = try? JSONDecoder().decode(Self.self, from: entryBytes), result.version == 1 else { return nil }
        result.edgeCalibration = EdgeCalibration.read(calibration)
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
        if let edgeCalibration { fields.merge(edgeCalibration.traceFields) { _, value in value } }
        return fields
    }
}
