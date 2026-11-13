// Built only by verify.py, outside the app. Takes an ephemeral fixture configuration on stdin.
import AppKit
import Carbon
import Foundation

struct FixtureImage: Decodable {
    let operation: String
    let bytes: String
}
struct FixtureConfig: Decodable {
    let address: String
    let pid: pid_t
    let images: [FixtureImage]
}
enum FixtureError: Error { case malformed, documentChanged, unexpectedInput, unknown }

func quoted(_ value: String) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}

func runFixture() throws {
    let config = try JSONDecoder().decode(FixtureConfig.self, from: FileHandle.standardInput.readDataToEndOfFile())
    guard CommandLine.arguments.count == 2, config.pid > 0,
          let url = URLComponents(string: config.address), url.scheme == "http", url.host == "127.0.0.1",
          url.port != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
          url.path.range(of: #"^/draft/[0-9a-f]{32}$"#, options: .regularExpression) != nil,
          config.images.count == 2, config.images[0].operation != config.images[1].operation,
          config.images.allSatisfy({ $0.operation.range(of: #"^[0-9a-f]{32}$"#, options: .regularExpression) != nil &&
              $0.bytes.count < 1024 && Data(base64Encoded: $0.bytes)?.starts(with: [137,80,78,71,13,10,26,10]) == true })
    else { throw FixtureError.malformed }
    // Never address another Edge process (including a real profile) when headless Edge
    // has no foreground NSRunningApplication. No requesting consent or activating it.
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == config.pid else {
        throw EdgeHostError.notFrontmost
    }
    let host = EdgeApplicationHost()
    let lease = try host.freeze()
    guard lease.process.pid == config.pid, lease.address == config.address else { throw EdgeHostError.changed }
    let program = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    for image in config.images {
        func call(_ action: String) throws -> String {
            let arguments = try [action, config.address, image.operation, action == "commit" ? image.bytes : ""].map(quoted)
            return try EdgeJavaScriptEvent.send("(\n" + program + "\n)(" + arguments.joined(separator: ",") + ")", to: lease, using: host)
        }
        guard try call("capture") == "bound" else { throw FixtureError.documentChanged }
        // Once entered, a native timeout or rejected reply exits without another input.
        guard try call("commit") == "input-entered" else { throw FixtureError.unexpectedInput }
        let until = ProcessInfo.processInfo.systemUptime + 3
        var observed = false
        repeat {
            observed = try call("observe") == "attached"
            if !observed { Thread.sleep(forTimeInterval: 0.05) }
        } while !observed && ProcessInfo.processInfo.systemUptime < until
        guard observed else { throw FixtureError.unknown }
    }
    print("CONTROLLED_AE_INPUT_OBSERVED")
}

do { try runFixture() }
catch EdgeHostError.notFrontmost { print("NOT_RUN_HEADLESS_PROCESS_NOT_FOREGROUND"); exit(77) }
catch EdgeHostError.automation(let code) { print("EDGE_AUTOMATION_OSSTATUS_\(code)"); exit(77) }
catch { print("EDGE_NATIVE_ROUTE_OR_RECEIPT_UNVERIFIED"); exit(1) }
