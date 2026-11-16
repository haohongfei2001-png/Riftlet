import XCTest
import JavaScriptCore
import CryptoKit
import RiftletCore
@testable import RiftletAdapters

final class MainWorldCommandRelayTests: XCTestCase {
    private func context(virtualMachine: JSVirtualMachine? = nil) throws -> JSContext {
        let machine = try XCTUnwrap(virtualMachine ?? JSVirtualMachine())
        let js = try XCTUnwrap(JSContext(virtualMachine: machine))
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
    func testColdBootstrapOwnsApplicationPrototypeAndLaterIsolatedDispatchKeepsThatMainClosure() throws {
        // Two actual JavaScriptCore realms with one shared DOM model. This
        // verifies closure/prototype ownership, not native Chrome focus behavior.
        let vm = try XCTUnwrap(JSVirtualMachine())
        let main = try context(virtualMachine: vm), isolated = try context(virtualMachine: vm)
        main.evaluateScript("""
            var realm='MAIN',handoffs=0,nativePickerCalls=0;
            class HTMLInputElement{click(){nativePickerCalls++}}
            function activateApplicationPicker(){new HTMLInputElement().click()}
            """)
        isolated.evaluateScript("var realm='ISOLATED',handoffs=0;class HTMLInputElement{click(){}}")
        isolated.setObject(main.objectForKeyedSubscript("document"), forKeyedSubscript: "document" as NSString)
        isolated.setObject(main.objectForKeyedSubscript("activateApplicationPicker"),
            forKeyedSubscript: "activateApplicationPicker" as NSString)
        let hook = """
            function(){const original=HTMLInputElement.prototype.click;
              HTMLInputElement.prototype.click=function(){handoffs++};
              try{activateApplicationPicker();return {realm,handoffs}}
              finally{HTMLInputElement.prototype.click=original}}
            """
        let relay = MainWorldCommandRelay(function: hook, contextJSON: native)
        var bootstraps = 0, dispatches = 0
        for install in [true, false] {
            let command = MainWorldCommandEnvelope(function: hook, commandJSON: "{\"action\":\"commit\"}", contextJSON: native)
            try ChromeMainWorldSubmission.submit(relay: relay, envelope: command, install: install,
                bootstrap: { bootstraps += 1; main.evaluateScript($0) },
                dispatch: { dispatches += 1; isolated.evaluateScript($0) })
            XCTAssertNil(main.exception); XCTAssertNil(isolated.exception)
            let raw = try XCTUnwrap(isolated.evaluateScript(command.reader)?.toString())
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(command.decode(raw).utf8)) as? [String: Any])
            XCTAssertEqual(result["realm"] as? String, "MAIN")
            XCTAssertEqual(result["handoffs"] as? Int, install ? 1 : 2)
            XCTAssertEqual(main.evaluateScript("nativePickerCalls")?.toInt32(), 0)
        }
        XCTAssertEqual(bootstraps, 1); XCTAssertEqual(dispatches, 1)
        XCTAssertEqual(isolated.evaluateScript("handoffs")?.toInt32(), 0)
    }

    func testBootstrapFailureNeverFallsBackToIsolatedInstallationOrRepeatsSubmission() throws {
        let js = try context(), relay = MainWorldCommandRelay(function: function, contextJSON: native), command = envelope()
        var bootstraps = 0, dispatches = 0
        XCTAssertThrowsError(try ChromeMainWorldSubmission.submit(relay: relay, envelope: command, install: true,
            bootstrap: { source in
                bootstraps += 1
                js.evaluateScript(source) // MAIN ran, but its native submission reply was lost.
                throw WebAdapterError.nativeEventFailed(-1712)
            }, dispatch: { _ in dispatches += 1 })) {
                XCTAssertEqual($0 as? WebAdapterError, .nativeEventFailed(-1712))
            }
        for _ in 0..<3 {
            _ = try command.decode(try XCTUnwrap(js.evaluateScript(command.reader)?.toString()))
        }
        XCTAssertEqual(bootstraps, 1); XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
    }

    func testMissingWarmRelayDoesNotReinstallOrInput() throws {
        let js = try context(), relay = MainWorldCommandRelay(function: function, contextJSON: native), command = envelope()
        var bootstraps = 0, dispatches = 0
        try ChromeMainWorldSubmission.submit(relay: relay, envelope: command, install: false,
            bootstrap: { _ in bootstraps += 1 }, dispatch: { dispatches += 1; js.evaluateScript($0) })
        XCTAssertNotNil(js.exception)
        XCTAssertEqual(bootstraps, 0); XCTAssertEqual(dispatches, 1)
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 0)
    }
    func testEveryNativeCommandReachesInstalledRelayAndReturnsItsReceiptExactlyOnce() throws {
        let js = try context(), relay = MainWorldCommandRelay(function: function, contextJSON: native)
        js.evaluateScript(relay.installer)
        for (index, action) in WebBridgeAction.allCases.enumerated() {
            let e = envelope("{\"action\":\"\(action.rawValue)\"}")
            js.evaluateScript(relay.dispatch(e))
            XCTAssertNil(js.exception, action.rawValue)
            let raw = try XCTUnwrap(js.evaluateScript(e.reader)?.toString())
            _ = try e.decode(raw)
            js.evaluateScript(relay.dispatch(e))
            XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), Int32(index + 1), action.rawValue)
        }
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
    func testCapturedTargetRetainsItsExactRelayWhenANewerClickUpgradesTheNativeStore() throws {
        let store = MainWorldRelayStore()
        let original = try XCTUnwrap(store.relay(function: function, contextJSON: native, allowCreate: true))
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "current", windowID: "A", tabID: "1",
            documentID: "document", composerID: "composer", draftGeneration: "draft", clickBindingID: UUID())
        store.bind(original, to: target)
        let upgraded = try XCTUnwrap(store.relay(function: function, contextJSON: native,
            allowCreate: true, legacyObservationSession: "legacy"))
        XCTAssertNotEqual(upgraded.channel, original.channel)
        XCTAssertEqual(store.bound(to: target)?.channel, original.channel)

        let nextClick = TargetLease(adapterID: target.adapterID, surface: target.surface,
            applicationID: target.applicationID, sessionID: target.sessionID, windowID: target.windowID,
            tabID: target.tabID, documentID: target.documentID, composerID: target.composerID,
            draftGeneration: target.draftGeneration, clickBindingID: UUID())
        XCTAssertNil(store.bound(to: nextClick), "Same tab and composer are not the original captured click")
        store.bind(upgraded, to: nextClick)
        XCTAssertEqual(store.bound(to: nextClick)?.channel, upgraded.channel)
        XCTAssertEqual(store.bound(to: target)?.channel, original.channel)

        let js = try context(), command = envelope()
        js.evaluateScript(original.installer)
        js.evaluateScript(upgraded.installer)
        js.evaluateScript(try XCTUnwrap(store.bound(to: target)).dispatch(command))
        js.evaluateScript(try XCTUnwrap(store.bound(to: target)).dispatch(command))
        XCTAssertNil(js.exception)
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
        _ = try command.decode(try XCTUnwrap(js.evaluateScript(command.reader)?.toString()))
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

    func testOriginalObservationFindsBothV17BuildsAndV18ThroughV20ByExactFunctionAndLease() throws {
        let v17 = try XCTUnwrap(ChatGPTWebPageProgram.originalObservationProgram(sourceID: ChatGPTWebPageProgram.priorScreenshotSource))
        let v18 = try XCTUnwrap(ChatGPTWebPageProgram.originalObservationProgram(sourceID: ChatGPTWebPageProgram.priorClickSource))
        let v19 = try XCTUnwrap(ChatGPTWebPageProgram.originalObservationProgram(sourceID: ChatGPTWebPageProgram.priorOriginSource))
        let v20 = try XCTUnwrap(ChatGPTWebPageProgram.originalObservationProgram(sourceID: ChatGPTWebPageProgram.priorProgressSource))
        let v20Sources = try ChatGPTWebPageProgram.observationRelayFunctions(for: v20)
        let v19Sources = try ChatGPTWebPageProgram.observationRelayFunctions(for: v19)
        let v17Sources = try ChatGPTWebPageProgram.observationRelayFunctions(for: v17)
        let v18Sources = try ChatGPTWebPageProgram.observationRelayFunctions(for: v18)
        let hashes = (v17Sources + v18Sources + v19Sources + v20Sources).map { source in
            SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        XCTAssertEqual(hashes, ["0daf3f2763e340503b8c957c4ef35a619417c5e486ac48fccbcae3f657ff9a09",
                                "5fffb4b9fcee31af401a00259b3cf0cdbf7577c8f990dddbbd1ec99bfe16de3f",
                                "c32a45bbe8f6339247d523371193a81e554d770424e86f214ea50e14c29a4ef8",
                                "f1a4dfce2e04e5c54ec812e01e33fb90a6a97a839d2b06ce5eed378f77887550",
                                "0bc928293ba44f84accdb0d19886fedc94c6702383a827fa1a48214eeaebc336"])
        for (program, sources) in [(v17, v17Sources), (v18, v18Sources), (v19, v19Sources), (v20, v20Sources)] {
            for function in sources {
                let hosts = program.sourceID == v17.sourceID ? ["com.google.Chrome"] : ["com.google.Chrome", "com.microsoft.edgemac"]
                for host in hosts {
                    let js = try context(), store = MainWorldRelayStore()
                    let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: host,
                        sessionID: "current", windowID: "A", tabID: "1", documentID: "d", composerID: "c", draftGeneration: "g")
                    let identity = ObservationIdentity(operationID: UUID(), assetID: UUID(), attempt: 1,
                        assetSHA256: String(repeating: "a", count: 64), target: target)
                    let command = WebBridgeCommand(action: .observe, target: target, identity: identity)
                    let json = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
                    let context = native.replacingOccurrences(of: "com.google.Chrome", with: host)
                    let legacy = host == "com.google.Chrome" ? "legacy" : nil
                    let old = MainWorldCommandRelay(function: function, contextJSON: context, legacyObservationSession: legacy)
                    js.evaluateScript(old.installer)
                    js.evaluateScript("""
                        const id=(\(json)).identity;
                        globalThis.__riftletIndependentFileInput20261104={operations:new Map([[id.operationID,
                          {identity:id,binding:null,changeReturned:true,inputCount:1}]])};
                        """)
                    let recovered = try store.resolve(command, program: program, contextJSON: context, legacyObservationSession: legacy) {
                        try XCTUnwrap(js.evaluateScript($0)?.toString())
                    }
                    XCTAssertEqual(recovered.channel, old.channel)
                    let request = MainWorldCommandEnvelope(function: program.functionSource, commandJSON: json, contextJSON: context)
                    js.evaluateScript(recovered.dispatch(request))
                    let raw = try XCTUnwrap(js.evaluateScript(request.reader)?.toString())
                    let result = try ObservationDecoder.decode(Data(request.decode(raw).utf8))
                    XCTAssertEqual(result.observation.identity, identity)
                    XCTAssertEqual(result.observation.state, .inputTriggered)
                    XCTAssertNil(result.observation.uploadStart)
                    XCTAssertNil(js.exception)
                    XCTAssertNil(store.bound(to: target))
                    XCTAssertNil(store.relay(function: function, contextJSON: context, allowCreate: false))
                    XCTAssertThrowsError(try store.resolve(.init(action: .commit, target: target, identity: identity),
                        program: program, contextJSON: context) { _ in XCTFail("Historical input attempted discovery"); return "" })
                }
            }
        }
    }

    @MainActor func testChromeHistoricalProgramsCannotPinOrExecuteInputBeforeConsultingBrowser() async throws {
        let executor = ChromeAppleEventsExecutor()
        for source in [ChatGPTWebPageProgram.priorScreenshotSource, ChatGPTWebPageProgram.priorClickSource,
                       ChatGPTWebPageProgram.priorOriginSource, ChatGPTWebPageProgram.priorProgressSource] {
            let program = try XCTUnwrap(ChatGPTWebPageProgram.originalObservationProgram(sourceID: source))
            XCTAssertThrowsError(try executor.targetForClick(program: program)) { XCTAssertEqual($0 as? WebAdapterError, .invalidRequest) }
            for action in [WebBridgeAction.captureTarget, .validate, .begin, .chunk, .commit, .discard] {
                do { _ = try await executor.execute(.init(action: action), program: program); XCTFail("Historical command accepted") }
                catch { XCTAssertEqual(error as? WebAdapterError, .invalidRequest) }
            }
        }
    }

    func testHistoricalObservationAmbiguityAbsenceAndDifferentLeaseNeverInstallOrDispatch() throws {
        let program = try XCTUnwrap(ChatGPTWebPageProgram.originalObservationProgram(sourceID: ChatGPTWebPageProgram.priorScreenshotSource))
        let functions = try ChatGPTWebPageProgram.observationRelayFunctions(for: program)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "current", windowID: "A", tabID: "1", documentID: "d", composerID: "c", draftGeneration: "g")
        let identity = ObservationIdentity(operationID: UUID(), assetID: UUID(), attempt: 1,
            assetSHA256: String(repeating: "a", count: 64), target: target)
        let command = WebBridgeCommand(action: .observe, target: target, identity: identity)
        for installed in [[], functions, [functions[0], functions[0]]] {
            let js = try context(), store = MainWorldRelayStore()
            for source in installed { js.evaluateScript(MainWorldCommandRelay(function: source, contextJSON: native).installer) }
            let before = try XCTUnwrap(js.evaluateScript("JSON.stringify(document.documentElement.values)")?.toString())
            var reads = 0
            XCTAssertThrowsError(try store.resolve(command, program: program, contextJSON: native) { script in
                reads += 1
                return try XCTUnwrap(js.evaluateScript(script)?.toString())
            }) { XCTAssertEqual($0 as? WebAdapterError, .pageRejected(.bridgeUnavailable)) }
            XCTAssertEqual(reads, 1)
            XCTAssertEqual(js.evaluateScript("JSON.stringify(document.documentElement.values)")?.toString(), before)
            XCTAssertNil(store.bound(to: target))
        }
        let another = TargetLease(adapterID: target.adapterID, surface: target.surface, applicationID: target.applicationID,
            sessionID: target.sessionID, windowID: "other", tabID: target.tabID, documentID: target.documentID,
            composerID: target.composerID, draftGeneration: target.draftGeneration)
        XCTAssertThrowsError(try MainWorldRelayStore().resolve(.init(action: .observe, target: another, identity: identity),
            program: program, contextJSON: native) { _ in XCTFail("Mismatched identity reached the page"); return "" }) {
                XCTAssertEqual($0 as? WebAdapterError, .invalidRequest)
            }
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

    func testAsyncAttachmentDiscoverySettlesOriginalCommandWithoutSerializingPromiseOrReplaying() throws {
        let js = try context()
        js.evaluateScript("var resolveCommit;")
        let asyncFunction = "function(){executions++;return new Promise(resolve=>{resolveCommit=resolve})}"
        let relay = MainWorldCommandRelay(function: asyncFunction, contextJSON: native)
        let e = envelope("{\"action\":\"commit\"}")
        js.evaluateScript(relay.installer)
        js.evaluateScript(relay.dispatch(e))
        XCTAssertNil(js.exception)
        XCTAssertEqual(js.evaluateScript(e.reader)?.toString(), "", "A Promise is not a settled input result")
        XCTAssertEqual(js.evaluateScript("timers.length")?.toInt32(), 0, "Receipt TTL starts only after settlement")
        js.evaluateScript(relay.dispatch(e))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1, "Pending menu discovery cannot repeat commit")
        js.evaluateScript("resolveCommit({inputCount:1,state:'inputTriggered'})")
        XCTAssertNil(js.exception)
        let raw = try XCTUnwrap(js.evaluateScript(e.reader)?.toString())
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(e.decode(raw).utf8)) as? [String: Any])
        XCTAssertEqual(payload["inputCount"] as? Int, 1)
        XCTAssertEqual(payload["state"] as? String, "inputTriggered")
        XCTAssertEqual(js.evaluateScript("timers.length")?.toInt32(), 1)
        js.evaluateScript(relay.dispatch(e))
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
        XCTAssertEqual(js.evaluateScript(e.reader)?.toString(), raw)
        js.evaluateScript("timers.forEach(f=>f())")
        js.evaluateScript(relay.dispatch(e))
        XCTAssertEqual(js.evaluateScript(e.reader)?.toString(), "")
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
    }

    func testRejectedAsyncCommandPublishesOnlyItsClosedFailureAndDoesNotRetry() throws {
        for reason in ["TARGET_INVALID", "private-page-error"] {
            let js = try context()
            js.evaluateScript("var rejectCommit;")
            let pending = "function(){executions++;return new Promise((resolve,reject)=>{rejectCommit=reject})}"
            let relay = MainWorldCommandRelay(function: pending, contextJSON: native)
            let e = envelope("{\"action\":\"commit\"}")
            js.evaluateScript(relay.installer); js.evaluateScript(relay.dispatch(e))
            js.evaluateScript("rejectCommit(Error('\(reason)'))")
            XCTAssertNil(js.exception)
            let raw = try XCTUnwrap(js.evaluateScript(e.reader)?.toString())
            XCTAssertThrowsError(try e.decode(raw)) {
                XCTAssertEqual($0 as? WebAdapterError,
                    reason == "TARGET_INVALID" ? .pageRejected(.invalidTarget) : .invalidReply)
            }
            XCTAssertFalse(raw.contains("private-page-error"))
            js.evaluateScript(relay.dispatch(e))
            XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
        }
    }

    func testAsyncSettlementCannotPublishIntoAnotherDocument() throws {
        let js = try context()
        js.evaluateScript("var resolveCommit;")
        let pending = "function(){executions++;return new Promise(resolve=>{resolveCommit=resolve})}"
        let relay = MainWorldCommandRelay(function: pending, contextJSON: native), e = envelope()
        js.evaluateScript(relay.installer); js.evaluateScript(relay.dispatch(e))
        js.evaluateScript("var oldRoot=document.documentElement;document.documentElement=makeRoot();resolveCommit({inputCount:1})")
        XCTAssertNil(js.exception)
        XCTAssertEqual(js.evaluateScript(e.reader)?.toString(), "")
        XCTAssertEqual(js.evaluateScript("Object.keys(document.documentElement.values).length")?.toInt32(), 0)
        XCTAssertEqual(js.evaluateScript("timers.length")?.toInt32(), 0)
        XCTAssertEqual(js.evaluateScript("executions")?.toInt32(), 1)
    }

}
