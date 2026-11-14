import AppKit
import ApplicationServices
import Foundation

// Operate only the two processes launched by this test, on a disposable hosted console.
let args = CommandLine.arguments
let env = ProcessInfo.processInfo.environment
guard env["GITHUB_ACTIONS"] == "true", env["RUNNER_ENVIRONMENT"] == "github-hosted",
      env["GITHUB_REPOSITORY"] == "haohongfei2001-png/Riftlet", args.count >= 2 else { exit(77) }
if args[1] == "preflight" {
    guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
        print("MISSING_EXISTING_AX_OR_SCREEN_PERMISSION")
        exit(77)
    }
    guard ["com.riftlet.app", "com.microsoft.edgemac"].allSatisfy({
        NSRunningApplication.runningApplications(withBundleIdentifier: $0).allSatisfy(\.isTerminated)
    }) else { print("AN_EXISTING_HOST_IS_RUNNING"); exit(77) }
    exit(0)
}
if ["productPID", "quitProduct"].contains(args[1]) {
    guard args.count == 3 else { exit(64) }
    let url = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath().standardizedFileURL
    let matches = NSRunningApplication.runningApplications(withBundleIdentifier: "com.riftlet.app")
        .filter { !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == url }
    guard matches.count == 1, let product = matches.first else { exit(2) }
    if args[1] == "quitProduct" {
        guard product.terminate() else { exit(1) }
    }
    print(product.processIdentifier)
    exit(0)
}
guard args.count == 8, let expectedWindow = CGWindowID(args[7]), let edgePID = Int32(args[2]), let productPID = Int32(args[3]),
      let row = Int(args[6]), (0...2).contains(row),
      let edge = NSRunningApplication(processIdentifier: edgePID),
      edge.bundleIdentifier == "com.microsoft.edgemac", !edge.isTerminated, edge.launchDate != nil,
      edge.bundleURL?.resolvingSymlinksInPath().path == "/Applications/Microsoft Edge.app",
      let app = NSRunningApplication(processIdentifier: productPID),
      app.bundleIdentifier == "com.riftlet.app", !app.isTerminated, app.launchDate != nil,
      app.bundleURL?.resolvingSymlinksInPath().path == args[4] else { exit(1) }

func ownedWindow() -> CGWindowID? {
    guard NSWorkspace.shared.frontmostApplication == edge,
          let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] else { return nil }
    let own = windows.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == edgePID && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    guard own.count == 1, let window = own.first, let name = window[kCGWindowName as String] as? String,
          name == args[5] || name.hasPrefix(args[5] + " - ") || name.hasPrefix(args[5] + " – ") else { return nil }
    return window[kCGWindowNumber as String] as? CGWindowID
}

func attribute(_ node: AXUIElement, _ name: String) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(node, name as CFString, &result) == .success else { return nil }
    return result
}
func array(_ node: AXUIElement, _ name: String) -> [AXUIElement] {
    (attribute(node, name) as? [AXUIElement]) ?? []
}

func pendingRow(_ number: Int) -> AXUIElement? {
    let application = AXUIElementCreateApplication(productPID)
    var queue = array(application, kAXWindowsAttribute)
    queue.append(contentsOf: array(application, kAXChildrenAttribute))
    var seen: [AXUIElement] = []
    var matches: [AXUIElement] = []
    while let node = queue.popLast() {
        if seen.contains(where: { CFEqual($0, node) }) { continue }
        guard seen.count < 768 else { return nil }
        seen.append(node)
        var pid: pid_t = -1
        guard AXUIElementGetPid(node, &pid) == .success, pid == productPID else { continue }
        if attribute(node, kAXRoleAttribute) as? String == kAXButtonRole,
           [kAXDescriptionAttribute, kAXTitleAttribute].contains(where: {
               attribute(node, $0) as? String == "截图 \(number)，可附加"
           }), attribute(node, kAXEnabledAttribute) as? Bool != false {
            matches.append(node)
        }
        queue.append(contentsOf: array(node, kAXChildrenAttribute))
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
}

switch args[1] {
case "activate":
    guard edge.activate(options: []) else { exit(2) }
case "window":
    guard let id = ownedWindow() else { exit(2) }
    print(id)
case "ready", "press":
    guard expectedWindow != 0, ownedWindow() == expectedWindow, AXIsProcessTrusted(), row > 0, let button = pendingRow(row) else { exit(2) }
    var actions: CFArray?
    guard AXUIElementCopyActionNames(button, &actions) == .success,
          (actions as? [String])?.contains(kAXPressAction) == true else { exit(5) }
    guard args[1] == "press" else { exit(0) }
    guard ownedWindow() == expectedWindow else { exit(2) }
    // Never retry after entering AXUIElementPerformAction, including a missing reply.
    guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { exit(3) }
    guard ownedWindow() == expectedWindow else { exit(4) }
default: exit(64)
}
