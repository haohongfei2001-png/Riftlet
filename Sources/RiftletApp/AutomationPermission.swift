import AppKit
import Carbon

enum AutomationPermissionState: Equatable, Sendable {
    case notNeeded, notRequested, granted, denied, browserNotRunning, browserNotInstalled, unavailable
}

protocol AutomationPermissionChecking: Sendable {
    func check(askUserIfNeeded: Bool) async -> AutomationPermissionState
}

/// A status check sends no page program and never launches/activates Chrome.
/// Apple Events authorization is unrelated to admission of an upload profile.
struct NativeAutomationPermissionChecker: AutomationPermissionChecking {
    private static let queue = DispatchQueue(label: "Riftlet.permission", qos: .userInitiated)

    func check(askUserIfNeeded: Bool) async -> AutomationPermissionState {
        let availability: (AutomationPermissionState?, pid_t?, Date?) = await MainActor.run {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil else {
                return (.browserNotInstalled, nil, nil)
            }
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
                .first(where: { !$0.isTerminated }) else { return (.browserNotRunning, nil, nil) }
            return (nil, running.processIdentifier, running.launchDate)
        }
        if let status = availability.0 { return status }
        guard let pid = availability.1, let launched = availability.2 else { return .unavailable }
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated,
                      running.bundleIdentifier == "com.google.Chrome", running.launchDate == launched else {
                    continuation.resume(returning: .browserNotRunning); return
                }
                // A PID address cannot launch an app if it exited between the
                // availability check and this queue turn. It grants no target lease.
                let address = NSAppleEventDescriptor(processIdentifier: pid)
                let code = AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, askUserIfNeeded)
                continuation.resume(returning: Self.classify(code))
            }
        }
    }

    static func classify(_ status: OSStatus) -> AutomationPermissionState {
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .notRequested
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .browserNotRunning
        default: return .unavailable
        }
    }
}

/// No normal collection/simulation code path can request Automation. Tests use
/// a fake driver; CI never prompts, inspects Chrome, or resets the user's TCC.
struct AutomationPermissionGate: Sendable {
    let requiresChrome: Bool
    let checker: any AutomationPermissionChecking

    init(requiresChrome: Bool, checker: any AutomationPermissionChecking = NativeAutomationPermissionChecker()) {
        self.requiresChrome = requiresChrome; self.checker = checker
    }

    func inspect() async -> AutomationPermissionState {
        guard requiresChrome else { return .notNeeded }
        return await checker.check(askUserIfNeeded: false)
    }

    /// Called only by an explicit setup button. Denial goes to System Settings;
    /// repeatedly issuing requests cannot override a previous user decision.
    func requestFromUserAction() async -> AutomationPermissionState {
        guard requiresChrome else { return .notNeeded }
        let current = await checker.check(askUserIfNeeded: false)
        guard current == .notRequested else { return current }
        return await checker.check(askUserIfNeeded: true)
    }
}
