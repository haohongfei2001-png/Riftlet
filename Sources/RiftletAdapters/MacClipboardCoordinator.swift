import Darwin
import Foundation
import RiftletCore

public enum MacClipboardCoordinationError: Error, Equatable {
    case busy, unresolvedOperation, duplicateOperation, invalidTransition, identityMismatch
    case journalFull, invalidJournal, unsafeStorage, storageFailure(Int32), poisoned
}

/// One scope must be shared by every cooperating Riftlet instance using the same
/// pasteboard, regardless of queue/simulation directory. This lock cannot exclude
/// another application's Copy, and NSPasteboard has no atomic compare-and-swap.
///
/// The durable journal contains identities/intent only, NEVER clipboard bytes,
/// paths, AX text or a restorable snapshot. A restarted process may observe the
/// original operation, but can neither repeat its input nor restore lost content.
public final class MacClipboardCoordinator: @unchecked Sendable {
    public enum Phase: String, Codable, Sendable {
        case reserved, clipboardWriteIntent, clipboardOwned, inputIntent, resolved, cancelled
        var unresolved: Bool { self != .resolved && self != .cancelled }
    }

    public struct Record: Codable, Equatable, Sendable {
        public let identity: ObservationIdentity
        public var phase: Phase
        public var owner: ClipboardOwnerState?
        public var resolution: Resolution?
    }

    public enum Resolution: String, Codable, Sendable { case consumed, retryPermitted }
    enum Checkpoint: Sendable { case temporaryFileSynced, journalRenamed, directorySynced }

    private struct Journal: Codable { let version: Int; var records: [Record] }
    private let mutex = NSLock()
    private let directoryFD: Int32
    private let lockFD: Int32
    private let maximumEntries: Int
    private let fault: (@Sendable (Checkpoint) throws -> Void)?
    private var ownsLock = false
    private var poisoned = false
    private var activeID: UUID?
    private var records: [Record] = []
    private static let maximumJournalBytes = 2 * 1024 * 1024

    /// Supply one private, stable directory for a pasteboard scope. Never put it
    /// in a mode-specific queue directory, delete its lock file, or clear a journal
    /// to bypass UNKNOWN. No native adapter constructs or enables itself here.
    public convenience init(directoryURL: URL) throws {
        try self.init(directoryURL: directoryURL, maximumEntries: 256, fault: nil)
    }

    init(directoryURL: URL, maximumEntries: Int,
         fault: (@Sendable (Checkpoint) throws -> Void)? = nil) throws {
        guard directoryURL.isFileURL, (1...256).contains(maximumEntries) else {
            throw MacClipboardCoordinationError.unsafeStorage
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let directory = Darwin.open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw MacClipboardCoordinationError.storageFailure(errno) }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else {
            Darwin.close(directory); throw MacClipboardCoordinationError.unsafeStorage
        }
        let file = openat(directory, "owner.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard file >= 0 else {
            let code = errno; Darwin.close(directory); throw MacClipboardCoordinationError.storageFailure(code)
        }
        guard Self.safeRegularFile(file) else {
            Darwin.close(file); Darwin.close(directory); throw MacClipboardCoordinationError.unsafeStorage
        }
        self.directoryFD = directory; self.lockFD = file
        self.maximumEntries = maximumEntries; self.fault = fault
    }

    deinit {
        // OS releases advisory ownership on process death as well. The journal
        // survives; unlock does NOT resolve the pending external operation.
        if ownsLock { _ = flock(lockFD, LOCK_UN) }
        Darwin.close(lockFD); Darwin.close(directoryFD)
    }

    /// A transient availability hint only. reserve() rechecks under the real lock.
    public func canReserve() throws -> Bool {
        try synchronized {
            guard activeID == nil else { return false }
            do { try acquireAndRead() }
            catch MacClipboardCoordinationError.busy { return false }
            defer { unlock() }
            return records.count < maximumEntries && !records.contains(where: { $0.phase.unresolved })
        }
    }

