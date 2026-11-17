import Foundation
import ImageIO
import RiftletCore

public struct MediaCleanupItem: Sendable {
    public let record: AssetRecord
    public let verifiedOriginal: Bool
}

public struct MediaRetention: Codable, Sendable {
    public let days: Int
    public let since: Date?
}

extension PrivateAssetImporter {
    private func isManagedName(_ record: AssetRecord) -> Bool {
        let name = record.image.fileName
        return name.hasPrefix(record.id.uuidString.lowercased() + ".")
            && !name.contains("/") && !name.contains("\\") && !name.utf8.contains(0)
    }

    private var retentionKey: String { "media-retention-v1" }

    public func initializeRetention(newProfile: Bool) async throws {
        let initial = MediaRetention(days: newProfile ? 30 : 0, since: nil)
        _ = try await store.saveCheckpointIfAbsent(JSONEncoder().encode(initial), for: retentionKey)
    }

    public func retention() async throws -> MediaRetention {
        guard let bytes = try await store.checkpoint(for: retentionKey) else { return MediaRetention(days: 0, since: nil) }
        let rule = try JSONDecoder().decode(MediaRetention.self, from: bytes)
        guard [0, 30, 90].contains(rule.days) else { throw CaptureError.invalidManifest }
        return rule
    }

    public func setRetention(days: Int, includeExisting: Bool) async throws {
        guard !mediaMaintenanceActive, [0, 30, 90].contains(days) else { throw RiftletError.invalidTransition }
        let rule = MediaRetention(days: days, since: includeExisting ? nil : Date())
        try await store.saveCheckpoint(JSONEncoder().encode(rule), for: retentionKey)
    }

    private func hasVerifiedOriginal(_ image: ImportedAsset) -> Bool {
        guard image.origin == .systemScreenshot else { return false }
        let journal = privateRoot.appendingPathComponent("journal").appendingPathComponent(image.id.uuidString.lowercased() + ".json")
        guard let signature = try? FileSignature.read(at: journal), signature.size <= 32_768,
              let bytes = try? Data(contentsOf: journal),
              let manifest = try? JSONDecoder().decode(ImportManifest.self, from: bytes),
              manifest.version == 1, manifest.image == image, let url = manifest.externalSource, url.isFileURL,
              let original = try? FileSignature.read(at: url), original.sourceKey == image.sourceKey,
              original.size == image.byteCount, (try? PrivateFiles.hashFile(url)) == image.sha256,
              (try? FileSignature.read(at: url)) == original else { return false }
        return true
    }

    public func cleanupItems(rule: MediaRetention? = nil, now: Date = Date()) async throws -> [MediaCleanupItem] {
        if let rule, rule.days == 0 { return [] }
        var items = [MediaCleanupItem]()
        let cutoff = rule.map { now.addingTimeInterval(-Double($0.days) * 86_400) }
        for record in try await store.cleanableMedia(before: cutoff) {
            await Task.yield()
            try Task.checkCancellation()
            if let rule, record.image.importedAt < (rule.since ?? .distantPast) { continue }
            guard isManagedName(record) else { continue }
            let url = mediaDirectory.appendingPathComponent(record.image.fileName)
            guard (try? FileSignature.read(at: url).size) == record.image.byteCount,
                  (try? PrivateFiles.hashFile(url)) == record.image.sha256 else { continue }
            let verified = hasVerifiedOriginal(record.image)
            if rule == nil || verified { items.append(MediaCleanupItem(record: record, verifiedOriginal: verified)) }
        }
        return items
    }

    /// Deterministic Trash names make a crash after rename recoverable without a second
    /// copy. The SQLite retirement is committed before the original directory entry moves.
    func cleanup(_ items: [MediaCleanupItem], trash: URL, automatic: Bool) async throws {
        guard !mediaMaintenanceActive else { throw RiftletError.invalidTransition }
        mediaMaintenanceActive = true
        defer { mediaMaintenanceActive = false }
        try PrivateFiles.ensurePrivateDirectory(mediaDirectory)
        let current = automatic ? try await retention() : nil
        var skipped = false
        let batch = UUID()
        for item in items {
            try Task.checkCancellation()
            let record = item.record
            guard isManagedName(record) else { throw CaptureError.invalidManifest }
            if let current, current.days == 0 || record.image.importedAt < (current.since ?? .distantPast)
                || record.lastInteractionAt > Date().addingTimeInterval(-Double(current.days) * 86_400) { continue }
            let media = mediaDirectory.appendingPathComponent(record.image.fileName)
            guard (try? PrivateFiles.hashFile(media)) == record.image.sha256 else { skipped = true; continue }
            if automatic || item.verifiedOriginal {
                guard hasVerifiedOriginal(record.image) else { skipped = true; continue }
            }
            do { try await store.retireMedia(record.id, revision: record.visibilityRevision, batch: batch) }
            catch RiftletError.invalidTransition { skipped = true; continue }
            do { try PrivateFiles.promote(media, to: trashURL(for: record, directory: trash)) }
            catch {
                if FileManager.default.fileExists(atPath: media.path) { try await store.reinstateMedia(record.id) }
                throw error
            }
        }
        if skipped && !automatic { throw CaptureError.unstableFile }
    }

