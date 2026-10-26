import Foundation
import Darwin

public enum StorageUsageArea: String, Codable, CaseIterable, Sendable {
    case media, staging, journal, database
}

public enum StorageAreaAvailability: String, Codable, Sendable { case present, absent, unavailable }

/// Generic classifications only: never a private filename, path or file content.
public enum StorageUsageIssue: String, Codable, Hashable, Sendable {
    case inaccessible, unsafeEntry, unsupportedType, invalidMetadata
    case entryLimit, arithmeticOverflow, changedDuringScan
}

public struct StorageAreaUsage: Codable, Equatable, Sendable {
    public let area: StorageUsageArea
    public private(set) var availability: StorageAreaAvailability
    public private(set) var regularFileCount = 0
    /// Logical bytes per regular directory entry, not unique physical/APFS allocation.
    /// nil means the sum overflowed and must not be presented as a complete number.
    public private(set) var logicalBytes: UInt64? = 0
    public private(set) var skippedEntryCount = 0
    public private(set) var issues: Set<StorageUsageIssue> = []
    public var isComplete: Bool { availability != .unavailable && issues.isEmpty }

    init(area: StorageUsageArea, availability: StorageAreaAvailability) {
        self.area = area; self.availability = availability
    }

    mutating func observeRegularFile(logicalBytes bytes: UInt64) {
        regularFileCount += 1
        guard let subtotal = logicalBytes else { return }
        let addition = subtotal.addingReportingOverflow(bytes)
        if addition.overflow { logicalBytes = nil; issues.insert(.arithmeticOverflow) }
        else { logicalBytes = addition.partialValue }
    }

    fileprivate mutating func skip(_ issue: StorageUsageIssue) {
        skippedEntryCount += 1; issues.insert(issue)
    }

    fileprivate mutating func addIssue(_ issue: StorageUsageIssue) { issues.insert(issue) }
    fileprivate mutating func setAvailability(_ value: StorageAreaAvailability) { availability = value }
}

public struct StorageUsageSnapshot: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let areas: [StorageAreaUsage]
    public var regularFileCount: Int { areas.reduce(0) { $0 + $1.regularFileCount } }
    public var skippedEntryCount: Int { areas.reduce(0) { $0 + $1.skippedEntryCount } }
    public var logicalBytes: UInt64? {
        var total: UInt64 = 0
        for area in areas {
            guard let bytes = area.logicalBytes else { return nil }
            let addition = total.addingReportingOverflow(bytes)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }
    /// Complete means this bounded enumeration encountered no skipped/unknown entry.
    /// The live filesystem may change during or after observation; this is not an atomic
    /// snapshot, a disk-free-space guarantee or an estimate of space deletion would free.
    public var isComplete: Bool { areas.allSatisfy(\.isComplete) && logicalBytes != nil }
}

public enum StorageUsageError: Error, Equatable, Sendable {
    case invalidRoot, invalidLimit, unsafeRoot, cannotOpenRoot(Int32)
}

/// On-demand, nonrecursive metadata accounting for the application's fixed private layout.
/// Child operations are relative to open directory descriptors and never follow symlinks.
/// Unknown root files (including configuration and instance locks) are outside this scope.
public enum PrivateStorageUsage {
    public static func measure(privateRoot: URL, maximumEntriesPerArea: Int = 25_000) throws -> StorageUsageSnapshot {
        guard privateRoot.isFileURL, !privateRoot.path.utf8.contains(0) else { throw StorageUsageError.invalidRoot }
        guard (1...1_000_000).contains(maximumEntriesPerArea) else { throw StorageUsageError.invalidLimit }
        let started = Date()
        var rootPath = privateRoot.path
        // A terminal slash must not turn a root symlink into a followed directory.
        while rootPath.count > 1 && rootPath.hasSuffix("/") { rootPath.removeLast() }
        let descriptor = Darwin.open(rootPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StorageUsageError.cannotOpenRoot(errno) }
        defer { Darwin.close(descriptor) }
        var rootInfo = stat()
        guard fstat(descriptor, &rootInfo) == 0,
              rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              rootInfo.st_uid == getuid() else { throw StorageUsageError.unsafeRoot }

        var areas = [StorageUsageArea.media, .staging, .journal].map {
            scanDirectory(rootDescriptor: descriptor, area: $0, limit: maximumEntriesPerArea)
        }
        areas.append(scanDatabase(rootDescriptor: descriptor))
        return StorageUsageSnapshot(startedAt: started, finishedAt: Date(), areas: areas)
    }