    /// Persist before even snapshotting the clipboard. Duplicate IDs are refused
    /// permanently within this journal; capacity exhaustion is fail-closed.
    public func reserve(_ request: TransferRequest) throws {
        try synchronized {
            let identity = try Self.identity(request)
            guard request.operation.phase == .dispatchIntent else {
                throw MacClipboardCoordinationError.invalidTransition
            }
            guard activeID == nil else { throw MacClipboardCoordinationError.busy }
            try acquireAndRead()
            do {
                guard !records.contains(where: { $0.identity.operationID == identity.operationID }) else {
                    throw MacClipboardCoordinationError.duplicateOperation
                }
                guard !records.contains(where: { $0.phase.unresolved }) else {
                    throw MacClipboardCoordinationError.unresolvedOperation
                }
                guard records.count < maximumEntries else { throw MacClipboardCoordinationError.journalFull }
                var next = records
                next.append(Record(identity: identity, phase: .reserved, owner: nil, resolution: nil))
                activeID = identity.operationID
                try persist(next)
            } catch {
                if !poisoned { activeID = nil; unlock() }
                throw error
            }
        }
    }

    public func markClipboardWriteIntent(for request: TransferRequest) throws {
        try update(request, allowed: [.reserved]) { $0.phase = .clipboardWriteIntent }
    }

    public func clipboardWritten(for request: TransferRequest, owner: ClipboardOwnerState) throws {
        guard Self.validOwner(owner, operationID: request.operation.id) else {
            throw MacClipboardCoordinationError.identityMismatch
        }
        try update(request, allowed: [.clipboardWriteIntent]) { $0.phase = .clipboardOwned; $0.owner = owner }
    }

    /// Native executor calls this once, before its final synchronous input checks.
    /// A throw or AX timeout after this point leaves the operation uncertain. An
    /// already-recorded intent never returns success, even for the same identity.
    public func markInputIntent(for request: TransferRequest, owner: ClipboardOwnerState) throws {
        try update(request, allowed: [.clipboardOwned]) {
            guard $0.owner == owner else { throw MacClipboardCoordinationError.identityMismatch }
            $0.phase = .inputIntent
        }
    }

    /// Only when the caller knows no clipboard mutation was attempted/completed:
    /// e.g. capture failed, or writeIfUnchanged returned nil before clearing. An
    /// exception after a native clear/write must NEVER call this method.
    public func cancelBeforeClipboardMutation(_ request: TransferRequest) throws {
        try synchronized {
            try mutateLocked(request, allowed: [.reserved, .clipboardWriteIntent]) { $0.phase = .cancelled }
            activeID = nil; unlock()
        }
    }

    /// Acquire only the original operation for observation. Its snapshot is not
    /// persisted or reconstructed. No transition here authorizes another paste.
    @discardableResult
    public func recoverForObservation(_ request: TransferRequest) throws -> Record {
        try synchronized {
            let identity = try Self.identity(request)
            if let activeID {
                guard activeID == identity.operationID else { throw MacClipboardCoordinationError.busy }
            } else { try acquireAndRead() }
            do {
                guard let record = records.first(where: { $0.identity.operationID == identity.operationID }),
                      record.identity == identity else {
                    throw MacClipboardCoordinationError.identityMismatch
                }
                activeID = identity.operationID
                if record.phase == .cancelled {
                    activeID = nil; unlock(); return record
                }
                if record.phase == .reserved {
                    // No write intent ever became durable, so this reservation
                    // cannot have reached our native clipboard mutation. Retain
                    // its tombstone; allow different work without replaying it.
                    try mutateLocked(request, allowed: [.reserved]) { $0.phase = .cancelled }
                    let cancelled = records.first(where: { $0.identity == identity })!
                    activeID = nil; unlock()
                    return cancelled
                }
                return record
            } catch {
                if activeID == nil { unlock() }
                throw error
            }
        }
    }

