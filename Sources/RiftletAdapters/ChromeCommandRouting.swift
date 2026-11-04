import Foundation
import RiftletCore

/// Application focus may change at the thumbnail click. The destination must
/// still match the original process, window, tab and page before input.
enum ChromeCommandRouting {
    static func requiresSelectionCheck(_ action: WebBridgeAction) -> Bool {
        [.captureTarget, .validate, .commit].contains(action)
    }
}

/// Native address fixed before asynchronous page discovery. URL query and
/// fragment do not select another chat; origin and pathname do.
struct ChromeClickRoute: Equatable, Sendable {
    let window: String
    let tab: String
    let address: String

    init(window: String, tab: String, url: String) throws {
        guard let windowNumber = Int64(window), windowNumber > 0,
              let tabNumber = Int64(tab), tabNumber > 0,
              var components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty else {
            throw WebAdapterError.invalidTarget
        }
        components.scheme = scheme; components.host = host
        components.user = nil; components.password = nil
        components.query = nil; components.fragment = nil
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if components.path.isEmpty { components.path = "/" }
        guard let address = components.string else { throw WebAdapterError.invalidTarget }
        self.window = window; self.tab = tab; self.address = address
    }
}

/// Uses actual application activity. A visible Chrome window does not identify
/// the last used process: the user's chat may be minimized or on another Space.
enum ChromeReceiverSelection {
    static func choose(frontmost: Int32?, lastForeground: Int32?, running: Set<Int32>) -> Int32? {
        if let frontmost, running.contains(frontmost) { return frontmost }
        if let lastForeground { return running.contains(lastForeground) ? lastForeground : nil }
        return running.count == 1 ? running.first : nil
    }
}
