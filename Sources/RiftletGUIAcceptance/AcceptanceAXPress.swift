import AppKit
import ApplicationServices
import Darwin

/// One software accessibility action in the existing helper, never a physical
/// mouse claim or a direct call into Riftlet's selection/transfer implementation.
@MainActor
enum AcceptanceAXPress {
    private enum Refusal: String, Error {
        case invalidArguments, permissionUnavailable, applicationMismatch
        case axUnavailable, traversalLimit, noMatch, ambiguousMatch
        case invalidButton, foregroundChanged
    }

    private struct ProcessIdentity: Equatable {
        let pid: pid_t
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    static func run(_ arguments: [String]) -> Int32 {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        var fields: [String: Any] = ["event": "acceptance_asset_axpress", "source": "helperAX",
            "physical": false, "beforeForegroundPID": before, "axActionAttempted": false]
        var result: Int32 = 1
        do {
            let flags = ["--press-acceptance-asset", "--app-pid", "--app-path"]
            guard arguments.count == 6 else { throw Refusal.invalidArguments }
            var values: [String: String] = [:]
            for offset in stride(from: 0, to: arguments.count, by: 2) {
                let key = arguments[offset]
                guard flags.contains(key), values[key] == nil else { throw Refusal.invalidArguments }
                values[key] = arguments[offset + 1]
            }
            guard let asset = values[flags[0]].flatMap(UUID.init(uuidString:)),
                  let pid = values[flags[1]].flatMap(Int32.init), pid > 0,
                  let path = values[flags[2]], path.hasPrefix("/"),
                  URL(fileURLWithPath: path).pathExtension == "app" else { throw Refusal.invalidArguments }
            let appURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let originalProcess = try verifyApplication(pid: pid, appURL: appURL, phase: "initial", diagnostics: &fields)
            guard AXIsProcessTrusted() else { throw Refusal.permissionUnavailable }
            let identifier = "riftlet-synthetic-\(asset.uuidString)"
            fields["assetID"] = asset.uuidString
            fields["appPID"] = pid
            let application = AXUIElementCreateApplication(pid)
            let button = try uniqueButton(in: application, pid: pid, identifier: identifier, diagnostics: &fields)
            let originalWindow = try verifyWindowMembership(button, application: application, pid: pid, diagnostics: &fields)
            // Recheck process identity and fresh button attributes immediately
            // before the single action. No activation, key event, or retry.
            let currentProcess = try verifyApplication(pid: pid, appURL: appURL, phase: "beforePress", diagnostics: &fields)
            fields["processIdentityStable"] = currentProcess == originalProcess
            guard currentProcess == originalProcess else {
                fields["identityFailureStage"] = "kernelStartChanged"
                throw Refusal.applicationMismatch
            }
            let currentWindow = try verifyWindowMembership(button, application: application, pid: pid, diagnostics: &fields)
            guard CFEqual(originalWindow, currentWindow) else { throw Refusal.invalidButton }
            fields["buttonPhase"] = "beforePress"
            try verifyButton(button, pid: pid, identifier: identifier, diagnostics: &fields)
            guard (NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) == before else {
                throw Refusal.foregroundChanged
            }
            fields["axActionAttempted"] = true
            fields["actionUptime"] = ProcessInfo.processInfo.systemUptime
            let actionResult = AXUIElementPerformAction(button, kAXPressAction as CFString)
            fields["axErrorCode"] = actionResult.rawValue
            // Even an AX transport error may follow a delivered action. Never
            // retry or claim that an unsuccessful return proves no input.
            fields["result"] = actionResult == .success ? "axPressReturnedSuccess" : "pressOutcomeUnknown"
            result = actionResult == .success ? 0 : 2
        } catch {
            fields["result"] = "refused"
            fields["reason"] = (error as? Refusal)?.rawValue ?? "axUnavailable"
        }
        let after = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        fields["afterForegroundPID"] = after
        if fields["axActionAttempted"] as? Bool == true, after != before {
            fields["result"] = "pressOutcomeUnknownForegroundChanged"
            result = 2
        }
        fields["completionUptime"] = ProcessInfo.processInfo.systemUptime
        fields["attachmentResultVerified"] = false
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
            try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
        }
        return result
    }

