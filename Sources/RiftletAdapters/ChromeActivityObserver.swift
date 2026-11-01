import AppKit
import ApplicationServices

/// AX messages are scheduling hints, not attachment authority. A window
/// selection change invalidates the old window ACK. Title/focus changes are
/// ambiguous (a chat can rename itself without changing tabs), so they trigger
/// a fresh observation without granting or revoking attachment authority.
public enum ChromeActivityHintPolicy {
    public static func invalidatesTarget(_ reason: String) -> Bool {
        reason == "chromeWindow"
    }

    public static func coalesce(previous: String?, incoming: String) -> String {
        guard let previous else { return incoming }
        // A subsequent editor focus notification must not erase an earlier
        // target-change hint before the actor can revoke stale authority.
        return invalidatesTarget(previous) && !invalidatesTarget(incoming) ? previous : incoming
    }
}

/// Scheduling hints only. AX events never supply target identity or authorize
/// input. No title, textbox value, chat content or accessibility tree is read.
@MainActor
public final class ChromeActivityObserver {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var focusedWindow: AXUIElement?
    private var pid: pid_t?
    private var processIdentity: ChromeProcessIdentity?
    private var generation = UUID()
    private var scheduledRefresh: Task<Void, Never>?
    private var needsWindowRefresh = false
    private var pendingReason: String?
    private let onChange: (String) -> Void

    public init(onChange: @escaping (String) -> Void) { self.onChange = onChange }
    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }

    /// Uses existing OS authorization; never opens a permission prompt itself.
    @discardableResult
    public func bind(to app: NSRunningApplication?) -> Bool {
        guard let app, app.bundleIdentifier == "com.google.Chrome",
              let identity = ChromeProcessIdentity.read(pid: app.processIdentifier), AXIsProcessTrusted() else {
            stop(); return false
        }
        // A new Chrome process can reuse a PID; its predecessor's observer is
        // not an event source for the new launch session.
        if pid == app.processIdentifier, processIdentity == identity, observer != nil { return true }
        stop()
        var next: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, { source, _, name, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromeActivityObserver>.fromOpaque(context).takeUnretainedValue()
                owner.received(source, name: name as String)
            }
        }, &next)
        guard result == .success, let next else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementSetMessagingTimeout(element, 0.05) == .success else { return false }
        observer = next; application = element; pid = app.processIdentifier; processIdentity = identity
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var registrations = 0
        for name in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXWindowCreatedNotification] {
            if AXObserverAddNotification(next, element, name as CFString, pointer) == .success { registrations += 1 }
        }
        guard registrations > 0, identity.isCurrent() else { stop(); return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
        observeFocusedWindow()
        return true
    }

    public func stop() {
        generation = UUID(); scheduledRefresh?.cancel(); scheduledRefresh = nil
        needsWindowRefresh = false
        pendingReason = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let application {
                for name in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXWindowCreatedNotification] {
                    AXObserverRemoveNotification(observer, application, name as CFString)
                }
            }
            if let focusedWindow { AXObserverRemoveNotification(observer, focusedWindow, kAXTitleChangedNotification as CFString) }
        }
        observer = nil; application = nil; focusedWindow = nil; pid = nil; processIdentity = nil
    }

    private func observeFocusedWindow() {
        guard let observer, let application else { return }
        if let focusedWindow { AXObserverRemoveNotification(observer, focusedWindow, kAXTitleChangedNotification as CFString) }
        focusedWindow = nil
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return }
        let window = raw as! AXUIElement
        guard AXUIElementSetMessagingTimeout(window, 0.05) == .success else { return }
        focusedWindow = window
        AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }

    private func received(_ source: AXObserver, name: String) {
        guard let observer, CFEqual(observer, source) else { return }
        guard processIdentity?.isCurrent() == true else { stop(); return }
        let reason: String
        switch name {
        case kAXFocusedWindowChangedNotification: reason = "chromeWindow"
        case kAXFocusedUIElementChangedNotification: reason = "chromeFocus"
        case kAXWindowCreatedNotification: reason = "chromeWindowCreated"
        case kAXTitleChangedNotification: reason = "chromeTitle"
        default: return
        }
        // Preserve target-changing notifications even when a later ordinary
        // focus event arrives in the same coalesced AX burst.
        pendingReason = ChromeActivityHintPolicy.coalesce(previous: pendingReason, incoming: reason)
        needsWindowRefresh = needsWindowRefresh || name == kAXFocusedWindowChangedNotification || name == kAXWindowCreatedNotification
        guard scheduledRefresh == nil else { return }
        let token = generation
        scheduledRefresh = Task { @MainActor [weak self] in
            // Leave the AX callback stack before making remote AX requests.
            await Task.yield()
            guard let self, !Task.isCancelled, self.generation == token, self.observer != nil else { return }
            self.scheduledRefresh = nil
            guard self.processIdentity?.isCurrent() == true else { self.stop(); return }
            guard let reason = self.pendingReason else { return }
            let refreshWindow = self.needsWindowRefresh
            self.pendingReason = nil
            self.needsWindowRefresh = false
            // The target-change hint must revoke the old ACK before an AX
            // focused-window read, which may block for its full timeout.
            self.onChange(reason)
            // Invalidation/cancellation may have replaced this observer.
            guard self.generation == token, self.observer != nil else { return }
            if refreshWindow { self.observeFocusedWindow() }
        }
    }
}
