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

    var historyConversationID: UUID? {
        guard let parts = URLComponents(string: address), parts.scheme == "https", parts.host == "chatgpt.com",
              parts.port == nil, parts.percentEncodedPath.hasPrefix("/c/") else { return nil }
        var id = String(parts.percentEncodedPath.dropFirst(3))
        if id.hasSuffix("/") { id.removeLast() }
        return id.count == 36 ? UUID(uuidString: id) : nil
    }

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

/// Idle routes and installed relay descriptions may be rediscovered only by a
/// normal capture or an exact read-only observation. Nonce/operation replay
/// fences live elsewhere and are never evicted by this cache.
struct ChromeSessionCache<Value> {
    private var entries: [String: (value: Value, touched: TimeInterval)] = [:]
    private var lastSweep: TimeInterval = -.infinity
    private let idleInterval: TimeInterval = 600

    mutating func store(_ value: Value, for key: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        sweep(now)
        entries[key] = (value, now)
    }

    mutating func value(for key: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Value? {
        sweep(now)
        guard let entry = entries[key], now - entry.touched < idleInterval else { return nil }
        entries[key]?.touched = now
        return entry.value
    }

    private mutating func sweep(_ now: TimeInterval) {
        guard now - lastSweep >= 60 else { return }
        entries = entries.filter { now - $0.value.touched < idleInterval }
        lastSweep = now
    }
}
