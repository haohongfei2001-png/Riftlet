import AppKit
import Carbon
import Security

public enum EdgeAutomationPermissionState: String, Sendable, Equatable {
    case granted, notRequested, denied, receiverChanged, unavailable
}

/// Diagnostic code identities, not an upload or TCC capability. No path, page,
/// signing entitlement payload, cookie or account content is collected.
public struct EdgeAutomationCodeIdentity: Sendable, Equatable {
    public let signatureValid: Bool
    public let signingIdentifier: String?
    public let teamIdentifier: String?

    static func read(pid: pid_t) -> Self {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return .init(signatureValid: false, signingIdentifier: nil, teamIdentifier: nil) }
        let valid = SecCodeCheckValidity(code, [], nil) == errSecSuccess
        var information: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else {
            return .init(signatureValid: valid, signingIdentifier: nil, teamIdentifier: nil)
        }
        return .init(signatureValid: valid, signingIdentifier: values[kSecCodeInfoIdentifier as String] as? String,
                     teamIdentifier: values[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}

public struct EdgeAutomationPermissionResult: Sendable, Equatable {
    public let state: EdgeAutomationPermissionState
    public let osStatus: Int32?
    public let prompted: Bool
    public let sender: EdgeAutomationCodeIdentity
    public let receiver: EdgeAutomationCodeIdentity?
}

/// One ordinary App instance owns this controller. Background checks never ask;
/// only its explicit user-action method may present macOS's Automation consent.
/// Granting consent never replays a saved screenshot or selects a later draft.
@MainActor public final class EdgeAutomationPermissionController {
    private var requested = Set<String>()
    private let foreground: () -> EdgeProcessIdentity?
    private let recover: (String) -> EdgeProcessIdentity?
    private let current: (EdgeProcessIdentity) -> Bool
    private let determine: @Sendable (EdgeProcessIdentity, Bool) async -> Int32
    private let signing: @MainActor (pid_t) async -> EdgeAutomationCodeIdentity

    public convenience init() {
        self.init(foreground: EdgeProcessIdentity.currentForeground, current: { $0.isCurrent() }, determine: { process, ask in
            await Task.detached(priority: .userInitiated) {
                guard process.isCurrent() else { return Int32(procNotFound) }
                let target = NSAppleEventDescriptor(processIdentifier: process.pid)
                return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            }.value
        }, signing: { pid in
            // SecCode validity/signing reads can touch disk. Never perform
            // those synchronous Security calls on the App's main actor.
            await Task.detached(priority: .utility) { EdgeAutomationCodeIdentity.read(pid: pid) }.value
        }, recover: EdgeProcessIdentity.recover)
    }

    init(foreground: @escaping () -> EdgeProcessIdentity?, current: @escaping (EdgeProcessIdentity) -> Bool,
         determine: @escaping @Sendable (EdgeProcessIdentity, Bool) async -> Int32,
         signing: @escaping @MainActor (pid_t) async -> EdgeAutomationCodeIdentity,
         recover: @escaping (String) -> EdgeProcessIdentity? = { _ in nil }) {
        self.foreground = foreground; self.current = current; self.determine = determine; self.signing = signing
        self.recover = recover
    }

    public func checkCurrent(expectedSession: String? = nil) async -> EdgeAutomationPermissionResult {
        await inspect(expectedSession: expectedSession, request: false)
    }

    public func requestFromUserAction(expectedSession: String? = nil) async -> EdgeAutomationPermissionResult {
        await inspect(expectedSession: expectedSession, request: true)
    }

    /// Passive recovery of the exact stored receiver. A frontmost change does
    /// not hide an original operation, and a second Edge instance cannot lend
    /// either its lifetime identity or its permission to the stored operation.
    public func checkOriginal(session: String) async -> EdgeAutomationPermissionResult {
        // Freeze before any await. Signing completion cannot select a later
        // receiver or revive a process that was absent when this check began.
        let original = recover(session)
        let validAtEntry = original.map { $0.session == session && current($0) } == true
        let sender = await signing(getpid())
        guard validAtEntry, let original, current(original), recover(session) == original else {
            return .init(state: .receiverChanged, osStatus: nil, prompted: false, sender: sender, receiver: nil)
        }
        let receiver = await signing(original.pid)
        guard current(original), recover(session) == original else {
            return .init(state: .receiverChanged, osStatus: nil, prompted: false, sender: sender, receiver: receiver)
        }
        let status = await determine(original, false)
        let unchanged = current(original) && recover(session) == original
        return .init(state: unchanged ? Self.classify(status) : .receiverChanged, osStatus: status,
                     prompted: false, sender: sender, receiver: receiver)
    }

    private func inspect(expectedSession: String?, request: Bool) async -> EdgeAutomationPermissionResult {
        let original = foreground()
        let validAtEntry = original.map { (expectedSession == nil || $0.session == expectedSession) && current($0) } == true
        let sender = await signing(getpid())
        guard validAtEntry, let original, current(original), foreground() == original else {
            return .init(state: .receiverChanged, osStatus: nil, prompted: false, sender: sender, receiver: nil)
        }
        let receiver = await signing(original.pid)
        func result(_ status: Int32?, prompted: Bool, changed: Bool = false) -> EdgeAutomationPermissionResult {
            .init(state: changed ? .receiverChanged : Self.classify(status), osStatus: status,
                  prompted: prompted, sender: sender, receiver: receiver)
        }
        guard current(original), foreground() == original else { return result(nil, prompted: false, changed: true) }
        var status = await determine(original, false)
        guard current(original), foreground() == original else { return result(status, prompted: false, changed: true) }
        guard request, Self.classify(status) == .notRequested, requested.insert(original.session).inserted else {
            return result(status, prompted: false)
        }
        status = await determine(original, true)
        return result(status, prompted: true, changed: !current(original) || foreground() != original)
    }

    static func classify(_ status: Int32?) -> EdgeAutomationPermissionState {
        switch status {
        case noErr?: return .granted
        case Int32(errAEEventWouldRequireUserConsent)?: return .notRequested
        case Int32(errAEEventNotPermitted)?: return .denied
        case Int32(procNotFound)?: return .receiverChanged
        default: return .unavailable
        }
    }
}
