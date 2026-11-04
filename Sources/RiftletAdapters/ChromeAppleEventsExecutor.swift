import AppKit
import Foundation
import RiftletCore

/// Native Apple Events address a fixed process/window/tab. Page discovery may
/// start on the first click; no earlier page acknowledgement authorizes input.
@MainActor
public final class ChromeAppleEventsExecutor: WebClickTargetPinning {
    private static let scriptQueue = DispatchQueue(label: "com.riftlet.apple-events", qos: .userInitiated)
    private static let observationQueue = DispatchQueue(label: "com.riftlet.apple-events-observation", qos: .utility)
    private let relays = MainWorldRelayStore()
    private let trace: ChromeBridgeTrace
    private var routes: [String: ChromeClickRoute] = [:]
    private var lastForegroundChrome: ChromeProcessIdentity?
    private var activationObserver: NSObjectProtocol?

    public init(traceEnabled: Bool = false, diagnosticTrace: BoundedDiagnosticTrace? = nil) {
        trace = ChromeBridgeTrace(sink: diagnosticTrace ?? BoundedDiagnosticTrace(enabled: traceEnabled))
        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier == "com.google.Chrome" {
            lastForegroundChrome = ChromeProcessIdentity.read(pid: application.processIdentifier)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          application.bundleIdentifier == "com.google.Chrome" else { return }
                    self?.lastForegroundChrome = ChromeProcessIdentity.read(pid: application.processIdentifier)
                }
            }
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    /// Only native object IDs and the tab URL are read during mouse-down. This
    /// fixes the destination before a queued task can observe a different chat.
    /// JavaScript bootstrap, DOM discovery and receipt waiting run off the UI.
    public func targetForClick(program: WebPageProgram) throws -> Task<TargetLease, Error> {
        let identity = try clickReceiver()
        let requestID = UUID().uuidString
        let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: requestID)
        let selected = try bridge.activeIdentity(check: "click_selection")
        let route = try ChromeClickRoute(window: selected.window, tab: selected.tab,
            url: bridge.url(window: selected.window, tab: selected.tab))
        guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
        let relays = self.relays, trace = self.trace
        return Task { [weak self] in
            try Task.checkCancellation()
            let bytes = try await Self.run(WebBridgeCommand(action: .captureTarget), program: program,
                identity: identity, route: route, relays: relays, trace: trace, requestID: requestID)
            try Task.checkCancellation()
            guard let target = try? JSONDecoder().decode(TargetLease.self, from: bytes),
                  target.adapterID == "chatgpt-web", target.surface == .webChat,
                  target.applicationID == "com.google.Chrome", target.sessionID == identity.session,
                  target.windowID == route.window, target.tabID == route.tab,
                  !target.documentID.isEmpty, !target.composerID.isEmpty, !target.draftGeneration.isEmpty,
                  let self else { throw WebAdapterError.invalidTarget }
            self.routes[target.stableKey] = route
            return target
        }
    }

    private func clickReceiver() throws -> ChromeProcessIdentity {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
        let running = Set(applications.filter { !$0.isTerminated }.map(\.processIdentifier))
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmost?.bundleIdentifier == "com.google.Chrome" ? frontmost?.processIdentifier : nil
        if let frontmostPID {
            guard let identity = ChromeProcessIdentity.read(pid: frontmostPID) else { throw WebAdapterError.invalidTarget }
            return identity
        }
        let previous = lastForegroundChrome
        guard let pid = ChromeReceiverSelection.choose(frontmost: nil, lastForeground: previous?.pid,
                running: running),
              let identity = ChromeProcessIdentity.read(pid: pid) else { throw WebAdapterError.invalidTarget }
        // Retain the observed process lifetime. An exited Chrome or reused PID
        // is different from never having observed a Chrome activation.
        if let previous, identity != previous { throw WebAdapterError.invalidTarget }
        return identity
    }

    private nonisolated static func contextJSON(session: String, window: String, tab: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(["applicationID":"com.google.Chrome", "sessionID":session,
            "windowID":window, "tabID":tab]), as: UTF8.self)
    }

    public func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        guard command.action != .pinTarget else { throw WebAdapterError.invalidRequest }
        if command.action == .captureTarget {
            let task = try targetForClick(program: program)
            let target = try await task.value
            return try JSONEncoder().encode(target)
        }
        guard let target = command.target, target.applicationID == "com.google.Chrome",
              let application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first(where: {
                  ChromeProcessIdentity.read(pid: $0.processIdentifier)?.matches(session: target.sessionID,
                      allowLegacyObservation: command.action == .observe) == true
              }), let identity = ChromeProcessIdentity.read(pid: application.processIdentifier),
              let tab = target.tabID, let windowNumber = Int64(target.windowID), windowNumber > 0,
              let tabNumber = Int64(tab), tabNumber > 0 else { throw WebAdapterError.invalidTarget }
        let route = routes[target.stableKey]
        if ChromeCommandRouting.requiresSelectionCheck(command.action), route == nil {
            throw WebAdapterError.invalidTarget
        }
        return try await Self.run(command, program: program, identity: identity, route: route,
            relays: relays, trace: trace, requestID: UUID().uuidString)
    }

    private nonisolated static func run(_ command: WebBridgeCommand, program: WebPageProgram,
        identity: ChromeProcessIdentity, route: ChromeClickRoute?, relays: MainWorldRelayStore,
        trace: ChromeBridgeTrace, requestID: String) async throws -> Data {
        let commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        let enqueued = ProcessInfo.processInfo.systemUptime
        // Old UNKNOWN observations must not occupy the input queue. Each
        // request still owns a separate receipt and never resubmits input.
        let queue = command.action == .observe ? observationQueue : scriptQueue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let started = ProcessInfo.processInfo.systemUptime
                var phase = "process"
                let result: Result<Data, Error> = Result {
                    try autoreleasepool {
                        guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
                        let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: requestID)
                        guard let window = route?.window ?? command.target?.windowID,
                              let tab = route?.tab ?? command.target?.tabID else { throw WebAdapterError.invalidTarget }
                        func checkSelection() throws {
                            guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
                            guard ChromeCommandRouting.requiresSelectionCheck(command.action) else { return }
                            guard let route else { throw WebAdapterError.invalidTarget }
                            let active = try bridge.activeIdentity(check: "fixed_selection")
                            let current = try ChromeClickRoute(window: active.window, tab: active.tab,
                                url: bridge.url(window: active.window, tab: active.tab))
                            guard current == route else { throw WebAdapterError.nativeSelectionChanged }
                        }
                        phase = "selection"
                        if command.action == .captureTarget { try checkSelection() }
                        let context = contextJSON(session: command.target?.sessionID ?? identity.session, window: window, tab: tab)
                        let envelope = MainWorldCommandEnvelope(function: program.functionSource,
                            commandJSON: commandJSON, contextJSON: context)
                        let legacySession = identity.legacyLaunchDate.flatMap { date in
                            date.timeIntervalSince1970.isFinite ? "\(identity.pid):\(date.timeIntervalSince1970)" : nil
                        }
                        var relay = relays.relay(function: program.functionSource, contextJSON: context,
                            allowCreate: false, legacyObservationSession: legacySession)
                        if relay == nil, command.action == .observe || command.action == .captureTarget {
                            let expected = MainWorldCommandRelay(function: program.functionSource,
                                contextJSON: context, legacyObservationSession: legacySession)
                            let channel = try bridge.execute(expected.discovery, window: window, tab: tab,
                                receiptBudget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 1))
                            guard channel != "ambiguous" else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
                            relay = relays.adopt(function: program.functionSource, contextJSON: context,
                                channel: channel, legacyObservationSession: legacySession)
                        }
                        if command.action == .captureTarget, relay == nil {
                            relay = relays.relay(function: program.functionSource, contextJSON: context,
                                allowCreate: true, legacyObservationSession: legacySession)
                        }
                        guard let relay else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
                        phase = "submit"
                        var install = false
                        if command.action == .captureTarget {
                            install = try bridge.execute(relay.probe, window: window, tab: tab,
                                receiptBudget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 1)) != "ready"
                        }
                        // Bootstrap is legal on the first click even when the
                        // thumbnail changed focus. It addresses this exact tab.
                        try checkSelection()
                        if install {
                            let source = "(()=>{\(relay.installer);return \(relay.dispatch(envelope));})()"
                            try bridge.submitMainWorld(source, window: window, tab: tab)
                        } else {
                            try bridge.dispatchMainWorld(relay.dispatch(envelope), window: window, tab: tab)
                        }
                        phase = "receipt"
                        let receipt = try MainWorldReceiptReader.read(envelope) { budget in
                            try bridge.execute(envelope.reader, window: window, tab: tab, receiptBudget: budget)
                        }
                        guard identity.isCurrent(), receipt.text.utf8.count <= ObservationDecoder.maximumPayloadBytes else {
                            throw WebAdapterError.invalidReply
                        }
                        if command.action == .captureTarget { try checkSelection() }
                        phase = "complete"
                        return Data(receipt.text.utf8)
                    }
                }
                let error: WebAdapterError?
                if case .failure(let failure) = result { error = failure as? WebAdapterError } else { error = nil }
                trace.record(requestID: requestID, action: command.action.rawValue, phase: phase,
                    enqueued: enqueued, started: started, context: command.captureInvocation,
                    succeeded: (try? result.get()) != nil, error: error)
                continuation.resume(with: result)
            }
        }
    }
}

