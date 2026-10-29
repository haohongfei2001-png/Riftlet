import Foundation
import CryptoKit
import Darwin
import RiftletCore

public struct CaptureRecoveryReport: Sendable {
    public var adopted: Int = 0
    public var missing: [UUID] = []
    public var invalid: [UUID] = []
}

private struct ImportManifest: Codable {
    let version: Int
    let image: ImportedAsset
}

/// Internal deterministic fault seams. Production construction leaves the hook nil.
/// Tests reopen real files/SQLite after an interruption; this does not simulate power loss.
enum ImportBoundary: CaseIterable, Hashable, Sendable {
    case stageOpened, stageSynced, journalRenamed, journalSynced
    case mediaRenamed, mediaSynced, databaseCommitted
}

struct ImportBoundaryContext: Sendable {
    let boundary: ImportBoundary
    let stageURL: URL
    let journalURL: URL?
    let mediaURL: URL?
}

struct SimulatedImportInterruption: Error, Equatable {
    let boundary: ImportBoundary
}

typealias ImportFaultHook = @Sendable (ImportBoundaryContext) throws -> Void

struct AssetImportTiming: Sendable {
    let validatedCopyUptime: TimeInterval
    let durableCommitUptime: TimeInterval
}

struct ObservedAssetImport: Sendable {
    let record: AssetRecord
    /// Existing and journal-recovered assets never acquire fresh source times.
    let timing: AssetImportTiming?
}

