import AppKit
import ApplicationServices

/// Installed bundle and already-running process only. No launch/activation,
/// enumeration of draft elements, AXValue/title, chat content or actions.
@main private struct Inventory {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true)
        var facts: [String: Any] = ["surface": "NOT_RUN", "input": "NOT_RUN", "axTrustedForProbeProcess": AXIsProcessTrusted()]
        if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            facts["installed"] = true
            facts["bundleID"] = id
            facts["version"] = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            facts["build"] = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter {
                !$0.isTerminated && $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path
            }
            facts["runningInstancesOfInstalledBundle"] = candidates.count
            if candidates.count == 1, let app = candidates.first {
                let pid = app.processIdentifier
                let front = NSWorkspace.shared.frontmostApplication
                facts["foregroundAtSample"] = front?.processIdentifier == pid && front?.launchDate == app.launchDate
                facts["launchIdentityAvailable"] = app.launchDate != nil
                if AXIsProcessTrusted() {
                    let object = AXUIElementCreateApplication(pid)
                    let bounded = AXUIElementSetMessagingTimeout(object, 0.25)
                    var count: CFIndex = 0
                    if bounded == .success {
                        let status = AXUIElementGetAttributeValueCount(object, kAXWindowsAttribute as CFString, &count)
                        facts["axWindowCountStatus"] = status.rawValue
                        if status == .success { facts["axWindowCount"] = count }
                        var window: CFTypeRef?
                        let result = AXUIElementCopyAttributeValue(object, kAXFocusedWindowAttribute as CFString, &window)
                        facts["axFocusedWindowStatus"] = result.rawValue
                        if result == .success, let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
                            var owner: pid_t = 0
                            let read = AXUIElementGetPid(window as! AXUIElement, &owner)
                            let current = NSRunningApplication(processIdentifier: pid)
                            facts["focusedWindowBoundToSampledProcess"] = read == .success && owner == pid &&
                                current?.bundleIdentifier == id && current?.launchDate == app.launchDate && app.launchDate != nil
                        }
                    }
                }
            }
        } else { facts["installed"] = false }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: .sortedKeys), as: UTF8.self))
    }
}
