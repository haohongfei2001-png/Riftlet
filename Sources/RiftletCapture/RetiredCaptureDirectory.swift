import Foundation
import Darwin

/// An acknowledged old watch supplies the identity. The stream and all candidate
/// lookups stay on that exact opened directory even if its pathname is replaced.
final class RetiredCaptureDirectory {
    private let directoryDescriptor: Int32
    private let identity: WatchedFileIdentity
    private let originalURL: URL

    init?(url: URL, identity: WatchedFileIdentity) {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0, identity.matches(info, descriptor: fd) else {
            Darwin.close(fd)
            return nil
        }
        directoryDescriptor = fd
        self.identity = identity
        originalURL = url
    }

    deinit { Darwin.close(directoryDescriptor) }

    func candidates() -> (files: [(URL, FileSignature)], complete: Bool) {
        // fdopendir can snapshot names immediately on macOS. Open a fresh
        // stream only now, relative to the verified directory, for each scan.
        let parent = Darwin.openat(directoryDescriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { return ([], false) }
        guard let stream = fdopendir(parent) else {
            Darwin.close(parent)
            return ([], false)
        }
        defer { closedir(stream) }
        var entries: [(String, FileSignature)] = []
        var complete = true
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { complete = false }
                break
            }
            let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
            withUnsafePointer(to: &entry.pointee.d_name) { buffer in
                buffer.withMemoryRebound(to: CChar.self, capacity: capacity) { name in
                    guard name[0] != 46 else { return }
                    guard let filename = String(validatingCString: name) else { complete = false; return }
                    guard CaptureSource.mayBeImage(originalURL.appendingPathComponent(filename)) else { return }
                    let child = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else {
                        if errno != ELOOP { complete = false }
                        return
                    }
                    defer { Darwin.close(child) }
                    do {
                        var info = stat()
                        guard fstat(child, &info) == 0 else { complete = false; return }
                        let signature = try FileSignature.read(metadata: info, volumeUUID: CaptureVolume.identifier(of: child))
                        guard signature.volumeUUID != nil else { complete = false; return }
                        guard info.st_flags & UInt32(UF_HIDDEN) == 0 else { return }
                        guard let invisible = Self.finderInvisible(child) else { complete = false; return }
                        guard !invisible else { return }
                        entries.append((filename, signature))
                    } catch CaptureError.notRegularFile {
                        // A non-file cannot be a capture.
                    } catch { complete = false }
                }
            }
        }
        // A remembered URL locates an already proven file for later recovery.
        // The importer still checks the full file identity before reading bytes.
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let currentURL: URL
        if fcntl(parent, F_GETPATH, &path) == 0 {
            currentURL = URL(fileURLWithFileSystemRepresentation: path, isDirectory: true, relativeTo: nil)
            if !identity.matchesDirectory(currentURL) { complete = false }
        } else {
            currentURL = originalURL
            complete = false
        }
        return (entries.map { (currentURL.appendingPathComponent($0.0), $0.1) }, complete)
    }

    private static func finderInvisible(_ fd: Int32) -> Bool? {
        var data = [UInt8](repeating: 0, count: 32)
        let length = data.withUnsafeMutableBytes { bytes in
            fgetxattr(fd, "com.apple.FinderInfo", bytes.baseAddress, bytes.count, 0, 0)
        }
        if length < 0 { return errno == ENOATTR || errno == ENOTSUP ? false : nil }
        guard length >= 10 else { return nil }
        // The big-endian Finder flags word at offset 8 contains kIsInvisible.
        return data[8] & 0x40 != 0
    }
}
