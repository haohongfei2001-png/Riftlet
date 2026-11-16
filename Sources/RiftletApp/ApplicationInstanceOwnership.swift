import Foundation
import Darwin

/// Own the entire App mode before starting any sidecar, UI or store. Separate
/// subsystem locks still protect their stores, but cannot choose different App
/// instances as owners during concurrent startup.
final class ApplicationInstanceOwnership {
    enum Failure: Error { case unavailable }
    let root: URL
    private let createdLock: Bool
    private var descriptor: Int32 = -1
    private var processOwnsDescriptor = false

    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let path = root.appendingPathComponent("instance.lock").path
        let flags = O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        let created = Darwin.open(path, O_CREAT | O_EXCL | flags, 0o600)
        createdLock = created >= 0
        let fd = createdLock ? created : (errno == EEXIST ? Darwin.open(path, flags) : -1)
        guard fd >= 0 else { throw Failure.unavailable }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw Failure.unavailable
        }
        descriptor = fd
    }

    /// Run under the instance lock, before first-use, SQLite, or sidecars write profile evidence.
    func isNewProfile(defaults: UserDefaults, domain: String, reviewMarker: Bool = false) -> Bool {
        guard createdLock, (defaults.persistentDomain(forName: domain) ?? [:]).isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return false }
        return files.allSatisfy { $0 == "instance.lock" || (reviewMarker && $0 == "settings-review-identity.txt") }
    }

    /// Call only from applicationWillTerminate, after termination is irrevocable.
    /// Sidecar stores may still own their locks until process teardown. Keeping
    /// this descriptor open prevents a successor from taking the App lock first.
    /// The kernel releases it on exit/crash; O_CLOEXEC prevents child inheritance.
    func keepUntilProcessExit() { processOwnsDescriptor = true }

    func close() {
        guard !processOwnsDescriptor, descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN); Darwin.close(descriptor); descriptor = -1
    }

    deinit { close() }
}
