import AppKit
import Carbon
import Foundation

/// Native routing is specific to each browser's installed scripting dictionary.
/// All hosts share the same original-document lease, one-shot transfer and receipt reader.
protocol BrowserTabEvents: Sendable {
    var pid: pid_t { get }
    var clickDeadline: ChromeClickDeadline? { get }
    func clickRoute(deadline: ChromeClickDeadline) throws -> ChromeClickRoute
    func activeIdentity(check: String) throws -> (window: String, tab: String)
    func requireSelection(window: String, tab: String, check: String) throws
    func url(window: String, tab: String) throws -> String
    func selectForHistory(window: String, tab: String) throws
    func enqueueWitness(_ source: String, route: ChromeClickRoute, deadline: ChromeClickDeadline) throws -> ChromeClickSnapshot.WitnessReply
    func confirmWitness(_ reply: ChromeClickSnapshot.WitnessReply, before deadline: ChromeClickDeadline) throws -> Bool
    func execute(_ source: String, window: String, tab: String, receiptBudget: MainWorldReceiptReadBudget?) throws -> String
    func dispatchMainWorld(_ source: String, window: String, tab: String) throws
    func submitMainWorld(_ source: String, window: String, tab: String) throws
    func connectionProbe(stillCurrent: () -> Bool) throws -> String
}

extension BrowserTabEvents {
    func requireSelection(window: String, tab: String, check: String) throws {
        let current = try activeIdentity(check: check)
        guard current.window == window, current.tab == tab else { throw WebAdapterError.nativeSelectionChanged }
    }

    func confirmWitness(_ reply: ChromeClickSnapshot.WitnessReply, before deadline: ChromeClickDeadline) throws -> Bool {
        try reply.boundWithinClick(before: deadline)
    }

    func connectionProbe(stillCurrent: () -> Bool) throws -> String {
        let route = try activeIdentity(check: "setup")
        guard stillCurrent() else { throw WebAdapterError.invalidTarget }
        return try execute("'Riftlet'", window: route.window, tab: route.tab,
                           receiptBudget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 3))
    }

    func execute(_ source: String, window: String, tab: String) throws -> String {
        try execute(source, window: window, tab: tab, receiptBudget: nil)
    }

    func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    func object(_ kind: String, form: String, key: NSAppleEventDescriptor,
                        container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
        record.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(key, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        guard let specifier = record.coerce(toDescriptorType: code("obj ")) else { throw WebAdapterError.nativeExecutionFailed }
        return specifier
    }

    func property(_ name: String, of container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        try object("prop", form: "prop", key: .init(typeCode: code(name)), container: container)
    }

    func send(_ suite: String, _ event: String, direct: NSAppleEventDescriptor,
                      javascript: String? = nil, value: String? = nil, integer: Int32? = nil,
                      receiptBudget: MainWorldReceiptReadBudget? = nil) throws -> NSAppleEventDescriptor {
        let request = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(event),
            targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        request.setParam(direct, forKeyword: code("----"))
        if let javascript { request.setParam(.init(string: javascript), forKeyword: code("JvSc")) }
        if let integer { request.setParam(.init(int32: integer), forKeyword: code("data")) }
        if let value { request.setParam(.init(string: value), forKeyword: code("data")) }
        return try send(request, permitsMissingResult: value != nil || integer != nil, receiptBudget: receiptBudget)
    }

    func send(_ request: NSAppleEventDescriptor, permitsMissingResult: Bool = false,
              receiptBudget: MainWorldReceiptReadBudget? = nil) throws -> NSAppleEventDescriptor {
        let timeout: TimeInterval
        if let receiptBudget {
            timeout = try receiptBudget.timeout(at: ProcessInfo.processInfo.systemUptime)
        } else if let clickDeadline {
            timeout = try clickDeadline.timeout()
        } else { timeout = 5 }
        let reply: NSAppleEventDescriptor
        do { reply = try request.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: timeout) }
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
            if permitsMissingResult { return .null() }
            throw WebAdapterError.nativeExecutionFailed
        }
        return result
    }

    func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send("core", "getd", direct: object)
    }

    func identifier(_ object: NSAppleEventDescriptor) throws -> String {
        guard let value = try get(property("ID  ", of: object)).stringValue,
              let number = Int64(value), number > 0 else { throw WebAdapterError.invalidTarget }
        return String(number)
    }
}
