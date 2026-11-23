import AppKit
import Carbon
import Foundation
@testable import RiftletAdapters

// Presentation only. The caller holds the shared GUI lease. Neither the placement nor
// the activation helpers have a page mutation, mouse event or keyboard input path.
@main enum PresentOriginal {
    typealias Row = [String: Any]
    typealias Descriptor = NSAppleEventDescriptor

    static func require(_ condition: Bool, _ reason: String) throws {
        if !condition { throw Identity.Refusal(reason) }
    }

    static func read(_ directory: URL, _ name: String) throws -> Row {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        guard let row = try JSONSerialization.jsonObject(with: data) as? Row else {
            throw Identity.Refusal("UNREADABLE_RECEIPT")
        }
        return row
    }

    static func ax(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func axFrame(_ window: AXUIElement) -> CGRect? {
        guard let p = ax(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = ax(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &position),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        zip([a.minX, a.minY, a.width, a.height], [b.minX, b.minY, b.width, b.height])
            .allSatisfy { abs($0 - $1) <= 1 }
    }

    static func coords(_ frame: CGRect) -> [CGFloat] {
        [frame.minX, frame.minY, frame.width, frame.height]
    }

    static func decodeFrame(_ descriptor: Descriptor) throws -> CGRect {
        try require(descriptor.descriptorType == typeQDRectangle && descriptor.data.count == 8, "NATIVE_BOUNDS_UNAVAILABLE")
        let edges = descriptor.data.withUnsafeBytes { bytes in
            (0..<4).map { Int(bytes.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self)) }
        }
        let frame = CGRect(x: edges[1], y: edges[0], width: edges[3] - edges[1], height: edges[2] - edges[0])
        try require(frame.width > 0 && frame.height > 0, "INVALID_NATIVE_BOUNDS")
        return frame
    }

    static func encodeFrame(_ frame: CGRect) throws -> Descriptor {
        let edges = [frame.minY, frame.minX, frame.maxY, frame.maxX].compactMap { Int16(exactly: $0) }
        guard edges.count == 4, let descriptor = edges.withUnsafeBytes({
            Descriptor(descriptorType: typeQDRectangle, bytes: $0.baseAddress, length: $0.count)
        }) else { throw Identity.Refusal("UNREPRESENTABLE_NATIVE_BOUNDS") }
        return descriptor
    }

    @MainActor static func placement(excluding peers: [CGRect]) throws -> CGRect {
        guard let primary = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) else { throw Identity.Refusal("NO_PRIMARY_DISPLAY") }
        // NSScreen uses a bottom-left origin. Chromium, AX and CG windows use a
        // top-left origin measured from the primary display, in logical points.
        let v = primary.visibleFrame
        let area = CGRect(x: v.minX, y: primary.frame.maxY - v.maxY, width: v.width, height: v.height)
        let width = min(1000, floor(area.width * 0.76)), height = min(660, floor(area.height * 0.79))
        try require(width >= 480 && height >= 320, "VISIBLE_DISPLAY_TOO_SMALL")
        for offset in [0.46, 0.18, 0.72, 0.32] {
            let frame = CGRect(x: round(area.minX + (area.width - width) * offset),
                               y: round(area.minY + (area.height - height) * offset), width: width, height: height)
            if area.contains(frame) && !peers.contains(where: { same($0, frame) }) { return frame }
        }
        throw Identity.Refusal("DISTINCT_VISIBLE_GEOMETRY_UNAVAILABLE")
    }