/// Local opt-in timing only; never raw source, URL, page content or payload.
private final class ChromeBridgeTrace: @unchecked Sendable {
    private let sink: BoundedDiagnosticTrace
    init(sink: BoundedDiagnosticTrace) { self.sink = sink }
    func record(requestID: String, action: String, phase: String, enqueued: TimeInterval, started: TimeInterval,
                context: CaptureInvocationContext?, succeeded: Bool, error: WebAdapterError? = nil) {
        let end = ProcessInfo.processInfo.systemUptime
        var fields: [String: Any] = ["event": "native_bridge", "requestID": requestID, "action": action, "phase": phase,
            "queuedUptime": enqueued, "startedUptime": started, "endedUptime": end,
            "queueMS": (started - enqueued) * 1000, "executionMS": (end - started) * 1000, "transportSucceeded": succeeded]
        addContext(context, to: &fields)
        if let error {
            fields["error"] = error.diagnosticLabel
            if case .pageRejected(let code) = error, code.isInputResourceRefusal {
                fields["resourceRefusalReason"] = code.rawValue
            }
        }
        sink.record(fields, critical: !succeeded && action != "captureTarget" && action != "observe")
    }

    func activeIdentity(requestID: String, check: String, route: String, started: TimeInterval, succeeded: Bool) {
        let fields: [String: Any] = ["event": "active_identity", "requestID": requestID,
            "check": check, "route": route, "elapsedMS": (ProcessInfo.processInfo.systemUptime - started) * 1000,
            "succeeded": succeeded, "authority": "DIAGNOSTIC_ONLY"]
        sink.record(fields)
    }

