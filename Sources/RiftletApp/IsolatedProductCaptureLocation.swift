import Foundation
import Darwin
import RiftletCapture

/// The isolated package uses the ordinary collector, but must never watch the
/// user's screenshot directory. No argument, preference or environment variable
/// can redirect this provider. The normal product still uses the system provider.
actor IsolatedProductCaptureLocation: CaptureLocationProviding {
    enum Failure: Error { case unsafeDirectory }
    private let root: URL
    private let directory: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
        directory = Self.directory(in: root)
    }

    nonisolated static func directory(in root: URL) -> URL {
        root.standardizedFileURL.appendingPathComponent("capture-source", isDirectory: true)
    }

    nonisolated private static func validate(_ directory: URL) throws {
        var info = stat()
        guard directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path,
              lstat(directory.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw Failure.unsafeDirectory }
    }

    nonisolated static func permitsRead(_ source: URL, root: URL) -> Bool {
        guard source.standardizedFileURL.path == directory(in: root).path else { return false }
        do { try validate(root); try validate(source); return true }
        catch { return false }
    }

    func currentDirectory() throws -> URL {
        try Self.validate(root)
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw Failure.unsafeDirectory }
        // Repeated reads/start must preserve the original directory and files.
        // EEXIST is acceptable only after the same strict validation below.
        guard mkdir(directory.path, 0o700) == 0 || errno == EEXIST else { throw Failure.unsafeDirectory }
        try Self.validate(root)
        try Self.validate(directory)
        return directory
    }

    func start(onChange: @escaping @Sendable () async -> Void) throws {
        // CaptureService owns the source's real filesystem watcher. This fixed
        // location has no screenshot-preference observer or fallback to Desktop.
        _ = try currentDirectory()
    }

    func stop() {}
}
