import AppKit
import ApplicationServices

// This runs as a CLI only on the disposable runner. Never request AX consent.
// Return only fixed status codes. Window text and process identifiers stay local.
private func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key, &result) == .success ? result : nil
}

private func isAutomationHeading(_ text: String, token: String) -> Bool {
    let title = text.lowercased().filter { !"“”‘’\"".contains($0) }
        .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    let sender = "riftlet ci " + token.lowercased()
    let headings = ["allow " + sender + " to control google chrome",
                    sender + " wants access to control google chrome",
                    sender + " would like to control google chrome",
                    sender + " wants to control google chrome"]
    return headings.contains { title == $0 || title.hasPrefix($0 + ".") || title.hasPrefix($0 + "?") }
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
    let automation = kind.hasPrefix("automation-")
    guard visibleText.contains(token) else { return nil }
    if automation {
        guard text.contains(where: { isAutomationHeading($0, token: token) }) else { return nil }
    } else if !visibleText.contains("downloads") { return nil }
    let titles: Set<String>
    let allowTitles: Set<String> = automation ? ["allow", "ok"] : ["allow"]
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
    case "allow", "automation-allow": titles = allowTitles
    case "deny", "automation-deny": titles = denyTitles
    default: return nil
    }
    let target = buttons.filter { button in button.1.contains { titles.contains($0.lowercased()) } }
    guard target.count == 1 else { return ["state": "EXACT_SURFACE_NO_UNIQUE_BUTTON"] }
    let status = AXUIElementPerformAction(target[0].0, kAXPressAction as CFString)
    return ["state": status == .success ? "AX_PRESS_SENT" : "AX_PRESS_FAILED",
            "action": kind, "axCode": status.rawValue]
}

private func labels(_ element: AXUIElement) -> Set<String> {
    Set([kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attribute(element, $0 as CFString) as? String })
}

private func role(_ element: AXUIElement) -> String {
    attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func descendants(_ element: AXUIElement, limit: Int) -> [AXUIElement]? {
    var result = [element], index = 0
    while index < result.count {
        let next = children(result[index])
        guard result.count + next.count <= limit else { return nil }
        result.append(contentsOf: next)
        index += 1
    }
    return result
}

// Only an off receiver switch inside the *identified sender row* is eligible.
// Unknown hierarchy, localization, authentication or multiple matching rows
// leave recovery untested. Never toggle a screen-wide "Google Chrome" match.
private func recover(_ window: AXUIElement, token: String, expanded: inout Bool) -> [String: Any]? {
    guard let nodes = descendants(window, limit: 400),
          nodes.contains(where: { labels($0).contains("Automation") }) else { return nil }
    let sender = "Riftlet CI " + token
    let rows = nodes.filter { node in
        let names = labels(node)
        guard ["AXRow", "AXDisclosureGroup", "AXGroup"].contains(role(node)) else { return false }
        if names.contains(sender) { return true }
        return role(node) != "AXGroup" && children(node).contains { role($0) == "AXStaticText" && labels($0).contains(sender) }
    }
    guard rows.count == 1, let members = descendants(rows[0], limit: 32) else { return nil }
    let switches = members.filter { item in
        ["AXCheckBox", "AXSwitch"].contains(role(item)) && labels(item).contains("Google Chrome")
    }
    if switches.isEmpty && !expanded {
        let triangles = members.filter { role($0) == "AXDisclosureTriangle" }
        if triangles.count == 1, (attribute(triangles[0], kAXValueAttribute as CFString) as? NSNumber)?.intValue == 0 {
            expanded = true
            _ = AXUIElementPerformAction(triangles[0], kAXPressAction as CFString)
        }
        return nil
    }
    guard switches.count == 1, let button = switches.first,
          (attribute(button, kAXEnabledAttribute as CFString) as? NSNumber)?.boolValue == true,
          (attribute(button, kAXValueAttribute as CFString) as? NSNumber)?.intValue == 0 else { return nil }
    let code = AXUIElementPerformAction(button, kAXPressAction as CFString)
    return ["state": code == .success ? "AX_PRESS_SENT" : "AX_PRESS_FAILED", "action": "automation-recovery", "axCode": code.rawValue]
}

private func observe() -> [String: Any] {
    let args = CommandLine.arguments
    guard args.count == 5, UUID(uuidString: args[1]) != nil, let ownPID = Int32(args[2]),
          ["allow", "deny", "select", "observe", "automation-allow", "automation-deny", "automation-recovery"].contains(args[3]) else { return ["state": "INVALID_ARGUMENTS"] }
    guard AXIsProcessTrusted() else { return ["state": "NOT_RUN_NO_EXISTING_AX_ACCESS"] }
    let token = args[1], kind = args[3], receipt = URL(fileURLWithPath: args[4])
    let automation = kind.hasPrefix("automation-")
    if automation && NSRunningApplication(processIdentifier: ownPID)?.bundleIdentifier != "org.riftlet.release-identity-host." + token {
        return ["state": "SENDER_IDENTITY_UNAVAILABLE"]
    }
    var expanded = false
    let systemConsentIDs: Set<String> = ["com.apple.usernotificationcenter", "com.apple.securityagent",
                                         "com.apple.coreservicesuiagent", "com.apple.notificationcenterui"]
    let until = ProcessInfo.processInfo.systemUptime + 6
    while ProcessInfo.processInfo.systemUptime < until {
        if let bytes = try? Data(contentsOf: receipt),
           let envelope = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
           let facts = envelope["observations"] as? [String: Any] {
            if facts["completed"] as? Bool == true { break }
            if automation && facts["stage"] as? String != (kind == "automation-recovery" ? "openingAutomationSettings" : "requesting") {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
        } else if automation { break }
        for app in NSWorkspace.shared.runningApplications {
            let bundleID = app.bundleIdentifier?.lowercased() ?? ""
            let systemHost = app.bundleURL?.resolvingSymlinksInPath().path.hasPrefix("/System/") == true
            if kind == "automation-recovery" {
                guard systemHost, bundleID == "com.apple.systempreferences" else { continue }
            } else if kind == "select" {
                guard app.processIdentifier == ownPID ||
                        (systemHost && bundleID == "com.apple.appkit.xpc.openandsavepanelservice") else { continue }
            } else {
                guard systemHost, systemConsentIDs.contains(bundleID) else { continue }
            }
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.25)
            let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
            for window in windows {
                let result = kind == "automation-recovery" ? recover(window, token: token, expanded: &expanded)
                    : inspect(window, token: token, kind: kind)
                if let result { return result }
            }
        }
        Thread.sleep(forTimeInterval: 0.12)
    }
    return ["state": "NO_MATCHING_SURFACE_OBSERVED"]
}

let data = try JSONSerialization.data(withJSONObject: observe(), options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
