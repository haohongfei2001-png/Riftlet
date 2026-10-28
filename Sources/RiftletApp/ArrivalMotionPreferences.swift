import Foundation
import RiftletUI

/// Kept separate from queue/lifecycle preferences, with one file per existing
/// App data root. Loading an older installation never writes a new default.
struct ArrivalMotionPreferences: Equatable, Sendable {
    private struct Document: Codable {
        let version: Int
        let mode: ArrivalMotionMode
    }

    enum LoadState: Equatable, Sendable { case unselected, selected, unreadable }
    let url: URL
    private(set) var selectedMode: ArrivalMotionMode?
    private(set) var loadState: LoadState
    var mode: ArrivalMotionMode { selectedMode ?? .provisionalFallback }

    init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else {
            selectedMode = nil; loadState = .unselected; return
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 4_096 else { throw CocoaError(.fileReadCorruptFile) }
            let value = try JSONDecoder().decode(Document.self, from: data)
            guard value.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            selectedMode = value.mode; loadState = .selected
        } catch {
            // Preserve unreadable/future-version bytes. An explicit successful
            // choice may replace them; silently falling back must not do so.
            selectedMode = nil; loadState = .unreadable
        }
    }

    mutating func select(_ mode: ArrivalMotionMode) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(version: 1, mode: mode))
        try data.write(to: url, options: .atomic)
        selectedMode = mode; loadState = .selected
    }
}