    private func trashURL(for record: AssetRecord, directory: URL) -> URL {
        directory.appendingPathComponent("Riftlet-" + record.image.fileName)
    }

    private func trashDirectory() throws -> URL {
        try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: mediaDirectory, create: true)
    }

    public func cleanup(_ items: [MediaCleanupItem], automatic: Bool = false) async throws {
        guard !items.isEmpty else { return }
        try await cleanup(items, trash: trashDirectory(), automatic: automatic)
    }

    public func trashSummary() async throws -> (recoverable: Int, damaged: Int) {
        let records = try await store.retiredMedia()
        guard !records.isEmpty else { return (0, 0) }
        let trash = try trashDirectory()
        return try trashSummary(records, directory: trash)
    }

    func trashSummary(_ records: [AssetRecord], directory: URL) throws -> (recoverable: Int, damaged: Int) {
        var count = 0, damaged = 0
        for record in records where isManagedName(record) {
            let trash = trashURL(for: record, directory: directory)
            do {
                let media = mediaDirectory.appendingPathComponent(record.image.fileName)
                if try PrivateFiles.hashFile(trash) == record.image.sha256,
                   !FileManager.default.fileExists(atPath: media.path) || (try? PrivateFiles.hashFile(media)) == record.image.sha256 { count += 1 }
                else { damaged += 1 }
            } catch CaptureError.io(_, ENOENT) { continue }
        }
        return (count, damaged)
    }

    public func restoreTrash() async throws { try await restoreTrash(from: trashDirectory()) }

    func restoreTrash(from directory: URL) async throws {
        guard !mediaMaintenanceActive else { throw RiftletError.invalidTransition }
        mediaMaintenanceActive = true
        defer { mediaMaintenanceActive = false }
        try PrivateFiles.ensurePrivateDirectory(mediaDirectory)
        var failed = false
        for record in try await store.retiredMedia() where isManagedName(record) {
            let media = mediaDirectory.appendingPathComponent(record.image.fileName)
            let trash = trashURL(for: record, directory: directory)
            if !FileManager.default.fileExists(atPath: media.path) {
                do {
                    guard try PrivateFiles.hashFile(trash) == record.image.sha256 else { failed = true; continue }
                } catch CaptureError.io(_, ENOENT) { continue }
                catch { failed = true; continue }
                try PrivateFiles.promote(trash, to: media)
            }
            if (try? PrivateFiles.hashFile(media)) == record.image.sha256 { try await store.reinstateMedia(record.id, restoredByUserAt: Date()) }
            else { failed = true }
        }
        if failed { throw CaptureError.invalidManifest }
    }

    public func reconcileInterruptedMoves() async throws {
        guard !mediaMaintenanceActive else { throw RiftletError.invalidTransition }
        mediaMaintenanceActive = true
        defer { mediaMaintenanceActive = false }
        try PrivateFiles.ensurePrivateDirectory(mediaDirectory)
        for record in try await store.retiredMedia() where isManagedName(record) {
            let media = mediaDirectory.appendingPathComponent(record.image.fileName)
            if (try? PrivateFiles.hashFile(media)) == record.image.sha256 { try await store.reinstateMedia(record.id) }
        }
    }
}

extension PrivateAssetImporter {
    private func truncatedPNG(_ url: URL, length: Int64) throws -> Bool {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.read(upToCount: 8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) else { return false }
        var offset: Int64 = 8
        while offset < length {
            try file.seek(toOffset: UInt64(offset))
            guard let header = try file.read(upToCount: 8), header.count == 8 else { return true }
            let bytes = header.prefix(4).reduce(Int64(0)) { $0 * 256 + Int64($1) }
            guard bytes <= Int64(Int32.max) else { return false }
            let type = String(decoding: header.suffix(4), as: UTF8.self)
            if offset == 8 && (type != "IHDR" || bytes != 13) { return false }
            offset += bytes + 12
            if offset > length { return true }
            if type == "IEND" { return false }
        }
        return true
    }