    @MainActor static func desktop(at target: CGRect) throws {
        guard let s = CGSessionCopyCurrentDictionary() as? Row, let front = NSWorkspace.shared.frontmostApplication else {
            throw Identity.Refusal("DESKTOP_UNAVAILABLE")
        }
        try require(s[kCGSessionOnConsoleKey as String] as? Bool == true && s[kCGSessionLoginDoneKey as String] as? Bool == true &&
                    s["CGSSessionScreenIsLocked"] as? Bool != true && CGDisplayIsAsleep(CGMainDisplayID()) == 0, "DESKTOP_UNAVAILABLE")
        try require(AXIsProcessTrusted(), "AX_NOT_TRUSTED")
        let guarded = ["com.apple.UserNotificationCenter", "com.apple.SecurityAgent", "com.apple.CoreAuthUI",
                       "com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [Row]
        guard let rows else { throw Identity.Refusal("WINDOWSERVER_UNAVAILABLE") }
        // ScreenCaptureUI can own a full-display, input-transparent overlay. A
        // rectangle alone is inconclusive. Stop when the tool owns the front or
        // an actual accessibility hit within the original (or proposed) window.
        let captureBundle = "com.apple.screencaptureui"
        let captureApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier?.lowercased() == captureBundle }
        if captureApps.contains(where: { $0.processIdentifier == front.processIdentifier }) {
            throw Identity.Refusal("SYSTEM_CAPTURE_UI_FOREGROUND")
        }
        for app in captureApps {
            let frames = rows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier &&
                                       ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
                .compactMap { $0[kCGWindowBounds as String] as? NSDictionary }.compactMap { CGRect(dictionaryRepresentation: $0) }
            let system = AXUIElementCreateSystemWide()
            for (x, y) in [(0.50, 0.50), (0.25, 0.30), (0.75, 0.30), (0.25, 0.70), (0.75, 0.70)] {
                let point = CGPoint(x: target.minX + x * target.width, y: target.minY + y * target.height)
                guard frames.contains(where: { $0.contains(point) }) else { continue }
                var hit: AXUIElement?, hitPID: pid_t = -1
                try require(AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success &&
                            hit != nil, "CAPTURE_OVERLAY_HIT_UNRESOLVED")
                if let hit {
                    try require(AXUIElementGetPid(hit, &hitPID) == .success, "CAPTURE_OVERLAY_OWNER_UNAVAILABLE")
                    try require(hitPID != app.processIdentifier, "INTERACTIVE_CAPTURE_OVERLAY")
                }
            }
        }
        // A background process having an AXSystemDialog in another Space is not
        // evidence this desktop is blocked. Match visible geometry without reading text.
        for bundle in guarded {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundle) {
                let onscreen = rows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier &&
                                              ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
                if onscreen.isEmpty && app.processIdentifier != front.processIdentifier { continue }
                let windows = ax(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement]
                guard let windows else { throw Identity.Refusal("PROTECTED_SURFACE_UNRESOLVED") }
                for window in windows where ax(window, kAXSubroleAttribute) as? String == "AXSystemDialog" ||
                                             ax(window, kAXModalAttribute) as? Bool == true {
                    guard let frame = axFrame(window) else { throw Identity.Refusal("PROTECTED_BOUNDS_UNAVAILABLE") }
                    if app.processIdentifier == front.processIdentifier || onscreen.contains(where: {
                        guard let d = $0[kCGWindowBounds as String] as? NSDictionary,
                              let cg = CGRect(dictionaryRepresentation: d) else { return true }
                        return same(frame, cg) || (cg.width > 1 && cg.height > 1 && cg.intersects(frame))
                    }) { throw Identity.Refusal("VISIBLE_PROTECTED_DIALOG") }
                }
                if app.processIdentifier == front.processIdentifier { throw Identity.Refusal("PROTECTED_FOREGROUND") }
            }
        }
        guard let windows = ax(AXUIElementCreateApplication(front.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] else {
            throw Identity.Refusal("FOREGROUND_WINDOWS_UNREADABLE")
        }
        try require(!windows.contains { ax($0, kAXModalAttribute) as? Bool == true }, "FOREGROUND_MODAL")
    }

