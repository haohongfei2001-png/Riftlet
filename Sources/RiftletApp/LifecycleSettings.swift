import Foundation
import RiftletCapture
import RiftletCore

/// Archiving only changes queue visibility. The old encoder stored "off" as {}.
struct LifecycleSettings: Codable, Equatable {
    static let defaultSeconds = QueueArchivePolicy.defaultMinutes * 60
    private static let validSeconds = (QueueArchivePolicy.minutesRange.lowerBound * 60)...(QueueArchivePolicy.minutesRange.upperBound * 60)
    var archiveAfterSeconds: TimeInterval? = defaultSeconds

    init() {}

    private enum CodingKeys: String, CodingKey { case archiveAfterSeconds }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard let saved = try fields.decodeIfPresent(Double.self, forKey: .archiveAfterSeconds) else {
            archiveAfterSeconds = nil
            return
        }
        guard saved.isFinite, saved > 0 else { throw RiftletError.invalidTransition }
        // Legacy hour-based presets outside the new range adopt the product default.
        // Decode in place: opening the App must not rewrite the user's file.
        archiveAfterSeconds = Self.validSeconds.contains(saved) ? saved : Self.defaultSeconds
    }

    func validate() throws {
        if let seconds = archiveAfterSeconds, !Self.validSeconds.contains(seconds) {
            throw RiftletError.invalidTransition
        }
    }
}
