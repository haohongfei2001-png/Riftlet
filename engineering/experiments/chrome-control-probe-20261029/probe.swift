// Read-only control-channel diagnosis, never a Riftlet target or input grant.
// No activation, prompt, setter, file input, capture, paste, or process launch.
import AppKit
import Carbon

private func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
private func object(_ kind: String, form: String, key: NSAppleEventDescriptor,
                    container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
    let r = NSAppleEventDescriptor.record()
    r.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
    r.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
    r.setDescriptor(key, forKeyword: code("seld"))
    r.setDescriptor(container, forKeyword: code("from"))
    guard let result = r.coerce(toDescriptorType: code("obj ")) else { throw ProbeError.shape }
    return result
}
private func property(_ name: String, of parent: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
    try object("prop", form: "prop", key: .init(typeCode: code(name)), container: parent)
}
private enum ProbeError: Error { case shape, processChanged, permission(Int32), native(Int32) }
private func failure(_ error: Error) -> [String: Any] {
    switch error {
    case ProbeError.shape: return ["result": "FAIL", "kind": "descriptorShape"]
    case ProbeError.processChanged: return ["result": "FAIL", "kind": "processChanged"]
    case let ProbeError.permission(status): return ["result": "NOT_RUN", "kind": "permission", "status": status]
    case let ProbeError.native(status): return ["result": "FAIL", "kind": "appleEvent", "status": status]
    default: return ["result": "FAIL", "kind": "native", "status": (error as NSError).code]
    }
}

private struct Receiver {
    let pid: pid_t
    let launch: Date
    func stable() -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated && app.bundleIdentifier == "com.google.Chrome" && app.launchDate == launch
    }
    func permission() -> Int32 {
        let address = NSAppleEventDescriptor(processIdentifier: pid)
        return AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, false)
    }
    func send(_ suite: String, _ event: String, direct: NSAppleEventDescriptor,
              javascript: String? = nil) throws -> NSAppleEventDescriptor {
        guard stable() else { throw ProbeError.processChanged }
        let consent = permission()
        guard consent == noErr else { throw ProbeError.permission(consent) }
        let request = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(event),
            targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        request.setParam(direct, forKeyword: code("----"))
        if let javascript { request.setParam(.init(string: javascript), forKeyword: code("JvSc")) }
        let reply = try request.sendEvent(options: [.waitForReply, .neverInteract], timeout: 0.5)
        guard stable() else { throw ProbeError.processChanged }
        if let err = reply.paramDescriptor(forKeyword: code("errn")), err.int32Value != 0 {
            throw ProbeError.native(err.int32Value)
        }
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else { throw ProbeError.shape }
        return result
    }
    func get(_ value: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send("core", "getd", direct: value)
    }
}

