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
    let developerLabels: Set<String> = ["developer", "develop"]
    let advancedLabels: Set<String> = ["advanced"]
    let itemLabels: Set<String> = ["allow javascript from apple events"]
    let toolbarRoles: Set<String> = ["AXRadioButton", "AXButton", "AXTab"]
    func settingsWindow() -> AXUIElement? {
        let windows = attribute(safari, "AXWindows") as? [AXUIElement] ?? []
        return windows.first { window in
            search(window, roles: toolbarRoles, labels: advancedLabels) != nil
        }
    }
    guard foreground(), !modal(safari),
          let down = CGEvent(keyboardEventSource: nil, virtualKey: 43, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 43, keyDown: false)
    else { print("settingsShortcut=BLOCKED_PREFLIGHT"); return false }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.postToPid(pid)
    up.postToPid(pid)
    guard let settings = await waitFor(settingsWindow), foreground() else {
        print("settingsShortcut=BLOCKED_WINDOW_NOT_FOUND"); return false
    }
    print("settingsShortcut=PASS")
    func developerTab() -> AXUIElement? { search(settings, roles: toolbarRoles, labels: developerLabels) }
    if developerTab() == nil {
        guard let advanced = search(settings, roles: toolbarRoles, labels: advancedLabels), press(advanced),
              let checkbox = await waitFor({
                  search(settings, roles: ["AXCheckBox"], labels: ["show features for web developers", "show develop menu in menu bar"])
              }), foreground(), !modal(safari), let initial = checked(checkbox)
        else { print("settingsDeveloper=BLOCKED_ADVANCED_CHECKBOX_NOT_VERIFIED"); return false }
        print("settingsAdvancedDeveloperCheckbox=\(initial)")
        if !initial, !press(checkbox) { print("settingsDeveloper=BLOCKED_ADVANCED_CHECKBOX_PRESS"); return false }
    }
    guard let developer = await waitFor(developerTab), foreground(), !modal(safari) else {
        print("settingsDeveloper=BLOCKED_TAB_NOT_AVAILABLE_OR_MODAL"); return false
    }
    let tabCode = AXUIElementPerformAction(developer, kAXPressAction as CFString)
    print("settingsDeveloperTabPress=\(tabCode.rawValue)")
    guard tabCode == .success else { return false }
    guard let checkbox = await waitFor({
        search(settings, roles: ["AXCheckBox"], labels: itemLabels)
    }), let initial = checked(checkbox), foreground(), !modal(safari) else {
        let recognizedDescriptions: Set<String> = ["allow javascript from apple events", "allow remote automation",
          "allow unsigned extensions", "show automation menu", "developer", "develop", "advanced"]
        let roles: Set<String> = ["AXCheckBox", "AXMenuItem", "AXPopUpButton", "AXButton", "AXRadioButton", "AXStaticText"]
        for name in recognizedDescriptions.sorted() {
            if search(settings, roles: roles, labels: [name]) != nil { print("settingsDeveloperRecognizedLabel=\(name)") }
        }
        print("settingsDeveloper=BLOCKED_APPLE_EVENTS_CHECKBOX_NOT_VERIFIED")
        return false
    }
    print("settingsDeveloperAppleEventsBefore=\(initial)")
    if !initial, !press(checkbox) { print("settingsDeveloper=BLOCKED_APPLE_EVENTS_PRESS"); return false }
    let possiblePromptOwners: Set<String> = ["com.apple.SecurityAgent", "com.apple.CoreServicesUIAgent",
        "com.apple.UserNotificationCenter", "com.apple.TCCUIAgent"]
    for _ in 0..<24 {
        let focused = element(attribute(safari, "AXFocusedWindow"))
        let windows = attribute(safari, "AXWindows") as? [AXUIElement] ?? []
        let sheets = windows.reduce(0) { $0 + ((attribute($1, "AXSheets") as? [AXUIElement]) ?? []).count }
        let dialogWindows = windows.filter {
            (attribute($0, "AXSubrole") as? String) == "AXDialog" || (attribute($0, "AXModal") as? NSNumber)?.boolValue == true
        }.count
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if sheets > 0 || dialogWindows > 0 || modal(safari) || front.map(possiblePromptOwners.contains) == true {
            let approvalText: Set<String> = ["allow javascript from apple events", "allow", "cancel", "turn on"]
            let seen = approvalText.sorted().filter { name in windows.contains { window in
                search(window, roles: ["AXButton", "AXStaticText"], labels: [name]) != nil
            } }
            print("settingsDeveloper=BLOCKED_APPROVAL_UI_UNTOUCHED sheetCount=\(sheets) dialogCount=\(dialogWindows) systemPromptOwner=\(front.map(possiblePromptOwners.contains) == true) recognizedLabels=\(seen.joined(separator: ","))")
            return false
        }
        guard foreground() else {
            print("settingsDeveloper=BLOCKED_FOCUS_CHANGED focusedWindow=\(focused != nil)"); return false
        }
        if let refreshed = search(settings, roles: ["AXCheckBox"], labels: itemLabels),
           checked(refreshed) == true {
            print("settingsDeveloper=PASS_READBACK_CHECKED")
            return true
        }
        try? await Task.sleep(for: .milliseconds(100))
    }
    print("settingsDeveloper=BLOCKED_CHECKBOX_NOT_CHECKED_AFTER_2S")
    return false
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