/// Files and metadata use a recoverable ordering, not a fictitious cross-filesystem/SQL transaction.
/// Durable staging -> durable manifest -> atomic media rename -> SQLite insert.
/// The original screenshot is never moved, modified or deleted.
public actor PrivateAssetImporter {
    private let store: QueueStore
    public let privateRoot: URL
    public let mediaDirectory: URL
    private let stagingDirectory: URL
    private let journalDirectory: URL
    private var importing = Set<String>()
    private var journaledSources = Set<String>()
    private let fault: ImportFaultHook?
    private let capacityCheck: ImportCapacityCheck

    public init(privateRoot: URL, store: QueueStore) {
        self.privateRoot = privateRoot.standardizedFileURL
        self.store = store
        mediaDirectory = privateRoot.appendingPathComponent("media", isDirectory: true)
        stagingDirectory = privateRoot.appendingPathComponent("staging", isDirectory: true)
        journalDirectory = privateRoot.appendingPathComponent("journal", isDirectory: true)
        fault = nil
        capacityCheck = { try PrivateStorageCapacity.check(directory: $0, copyBytes: $1) }
    }

    init(privateRoot: URL, store: QueueStore, fault: @escaping ImportFaultHook) {
        self.privateRoot = privateRoot.standardizedFileURL
        self.store = store
        mediaDirectory = privateRoot.appendingPathComponent("media", isDirectory: true)
        stagingDirectory = privateRoot.appendingPathComponent("staging", isDirectory: true)
        journalDirectory = privateRoot.appendingPathComponent("journal", isDirectory: true)
        self.fault = fault
        capacityCheck = { try PrivateStorageCapacity.check(directory: $0, copyBytes: $1) }
    }

    /// Internal capacity seam: tests can model quota exhaustion without filling a disk.
    init(privateRoot: URL, store: QueueStore, capacityCheck: @escaping ImportCapacityCheck) {
        self.privateRoot = privateRoot.standardizedFileURL
        self.store = store
        mediaDirectory = privateRoot.appendingPathComponent("media", isDirectory: true)
        stagingDirectory = privateRoot.appendingPathComponent("staging", isDirectory: true)
        journalDirectory = privateRoot.appendingPathComponent("journal", isDirectory: true)
        fault = nil
        self.capacityCheck = capacityCheck
    }

    /// Convenience entry point for an explicit candidate. The directory collector instead
    /// shares one stability window across all candidates, so bursts do not wait N × 120 ms.
    @discardableResult
    public func importFile(at url: URL, origin: AssetOrigin = .systemScreenshot,
                           firstSeenAt: Date = Date()) async throws -> AssetRecord {
        let signature = try FileSignature.read(at: url)
        try await Task.sleep(nanoseconds: 120_000_000)
        try Task.checkCancellation()
        guard signature == (try FileSignature.read(at: url)) else { throw CaptureError.unstableFile }
        return try await importStableFile(at: url, signature: signature, origin: origin, firstSeenAt: firstSeenAt)
    }

    @discardableResult
    func importStableFile(at url: URL, signature: FileSignature,
                          origin: AssetOrigin = .systemScreenshot,
                          firstSeenAt: Date) async throws -> AssetRecord {
        let result = try await importStableFileWithTiming(at: url, signature: signature,
            origin: origin, firstSeenAt: firstSeenAt, recordTiming: false)
        return result.record
    }

    /// Same import path with optional ephemeral observations. The default callers
    /// avoid clock sampling; timing cannot affect file, journal or SQL decisions.
    func importStableFileWithTiming(at url: URL, signature: FileSignature,
                                   origin: AssetOrigin = .systemScreenshot,
                                   firstSeenAt: Date, recordTiming: Bool) async throws -> ObservedAssetImport {
        guard await store.mode != .simulation || origin == .synthetic else { throw RiftletError.modeMismatch }
        guard !importing.contains(signature.sourceKey) else { throw CaptureError.importInProgress }
        importing.insert(signature.sourceKey)
        defer { importing.remove(signature.sourceKey) }
        if let existing = try await store.asset(sourceKey: signature.sourceKey) {
            journaledSources.remove(signature.sourceKey)
            return ObservedAssetImport(record: existing, timing: nil)
        }
        // An earlier IO/SQL failure may already own a durable private copy. Reconcile it
        // before allocating another UUID/file for the same source event.
        if journaledSources.contains(signature.sourceKey) {
            _ = try await recover()
            if let existing = try await store.asset(sourceKey: signature.sourceKey) {
                journaledSources.remove(signature.sourceKey)
                return ObservedAssetImport(record: existing, timing: nil)
            }
        }
        try ensureDirectories()
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CaptureError.io("open-source", errno) }
        defer { Darwin.close(descriptor) }
        guard try FileSignature.read(descriptor: descriptor) == signature else { throw CaptureError.unstableFile }
        if origin == .systemScreenshot, try !CaptureSource.isScreenshot(descriptor: descriptor) {
            throw CaptureError.notScreenshot
        }
        guard signature.size > 0, signature.size <= ValidatedImage.maximumBytes else { throw CaptureError.imageTooLarge }
        try capacityCheck(stagingDirectory, signature.size)

        let id = UUID()
        let stageURL = stagingDirectory.appendingPathComponent(id.uuidString.lowercased() + ".part")
        var hasManifest = false
        var simulatedAbruptExit = false
        defer {
            // Only an uncommitted file made by this attempt, inside the private staging directory.
            // Once the durable manifest exists, recovery owns it even if DB/promote fails.
            if !hasManifest && !simulatedAbruptExit { try? FileManager.default.removeItem(at: stageURL) }
        }
        do {
            let hook = fault
            let copyProbe: ((ImportBoundary) throws -> Void)? = hook.map { callback in
                { boundary in try callback(ImportBoundaryContext(boundary: boundary, stageURL: stageURL,
                                                                 journalURL: nil, mediaURL: nil)) }
            }
            let hash = try PrivateFiles.copyAndHash(sourceDescriptor: descriptor, destination: stageURL,
                                                    maximumBytes: ValidatedImage.maximumBytes, probe: copyProbe)
            guard try FileSignature.read(descriptor: descriptor) == signature,
                  try FileSignature.read(at: url) == signature else { throw CaptureError.unstableFile }
            if origin == .systemScreenshot, try !CaptureSource.isScreenshot(descriptor: descriptor) {
                throw CaptureError.notScreenshot
            }
            let result = try ValidatedImage.inspect(stageURL, byteCount: signature.size)
            let validatedCopyUptime = recordTiming ? ProcessInfo.processInfo.systemUptime : nil
            let fileName = id.uuidString.lowercased() + "." + result.fileExtension
            let image = ImportedAsset(id: id, sourceKey: signature.sourceKey, fileName: fileName,
                                      sha256: hash, byteCount: signature.size, pixelWidth: result.width,
                                      pixelHeight: result.height, mediaType: result.mimeType,
                                      capturedAt: nil, firstSeenAt: firstSeenAt, origin: origin)
            // File birthtime is useful for scan order, but is not mislabeled as capture time.
            let manifest = ImportManifest(version: 1, image: image)
            let manifestURL = journalDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json")
            let mediaURL = mediaDirectory.appendingPathComponent(fileName)
            let commitProbe: ((ImportBoundary) throws -> Void)? = hook.map { callback in
                { boundary in try callback(ImportBoundaryContext(boundary: boundary, stageURL: stageURL,
                                                                 journalURL: manifestURL, mediaURL: mediaURL)) }
            }
            try PrivateFiles.atomicPrivateWrite(try JSONEncoder().encode(manifest), to: manifestURL,
                didRename: { hasManifest = true }, probe: commitProbe)
            journaledSources.insert(signature.sourceKey)
            try PrivateFiles.promote(stageURL, to: mediaURL, probe: commitProbe)
            let record = try await store.importAsset(image)
            // QueueStore can also deduplicate at transaction time. Another
            // importer winning that race must not inherit this copy's timeline.
            let timing = record.image == image ? validatedCopyUptime.map {
                AssetImportTiming(validatedCopyUptime: $0,
                                  durableCommitUptime: ProcessInfo.processInfo.systemUptime)
            } : nil
            journaledSources.remove(signature.sourceKey)
            try commitProbe?(.databaseCommitted)
            return ObservedAssetImport(record: record, timing: timing)
        } catch {
            // A renamed journal owns staging even if its directory fsync subsequently fails.
            // Deleting that stage would break recovery from an otherwise valid journal.
            if hasManifest { journaledSources.insert(signature.sourceKey) }
            if error is SimulatedImportInterruption { simulatedAbruptExit = true }
            throw error
        }
    }

    /// Adopt only journaled, identity-checked private copies. Unjournaled staging fragments
    /// are left inert; directory listing alone is never treated as proof of a complete import.
    @discardableResult
    public func recover() async throws -> CaptureRecoveryReport {
        try ensureDirectories()
        var report = CaptureRecoveryReport()
        let manifests = try FileManager.default.contentsOfDirectory(at: journalDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        for url in manifests where url.pathExtension == "json" {
            var parsedID: UUID?
            do {
                let attrs = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard attrs.isRegularFile == true, attrs.isSymbolicLink != true,
                      (attrs.fileSize ?? 0) <= 32_768 else { throw CaptureError.invalidManifest }
                let manifest = try JSONDecoder().decode(ImportManifest.self, from: Data(contentsOf: url))
                let asset = manifest.image
                parsedID = asset.id
                guard manifest.version == 1, Self.isValidBasename(asset.fileName),
                      url.deletingPathExtension().lastPathComponent.lowercased() == asset.id.uuidString.lowercased(),
                      asset.fileName.hasPrefix(asset.id.uuidString.lowercased() + ".") else {
                    throw CaptureError.invalidManifest
                }
                let mediaURL = mediaDirectory.appendingPathComponent(asset.fileName)
                let stageURL = stagingDirectory.appendingPathComponent(asset.id.uuidString.lowercased() + ".part")
                let candidate = FileManager.default.fileExists(atPath: mediaURL.path) ? mediaURL : stageURL
                guard FileManager.default.fileExists(atPath: candidate.path) else {
                    report.missing.append(asset.id); continue
                }
                let existing = try await store.asset(id: asset.id)
                if let existing, candidate == mediaURL {
                    guard existing.image == asset else { throw CaptureError.invalidManifest }
                    let current = try PrivateFiles.privateSignature(at: candidate)
                    guard current.size == asset.byteCount else { throw CaptureError.invalidManifest }
                    // Active copies get byte-integrity validation after restart; already-used
                    // history needs no decode work and is never automatically deleted.
                    if existing.status == .used { continue }
                    guard try PrivateFiles.hashFile(candidate) == asset.sha256 else { throw CaptureError.invalidManifest }
                    _ = try ValidatedImage.inspect(candidate, byteCount: current.size)
                    if existing.status == .missing { try await store.restoreMissingAsset(asset.id) }
                    continue
                }
                let signature = try PrivateFiles.privateSignature(at: candidate)
                guard signature.size == asset.byteCount,
                      try PrivateFiles.hashFile(candidate) == asset.sha256 else { throw CaptureError.invalidManifest }
                let image = try ValidatedImage.inspect(candidate, byteCount: signature.size)
                guard image.width == asset.pixelWidth, image.height == asset.pixelHeight,
                      image.mimeType == asset.mediaType else { throw CaptureError.invalidManifest }
                if candidate == stageURL {
                    let probe: ((ImportBoundary) throws -> Void)? = fault.map { callback in
                        { boundary in try callback(ImportBoundaryContext(boundary: boundary, stageURL: stageURL,
                                                                         journalURL: url, mediaURL: mediaURL)) }
                    }
                    try PrivateFiles.promote(stageURL, to: mediaURL, probe: probe)
                }
                _ = try await store.importAsset(asset)
                report.adopted += 1
            } catch let error as RiftletError {
                // Database/disk failures must be visible to the caller, not mislabeled as
                // an invalid image and silently skipped.
                throw error
            } catch {
                // A valid journal still owns its copy when storage is temporarily
                // unavailable. Do not turn IO failure into "invalid" and let a caller
                // allocate another private identity on every collection retry.
                if let capture = error as? CaptureError, case .io = capture { throw capture }
                let native = error as NSError
                if !(error is DecodingError),
                   native.domain == NSCocoaErrorDomain || native.domain == NSPOSIXErrorDomain { throw error }
                // One damaged journal entry cannot prevent unrelated valid captures recovering.
                if let id = parsedID ?? UUID(uuidString: url.deletingPathExtension().lastPathComponent) {
                    report.invalid.append(id)
                    if let existing = try await store.asset(id: id), existing.status != .used {
                        try await store.markMissingAsset(id)
                    }
                }
            }
        }
        for record in try await store.assets(includeUsed: true) {
            guard Self.isValidBasename(record.image.fileName) else { continue }
            let file = mediaDirectory.appendingPathComponent(record.image.fileName)
            if !FileManager.default.fileExists(atPath: file.path) {
                if record.status != .used { try await store.markMissingAsset(record.id) }
                if !report.missing.contains(record.id) { report.missing.append(record.id) }
            }
        }
        return report
    }

    private func ensureDirectories() throws {
        for directory in [privateRoot, mediaDirectory, stagingDirectory, journalDirectory] {
            try PrivateFiles.ensurePrivateDirectory(directory)
        }
    }

    private static func isValidBasename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }
}

