import Foundation
import RiftletCapture
import RiftletUI

/// One preference controls the next session's fixed mode order. Capturing and
/// switching the active mode never write this setting.
struct ScreenshotEntryPreferences: Codable, Equatable {
    var version: Int = 1
    var defaultMode: ScreenshotMode = .window

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

    /// Adopt the approved reference's spacing only for the old untouched design
    /// defaults. A user's adjusted placement/size is never overwritten.
    static func initialLayout(_ existing: RiftConfiguration) -> RiftConfiguration {
        guard existing.fitWidth == 72, existing.fitHeight == 56,
              existing.rowPitch == 60, existing.outerInset == 8,
              existing.firstCenterFromTop == 180 else { return existing }
        var result = existing
        result.fitHeight = 48
        result.rowPitch = 62
        result.outerInset = 14
        result.firstCenterFromTop = 332
        return result
    }

    static func placement(in frame: CGRect, configuration c: RiftConfiguration) -> (anchor: CGPoint, queueHeader: CGPoint?) {
        let rowHeight = max(c.fitHeight, c.minimumHitHeight)
        let intendedY = frame.maxY - c.firstCenterFromTop + rowHeight / 2 + 62
        let minimumY = frame.minY + 62 + c.screenPadding + rowHeight + 1
        let maximumY = frame.maxY - 122
        let defaultX = max(frame.minX + 26, min(frame.maxX - 26, frame.maxX - c.outerInset - 18))
        if minimumY <= maximumY {
            let anchor = CGPoint(x: defaultX, y: max(minimumY, min(maximumY, intendedY)))
            return (anchor, anchor)
        }
        // A very short display cannot fit the expanded rail above a full row.
        // Keep the existing queue's full vertical space and move the capture
        // control left of its maximum row width instead of making all rows vanish.
        let queueWidth = max(c.minimumHitWidth, c.fitWidth + c.numberGap + c.numberFontSize * 13 + c.leftPadding)
        let x = max(frame.minX + 26, min(defaultX, frame.maxX - c.outerInset - queueWidth - 28))
        let y = max(frame.minY + 26, min(maximumY, intendedY))
        return (CGPoint(x: x, y: y), nil)
    }
}
