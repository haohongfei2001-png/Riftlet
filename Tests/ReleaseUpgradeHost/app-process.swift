import AppKit
import ApplicationServices
import Foundation

// The driver asks only about the exact ordinary App it installed on the disposable host.
let arguments = CommandLine.arguments
guard arguments.count == 3, ["pid", "quit", "onboarding"].contains(arguments[1]) else { exit(64) }
let appURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
let matches = NSRunningApplication.runningApplications(withBundleIdentifier: "com.riftlet.app")
    .filter { $0.bundleURL?.standardizedFileURL == appURL && !$0.isTerminated }
guard matches.count == 1, let app = matches.first else { exit(2) }
if arguments[1] == "onboarding" {
    guard AXIsProcessTrusted() else { print("AX_NOT_AVAILABLE"); exit(0) }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { print("AX_NOT_AVAILABLE"); exit(0) }
    let presented = windows.contains { window in
        var id: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXIdentifierAttribute as CFString, &id) == .success
            && (id as? String) == "RiftletOnboarding"
    }
    print(presented ? "OBSERVED" : "WINDOW_MISSING")
    exit(0)
}
if arguments[1] == "quit" {
    guard app.terminate() else { exit(3) }
    let deadline = Date().addingTimeInterval(12)
    while !app.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard app.isTerminated else { exit(4) }
}
print(app.processIdentifier)
