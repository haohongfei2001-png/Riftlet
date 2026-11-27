import AppKit
import ApplicationServices
import Carbon

private enum Failure: Error { case invalidURL, browserAlreadyRunning, notAppleSafari, foregroundNotVerified }
private let safariID = "com.apple.Safari"

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
        print("safariDeveloperSetting=NOT_OBSERVED signedRiftletConsent=NOT_RUN signedCandidateDMG=NOT_PROVIDED nativeSite=NOT_RUN")
    }
}
