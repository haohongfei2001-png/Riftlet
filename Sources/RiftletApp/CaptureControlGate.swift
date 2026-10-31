import Foundation

/// MainActor-owned serialization of explicit source rechecks and Pause/Resume.
/// A recheck may reopen the watcher, so it must never outlive a newer Pause.
/// Hide/history do not use this gate and remain immediately available.
struct CaptureControlGate {
    enum Action: Equatable { case recheck, changeCollection }
    private(set) var action: Action?
    private var owner: UUID?
    var isBusy: Bool { owner != nil }

    mutating func begin(_ action: Action) -> UUID? {
        guard owner == nil else { return nil }
        let token = UUID()
        owner = token; self.action = action
        return token
    }

    mutating func finish(_ token: UUID) {
        guard owner == token else { return }
        owner = nil; action = nil
    }
}
