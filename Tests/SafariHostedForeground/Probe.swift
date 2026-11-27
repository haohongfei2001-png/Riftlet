import AppKit
import ApplicationServices
import Carbon

private enum Failure: Error { case invalidURL, browserAlreadyRunning, notAppleSafari, foregroundNotVerified }
private let safariID = "com.apple.Safari"

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
private func element(_ object: CFTypeRef?) -> AXUIElement? {
    guard let object, CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
    return (object as! AXUIElement)
}
private func label(_ node: AXUIElement, _ match: Set<String>) -> Bool {
    ["AXTitle", "AXDescription", "AXHelp"].contains { key in
        guard let value = attribute(node, key) as? String else { return false }
        return match.contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
private func search(_ root: AXUIElement, roles: Set<String>, labels: Set<String>) -> AXUIElement? {
    var queue = [root]
    var visited: [AXUIElement] = []
    while !queue.isEmpty && visited.count < 250 {
        let next = queue.removeFirst()
        guard !visited.contains(where: { CFEqual($0, next) }) else { continue }
        visited.append(next)
        if let role = attribute(next, "AXRole") as? String, roles.contains(role), label(next, labels) { return next }
        let children = (attribute(next, "AXChildren") as? [AXUIElement]) ?? []
        queue.append(contentsOf: children.prefix(80))
    }
    return nil
}
private func press(_ node: AXUIElement) -> Bool {
    AXUIElementPerformAction(node, kAXPressAction as CFString) == .success
}
private func checked(_ node: AXUIElement) -> Bool? {
    if let number = attribute(node, "AXValue") as? NSNumber { return number.boolValue }
    if let mark = attribute(node, "AXMenuItemMarkChar") as? String { return !mark.isEmpty }
    return nil
}
private func modal(_ app: AXUIElement) -> Bool {
    guard let window = element(attribute(app, "AXFocusedWindow")) else { return false }
    return (attribute(window, "AXModal") as? NSNumber)?.boolValue == true ||
        !((attribute(window, "AXSheets") as? [AXUIElement]) ?? []).isEmpty ||
        (attribute(window, "AXSubrole") as? String) == "AXDialog"
}
@MainActor
private func waitFor(_ lookup: () -> AXUIElement?) async -> AXUIElement? {
    for _ in 0..<24 {
        if let item = lookup() { return item }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return nil
}

@MainActor
private func developerOption(in safari: AXUIElement, pid: pid_t) async -> Bool {
    func foreground() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    func developer() -> AXUIElement? {
        guard let bar = element(attribute(safari, "AXMenuBar")) else { return nil }
        return search(bar, roles: ["AXMenuBarItem"], labels: ["develop", "developer"])
    }
    guard foreground(), let bar = element(attribute(safari, "AXMenuBar")) else {
        print("safariDeveloperGUI=BLOCKED_NO_MENUBAR"); return false
    }
    if developer() == nil {
        guard let safariMenu = search(bar, roles: ["AXMenuBarItem"], labels: ["safari"]),
              press(safariMenu), let settings = await waitFor({
                  search(safariMenu, roles: ["AXMenuItem"], labels: ["settings…", "settings...", "preferences…", "preferences..."])
              }), foreground(), press(settings)
        else { print("safariDeveloperGUI=BLOCKED_SETTING_MENU_ACTION"); return false }
        guard let focused = await waitFor({
            guard let window = element(attribute(safari, "AXFocusedWindow")),
                  search(window, roles: ["AXRadioButton", "AXButton", "AXTab"], labels: ["advanced"]) != nil
            else { return nil }
            return window
        }), foreground(), !modal(safari),
              let advanced = search(focused, roles: ["AXRadioButton", "AXButton", "AXTab"], labels: ["advanced"]),
              press(advanced)
        else { print("safariDeveloperGUI=BLOCKED_ADVANCED_TAB"); return false }
        guard let option = await waitFor({
            search(focused, roles: ["AXCheckBox"], labels: ["show features for web developers", "show develop menu in menu bar"])
        }), foreground(), !modal(safari), let before = checked(option)
        else { print("safariDeveloperGUI=BLOCKED_UNVERIFIED_DEVELOPER_CHECKBOX"); return false }
        if !before {
            guard press(option) else { print("safariDeveloperGUI=BLOCKED_DEVELOPER_CHECKBOX_ACTION"); return false }
            try? await Task.sleep(for: .milliseconds(250))
            if !foreground() || modal(safari) {
                print("safariDeveloperGUI=BLOCKED_DEVELOPER_PROMPT_UNTOUCHED"); return false
            }
        }
    }
    guard foreground(), let menu = await waitFor(developer), press(menu), let option = await waitFor({
        search(menu, roles: ["AXMenuItem"], labels: ["allow javascript from apple events"])
    }), foreground(), !modal(safari)
    else { print("safariDeveloperGUI=BLOCKED_NO_APPLE_EVENTS_MENU_ACTION"); return false }
    if checked(option) == true {
        print("safariDeveloperGUI=PASS_ALREADY_CHECKED"); return true
    }
    guard press(option) else { print("safariDeveloperGUI=BLOCKED_APPLE_EVENTS_MENU_ACTION"); return false }
    try? await Task.sleep(for: .milliseconds(250))
    guard foreground(), !modal(safari) else {
        print("safariDeveloperGUI=BLOCKED_SAFARI_APPROVAL_UNTOUCHED"); return false
    }
    guard let reopened = developer(), press(reopened), let rechecked = await waitFor({
        search(reopened, roles: ["AXMenuItem"], labels: ["allow javascript from apple events"])
    }), checked(rechecked) == true
    else { print("safariDeveloperGUI=BLOCKED_READBACK_NOT_CHECKED"); return false }
    print("safariDeveloperGUI=PASS_CHECKED_VIA_VISIBLE_MENU")
    return true
}

private actor ConsentResult {
    var value: OSStatus?
    func complete(_ status: OSStatus) { value = status }
}
@MainActor
private func observeConsent(safariPID: pid_t) async {
    func systemPromptWindows() -> Int {
        let ids: Set<String> = ["com.apple.SecurityAgent", "com.apple.CoreServicesUIAgent",
                                "com.apple.UserNotificationCenter", "com.apple.TCCUIAgent"]
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier.map(ids.contains) == true }
        let pids = Set(apps.map(\.processIdentifier))
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
        return rows.filter { row in
            guard let owner = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return false }
            return pids.contains(owner)
        }.count
    }
    let initial = systemPromptWindows()
    let box = ConsentResult()
    let pending = Task.detached {
        let target = NSAppleEventDescriptor(processIdentifier: safariPID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, 0x73667269, 0x646f6a73, true)
        await box.complete(status)
    }
    defer { pending.cancel() }
    for _ in 0..<40 {
        if systemPromptWindows() > initial {
            print("ordinaryAutomationConsent=SYSTEM_WINDOW_OBSERVED_NO_RESPONSE"); return
        }
        if let status = await box.value {
            print("ordinaryAutomationConsent=RETURNED osstatus=\(status) userConsentClicked=false"); return
        }
        try? await Task.sleep(for: .milliseconds(100))
    }
    print("ordinaryAutomationConsent=PENDING_UNATTRIBUTED userConsentClicked=false")
}

@main @MainActor struct Probe {
    static func main() async {
        do { try await run() }
        catch {
            print("BLOCKED_HOSTED_CAPABILITY \(type(of: error)) \(error)")
            exit(2)
        }
    }

    static func run() async throws {
        let appURL = URL(fileURLWithPath: "/Applications/Safari.app")
        guard CommandLine.arguments.count == 2,
              let page = URL(string: CommandLine.arguments[1]),
              page.scheme == "http", page.host == "127.0.0.1", page.path == "/riftlet-qa"
        else { throw Failure.invalidURL }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: safariID).isEmpty
        else { throw Failure.browserAlreadyRunning }
        print("displayCount=\(NSScreen.screens.count)")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let app = try await NSWorkspace.shared.open([page], withApplicationAt: appURL, configuration: config)
        guard app.bundleIdentifier == safariID else { throw Failure.notAppleSafari }
        defer { _ = app.terminate() }
        let version = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        print("safariVersion=\(version)")
        let pid = app.processIdentifier
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        var verified = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] ?? []
            let ordinaryWindow = onScreen.contains { row in
                (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
                (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
            }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && ordinaryWindow {
                verified = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard verified else { throw Failure.foregroundNotVerified }
        let trusted = AXIsProcessTrusted()
        let axApp = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        let ax = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window)
        let descriptor = NSAppleEventDescriptor(processIdentifier: pid)
        // Read only: this is the separate probe sender; never prompt or send Apple Events.
        let status = AEDeterminePermissionToAutomateTarget(descriptor.aeDesc, 0x73667269, 0x646f6a73, false)
        print("foreground=PASS windowServerOwnedWindow=PASS")
        print("axTrusted=\(trusted) axFocusedWindowStatus=\(ax.rawValue) axWindowPresent=\(window != nil)")
        print("appleEventsProbeSenderNonpromptingOSStatus=\(status)")
        guard trusted, ax == .success, window != nil else {
            print("safariDeveloperGUI=BLOCKED_AX ordinaryAutomationConsent=NOT_RUN")
            return
        }
        let developerReady = await developerOption(in: axApp, pid: pid)
        if developerReady && status == -1744 {
            await observeConsent(safariPID: pid)
        } else {
            print("ordinaryAutomationConsent=NOT_RUN developerReadback=\(developerReady) nonpromptingOSStatus=\(status)")
        }
        print("signedRiftletConsent=NOT_RUN signedCandidateDMG=NOT_PROVIDED nativeSite=NOT_RUN")
    }
}
