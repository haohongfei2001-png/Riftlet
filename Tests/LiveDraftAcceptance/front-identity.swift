import AppKit
import Carbon
@testable import RiftletAdapters

// Read-only sibling of the browser client. Its sole event is 'getd' on the
// front window's active tab, which returns object IDs without URL or title.
@main
struct FrontIdentity {
    enum Failure: Error { case unavailable }
    static func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    static func object(_ kind: String, _ form: String, _ selector: NSAppleEventDescriptor,
                       _ parent: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
        record.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(selector, forKeyword: code("seld"))
        record.setDescriptor(parent, forKeyword: code("from"))
        guard let result = record.coerce(toDescriptorType: code("obj ")) else { throw Failure.unavailable }
        return result
    }

    static func sample(_ bundle: String) throws -> [String:String] {
        guard ["com.google.Chrome", "com.microsoft.edgemac"].contains(bundle),
              let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundle,
              let process = ChromeProcessIdentity.read(pid: front.processIdentifier, applicationID: bundle)
        else { throw Failure.unavailable }
        let window = try object("cwin", "indx", .init(int32: 1))
        let active = try object("prop", "prop", .init(typeCode: code("acTa")), window)
        let request = NSAppleEventDescriptor(eventClass: code("core"), eventID: code("getd"),
                                            targetDescriptor: .init(processIdentifier: process.pid),
                                            returnID: -1, transactionID: 0)
        request.setParam(active, forKeyword: keyDirectObject)
        let reply = try request.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: 0.25)
        guard reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0 == 0,
              let value = reply.paramDescriptor(forKeyword: keyDirectObject),
              let ids = ChromeActiveTabDescriptor.identity(in: value),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == process.pid, process.isCurrent()
        else { throw Failure.unavailable }
        return ["bundle":bundle, "sessionID":process.session, "windowID":ids.window, "tabID":ids.tab]
    }

    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else { throw Failure.unavailable }
            let data = try JSONSerialization.data(withJSONObject: sample(CommandLine.arguments[1]))
            FileHandle.standardOutput.write(data)
        } catch {
            FileHandle.standardError.write(Data("NATIVE_FRONT_OBSERVER_UNAVAILABLE\n".utf8))
            exit(1)
        }
    }
}
