import AppKit
import Carbon

/// An ephemeral click-time address. Keep the address in memory; URLs can contain private draft IDs.
struct EdgeWindowTab: Equatable {
    let process: KernelProcessBirth
    let windowID: String
    let tabID: String
    let address: String

    var sessionID: String { "edge-kernel-v1:\(process.pid):\(process.seconds):\(process.microseconds)" }
}

enum EdgeHostError: Error, Equatable {
    case notFrontmost, changed, unsupportedDescriptor, automation(OSStatus)
}

/// Read-only host candidate. A window title, a URL, or a previously foreground browser
/// can never select a target. All events address a specific process on this launch.
struct EdgeApplicationHost: ApplicationHostAdapter {
    static let bundleID = "com.microsoft.edgemac"
    private let frontmost: () -> KernelProcessBirth?
    private let selected: (pid_t) throws -> (window: String, tab: String)
    private let address: (pid_t, String, String) throws -> String

    init() {
        self.init(frontmost: {
            guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
                  app.bundleIdentifier == Self.bundleID,
                  let birth = KernelProcessBirth.read(pid: app.processIdentifier),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == birth.pid,
                  NSRunningApplication(processIdentifier: birth.pid)?.bundleIdentifier == Self.bundleID,
                  KernelProcessBirth.read(pid: birth.pid) == birth else { return nil }
            return birth
        }, selected: EdgeReadEvents.activeTab, address: EdgeReadEvents.address)
    }

    init(frontmost: @escaping () -> KernelProcessBirth?,
         selected: @escaping (pid_t) throws -> (window: String, tab: String),
         address: @escaping (pid_t, String, String) throws -> String) {
        self.frontmost = frontmost
        self.selected = selected
        self.address = address
    }

    func freeze() throws -> EdgeWindowTab {
        guard let process = frontmost() else { throw EdgeHostError.notFrontmost }
        return try freeze(process)
    }

    private func freeze(_ process: KernelProcessBirth) throws -> EdgeWindowTab {
        guard frontmost() == process else { throw EdgeHostError.changed }
        let selection = try selected(process.pid)
        let url = try address(process.pid, selection.window, selection.tab)
        guard !url.isEmpty, try selected(process.pid) == selection, frontmost() == process else {
            throw EdgeHostError.changed
        }
        return EdgeWindowTab(process: process, windowID: selection.window, tabID: selection.tab, address: url)
    }

    func revalidate(_ original: EdgeWindowTab) throws {
        // Reject immediately on process switch, before reading any other receiver.
        guard try freeze(original.process) == original else { throw EdgeHostError.changed }
    }
}

/// Codes independently verified against the Edge app's own Contents/Resources/scripting.sdef.
/// The shared parser accepts only absolute tab-id -> window-id -> null descriptors.
enum EdgeReadEvents {
    static func code(_ value: String) -> UInt32 { value.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private static func object(kind: String, form: String, key: NSAppleEventDescriptor,
                               container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let descriptor = NSAppleEventDescriptor.record()
        descriptor.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
        descriptor.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
        descriptor.setDescriptor(key, forKeyword: code("seld"))
        descriptor.setDescriptor(container, forKeyword: code("from"))
        guard let result = descriptor.coerce(toDescriptorType: code("obj ")) else {
            throw EdgeHostError.unsupportedDescriptor
        }
        return result
    }

    static func tab(window: String, id: String) throws -> NSAppleEventDescriptor {
        let parent = try object(kind: "cwin", form: "ID  ", key: .init(string: window))
        return try object(kind: "CrTb", form: "ID  ", key: .init(string: id), container: parent)
    }

    private static func read(pid: pid_t, property: String, of container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let receiver = NSAppleEventDescriptor(processIdentifier: pid)
        let status = AEDeterminePermissionToAutomateTarget(receiver.aeDesc, code("core"), code("getd"), false)
        guard status == noErr else { throw EdgeHostError.automation(status) }
        let event = NSAppleEventDescriptor(eventClass: code("core"), eventID: code("getd"),
                                           targetDescriptor: receiver, returnID: -1, transactionID: 0)
        event.setParam(try object(kind: "prop", form: "prop", key: .init(typeCode: code(property)),
                                  container: container), forKeyword: code("----"))
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1)
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            throw EdgeHostError.automation(error.int32Value)
        }
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else {
            throw EdgeHostError.unsupportedDescriptor
        }
        return result
    }

    static func activeTab(pid: pid_t) throws -> (window: String, tab: String) {
        let front = try object(kind: "cwin", form: "indx", key: .init(int32: 1))
        let descriptor = try read(pid: pid, property: "acTa", of: front)
        guard let selection = ChromeActiveTabDescriptor.identity(in: descriptor) else {
            throw EdgeHostError.unsupportedDescriptor
        }
        return selection
    }

    static func address(pid: pid_t, window: String, tab id: String) throws -> String {
        guard let value = try read(pid: pid, property: "URL ", of: tab(window: window, id: id)).stringValue else {
            throw EdgeHostError.unsupportedDescriptor
        }
        return value
    }
}
