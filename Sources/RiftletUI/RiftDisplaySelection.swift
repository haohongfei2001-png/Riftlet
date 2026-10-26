import Foundation

/// The same deterministic display policy is used by the NSPanel controller and
/// disconnect/reconnect tests. It does not infer a capture's display from the cursor.
enum RiftDisplaySelection {
    static func choose(preferred: UInt32?, main: UInt32?, available: [UInt32]) -> UInt32? {
        if let preferred, available.contains(preferred) { return preferred }
        if let main, available.contains(main) { return main }
        return available.first
    }
}
