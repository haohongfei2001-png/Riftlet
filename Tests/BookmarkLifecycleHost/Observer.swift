import AppKit
import ApplicationServices

// Only on the disposable Aqua session. Never request accessibility privileges.
private func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success ? value : nil
}
private func strings(_ node: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].compactMap { attr(node, $0) as? String }
}
private func role(_ node: AXUIElement) -> String { attr(node, kAXRoleAttribute) as? String ?? "" }
private func children(_ node: AXUIElement) -> [AXUIElement] { attr(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
private func nodes(_ root: AXUIElement, limit: Int) -> [AXUIElement]? {
    var all = [root], index = 0
    while index < all.count {
        all.append(contentsOf: children(all[index])); index += 1
        guard all.count <= limit else { return nil }
    }
    return all
}
private func normalized(_ str: String) -> String {
    str.lowercased().filter { !"“”‘’\"".contains($0) }.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}
private func matchesHeading(_ raw: String, sender: String, target: String, files: Bool) -> Bool {
    let a = normalized(sender), b = normalized(target)
    let phrases = files ? ["allow \(a) to access files in your documents folder", "\(a) would like to access files in your documents folder",
                           "\(a) wants to access files in your documents folder"] :
        ["allow \(a) to control \(b)", "\(a) wants access to control \(b)", "\(a) would like to control \(b)", "\(a) wants to control \(b)"]
    let title = normalized(raw)
    return phrases.contains { title == $0 || title == $0 + "?" || title == $0 + "." }
}
private func press(_ node: AXUIElement) -> [String: Any] {
    let code = AXUIElementPerformAction(node, kAXPressAction as CFString)
    return ["state": code == .success ? "PRESS_ACK" : "PRESS_UNCONFIRMED", "axCode": code.rawValue]
}
private func alert(_ window: AXUIElement, sender: String, receiver: String, files: Bool, action: String) -> [String: Any]? {
    guard let all = nodes(window, limit: 230),
          let heading = all.filter({ role($0) == "AXStaticText" || role($0) == "AXWindow" || role($0) == "AXHeading" }).flatMap(strings)
          .first(where: { matchesHeading($0, sender: sender, target: receiver, files: files) }) else { return nil }
    let buttons = all.filter { role($0) == "AXButton" }
    let yes = buttons.filter { !Set(strings($0)).isDisjoint(with: files ? ["Allow"] : ["Allow","OK"]) }
    let no = buttons.filter { !Set(strings($0)).isDisjoint(with: ["Don’t Allow","Don't Allow","Deny"]) }
    guard yes.count == 1, no.count == 1 else { return nil }
    let target = action == "allow" ? yes[0] : no[0]
    var result = press(target)
    let choices = Set(["Allow","OK","Don’t Allow","Don't Allow","Deny"])
    result["button"] = strings(target).first(where: { choices.contains($0) })
    result["systemHeading"] = heading
    return result
}
private func picker(_ window: AXUIElement, nonce: String) -> [String: Any]? {
    guard let all = nodes(window, limit: 540),
          all.flatMap(strings).contains("Choose fixture " + nonce) else { return nil }
    let matches = all.filter { role($0) == "AXButton" && strings($0).contains("Select fixture") }
    guard matches.count == 1 else { return nil }
    return press(matches[0])
}
private func settings(_ window: AXUIElement, sender: String, target: String, files: Bool, expanded: inout Bool) -> [String: Any]? {
    let section = files ? "Files & Folders" : "Automation"
    guard let all = nodes(window, limit: 600), all.flatMap(strings).contains(section) else { return nil }
    let rows = all.filter { item in
        let r = role(item)
        guard ["AXRow", "AXDisclosureGroup", "AXGroup"].contains(r) else { return false }
        if strings(item).contains(sender) { return true }
        return r != "AXGroup" && children(item).contains { role($0) == "AXStaticText" && strings($0).contains(sender) }
    }
    guard rows.count == 1, let members = nodes(rows[0], limit: 40) else { return nil }
    let controls = members.filter { ["AXCheckBox","AXSwitch"].contains(role($0)) && strings($0).contains(target) }
    if controls.isEmpty && !expanded {
        let triangles = members.filter { role($0) == "AXDisclosureTriangle" }
        if triangles.count == 1, (attr(triangles[0], kAXValueAttribute) as? NSNumber)?.intValue == 0 {
            expanded = true
            _ = AXUIElementPerformAction(triangles[0], kAXPressAction as CFString)
        }
        return nil
    }
    guard controls.count == 1, let control = controls.first,
          (attr(control, kAXEnabledAttribute) as? NSNumber)?.boolValue == true,
          (attr(control, kAXValueAttribute) as? NSNumber)?.intValue == 0 else { return nil }
    return press(control)
}
private func observe() -> [String: Any] {
    let args = CommandLine.arguments
    guard args.count == 7, UUID(uuidString: args[1]) != nil, let pid = Int32(args[3]),
          ["book","docallow","docdeny","aeallow","aedeny"].contains(args[2]), ["select","allow","deny","settings"].contains(args[4]) else { return ["state":"INVALID"] }
    guard AXIsProcessTrusted() else { return ["state":"NO_EXISTING_AX"] }
    let token = args[1], kind = args[2], action = args[4]
    let files = kind.hasPrefix("doc"), expectedStage = action == "settings" ? "recovering" : action == "select" ? "showingPanel" : files ? "reading" : "requesting"
    let owner = URL(fileURLWithPath: args[5], isDirectory: true).resolvingSymlinksInPath()
    let label = kind.hasPrefix("doc") ? "Riftlet Files " : "Riftlet Consent "
    let sender = label + (kind.hasSuffix("allow") ? "Allow " : "Deny ") + token
    let receiver = "Riftlet Receiver " + token
    let systemHosts = Set(["com.apple.usernotificationcenter","com.apple.securityagent","com.apple.coreservicesuiagent","com.apple.notificationcenterui"])
    let deadline = ProcessInfo.processInfo.systemUptime + 7
    var expanded = false
    while ProcessInfo.processInfo.systemUptime < deadline {
        guard let own = NSRunningApplication(processIdentifier: pid),
              own.bundleURL?.resolvingSymlinksInPath() == owner, own.bundleIdentifier == "org.riftlet.scopedlab." + kind + "." + token,
              !own.isTerminated else { return ["state":"OWNER_EXITED_OR_DIFFERENT"] }
        // Only interact while the identified requesting process is in this phase.
        let data = try? String(contentsOfFile: args[6], encoding: .utf8)
        if let line = data?.split(separator: "\n").last,
           let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
           event["token"] as? String == token, event["pid"] as? Int32 == pid,
           event["role"] as? String == kind, event["stage"] as? String == expectedStage {
            for host in NSWorkspace.shared.runningApplications {
                let id = host.bundleIdentifier?.lowercased() ?? ""
                let sys = host.bundleURL?.resolvingSymlinksInPath().path.hasPrefix("/System/") == true
                if action == "settings" {
                    guard sys && id == "com.apple.systempreferences" else { continue }
                } else if action == "select" {
                    guard host.processIdentifier == pid || (sys && id == "com.apple.appkit.xpc.openandsavepanelservice") else { continue }
                } else { guard sys && systemHosts.contains(id) else { continue } }
                let ax = AXUIElementCreateApplication(host.processIdentifier)
                AXUIElementSetMessagingTimeout(ax, 0.3)
                let windows = attr(ax,kAXWindowsAttribute) as? [AXUIElement] ?? []
                for win in windows {
                    var result: [String: Any]?
                    if action == "select" { result = picker(win, nonce: token) }
                    else if action == "settings" { result = settings(win, sender: sender, target: files ? "Documents Folder" : receiver, files: files, expanded: &expanded) }
                    else { result = alert(win,sender: sender,receiver: receiver,files: files,action: action) }
                    if var result {
                        result["verifiedSurfaceHost"] = host.processIdentifier == pid ? "verified-test-app" : id
                        result["requestingPIDAndBundleMatched"] = true
                        if let title = result["systemHeading"] as? String {
                            result["systemHeading"] = title.replacingOccurrences(of: token, with: "<test-id>", options: [.caseInsensitive])
                        }
                        return result
                    }
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.13)
    }
    return ["state":"NO_IDENTIFIED_SURFACE"]
}
let data = try JSONSerialization.data(withJSONObject: observe(), options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
