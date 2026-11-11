/// User-facing minutes. The on-disk preference and queue cutoffs use seconds.
public enum QueueArchivePolicy {
    public static let defaultMinutes: Double = 2
    public static let minutesRange: ClosedRange<Double> = 1...10
}