    @MainActor static func execute(_ result: inout Row) throws {
        var args = Array(CommandLine.arguments.dropFirst())
        let mode = args.count == 2 ? "present" : (args.isEmpty ? "" : args.removeFirst())
        try require(args.count == 2 && ["present", "place"].contains(mode), "USE_PRESENT_OR_PLACE_WITH_ENROLLED_SCOPE")
        let state = URL(fileURLWithPath: args[0], isDirectory: true), family = args[1]
        let c = try read(state, "creation.json"), before = try read(state, "before.json"), local = try read(state, "challenge.json")
        guard let vendor = Identity.families[family], c["family"] as? String == family, let pid = c["pid"] as? Int32,
              c["phase"] as? String == "qaAddressConfirmed", let wid = c["windowID"] as? String, let tid = c["tabID"] as? String,
              let birth = c["sessionID"] as? String, let earlier = before["windowIDs"] as? [String], !earlier.contains(wid),
              before["sessionID"] as? String == birth, before["pid"] as? Int32 == pid, before["dynamicSignature"] as? Bool == true,
              local["sessionID"] as? String == birth, local["bundle"] as? String == vendor.bundle, local["windowID"] as? String == wid,
              local["tabID"] as? String == tid, local["dynamicSignature"] as? Bool == true, let marker = local["doc"] as? String,
              UUID(uuidString: marker) != nil, (local["renderer"] as? Row)?["sameDocument"] as? Bool == true else {
            throw Identity.Refusal("ORIGINAL_CREATION_AND_CHALLENGE_REQUIRED")
        }
        let permission = AEDeterminePermissionToAutomateTarget(Descriptor(bundleIdentifier: vendor.bundle).aeDesc, typeWildCard, typeWildCard, false)
        result["permissionOSStatus"] = permission
        try require(permission == noErr, "AE_PERMISSION_NOT_ESTABLISHED_WITHOUT_PROMPT")
        let proc = try Identity.certified(vendor, expectedPID: pid)
        guard let app = NSRunningApplication(processIdentifier: pid) else { throw Identity.Refusal("PROCESS_UNAVAILABLE") }
        let win = try Identity.object("cwin", "ID  ", .init(string: wid))
        let tab = try Identity.object("CrTb", "ID  ", .init(string: tid), win)
        let entry: Row?, url: String
        if FileManager.default.fileExists(atPath: state.appendingPathComponent("original-entry.json").path) {
            entry = try read(state, "original-entry.json")
            let nav = try read(state, "site-navigation-return.json")
            let route = ["applicationID": vendor.bundle, "session": birth, "windowID": wid, "tabID": tid]
            try require(nav["navigationRequested"] as? Bool == true && nav["sourceDoc"] as? String == marker &&
                        nav["route"] as? [String: String] == route && entry?["sourceDoc"] as? String == marker &&
                        (entry?["entryID"] as? String).flatMap(UUID.init(uuidString:)) != nil && entry?["timeOrigin"] is Double,
                        "ORIGINAL_SITE_ROUTE_REQUIRED")
            url = QAOriginalBrowserTab.temporaryChat
        } else {
            entry = nil
            guard let localURL = try read(state, "urls.json")[family] as? String, Owned.valid(localURL) else {
                throw Identity.Refusal("LOCAL_CHALLENGE_REQUIRED")
            }
            url = localURL
        }
        result["documentKind"] = entry == nil ? "localChallenge" : "temporaryChat"
        result["family"] = family
        result["mode"] = mode
        func original() throws {
            try require(proc.isCurrent() && proc.session == birth && !app.isTerminated, "BROWSER_BIRTH_CHANGED")
            try require(try Owned.tabIDs(proc, window: win) == [tid] && Identity.get(proc, Identity.property("URL ", tab)).stringValue == url,
                        "ORIGINAL_TAB_CHANGED")
            let probe = entry == nil ? "document.querySelector('output#doc')?.textContent || ''" :
                                       "JSON.stringify([navigation.currentEntry.id,performance.timeOrigin])"
            let data = try Owned.request(proc, "CrSu", "ExJa", ["----": tab, "JvSc": .init(string: probe)]).stringValue
            if let entry {
                guard let data, let fields = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [Any],
                      fields.count == 2, fields[0] as? String == entry["entryID"] as? String,
                      fields[1] as? Double == entry["timeOrigin"] as? Double else { throw Identity.Refusal("ORIGINAL_DOCUMENT_CHANGED") }
            } else { try require(data == marker, "LOCAL_DOCUMENT_CHANGED") }
        }
        func check() throws { try original(); try desktop(at: bounds(win)) }
        func bounds(_ window: Descriptor) throws -> CGRect {
            try decodeFrame(Identity.get(proc, Identity.property("pbnd", window)))
        }
        func peerBounds() throws -> [CGRect] {
            try Identity.windows(proc).filter { $0 != wid }.map { try bounds(Identity.object("cwin", "ID  ", .init(string: $0))) }
        }
        func selected() throws -> Bool {
            let front = try Identity.object("cwin", "indx", .init(int32: 1))
            let item = try ChromeActiveTabDescriptor.identity(in: Identity.get(proc, Identity.property("acTa", front)))
            return item?.window == wid && item?.tab == tid
        }
        func setWindow(_ key: String, _ value: Descriptor, record flag: String) throws {
            let property = try Identity.property(key, win)
            try check()
            if key == "pbnd" { try desktop(at: decodeFrame(value)) }
            try require(proc.isCurrent(), "BROWSER_BIRTH_CHANGED")
            result[flag] = true
            _ = try Owned.request(proc, "core", "setd", ["----": property, "data": value])
            result[flag + "ReturnOSStatus"] = 0
        }
        func matchingAX() throws -> AXUIElement {
            let frame = try bounds(win)
            try require(try !peerBounds().contains(where: { same($0, frame) }), "NATIVE_FRAME_AMBIGUOUS")
            guard let windows = ax(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] else {
                throw Identity.Refusal("AX_WINDOWS_UNAVAILABLE")
            }
            let exact = windows.filter { ax($0, kAXRoleAttribute) as? String == "AXWindow" &&
                ax($0, kAXSubroleAttribute) as? String == "AXStandardWindow" && axFrame($0).map { same($0, frame) } == true }
            guard exact.count == 1 else { throw Identity.Refusal(exact.isEmpty ? "AX_FRAME_MISSING" : "AX_FRAME_AMBIGUOUS") }
            return exact[0]
        }
        func settle() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.22)) }
        func foreground() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
        try check()
        result["beforeSelected"] = try selected()
        result["beforeForeground"] = foreground()
        result["beforeBounds"] = coords(try bounds(win))
        if try Identity.get(proc, Identity.property("pmnd", win)).booleanValue {
            try setWindow("pmnd", .init(boolean: false), record: "restoreMinimizedIssued")
            settle()
        }
        if mode == "place" {
            let target = try placement(excluding: peerBounds())
            result["placementRequestedBounds"] = coords(target)
            if !same(try bounds(win), target) {
                try setWindow("pbnd", encodeFrame(target), record: "placementIssued")
                settle()
            }
            try check()
            result["placementReadback"] = coords(try bounds(win))
            try require(same(try bounds(win), target), "PLACEMENT_READBACK_MISMATCH")
        }
        // pidx addresses the created window by its immutable ID. An index is never
        // used to select a target, only to read back which window is currently front.
        if try !selected() {
            try setWindow("pidx", .init(int32: 1), record: "selectionRequestIssued")
            settle()
        }
        try check()
        try require(try selected(), "ORIGINAL_TAB_NOT_SELECTED_FOR_ACTIVATION")
        let currentWindows = try Identity.windows(proc)
        try require(currentWindows.contains(wid), "ORIGINAL_WINDOW_MISSING")
        let soleWindow = currentWindows == Set([wid])
        result["nativeWindowCountAtActivation"] = currentWindows.count
        if soleWindow || !foreground() {
            try check()
            try require(try selected() && Identity.windows(proc) == currentWindows, "WINDOW_SET_CHANGED_BEFORE_ACTIVATION")
            let options: NSApplication.ActivationOptions = soleWindow ? [.activateIgnoringOtherApps, .activateAllWindows] : []
            result["appActivationIssued"] = true
            result["activationOptions"] = soleWindow ? "ignoreOtherApps+allWindows" : "ordinary"
            result["appActivationReturned"] = app.activate(options: options)
            settle()
        } else {
            result["activationOptions"] = "alreadyForegroundWithPeerWindows"
        }
        result["afterNSForeground"] = foreground()
        try check()
        do {
            let target = try matchingAX()
            try check()
            let second = try matchingAX()
            try require(CFEqual(target, second), "AX_TARGET_CHANGED_BEFORE_RAISE")
            result["axRaiseIssued"] = true
            result["axRaiseReturnCode"] = AXUIElementPerformAction(second, kAXRaiseAction as CFString).rawValue
            settle()
        } catch let error as Identity.Refusal { result["axDisposition"] = error.reason }
        result["afterAXForeground"] = foreground()
        try check()
        try require(try selected(), "ORIGINAL_TAB_NOT_SELECTED_FOR_APPLE_EVENT")
        result["aeActivationIssued"] = true
        do {
            _ = try Owned.request(proc, "misc", "actv", [:])
            result["aeActivationOSStatus"] = 0
        } catch {
            let ns = error as NSError
            result["aeActivationErrorDomain"] = ns.domain
            result["aeActivationErrorCode"] = ns.code
            result["aeActivationOSStatus"] = NSNull()
            if let reason = error as? Identity.Refusal {
                result["aeActivationError"] = reason.reason
                let prefix = "OWNED_actv_"
                if reason.reason.hasPrefix(prefix), let status = Int32(reason.reason.dropFirst(prefix.count)) {
                    result["aeActivationOSStatus"] = status
                }
            } else if ns.domain == NSOSStatusErrorDomain { result["aeActivationOSStatus"] = ns.code }
        }
        settle()
        try check()
        // Both browsers expose acTI. With exactly one enrolled tab, index 1 is
        // unambiguous, and the original IDs and document are checked on both sides.
        try setWindow("acTI", .init(int32: 1), record: "originalTabSelectionIssued")
        try check()
        result["originalSelected"] = try selected()
        result["systemForeground"] = foreground()
        result["endingBounds"] = coords(try bounds(win))
        result["finalForegroundPID"] = NSWorkspace.shared.frontmostApplication?.processIdentifier as Any? ?? NSNull()
        result["finalForegroundBundle"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unavailable"
    }

    @MainActor static func main() {
        var row: Row = ["utc": ISO8601DateFormatter().string(from: Date()), "appActivationIssued": false,
                        "axRaiseIssued": false, "aeActivationIssued": false, "placementIssued": false,
                        "selectionRequestIssued": false, "originalTabSelectionIssued": false]
        var code: Int32 = 0
        do { try execute(&row) } catch {
            row["refusal"] = (error as? Identity.Refusal)?.reason ?? "NATIVE_PRESENTATION_ERROR"
            row["errorCode"] = (error as NSError).code
            code = 1
        }
        if let data = try? JSONSerialization.data(withJSONObject: row, options: .sortedKeys) { FileHandle.standardOutput.write(data) }
        exit(code)
    }
}
