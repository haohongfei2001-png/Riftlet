import AppKit
import Darwin
import RiftletCore

/// Process birth, not a page/target proof. Some Chrome launches have no
/// LaunchServices launchDate. Integer kernel birth identity also survives a
/// launchDate becoming available later without changing a new target's session.
public struct ChromeProcessIdentity: Equatable, Sendable {
    public let pid: pid_t
    public let applicationID: String
    let birth: KernelProcessBirth
    let legacyLaunchDate: Date?

    public var session: String {
        let browser = applicationID == AttachmentBrowser.chrome.rawValue ? "chrome" : "edge"
        return "\(browser)-kernel-v1:\(pid):\(birth.seconds):\(birth.microseconds)"
    }

    init?(birth: KernelProcessBirth, applicationID: String?, terminated: Bool, launchDate: Date?) {
        guard let applicationID, Self.supports(applicationID), !terminated else { return nil }
        self.applicationID = applicationID; pid = birth.pid; self.birth = birth; legacyLaunchDate = launchDate
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.birth == rhs.birth && lhs.applicationID == rhs.applicationID }

    public static func supports(_ id: String) -> Bool {
        AttachmentBrowser(rawValue: id) != nil
    }

    public static func read(pid: pid_t, applicationID: String = AttachmentBrowser.chrome.rawValue) -> Self? {
        guard let before = KernelProcessBirth.read(pid: pid),
              let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == applicationID,
              let identity = Self(birth: before, applicationID: app.bundleIdentifier,
                                  terminated: app.isTerminated, launchDate: app.launchDate),
              KernelProcessBirth.read(pid: pid) == before else { return nil }
        return identity
    }

    func matchesForeground(pid: pid_t?, applicationID: String?) -> Bool {
        pid == self.pid && applicationID == self.applicationID
    }

    public func isCurrent() -> Bool { Self.read(pid: pid, applicationID: applicationID) == self }

    /// Legacy spelling is never inferred from kernel time or rewritten into a
    /// stored operation. It is accepted only for explicitly read-only recovery.
    public func matches(session: String, allowLegacyObservation: Bool = false) -> Bool {
        if session == self.session { return true }
        guard applicationID == AttachmentBrowser.chrome.rawValue, allowLegacyObservation, let date = legacyLaunchDate,
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
