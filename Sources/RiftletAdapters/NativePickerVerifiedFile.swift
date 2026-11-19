import CryptoKit
import Darwin
import Foundation

/// Private regular-file identity is checked on an open descriptor, then against
/// the exact clipboard path before action. The importer remains codec authority.
final class NativeMacVerifiedFile {
    private let descriptor: Int32
    private let directoryDescriptor: Int32
    private let directory: URL
    private let name: String
    private let original: stat
    private let originalDirectory: stat
    private let expectedHash: String

    init(fileURL: URL, mediaDirectory: URL, name: String, byteCount: Int64, sha256: String) throws {
        let url = fileURL.standardizedFileURL
        guard mediaDirectory.isFileURL, url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.deletingLastPathComponent().path == mediaDirectory.path, url.lastPathComponent == name,
              !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), byteCount > 0,
              byteCount <= 16 * 1024 * 1024 else { throw NativeMacAXError.invalidPrivateFile }
        let dirFD = open(mediaDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw NativeMacAXError.invalidPrivateFile }
        var directoryStat = stat()
        guard fstat(dirFD, &directoryStat) == 0 else { close(dirFD); throw NativeMacAXError.invalidPrivateFile }
        let fd = openat(dirFD, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { close(dirFD); throw NativeMacAXError.invalidPrivateFile }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_size == byteCount else {
            close(fd); close(dirFD); throw NativeMacAXError.invalidPrivateFile
        }
        descriptor = fd; directoryDescriptor = dirFD; directory = mediaDirectory; self.name = name
        original = info; originalDirectory = directoryStat; expectedHash = sha256
    }

    deinit { close(descriptor); close(directoryDescriptor) }

    func verifyBytes(expectedPrefix: Data = Data()) throws {
        var hasher = SHA256()
        var total: Int64 = 0
        var buffer = Data(count: 64 * 1024)
        while true {
            let count: Int = buffer.withUnsafeMutableBytes { bytes in
                var result: Int
                repeat { result = read(descriptor, bytes.baseAddress, bytes.count) } while result < 0 && errno == EINTR
                return result
            }
            guard count >= 0 else { throw NativeMacAXError.invalidPrivateFile }
            if count == 0 { break }
            let remaining = expectedPrefix.count - min(expectedPrefix.count, Int(total))
            let checked = min(remaining, count)
            if checked > 0, !buffer.prefix(checked).elementsEqual(expectedPrefix.dropFirst(Int(total)).prefix(checked)) {
                throw NativeMacAXError.invalidPrivateFile
            }
            total += Int64(count)
            guard total <= original.st_size else { throw NativeMacAXError.invalidPrivateFile }
            hasher.update(data: buffer.prefix(count))
        }
        guard total == original.st_size, total >= Int64(expectedPrefix.count),
              hasher.finalize().map({ String(format: "%02x", $0) }).joined() == expectedHash else {
            throw NativeMacAXError.invalidPrivateFile
        }
        try verifyPathAndMetadata()
    }

    func verifyPathAndMetadata() throws {
        var now = stat(); var path = stat(); var dirPath = stat()
        guard fstat(descriptor, &now) == 0,
              fstatat(directoryDescriptor, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
              lstat(directory.path, &dirPath) == 0,
              dirPath.st_dev == originalDirectory.st_dev, dirPath.st_ino == originalDirectory.st_ino,
              Self.sameFile(original, now), Self.sameFile(original, path) else {
            throw NativeMacAXError.invalidPrivateFile
        }
    }

    private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
        (rhs.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) && lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
