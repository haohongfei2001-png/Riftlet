import JavaScriptCore
import RiftletCore
import XCTest
@testable import RiftletAdapters

final class Build56ObservationCompatibilityTests: XCTestCase {
    // Independently computed from the signed build 56 app resource, the exact
    // sorted native context bytes, and JSONEncoder's optional-string suffix.
    private let edge = #"{"applicationID":"com.microsoft.edgemac","sessionID":"test-kernel-session","tabID":"34","windowID":"12"}"#
    private let chrome = #"{"applicationID":"com.google.Chrome","sessionID":"test-kernel-session","tabID":"34","windowID":"12"}"#

    func testArchivedMarkersMatchBothBrowsersAndOriginalLegacyEncoding() {
        XCTAssertEqual(Build56ObservationCompatibility.marker(contextJSON: edge, legacyObservationSession: nil),
                       "81f4b41dc0ed357dc640b073147db52c37b376b740c790fd13dc3489be1bf249")
        XCTAssertEqual(Build56ObservationCompatibility.marker(contextJSON: chrome, legacyObservationSession: "4321:1712345678.25"),
                       "7ba0f13b6bffb6fc10ef42bd8d2c6717081e26c373561ed75a49a9530fc3429b")
        XCTAssertEqual(Build56ObservationCompatibility.marker(contextJSON: chrome, legacyObservationSession: nil),
                       "2945bc998ba2aec5a7e33eab4815e848bbd906dff7231408a6fe74981770b8c4")
    }

    func testCurrentProgramAndChangedAddressCannotMatchHistoricalRelay() throws {
        let original = try XCTUnwrap(Build56ObservationCompatibility.marker(contextJSON: edge, legacyObservationSession: nil))
        let program = try ChatGPTWebPageProgram.load()
        XCTAssertNotEqual(original, MainWorldCommandRelay(function: program.functionSource, contextJSON: edge).marker)
        for (from, to) in [("test-kernel-session","another-process"), ("34","35"), ("12","13")] {
            let different = edge.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(original, try XCTUnwrap(Build56ObservationCompatibility.marker(contextJSON: different,
                                                                                           legacyObservationSession: nil)))
        }
    }
    private func target(tab: String = "34") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.microsoft.edgemac",
                    sessionID: "test-kernel-session", windowID: "12", tabID: tab,
                    documentID: "qa-document", composerID: "qa-composer", draftGeneration: "qa-generation")
    }

    private func identity(for target: TargetLease) -> ObservationIdentity {
        ObservationIdentity(operationID: UUID(), assetID: UUID(), attempt: 1,
                            assetSHA256: String(repeating: "a", count: 64), target: target)
    }

    func testOnlyOriginalObservationCanDispatchOnCanonicalChannelAndNonce() throws {
        let original = target(), owner = identity(for: original)
        let reader = try XCTUnwrap(Build56ObservationChannel(context: edge, legacySession: nil, owner: owner))
        let channel = UUID().uuidString.lowercased(), nonce = UUID().uuidString.lowercased()
        let invoke = UUID()
        let polluted = WebBridgeCommand(action: .observe, target: original, identity: owner, uploadName: "unwanted.png",
                                        mediaType: "image/png", byteCount: 7, chunkIndex: 3, chunkBase64: "unwanted",
                                        invocationID: invoke, clickWitnessID: UUID(), requireLiveOriginal: true, preferStartReceipt: true)
        let script = try reader.read(channel: channel, nonce: nonce, command: polluted)
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        let dispatched, count = 0;
        class Event { constructor(type) { this.type = type; } }
        const document = {documentElement: {
          getAttribute: name => name === 'data-riftlet-channel-\(channel)' ? '\(reader.marker)' : null,
          setAttribute(name, value) { if (name === 'data-riftlet-command') dispatched = JSON.parse(value); },
          dispatchEvent(event) { if (event.type === 'riftlet-command-\(channel)') count++; },
          removeAttribute() {}
        }};
        """)
        XCTAssertEqual(js.evaluateScript(script)?.toString(), "submitted")
        XCTAssertNil(js.exception)
        XCTAssertEqual(js.evaluateScript("count")?.toInt32(), 1)
        let raw = try XCTUnwrap(js.evaluateScript("JSON.stringify(dispatched)")?.toString())
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertEqual(wire["nonce"] as? String, nonce)
        let command = try XCTUnwrap(wire["command"] as? [String: Any])
        XCTAssertEqual(Set(command.keys), ["action", "target", "identity", "invocationID", "requireLiveOriginal", "preferStartReceipt"])
        XCTAssertEqual(command["action"] as? String, "observe")
        XCTAssertEqual(command["invocationID"] as? String, invoke.uuidString)
        let encoded = try JSONSerialization.data(withJSONObject: XCTUnwrap(command["identity"]))
        XCTAssertEqual(try JSONDecoder().decode(ObservationIdentity.self, from: encoded), owner)

        for action in WebBridgeAction.allCases where action != .observe {
            XCTAssertThrowsError(try reader.read(channel: channel, nonce: nonce,
                                                 command: WebBridgeCommand(action: action, target: original, identity: owner)))
        }
        let otherTarget = target(tab: "35")
        for request in [
            WebBridgeCommand(action: .observe, target: otherTarget, identity: owner),
            WebBridgeCommand(action: .observe, target: otherTarget, identity: identity(for: otherTarget)),
            WebBridgeCommand(action: .observe, target: original, identity: identity(for: original)),
            WebBridgeCommand(action: .observe, target: original)
        ] {
            XCTAssertThrowsError(try reader.read(channel: channel, nonce: nonce, command: request))
        }
        for invalid in ["", "ambiguous", "not-an-id", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"] {
            XCTAssertThrowsError(try reader.read(channel: invalid, nonce: nonce, command: polluted))
            XCTAssertThrowsError(try reader.read(channel: channel, nonce: invalid, command: polluted))
        }
    }

}
