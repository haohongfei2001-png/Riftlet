import Foundation
import RiftletCore

/// Adjustable development starting value, not a newly approved retention rule.
/// Archiving never removes bytes. Nil disables automatic archive.
struct LifecycleSettings: Codable, Equatable {
    var archiveAfterSeconds: TimeInterval? = 24 * 60 * 60

    func validate() throws {
        if let interval = archiveAfterSeconds, !interval.isFinite || interval <= 0 {
            throw RiftletError.invalidTransition
        }
    }
}
