import AppKit
import Carbon
@testable import RiftletAdapters

// Verify a challenge loaded by the official browser client, independently in
// the native process. The protocol never returns a page URL, title or content.
@main
enum Marker {
    enum Failure: Error { case mismatch }
    static func code(_ value: String) -> UInt32 { value.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    static func object(_ kind: String, _ form: String, _ key: NSAppleEventDescriptor,
                       in parent: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
        record.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(key, forKeyword: code("seld"))
        record.setDescriptor(parent, forKeyword: code("from"))
        guard let result = record.coerce(toDescriptorType: code("obj ")) else { throw Failure.mismatch }
        return result
    }

    static func run(_ args: [String]) throws {
        guard args.count == 8, ["sample", "activate-owned"].contains(args[0]),
              let appName = ["com.google.Chrome": "Google Chrome", "com.microsoft.edgemac": "Microsoft Edge"][args[1]],
              let pid = Int32(args[2]), let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == args[1], app.bundleURL?.standardizedFileURL.path == "/Applications/" + appName + ".app",
              let identity = ChromeProcessIdentity.read(pid: pid, applicationID: args[1]), identity.session == args[3],
              let window = Int32(args[4]), window > 0, let tab = Int32(args[5]), tab > 0,
              let url = URLComponents(string: args[6]), url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.range(of: "^/[0-9a-f]{48}/$", options: .regularExpression) != nil,
              UUID(uuidString: args[7]) != nil else { throw Failure.mismatch }
        func get(_ receiver: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(eventClass: code("core"), eventID: code("getd"),
                targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
            event.setParam(receiver, forKeyword: keyDirectObject)
            let reply = try event.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: 0.8)
            guard reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0 == 0,
                  let value = reply.paramDescriptor(forKeyword: keyDirectObject) else { throw Failure.mismatch }
            return value
        }
        let front = try object("cwin", "indx", .init(int32: 1))
        let active = try object("prop", "prop", .init(typeCode: code("acTa")), in: front)
        let fixedWindow = try object("cwin", "ID  ", .init(string: args[4]))
        let fixedTab = try object("CrTb", "ID  ", .init(string: args[5]), in: fixedWindow)
        let address = try object("prop", "prop", .init(typeCode: code("URL ")), in: fixedTab)
        func verify() throws {
            guard identity.isCurrent(), let ids = ChromeActiveTabDescriptor.identity(in: try get(active)),
                  ids.window == args[4], ids.tab == args[5], try get(address).stringValue == args[6]
            else { throw Failure.mismatch }
        }
        try verify()
        if args[0] == "activate-owned" && !app.isActive {
            // Activate only after the front tab in this exact process returned
            // the fresh loopback challenge. Browser input stays in Browser RPC.
            guard app.activate(options: [.activateIgnoringOtherApps]) else { throw Failure.mismatch }
            let until = ProcessInfo.processInfo.systemUptime + 1
            while !app.isActive && ProcessInfo.processInfo.systemUptime < until {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025))
            }
        }
        try verify()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let row: [String: Any] = ["bundle": args[1], "sessionID": identity.session, "windowID": args[4],
            "tabID": args[5], "doc": args[7], "exactLocalMarker": true,
            "observedUTC": iso.string(from: Date()), "systemForeground": NSWorkspace.shared.frontmostApplication?.processIdentifier == pid]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: row))
    }
    static func main() {
        do { try run(Array(CommandLine.arguments.dropFirst())) }
        catch { FileHandle.standardError.write(Data("ORIGINAL_NATIVE_MARKER_UNAVAILABLE\n".utf8)); exit(1) }
    }
}
