import AppKit
import ApplicationServices
import Carbon
import RiftletCore

/// The pre-release host directory is separate from the stable AttachmentBrowser registry.
@MainActor enum CandidateBrowserHosts {
    static func host(for bundle: String) -> (any BrowserHost)? {
        switch bundle {
        case BraveBrowserHost.applicationID: return BraveBrowserHost()
        case "com.apple.Safari": return AXBrowserHost(browser: .safari)
        case "org.mozilla.firefox": return AXBrowserHost(browser: .firefox)
        default: return nil
        }
    }
}

struct CandidateReceiver: Equatable {
    let bundle: String
    let birth: KernelProcessBirth

    var session: String { "\(bundle):\(birth.pid):\(birth.seconds):\(birth.microseconds)" }

    static func read(_ app: NSRunningApplication?, bundle: String) -> Self? {
        guard let app, let birth = KernelProcessBirth.read(pid: app.processIdentifier),
              !app.isTerminated, app.bundleIdentifier == bundle,
              NSRunningApplication(processIdentifier: birth.pid)?.bundleIdentifier == bundle,
              KernelProcessBirth.read(pid: birth.pid) == birth else { return nil }
        return Self(bundle: bundle, birth: birth)
    }

    @MainActor static func foreground(_ bundle: String) -> Self? {
        read(NSWorkspace.shared.frontmostApplication, bundle: bundle)
    }

    @MainActor static func forSettings(_ bundle: String) -> Self? {
        if let front = foreground(bundle) { return front }
        let processes = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).filter { !$0.isTerminated }
        guard processes.count == 1 else { return nil }
        return read(processes[0], bundle: bundle)
    }

    static func automationState(_ status: OSStatus) -> OriginalReceiverAccess {
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent): return .permissionRequired
        default: return .unavailable
        }
    }

    func automationState() -> OriginalReceiverAccess {
        let address = NSAppleEventDescriptor(processIdentifier: birth.pid)
        let status = AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, false)
        guard KernelProcessBirth.read(pid: birth.pid) == birth else { return .unavailable }
        return Self.automationState(status)
    }
}

/// For an explicit developer-candidate diagnostic. Values disclose no page
/// address, window title, text, native IDs or per-process session tokens.
public struct CandidateHostInspection: Encodable, Sendable {
    public let bundle: String?
    public let permission: String
    public let nativeTarget: String
    public let scriptRead: String
}

@MainActor public enum CandidateHostInspector {
    public static func inspectForeground() -> CandidateHostInspection {
        guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let host = CandidateBrowserHosts.host(for: bundle) else {
            return .init(bundle: nil, permission: "notChecked", nativeTarget: "unavailable", scriptRead: "notRun")
        }
        let access = host.permissionState()
        let permission: String
        switch access {
        case .granted: permission = "granted"
        case .permissionRequired: permission = "permissionRequired"
        case .unavailable: permission = "unavailable"
        }
        if let brave = host as? BraveBrowserHost, access == .granted,
           let click = try? brave.freezeClick() {
            let read: String
            do {
                switch try brave.readScriptSetting(for: click) {
                case .available: read = "readOnlyReply"
                case .automationRequired: read = "permissionRequired"
                case .browserSettingDisabled: read = "browserSettingDisabled"
                }
            } catch {
                read = "unverified"
            }
            return .init(bundle: bundle, permission: permission, nativeTarget: "absoluteNativeIDs", scriptRead: read)
        }
        if let ax = host as? AXBrowserHost, let objects = try? ax.observeFocusedWebArea() {
            var observation = BrowserAXObservation(original: objects)
            let compared = observation.compare(try? ax.observeFocusedWebArea())
            let target = compared == .sameExposedObjectsOnly ? "sameAXObjectsOnly" : "axTargetChanged"
            return .init(bundle: bundle, permission: permission, nativeTarget: target, scriptRead: "notRun")
        }
        return .init(bundle: bundle, permission: permission, nativeTarget: "unverified", scriptRead: "notRun")
    }
}
