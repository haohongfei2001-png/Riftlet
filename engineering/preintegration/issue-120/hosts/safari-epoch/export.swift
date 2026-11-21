// Link this fixture exporter to the exact RiftletAdapters source under test.
import AppKit
import CoreGraphics
@testable import RiftletAdapters

// A WindowServer window number is only an observation. It cannot bind a tab,
// document or editable draft. Keep process/window numbers local to the runner.
@MainActor func observeNativeWindow() -> Never {
    let safari = "com.apple.Safari"
    guard let before = CandidateReceiver.foreground(safari),
          let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] else { exit(3) }
    let ids = info.compactMap { item -> UInt32? in
        guard (item[kCGWindowOwnerPID as String] as? Int32) == before.birth.pid,
              (item[kCGWindowLayer as String] as? Int) == 0 else { return nil }
        return item[kCGWindowNumber as String] as? UInt32
    }
    guard ids.count == 1, CandidateReceiver.foreground(safari) == before else { exit(3) }
    print("\(before.session)/\(ids[0])")
    exit(0)
}

if CommandLine.arguments.dropFirst() == ["--native-window"] {
    MainActor.assumeIsolated { observeNativeWindow() }
}

let address = CommandLine.arguments[1]
guard let url = URL(string: address), url.scheme == "http", url.host == "127.0.0.1",
      url.port != nil, url.path == "/fixture", url.query != nil else { exit(2) }

let encoder = JSONEncoder()
func literal(_ string: String) throws -> String {
    String(decoding: try encoder.encode(string), as: UTF8.self)
}

// Only the host fence is exercised. No provider selector or input runs here.
let probe = "({inspect: () => 'probe_ran'})"
var members = [String]()
for scenario in ["original", "editor", "afterEditor", "history", "afterHistory", "reload", "newDocument"] {
    let pin = ProviderDiscoveryPin(id: UUID())
    let bind = try pin.bind(address: address)
    members.append("\(try literal(scenario)): {bind: () => (\(bind)), read: () => (\(pin.read(program: probe)))}")
}
print("const fence = {" + members.joined(separator: ",\n") + "};")
