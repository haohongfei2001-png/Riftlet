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
let edgeBundle = URL(fileURLWithPath: "/Applications/Microsoft Edge.app").resolvingSymlinksInPath().standardizedFileURL
func birth(_ app: NSRunningApplication) -> Int64? {
    app.launchDate.map { Int64($0.timeIntervalSince1970 * 1_000_000) }
}
func verifiedEdge(_ app: NSRunningApplication) -> Bool {
    guard let executable = app.executableURL?.resolvingSymlinksInPath().standardizedFileURL,
          let expected = Bundle(url: edgeBundle)?.executableURL?.resolvingSymlinksInPath().standardizedFileURL
          else { return false }
    return !app.isTerminated && app.bundleIdentifier == "com.microsoft.edgemac"
        && app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == edgeBundle.path
        && executable.path == expected.path
}
if args[1] == "launchEdge" {
    guard args.count == 4, let runner = env["RUNNER_TEMP"],
          let link = URLComponents(string: args[3]), link.scheme == "http", link.host == "127.0.0.1",
          link.port != nil, link.query == nil, link.fragment == nil, link.user == nil, link.password == nil,
          link.path.range(of: #"^/RiftletNeutral[a-f0-9]{32}$"#, options: .regularExpression) != nil else { exit(64) }
    let profile = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath().standardizedFileURL
    let scratch = profile.deletingLastPathComponent()
    guard profile.lastPathComponent == "edge", !FileManager.default.fileExists(atPath: profile.path),
          scratch.lastPathComponent.hasPrefix("riftlet-edge-host-"),
          scratch.deletingLastPathComponent().standardizedFileURL.path
            == URL(fileURLWithPath: runner).resolvingSymlinksInPath().standardizedFileURL.path,
          NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.edgemac").isEmpty else { exit(18) }
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.activates = true
    config.arguments = ["--user-data-dir=" + profile.path, "--disable-extensions", "--no-first-run",
        "--no-default-browser-check", "--no-proxy-server", "--disable-background-networking", "--disable-sync",
        "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1", "--app=" + args[3]]
    NSWorkspace.shared.openApplication(at: edgeBundle, configuration: config) { launched, error in
        if let error = error as NSError? { print(error.code); exit(19) }
        guard let launched, verifiedEdge(launched), let stamp = birth(launched) else { exit(20) }
        print("\(launched.processIdentifier) \(stamp)")
        exit(0)
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 18))
    exit(21)
}
if args[1] == "quitEdge" {
    guard args.count == 4, let pid = Int32(args[2]), let stamp = Int64(args[3]) else { exit(64) }
    guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { exit(0) }
    guard verifiedEdge(app), birth(app) == stamp else { exit(11) }
    guard app.terminate() else { exit(22) }
    let deadline = Date(timeIntervalSinceNow: 8)
    while !app.isTerminated && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    exit(app.isTerminated ? 0 : 23)
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
guard args.count == 9, let expectedWindow = CGWindowID(args[7]), let edgePID = Int32(args[2]),
      let productPID = Int32(args[3]), let stamp = Int64(args[8]), let row = Int(args[6]), (0...2).contains(row)
      else { exit(64) }
guard let edge = NSRunningApplication(processIdentifier: edgePID), !edge.isTerminated else { exit(10) }
guard verifiedEdge(edge), birth(edge) == stamp else { exit(11) }
guard let app = NSRunningApplication(processIdentifier: productPID), !app.isTerminated else { exit(12) }
guard app.bundleIdentifier == "com.riftlet.app", app.launchDate != nil,
      app.bundleURL?.resolvingSymlinksInPath().path == args[4] else { exit(13) }

func ownedWindow(requireFront: Bool = true, status: inout String) -> CGWindowID? {
    if requireFront && NSWorkspace.shared.frontmostApplication?.processIdentifier != edgePID {
        status = "EDGE_NOT_FRONTMOST"
        return nil
    }
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]]
        else { status = "WINDOWSERVER_LIST_UNAVAILABLE"; return nil }
    let own = windows.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == edgePID && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    guard own.count == 1, let window = own.first else {
        status = own.isEmpty ? "NO_EDGE_NORMAL_WINDOW" : "MULTIPLE_EDGE_NORMAL_WINDOWS"
        return nil
    }
    guard let name = window[kCGWindowName as String] as? String, !name.isEmpty
        else { status = "ORIGINAL_WINDOW_TITLE_UNAVAILABLE"; return nil }
    guard name == args[5] || name.hasPrefix(args[5] + " - ") || name.hasPrefix(args[5] + " – ")
        else { status = "NEUTRAL_DOCUMENT_TITLE_NOT_VISIBLE"; return nil }
    status = "WINDOW_NUMBER_UNAVAILABLE"
    return window[kCGWindowNumber as String] as? CGWindowID
}
func ownedWindow() -> CGWindowID? {
    var status = ""
    return ownedWindow(requireFront: true, status: &status)
}

// WindowServer returns front-to-back order. Decline if any visible window
// intersects the entire capture rectangle before the exact neutral Edge window.
func unobscuredContentRegion() -> CGRect? {
    guard expectedWindow != 0, ownedWindow() == expectedWindow, CGPreflightScreenCaptureAccess(),
          let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]],
          let own = entries.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == expectedWindow }),
          let bounds = own[kCGWindowBounds as String] as? NSDictionary,
          let frame = CGRect(dictionaryRepresentation: bounds), frame.width >= 420, frame.height >= 340 else { return nil }
    let region = CGRect(x: floor(frame.midX) - 64, y: floor(frame.midY) - 36, width: 128, height: 72)
    var count: UInt32 = 0
    guard frame.insetBy(dx: 60, dy: 90).contains(region),
          CGGetDisplaysWithRect(region, 0, nil, &count) == .success, count == 1 else { return nil }
    var display: CGDirectDisplayID = 0
    guard CGGetDisplaysWithRect(region, 1, &display, &count) == .success, count == 1,
          CGDisplayBounds(display).contains(region) else { return nil }
    for entry in entries {
        guard let alpha = entry[kCGWindowAlpha as String] as? Double, (0...1).contains(alpha) else { return nil }
        if alpha == 0 { continue }
        guard let box = entry[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: box),
              rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
        if !rect.intersects(region) { continue }
        guard alpha == 1, (entry[kCGWindowOwnerPID as String] as? Int32) == edgePID,
              (entry[kCGWindowNumber as String] as? CGWindowID) == expectedWindow else { return nil }
        return region
    }
    return nil
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
case "unfocusedWindow":
    var status = ""
    guard let id = ownedWindow(requireFront: false, status: &status) else { print(status); exit(14) }
    print(id)
case "activate":
    var status = ""
    guard expectedWindow != 0, ownedWindow(requireFront: false, status: &status) == expectedWindow else { exit(15) }
    if ownedWindow() == expectedWindow { print("ALREADY_FRONTMOST"); exit(0) }
    guard edge.activate(options: []) else { exit(16) }
    print("REQUEST_ACCEPTED")
case "window":
    var status = ""
    guard let id = ownedWindow(status: &status) else { print(status); exit(2) }
    print(id)
case "region":
    guard let region = unobscuredContentRegion() else { exit(2) }
    print([region.minX, region.minY, region.width, region.height].map { String(Int($0)) }.joined(separator: ","))
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
