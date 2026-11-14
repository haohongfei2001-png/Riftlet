import AppKit
import ApplicationServices
import Foundation

// Operate only the two processes launched by this test, on a disposable hosted console.
let args = CommandLine.arguments
let env = ProcessInfo.processInfo.environment
guard env["GITHUB_ACTIONS"] == "true", env["RUNNER_ENVIRONMENT"] == "github-hosted",
      env["GITHUB_REPOSITORY"] == "haohongfei2001-png/Riftlet", args.count >= 2 else { exit(77) }
if args[1] == "preflight" {
    guard CGPreflightScreenCaptureAccess() else {
        print("SCREEN_CAPTURE_PERMISSION_UNAVAILABLE")
        exit(77)
    }
    guard ["com.riftlet.app", "com.microsoft.edgemac"].allSatisfy({
        NSRunningApplication.runningApplications(withBundleIdentifier: $0).allSatisfy(\.isTerminated)
    }) else { print("AN_EXISTING_HOST_IS_RUNNING"); exit(77) }
    exit(0)
}
let edgeBundle = URL(fileURLWithPath: "/Applications/Microsoft Edge.app").resolvingSymlinksInPath().standardizedFileURL
func edgeIdentity(_ pid: pid_t) -> (String?, String) {
    guard let first = KernelProcessBirth.read(pid: pid) else { return (nil, "KERNEL_BIRTH_UNAVAILABLE") }
    guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated
        else { return (nil, "OWN_CHILD_NOT_REGISTERED") }
    guard app.bundleIdentifier == "com.microsoft.edgemac" else { return (nil, "BUNDLE_ID_NOT_CONFIRMED") }
    guard app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == edgeBundle.path
        else { return (nil, "BUNDLE_PATH_NOT_CONFIRMED") }
    guard let actual = app.executableURL?.resolvingSymlinksInPath().standardizedFileURL.path,
          let expected = Bundle(url: edgeBundle)?.executableURL?.resolvingSymlinksInPath().standardizedFileURL.path,
          actual == expected else { return (nil, "EXECUTABLE_PATH_NOT_CONFIRMED") }
    guard KernelProcessBirth.read(pid: pid) == first else { return (nil, "CHILD_BIRTH_CHANGED") }
    return ("\(first.seconds):\(first.microseconds)", "VERIFIED")
}
if args[1] == "edgeVacant" {
    guard args.count == 2 else { exit(64) }
    exit(NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.edgemac")
        .allSatisfy(\.isTerminated) ? 0 : 18)
}
if args[1] == "edgeIdentity" {
    guard args.count == 3, let pid = Int32(args[2]), pid > 0 else { exit(64) }
    let result = edgeIdentity(pid)
    guard let stamp = result.0 else { print(result.1); exit(17) }
    print(stamp); exit(0)
}
if ["productPID", "quitProduct"].contains(args[1]) {
    guard args.count == (args[1] == "productPID" ? 3 : 4) else { exit(64) }
    let url = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath().standardizedFileURL
    let matches = NSRunningApplication.runningApplications(withBundleIdentifier: "com.riftlet.app")
        .filter { !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == url.path }
    guard matches.count == 1, let product = matches.first, let born = KernelProcessBirth.read(pid: product.processIdentifier),
          let actual = product.executableURL?.resolvingSymlinksInPath().path,
          actual == Bundle(url: url)?.executableURL?.resolvingSymlinksInPath().path else { exit(2) }
    let stamp = "\(born.seconds):\(born.microseconds)"
    if args[1] == "quitProduct" {
        guard stamp == args[3], product.terminate() else { exit(1) }
    }
    print("\(product.processIdentifier) \(stamp)")
    exit(0)
}
let mouseProbe = ["mouseReady", "mouseClick"].contains(args[1])
if mouseProbe || args[1] == "neutralAX" {
    // NSWindow.windowNumber(at:) returned zero for every owned point in an
    // uninitialized command-line observer. Establish AppKit's WindowServer
    // connection while keeping this helper unable to become the active app.
    let observer = NSApplication.shared
    if observer.activationPolicy() != .prohibited { _ = observer.setActivationPolicy(.prohibited) }
    guard observer.activationPolicy() == .prohibited else {
        print(mouseProbe ? "observerInitializationUnavailable" : "AX_ATTRIBUTES_UNAVAILABLE")
        exit(mouseProbe ? 24 : 0)
    }
}
let expectedCount = mouseProbe ? 12 : (args[1] == "neutralAX" ? 11 : 10)
guard args.count == expectedCount, let expectedWindow = CGWindowID(args[7]), let edgePID = Int32(args[2]),
      let productPID = Int32(args[3]), let row = Int(args[6]), (0...2).contains(row)
      else { exit(64) }
