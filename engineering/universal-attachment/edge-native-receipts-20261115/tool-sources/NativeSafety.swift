import Foundation
import CoreGraphics
import Darwin

struct Failure: Error { let code: String }
func require(_ condition: Bool, _ code: String) throws {
    if !condition { throw Failure(code: code) }
}
func validHash(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
}
func validAttempt(_ value: String) -> Bool {
    value.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil
}
func ownedData(_ path: String, limit: Int) throws -> Data {
    let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    try require(fd >= 0, "ownedFileUnavailable")
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var before = stat()
    try require(fstat(fd, &before) == 0 && before.st_uid == getuid() && (before.st_mode & S_IFMT) == S_IFREG,
                "ownedFileIdentityInvalid")
    try require(before.st_size > 0 && before.st_size < limit, "ownedFileSizeInvalid")
    guard let data = try handle.read(upToCount: limit), data.count == before.st_size else {
        throw Failure(code: "ownedFileReadIncomplete")
    }
    var after = stat()
    try require(fstat(fd, &after) == 0 && before.st_dev == after.st_dev && before.st_ino == after.st_ino
        && before.st_size == after.st_size && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
        && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec, "ownedFileChanged")
    return data
}

/// Open each literal directory component without following a symbolic link.
/// Ancestors need not be private (e.g. /Users); the owned final directory must be.
func privateDirectory(_ path: String, create: Bool) throws -> Int32 {
    try require(path.hasPrefix("/") && !path.contains("//"), "directoryPathInvalid")
    let components = path.split(separator: "/").map(String.init)
    try require(!components.isEmpty && components.allSatisfy { $0 != "." && $0 != ".." }, "directoryPathInvalid")
    var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    try require(fd >= 0, "directoryRootUnavailable")
    do {
        for (index, component) in components.enumerated() {
            let final = index == components.count - 1
            if final && create {
                let made = mkdirat(fd, component, 0o700)
                try require(made == 0 || errno == EEXIST, "directoryCreationFailed")
            }
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            try require(next >= 0, "directoryNotUnlinkedFolder")
            if final {
                var info = stat(), linked = stat()
                let okay = fstat(next, &info) == 0 && fstatat(fd, component, &linked, AT_SYMLINK_NOFOLLOW) == 0
                    && info.st_uid == getuid() && (info.st_mode & S_IFMT) == S_IFDIR
                    && (info.st_mode & 0o7777) == 0o700 && info.st_dev == linked.st_dev && info.st_ino == linked.st_ino
                if !okay { close(next); throw Failure(code: "directoryIdentityOrModeInvalid") }
            }
            close(fd); fd = next
        }
        return fd
    } catch { close(fd); throw error }
}
func writeExclusive(_ directoryFD: Int32, name: String, data: Data) throws {
    try require(!name.isEmpty && !name.contains("/") && name != "." && name != "..", "receiptNameInvalid")
    let fd = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    try require(fd >= 0, "receiptAlreadyReservedOrUnavailable")
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? file.close() }
    try file.write(contentsOf: data)
    try require(fsync(fd) == 0 && fsync(directoryFD) == 0, "receiptNotDurable")
}
func readAt(_ directoryFD: Int32, name: String, limit: Int) throws -> Data? {
    let fd = openat(directoryFD, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    if fd < 0 && errno == ENOENT { return nil }
    try require(fd >= 0, "receiptReadUnavailable")
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? file.close() }
    var info = stat()
    try require(fstat(fd, &info) == 0 && info.st_uid == getuid() && (info.st_mode & S_IFMT) == S_IFREG
        && (info.st_mode & 0o7777) == 0o600 && info.st_size > 0 && info.st_size < limit, "receiptIdentityInvalid")
    guard let data = try file.read(upToCount: limit), data.count == info.st_size else { throw Failure(code: "receiptReadIncomplete") }
    return data
}

struct SemanticWindow: Equatable {
    let role, subrole: String
    let main: Bool
    let frame: CGRect
}
struct ServerWindow: Equatable {
    let pid: Int32
    let layer, number: Int
    let frame: CGRect
}
func validFrame(_ frame: CGRect) -> Bool {
    [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
        && frame.width > 0 && frame.height > 0
}
func matchStandardWindow(_ semantic: [SemanticWindow], _ server: [ServerWindow], pid: Int32) throws -> Int {
    try require((1...16).contains(semantic.count) && !server.isEmpty && server.count <= 16, "edgeWindowSetUnavailable")
    try require(semantic.allSatisfy { validFrame($0.frame) } && server.allSatisfy {
        $0.pid == pid && $0.layer == 0 && $0.number > 0 && validFrame($0.frame)
    }, "edgeWindowGeometryInvalid")
    try require(Set(server.map(\.number)).count == server.count, "edgeDuplicateServerWindow")
    let mains = semantic.filter { $0.role == "AXWindow" && $0.subrole == "AXStandardWindow" && $0.main }
    guard mains.count == 1, let main = mains.first else { throw Failure(code: "edgeMainWindowNotUnique") }
    let matches = server.filter { $0.frame == main.frame }
    guard matches.count == 1, let selected = matches.first else { throw Failure(code: "edgeMainWindowNotMatched") }
    let dialogs = semantic.filter { !$0.main && ($0.role == "AXDialog" || ($0.role == "AXWindow" && $0.subrole == "AXDialog")) }
    for window in server where window.number != selected.number {
        let candidates = dialogs.filter { $0.frame == window.frame }
        try require(candidates.count == 1 && server.filter { $0.frame == window.frame }.count == 1,
                    "edgeOtherWindowNotVerifiedDialog")
    }
    return selected.number
}

// Exact source logic from ChromeProcessIdentity.swift, source c3278c0.
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