    private static func scanDirectory(rootDescriptor: Int32, area: StorageUsageArea, limit: Int) -> StorageAreaUsage {
        var usage = StorageAreaUsage(area: area, availability: .present)
        var linkInfo = stat()
        guard fstatat(rootDescriptor, area.rawValue, &linkInfo, AT_SYMLINK_NOFOLLOW) == 0 else {
            usage.setAvailability(errno == ENOENT ? .absent : .unavailable)
            if usage.availability == .unavailable { usage.addIssue(.inaccessible) }
            return usage
        }
        guard linkInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            usage.setAvailability(.unavailable)
            usage.skip(linkInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) ? .unsafeEntry : .unsupportedType)
            return usage
        }
        let descriptor = Darwin.openat(rootDescriptor, area.rawValue, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            usage.setAvailability(.unavailable); usage.addIssue(.inaccessible)
            return usage
        }
        // fdopendir owns and closes descriptor on success; never close it twice.
        guard let directory = fdopendir(descriptor) else {
            Darwin.close(descriptor)
            usage.setAvailability(.unavailable); usage.addIssue(.inaccessible)
            return usage
        }
        defer { closedir(directory) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0 else {
            usage.setAvailability(.unavailable); usage.addIssue(.inaccessible)
            return usage
        }
        var visited = 0
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { usage.addIssue(.inaccessible) }
                break
            }
            let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
            let stop = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { name -> Bool in
                    if name[0] == 46 && (name[1] == 0 || (name[1] == 46 && name[2] == 0)) { return false }
                    guard visited < limit else { usage.addIssue(.entryLimit); return true }
                    visited += 1
                    var info = stat()
                    guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                        usage.skip(errno == ENOENT ? .changedDuringScan : .inaccessible)
                        return false
                    }
                    account(info, in: &usage)
                    return false
                }
            }
            if stop { break }
        }
        var final = stat()
        if fstat(descriptor, &final) != 0 { usage.addIssue(.inaccessible) }
        else if initial.st_mtimespec.tv_sec != final.st_mtimespec.tv_sec
            || initial.st_mtimespec.tv_nsec != final.st_mtimespec.tv_nsec
            || initial.st_ctimespec.tv_sec != final.st_ctimespec.tv_sec
            || initial.st_ctimespec.tv_nsec != final.st_ctimespec.tv_nsec {
            usage.addIssue(.changedDuringScan)
        }
        return usage
    }

    private static func scanDatabase(rootDescriptor: Int32) -> StorageAreaUsage {
        var usage = StorageAreaUsage(area: .database, availability: .absent)
        for name in ["queue.sqlite", "queue.sqlite-wal", "queue.sqlite-shm"] {
            var info = stat()
            guard fstatat(rootDescriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno != ENOENT { usage.setAvailability(.unavailable); usage.skip(.inaccessible) }
                continue
            }
            if usage.availability != .unavailable { usage.setAvailability(.present) }
            account(info, in: &usage)
        }
        return usage
    }

    private static func account(_ info: stat, in usage: inout StorageAreaUsage) {
        switch info.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFREG):
            guard info.st_size >= 0 else { usage.skip(.invalidMetadata); return }
            usage.observeRegularFile(logicalBytes: UInt64(info.st_size))
        case mode_t(S_IFLNK): usage.skip(.unsafeEntry)
        default: usage.skip(.unsupportedType)
        }
    }
}
