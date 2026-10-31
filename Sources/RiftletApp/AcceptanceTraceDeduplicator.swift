/// Bounded, diagnostic-only last-value memory. It cannot affect product state,
/// target authority, refresh scheduling or the separate global trace budget.
/// Eviction permits a later repeat to be logged again; it never hides a change.
struct AcceptanceTraceDeduplicator<Key: Hashable, Value: Equatable> {
    private let capacity: Int
    private var values: [Key: Value] = [:]
    private var insertionOrder: [Key] = []
    var count: Int { values.count }

    init(capacity: Int = 128) { self.capacity = min(128, max(1, capacity)) }

    mutating func shouldRecord(_ value: Value, for key: Key) -> Bool {
        if values[key] == value { return false }
        if values[key] == nil {
            if insertionOrder.count == capacity {
                values.removeValue(forKey: insertionOrder.removeFirst())
            }
            insertionOrder.append(key)
        }
        values[key] = value
        return true
    }
}