    /// Policy remains the admission authority. Persist resolution BEFORE a best-
    /// effort restoration, retaining the lock until finishSettlement() is called.
    /// A crash during restore cannot replay input or restore after restart.
    @discardableResult
    public func authorizeSettlement(_ receipt: TransferReceipt, request: TransferRequest,
                                    policy: ReceiptPolicy) throws -> Resolution? {
        try synchronized {
            let identity = try Self.identity(request)
            guard receipt.operationID == identity.operationID, receipt.assetID == identity.assetID,
                  receipt.attempt == identity.attempt, receipt.assetSHA256 == identity.assetSHA256,
                  receipt.target == identity.target else { throw MacClipboardCoordinationError.identityMismatch }
            let resolution: Resolution
            if policy.allowsConsumption(receipt: receipt, asset: request.asset, mode: .production) {
                resolution = .consumed
            } else if policy.allowsRetry(receipt: receipt, asset: request.asset, mode: .production) {
                resolution = .retryPermitted
            } else { return nil }
            let index = try activeIndex(request)
            if records[index].phase == .resolved {
                // Adapter resolution may precede Core's receipt transaction. A
                // reopened queue can re-observe this SAME operation and commit
                // its receipt; a tombstone never grants new input or a snapshot.
                guard records[index].resolution == resolution else {
                    throw MacClipboardCoordinationError.invalidTransition
                }
                return resolution
            }
            // Only an actual durable input intent can be resolved by a remote
            // receipt. A write-only operation cannot borrow an attachment's proof.
            try mutateLocked(request, allowed: [.inputIntent]) {
                $0.phase = .resolved; $0.resolution = resolution
            }
            return resolution
        }
    }

    public func finishSettlement(_ request: TransferRequest) throws {
        try synchronized {
            let index = try activeIndex(request)
            guard records[index].phase == .resolved else { throw MacClipboardCoordinationError.invalidTransition }
            activeID = nil; unlock()
        }
    }

    private func update(_ request: TransferRequest, allowed: Set<Phase>,
                        mutation: (inout Record) throws -> Void) throws {
        try synchronized { try mutateLocked(request, allowed: allowed, mutation: mutation) }
    }

    private func mutateLocked(_ request: TransferRequest, allowed: Set<Phase>,
                              mutation: (inout Record) throws -> Void) throws {
        let index = try activeIndex(request)
        guard allowed.contains(records[index].phase) else { throw MacClipboardCoordinationError.invalidTransition }
        var next = records; try mutation(&next[index]); try persist(next)
    }

    private func activeIndex(_ request: TransferRequest) throws -> Int {
        let identity = try Self.identity(request)
        guard ownsLock, activeID == identity.operationID,
              let index = records.firstIndex(where: { $0.identity == identity }) else {
            throw MacClipboardCoordinationError.identityMismatch
        }
        return index
    }

    private func synchronized<T>(_ body: () throws -> T) throws -> T {
        mutex.lock(); defer { mutex.unlock() }
        guard !poisoned else { throw MacClipboardCoordinationError.poisoned }
        return try body()
    }

