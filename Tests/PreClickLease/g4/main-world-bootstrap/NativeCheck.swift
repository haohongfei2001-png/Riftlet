
import CryptoKit
import Darwin

/// This file is compiled only into the private QA executable. The family is its
/// only argument. It creates a new window and accepts no URL, target, or script.
@MainActor
public enum OwnedNativeBootstrap {
    private typealias Row = [String: Any]
    private typealias Descriptor = NSAppleEventDescriptor
    private enum Step: String { case install, read, clear, retire }
    private static let root = URL(fileURLWithPath: PinnedLocalBootstrapFixture.work, isDirectory: true)
    private static let fixtureSuffix = "Tests/PreClickLease/g4/main-world-bootstrap/fixture.html"

    private static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw Identity.Refusal(reason) }
    }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func literal(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor private final class Session {
        let family: String
        let file: URL
        let directory: URL
        let process: ChromeProcessIdentity
        let before: Set<String>
        let bridge: ChromePIDEvents
        let challenge = UUID().uuidString.lowercased()
        var windowID: String?
        var tabID: String?
        var nonce: String?
        var globalKey = ""
        var prototypeKey = ""
        var pendingCleanup = false
        var cleanupIssued = false
        var log = [Row]()

        init(_ family: String) throws {
            guard let vendor = Identity.families[family] else { throw Identity.Refusal("UNKNOWN_FAMILY") }
            self.family = family
            directory = root.appendingPathComponent(family, isDirectory: true)
            file = directory.appendingPathComponent(fixtureSuffix)
            guard let path = realpath(file.path, nil) else { throw Identity.Refusal("FIXTURE_PATH_UNAVAILABLE") }
            defer { free(path) }
            try require(file.isFileURL && String(cString: path) == file.path, "FIXTURE_PATH_CHANGED")
            try require(sha(try Data(contentsOf: file)) == PinnedLocalBootstrapFixture.sha, "FIXTURE_DIGEST_CHANGED")
            let permission = AEDeterminePermissionToAutomateTarget(Descriptor(bundleIdentifier: vendor.bundle).aeDesc,
                                                                 typeWildCard, typeWildCard, false)
            try require(permission == noErr, "EXISTING_AUTOMATION_PERMISSION_REQUIRED_\(permission)")
            process = try Identity.certified(vendor, expectedPID: nil)
            before = try Identity.windows(process)
            bridge = ChromePIDEvents(pid: process.pid, trace: ChromeBridgeTrace(sink: BoundedDiagnosticTrace(enabled: false)),
                                     requestID: challenge)
            try write("creation-intent", ["originalWindowIDs": before.sorted(), "pid": process.pid, "birth": process.session])
        }

        func write(_ name: String, _ value: Row) throws {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: directory.appendingPathComponent(name + ".json"), options: .withoutOverwriting)
        }

        func event(_ name: String, _ detail: Row = [:]) {
            log.append(["event": name, "uptime": ProcessInfo.processInfo.systemUptime, "detail": detail])
        }

        func ownedWindow(_ id: String) throws -> Descriptor {
            try Identity.object("cwin", "ID  ", .init(string: id))
        }

        func create() throws {
            let created = try Owned.request(process, "core", "crel", ["kocl": .init(typeCode: Identity.code("cwin"))])
            guard created.descriptorType == typeObjectSpecifier,
                  created.forKeyword(Identity.code("want"))?.typeCodeValue == Identity.code("cwin"),
                  created.forKeyword(Identity.code("form"))?.enumCodeValue == Identity.code("ID  "),
                  let id = created.forKeyword(Identity.code("seld"))?.stringValue,
                  let number = Int64(id), number > 0, String(number) == id, !before.contains(id),
                  try Identity.windows(process) == before.union([id]) else { throw Identity.Refusal("NEW_WINDOW_NOT_VERIFIED") }
            windowID = id
            let win = try ownedWindow(id)
            let tabs = try Owned.tabIDs(process, window: win)
            guard tabs.count == 1 else { throw Identity.Refusal("SOLE_NEW_TAB_NOT_VERIFIED") }
            tabID = tabs[0]
            let tab = try Identity.object("CrTb", "ID  ", .init(string: tabs[0]), win)
            let blank = try bridge.url(window: id, tab: tabs[0])
            try require(["about:blank","chrome://newtab/","edge://newtab/"].contains(blank), "NEW_TAB_NOT_BLANK")
            try write("window-created", ["pid": process.pid, "birth": process.session, "window": id, "tab": tabs[0],
                                        "beforeWindowIDs": before.sorted(), "blankVerified": true])
            _ = try Owned.request(process, "core", "setd",
                                  ["----": Identity.property("URL ", tab), "data": .init(string: file.absoluteString)])
            let end = Date(timeIntervalSinceNow: 4)
            while try bridge.url(window: id, tab: tabs[0]) != file.absoluteString {
                if Date() > end { throw Identity.Refusal("LOCAL_FILE_DID_NOT_LOAD") }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.035))
            }
            try checkOriginal()
            event("owned-file-loaded")
        }

        func checkOriginal() throws {
            guard let win = windowID, let tab = tabID, process.isCurrent(),
                  try Identity.windows(process) == before.union([win]),
                  try Owned.tabIDs(process, window: ownedWindow(win)) == [tab],
                  try bridge.url(window: win, tab: tab) == file.absoluteString else {
                throw Identity.Refusal("ORIGINAL_LOCAL_TARGET_CHANGED")
            }
            let active = try bridge.activeIdentity(check: "owned_local_bootstrap")
            try require(active.window == win && active.tab == tab, "ORIGINAL_TAB_NO_LONGER_SELECTED")
        }

        func sample() throws -> Row? {
            try checkOriginal()
            guard let win = windowID, let tab = tabID else { throw Identity.Refusal("MISSING_ORIGINAL") }
            let source = """
            (()=>{if(location.protocol!=='file:'||location.href!==\(try literal(file.absoluteString))||top!==self)return '';
              const e=document.querySelector('#riftlet-owned-bootstrap-receipt');if(!e?.dataset.result)return '';
              const r=JSON.parse(e.dataset.result),g=\(try literal(globalKey)),p=\(try literal(prototypeKey));
              return JSON.stringify({page:r,timeOrigin:performance.timeOrigin,entryID:navigation.currentEntry?.id??null,
                originalFile:location.href,globalVisible:!!g&&Object.hasOwn(globalThis,g),
                xhrVisible:!!p&&Object.hasOwn(XMLHttpRequest.prototype,p),
                ownedFunctionVisible:typeof globalThis.riftletOwnedBootstrapFixture==='function',
                hidden:e.hidden,textEmpty:e.textContent==='',cspCount:e.dataset.cspViolations??null,
                cspDirective:e.dataset.cspEffectiveDirective??null,bufferFull:e.dataset.resourceBufferFullEvents??null,
                temporaryNodePresent:!!document.getElementById('riftlet-owned-bootstrap-temporary'),
                resourceEntries:performance.getEntriesByType('resource').filter(e=>/^https?:/i.test(e.name)).length});})()
            """
            let answer = try bridge.execute(source, window: win, tab: tab)
            try checkOriginal()
            guard !answer.isEmpty else { return nil }
            let result = try JSONSerialization.jsonObject(with: Data(answer.utf8)) as? Row
            if let nonce { try require((result?["page"] as? Row)?["documentNonce"] as? String == nonce, "STALE_DOCUMENT") }
            return result
        }

        func wait(_ phase: String) throws -> Row {
            let end = Date(timeIntervalSinceNow: 4)
            var last: Row?
            repeat {
                if let result = try sample(), let page = result["page"] as? Row {
                    last = result
                    if page["phase"] as? String == phase { return result }
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.035))
            } while Date() < end
            if let last {
                try write("last-while-waiting-" + phase, last)
                if (last["page"] as? Row)?["phase"] as? String == "ready",
                   let count = last["cspCount"] as? String, Int(count) ?? 0 > 0 {
                    pendingCleanup = false
                }
            }
            throw Identity.Refusal("PAGE_RECEIPT_MISSING_" + phase.uppercased())
        }

        func submit(_ step: Step) throws {
            try checkOriginal()
            guard let win = windowID, let tab = tabID, let nonce else { throw Identity.Refusal("MISSING_ORIGINAL") }
            // Only the immutable function already authored into this exact local
            // file can receive the three fixed actions. No general payload API.
            let source = """
            (()=>{if(location.protocol!=='file:'||top!==self||location.href!==\(try literal(file.absoluteString)))return;
              const e=document.getElementById('riftlet-owned-bootstrap-receipt');
              if(!e?.dataset.result||JSON.parse(e.dataset.result).documentNonce!==\(try literal(nonce)))return;
              globalThis.riftletOwnedBootstrapFixture?.(\(try literal(step.rawValue)),globalThis,XMLHttpRequest.prototype,\(try literal(challenge)));})()
            """
            event("native-submit-intent", ["step": step.rawValue])
            if step == .install { pendingCleanup = true }
            if step == .clear { cleanupIssued = true }
            try bridge.submitMainWorld(source, window: win, tab: tab)
            event("native-submit-return", ["step": step.rawValue, "nativeStatus": 0])
            try checkOriginal()
        }

        func measure() throws {
            try create()
            let ready = try wait("ready")
            guard let page = ready["page"] as? Row, let proof = page["documentNonce"] as? String, !proof.isEmpty else {
                throw Identity.Refusal("FIXTURE_NOT_READY")
            }
            nonce = proof
            try write("ready", ready)
            try submit(.install)
            let installed = try wait("installed")
            try write("installed", installed)
            guard let receipt = installed["page"] as? Row,
                  receipt["nativeChallenge"] as? String == challenge,
                  let g = receipt["globalMarkerKey"] as? String, !g.isEmpty,
                  let p = receipt["prototypeMarkerKey"] as? String, !p.isEmpty else {
                throw Identity.Refusal("LOCAL_INSTALL_CHALLENGE_OR_KEYS_MISSING")
            }
            globalKey = g
            prototypeKey = p
            try write("isolated", wait("installed"))
            try submit(.read)
            try write("main-read", wait("read"))
            try submit(.clear)
            try write("clear", wait("cleared"))
            pendingCleanup = false
            try write("final-independent-read", wait("cleared"))
            try submit(.retire)
            try verifyRetirement(ready)
        }

        func verifyRetirement(_ original: Row) throws {
            guard let win = windowID, let tab = tabID else { throw Identity.Refusal("MISSING_ORIGINAL") }
            let source = """
            (()=>{if(location.protocol!=='file:'||top!==self||location.href!==\(try literal(file.absoluteString)))return '';
              const e=document.getElementById('riftlet-owned-bootstrap-receipt');
              return JSON.stringify({timeOrigin:performance.timeOrigin,entryID:navigation.currentEntry?.id??null,
                staticNodePresent:!!e,hidden:e?.hidden===true,textEmpty:e?.textContent==='',
                noReceiptOrPolicyData:!!e&&Object.keys(e.dataset).length===0,
                temporaryNodeAbsent:!document.getElementById('riftlet-owned-bootstrap-temporary'),
                globalAbsent:!Object.hasOwn(globalThis,\(try literal(globalKey))),
                prototypeAbsent:!Object.hasOwn(XMLHttpRequest.prototype,\(try literal(prototypeKey)))});})()
            """
            let end = Date(timeIntervalSinceNow: 3)
            repeat {
                try checkOriginal()
                let string = try bridge.execute(source, window: win, tab: tab)
                try checkOriginal()
                if let row = try JSONSerialization.jsonObject(with: Data(string.utf8)) as? Row,
                   row["noReceiptOrPolicyData"] as? Bool == true {
                    let expected = ["staticNodePresent","hidden","textEmpty","temporaryNodeAbsent","globalAbsent","prototypeAbsent"]
                    try require(expected.allSatisfy { row[$0] as? Bool == true }
                                && row["timeOrigin"] as? Double == original["timeOrigin"] as? Double, "RETIREMENT_MISMATCH")
                    try write("retired", row)
                    return
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.035))
            } while Date() < end
            throw Identity.Refusal("RECEIPT_RETIREMENT_UNCONFIRMED")
        }

        func closeIfOwned() throws {
            guard let win = windowID, let tab = tabID, !before.contains(win),
                  process.isCurrent(), try Identity.windows(process).contains(win),
                  try Owned.tabIDs(process, window: ownedWindow(win)) == [tab],
                  try bridge.url(window: win, tab: tab) == file.absoluteString else {
                throw Identity.Refusal("CLOSURE_OWNERSHIP_UNPROVEN")
            }
            if pendingCleanup && !cleanupIssued && nonce != nil {
                do { try submit(.clear); try write("cleanup-after-stop", wait("cleared")) }
                catch { event("cleanup-read-unavailable") }
            }
            try write("close-intent", ["pid": process.pid, "birth": process.session, "window": win, "tab": tab])
            _ = try Owned.request(process, "core", "clos", ["----": ownedWindow(win)])
            let end = Date(timeIntervalSinceNow: 3)
            while try Identity.windows(process).contains(win) {
                if Date() > end { throw Identity.Refusal("WINDOW_CLOSE_UNCONFIRMED") }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            let after = try Identity.windows(process)
            try write("closed", ["ownedWindowGone": !after.contains(win), "allOriginalIDsRestored": before == after])
        }
    }

    private static func reason(_ error: Error) -> String {
        if let known = error as? Identity.Refusal { return known.reason }
        if case WebAdapterError.nativeEventFailed(let status) = error { return "APPLE_EVENT_\(status)" }
        return "LOCAL_AUDIT_ERROR_\((error as NSError).code)"
    }

    public static func main() -> Int32 {
        let args = CommandLine.arguments
        guard args.count == 2, Identity.families[args[1]] != nil else { return 2 }
        let family = args[1]
        var result: Row = ["family": family, "startedUTC": ISO8601DateFormatter().string(from: Date())]
        do {
            let session = try Session(family)
            do { try session.measure() } catch { result["measurementStop"] = reason(error) }
            if session.windowID != nil {
                do { try session.closeIfOwned() } catch { result["closureStop"] = reason(error) }
            }
            result["events"] = session.log
            result["challenge"] = session.challenge
            result["endedUTC"] = ISO8601DateFormatter().string(from: Date())
            try session.write("run", result)
        } catch {
            result["preparationStop"] = reason(error)
            guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                  (try? data.write(to: root.appendingPathComponent(family + "/preparation-stop.json"),
                                   options: .withoutOverwriting)) != nil else { return 1 }
        }
        print(family + " local receipt recorded")
        return 0
    }
}
