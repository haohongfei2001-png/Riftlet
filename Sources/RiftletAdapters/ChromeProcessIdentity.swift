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
    private let executablePath: String?

    public var session: String {
        "\(browser.sessionPrefix):\(pid):\(birth.seconds):\(birth.microseconds)"
    }

    let browser: AttachmentBrowser

    init?(birth: KernelProcessBirth, applicationID: String?, terminated: Bool, launchDate: Date?, executablePath: String? = nil) {
        guard let applicationID, let browser = AttachmentBrowser(rawValue: applicationID), !terminated else { return nil }
        self.browser = browser
        self.applicationID = applicationID; pid = birth.pid; self.birth = birth; legacyLaunchDate = launchDate
        self.executablePath = executablePath
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
                                  terminated: app.isTerminated, launchDate: app.launchDate,
                                  executablePath: kernelExecutablePath(pid)),
              KernelProcessBirth.read(pid: pid) == before else { return nil }
        return identity
    }

    func matchesForeground(pid: pid_t?, applicationID: String?) -> Bool {
        pid == self.pid && applicationID == self.applicationID
    }

    static func kernelExecutablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let size = UInt32(buffer.count)
        guard proc_pidpath(pid, &buffer, size) > 0 else { return nil }
        return String(validatingUTF8: buffer)
    }

    /// Launch Services classifies the receiver at acquisition. Rechecking a
    /// captured receiver needs its kernel birth and executable, even if Launch
    /// Services temporarily has no application object for the running PID.
    public func isCurrent() -> Bool {
        guard let executablePath else { return Self.read(pid: pid, applicationID: applicationID) == self }
        guard KernelProcessBirth.read(pid: pid) == birth, Self.kernelExecutablePath(pid) == executablePath else { return false }
        return KernelProcessBirth.read(pid: pid) == birth
    }

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