    private func acquireAndRead() throws {
        guard !ownsLock else { return }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw MacClipboardCoordinationError.busy }
            throw MacClipboardCoordinationError.storageFailure(errno)
        }
        ownsLock = true
        do { records = try readJournal() }
        catch { unlock(); throw error }
    }

    private func unlock() {
        if ownsLock { _ = flock(lockFD, LOCK_UN); ownsLock = false }
    }

    private static func identity(_ request: TransferRequest) throws -> ObservationIdentity {
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        guard request.operation.assetID == request.asset.id, request.asset.origin == .synthetic,
              request.operation.phase.isUnresolved, request.operation.phase != .prepared,
              [.macChat, .macWork, .macClassic].contains(identity.target.surface), identity.target.tabID == nil else {
            throw MacClipboardCoordinationError.identityMismatch
        }
        try validateIdentity(identity)
        return identity
    }

    private static func validateIdentity(_ identity: ObservationIdentity) throws {
        try ObservationDecoder.validate(.init(provenance: .init(source: .integratedDevelopment,
            evidenceID: "mac-native-journal-v1"), observation: .init(identity: identity, state: .unknown)))
    }

    private static func validOwner(_ owner: ClipboardOwnerState, operationID: UUID) -> Bool {
        guard owner.changeCount >= 0, let marker = owner.marker else { return false }
        let prefix = operationID.uuidString + ":"
        return marker.hasPrefix(prefix) && UUID(uuidString: String(marker.dropFirst(prefix.count))) != nil
    }

    private static func safeRegularFile(_ fd: Int32) -> Bool {
        var info = stat()
        return fstat(fd, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
            && info.st_uid == geteuid() && info.st_nlink == 1 && info.st_mode & 0o077 == 0
    }

    private func readJournal() throws -> [Record] {
        let fd = openat(directoryFD, "journal.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return [] }
            throw MacClipboardCoordinationError.storageFailure(errno)
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Self.safeRegularFile(fd), fstat(fd, &info) == 0, info.st_size > 0,
              info.st_size <= Self.maximumJournalBytes else { throw MacClipboardCoordinationError.invalidJournal }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw MacClipboardCoordinationError.storageFailure(errno)
            }
            guard count <= Self.maximumJournalBytes - data.count else { throw MacClipboardCoordinationError.invalidJournal }
            data.append(contentsOf: buffer.prefix(count))
        }
        do {
            let journal = try JSONDecoder().decode(Journal.self, from: data)
            guard journal.version == 1, journal.records.count <= maximumEntries,
                  Set(journal.records.map { $0.identity.operationID }).count == journal.records.count,
                  journal.records.filter({ $0.phase.unresolved }).count <= 1 else {
                throw MacClipboardCoordinationError.invalidJournal
            }
            for record in journal.records {
                try Self.validateIdentity(record.identity)
                guard [.macChat, .macWork, .macClassic].contains(record.identity.target.surface),
                      record.identity.target.tabID == nil,
                      (record.phase == .resolved) == (record.resolution != nil) else {
                    throw MacClipboardCoordinationError.invalidJournal
                }
                if [.clipboardOwned, .inputIntent, .resolved].contains(record.phase) {
                    guard let owner = record.owner, Self.validOwner(owner, operationID: record.identity.operationID) else {
                        throw MacClipboardCoordinationError.invalidJournal
                    }
                } else if record.owner != nil { throw MacClipboardCoordinationError.invalidJournal }
            }
            return journal.records
        } catch { throw MacClipboardCoordinationError.invalidJournal }
    }

    private func persist(_ next: [Record]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Journal(version: 1, records: next))
        guard data.count <= Self.maximumJournalBytes else { throw MacClipboardCoordinationError.journalFull }
        let name = ".journal-\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { poisoned = true; throw MacClipboardCoordinationError.storageFailure(errno) }
        defer { Darwin.close(fd); _ = unlinkat(directoryFD, name, 0) }
        do {
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw MacClipboardCoordinationError.storageFailure(errno) }
                    offset += written
                }
            }
            guard fsync(fd) == 0 else { throw MacClipboardCoordinationError.storageFailure(errno) }
            try fault?(.temporaryFileSynced)
            guard renameat(directoryFD, name, directoryFD, "journal.json") == 0 else {
                throw MacClipboardCoordinationError.storageFailure(errno)
            }
            try fault?(.journalRenamed)
            guard fsync(directoryFD) == 0 else { throw MacClipboardCoordinationError.storageFailure(errno) }
            try fault?(.directorySynced)
            records = next
        } catch {
            // A rename might have succeeded even when a subsequent step failed.
            // Hold exclusion until destruction/restart and never guess the phase.
            poisoned = true; throw error
        }
    }
}