    private func addContext(_ context: CaptureInvocationContext?, to fields: inout [String: Any]) {
        guard let context else { return }
        fields["captureRequestID"] = context.requestID.uuidString
        fields["armAttemptID"] = context.armAttemptID.uuidString
        fields["hostEpoch"] = context.hostEpoch.uuidString
    }
}

/// Pure parser for the observed Chrome get-acTa result. Only a complete,
/// absolute tab-ID -> window-ID -> null object chain is a one-read identity.
/// Unsupported descriptor shapes return nil for the existing compatibility path.
enum ChromeActiveTabDescriptor {
    private static func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    static func identity(in descriptor: NSAppleEventDescriptor) -> (window: String, tab: String)? {
        guard let tab = fixedObject(descriptor, kind: "CrTb"),
              let window = fixedObject(tab.container, kind: "cwin"),
              window.container.descriptorType == code("null"), window.container.data.isEmpty else { return nil }
        return (window.id, tab.id)
    }

    private static func fixedObject(_ descriptor: NSAppleEventDescriptor, kind: String)
        -> (id: String, container: NSAppleEventDescriptor)? {
        let keys = Set([code("want"), code("form"), code("seld"), code("from")])
        guard descriptor.descriptorType == code("obj "), descriptor.numberOfItems == 4,
              Set((1...4).map { descriptor.keywordForDescriptor(at: $0) }) == keys,
              let want = descriptor.forKeyword(code("want")), want.descriptorType == code("type"),
              want.data.count == 4, want.typeCodeValue == code(kind),
              let form = descriptor.forKeyword(code("form")), form.descriptorType == code("enum"),
              form.data.count == 4, form.enumCodeValue == code("ID  "),
              let selector = descriptor.forKeyword(code("seld")), selector.descriptorType == code("utxt"),
              let text = selector.stringValue, !text.isEmpty, text.utf8.count <= 19,
              text.utf8.allSatisfy({ (48...57).contains($0) }), text.first != "0",
              let number = Int64(text), number > 0, String(number) == text,
              let container = descriptor.forKeyword(code("from")) else { return nil }
        return (text, container)
    }
}