enum PrivateFiles {
    static func privateSignature(at url: URL) throws -> FileSignature {
        do { return try FileSignature.read(at: url) }
        catch CaptureError.io(_, let code) { throw CaptureError.io("inspect-private-copy", code) }
    }

    static func privateSignature(descriptor: Int32) throws -> FileSignature {
        do { return try FileSignature.read(descriptor: descriptor) }
        catch CaptureError.io(_, let code) { throw CaptureError.io("stat-private-copy", code) }
    }

    static func ensurePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == getuid() else { throw CaptureError.privatePathUnsafe }
        guard chmod(url.path, 0o700) == 0 else { throw CaptureError.io("private-directory-permissions", errno) }
    }

    static func copyAndHash(sourceDescriptor: Int32, destination: URL, maximumBytes: Int64,
                            probe: ((ImportBoundary) throws -> Void)? = nil) throws -> String {
        let target = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard target >= 0 else { throw CaptureError.io("create-private-copy", errno) }
        defer { Darwin.close(target) }
        try probe?(.stageOpened)
        var hash = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total: Int64 = 0
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(sourceDescriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw CaptureError.io("read-source", errno)
            }
            if count == 0 { break }
            total += Int64(count)
            guard total <= maximumBytes else { throw CaptureError.imageTooLarge }
            let chunk = Data(buffer.prefix(count))
            hash.update(data: chunk)
            try writeAll(chunk, descriptor: target)
        }
        guard fsync(target) == 0 else { throw CaptureError.io("sync-private-copy", errno) }
        // The manifest must not become durable before the stage's directory entry.
        // Syncing only the file data does not establish that ordering for its new name.
        try syncDirectory(destination.deletingLastPathComponent())
        try probe?(.stageSynced)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hashFile(_ url: URL) throws -> String {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CaptureError.io("open-private-copy", errno) }
        defer { Darwin.close(descriptor) }
        let initial = try privateSignature(descriptor: descriptor)
        guard initial.size <= ValidatedImage.maximumBytes else {
            throw CaptureError.imageTooLarge
        }
        var hash = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total: Int64 = 0
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw CaptureError.io("hash-private-copy", errno)
            }
            if count == 0 { break }
            total += Int64(count)
            guard total <= ValidatedImage.maximumBytes else { throw CaptureError.imageTooLarge }
            hash.update(data: Data(buffer.prefix(count)))
        }
        guard try privateSignature(descriptor: descriptor) == initial else { throw CaptureError.unstableFile }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func atomicPrivateWrite(_ data: Data, to destination: URL,
                                   didRename: () -> Void = {},
                                   probe: ((ImportBoundary) throws -> Void)? = nil) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CaptureError.io("create-import-journal", errno) }
        defer { Darwin.close(descriptor); try? FileManager.default.removeItem(at: temporary) }
        try writeAll(data, descriptor: descriptor)
        guard fsync(descriptor) == 0 else { throw CaptureError.io("sync-import-journal", errno) }
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw CaptureError.io("commit-import-journal", errno) }
        didRename()
        try probe?(.journalRenamed)
        try syncDirectory(destination.deletingLastPathComponent())
        try probe?(.journalSynced)
    }

    static func promote(_ source: URL, to destination: URL,
                        probe: ((ImportBoundary) throws -> Void)? = nil) throws {
        // EXCL prevents overwriting an unrelated (even same-named) private file.
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw CaptureError.io("promote-private-copy", errno)
        }
        try probe?(.mediaRenamed)
        try syncDirectory(destination.deletingLastPathComponent())
        try syncDirectory(source.deletingLastPathComponent())
        try probe?(.mediaSynced)
    }

    static func syncDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CaptureError.io("open-private-directory", errno) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw CaptureError.io("sync-private-directory", errno) }
    }

    static func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw CaptureError.io("write-private-data", errno)
                }
                guard count > 0 else { throw CaptureError.io("write-private-data", EIO) }
                offset += count
            }
        }
    }
}
