import JavaScriptCore
import RiftletCore
import XCTest
@testable import RiftletAdapters

final class ArchivedObservationCompatibilityTests: XCTestCase {
    // Independently computed from the signed build 56/57/58 app resources, the exact
    // sorted native context bytes, and JSONEncoder's optional-string suffix.
    private let edge = #"{"applicationID":"com.microsoft.edgemac","sessionID":"test-kernel-session","tabID":"34","windowID":"12"}"#
    private let chrome = #"{"applicationID":"com.google.Chrome","sessionID":"test-kernel-session","tabID":"34","windowID":"12"}"#

    func testArchivedMarkersMatchBothBrowsersAndOriginalLegacyEncoding() {
        XCTAssertEqual(ArchivedObservationCompatibility.markers(contextJSON: edge, legacyObservationSession: nil),
                       ["81f4b41dc0ed357dc640b073147db52c37b376b740c790fd13dc3489be1bf249",
                        "7eb2ca13fa0c23519ddb10dac060ad27fae4b309859dbaf8a66687acde6ad6af",
                        "b020534f878138e1b9ba759ade043f05d836437b8443787c95f6fef578aa8ffa"])
        XCTAssertEqual(ArchivedObservationCompatibility.markers(contextJSON: chrome, legacyObservationSession: "4321:1712345678.25"),
                       ["7ba0f13b6bffb6fc10ef42bd8d2c6717081e26c373561ed75a49a9530fc3429b",
                        "e9e5127837797a3f920c4c6de184c804ac8e2688be56a0615442426bdb141fae",
                        "15154215eec9605969039abbaadc4f4d59ed6a9f220571742e8572b814788ee2"])
        XCTAssertEqual(ArchivedObservationCompatibility.markers(contextJSON: chrome, legacyObservationSession: nil),
                       ["2945bc998ba2aec5a7e33eab4815e848bbd906dff7231408a6fe74981770b8c4",
                        "b3199573cf9928dd0d5403fce2d26a6e399d7e427f14e80143d59f172fc0836c",
                        "19bccd5bf649e51837a213785c23dd4014a748583bb7affaf08a732b37422662"])
    }

