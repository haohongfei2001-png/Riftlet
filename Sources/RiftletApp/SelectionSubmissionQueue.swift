import Foundation

/// Original clicks enter synchronously on MainActor. Only one consumer submits
/// them to Core, so async permission checks cannot reorder original selections.
@MainActor
final class SelectionSubmissionQueue {
    private struct Entry {
        let id: UUID
        let selectionID: UUID?
        let ordinal: UInt64
        let run: @MainActor (UInt64) async -> Void
        let cancelled: @MainActor () -> Void
    }
    private var pending: [Entry] = []
    private var consumer: Task<Void, Never>?
    private var expiries: [UUID: Task<Void, Never>] = [:]
    private var nextOrdinal: UInt64 = 0
    private var active = false

    @discardableResult
    func enqueue(selectionID: UUID?, deadline: TimeInterval?,
                 cancelled: @escaping @MainActor () -> Void,
                 run: @escaping @MainActor (UInt64) async -> Void) -> UInt64? {
        guard pending.count + (active ? 1 : 0) < 16 else { return nil }
        let entry = Entry(id: UUID(), selectionID: selectionID, ordinal: nextOrdinal, run: run, cancelled: cancelled)
        nextOrdinal += 1
        pending.append(entry)
        if let deadline {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining.isFinite, remaining > 0, remaining <= 30 else {
                pending.removeLast(); return nil
            }
            expiries[entry.id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
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
            active = true
            await entry.run(entry.ordinal)
            active = false
        }
        consumer = nil
    }
}
