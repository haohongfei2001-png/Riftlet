import Foundation
import XCTest
@testable import RiftletAdapters

final class BoundedDiagnosticTraceTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-trace-\(UUID())")
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func rows(_ name: String) throws -> [[String: Any]] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try data.split(separator: 10).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }

    func testLateRefusalSurvivesLifetimeLimitAndSubsequentRoutineTraffic() throws {
        let trace = BoundedDiagnosticTrace(enabled: true, directory: directory, emitStandardError: false)
        for index in 0..<6_000 { trace.record(["event": "capture_ack", "observedSequence": index]) }
        trace.record(["event": "input_resource_refused", "action": "prepareInputResource",
            "resourceRefusalReason": WebPageRejection.inputResourceNativeFilesRetained.rawValue], critical: true)
        for index in 0..<6_000 { trace.record(["event": "capture_ack", "observedSequence": index]) }
        trace.flushForTesting()
        let recent = try rows("acceptance-recent.jsonl"), failures = try rows("acceptance-failures.jsonl")
        XCTAssertEqual(recent.count, BoundedDiagnosticTrace.recentCapacity)
        XCTAssertEqual(recent.last?["observedSequence"] as? Int, 5_999)
        XCTAssertEqual(recent.last?["diagnosticSequence"] as? Int, 12_001)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0]["resourceRefusalReason"] as? String, "INPUT_RESOURCE_NATIVE_FILES_RETAINED")
        for (name, capacity) in [("acceptance-recent.jsonl", BoundedDiagnosticTrace.recentCapacity),
                                  ("acceptance-failures.jsonl", BoundedDiagnosticTrace.failureCapacity)] {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            XCTAssertLessThanOrEqual(data.count, capacity * BoundedDiagnosticTrace.maximumLineBytes)
        }
    }

    func testRestartPreservesCriticalWindowAndBoundsRepeatedFailures() throws {
        let original = BoundedDiagnosticTrace(enabled: true, directory: directory, emitStandardError: false)
        for index in 0..<100 {
            original.record(["event": "input_resource_refused", "observedSequence": index,
                "resourceRefusalReason": WebPageRejection.inputResourceExecutionBusy.rawValue], critical: true)
        }
        original.flushForTesting()
        let old = try rows("acceptance-failures.jsonl")
        XCTAssertEqual(old.count, BoundedDiagnosticTrace.failureCapacity)
        let resumed = BoundedDiagnosticTrace(enabled: true, directory: directory, emitStandardError: false)
        for _ in 0..<300 { resumed.record(["event": "capture_ack"]) }
        resumed.flushForTesting()
        let restored = try rows("acceptance-failures.jsonl")
        XCTAssertEqual(restored.count, old.count)
        XCTAssertEqual(restored.last?["observedSequence"] as? Int, 99)
        XCTAssertEqual(restored.last?["diagnosticSessionDigest"] as? String, old.last?["diagnosticSessionDigest"] as? String)
        let recent = try rows("acceptance-recent.jsonl")
        XCTAssertNotEqual(recent.last?["diagnosticSessionDigest"] as? String, old.last?["diagnosticSessionDigest"] as? String)
    }

    func testRawIdentityContentUnknownReasonAndErrorTextAreExcluded() throws {
        let trace = BoundedDiagnosticTrace(enabled: true, directory: directory, emitStandardError: false)
        let operationID = UUID().uuidString
        trace.record(["event": "input_resource_refused", "operationID": operationID,
            "attachmentID": "raw-private-attachment", "chatText": "private chat", "payload": "private bytes",
            "url": "https://chatgpt.com/private", "token": "private token", "error": "private page exception",
            "resourceRefusalReason": "INPUT_RESOURCE_UNAVAILABLE:private suffix"], critical: true)
        trace.flushForTesting()
        let data = try Data(contentsOf: directory.appendingPathComponent("acceptance-failures.jsonl"))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(operationID)); XCTAssertFalse(text.contains("private"))
        let row = try XCTUnwrap(rows("acceptance-failures.jsonl").first)
        XCTAssertEqual((row["operationIDDigest"] as? String)?.count, 64)
        XCTAssertNil(row["error"]); XCTAssertNil(row["resourceRefusalReason"])
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("acceptance-failures.jsonl").path)
        XCTAssertEqual((permissions[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testDisabledTraceCreatesNoFilesAndDiskFailureDoesNotEscape() throws {
        let disabled = BoundedDiagnosticTrace(enabled: false, directory: directory, emitStandardError: false)
        disabled.record(["event": "input_resource_refused"], critical: true); disabled.flushForTesting()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try Data("not a directory".utf8).write(to: directory)
        let unwritable = BoundedDiagnosticTrace(enabled: true, directory: directory, emitStandardError: false)
        unwritable.record(["event": "input_resource_refused"], critical: true); unwritable.flushForTesting()
        XCTAssertEqual(try Data(contentsOf: directory), Data("not a directory".utf8))
    }
}
