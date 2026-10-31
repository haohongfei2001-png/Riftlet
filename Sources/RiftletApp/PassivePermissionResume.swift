import Foundation

/// Event-driven permission recovery only. This never requests authorization,
/// captures a target, retains a click, or supplies an attachment receipt.
@MainActor
final class PassivePermissionResume {
    private let inspect: @MainActor () async -> AutomationPermissionState
    private let onResult: @MainActor (AutomationPermissionState) -> Void
    private let resume: @MainActor () async -> Void
    private var generation = UUID()
    private var inFlight: UUID?
    private var pending = false
    private var task: Task<Void, Never>?
    private(set) var isRunning = false
    var isBusy: Bool { inFlight != nil }

    init(inspect: @escaping @MainActor () async -> AutomationPermissionState,
         onResult: @escaping @MainActor (AutomationPermissionState) -> Void = { _ in },
         resume: @escaping @MainActor () async -> Void) {
        self.inspect = inspect; self.onResult = onResult; self.resume = resume
    }

    /// Merely enables host events; no timer or unsolicited permission call.
    func start() {
        guard !isRunning else { return }
        generation = UUID(); isRunning = true
    }

    /// Coalesce event bursts into one active check and at most one follow-up.
    /// Every executed check is fresh; a prior grant is never reused as authority.
    func request() {
        guard isRunning else { return }
        pending = true
        beginIfNeeded()
    }

    func stop() {
        isRunning = false; pending = false; generation = UUID()
        task?.cancel()
        // An OS call may ignore cancellation. Keep its slot until it drains so
        // a restart cannot run another inspection/resume concurrently with it.
    }

    private func beginIfNeeded() {
        guard isRunning, pending, inFlight == nil else { return }
        pending = false
        let id = UUID(), epoch = generation
        inFlight = id
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.finished(id) }
            guard self.accepts(id, epoch: epoch) else { return }
            let state = await self.inspect()
            guard self.accepts(id, epoch: epoch) else { return }
            self.onResult(state)
            guard state == .granted, self.accepts(id, epoch: epoch) else { return }
            // The owner retains its installation latch and must check task
            // cancellation after its own awaits before installing observers.
            await self.resume()
        }
    }

    private func accepts(_ id: UUID, epoch: UUID) -> Bool {
        isRunning && generation == epoch && inFlight == id && !Task.isCancelled
    }

    private func finished(_ id: UUID) {
        guard inFlight == id else { return }
        inFlight = nil; task = nil
        beginIfNeeded()
    }
}