/// Codes come from Chrome's installed scripting.sdef (Standard/Chromium suites),
/// not undocumented browser internals. Submission and identity reads retain the
/// five-second per-event timeout; receipt reads use their remaining one-second
/// budget. This never activates or sends a ChatGPT message. The URL setter
/// receives only a void JavaScript expression, not a navigation URL.
private struct ChromePIDEvents {
    let pid: pid_t
    let trace: ChromeBridgeTrace
    let requestID: String
    private func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    private func object(_ kind: String, form: String, key: NSAppleEventDescriptor,
                        container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
        record.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(key, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        guard let specifier = record.coerce(toDescriptorType: code("obj ")) else { throw WebAdapterError.nativeExecutionFailed }
        return specifier
    }

    private func property(_ name: String, of container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        try object("prop", form: "prop", key: .init(typeCode: code(name)), container: container)
    }

    private func send(_ suite: String, _ event: String, direct: NSAppleEventDescriptor,
                      javascript: String? = nil, value: String? = nil,
                      receiptBudget: MainWorldReceiptReadBudget? = nil) throws -> NSAppleEventDescriptor {
        let request = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(event),
            targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        request.setParam(direct, forKeyword: code("----"))
        if let javascript { request.setParam(.init(string: javascript), forKeyword: code("JvSc")) }
        if let value { request.setParam(.init(string: value), forKeyword: code("data")) }
        let timeout: TimeInterval
        if let receiptBudget {
            timeout = try receiptBudget.timeout(at: ProcessInfo.processInfo.systemUptime)
        } else { timeout = 5 }
        let reply: NSAppleEventDescriptor
        do { reply = try request.sendEvent(options: [.waitForReply], timeout: timeout) }
        catch {
            // Never surface the native localized description: it can contain
            // script source, user paths or page payload. A numeric OSStatus is
            // sufficient to distinguish denied Automation from timeout/transport.
            let native = error as NSError
            guard native.domain == NSOSStatusErrorDomain,
                  let status = Int32(exactly: native.code) else { throw WebAdapterError.nativeExecutionFailed }
            throw WebAdapterError.nativeEventFailed(status)
        }
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            throw WebAdapterError.nativeEventFailed(error.int32Value)
        }
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else {
            if value != nil { return .null() }
            throw WebAdapterError.nativeExecutionFailed
        }
        return result
    }

    private func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send("core", "getd", direct: object)
    }

    private func identifier(_ object: NSAppleEventDescriptor) throws -> String {
        guard let value = try get(property("ID  ", of: object)).stringValue,
              let number = Int64(value), number > 0 else { throw WebAdapterError.invalidTarget }
        return String(number)
    }

    func url(window: String, tab: String) throws -> String {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        guard let value = try get(property("URL ", of: tabObject)).stringValue else {
            throw WebAdapterError.invalidTarget
        }
        return value
    }

    func activeIdentity(check: String) throws -> (window: String, tab: String) {
        let started = ProcessInfo.processInfo.systemUptime
        var route = "descriptor_read_failed", succeeded = false
        defer { trace.activeIdentity(requestID: requestID, check: check, route: route, started: started, succeeded: succeeded) }
        let front = try object("cwin", form: "indx", key: .init(int32: 1))
        // One get resolves the front window's active tab to an absolute object
        // chain. Parse fields, never the descriptor's printable description.
        let snapshot = try get(property("acTa", of: front))
        if let identity = ChromeActiveTabDescriptor.identity(in: snapshot) {
            route = "descriptor_fast"; succeeded = true; return identity
        }
        route = "legacy_fallback"
        // Older/unsupported Chrome shapes retain the previous three-read path.
        // A transport error above propagates; it is not an automatic resend.
        let windowID = try identifier(front)
        // Resolve the tab from the captured window, not a second front-window read.
        let window = try object("cwin", form: "ID  ", key: .init(string: windowID))
        let active = try get(property("acTa", of: window))
        let tabID = try identifier(active)
        succeeded = true
        return (windowID, tabID)
    }

    func execute(_ source: String, window: String, tab: String,
                 receiptBudget: MainWorldReceiptReadBudget) throws -> String {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        guard let result = try send("CrSu", "ExJa", direct: tabObject, javascript: source,
                                    receiptBudget: receiptBudget).stringValue else {
            throw WebAdapterError.nativeExecutionFailed
        }
        return result
    }

    func dispatchMainWorld(_ source: String, window: String, tab: String) throws {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        guard try send("CrSu", "ExJa", direct: tabObject, javascript: source).stringValue == "submitted" else {
            throw WebAdapterError.nativeExecutionFailed
        }
    }

    func submitMainWorld(_ source: String, window: String, tab: String) throws {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        // URL parsing strips literal line breaks (which would turn // comments
        // into the remainder of the program). Encode source before that parser.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = ("void(" + source + ")").addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw WebAdapterError.invalidRequest
        }
        _ = try send("core", "setd", direct: property("URL ", of: tabObject), value: "javascript:" + encoded)
    }
}
