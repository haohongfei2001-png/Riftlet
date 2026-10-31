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
            var executions = 0, attributes = {}, expireReceipt, receiptTTL;
            var document = {documentElement:{
              setAttribute:function(k,v){attributes[k]=v},
              getAttribute:function(k){return attributes[k] || null},
              removeAttribute:function(k){delete attributes[k]}
            }};
            function setTimeout(callback,delay) { expireReceipt=callback; receiptTTL=delay; }
            """)
        let command = MainWorldCommandEnvelope(
            function: "function(){executions++; return {inputCount:executions}}", commandJSON: "{}", contextJSON: "{}")
        context.evaluateScript(command.source)
        XCTAssertNil(context.exception)
        var now: TimeInterval = 10, reads = 0, lost = ""
        let recovered = try MainWorldReceiptReader.read(command, clock: { now }, sleep: { now += $0 }) { budget in
            reads += 1
            let raw = try XCTUnwrap(context.evaluateScript(command.reader)?.toString())
            if reads == 1 {
                // Chrome executed the reader, but the host never received its
                // reply. Only another read, not another MAIN submission, follows.
                lost = raw; now += try budget.timeout(at: now)
                throw WebAdapterError.nativeEventFailed(-1712)
            }
            XCTAssertEqual(raw, lost)
            return raw
        }
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(recovered.text.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["inputCount"] as? Int, 1)
        XCTAssertEqual(reads, 2); XCTAssertFalse(lost.isEmpty)
        for _ in 0..<3 {
            let repeated = try XCTUnwrap(context.evaluateScript(command.reader)?.toString())
            XCTAssertEqual(repeated, lost)
            XCTAssertEqual(try command.decode(repeated), recovered.text)
        }
        XCTAssertEqual(context.evaluateScript("receiptTTL")?.toInt32(), 10_000)
        context.evaluateScript("expireReceipt()")
        let expired = try XCTUnwrap(context.evaluateScript(command.reader)?.toString())
        XCTAssertTrue(expired.isEmpty); reject(expired, using: command)
        XCTAssertEqual(context.evaluateScript("executions")?.toInt32(), 1)
        XCTAssertNil(context.exception)
    }

    func testReceiptExpiryIsScopedToItsNonceWithoutConsumingAnotherReceipt() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
            var attributes={}, timers=[], executions=0, document={documentElement:{
              setAttribute:function(k,v){attributes[k]=v},getAttribute:function(k){return attributes[k] || null},
              removeAttribute:function(k){delete attributes[k]}}};
            function setTimeout(callback,delay) { timers.push({callback:callback,delay:delay}); }
            """)
        let function = "function(){executions++; return {count:executions}}"
        let first = MainWorldCommandEnvelope(function: function, commandJSON: "{}", contextJSON: "{}")
        let second = MainWorldCommandEnvelope(function: function, commandJSON: "{}", contextJSON: "{}")
        context.evaluateScript(first.source); context.evaluateScript(second.source)
        let firstRaw = try XCTUnwrap(context.evaluateScript(first.reader)?.toString())
        let secondRaw = try XCTUnwrap(context.evaluateScript(second.reader)?.toString())
        XCTAssertNotEqual(firstRaw, secondRaw)
        reject(firstRaw, using: second); reject(secondRaw, using: first)
        context.evaluateScript("timers[0].callback()")
        XCTAssertEqual(context.evaluateScript(first.reader)?.toString(), "")
        XCTAssertEqual(context.evaluateScript(second.reader)?.toString(), secondRaw)
        XCTAssertEqual(context.evaluateScript("timers[0].delay")?.toInt32(), 10_000)
        XCTAssertEqual(context.evaluateScript("timers[1].delay")?.toInt32(), 10_000)
        XCTAssertEqual(context.evaluateScript("executions")?.toInt32(), 2)
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
        for code in WebPageRejection.allCases {
            let refused = try json(["nonce": expected.nonce, "ok": false, "rejection": code.rawValue])
            XCTAssertThrowsError(try expected.decode(refused)) {
                XCTAssertEqual($0 as? WebAdapterError, .pageRejected(code))
            }
        }
        for code in ["private-page-detail", "UNPROVEN_THREAD_IDENTITY\n", "", "TOP_SECRET"] {
            reject(try json(["nonce": expected.nonce, "ok": false, "rejection": code]), using: expected)
        }
        reject(try json(["nonce": "other", "ok": false, "rejection": "UNPROVEN_THREAD_IDENTITY"]), using: expected)
        reject(try json(["nonce": expected.nonce, "ok": false, "rejection": "UNPROVEN_THREAD_IDENTITY", "extra": "detail"]), using: expected)
    }

    func testRootBindingRejectionsCrossEnvelopeOnlyAsExactFailureCodes() throws {
        for code in [WebPageRejection.unobservedRootDescriptor, .unprovenMonitoredBinding] {
            let context = try XCTUnwrap(JSContext())
            context.evaluateScript("""
                var attributes = {}, executions = 0, document = {documentElement:{
                  setAttribute:function(k,v){attributes[k]=v},getAttribute:function(k){return attributes[k] || null},
                  removeAttribute:function(k){delete attributes[k]}}};
                function setTimeout(callback,delay) {}
                """)
            let command = MainWorldCommandEnvelope(
                function: "function(){executions++; throw Error('\(code.rawValue)')}",
                commandJSON: "{}", contextJSON: "{}")
            context.evaluateScript(command.source)
            XCTAssertNil(context.exception)
            let raw = try XCTUnwrap(context.evaluateScript(command.reader)?.toString())
            let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            XCTAssertEqual(Set(parsed.keys), Set(["nonce", "ok", "rejection"]))
            XCTAssertEqual(parsed["ok"] as? Bool, false)
            XCTAssertThrowsError(try command.decode(raw)) {
                XCTAssertEqual($0 as? WebAdapterError, .pageRejected(code))
            }
            XCTAssertEqual(context.evaluateScript(command.reader)?.toString(), raw)
            XCTAssertEqual(context.evaluateScript("executions")?.toInt32(), 1)
            for altered in [code.rawValue + "\n", code.rawValue + ":private-detail", code.rawValue.lowercased()] {
                reject(try json(["nonce": command.nonce, "ok": false, "rejection": altered]), using: command)
            }
            reject(try json(["nonce": command.nonce, "ok": false, "rejection": code.rawValue,
                             "detail": "private-detail"]), using: command)
        }
    }
}
