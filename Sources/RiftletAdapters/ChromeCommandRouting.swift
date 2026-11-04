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

/// Uses actual desktop activity, never a scan for a matching chat in arbitrary
/// tabs. Window owners are in native front-to-back order.
enum ChromeReceiverSelection {
    static func choose(frontmost: Int32?, lastForeground: Int32?,
                       visibleWindowOwners: [Int32], running: Set<Int32>) -> Int32? {
        if let frontmost, running.contains(frontmost) { return frontmost }
        if let lastForeground, running.contains(lastForeground) { return lastForeground }
        if let visible = visibleWindowOwners.first(where: { running.contains($0) }) { return visible }
        return running.count == 1 ? running.first : nil
    }
}
