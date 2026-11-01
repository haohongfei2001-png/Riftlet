import RiftletCore

/// Startup-only scheduling, not observation or upload authority. Give one
/// replacement capture a head start when the first result belongs to an old
/// epoch. A second stale result releases recovery too, so repeated switching
/// cannot starve original-ID-only UNKNOWN observations. No timer or click is
/// retained, and every actual recovery still performs its own permission check.
struct OriginalRecoveryDeferral {
    private var deferredStaleCompletion = false

    mutating func shouldStart(after completion: TargetArmScheduler.Completion, isRunning: Bool) -> Bool {
        guard isRunning else { return false }
        if !completion.acceptsAcknowledgement, completion.shouldWake, !deferredStaleCompletion {
            deferredStaleCompletion = true
            return false
        }
        return true
    }
}
