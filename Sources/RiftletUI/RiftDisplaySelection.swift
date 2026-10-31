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

/// Session-local fallback never rewrites persistent user intent. Reconnection
/// becomes an offer, rather than moving native input windows under a pointer.
struct RiftDisplaySessionSelection {
    struct Display: Equatable { let id: UInt32; let uuid: String? }
    private var preferenceKey: String?
    private var fallbackID: UInt32?
    private(set) var restoreAvailable = false

    mutating func resolve(preferred: UInt32?, uuid: String?, main: UInt32?, available: [Display], restore: Bool = false) -> UInt32? {
        let key = uuid.map { "uuid:" + $0 } ?? preferred.map { "id:\($0)" } ?? "initial"
        if key != preferenceKey { preferenceKey = key; fallbackID = nil; restoreAvailable = false }
        let matches = uuid.map { value in available.filter { $0.uuid == value } } ?? available.filter { $0.id == preferred }
        // Ambiguous UUIDs are not disambiguated by a transient ID.
        let intended = matches.count == 1 ? matches.first?.id : nil
        let ids = available.map(\.id)
        if let fallbackID, ids.contains(fallbackID), !restore {
            restoreAvailable = intended != nil && intended != fallbackID
            return fallbackID
        }
        if let intended { fallbackID = nil; restoreAvailable = false; return intended }
        let fallback = RiftDisplaySelection.choose(preferred: nil, main: main, available: ids)
        fallbackID = fallback; restoreAvailable = false
        return fallback
    }

    mutating func userSelectedDisplay() { preferenceKey = nil; fallbackID = nil; restoreAvailable = false }
}
