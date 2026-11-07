import AppKit
import RiftletAdapters

@main private enum ChromeConsentFixture {
    private static let chromeApp = URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)

    static func identity(_ pid: pid_t) -> ChromeProcessIdentity? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleURL?.resolvingSymlinksInPath().path == chromeApp.resolvingSymlinksInPath().path else { return nil }
        return ChromeProcessIdentity.read(pid: pid)
    }

    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--identify-chrome", let pid = Int32(args[2]),
           let target = identity(pid) {
            print(target.session)
            return
        }
        guard args.count == 5, args[1] == "--fixture-root", args[3] == "--phase" else { exit(64) }
        let app = NSApplication.shared
        let delegate = Consent(root: URL(fileURLWithPath: args[2], isDirectory: true), phase: args[4])
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class Consent: NSObject, NSApplicationDelegate {
    let root: URL
    let phase: String
    let targetPID: pid_t
    let session: String
    let gate = AutomationPermissionGate(requiresChrome: true)
    var facts: [String: Any] = [:]

    init(root: URL, phase: String) {
        guard ["allow", "deny", "denied-restart", "settings-recovery"].contains(phase),
              let nonce = Bundle.main.object(forInfoDictionaryKey: "FixtureNonce") as? String,
              UUID(uuidString: nonce) != nil,
              Bundle.main.bundleIdentifier == "org.riftlet.release-identity-host." + nonce,
              root.lastPathComponent == "riftlet-automation-host-" + nonce,
              root.resolvingSymlinksInPath().path == root.path,
              Bundle.main.bundleURL.resolvingSymlinksInPath().path == root.appendingPathComponent("installed/Fixture.app").path,
              let data = try? Data(contentsOf: root.appendingPathComponent("target.json")),
              let target = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              target["nonce"] as? String == nonce, let pid = target["pid"] as? Int32,
              let expected = target["session"] as? String else { exit(65) }
        self.root = root; self.phase = phase; targetPID = pid; session = expected
    }

    var sameChrome: Bool { ChromeConsentFixture.identity(targetPID)?.session == session }

    func persist(_ stage: String, complete: Bool = false) {
        facts["stage"] = stage; facts["completed"] = complete
        do {
            let bytes = try JSONSerialization.data(withJSONObject:
                ["pid": ProcessInfo.processInfo.processIdentifier, "observations": facts])
            try bytes.write(to: root.appendingPathComponent(phase + ".json"), options: .atomic)
        } catch { exit(74) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        facts["displayAvailable"] = !NSScreen.screens.isEmpty
        persist("launched")
        Task { await run() }
    }

    func run() async {
        defer {
            facts["originalChromeStillCurrent"] = sameChrome
            persist("finished", complete: true)
            NSApp.terminate(nil)
        }
        guard !NSScreen.screens.isEmpty, sameChrome else { return }
        let before = await gate.inspect(expectedSession: session)
        facts["passiveBefore"] = String(describing: before)
        guard sameChrome else { return }
        if ["allow", "deny"].contains(phase), before == .notRequested {
            // This explicit fixture action uses the same one-request gate as
            // the product's settings button. It sends no page script or event.
            NSApp.activate(ignoringOtherApps: true)
            persist("requesting")
            let result = await gate.requestFromUserAction(expectedSession: session)
            facts["requestResult"] = String(describing: result)
        } else if phase == "settings-recovery", before == .denied {
            persist("openingAutomationSettings")
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                facts["settingsOpened"] = NSWorkspace.shared.open(url)
                let until = ProcessInfo.processInfo.systemUptime + 9
                while sameChrome && ProcessInfo.processInfo.systemUptime < until {
                    let state = await gate.inspect(expectedSession: session)
                    if state != .denied { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        guard sameChrome else { return }
        let after = await gate.inspect(expectedSession: session)
        facts["passiveAfter"] = String(describing: after)
    }
}
