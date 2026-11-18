import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class EdgeCalibrationDiagnosticsTests: XCTestCase {
    private var calibration: [String: Any] {
        ["version": 1, "sampleNumber": 2, "baselineAvailable": true, "beforeInputBaselineAvailable": true,
         "originalDraftCurrent": true, "clickBound": true, "originalTextUnchanged": true,
         "selectionComparable": true, "originalSelectionUnchanged": true,
         "baselineAttachmentNodes": 2, "retainedBaselineAttachmentNodes": 2,
         "matchedNodes": 2, "matchedOriginalFormNodes": 2, "newMatchedNodes": 2, "filenameMatchedNodes": 2,
         "blobMatchedNodes": 0, "progressNodes": 1, "progressValueKnown": true,
         "progressPercentMinimum": 100, "progressPercentMaximum": 100, "busyAttributeNodes": 0,
         "readyAttributeNodes": 1, "errorAttributeNodes": 0, "loadedImageNodes": 1, "changedMatchedPreviews": 2,
         "scanLimited": false, "samplingFailed": false]
    }

    private func summary(_ calibration: Any? = nil) -> [String: Any] {
        var result: [String: Any] = ["version": 1, "entryCandidates": 1, "entryActivations": 0,
            "openedContainers": 0, "menuActivations": 0, "pickerClicks": 0, "pickerShows": 0,
            "inputSeen": true, "inputConnected": true, "setterEntered": true, "changeReturned": true,
            "stage": "observation", "cause": "none", "exceptionType": "none"]
        if let calibration { result["edgeCalibration"] = calibration }
        return result
    }

    private func packet() -> AttachmentObservationEnvelope {
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.microsoft.edgemac", sessionID: "fixture-edge-session",
            windowID: "17", tabID: "19", documentID: "fixture-document", composerID: "fixture-composer",
            draftGeneration: "fixture-generation", clickBindingID: UUID())
        let identity = ObservationIdentity(operationID: UUID(), assetID: UUID(), attempt: 1,
            assetSHA256: String(repeating: "0", count: 64), target: target)
        return AttachmentObservationEnvelope(schemaVersion: 2,
            provenance: .init(source: .syntheticFixture, evidenceID: "edge-calibration-fixture"),
            observation: .init(identity: identity, state: .inputTriggered, belongsToOriginalDraft: true))
    }

    private func payload(_ packet: AttachmentObservationEnvelope, _ sidecar: Any) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(packet)) as? [String: Any])
        object["entryDiagnostics"] = sidecar
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testProgressDecisionAcceptsOnlyClosedLabelsAndNeverSuppliesAReceipt() throws {
        let original = packet()
        for name in ["fileBlobMissing", "ownershipTopology", "conflictingFileLabel", "retainedBaseline", "selectionChanged", "nodeReused", "progressUnavailable", "started", "previewEncoding", "previewMismatch", "previewUnavailable", "encodedPreviewWithoutProgress", "untrusted data"] {
            var fields = calibration; fields["progressDecision"] = name
            let data = try payload(original, summary(fields))
            let decoded = try ObservationDecoder.decodeResponse(data, includeDiagnostics: true)
            XCTAssertEqual(decoded.envelope, original)
            XCTAssertEqual(decoded.diagnostics?.traceFields["edgeProgressDecision"] as? String, name == "untrusted data" ? nil : name)
        }
    }

    func testCompleteLookingCalibrationCannotChangeObservationOrGrantEvidence() throws {
        let original = packet(), data = try payload(original, summary(calibration))
        let response = try ObservationDecoder.decodeResponse(data, includeDiagnostics: true)
        XCTAssertEqual(response.envelope, original)
        XCTAssertEqual(response.envelope.observation.state, .inputTriggered)
        XCTAssertNil(response.envelope.observation.uploadStart)
        XCTAssertNil(response.envelope.observation.completionEvidence)
        XCTAssertFalse(response.envelope.observation.exactImageIdentity)
        XCTAssertFalse(response.envelope.observation.automaticRetryExcluded)
        XCTAssertEqual(response.diagnostics?.edgeCalibration?.readyAttributeNodes, 1)
        XCTAssertEqual(response.diagnostics?.edgeCalibration?.progressPercentMaximum, 100)
        XCTAssertNil(try ObservationDecoder.decodeResponse(data, includeDiagnostics: false).diagnostics)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(response.envelope), as: UTF8.self).contains("edgeCalibration"))
    }

    func testMalformedOptionalCalibrationPreservesExistingEntryDiagnostics() throws {
        let original = packet()
        for malformed: Any in [NSNull(), "private text", ["version": 1], 1] {
            let response = try ObservationDecoder.decodeResponse(payload(original, summary(malformed)), includeDiagnostics: true)
            XCTAssertEqual(response.envelope, original)
            XCTAssertEqual(response.diagnostics?.stage, .observation)
            XCTAssertEqual(response.diagnostics?.setterEntered, true)
            XCTAssertNil(response.diagnostics?.edgeCalibration)
        }
        let legacy = try XCTUnwrap(AttachmentEntryDiagnostics.read(summary()))
        XCTAssertNil(legacy.edgeCalibration)
        XCTAssertFalse(legacy.traceFields.keys.contains { $0.hasPrefix("edge") })
    }

    func testStrictShapeAndRangeExcludeUnboundedOrPrivateSidecars() throws {
        var variants = [[String: Any]]()
        for (key, value): (String, Any) in [("sampleNumber", 0), ("sampleNumber", 65_536),
            ("matchedNodes", -1), ("matchedNodes", 513), ("progressPercentMaximum", 101),
            ("progressPercentMinimum", -1), ("originalTextUnchanged", "private text"),
            ("version", 2), ("privateDraftText", "private-content"), ("uploadStart", true)] {
            var changed = calibration; changed[key] = value; variants.append(changed)
        }
        var missing = calibration; missing.removeValue(forKey: "clickBound"); variants.append(missing)
        var reversed = calibration; reversed["progressPercentMaximum"] = 40; variants.append(reversed)
        for value in variants {
            let read = try XCTUnwrap(AttachmentEntryDiagnostics.read(summary(value)))
            XCTAssertNil(read.edgeCalibration)
            XCTAssertEqual(read.stage, .observation)
            XCTAssertFalse(String(describing: read.traceFields).contains("private-content"))
        }
        var maximum = calibration; maximum["matchedNodes"] = 512; maximum["sampleNumber"] = 65_535
        XCTAssertEqual(AttachmentEntryDiagnostics.read(summary(maximum))?.edgeCalibration?.sampleNumber, 65_535)
    }

    func testTracePublishesOnlyNamespacedCalibrationNumbersAndBooleans() throws {
        let decoded = try XCTUnwrap(AttachmentEntryDiagnostics.read(summary(calibration)))
        let safe = try XCTUnwrap(decoded.edgeCalibration).traceFields
        XCTAssertTrue(safe.keys.allSatisfy { $0.hasPrefix("edge") && $0.utf8.count <= 64 })
        XCTAssertTrue(safe.values.allSatisfy { $0 is NSNumber })
        XCTAssertNil(safe["state"]); XCTAssertNil(safe["uploadStart"]); XCTAssertNil(safe["completionEvidence"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-edge-calibration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = BoundedDiagnosticTrace(enabled: true, directory: directory, emitStandardError: false)
        var fields = decoded.traceFields
        fields["event"] = "attachment_entry_result"; fields["phase"] = "inputTriggered"
        fields["startObserved"] = false
        trace.record(fields); trace.flushForTesting()
        let line = try XCTUnwrap(Data(contentsOf: directory.appendingPathComponent("acceptance-recent.jsonl"))
            .split(separator: 10).last)
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        XCTAssertEqual(row["edgeReadyAttributeNodes"] as? Int, 1)
        XCTAssertEqual(row["edgeOriginalSelectionUnchanged"] as? Bool, true)
        XCTAssertEqual(row["startObserved"] as? Bool, false)
        XCTAssertEqual(row["phase"] as? String, "inputTriggered")
        XCTAssertNil(row["completionEvidence"])
    }

    func testOversizedSidecarDoesNotInvalidateTheOriginalObservation() throws {
        let original = packet()
        var oversized = calibration; oversized["privateDraftText"] = String(repeating: "secret", count: 500)
        let response = try ObservationDecoder.decodeResponse(payload(original, summary(oversized)), includeDiagnostics: true)
        XCTAssertEqual(response.envelope, original)
        XCTAssertNil(response.diagnostics)
    }
}
