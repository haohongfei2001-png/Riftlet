import Foundation

/// One pending AX hint binding, never target or permission authority. A stale
/// capture completion cannot consume a newer foreground epoch's binding request.
struct DeferredChromeActivityBinding {
    private var pendingEpoch: UUID?

    mutating func request(afterCaptureIn epoch: UUID) { pendingEpoch = epoch }

    mutating func take(afterCaptureIn epoch: UUID, isRunning: Bool) -> Bool {
        guard isRunning, pendingEpoch == epoch else { return false }
        pendingEpoch = nil
        return true
    }

    mutating func cancel() { pendingEpoch = nil }
}
