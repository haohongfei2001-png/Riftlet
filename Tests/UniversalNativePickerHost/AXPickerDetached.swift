import AppKit
import CryptoKit
import ApplicationServices

/// Separate processes. Receiver has activation prohibited and no ordered
/// windows. Only the generated control in our own ephemeral PID is actionable.
@main private struct Detached {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 && args[1] == "--receive" || args.count == 4 && args[1] == "--observe" else { exit(64) }
        let file = URL(fileURLWithPath: args[2]); guard file.lastPathComponent == "token", let token = try? String(contentsOf: file, encoding: .utf8), UUID(uuidString: token) != nil else { exit(64) }
        let app = NSApplication.shared
        if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
        guard app.activationPolicy() == .prohibited else { exit(1) }
        if args[1] == "--receive" {
            let host = Host(root: file.deletingLastPathComponent(), token: token)
            host.prepare()
            withExtendedLifetime(host) { app.run() }
        } else if args[1] == "--observe", let pid = Int32(args[3]) {
            guard AXIsProcessTrusted() else { print("NOT_RUN_NO_EXISTING_AX_TRUST"); exit(77) }
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.25)
            var match: AXUIElement?
            var visited = 0
            repeat {
                var nodes = [application]
                var cursor = 0
                while cursor < nodes.count && nodes.count < 64 {
                    let node = nodes[cursor]; cursor += 1
                    var owner: pid_t = 0
                    guard AXUIElementGetPid(node, &owner) == .success, owner == pid else { exit(1) }
                    if attr(node, kAXIdentifierAttribute) as? String == token {
                        guard match == nil || CFEqual(match, node) else { exit(1) }; match = node
                    }
                    for key in [kAXChildrenAttribute, kAXWindowsAttribute] {
                        for child in attr(node, key) as? [AXUIElement] ?? [] where !nodes.contains(where: { CFEqual($0, child) }) { nodes.append(child) }
                    }
                }
                visited = max(visited, nodes.count)
                if match == nil { Thread.sleep(forTimeInterval: 0.05) }
            } while match == nil && ProcessInfo.processInfo.systemUptime < deadline
            guard let entry = match else { print("DETACHED_AX_TREE_UNAVAILABLE_nodes_\(visited)"); exit(2) }
            var names: CFArray?
            guard attr(entry, kAXRoleAttribute) as? String == kAXRadioButtonRole,
                  AXUIElementCopyActionNames(entry, &names) == .success,
                  (names as? [String])?.contains(kAXPressAction) == true else { print("DETACHED_NO_PRESS_ACTION"); exit(2) }
            guard AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success else { print("DETACHED_PRESS_UNKNOWN"); exit(2) }
            let end = ProcessInfo.processInfo.systemUptime + 1
            var submit: AXUIElement?
            var phase = "untested"
            repeat {
                let controls = attr(application, kAXChildrenAttribute) as? [AXUIElement] ?? []
                let matches = controls.filter { attr($0, kAXIdentifierAttribute) as? String == "submit-" + token }
                let receipts = controls.filter { attr($0, kAXIdentifierAttribute) as? String == "selected-" + token }
                let state = (attr(entry, kAXValueAttribute) as? NSNumber)?.intValue ?? -1
                let enabled = matches.count == 1 && attr(matches[0], kAXEnabledAttribute) as? Bool == true
                phase = "controls_\(controls.count)_buttons_\(matches.count)_receipts_\(receipts.count)_state_\(state)_enabled_\(enabled)"
                if matches.count == 1, receipts.count == 1, state == 1, enabled { submit = matches[0]; break }
                Thread.sleep(forTimeInterval: 0.035)
            } while ProcessInfo.processInfo.systemUptime < end
            guard let submit, attr(submit, kAXRoleAttribute) as? String == kAXButtonRole else { print("DETACHED_SELECTION_UNPROVEN_\(phase)"); exit(2) }
            var owner: pid_t = 0
            guard AXUIElementGetPid(submit, &owner) == .success, owner == pid,
                  AXUIElementCopyActionNames(submit, &names) == .success, (names as? [String])?.contains(kAXPressAction) == true else { print("DETACHED_SUBMIT_NOT_AVAILABLE"); exit(2) }
            guard AXUIElementPerformAction(submit, kAXPressAction as CFString) == .success else { print("DETACHED_SUBMIT_UNKNOWN"); exit(2) }
            print("DETACHED_SELECTION_AND_SUBMIT_AXPRESS_ONCE")
        } else { exit(64) }
    }
    static func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }; return value
    }
}
@MainActor private final class Host: NSObject {
    let root: URL
    let token: String
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 50), styleMask: [.titled], backing: .buffered, defer: false)
    let choice = AXPickerActionButton()
    let submit = AXPickerActionButton()
    let stateLabel = NSTextField(labelWithString: "Empty")
    var selected: URL?
    var selectionActions = 0
    var submitActions = 0
    init(root: URL, token: String) { self.root = root; self.token = token }
    func prepare() {
        choice.frame = NSRect(x: 10, y: 10, width: 140, height: 28)
        choice.title = "Neutral fixture"
        choice.setButtonType(.radio)
        choice.target = self; choice.action = #selector(pressed)
        choice.setAccessibilityElement(true); choice.setAccessibilityRole(.radioButton); choice.setAccessibilityIdentifier(token)
        window.contentView?.addSubview(choice)
        // The cooperating host explicitly exposes its detached generated AX
        // element. No element from any other PID enters this accessibility tree.
        submit.frame = NSRect(x: 0, y: 0, width: 80, height: 20)
        submit.title = "Attach"
        submit.target = self; submit.action = #selector(confirm)
        submit.setAccessibilityElement(true); submit.setAccessibilityRole(.button); submit.setAccessibilityIdentifier("submit-" + token)
        submit.isEnabled = false
        stateLabel.setAccessibilityElement(true); stateLabel.setAccessibilityIdentifier("empty-" + token)
        window.contentView?.addSubview(submit)
        window.contentView?.addSubview(stateLabel)
        NSApp.setAccessibilityChildren([choice, submit, stateLabel])
        guard !window.isVisible, !NSApp.isActive else { exit(1) }
        try? Data().write(to: root.appendingPathComponent("ready"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(3) }
    }
    @objc func pressed() {
        selectionActions += 1
        guard !window.isVisible, !NSApp.isActive, choice.state == .on, selectionActions == 1 else { exit(1) }
        selected = root.appendingPathComponent("neutral.png")
        stateLabel.stringValue = "Selected"
        stateLabel.setAccessibilityIdentifier("selected-" + token)
        submit.isEnabled = true
    }
    @objc func confirm() {
        submitActions += 1
        guard !window.isVisible, !NSApp.isActive, selectionActions == 1, submitActions == 1,
              let selected, let bytes = try? Data(contentsOf: selected) else { exit(1) }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        do { try Data((token + " " + digest).utf8).write(to: root.appendingPathComponent("receipt"), options: .withoutOverwriting) }
        catch { exit(1) }
    }
}