guard let edge = NSRunningApplication(processIdentifier: edgePID), !edge.isTerminated else { exit(10) }
guard edgeIdentity(edgePID).0 == args[8] else { exit(11) }
guard let app = NSRunningApplication(processIdentifier: productPID), !app.isTerminated else { exit(12) }
let productBundle = URL(fileURLWithPath: args[4]).resolvingSymlinksInPath().standardizedFileURL
guard app.bundleIdentifier == "com.riftlet.app", let born = KernelProcessBirth.read(pid: productPID),
      args[9] == "\(born.seconds):\(born.microseconds)",
      app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == productBundle.path,
      let actual = app.executableURL?.resolvingSymlinksInPath().standardizedFileURL.path,
      actual == Bundle(url: productBundle)?.executableURL?.resolvingSymlinksInPath().standardizedFileURL.path else { exit(13) }

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

struct MappedRow: Decodable, Equatable {
    let assetIDDigest: String
    let ordinal, windowNumber: Int
    let x, y, width, height: Double
    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct HitMap: Decodable {
    let pid: Int32
    let uptime: Double
    let rows: [MappedRow]
    let ignoringWindowNumbers: [Int]
}

struct MouseTarget: Equatable {
    let row: MappedRow
    let point: CGPoint
}

enum MouseUnavailable: String, Error {
    case mapAbsent, mapUnreadable, mapNotOwnedRegularFile, mapInvalidPayload, mapProcessMismatch, mapStale
    case mapRowsZero, mapRowsOne, mapRowsMoreThanTwo
    case foregroundChanged, ambiguousAsset, overlappingAssets, invalidGeometry
    case ownerUnconfirmed, eventDeliveryUnconfirmed, postPermissionUnavailable, otherInputActive
    case targetChangedBeforeDown, eventAllocationFailed
}

enum FirstMouseReceiver: String, Error {
    case originalFrontEdge, otherRiftletWindow, none, other
}

func mouseTarget() throws -> MouseTarget {
    guard expectedWindow != 0, ownedWindow() == expectedWindow,
          edgeIdentity(edgePID).0 == args[8], KernelProcessBirth.read(pid: productPID) == born
        else { throw MouseUnavailable.foregroundChanged }
    guard CGPreflightPostEventAccess() else { throw MouseUnavailable.postPermissionUnavailable }
    guard !CGEventSource.buttonState(.combinedSessionState, button: .left),
          !CGEventSource.buttonState(.combinedSessionState, button: .right),
          CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty
        else { throw MouseUnavailable.otherInputActive }
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Riftlet/diagnostics/acceptance-hit-map.json")
    let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw errno == ENOENT ? MouseUnavailable.mapAbsent : MouseUnavailable.mapUnreadable }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG
        else { throw MouseUnavailable.mapNotOwnedRegularFile }
    guard info.st_size > 0, info.st_size < 65536, let data = try? handle.read(upToCount: 65536),
          let map = try? JSONDecoder().decode(HitMap.self, from: data) else { throw MouseUnavailable.mapInvalidPayload }
    guard map.pid == productPID else { throw MouseUnavailable.mapProcessMismatch }
    guard map.uptime > 0, (0...2).contains(ProcessInfo.processInfo.systemUptime - map.uptime)
        else { throw MouseUnavailable.mapStale }
    switch map.rows.count {
    case 0: throw MouseUnavailable.mapRowsZero
    case 1: throw MouseUnavailable.mapRowsOne
    case 2: break
    default: throw MouseUnavailable.mapRowsMoreThanTwo
    }
    let rows = map.rows.filter { $0.assetIDDigest == args[10] }
    guard rows.count == 1, let target = rows.first, (1...2).contains(target.ordinal),
          target.windowNumber > 0, Set(map.rows.map(\.assetIDDigest)).count == 2,
          Set(map.rows.map(\.ordinal)) == [1, 2] else { throw MouseUnavailable.ambiguousAsset }
    let frame = target.frame
    guard [target.x, target.y, target.width, target.height].allSatisfy(\.isFinite),
          target.width > 0, target.height > 0 else { throw MouseUnavailable.invalidGeometry }
    let point = CGPoint(x: frame.midX, y: frame.midY)
    guard !map.rows.contains(where: { $0.assetIDDigest != target.assetIDDigest && $0.frame.contains(point) })
        else { throw MouseUnavailable.overlappingAssets }
    guard let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] else {
        throw MouseUnavailable.ownerUnconfirmed
    }
    var owned = Set<Int>()
    for entry in entries {
        guard let number = entry[kCGWindowNumber as String] as? Int,
              let pid = entry[kCGWindowOwnerPID as String] as? Int32, pid == productPID else { continue }
        owned.insert(number)
    }
    guard let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? Int) == target.windowNumber }),
          owned.contains(target.windowNumber), let box = entry[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: box), bounds.contains(point),
          bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
          !map.ignoringWindowNumbers.contains(target.windowNumber) else { throw MouseUnavailable.ownerUnconfirmed }
    let cocoa = CGPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    // The first window eligible for mouse-down must itself be the mapped input.
    let receiver = NSWindow.windowNumber(at: cocoa, belowWindowWithWindowNumber: 0)
    if receiver != target.windowNumber {
        if receiver <= 0 { throw FirstMouseReceiver.none }
        if owned.contains(receiver) { throw FirstMouseReceiver.otherRiftletWindow }
        if receiver == Int(expectedWindow) { throw FirstMouseReceiver.originalFrontEdge }
        throw FirstMouseReceiver.other
    }
    // The first eligible mouse-down receiver above already resolves transparent
    // pixels and windows that ignore events. A CGWindow rectangle above it can
    // overlap this point without receiving input; rectangle overlap adds no
    // authority to override AppKit's actual first-recipient result.
    return MouseTarget(row: target, point: point)
}

