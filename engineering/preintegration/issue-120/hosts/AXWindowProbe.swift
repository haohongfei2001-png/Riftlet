// Read the AX windows of the single guest browser launched for the local fixture.
// No AX press, keystroke, browser script, file selection or permission changes.
import AppKit
import ApplicationServices
import Darwin

@main struct AXWindowProbe {
    static func main() throws {
        let args = CommandLine.arguments
        var model = [CChar](repeating: 0, count: 128), size = 128
        guard args.count == 3, sysctlbyname("hw.model", &model, &size, nil, 0) == 0,
              String(cString: model) == "VirtualMac2,1",
              ["com.apple.Safari", "org.mozilla.firefox", "com.brave.Browser"].contains(args[1]) else { exit(2) }
        let folder = URL(fileURLWithPath: args[2], isDirectory: true)
        guard folder.deletingLastPathComponent().path == "/private/tmp", folder.lastPathComponent.hasPrefix("riftlet-ax-") else { exit(2) }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: args[1])
        guard apps.count == 1, let app = apps.first, let url = app.bundleURL,
              (args[1] == "com.apple.Safari"
                ? ["/Applications/Safari.app", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"].contains(url.path)
                : url.deletingLastPathComponent() == folder) else { exit(2) }
        let target = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(target, 2)
        var windows: CFTypeRef?
        let code = AXUIElementCopyAttributeValue(target, kAXWindowsAttribute as CFString, &windows)
        let trusted = AXIsProcessTrusted()
        var record: [String: Any] = [
            "browser": args[1], "browserVersion": Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown",
            "trusted": trusted, "axWindowsError": code.rawValue, "productPermission": "NOT_RUN"
        ]
        if code == .success, let list = windows as? [AXUIElement] {
            record["windows"] = list.count
            var fixtureCount = 0
            for window in list {
                var title: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
                   (title as? String)?.contains("Riftlet AX synthetic") == true { fixtureCount += 1 }
            }
            record["fixtureWindows"] = fixtureCount
        }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try data.write(to: folder.appendingPathComponent(args[1] + ".json"), options: .withoutOverwriting)
    }
}