    func testCurrentProgramAndChangedAddressCannotMatchHistoricalRelay() throws {
        let original = try XCTUnwrap(ArchivedObservationCompatibility.markers(contextJSON: edge, legacyObservationSession: nil))
        let program = try ChatGPTWebPageProgram.load()
        XCTAssertFalse(original.contains(MainWorldCommandRelay(function: program.functionSource + "/* changed */", contextJSON: edge).marker))
        for (from, to) in [("test-kernel-session","another-process"), ("34","35"), ("12","13")] {
            let different = edge.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(original, try XCTUnwrap(ArchivedObservationCompatibility.markers(contextJSON: different,
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
        let current = String(repeating: "d", count: 64)
        let archived = try XCTUnwrap(ArchivedObservationCompatibility.markers(contextJSON: edge, legacyObservationSession: nil))
        let marker = archived[2]
        let reader = try XCTUnwrap(OriginalObservationChannel(context: edge, legacySession: nil, currentMarker: current, owner: owner))
        let channel = UUID().uuidString.lowercased(), nonce = UUID().uuidString.lowercased()
        let match = marker + ":" + channel
        let invoke = UUID()
        let polluted = WebBridgeCommand(action: .observe, target: original, identity: owner, uploadName: "unwanted.png",
                                        mediaType: "image/png", byteCount: 7, chunkIndex: 3, chunkBase64: "unwanted",
                                        invocationID: invoke, clickWitnessID: UUID(), requireLiveOriginal: nil, preferStartReceipt: true)
        let script = try reader.read(match: match, nonce: nonce, command: polluted)
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        let dispatched, count = 0, attributes = [];
        const own = {name:'data-riftlet-channel-\(channel)', value:'\(marker)'};
        const second = {name:'data-riftlet-channel-00000000-0000-0000-0000-000000000000',value:'\(archived[0])'};
        class Event { constructor(type) { this.type = type; } }
        const document = {documentElement: {
          get attributes() { return attributes; },
          getAttribute: name => attributes.find(a=>a.name===name)?.value ?? null,
          setAttribute(name, value) { if (name === 'data-riftlet-command') dispatched = JSON.parse(value); },
          dispatchEvent(event) { if (event.type === 'riftlet-command-\(channel)') count++; },
          removeAttribute() {}
        }};
        """)
        XCTAssertEqual(js.evaluateScript(reader.discovery)?.toString(), "")
        js.evaluateScript("attributes.push(own)")
        XCTAssertEqual(js.evaluateScript(reader.discovery)?.toString(), match)
        js.evaluateScript("attributes.push(second)")
        XCTAssertEqual(js.evaluateScript(reader.discovery)?.toString(), "ambiguous")
        js.evaluateScript(script)
        XCTAssertNotNil(js.exception)
        js.exception = nil
        XCTAssertEqual(js.evaluateScript("count")?.toInt32(), 0)
        js.evaluateScript("second.value='\(archived[1])'")
        XCTAssertEqual(js.evaluateScript(reader.discovery)?.toString(), "ambiguous")
        js.evaluateScript("second.value='\(current)'")
        XCTAssertEqual(js.evaluateScript(reader.discovery)?.toString(), "ambiguous")
        js.evaluateScript("second.value='\(marker)'")
        XCTAssertEqual(js.evaluateScript(reader.discovery)?.toString(), "ambiguous")
        js.evaluateScript("attributes.pop()")
        XCTAssertEqual(js.evaluateScript(script)?.toString(), "submitted")
        XCTAssertNil(js.exception)
        XCTAssertEqual(js.evaluateScript("count")?.toInt32(), 1)
        let raw = try XCTUnwrap(js.evaluateScript("JSON.stringify(dispatched)")?.toString())
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertEqual(wire["nonce"] as? String, nonce)
        let command = try XCTUnwrap(wire["command"] as? [String: Any])
        XCTAssertEqual(Set(command.keys), ["action", "target", "identity", "invocationID", "requireLiveOriginal", "preferStartReceipt"])
        XCTAssertEqual(command["action"] as? String, "observe")
        XCTAssertEqual(command["requireLiveOriginal"] as? Bool, true)
        XCTAssertThrowsError(try reader.read(match: match, nonce: nonce,
            command: WebBridgeCommand(action: .observe, target: original, identity: owner)))
        XCTAssertEqual(command["invocationID"] as? String, invoke.uuidString)
        let encoded = try JSONSerialization.data(withJSONObject: XCTUnwrap(command["identity"]))
        XCTAssertEqual(try JSONDecoder().decode(ObservationIdentity.self, from: encoded), owner)

        for action in WebBridgeAction.allCases where action != .observe {
            XCTAssertThrowsError(try reader.read(match: match, nonce: nonce,
                                                 command: WebBridgeCommand(action: action, target: original, identity: owner)))
        }
        let otherTarget = target(tab: "35")
        for request in [
            WebBridgeCommand(action: .observe, target: otherTarget, identity: owner),
            WebBridgeCommand(action: .observe, target: otherTarget, identity: identity(for: otherTarget)),
            WebBridgeCommand(action: .observe, target: original, identity: identity(for: original)),
            WebBridgeCommand(action: .observe, target: original)
        ] {
            XCTAssertThrowsError(try reader.read(match: match, nonce: nonce, command: request))
        }
        for invalid in ["", "ambiguous", "not-an-id", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"] {
            XCTAssertThrowsError(try reader.read(match: marker + ":" + invalid, nonce: nonce, command: polluted))
            XCTAssertThrowsError(try reader.read(match: match, nonce: invalid, command: polluted))
        }
    }

}
