import AppKit
import ApplicationServices

/// Scheduling hints only. AX events never supply target identity or authorize
/// input. No title, textbox value, chat content or accessibility tree is read.
@MainActor
public final class ChromeActivityObserver {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var focusedWindow: AXUIElement?
    private var pid: pid_t?
    private var generation = UUID()
    private var scheduledRefresh: Task<Void, Never>?
    private var needsWindowRefresh = false
    private var pendingReason = "chromeFocus"
    private let onChange: (String) -> Void

    public init(onChange: @escaping (String) -> Void) { self.onChange = onChange }
    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }

    /// Uses existing OS authorization; never opens a permission prompt itself.
    @discardableResult
    public func bind(to app: NSRunningApplication?) -> Bool {
        guard let app, app.bundleIdentifier == "com.google.Chrome", AXIsProcessTrusted() else {
            stop(); return false
        }
        if pid == app.processIdentifier, observer != nil { return true }
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
        AXUIElementSetMessagingTimeout(element, 0.05)
        observer = next; application = element; pid = app.processIdentifier
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var registrations = 0
        for name in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXWindowCreatedNotification] {
            if AXObserverAddNotification(next, element, name as CFString, pointer) == .success { registrations += 1 }
        }
        guard registrations > 0 else { stop(); return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
        observeFocusedWindow()
        return true
    }

    public func stop() {
        generation = UUID(); scheduledRefresh?.cancel(); scheduledRefresh = nil
        needsWindowRefresh = false
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let application {
                for name in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXWindowCreatedNotification] {
                    AXObserverRemoveNotification(observer, application, name as CFString)
                }
            }
            if let focusedWindow { AXObserverRemoveNotification(observer, focusedWindow, kAXTitleChangedNotification as CFString) }
        }
        observer = nil; application = nil; focusedWindow = nil; pid = nil
    }

    private func observeFocusedWindow() {
        guard let observer, let application else { return }
        if let focusedWindow { AXObserverRemoveNotification(observer, focusedWindow, kAXTitleChangedNotification as CFString) }
        focusedWindow = nil
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return }
        let window = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.05)
        focusedWindow = window
        AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }

    private func received(_ source: AXObserver, name: String) {
        guard let observer, CFEqual(observer, source) else { return }
        let reason: String
        switch name {
        case kAXFocusedWindowChangedNotification: reason = "chromeWindow"
        case kAXFocusedUIElementChangedNotification: reason = "chromeFocus"
        case kAXWindowCreatedNotification: reason = "chromeWindowCreated"
        case kAXTitleChangedNotification: reason = "chromeTitle"
        default: return
        }
        pendingReason = reason
        needsWindowRefresh = needsWindowRefresh || name == kAXFocusedWindowChangedNotification || name == kAXWindowCreatedNotification
        guard scheduledRefresh == nil else { return }
        let token = generation
        scheduledRefresh = Task { @MainActor [weak self] in
            // Leave the AX callback stack before making remote AX requests.
            await Task.yield()
            guard let self, !Task.isCancelled, self.generation == token, self.observer != nil else { return }
            self.scheduledRefresh = nil
            if self.needsWindowRefresh { self.needsWindowRefresh = false; self.observeFocusedWindow() }
            self.onChange(self.pendingReason)
        }
    }
}
