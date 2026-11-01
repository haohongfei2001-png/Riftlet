/// Unadmitted local-only engineering candidate. No CLI/user default enables it.
/// Official builds keep PR31 routing for all sources, including web acceptance.
/// A disposable local build additionally needs the owned-loopback page fixture;
/// its production page program's origin predicate is never widened here.
public enum PendingClickConfiguration {
    #if RIFTLET_PENDING_CLICK_LOCAL
    public static let enabled = true
    #else
    public static let enabled = false
    #endif
}
