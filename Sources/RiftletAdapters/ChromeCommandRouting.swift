import Foundation
import RiftletCore

/// Background addressing is granted only to a page-issued click capability or
/// original read-only/cleanup commands. Ordinary capture and legacy input keep
/// their previous foreground requirements. The page still validates every pin.
enum ChromeCommandRouting {
    static func requiresForeground(_ action: WebBridgeAction, target: TargetLease?) -> Bool {
        action == .captureTarget || action == .pinTarget
            || (action != .observe && action != .discard && target?.clickBindingID == nil)
    }
}
