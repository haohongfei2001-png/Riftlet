import AppKit
import ApplicationServices

// This runs as a CLI only on the disposable runner. Never request AX consent.
// Return only fixed status codes. Window text and process identifiers stay local.
private func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key, &result) == .success ? result : nil
}

private func inspect(_ window: AXUIElement, token: String, kind: String) -> [String: Any]? {
    var nodes = [window], index = 0, text = [String](), buttons = [(AXUIElement, [String])]()
    while index < nodes.count, index < 160 {
        let element = nodes[index]
        index += 1
        let strings = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap {
            attribute(element, $0 as CFString) as? String
        }
        text.append(contentsOf: strings)
        if attribute(element, kAXRoleAttribute as CFString) as? String == kAXButtonRole as String {
            buttons.append((element, strings))
        }
        if let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            nodes.append(contentsOf: children.prefix(max(0, 160 - nodes.count)))
        }
    }
    let visibleText = text.joined(separator: " ").lowercased()
    guard visibleText.contains(token), visibleText.contains("downloads") else { return nil }
    let titles: Set<String>
    let allowTitles: Set<String> = ["allow"]
    let denyTitles: Set<String> = ["don’t allow", "don't allow", "deny"]
    let labels = Set(buttons.flatMap { $0.1.map { $0.lowercased() } })
    if kind != "select" {
        guard !labels.isDisjoint(with: allowTitles), !labels.isDisjoint(with: denyTitles) else { return nil }
    }
    switch kind {
    case "select":
        guard visibleText.contains("choose fixture " + token) else { return nil }
        titles = ["select fixture"]
    case "observe": return ["state": "EXACT_NATIVE_PROMPT_OBSERVED_NO_ACTION"]
    case "allow": titles = allowTitles
    case "deny": titles = denyTitles
    default: return nil
    }
    let target = buttons.filter { button in button.1.contains { titles.contains($0.lowercased()) } }
    guard target.count == 1 else { return ["state": "EXACT_SURFACE_NO_UNIQUE_BUTTON"] }
    let status = AXUIElementPerformAction(target[0].0, kAXPressAction as CFString)
    return ["state": status == .success ? "AX_PRESS_SENT" : "AX_PRESS_FAILED",
            "action": kind, "axCode": status.rawValue]
}

private func observe() -> [String: Any] {
    let args = CommandLine.arguments
    guard args.count == 5, UUID(uuidString: args[1]) != nil, let ownPID = Int32(args[2]),
          ["allow", "deny", "select", "observe"].contains(args[3]) else { return ["state": "INVALID_ARGUMENTS"] }
    guard AXIsProcessTrusted() else { return ["state": "NOT_RUN_NO_EXISTING_AX_ACCESS"] }
    let token = args[1], kind = args[3], receipt = URL(fileURLWithPath: args[4])
    let systemConsentIDs: Set<String> = ["com.apple.usernotificationcenter", "com.apple.securityagent",
                                         "com.apple.coreservicesuiagent", "com.apple.notificationcenterui"]
    let until = ProcessInfo.processInfo.systemUptime + 6
    while ProcessInfo.processInfo.systemUptime < until {
        if let bytes = try? Data(contentsOf: receipt),
           let envelope = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
           let facts = envelope["observations"] as? [String: Any], facts["completed"] as? Bool == true { break }
        for app in NSWorkspace.shared.runningApplications {
            let bundleID = app.bundleIdentifier?.lowercased() ?? ""
            let systemHost = app.bundleURL?.resolvingSymlinksInPath().path.hasPrefix("/System/") == true
            if kind == "select" {
                guard app.processIdentifier == ownPID ||
                        (systemHost && bundleID == "com.apple.appkit.xpc.openandsavepanelservice") else { continue }
            } else {
                guard systemHost, systemConsentIDs.contains(bundleID) else { continue }
            }
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.25)
            let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
            for window in windows {
                if let result = inspect(window, token: token, kind: kind) { return result }
            }
        }
        Thread.sleep(forTimeInterval: 0.12)
    }
    return ["state": "NO_MATCHING_SURFACE_OBSERVED"]
}

let data = try JSONSerialization.data(withJSONObject: observe(), options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
