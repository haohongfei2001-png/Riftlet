import AppKit
import Carbon

enum AutomationPermissionState: Equatable, Sendable {
    case notNeeded, notRequested, granted, denied, browserNotRunning, browserNotInstalled, unavailable
}

protocol AutomationPermissionChecking: Sendable {
    func check(askUserIfNeeded: Bool) async -> AutomationPermissionState
    func check(askUserIfNeeded: Bool, expectedSession: String?) async -> AutomationPermissionState
}

extension AutomationPermissionChecking {
    func check(askUserIfNeeded: Bool, expectedSession: String?) async -> AutomationPermissionState {
        await check(askUserIfNeeded: askUserIfNeeded)
    }
}

struct PermissionBrowserIdentity: Equatable, Sendable {
    let pid: pid_t
    let launched: Date
    var session: String { "\(pid):\(launched.timeIntervalSince1970)" }

    static func select(_ candidates: [Self], foregroundPID: pid_t?, expectedSession: String?) -> Self? {
        if let expectedSession {
            let matches = candidates.filter { $0.session == expectedSession }
            return matches.count == 1 ? matches[0] : nil
        }
        if let foregroundPID, let foreground = candidates.first(where: { $0.pid == foregroundPID }) { return foreground }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

/// A status check sends no page program and never launches/activates Chrome.
/// Apple Events authorization is unrelated to admission of an upload profile.
struct NativeAutomationPermissionChecker: AutomationPermissionChecking {
    private static let queue = DispatchQueue(label: "Riftlet.permission", qos: .userInitiated)

    func check(askUserIfNeeded: Bool) async -> AutomationPermissionState {
        await check(askUserIfNeeded: askUserIfNeeded, expectedSession: nil)
    }

    func check(askUserIfNeeded: Bool, expectedSession: String?) async -> AutomationPermissionState {
        let availability: (AutomationPermissionState?, PermissionBrowserIdentity?) = await MainActor.run {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil else {
                return (.browserNotInstalled, nil)
            }
            let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
                .compactMap { app -> PermissionBrowserIdentity? in
                    guard !app.isTerminated, let launch = app.launchDate else { return nil }
                    return .init(pid: app.processIdentifier, launched: launch)
                }
            guard !candidates.isEmpty else { return (.browserNotRunning, nil) }
            let chosen = PermissionBrowserIdentity.select(candidates,
                foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, expectedSession: expectedSession)
            return (chosen == nil ? .unavailable : nil, chosen)
        }
        if let status = availability.0 { return status }
        guard let identity = availability.1 else { return .unavailable }
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                func stillSameProcess() -> Bool {
                    guard let running = NSRunningApplication(processIdentifier: identity.pid) else { return false }
                    return !running.isTerminated && running.bundleIdentifier == "com.google.Chrome"
                        && running.launchDate == identity.launched
                }
                guard stillSameProcess() else { continuation.resume(returning: .browserNotRunning); return }
                let address = NSAppleEventDescriptor(processIdentifier: identity.pid)
                let code = AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, askUserIfNeeded)
                continuation.resume(returning: stillSameProcess() ? Self.classify(code) : .browserNotRunning)
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

    func inspect(expectedSession: String? = nil) async -> AutomationPermissionState {
        guard requiresChrome else { return .notNeeded }
        return await checker.check(askUserIfNeeded: false, expectedSession: expectedSession)
    }

    /// Called only by an explicit setup button. Denial goes to System Settings;
    /// repeatedly issuing requests cannot override a previous user decision.
    func requestFromUserAction(expectedSession: String? = nil) async -> AutomationPermissionState {
        guard requiresChrome else { return .notNeeded }
        let current = await checker.check(askUserIfNeeded: false, expectedSession: expectedSession)
        guard current == .notRequested else { return current }
        return await checker.check(askUserIfNeeded: true, expectedSession: expectedSession)
    }
}
