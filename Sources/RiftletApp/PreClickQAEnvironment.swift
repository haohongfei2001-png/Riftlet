import Darwin
import Foundation
import RiftletCapture

/// Selects a private store for the ordinary attachment implementation. No
/// caller-supplied directory, screenshot preference, or browser is accepted.
enum PreClickQAEnvironment {
    private static let flag = "--preclick-qa-profile"

    static func resolve(arguments: [String], mode: ApplicationMode, applicationSupport: URL) throws -> SettingsReviewEnvironment? {
        guard arguments.contains(where: { $0.hasPrefix("--preclick-") }) else { return nil }
        let flags = arguments.indices.filter { arguments[$0] == flag }
        guard mode == .capture, !OrdinaryCaptureConfiguration.isInternalAcceptance, flags.count == 1,
              let index = flags.first, arguments.indices.contains(index + 1),
              let id = UUID(uuidString: arguments[index + 1]),
              id.uuidString.lowercased() == arguments[index + 1].lowercased() else {
            throw SettingsReviewEnvironment.Failure.invalidIdentifier
        }
        var extra = arguments
        extra.removeSubrange(index...index + 1)
        if index > 0, arguments.first?.hasPrefix("-") == false { extra.removeFirst() }
        guard extra.isEmpty || extra == ["--acceptance-trace"] else { throw SettingsReviewEnvironment.Failure.invalidIdentifier }
        return SettingsReviewEnvironment(identifier: id, applicationSupport: applicationSupport, isPreClickQA: true)
    }

    struct FixedSource: CaptureLocationProviding {
        let directory: URL
        func currentDirectory() async throws -> URL {
            guard directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path,
                  try PreClickQAEnvironment.entry(directory).st_mode & S_IFMT == S_IFDIR else {
                throw SettingsReviewEnvironment.Failure.foreignDirectory
            }
            return directory.standardizedFileURL
        }
        func start(onChange: @escaping @Sendable () async -> Void) async throws { _ = try await currentDirectory() }
        func stop() async {}
    }

    private static func entry(_ url: URL) throws -> stat {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == geteuid() else { throw SettingsReviewEnvironment.Failure.foreignDirectory }
        return info
    }

    // Run before acquiring the app lock or reading marker bytes. A legitimate
    // UUID in a path does not establish ownership of an existing directory.
    static func checkOwnership(root: URL, marker: URL, byteCount: Int) throws {
        let folder = try entry(root), identity = try entry(marker)
        guard folder.st_mode & S_IFMT == S_IFDIR, folder.st_mode & 0o077 == 0,
              identity.st_mode & S_IFMT == S_IFREG, identity.st_nlink == 1,
              identity.st_size == byteCount else { throw SettingsReviewEnvironment.Failure.foreignDirectory }
        let lock = root.appendingPathComponent("instance.lock")
        var lockInfo = stat()
        if lstat(lock.path, &lockInfo) == 0 {
            guard lockInfo.st_uid == geteuid(), lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_nlink == 1 else {
                throw SettingsReviewEnvironment.Failure.foreignDirectory
            }
        } else if errno != ENOENT { throw SettingsReviewEnvironment.Failure.foreignDirectory }
    }

    /// Under the app lock, refuse links into other stores before opening any
    /// SQLite, media, feedback or settings path. Inspect metadata only.
    static func checkTree(root: URL) throws {
        let folder = try entry(root)
        guard folder.st_mode & S_IFMT == S_IFDIR, folder.st_mode & 0o077 == 0 else {
            throw SettingsReviewEnvironment.Failure.foreignDirectory
        }
        var failure: Error?
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [], errorHandler: { _, error in
            failure = error; return false
        }) else { throw SettingsReviewEnvironment.Failure.foreignDirectory }
        for case let url as URL in files {
            let item = try entry(url), kind = item.st_mode & S_IFMT
            guard item.st_dev == folder.st_dev, kind == S_IFDIR || (kind == S_IFREG && item.st_nlink == 1) else {
                throw SettingsReviewEnvironment.Failure.foreignDirectory
            }
        }
        if let failure { throw failure }
    }
}
