import AppKit
import RiftletCore
import Security

extension ChromeProcessIdentity {
    /// Verify the running code and the kernel executable, including for browsers
    /// installed outside /Applications. Display names and numeric IDs are insufficient.
    func isSignedBrowser() -> Bool {
        let rule: String
        let executable: String
        switch applicationID {
        case AttachmentBrowser.chrome.rawValue:
            rule = developerIDRequirement(team: "EQHXZ8M8AV"); executable = "Google Chrome"
        case AttachmentBrowser.edge.rawValue:
            rule = developerIDRequirement(team: "UBF8T346G9"); executable = "Microsoft Edge"
        case AttachmentBrowser.safari.rawValue:
            // The system Safari is Apple platform code and has no Developer ID team.
            rule = "anchor apple and identifier \"com.apple.Safari\""; executable = "Safari"
        default: return false
        }
        guard isCurrent(), let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == applicationID, let bundle = app.bundleURL,
              let appExecutable = app.executableURL,
              let kernelPath = Self.kernelExecutablePath(pid),
              bundle.pathExtension == "app" else { return false }
        let expected = bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
            .resolvingSymlinksInPath().standardizedFileURL
        guard expected == appExecutable.resolvingSymlinksInPath().standardizedFileURL,
              expected.path == URL(fileURLWithPath: kernelPath).resolvingSymlinksInPath().standardizedFileURL.path else {
            return false
        }
        var requirement: SecRequirement?
        var guest: SecCode?
        let flags = SecCSFlags(rawValue: 0)
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecRequirementCreateWithString(rule as CFString, flags, &requirement) == errSecSuccess,
              let requirement, SecCodeCopyGuestWithAttributes(nil, attributes, flags, &guest) == errSecSuccess,
              let guest, SecCodeCheckValidity(guest, flags, requirement) == errSecSuccess else { return false }
        return isCurrent()
    }

    private func developerIDRequirement(team: String) -> String {
        "anchor apple generic and identifier \"\(applicationID)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