    /// Called once the profile's exclusive instance lock is held, before starting
    /// a new interactive capture. A complete, unjournaled image is never garbage.
    public func cleanAbandonedStaging() throws {
        let fm = FileManager.default
        let stage = privateRoot.appendingPathComponent("staging")
        try PrivateFiles.ensurePrivateDirectory(stage)
        let journals = privateRoot.appendingPathComponent("journal")
        for url in try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            let stem = url.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: stem) != nil, url.pathExtension == "part",
                  !fm.fileExists(atPath: journals.appendingPathComponent(stem + ".json").path),
                  let sig = try? FileSignature.read(at: url) else { continue }
            if sig.size > 0 {
                // Only an explicitly identified truncated image is disposable.
                // Complete files, foreign formats and undecidable bytes stay intact.
                guard sig.size <= ValidatedImage.maximumBytes,
                      let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      CGImageSourceGetType(source) != nil,
                      try [.statusUnexpectedEOF, .statusIncomplete].contains(CGImageSourceGetStatus(source))
                          || truncatedPNG(url, length: sig.size) else { continue }
            }
            guard try FileSignature.read(at: url) == sig else { continue }
            try fm.removeItem(at: url)
        }
        let captures = privateRoot.appendingPathComponent("captures")
        try PrivateFiles.ensurePrivateDirectory(captures)
        for dir in try fm.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil) {
            let name = dir.lastPathComponent
            guard !ActiveCaptureStages.contains(name), name.hasPrefix(".capture-"), let stageID = UUID(uuidString: String(name.dropFirst(9))),
                  (try dir.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { continue }
            try recoverAbandonedCapture(in: dir, captures: captures, stageID: stageID)
            // rmdir fails closed if another entry appeared.
            _ = rmdir(dir.path)
        }
    }
    private func recoverAbandonedCapture(in stage: URL, captures: URL, stageID: UUID) throws {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        let rootFD = Darwin.open(captures.path, flags)
        guard rootFD >= 0 else { throw CaptureError.io("inspect-captures", errno) }
        defer { Darwin.close(rootFD) }
        let stageFD = openat(rootFD, stage.lastPathComponent, flags)
        guard stageFD >= 0 else { throw CaptureError.io("inspect-capture-stage", errno) }
        defer { Darwin.close(stageFD) }

        func signature(at name: String, in directory: Int32) throws -> FileSignature {
            let fd = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw CaptureError.io("inspect-capture-file", errno) }
            defer { Darwin.close(fd) }
            return try FileSignature.read(descriptor: fd)
        }

        var info = stat()
        guard fstat(stageFD, &info) == 0, info.st_uid == geteuid() else { throw CaptureError.privatePathUnsafe }
        for file in try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            let name = file.lastPathComponent
            guard file.pathExtension == "png", let requestID = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let sig = try? signature(at: name, in: stageFD), (try? FileSignature.read(at: file)) == sig else { continue }
            if sig.size == 0 {
                // After an abrupt application exit the old system tool can briefly
                // outlive its parent. Leave recent empty reservations for the next pass.
                guard Date().timeIntervalSince1970 - Double(sig.modificationSeconds) > 60 else { continue }
                if unlinkat(stageFD, name, 0) != 0 { throw CaptureError.io("retire-empty-reservation", errno) }
                continue
            }
            guard sig.size <= ValidatedImage.maximumBytes,
                  (try? ValidatedImage.inspect(file, byteCount: sig.size).mimeType) == "image/png",
                  try !truncatedPNG(file, length: sig.size), try FileSignature.read(at: file) == sig,
                  try signature(at: name, in: stageFD) == sig else { continue }
            var destination = InteractiveScreenshotOutput.originalURL(in: captures, captureID: requestID).lastPathComponent
            if let published = try? signature(at: destination, in: rootFD) {
                if published == sig {
                    guard fsync(rootFD) == 0, unlinkat(stageFD, name, 0) == 0 else { throw CaptureError.io("retire-published-link", errno) }
                    continue
                }
                destination = InteractiveScreenshotOutput.originalURL(in: captures, captureID: stageID).lastPathComponent
            }
            guard renameatx_np(stageFD, name, rootFD, destination, UInt32(RENAME_EXCL)) == 0,
                  fsync(rootFD) == 0, fsync(stageFD) == 0 else { throw CaptureError.io("recover-capture-stage", errno) }
        }
    }

}