private func absolute(_ descriptor: NSAppleEventDescriptor, kind: String) -> NSAppleEventDescriptor? {
    guard descriptor.descriptorType == code("obj "), descriptor.numberOfItems == 4,
          Set((1...4).map { descriptor.keywordForDescriptor(at: $0) }) == Set(["want", "form", "seld", "from"].map(code)),
          let want = descriptor.forKeyword(code("want")), want.descriptorType == code("type"),
          want.data.count == 4, want.typeCodeValue == code(kind),
          let form = descriptor.forKeyword(code("form")), form.descriptorType == code("enum"),
          form.data.count == 4, form.enumCodeValue == code("ID  "),
          let selector = descriptor.forKeyword(code("seld")), selector.descriptorType == code("utxt"),
          let value = selector.stringValue, !value.isEmpty, value.utf8.count <= 19,
          value.utf8.allSatisfy({ (48...57).contains($0) }), value.first != "0",
          let integer = Int64(value), integer > 0, String(integer) == value else { return nil }
    return descriptor.forKeyword(code("from"))
}
private func fixedTab(_ value: NSAppleEventDescriptor) -> Bool {
    guard let window = absolute(value, kind: "CrTb"), let root = absolute(window, kind: "cwin") else { return false }
    return root.descriptorType == code("null") && root.data.isEmpty
}
private func aggregateDOM(_ text: String?) throws -> [String: Any] {
    guard let text, text.utf8.count <= 512,
          let data = text.data(using: .utf8),
          let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(value.keys) == Set(["ready", "visible", "focused", "chatGPT", "ordinaryThread", "editors", "fileInputs"]),
          let ready = value["ready"] as? String, ["loading", "interactive", "complete"].contains(ready)
    else { throw ProbeError.shape }
    var projected: [String: Any] = ["ready": ready]
    for key in ["visible", "focused", "chatGPT", "ordinaryThread"] {
        guard let number = value[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID()
        else { throw ProbeError.shape }
        projected[key] = number.boolValue
    }
    for key in ["editors", "fileInputs"] {
        guard let number = value[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (0...10_000).contains(number.doubleValue),
              number.doubleValue.rounded() == number.doubleValue else { throw ProbeError.shape }
        projected[key] = number.intValue
    }
    return projected
}
private func timed(_ body: () throws -> [String: Any]) -> [String: Any] {
    let start = ProcessInfo.processInfo.systemUptime
    var report: [String: Any]
    do { report = try body() } catch { report = failure(error) }
    report["elapsedMilliseconds"] = (ProcessInfo.processInfo.systemUptime - start) * 1000
    return report
}

@main private struct Probe {
    @MainActor static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--self-check"] {
            let window = try object("cwin", form: "ID  ", key: .init(string: "17"))
            let tab = try object("CrTb", form: "ID  ", key: .init(string: "19"), container: window)
            precondition(fixedTab(tab))
            let relative = try object("CrTb", form: "indx", key: .init(int32: 1), container: window)
            let zero = try object("CrTb", form: "ID  ", key: .init(string: "0"), container: window)
            precondition(!fixedTab(relative)); precondition(!fixedTab(zero))
            let valid = "{\"ready\":\"complete\",\"visible\":true,\"focused\":false,\"chatGPT\":true,\"ordinaryThread\":true,\"editors\":1,\"fileInputs\":2}"
            let decoded = try aggregateDOM(valid)
            precondition(decoded["ready"] as? String == "complete")
            for invalid in [valid.replacingOccurrences(of: "{", with: "{\"unexpected\":\"private\","),
                            valid.replacingOccurrences(of: "\"visible\":true", with: "\"visible\":1"),
                            valid.replacingOccurrences(of: "\"editors\":1", with: "\"editors\":true"),
                            valid.replacingOccurrences(of: "\"editors\":1", with: "\"editors\":10001"),
                            String(repeating: "x", count: 513)] {
                do { _ = try aggregateDOM(invalid); preconditionFailure("invalid page reply accepted") }
                catch { /* Closed rejection; never output the remote text. */ }
            }
            print("CHROME_CONTROL_PROBE_SELF_CHECK_PASS; no running browser/permissions inspected")
            return
        }
        guard arguments == ["--live-read-only"] else {
            print("Usage: probe --self-check | --live-read-only (no UI writes, no permission prompts)")
            exit(2)
        }
        let front = NSWorkspace.shared.frontmostApplication
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
            .filter { !$0.isTerminated }.sorted { $0.processIdentifier < $1.processIdentifier }
        let trusted = AXIsProcessTrusted()
        var reports: [[String: Any]] = []
        for (index, app) in apps.enumerated() {
            var r: [String: Any] = ["receiverIndex": index + 1, "frontmost": front?.processIdentifier == app.processIdentifier]
            guard let launch = app.launchDate else {
                r["receiverSession"] = failure(ProbeError.processChanged)
                reports.append(r); continue
            }
            let receiver = Receiver(pid: app.processIdentifier, launch: launch)
            if trusted {
                r["accessibility"] = timed {
                    guard receiver.stable() else { throw ProbeError.processChanged }
                    let ax = AXUIElementCreateApplication(receiver.pid)
                    let configured = AXUIElementSetMessagingTimeout(ax, 0.3)
                    guard configured == .success else {
                        return ["result": "FAIL", "kind": "axTimeoutConfiguration", "status": configured.rawValue]
                    }
                    var value: CFTypeRef?
                    let status = AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &value)
                    guard receiver.stable() else { throw ProbeError.processChanged }
                    let validWindow = value.map { CFGetTypeID($0) == AXUIElementGetTypeID() } ?? false
                    return ["result": status == .success && validWindow ? "PASS" : "FAIL", "status": status.rawValue,
                            "focusedWindowReturned": validWindow]
                }
            } else { r["accessibility"] = ["result": "NOT_RUN", "reason": "probe process has no AX trust"] }
            if receiver.stable() {
                r["permissionStatus"] = receiver.permission()
                r["appleEventFrontmost"] = timed {
                    let reply = try receiver.get(property("pisf"))
                    return ["result": "PASS", "frontmost": reply.booleanValue]
                }
                r["activeTabAndReadOnlyDOM"] = timed {
                    let relativeWindow = try object("cwin", form: "indx", key: .init(int32: 1))
                    let tab = try receiver.get(property("acTa", of: relativeWindow))
                    guard fixedTab(tab) else { throw ProbeError.shape }
                    // Only aggregate booleans/counts. No URL, title, content,
                    // draft identity, text, selection, attachment, or file read.
                    let js = "JSON.stringify({ready:document.readyState,visible:document.visibilityState==='visible',focused:document.hasFocus(),chatGPT:location.hostname==='chatgpt.com',ordinaryThread:/^\\/c\\/[a-f0-9-]+$/.test(location.pathname),editors:document.querySelectorAll('[contenteditable=true][role=textbox]').length,fileInputs:document.querySelectorAll('input[type=file]').length})"
                    let text = try receiver.send("CrSu", "ExJa", direct: tab, javascript: js).stringValue
                    let value = try aggregateDOM(text)
                    return ["result": "PASS", "fixedOriginalTabDescriptor": true, "aggregateDOM": value]
                }
            }
            reports.append(r)
        }
        let result: [String: Any] = ["scope": "READ_ONLY_CONTROL_DIAGNOSIS_NOT_TARGET_AUTHORITY",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "screenCount": NSScreen.screens.count, "frontmostChrome": front?.bundleIdentifier == "com.google.Chrome",
            "probeAXTrusted": trusted, "probeScreenCapturePreflight": CGPreflightScreenCaptureAccess(),
            "chromeReceivers": reports, "prompts": 0, "activations": 0, "inputs": 0, "messagesSent": 0]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
