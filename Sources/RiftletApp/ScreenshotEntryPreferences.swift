import Foundation
import RiftletCapture
import RiftletUI

/// Capture availability and the next session's fixed mode order are independent
/// of collection pause and rift visibility. Capturing and mode switches never
/// write preferences or macOS screenshot settings.
struct ScreenshotEntryPreferences: Codable, Equatable {
    var version: Int = 1
    var defaultMode: ScreenshotMode = .window
    var builtInScreenshotEnabled: Bool = true

    private enum CodingKeys: String, CodingKey {
        case version, defaultMode, builtInScreenshotEnabled
    }

    init(version: Int = 1, defaultMode: ScreenshotMode = .window,
         builtInScreenshotEnabled: Bool = true) {
        self.version = version
        self.defaultMode = defaultMode
        self.builtInScreenshotEnabled = builtInScreenshotEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        defaultMode = try values.decode(ScreenshotMode.self, forKey: .defaultMode)
        // Version 1 predates the off switch. Its existing users already had the
        // built-in entry enabled; preserving that behavior must not reset their
        // chosen default mode. An explicit false survives every future load.
        builtInScreenshotEnabled = try values.decodeIfPresent(Bool.self, forKey: .builtInScreenshotEnabled) ?? true
    }

    static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.version == 1 else { throw RiftConfigurationError.invalidGeometry }
        return value
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Adopt the visual candidate's spacing only for the old untouched design
    /// defaults. A user's adjusted placement/size is never overwritten.
    static func initialLayout(_ existing: RiftConfiguration) -> RiftConfiguration {
        guard existing.fitWidth == 72, existing.fitHeight == 56,
              existing.rowPitch == 60, existing.outerInset == 8,
              existing.firstCenterFromTop == 180 else { return existing }
        var result = existing
        result.fitHeight = 56
        result.rowPitch = 60
        result.outerInset = 14
        result.firstCenterFromTop = 202
        return result
    }

    static func placement(in frame: CGRect, configuration c: RiftConfiguration) -> (anchor: CGPoint, queueHeader: CGPoint?) {
        let anchor = CGPoint(x: frame.maxX - c.outerInset - 18,
                             y: frame.maxY - c.firstCenterFromTop + 66)
        // No leftward rescue or queue shift. The host hides an entry that cannot
        // fit its fixed 36 x 132 expanded rail on a very short visible screen.
        let fits = anchor.x - 18 >= frame.minX + 12 && anchor.y + 114 <= frame.maxY - 12
            && anchor.y - 18 >= frame.minY + 12
        return (anchor, fits ? anchor : nil)
    }
}
