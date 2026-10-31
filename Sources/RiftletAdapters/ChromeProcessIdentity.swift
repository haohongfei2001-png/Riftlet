import AppKit
import Darwin

/// Process birth, not a page/target proof. Some Chrome launches have no
/// LaunchServices launchDate. Integer kernel birth identity also survives a
/// launchDate becoming available later without changing a new target's session.
public struct ChromeProcessIdentity: Equatable, Sendable {
    public let pid: pid_t
    let birth: KernelProcessBirth
    let legacyLaunchDate: Date?

    public var session: String {
        "chrome-kernel-v1:\(pid):\(birth.seconds):\(birth.microseconds)"
    }

    init?(birth: KernelProcessBirth, applicationID: String?, terminated: Bool, launchDate: Date?) {
        guard applicationID == "com.google.Chrome", !terminated else { return nil }
        pid = birth.pid; self.birth = birth; legacyLaunchDate = launchDate
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.birth == rhs.birth }

    public static func read(pid: pid_t) -> Self? {
        guard let before = KernelProcessBirth.read(pid: pid),
              let app = NSRunningApplication(processIdentifier: pid),
              let identity = Self(birth: before, applicationID: app.bundleIdentifier,
                                  terminated: app.isTerminated, launchDate: app.launchDate),
              KernelProcessBirth.read(pid: pid) == before else { return nil }
        return identity
    }

    public func isCurrent() -> Bool { Self.read(pid: pid) == self }

    /// Legacy spelling is never inferred from kernel time or rewritten into a
    /// stored operation. It is accepted only for explicitly read-only recovery.
    public func matches(session: String, allowLegacyObservation: Bool = false) -> Bool {
        if session == self.session { return true }
        guard allowLegacyObservation, let date = legacyLaunchDate,
              date.timeIntervalSince1970.isFinite else { return false }
        return session == "\(pid):\(date.timeIntervalSince1970)"
    }
}

struct KernelProcessBirth: Equatable, Sendable {
    let pid: pid_t
    let seconds: UInt64
    let microseconds: UInt64

    init?(requestedPID: pid_t, record: proc_bsdinfo, bytesRead: Int32) {
        guard requestedPID > 0, bytesRead == MemoryLayout<proc_bsdinfo>.size,
              record.pbi_pid == UInt32(requestedPID), record.pbi_start_tvsec > 0,
              record.pbi_start_tvusec < 1_000_000 else { return nil }
        pid = requestedPID; seconds = record.pbi_start_tvsec; microseconds = record.pbi_start_tvusec
    }

    static func read(pid: pid_t) -> Self? {
        var record = proc_bsdinfo()
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &record, Int32(MemoryLayout<proc_bsdinfo>.size))
        return Self(requestedPID: pid, record: record, bytesRead: count)
    }
}