switch args[1] {
case "neutralAX":
    guard let link = URL(string: args[10]), link.path == "/" + args[5] else { exit(64) }
    guard expectedWindow != 0, ownedWindow() == expectedWindow else { print("window"); exit(0) }
    let outcome = try MainActor.assumeIsolated {
        let probe = EdgeNativeDraftProbe(driver: try NativeMacAXDriver(messagingTimeout: 0.1))
        return probe.inspectNeutral(pid: edgePID, expectedBirth: args[8], address: link)
    }
    print(ownedWindow() == expectedWindow ? outcome : "window")
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
case "mouseReady", "mouseClick":
    guard args[10].range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
          let tag = Int64(args[11]), tag > 0, tag < (1 << 48) else { exit(64) }
    do {
        let first = try mouseTarget()
        if args[1] == "mouseClick" {
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                    mouseCursorPosition: first.point, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                    mouseCursorPosition: first.point, mouseButton: .left) else { throw MouseUnavailable.eventAllocationFailed }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.setIntegerValueField(.eventSourceUserData, value: tag)
            }
            guard try mouseTarget() == first else { throw MouseUnavailable.targetChangedBeforeDown }
            // No fallbacks/retries past this boundary, including an indeterminate reply.
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        print("\(first.row.ordinal) \(first.row.windowNumber)")
    } catch let receiver as FirstMouseReceiver {
        print("firstReceiver " + receiver.rawValue)
        exit(24)
    } catch let error as MouseUnavailable {
        print(error.rawValue)
        exit(24) // All cases are before mouse-down.
    }
default: exit(64)
}
