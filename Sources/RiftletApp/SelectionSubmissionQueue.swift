import Foundation

/// Original clicks enter synchronously on MainActor. Only one consumer submits
/// them to Core, so async permission checks cannot reorder original selections.
@MainActor
final class SelectionSubmissionQueue {
    private struct Entry {
        let id: UUID
        let selectionID: UUID?
        let ordinal: UInt64
        let deadline: TimeInterval?
        let run: @MainActor (UInt64) async -> Void
        let cancelled: @MainActor () -> Void
    }
    private var pending: [Entry] = []
    private var consumer: Task<Void, Never>?
    private var expiries: [UUID: Task<Void, Never>] = [:]
    private var nextOrdinal: UInt64 = 0
    private var active = false
    private let uptime: @MainActor () -> TimeInterval
    private let sleep: @MainActor (UInt64) async throws -> Void

    /// Internal timing seam for deterministic scheduling regressions. These
    /// dependencies never create or extend an accepted selection's authority.
    init(uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @MainActor (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.uptime = uptime; self.sleep = sleep
    }

    /// Presentation only: a later original selection will wait for this consumer.
    var hasOutstandingSubmission: Bool { active || !pending.isEmpty }

    @discardableResult
    func enqueue(selectionID: UUID?, deadline: TimeInterval?,
                 cancelled: @escaping @MainActor () -> Void,
                 run: @escaping @MainActor (UInt64) async -> Void) -> UInt64? {
        guard pending.count + (active ? 1 : 0) < 16 else { return nil }
        let entry = Entry(id: UUID(), selectionID: selectionID, ordinal: nextOrdinal,
                          deadline: deadline, run: run, cancelled: cancelled)
        nextOrdinal += 1
        pending.append(entry)
        if let deadline {
            let remaining = deadline - uptime()
            guard remaining.isFinite, remaining > 0, remaining <= 30 else {
                pending.removeLast(); return nil
            }
            expiries[entry.id] = Task { [weak self, uptime = self.uptime, sleep = self.sleep] in
                do {
                    try Task.checkCancellation()
                    // A delayed task must retain the original absolute deadline,
                    // not add its scheduling delay to the interval accepted above.
                    let remaining = deadline - uptime()
                    if remaining > 0 { try await sleep(UInt64(remaining * 1_000_000_000)) }
                    try Task.checkCancellation()
                } catch { return }
                self?.removePending { $0.id == entry.id }
            }
        }
        if consumer == nil { consumer = Task { [weak self] in await self?.drain() } }
        return entry.ordinal
    }

    func cancel(selectionIDs: Set<UUID>) {
        removePending { $0.selectionID.map(selectionIDs.contains) ?? false }
    }
    func stop() { removePending { _ in true }; consumer?.cancel() }

    private func removePending(where matches: (Entry) -> Bool) {
        let removed = pending.filter(matches)
        pending.removeAll(where: matches)
        for entry in removed {
            expiries.removeValue(forKey: entry.id)?.cancel()
            entry.cancelled()
        }
    }
    private func drain() async {
        while !pending.isEmpty && !Task.isCancelled {
            let entry = pending.removeFirst()
            expiries.removeValue(forKey: entry.id)?.cancel()
            // The timer may still be waiting to resume. Check the original
            // deadline at the actual submission boundary as well.
            if let deadline = entry.deadline, !(uptime() < deadline) {
                entry.cancelled()
                continue
            }
            active = true
            await entry.run(entry.ordinal)
            active = false
        }
        consumer = nil
    }
}
