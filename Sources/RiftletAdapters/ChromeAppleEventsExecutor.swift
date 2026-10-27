import AppKit
import Foundation
import RiftletCore

/// Native Apple Events transport; selectors and completion rules stay in the
/// reviewed page program. Events address the exact PID, never an ambiguous
/// bundle-ID lookup when several Chrome profile processes are running.
@MainActor
public final class ChromeAppleEventsExecutor: WebBridgeExecutor {
    private static let scriptQueue = DispatchQueue(label: "com.riftlet.apple-events", qos: .utility)

    public init() {}

    public func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        let browserID = "com.google.Chrome"
        let application: NSRunningApplication
        if command.action == .captureTarget {
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.bundleIdentifier == browserID else { throw WebAdapterError.browserNotFrontmost }
            application = frontmost
        } else {
            guard let target = command.target, target.applicationID == browserID,
                  let running = NSRunningApplication.runningApplications(withBundleIdentifier: browserID).first(where: {
                      guard let launch = $0.launchDate else { return false }
                      return "\($0.processIdentifier):\(launch.timeIntervalSince1970)" == target.sessionID
                  }) else { throw WebAdapterError.invalidTarget }
            application = running
        }
        guard let launched = application.launchDate else { throw WebAdapterError.invalidTarget }
        let pid = application.processIdentifier
        let session = "\(pid):\(launched.timeIntervalSince1970)"
        let requiresForeground = command.action != .observe && command.action != .discard
        if requiresForeground {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                throw WebAdapterError.browserNotFrontmost
            }
        }
        if command.action != .captureTarget {
            guard let target = command.target, target.sessionID == session,
                  let windowID = Int64(target.windowID), windowID > 0,
                  let tab = target.tabID, let tabID = Int64(tab), tabID > 0 else {
                throw WebAdapterError.invalidTarget
            }
        }
        let commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        let sessionJSON = String(decoding: try JSONEncoder().encode(session), as: UTF8.self)
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            Self.scriptQueue.async {
                let result: Result<Data, Error> = Result {
                    try autoreleasepool {
                        // Recheck process lifetime after waiting for the shared serial
                        // queue. An old lease cannot target a newly reused PID.
                        guard let running = NSRunningApplication(processIdentifier: pid),
                              running.bundleIdentifier == browserID, running.launchDate == launched else {
                            throw WebAdapterError.invalidTarget
                        }
                        let bridge = ChromePIDEvents(pid: pid)
                        if requiresForeground, try !bridge.frontmost() { throw WebAdapterError.browserNotFrontmost }
                        let selected: (window: String, tab: String)
                        if command.action == .captureTarget {
                            selected = try bridge.activeIdentity()
                        } else {
                            guard let target = command.target, let tab = target.tabID else { throw WebAdapterError.invalidTarget }
                            selected = (target.windowID, tab)
                            if requiresForeground {
                                let active = try bridge.activeIdentity()
                                guard active.window == selected.window, active.tab == selected.tab else {
                                    throw WebAdapterError.invalidTarget
                                }
                            }
                        }
                        let context = "{applicationID:\"\(browserID)\",sessionID:\(sessionJSON),windowID:\"\(selected.window)\",tabID:\"\(selected.tab)\"}"
                        // Chrome's execute-JavaScript event is isolated-world. The
                        // observed composer business identity lives in MAIN. Submit
                        // exactly once, then only read its nonce-bound DOM receipt.
                        let envelope = MainWorldCommandEnvelope(function: program.functionSource,
                            commandJSON: commandJSON, contextJSON: context)
                        try bridge.submitMainWorld(envelope.source, window: selected.window, tab: selected.tab)
                        let deadline = ProcessInfo.processInfo.systemUptime + 1
                        var reply = ""
                        repeat {
                            reply = try bridge.execute(envelope.reader, window: selected.window, tab: selected.tab)
                            if !reply.isEmpty { break }
                            Thread.sleep(forTimeInterval: 0.02)
                        } while ProcessInfo.processInfo.systemUptime < deadline
                        // Missing/late reply never resubmits an input command.
                        let text = try envelope.decode(reply)
                        guard text.utf8.count <= ObservationDecoder.maximumPayloadBytes else { throw WebAdapterError.invalidReply }
                        return Data(text.utf8)
                    }
                }
                continuation.resume(with: result)
            }
        }
        if command.action == .captureTarget {
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.processIdentifier == pid, frontmost.launchDate == launched else {
                throw WebAdapterError.browserNotFrontmost
            }
        }
        return data
    }
}

/// Codes come from Chrome's installed scripting.sdef (Standard/Chromium suites),
/// not undocumented browser internals. This preserves the existing five-second
/// per-event timeout and never activates or sends a ChatGPT message. The URL
/// setter receives only a void JavaScript expression, not a navigation URL.
private struct ChromePIDEvents {
    let pid: pid_t
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
                      javascript: String? = nil, value: String? = nil) throws -> NSAppleEventDescriptor {
        let request = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(event),
            targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        request.setParam(direct, forKeyword: code("----"))
        if let javascript { request.setParam(.init(string: javascript), forKeyword: code("JvSc")) }
        if let value { request.setParam(.init(string: value), forKeyword: code("data")) }
        let reply: NSAppleEventDescriptor
        do { reply = try request.sendEvent(options: [.waitForReply], timeout: 5) }
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

    func frontmost() throws -> Bool { try get(property("pisf")).booleanValue }

    func activeIdentity() throws -> (window: String, tab: String) {
        let front = try object("cwin", form: "indx", key: .init(int32: 1))
        let windowID = try identifier(front)
        // Resolve the tab from the captured window, not a second front-window read.
        let window = try object("cwin", form: "ID  ", key: .init(string: windowID))
        let active = try get(property("acTa", of: window))
        return (windowID, try identifier(active))
    }

    func execute(_ source: String, window: String, tab: String) throws -> String {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        guard let result = try send("CrSu", "ExJa", direct: tabObject, javascript: source).stringValue else {
            throw WebAdapterError.nativeExecutionFailed
        }
        return result
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
