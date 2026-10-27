import Foundation
import JavaScriptCore
import XCTest
@testable import RiftletAdapters

final class MainWorldCommandEnvelopeTests: XCTestCase {
    private func envelope() -> MainWorldCommandEnvelope {
        MainWorldCommandEnvelope(function: "function(){return {valid:true}}", commandJSON: "{}", contextJSON: "{}")
    }
    private func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    private func reject(_ raw: String, using envelope: MainWorldCommandEnvelope,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try envelope.decode(raw), file: file, line: line) {
            XCTAssertEqual($0 as? WebAdapterError, .invalidReply, file: file, line: line)
        }
    }

    func testMatchingNonceAndObjectReturnsOnlyResult() throws {
        let envelope = envelope()
        let raw = try json(["nonce": envelope.nonce, "ok": true, "result": ["valid": true, "count": 1]])
        let decoded = try envelope.decode(raw)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: Any])
        XCTAssertEqual(Set(result.keys), Set(["valid", "count"]))
        XCTAssertEqual(result["valid"] as? Bool, true); XCTAssertEqual(result["count"] as? Int, 1)
    }

    func testWrongNonceAndAnotherEnvelopeReplyAreRejected() throws {
        let expected = envelope(), other = envelope()
        XCTAssertNotEqual(expected.nonce, other.nonce)
        for nonce in ["", "wrong", other.nonce] {
            reject(try json(["nonce": nonce, "ok": true, "result": [:]]), using: expected)
        }
    }

    func testEmptyMissingMalformedAndScalarRepliesAreRejected() throws {
        let expected = envelope()
        for raw in ["", " ", "null", "undefined", "{}", "[]", "1", "true", "{not-json}"] {
            reject(raw, using: expected)
        }
        let scalarResults: [Any] = [NSNull(), "text", 1, true]
        for result in scalarResults {
            reject(try json(["nonce": expected.nonce, "ok": true, "result": result]), using: expected)
        }
        reject(try json(["nonce": expected.nonce, "ok": true]), using: expected)
    }

    func testErrorReplyAndUnexpectedFieldsAreRejected() throws {
        let expected = envelope()
        reject(try json(["nonce": expected.nonce, "ok": false]), using: expected)
        reject(try json(["nonce": expected.nonce, "ok": false, "result": [:]]), using: expected)
        reject(try json(["nonce": expected.nonce, "ok": true, "result": [:], "error": "unexpected"]), using: expected)
        reject(try json(["nonce": expected.nonce, "ok": "true", "result": [:]]), using: expected)
        reject(try json(["nonce": expected.nonce, "ok": 1, "result": [:]]), using: expected)
    }

    func testOversizedReplyRejectedByUTF8ByteCount() throws {
        let expected = envelope()
        let oversized = try json(["nonce": expected.nonce, "ok": true,
            "result": ["value": String(repeating: "界", count: 24_000)]])
        XCTAssertLessThan(oversized.count, ObservationDecoder.maximumPayloadBytes)
        XCTAssertGreaterThan(oversized.utf8.count, ObservationDecoder.maximumPayloadBytes)
        reject(oversized, using: expected)
    }

    func testReadingLostReplyNeverExecutesCommandAgain() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
            var executions = 0, attributes = {};
            var document = {documentElement:{
              setAttribute:function(k,v){attributes[k]=v},
              getAttribute:function(k){return attributes[k] || null},
              removeAttribute:function(k){delete attributes[k]}
            }};
            function setTimeout(callback,delay) {}
            """)
        let command = MainWorldCommandEnvelope(
            function: "function(){executions++; return {inputCount:executions}}", commandJSON: "{}", contextJSON: "{}")
        context.evaluateScript(command.source)
        XCTAssertNil(context.exception)
        let first = try XCTUnwrap(context.evaluateScript(command.reader)?.toString())
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(command.decode(first).utf8)) as? [String: Any])
        XCTAssertEqual(parsed["inputCount"] as? Int, 1)
        for _ in 0..<3 {
            let lost = try XCTUnwrap(context.evaluateScript(command.reader)?.toString())
            XCTAssertTrue(lost.isEmpty); reject(lost, using: command)
        }
        XCTAssertEqual(context.evaluateScript("executions")?.toInt32(), 1)
        XCTAssertNil(context.exception)
    }

    func testPageExceptionProducesOnlyCodeOwnedFailureAndCannotDecodeSuccess() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
            var attributes = {}, document = {documentElement:{
              setAttribute:function(k,v){attributes[k]=v},getAttribute:function(k){return attributes[k] || null},
              removeAttribute:function(k){delete attributes[k]}}};
            function setTimeout(callback,delay) {}
            """)
        let command = MainWorldCommandEnvelope(function: "function(){throw Error('private-page-detail')}", commandJSON: "{}", contextJSON: "{}")
        context.evaluateScript(command.source)
        let raw = try XCTUnwrap(context.evaluateScript(command.reader)?.toString())
        XCTAssertFalse(raw.contains("private-page-detail"))
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertEqual(Set(parsed.keys), Set(["nonce", "ok"]))
        XCTAssertEqual(parsed["ok"] as? Bool, false)
        reject(raw, using: command)
    }

    func testOnlyClosedCodeOwnedPageRejectionsAreDecoded() throws {
        let expected = envelope()
        let refused = try json(["nonce": expected.nonce, "ok": false, "rejection": "UNPROVEN_THREAD_IDENTITY"])
        XCTAssertThrowsError(try expected.decode(refused)) {
            XCTAssertEqual($0 as? WebAdapterError, .pageRejected(.unprovenThread))
        }
        for code in ["private-page-detail", "UNPROVEN_THREAD_IDENTITY\n", "", "TOP_SECRET"] {
            reject(try json(["nonce": expected.nonce, "ok": false, "rejection": code]), using: expected)
        }
        reject(try json(["nonce": "other", "ok": false, "rejection": "UNPROVEN_THREAD_IDENTITY"]), using: expected)
        reject(try json(["nonce": expected.nonce, "ok": false, "rejection": "UNPROVEN_THREAD_IDENTITY", "extra": "detail"]), using: expected)
    }
}
