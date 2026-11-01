import XCTest
import JavaScriptCore
@testable import RiftletAdapters

final class MainWorldCommandRelayTests: XCTestCase {
    private func context() throws -> JSContext {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        var executions=0,timers=[],lastSession=null;
        class TextEncoder{encode(s){return Array.from(unescape(encodeURIComponent(s)));}}
        class Event{constructor(type){this.type=type;}}
        function makeRoot(){return {values:{},listeners:{},get attributes(){return Object.entries(this.values).map(([name,value])=>({name,value}))},
          hasAttribute(k){return Object.prototype.hasOwnProperty.call(this.values,k)},
          getAttribute(k){return this.values[k]??null},setAttribute(k,v){this.values[k]=v},
          removeAttribute(k){delete this.values[k]},
          addEventListener(k,f){(this.listeners[k]??=[]).push(f)},
          dispatchEvent(e){e.target=this;for(const f of this.listeners[e.type]??[])f(e)}};}
        var document={documentElement:makeRoot()};
        function setTimeout(f){timers.push(f)}
        """)
        XCTAssertNil(js.exception)
        return js
    }
    private let function = "function(command,native){executions++;lastSession=native.sessionID;return {count:executions,session:native.sessionID}}"
    private let native = "{\"applicationID\":\"com.google.Chrome\",\"sessionID\":\"current\",\"windowID\":\"A\",\"tabID\":\"1\"}"
    private func envelope(_ command: String = "{\"action\":\"observe\"}") -> MainWorldCommandEnvelope {
        MainWorldCommandEnvelope(function: function, commandJSON: command, contextJSON: native)
    }
    func testOnlyInstalledClosureRunsAndLifetimeNonceCannotReplayAfterReceiptExpiry() throws {
        let js = try context(), relay = MainWorldCommandRelay(function: function, contextJSON: native), e = envelope()
        js.evaluateScript(relay.dispatch(e)); XCTAssertNotNil(js.exception); js.exception = nil
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 0)
        js.evaluateScript(relay.installer); XCTAssertNil(js.exception)
        XCTAssertEqual(js.evaluateScript(relay.probe)?.toString(), "ready")
        js.evaluateScript(relay.dispatch(e)); js.evaluateScript(relay.dispatch(e))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
        _ = try e.decode(try XCTUnwrap(js.evaluateScript(e.reader)?.toString()))
        js.evaluateScript("timers.forEach(f=>f())")
        js.evaluateScript(relay.dispatch(e))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
        XCTAssertEqual(js.evaluateScript(e.reader)?.toString(), "")
        XCTAssertEqual(js.evaluateScript("document.documentElement.getAttribute('data-riftlet-command')")?.isNull, true)
    }
    func testNewDocumentAndForeignChannelNeverTriggerFallbackInstallation() throws {
        let js = try context(), relay = MainWorldCommandRelay(function: function, contextJSON: native), e = envelope()
        js.evaluateScript(relay.installer)
        let other = MainWorldCommandRelay(function: function, contextJSON: native)
        js.evaluateScript(other.dispatch(e)); XCTAssertNotNil(js.exception); js.exception = nil
        js.evaluateScript("document.documentElement=makeRoot()")
        js.evaluateScript(relay.dispatch(e)); XCTAssertNotNil(js.exception)
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 0)
    }
    func testRequestCannotChangeNativeContextOrExecuteSuppliedCodeAndSizeIsBounded() throws {
        let js = try context(), relay = MainWorldCommandRelay(function: function, contextJSON: native)
        js.evaluateScript(relay.installer)
        let e = envelope("{\"action\":\"observe\",\"source\":\"executions=999\",\"native\":{\"sessionID\":\"B\"}}")
        js.evaluateScript(relay.dispatch(e))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
        XCTAssertEqual(js.evaluateScript("lastSession")?.toString(), "current")
        let large = envelope("{\"action\":\"chunk\",\"chunkBase64\":\"" + String(repeating: "x", count: 524289) + "\"}")
        js.evaluateScript(relay.dispatch(large))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
        XCTAssertEqual(js.evaluateScript(large.reader)?.toString(), "")
        js.evaluateScript(relay.dispatch(envelope("{\"action\":\"arbitrary\"}")))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
    }
    func testLegacySessionAliasIsFixedAtInstallAndReadOnly() throws {
        let js = try context(), relay = MainWorldCommandRelay(function: function, contextJSON: native, legacyObservationSession: "legacy")
        js.evaluateScript(relay.installer)
        js.evaluateScript(relay.dispatch(envelope("{\"action\":\"observe\",\"target\":{\"sessionID\":\"legacy\"}}")))
        XCTAssertEqual(js.evaluateScript("lastSession")?.toString(), "legacy")
        for action in ["begin", "commit", "pinTarget"] {
            js.evaluateScript(relay.dispatch(envelope("{\"action\":\"\(action)\",\"target\":{\"sessionID\":\"legacy\"}}")))
            XCTAssertEqual(js.evaluateScript("lastSession")?.toString(), "current")
        }
        js.evaluateScript(relay.dispatch(envelope("{\"action\":\"observe\",\"target\":{\"sessionID\":\"forged\"}}")))
        XCTAssertEqual(js.evaluateScript("lastSession")?.toString(), "current")
    }
    func testRelayStoreNeverCreatesOrUpgradesFromBackgroundRequest() throws {
        let store = MainWorldRelayStore()
        XCTAssertNil(store.relay(function: function, contextJSON: native, allowCreate: false))
        let first = try XCTUnwrap(store.relay(function: function, contextJSON: native, allowCreate: true))
        let background = try XCTUnwrap(store.relay(function: function, contextJSON: native, allowCreate: false, legacyObservationSession: "legacy"))
        XCTAssertEqual(background.channel, first.channel)
        let upgraded = try XCTUnwrap(store.relay(function: function, contextJSON: native, allowCreate: true, legacyObservationSession: "legacy"))
        XCTAssertNotEqual(upgraded.channel, first.channel)
        XCTAssertNil(store.relay(function: function + " ", contextJSON: native, allowCreate: false))
    }
    func testRestartDiscoversOnlyOneExactExistingChannelWithoutInstallingOrInput() throws {
        let js = try context(), relay = MainWorldCommandRelay(function: function, contextJSON: native), e = envelope()
        js.evaluateScript(relay.installer)
        let next = MainWorldCommandRelay(function: function, contextJSON: native)
        let channel = try XCTUnwrap(js.evaluateScript(next.discovery)?.toString())
        XCTAssertEqual(channel, relay.channel)
        let freshStore = MainWorldRelayStore()
        let adopted = try XCTUnwrap(freshStore.adopt(function: function, contextJSON: native, channel: channel, legacyObservationSession: nil))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 0)
        js.evaluateScript(adopted.dispatch(e))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
        XCTAssertNil(freshStore.adopt(function: function, contextJSON: native, channel: "ambiguous", legacyObservationSession: nil))
        js.evaluateScript(next.installer) // Same code/context but second random channel: refuse ambiguity.
        XCTAssertEqual(js.evaluateScript(next.discovery)?.toString(), "ambiguous")
        let changed = MainWorldCommandRelay(function: function + " ", contextJSON: native)
        XCTAssertEqual(js.evaluateScript(changed.discovery)?.toString(), "")
        js.evaluateScript("document.documentElement=makeRoot()")
        XCTAssertEqual(js.evaluateScript(next.discovery)?.toString(), "")
    }
    func testNonceIsConsumedBeforeReentrantEvent() throws {
        let js = try context(), id = UUID().uuidString.lowercased()
        let reentrant = "function(){executions++;document.documentElement.setAttribute('data-riftlet-command',nested);document.documentElement.dispatchEvent(new Event('riftlet-command-" + id + "'));return {count:executions}}"
        let relay = MainWorldCommandRelay(function: reentrant, contextJSON: native, channel: id), e = envelope()
        js.evaluateScript(relay.installer)
        js.evaluateScript("var nested=JSON.stringify({nonce:'" + e.nonce + "',command:{action:'observe'}})")
        js.evaluateScript(relay.dispatch(e))
        XCTAssertNil(js.exception)
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
    }

}
