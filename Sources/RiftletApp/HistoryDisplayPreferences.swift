import CryptoKit
import Foundation
import RiftletUI

/// One presentation preference shared by settings and history. It has no store,
/// asset, pagination or attachment dependency, and construction never writes.
@MainActor
final class HistoryDisplayPreferences {
    static let key = "historyDisplayStyle"

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private(set) var selection: HistoryDisplayStyle
    var onChange: ((HistoryDisplayStyle) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = Self.read(defaults)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Explicit choices are immediate. Refreshing a window never writes a key.
    func select(_ style: HistoryDisplayStyle) {
        if defaults.string(forKey: Self.key) != style.rawValue {
            defaults.set(style.rawValue, forKey: Self.key)
        }
        refresh()
    }

    func refresh() {
        let value = Self.read(defaults)
        guard value != selection else { return }
        selection = value
        onChange?(value)
    }

    private static func read(_ defaults: UserDefaults) -> HistoryDisplayStyle {
        defaults.string(forKey: key).flatMap(HistoryDisplayStyle.init(rawValue:)) ?? .current
    }

    /// Ordinary installed use has the requested standard key. Every existing
    /// synthetic/review mode gets a stable, separate domain so review restarts
    /// can test persistence without modifying the user's installed preference.
    static func make(mode: ApplicationMode, root: URL) -> HistoryDisplayPreferences {
        guard mode != .capture || OrdinaryCaptureConfiguration.isInternalAcceptance else {
            return HistoryDisplayPreferences(defaults: .standard)
        }
        // A valid, fixed suite name does not depend on a user-entered setting.
        return HistoryDisplayPreferences(defaults: UserDefaults(suiteName: reviewSuiteName(root: root))!)
    }

    static func reviewSuiteName(root: URL) -> String {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "com.riftlet.history-display.review." + digest
    }
}
