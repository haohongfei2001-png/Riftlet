import AppKit
import Darwin

/// Edge's own launch identity. It is never decoded from a page reply and has no
/// legacy Chrome-session alias. Reusing a PID after exit cannot revive a lease.
public struct EdgeProcessIdentity: Equatable, Sendable {
    public let pid: pid_t
    let birth: KernelProcessBirth
    public var session: String { "edge-kernel-v1:\(pid):\(birth.seconds):\(birth.microseconds)" }

    init?(birth: KernelProcessBirth, applicationID: String?, terminated: Bool) {
        guard applicationID == EdgeApplicationHost.bundleID, !terminated else { return nil }
        self.birth = birth; pid = birth.pid
    }

    public static func read(pid: pid_t) -> Self? {
        guard let before = KernelProcessBirth.read(pid: pid),
              let app = NSRunningApplication(processIdentifier: pid),
              let value = Self(birth: before, applicationID: app.bundleIdentifier, terminated: app.isTerminated),
              KernelProcessBirth.read(pid: pid) == before else { return nil }
        return value
    }

    public static func currentForeground() -> Self? {
        guard let app = NSWorkspace.shared.frontmostApplication, let value = read(pid: app.processIdentifier),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == value.pid else { return nil }
        return value
    }

    public func isCurrent() -> Bool { Self.read(pid: pid) == self }

    static func sessionPID(_ session: String) -> pid_t? {
        let parts = session.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "edge-kernel-v1", let pid = Int32(parts[1]), pid > 0,
              String(pid) == parts[1], let seconds = UInt64(parts[2]), seconds > 0, String(seconds) == parts[2],
              let micros = UInt64(parts[3]), micros < 1_000_000, String(micros) == parts[3] else { return nil }
        return pid
    }

    static func recover(_ session: String) -> Self? {
        guard let pid = sessionPID(session), let value = read(pid: pid), value.session == session else { return nil }
        return value
    }
}