    private static func verifyApplication(pid: pid_t, appURL: URL, phase: String,
                                          diagnostics: inout [String: Any]) throws -> ProcessIdentity {
        let running = NSRunningApplication(processIdentifier: pid)
        let bundle = Bundle(url: appURL)
        let executable = bundle?.executableURL?.standardizedFileURL.resolvingSymlinksInPath()
        let runningExecutable = running?.executableURL?.standardizedFileURL.resolvingSymlinksInPath()
        // proc_info.h defines this unavailable compound macro as 4 * MAXPATHLEN.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathCount = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        let pathRead = pathCount > 0 && pathCount < buffer.count
        let actual = pathRead
            ? URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL.resolvingSymlinksInPath() : nil
        var info = proc_bsdinfo()
        let infoSize = MemoryLayout<proc_bsdinfo>.size
        let infoCount = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(infoSize))
        }
        let checks: [(String, Bool)] = [
            ("runningFound", running != nil),
            ("notTerminated", running?.isTerminated == false),
            ("runningBundleIDMatches", running?.bundleIdentifier == "com.riftlet.app"),
            ("runningBundleURLMatches", running?.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == appURL),
            ("expectedBundleExists", bundle != nil),
            ("expectedBundleIDMatches", bundle?.bundleIdentifier == "com.riftlet.app"),
            ("expectedExecutablePresent", executable != nil),
            ("expectedExecutableUnderApp", executable?.path.hasPrefix(appURL.path + "/Contents/MacOS/") == true),
            ("runningExecutableMatches", executable != nil && runningExecutable == executable),
            ("procPathReadSucceeded", pathRead),
            ("procPathMatches", executable != nil && actual == executable),
            ("kernelInfoExactSize", infoCount == infoSize),
            ("kernelPIDMatches", info.pbi_pid == UInt32(pid)),
            ("kernelStartValid", info.pbi_start_tvsec > 0 && info.pbi_start_tvusec < 1_000_000)
        ]
        diagnostics["identityPhase"] = phase
        diagnostics["identityChecks"] = Dictionary(uniqueKeysWithValues: checks)
        // NSRunningApplication may omit launchDate for a directly launched bundle
        // executable. Kernel start sec/usec is mandatory instead, never guessed.
        diagnostics["launchDateAvailable"] = running?.launchDate != nil
        if let failed = checks.first(where: { !$0.1 }) {
            diagnostics["identityFailureStage"] = failed.0
            throw Refusal.applicationMismatch
        }
        diagnostics["identityFailureStage"] = "none"
        return ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec,
                               startMicroseconds: info.pbi_start_tvusec)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if error == .attributeUnsupported || error == .noValue { return nil }
        guard error == .success else { throw Refusal.axUnavailable }
        return value
    }

    private static func descendants(_ element: AXUIElement, _ name: String) throws -> [AXUIElement] {
        var count: CFIndex = 0
        let error = AXUIElementGetAttributeValueCount(element, name as CFString, &count)
        if error == .attributeUnsupported || error == .noValue { return [] }
        guard error == .success else { throw Refusal.axUnavailable }
        guard count >= 0, count <= 256 else { throw Refusal.traversalLimit }
        if count == 0 { return [] }
        var raw: CFArray?
        guard AXUIElementCopyAttributeValues(element, name as CFString, 0, count, &raw) == .success,
              let values = raw as? [Any], values.count == count else { throw Refusal.axUnavailable }
        return try values.map {
            guard CFGetTypeID($0 as CFTypeRef) == AXUIElementGetTypeID() else { throw Refusal.axUnavailable }
            return $0 as! AXUIElement
        }
    }

    private static func uniqueButton(in application: AXUIElement, pid: pid_t,
                                     identifier: String, diagnostics: inout [String: Any]) throws -> AXUIElement {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        var pending: [(AXUIElement, Int)] = [(application, 0)]
        var visited: [AXUIElement] = []
        var matches: [AXUIElement] = []
        var cursor = 0
        while cursor < pending.count {
            guard ProcessInfo.processInfo.systemUptime < deadline, pending.count <= 1024 else {
                throw Refusal.traversalLimit
            }
            let (element, depth) = pending[cursor]; cursor += 1
            if visited.contains(where: { CFEqual($0, element) }) { continue }
            guard visited.count < 512, depth <= 12 else { throw Refusal.traversalLimit }
            visited.append(element)
            guard AXUIElementSetMessagingTimeout(element, 0.1) == .success else { throw Refusal.axUnavailable }
            var elementPID: pid_t = 0
            guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == pid else {
                throw Refusal.applicationMismatch
            }
            if try attribute(element, kAXIdentifierAttribute) as? String == identifier {
                diagnostics["buttonPhase"] = "matchingIdentifier"
                try verifyButton(element, pid: pid, identifier: identifier, diagnostics: &diagnostics)
                matches.append(element)
                guard matches.count == 1 else { throw Refusal.ambiguousMatch }
            }
            for name in [kAXWindowsAttribute, kAXChildrenAttribute] {
                for child in try descendants(element, name) { pending.append((child, depth + 1)) }
            }
        }
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw Refusal.traversalLimit }
        guard let match = matches.first else { throw Refusal.noMatch }
        return match
    }

    private static func sampledAttribute(_ element: AXUIElement, _ name: String,
                                         key: String, diagnostics: inout [String: Any]) throws -> CFTypeRef? {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &raw)
        var errors = diagnostics["attributeErrors"] as? [String: Int32] ?? [:]
        errors[key] = error.rawValue
        diagnostics["attributeErrors"] = errors
        if error == .attributeUnsupported || error == .noValue { return nil }
        guard error == .success else { throw Refusal.axUnavailable }
        return raw
    }

    private static func verifyButton(_ button: AXUIElement, pid: pid_t, identifier: String,
                                     diagnostics: inout [String: Any]) throws {
        var owner: pid_t = 0
        let ownerError = AXUIElementGetPid(button, &owner)
        let actualID = try sampledAttribute(button, kAXIdentifierAttribute, key: "buttonIdentifier", diagnostics: &diagnostics)
        let role = try sampledAttribute(button, kAXRoleAttribute, key: "buttonRole", diagnostics: &diagnostics)
        let enabled = try sampledAttribute(button, kAXEnabledAttribute, key: "buttonEnabled", diagnostics: &diagnostics)
        var actions: CFArray?
        let actionError = AXUIElementCopyActionNames(button, &actions)
        diagnostics["actionNamesError"] = actionError.rawValue
        let checks: [(String, Bool)] = [
            ("samePID", ownerError == .success && owner == pid),
            ("identifierExact", actualID as? String == identifier),
            ("roleButton", role as? String == kAXButtonRole),
            ("enabledHasBool", enabled as? Bool != nil),
            ("enabledTrue", enabled as? Bool == true),
            ("pressAction", actionError == .success && (actions as? [String])?.contains(kAXPressAction) == true)
        ]
        diagnostics["buttonChecks"] = Dictionary(uniqueKeysWithValues: checks)
        if let failed = checks.first(where: { !$0.1 }) {
            diagnostics["buttonFailureStage"] = failed.0
            throw Refusal.invalidButton
        }
        diagnostics["buttonFailureStage"] = "none"
    }

    private static func verifyWindowMembership(_ button: AXUIElement, application: AXUIElement,
                                               pid: pid_t, diagnostics: inout [String: Any]) throws -> AXUIElement {
        diagnostics["windowFailureStage"] = "windowAttribute"
        guard let raw = try sampledAttribute(button, kAXWindowAttribute, key: "buttonWindow", diagnostics: &diagnostics),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw Refusal.invalidButton }
        let window = raw as! AXUIElement
        guard AXUIElementSetMessagingTimeout(window, 0.1) == .success else { throw Refusal.axUnavailable }
        var owner: pid_t = 0
        let ownerError = AXUIElementGetPid(window, &owner)
        let minimized = try sampledAttribute(window, kAXMinimizedAttribute, key: "windowMinimized", diagnostics: &diagnostics)
        diagnostics["windowFailureStage"] = "currentWindowsRead"
        let windows = try descendants(application, kAXWindowsAttribute)
        let checks: [(String, Bool)] = [
            ("windowElement", true), ("samePID", ownerError == .success && owner == pid),
            ("minimizedHasBool", minimized as? Bool != nil),
            ("notMinimized", minimized as? Bool == false),
            ("currentWindowsMember", windows.contains(where: { CFEqual($0, window) }))
        ]
        diagnostics["windowChecks"] = Dictionary(uniqueKeysWithValues: checks)
        if let failed = checks.first(where: { !$0.1 }) {
            diagnostics["windowFailureStage"] = failed.0
            throw Refusal.invalidButton
        }
        diagnostics["windowFailureStage"] = "none"
        return window
    }
}
