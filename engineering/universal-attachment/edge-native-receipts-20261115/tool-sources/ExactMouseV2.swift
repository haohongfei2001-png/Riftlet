import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import Darwin

// Explicit caller-owned local acceptance only. No activation, browser scripting,
// launch, TCC request, database write, retry, alternate row or fallback.
let helperRoot = "<USER_HOME>/Documents/GitHub/Riftlet/build/pr69-runtime-20261115-restart/native-helper"
let dataRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Riftlet-Isolated-Product-Acceptance")
func canonical(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path }
func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func birth(_ pid: Int32) throws -> String {
    guard let value = KernelProcessBirth.read(pid: pid) else { throw Failure(code: "kernelBirthUnavailable") }
    return "\(value.seconds):\(value.microseconds)"
}
struct Configuration: Codable {
    let productBundle, productBinarySHA256, productBirth, edgeBundle, edgeBinarySHA256, edgeBirth: String
    let productPID, edgePID: Int32
    let edgeWindow: Int
    let attemptID: String
    let assets: [String]
    let knownVisibleAssets: [String]?
}
struct Row: Decodable, Equatable {
    let assetIDDigest: String
    let ordinal, windowNumber: Int
    let x, y, width, height: Double
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
struct Map: Decodable { let pid: Int32; let uptime: Double; let rows: [Row]; let ignoringWindowNumbers: [Int] }
struct PointTarget: Equatable { let row: Row; let point: CGPoint }
func app(_ pid: Int32, bundlePath: String, identifier: String, expectedBirth: String, executableHash: String) throws {
    try require(try birth(pid) == expectedBirth, "processBirthChanged")
    guard let instance = NSRunningApplication(processIdentifier: pid), !instance.isTerminated,
          instance.bundleIdentifier == identifier, let actual = instance.bundleURL,
          canonical(actual.path) == canonical(bundlePath), let runningExecutable = instance.executableURL,
          let expectedExecutable = Bundle(path: bundlePath)?.executableURL,
          canonical(runningExecutable.path) == canonical(expectedExecutable.path) else { throw Failure(code: "processIdentityChanged") }
    try require(validHash(executableHash) && digest(try Data(contentsOf: expectedExecutable)) == executableHash, "executableHashChanged")
    try require(try birth(pid) == expectedBirth, "processBirthChanged")
}
func axValue(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else {
        throw Failure(code: "edgeAXAttributeUnavailable")
    }
    return value
}
func semanticWindows(_ app: AXUIElement, pid: Int32) throws -> [SemanticWindow] {
    let list = try axValue(app, kAXWindowsAttribute)
    guard CFGetTypeID(list) == CFArrayGetTypeID(), let windows = list as? [AXUIElement],
          !windows.isEmpty, windows.count <= 16 else { throw Failure(code: "edgeAXWindowsUnavailable") }
    return try windows.map { window in
        var owner: pid_t = 0
        try require(AXUIElementGetPid(window, &owner) == .success && owner == pid, "edgeAXOwnerMismatch")
        guard let role = try axValue(window, kAXRoleAttribute) as? String,
              let subrole = try axValue(window, kAXSubroleAttribute) as? String else { throw Failure(code: "edgeAXRoleUnavailable") }
        let mainValue = try axValue(window, kAXMainAttribute)
        try require(CFGetTypeID(mainValue) == CFBooleanGetTypeID(), "edgeAXMainUnavailable")
        let main = CFBooleanGetValue((mainValue as! CFBoolean))
        let rawPosition = try axValue(window, kAXPositionAttribute), rawSize = try axValue(window, kAXSizeAttribute)
        try require(CFGetTypeID(rawPosition) == AXValueGetTypeID() && CFGetTypeID(rawSize) == AXValueGetTypeID(), "edgeAXGeometryUnavailable")
        let positionValue = rawPosition as! AXValue, sizeValue = rawSize as! AXValue
        var point = CGPoint.zero, size = CGSize.zero
        try require(AXValueGetType(positionValue) == .cgPoint && AXValueGetType(sizeValue) == .cgSize
            && AXValueGetValue(positionValue, .cgPoint, &point) && AXValueGetValue(sizeValue, .cgSize, &size), "edgeAXGeometryUnavailable")
        return SemanticWindow(role: role, subrole: subrole, main: main, frame: CGRect(origin: point, size: size))
    }
}
func edgeWindow(_ pid: Int32) throws -> Int {
    let originalBirth = try birth(pid)
    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, "originalEdgeNotFrontmost")
    try require(AXIsProcessTrusted(), "edgeAXPermissionUnavailable")
    let owner = AXUIElementCreateApplication(pid)
    try require(AXUIElementSetMessagingTimeout(owner, 0.25) == .success, "edgeAXTimeoutUnavailable")
    let semantic = try semanticWindows(owner, pid: pid)
    guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] else {
        throw Failure(code: "windowListUnavailable")
    }
    let own = try entries.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }.map { entry in
        guard let number = entry[kCGWindowNumber as String] as? Int,
              let box = entry[kCGWindowBounds as String] as? NSDictionary, let frame = CGRect(dictionaryRepresentation: box) else {
            throw Failure(code: "edgeCGGeometryUnavailable")
        }
        return ServerWindow(pid: pid, layer: 0, number: number, frame: frame)
    }
    let selected = try matchStandardWindow(semantic, own, pid: pid)
    try require(try semanticWindows(owner, pid: pid) == semantic, "edgeAXWindowSetChanged")
    try require(try birth(pid) == originalBirth && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                "originalEdgeIdentityChangedDuringWindowRead")
    return selected
}
func verify(_ config: Configuration) throws {
    let bundle = Bundle(path: config.productBundle)
    try require(bundle?.bundleIdentifier == "com.riftlet.isolated-product-acceptance"
        && bundle?.object(forInfoDictionaryKey: "RiftletBuildChannel") as? String == "isolated-product-acceptance", "notIsolatedProductChannel")
    try require(validAttempt(config.attemptID), "invalidAttemptID")
    try app(config.productPID, bundlePath: config.productBundle, identifier: "com.riftlet.isolated-product-acceptance",
            expectedBirth: config.productBirth, executableHash: config.productBinarySHA256)
    try app(config.edgePID, bundlePath: config.edgeBundle, identifier: "com.microsoft.edgemac",
            expectedBirth: config.edgeBirth, executableHash: config.edgeBinarySHA256)
    try require(try edgeWindow(config.edgePID) == config.edgeWindow, "originalEdgeWindowChanged")
}
func target(_ config: Configuration, asset: String) throws -> PointTarget {
    try verify(config)
    let known = try validateVisibleAssetConfiguration(targets:config.assets, known:config.knownVisibleAssets)
    try require(config.assets.contains(asset), "clickedAssetNotOneOfTwoTargets")
    try require(CGPreflightPostEventAccess(), "postPermissionUnavailable")
    let buttonsFree = [CGMouseButton.left, .right, .center].allSatisfy { !CGEventSource.buttonState(.combinedSessionState, button: $0) }
    try require(buttonsFree && CGEventSource.flagsState(.combinedSessionState)
        .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty, "otherInputActive")
    let map = try JSONDecoder().decode(Map.self, from: ownedData(dataRoot.appendingPathComponent("diagnostics/acceptance-hit-map.json").path, limit: 65536))
    try require(map.pid == config.productPID && map.uptime > 0 && (0...2).contains(ProcessInfo.processInfo.systemUptime - map.uptime), "mapIdentityOrFreshnessInvalid")
    try validateKnownVisibleMap(map.rows.map(\.assetIDDigest), known:known)
    let matches = map.rows.filter { $0.assetIDDigest == asset }
    guard matches.count == 1, let row = matches.first else { throw Failure(code: "originalAssetNotUnique") }
    try require(row.windowNumber > 0 && row.ordinal > 0 && validFrame(row.rect), "invalidTargetGeometry")
    let point = CGPoint(x: row.rect.midX, y: row.rect.midY)
    try require(!map.rows.contains { $0.assetIDDigest != asset && $0.rect.contains(point) }, "overlappingAssets")
    guard let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]],
          let window = entries.first(where: { ($0[kCGWindowNumber as String] as? Int) == row.windowNumber }),
          (window[kCGWindowOwnerPID as String] as? Int32) == config.productPID,
          let raw = window[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: raw),
          bounds.contains(point), bounds.insetBy(dx: -0.5, dy: -0.5).contains(row.rect),
          !map.ignoringWindowNumbers.contains(row.windowNumber) else { throw Failure(code: "inputWindowOwnerUnconfirmed") }
    let cocoa = CGPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    try require(NSWindow.windowNumber(at: cocoa, belowWindowWithWindowNumber: 0) == row.windowNumber, "firstMouseReceiverMismatch")
    return PointTarget(row: row, point: point)
}
func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    try FileHandle.standardOutput.write(contentsOf: encoder.encode(value) + Data([10]))
}
@main struct ExactMouseV2 {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count >= 2 else { throw Failure(code: "usage") }
            if args[1] == "identity" {
                try require(args.count == 6 && validAttempt(args[5]), "usageIdentityProductEdgePIDAttempt")
                let productPath = canonical(args[2]), edgePath = canonical(args[3])
                guard let edgePID = Int32(args[4]), edgePID > 0,
                      let productExecutable = Bundle(path: productPath)?.executableURL,
                      let edgeExecutable = Bundle(path: edgePath)?.executableURL else { throw Failure(code: "usage") }
                let matches = NSRunningApplication.runningApplications(withBundleIdentifier: "com.riftlet.isolated-product-acceptance")
                    .filter { !$0.isTerminated && $0.bundleURL.map { canonical($0.path) == productPath } == true }
                guard matches.count == 1 else { throw Failure(code: "exactProductProcessNotUnique") }
                let config = Configuration(productBundle: productPath, productBinarySHA256: digest(try Data(contentsOf: productExecutable)),
                    productBirth: try birth(matches[0].processIdentifier), edgeBundle: edgePath,
                    edgeBinarySHA256: digest(try Data(contentsOf: edgeExecutable)), edgeBirth: try birth(edgePID),
                    productPID: matches[0].processIdentifier, edgePID: edgePID, edgeWindow: try edgeWindow(edgePID), attemptID: args[5], assets: [], knownVisibleAssets:nil)
                try verify(config); try emit(config); return
            }
            if args[1] == "checkIdentity" {
                try require(args.count == 3, "usage")
                let config = try JSONDecoder().decode(Configuration.self, from: ownedData(args[2], limit: 65536))
                try verify(config); print("{\"status\":\"EXACT_PROCESSES_AND_ORIGINAL_EDGE_WINDOW_CURRENT\"}"); return
            }
            try require(args.count == 4 && ["preflight", "post"].contains(args[1]), "usage")
            let observer = NSApplication.shared
            if observer.activationPolicy() != .prohibited { _ = observer.setActivationPolicy(.prohibited) }
            try require(observer.activationPolicy() == .prohibited, "observerInitializationUnavailable")
            let configurationData = try ownedData(args[2], limit: 65536)
            let config = try JSONDecoder().decode(Configuration.self, from: configurationData)
            let asset = args[3], first = try target(config, asset: asset)
            let traceData = try ownedData(dataRoot.appendingPathComponent("diagnostics/acceptance-recent.jsonl").path, limit: 1_048_576)
            let records = try traceData.split(separator: 10).map {
                guard let record = try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] else { throw Failure(code: "traceRecordInvalid") }
                return record
            }
            guard let last = records.last, let session = last["diagnosticSessionDigest"] as? String, validHash(session),
                  let sequence = last["diagnosticSequence"] as? Int else { throw Failure(code: "traceSessionUnavailable") }
            let number = Int64.random(in: 1...Int64(Int16.max)), tag = Int64.random(in: 1..<(1 << 48))
            var sent: [String: Any] = ["status":args[1] == "post" ? "reservedBeforePost" : "preflightOnly",
                "assetIDDigest":asset, "windowNumber":first.row.windowNumber, "x":first.point.x, "y":first.point.y,
                "mouseProbeTag":tag,"eventNumber":number,"diagnosticSessionDigest":session,"afterDiagnosticSequence":sequence,
                "productBinarySHA256":config.productBinarySHA256,"configurationSHA256":digest(configurationData),"attemptID":config.attemptID]
            if args[1] == "post" {
                let helper = try privateDirectory(helperRoot, create: false); close(helper)
                let attemptsPath = helperRoot + "/attempts"
                let attempts = try privateDirectory(attemptsPath, create: true); close(attempts)
                let path = attemptsPath + "/" + config.attemptID
                let directory = try privateDirectory(path, create: true)
                defer { close(directory) }
                let frozen = Data(digest(configurationData).utf8)
                if let prior = try readAt(directory, name: "configuration.sha256", limit: 128) {
                    try require(prior == frozen, "attemptConfigurationChanged")
                } else { try writeExclusive(directory, name: "configuration.sha256", data: frozen) }
                for previous in config.assets where previous != asset {
                    if let bytes = try readAt(directory, name: previous + ".json", limit: 65536) {
                        guard let record = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw Failure(code: "priorReceiptInvalid") }
                        try require((record["eventNumber"] as? Int64) != number && (record["mouseProbeTag"] as? Int64) != tag, "randomIdentifierCollision")
                    }
                }
                guard let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: first.point, mouseButton: .left),
                      let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: first.point, mouseButton: .left) else {
                    throw Failure(code: "eventAllocationUnavailable")
                }
                for event in [down, up] {
                    event.flags = []; event.setIntegerValueField(.mouseEventClickState, value: 1)
                    event.setIntegerValueField(.eventSourceUserData, value: tag); event.setIntegerValueField(.mouseEventNumber, value: number)
                    // NSEvent conversion is confined to a distinct copy. The
                    // original object is the only event ever posted.
                    try validateNativeReadbackOnCopy(event, number:number, tag:tag)
                }
                try require(try target(config, asset: asset) == first, "targetChangedBeforeDown")
                try writeExclusive(directory, name: asset + ".json", data: JSONSerialization.data(withJSONObject: sent, options: [.sortedKeys]))
                try require(try target(config, asset: asset) == first, "targetChangedAfterReservation")
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                sent["status"] = "singlePairPostedReceiptNotYetConfirmed"
                // Observe only this original operation, retaining the actual
                // posted objects. No input retry, fallback or activation occurs.
                let observation = withExtendedLifetime((source, down, up)) {
                    observeOriginalMouseReceipt(sent, traceURL:dataRoot.appendingPathComponent("diagnostics/acceptance-recent.jsonl"))
                }
                sent["passiveOriginalReceipt"] = observation
                sent["postReceiptStatus"] = observation["status"]
            }
            try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: sent, options: [.sortedKeys]) + Data([10]))
            if sent["postReceiptStatus"] as? String == "UNKNOWN_DO_NOT_REPOST" { exit(78) }
        } catch let error as Failure { print("{\"status\":\"STOP\",\"reason\":\"\(error.code)\"}"); exit(1) }
          catch { print("{\"status\":\"STOP\",\"reason\":\"helperError\"}"); exit(1) }
    }
}
