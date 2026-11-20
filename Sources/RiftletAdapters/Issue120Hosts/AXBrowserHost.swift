import AppKit
import ApplicationServices
import RiftletCore

/// Capture the original AX objects without persisting process-local handles,
/// fetching editor contents, walking unrelated tabs or opening any picker.
struct BrowserAXObjects: Equatable {
    let receiverSession: String
    let window: MacAXElement
    let webArea: MacAXElement
    let focusedElement: MacAXElement
}

/// A missing object or a change retires the sample for good. Matching objects
/// alone cannot exclude an unobserved same-document navigation or ABA.
struct BrowserAXObservation {
    enum Result { case sameExposedObjectsOnly, retired }
    private var original: BrowserAXObjects?

    init(original: BrowserAXObjects) { self.original = original }

    mutating func compare(_ current: BrowserAXObjects?) -> Result {
        guard let original, let current, original == current else {
            original = nil
            return .retired
        }
        return .sameExposedObjectsOnly
    }
}

@MainActor final class AXBrowserHost: BrowserHost {
    enum Browser: String { case safari = "com.apple.Safari", firefox = "org.mozilla.firefox" }
    private let browser: Browser
    var bundle: String { browser.rawValue }
    let capabilities = HostCapabilities(world: .unknown, reply: .unknown, locator: .unknown,
                                        epoch: .unknown, fileSetterAndDataTransferVerified: false, maximumPinBytes: 0)

    init(browser: Browser) { self.browser = browser }

    func permissionState() -> OriginalReceiverAccess {
        guard let receiver = CandidateReceiver.forSettings(bundle) else { return .unavailable }
        switch browser {
        case .firefox: return AXIsProcessTrusted() ? .granted : .permissionRequired
        case .safari: return receiver.automationState()
        }
    }

    /// This bounded, explicit capability diagnostic is never run on mouse-down.
    /// A trusted sender can compare original window, web area and focus handles
    /// before and after one controlled navigation or tab replacement.
    func observeFocusedWebArea() throws -> BrowserAXObjects {
        let driver = try NativeMacAXDriver(messagingTimeout: 0.05)
        guard driver.isTrusted(), let receiver = CandidateReceiver.foreground(bundle) else {
            throw BindingError.unsupported
        }
        let pid = receiver.birth.pid
        let app = try driver.applicationElement(processID: pid)
        guard let window = try driver.elementAttribute(kAXFocusedWindowAttribute, of: app),
              let focus = try driver.elementAttribute(kAXFocusedUIElementAttribute, of: app),
              try driver.processID(of: window) == pid, try driver.processID(of: focus) == pid else {
            throw BindingError.targetChanged
        }
        var cursor = focus
        var area: MacAXElement?
        for _ in 0..<24 {
            if cursor == window {
                guard let area, CandidateReceiver.foreground(bundle) == receiver,
                      try driver.elementAttribute(kAXFocusedWindowAttribute, of: app) == window,
                      try driver.elementAttribute(kAXFocusedUIElementAttribute, of: app) == focus
                else { throw BindingError.targetChanged }
                return BrowserAXObjects(receiverSession: receiver.session, window: window, webArea: area, focusedElement: focus)
            }
            if try driver.stringAttribute(kAXRoleAttribute, of: cursor) == "AXWebArea", area == nil {
                area = cursor
            }
            guard let parent = try driver.elementAttribute(kAXParentAttribute, of: cursor),
                  parent != cursor, try driver.processID(of: parent) == pid else { break }
            cursor = parent
        }
        throw BindingError.unsupported
    }

    func freezeClick() throws -> NativeClick {
        // A Safari tab index is mutable. Neither this AX observation nor a
        // Firefox chooser proves the original document/composer on a cold click.
        throw BindingError.unsupported
    }

    func enqueuePin(click: NativeClick, route: ProviderRoute, maximumBytes: Int) throws -> Task<PinReceipt, Error> {
        throw BindingError.unsupported
    }
}
