import Foundation
import RiftletCore

/// Application focus may change at the thumbnail click. The destination must
/// still match the original process, window, tab and page before input.
enum ChromeCommandRouting {
    static func requiresSelectionCheck(_ action: WebBridgeAction) -> Bool {
        [.captureTarget, .renewPreparedTarget, .validate, .commit].contains(action)
    }
}

/// Optional narrowing of the ordinary transport for an isolated QA account on a
/// shared desktop. In this configuration even preparation may address only the
/// explicitly attested native window and tab of the original browser process.
public struct QAOriginalBrowserTab: Decodable, Sendable {
    public let applicationID: String
    public let session: String
    public let windowID: String
    public let tabID: String

    static let temporaryChat = "https://chatgpt.com/?temporary-chat=true"

    func allows(_ target: TargetLease) -> Bool {
        applicationID == target.applicationID && session == target.sessionID &&
            windowID == target.windowID && tabID == target.tabID
    }

    public static func decode(_ value: String?) throws -> Self {
        guard let value, value.utf8.count <= 1024 else { throw WebAdapterError.invalidTarget }
        let result = try JSONDecoder().decode(Self.self, from: Data(value.utf8))
        let parts = result.session.split(separator: ":", omittingEmptySubsequences: false)
        let browser = AttachmentBrowser(rawValue: result.applicationID)
        guard let browser, parts.count == 4,
              parts[0] == (browser == .chrome ? "chrome-kernel-v1" : "edge-kernel-v1"),
              let pid = Int32(parts[1]), pid > 0, let seconds = UInt64(parts[2]), seconds > 0,
              let micros = UInt32(parts[3]), micros < 1_000_000,
              let window = Int32(result.windowID), window > 0, String(window) == result.windowID,
              let tab = Int32(result.tabID), tab > 0, String(tab) == result.tabID
        else { throw WebAdapterError.invalidTarget }
        return result
    }
}

/// Native address fixed before asynchronous page discovery. URL query and
/// fragment do not select another chat; origin and pathname do.
struct ChromeClickRoute: Equatable, Sendable {
    let window: String
    let tab: String
    let address: String

    /// Validate the raw browser URL before the click identity drops credentials
    /// and normalizes the default HTTPS port.
    static func chatGPT(window: String, tab: String, url: String) throws -> Self {
        guard let parts = URLComponents(string: url), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              ["chatgpt.com", "chat.openai.com"].contains(parts.host?.lowercased()) else {
            throw WebAdapterError.pageRejected(.pageRouteUnsupported)
        }
        return try Self(window: window, tab: tab, url: url)
    }

    var historyConversationID: UUID? {
        guard let parts = URLComponents(string: address), parts.scheme == "https", parts.host == "chatgpt.com",
              parts.port == nil else { return nil }
        let segments = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        var path = Array(segments.dropFirst())
        if path.last == "" { path.removeLast() }
        if path.count == 4, path[0] == "g",
           !path[1].isEmpty, path[1].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) {
            path.removeFirst(2)
        }
        guard path.count == 2, path[0] == "c" else { return nil }
        let id = String(path[1])
        return id.count == 36 ? UUID(uuidString: id) : nil
    }

    func matchesOriginal(route: Self?, savedConversation: UUID?) -> Bool {
        (route == nil || route == self) && (savedConversation == nil || savedConversation == historyConversationID)
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

    mutating func remove(for key: String) { entries.removeValue(forKey: key) }

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

/// Cancel work before entering its one native submission. Once entered, the
/// caller still reads the original reply even if the task has been cancelled.
final class NativeCommandSubmission: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var entered = false

    func perform<T: Sendable>(_ body: @escaping @Sendable (CheckedContinuation<T, Error>) -> Void) async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(body)
        } onCancel: { self.cancel() }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }

    func enter() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !entered else { throw WebAdapterError.invalidRequest }
        guard !cancelled else { throw CancellationError() }
        entered = true
    }
}
