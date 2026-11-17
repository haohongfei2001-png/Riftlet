import Foundation
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
    private var retentionKey: String { "media-retention-v1" }

    public func initializeRetention(newProfile: Bool) async throws {
        let initial = MediaRetention(days: newProfile ? 30 : 0, since: nil)
        _ = try await store.saveCheckpointIfAbsent(JSONEncoder().encode(initial), for: retentionKey)
    }

    public func retention() async throws -> MediaRetention {
        guard let bytes = try await store.checkpoint(for: retentionKey) else { return MediaRetention(days: 0, since: nil) }
        return try JSONDecoder().decode(MediaRetention.self, from: bytes)
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
        for record in try await store.cleanableMedia() {
            try Task.checkCancellation()
            if let rule, record.lastInteractionAt > now.addingTimeInterval(-Double(rule.days) * 86_400)
                || record.image.importedAt < (rule.since ?? .distantPast) { continue }
            let url = mediaDirectory.appendingPathComponent(record.image.fileName)
            guard (try? FileSignature.read(at: url).size) == record.image.byteCount else { continue }
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
        let current = automatic ? try await retention() : nil
        let batch = UUID()
        for item in items {
            try Task.checkCancellation()
            let record = item.record
            if let current, current.days == 0 || record.image.importedAt < (current.since ?? .distantPast)
                || record.lastInteractionAt > Date().addingTimeInterval(-Double(current.days) * 86_400) { continue }
            let media = mediaDirectory.appendingPathComponent(record.image.fileName)
            guard (try? PrivateFiles.hashFile(media)) == record.image.sha256 else { continue }
            if automatic || item.verifiedOriginal {
                guard hasVerifiedOriginal(record.image) else { continue }
            }
            do { try await store.retireMedia(record.id, revision: record.visibilityRevision, batch: batch) }
            catch RiftletError.invalidTransition { continue }
            do { try PrivateFiles.promote(media, to: trashURL(for: record, directory: trash)) }
            catch {
                if FileManager.default.fileExists(atPath: media.path) { try await store.reinstateMedia(record.id) }
                throw error
            }
        }
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

    public func recoverableTrashCount() async throws -> Int {
        let records = try await store.retiredMedia()
        guard !records.isEmpty else { return 0 }
        let trash = try trashDirectory()
        return records.filter { FileManager.default.fileExists(atPath: trashURL(for: $0, directory: trash).path) }.count
    }

    public func restoreTrash() async throws { try await restoreTrash(from: trashDirectory()) }

    func restoreTrash(from directory: URL) async throws {
        guard !mediaMaintenanceActive else { throw RiftletError.invalidTransition }
        mediaMaintenanceActive = true
        defer { mediaMaintenanceActive = false }
        for record in try await store.retiredMedia() {
            let media = mediaDirectory.appendingPathComponent(record.image.fileName)
            let trash = trashURL(for: record, directory: directory)
            if !FileManager.default.fileExists(atPath: media.path) {
                guard (try? PrivateFiles.hashFile(trash)) == record.image.sha256 else { continue }
                try PrivateFiles.promote(trash, to: media)
            }
            if (try? PrivateFiles.hashFile(media)) == record.image.sha256 { try await store.reinstateMedia(record.id) }
        }
    }

    public func reconcileInterruptedMoves() async throws {
        guard !mediaMaintenanceActive else { throw RiftletError.invalidTransition }
        mediaMaintenanceActive = true
        defer { mediaMaintenanceActive = false }
        for record in try await store.retiredMedia() {
            let media = mediaDirectory.appendingPathComponent(record.image.fileName)
            if (try? PrivateFiles.hashFile(media)) == record.image.sha256 { try await store.reinstateMedia(record.id) }
        }
    }
}

extension PrivateAssetImporter {
    /// Called once the profile's exclusive instance lock is held, before starting
    /// a new interactive capture. A complete, unjournaled image is never garbage.
    public func cleanEmptyReservations() throws {
        let fm = FileManager.default
        let stage = privateRoot.appendingPathComponent("staging")
        try PrivateFiles.ensurePrivateDirectory(stage)
        let journals = privateRoot.appendingPathComponent("journal")
        for url in try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            let stem = url.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: stem) != nil, url.pathExtension == "part",
                  !fm.fileExists(atPath: journals.appendingPathComponent(stem + ".json").path),
                  let sig = try? FileSignature.read(at: url), sig.size == 0 else { continue }
            try fm.removeItem(at: url)
        }
        let captures = privateRoot.appendingPathComponent("captures")
        try PrivateFiles.ensurePrivateDirectory(captures)
        for dir in try fm.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil) {
            let name = dir.lastPathComponent
            guard name.hasPrefix(".capture-"), UUID(uuidString: String(name.dropFirst(9))) != nil,
                  (try dir.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { continue }
            for file in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                guard file.pathExtension == "png", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                      let sig = try? FileSignature.read(at: file), sig.size == 0 else { continue }
                try fm.removeItem(at: file)
            }
            // rmdir fails closed if another entry appeared.
            _ = rmdir(dir.path)
        }
    }
}
