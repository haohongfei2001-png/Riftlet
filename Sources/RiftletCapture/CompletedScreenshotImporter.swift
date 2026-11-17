import Foundation
import RiftletCore

extension PrivateAssetImporter {
    /// Built-in capture is a distinct source even if the macOS encoder writes
    /// system-screenshot xattrs. Preserve that provenance through SQLite and
    /// leave upload admission to its own independently evidenced policy.
    /// Optional derivative IO runs on the existing importer actor, never AppKit.
    @discardableResult
    public func importBuiltInScreenshot(original: URL, editedPNG: Data? = nil,
                                        outputDirectory: URL,
                                        firstSeenAt: Date = Date()) async throws -> AssetRecord {
        let source = try editedPNG.map {
            try saveBuiltInMarkup($0, original: original, outputDirectory: outputDirectory)
        } ?? original
        let record = try await importCompletedScreenshot(at: source, origin: .applicationScreenshot,
                                                        firstSeenAt: firstSeenAt)
        // Existing source-key records are immutable provenance. Never return a
        // pre-existing system/synthetic record as successful built-in admission,
        // and never retag historical records or their operations to repair it.
        guard record.image.origin == .applicationScreenshot else { throw RiftletError.modeMismatch }
        return record
    }

    /// Persist a derivative once so a retry after an import error reuses its source identity.
    public func saveBuiltInMarkup(_ editedPNG: Data, original: URL, outputDirectory: URL) throws -> URL {
        guard !editedPNG.isEmpty, Int64(editedPNG.count) <= ValidatedImage.maximumBytes else {
            throw CaptureError.imageTooLarge
        }
        let expected = privateRoot.appendingPathComponent("captures", isDirectory: true).standardizedFileURL
        guard outputDirectory.standardizedFileURL == expected,
              original.deletingLastPathComponent().standardizedFileURL == expected else {
            throw CaptureError.privatePathUnsafe
        }
        try PrivateFiles.ensurePrivateDirectory(expected)
        // The system collector already ignores hidden directory entries.
        // Keep owned originals/derivatives out of that independent route even
        // if the user's system screenshot location overlaps this directory.
        let source = expected.appendingPathComponent("." + UUID().uuidString.lowercased() + "-edited.png")
        try PrivateFiles.atomicPrivateWrite(editedPNG, to: source)
        return source
    }

    /// The owning capture process has exited (or the editor has atomically
    /// finished this file). Skip the directory watcher's extra settling delay,
    /// retaining its descriptor/signature, format, capacity and durable-journal
    /// checks. No screenshot metadata is manufactured by this API.
    @discardableResult
    public func importCompletedScreenshot(at url: URL, origin: AssetOrigin,
                                           firstSeenAt: Date = Date()) async throws -> AssetRecord {
        guard origin != .synthetic else { throw RiftletError.modeMismatch }
        let signature = try FileSignature.read(at: url)
        return try await importStableFile(at: url, signature: signature,
                                         origin: origin, firstSeenAt: firstSeenAt)
    }
}

extension PrivateAssetImporter {
    private var ownedCaptures: URL { privateRoot.appendingPathComponent("captures", isDirectory: true) }

    private func captureID(_ source: URL) -> UUID? {
        let name = source.lastPathComponent
        guard source.deletingLastPathComponent().standardizedFileURL == ownedCaptures.standardizedFileURL,
              name.hasPrefix("."), name.hasSuffix(".png") else { return nil }
        let stem = String(name.dropFirst().dropLast(4))
        return UUID(uuidString: stem.hasSuffix("-edited") ? String(stem.dropLast(7)) : stem)
    }

    /// Called after the editor commits. The unmarked original stays paired with its
    /// derivative under the original request ID and is available from Manage.
    public func saveOwnedMarkup(_ data: Data, original: URL) throws -> URL {
        guard let id = captureID(original), !original.lastPathComponent.hasSuffix("-edited.png"),
              !data.isEmpty, Int64(data.count) <= ValidatedImage.maximumBytes else { throw CaptureError.invalidManifest }
        let edited = InteractiveScreenshotOutput.editedURL(in: ownedCaptures, id: id)
        try PrivateFiles.atomicPrivateWrite(data, to: edited)
        return edited
    }

    /// Only explicit host captures under the owned directory can retire their
    /// temporary names. Historical/generic importer callers keep their originals.
    public func collectOwnedCapture(_ source: URL) async throws -> AssetRecord {
        guard let id = captureID(source) else {
            return try await importBuiltInScreenshot(original: source, outputDirectory: ownedCaptures)
        }
        let signature = try FileSignature.read(at: source)
        let marker = "owned-capture-v1:" + signature.sourceKey
        _ = try await store.saveCheckpointIfAbsent(Data([1]), for: marker)
        let record = try await importBuiltInScreenshot(original: source, outputDirectory: ownedCaptures)
        guard record.image.sourceKey == signature.sourceKey,
              try FileSignature.read(at: source) == signature,
              try PrivateFiles.hashFile(mediaDirectory.appendingPathComponent(record.image.fileName)) == record.image.sha256
        else { throw CaptureError.unstableFile }
        if source.lastPathComponent.hasSuffix("-edited.png") {
            let original = InteractiveScreenshotOutput.originalURL(in: ownedCaptures, captureID: id)
            let basis = ownedCaptures.appendingPathComponent("." + record.id.uuidString.lowercased() + "-original.png")
            if FileManager.default.fileExists(atPath: original.path) {
                try PrivateFiles.promote(original, to: basis)
            }
        }
        guard try FileSignature.read(at: source) == signature else { throw CaptureError.unstableFile }
        try FileManager.default.removeItem(at: source)
        try PrivateFiles.syncDirectory(ownedCaptures)
        return record
    }

    /// Published UUID names survive a crash before the first import journal. A
    /// saved derivative supersedes its original as the pending selection. Older
    /// already-imported originals stay untouched and never create another row.
    public func pendingOwnedCaptures() async throws -> [URL] {
        try PrivateFiles.ensurePrivateDirectory(ownedCaptures)
        let files = try FileManager.default.contentsOfDirectory(at: ownedCaptures, includingPropertiesForKeys: nil)
        let edits = Set(files.filter { $0.lastPathComponent.hasSuffix("-edited.png") }.compactMap(captureID))
        var pending: [URL] = []
        for url in files {
            guard let id = captureID(url), url.lastPathComponent.hasSuffix("-edited.png") || !edits.contains(id),
                  let signature = try? FileSignature.read(at: url), signature.size > 0 else { continue }
            if try await store.asset(sourceKey: signature.sourceKey) == nil { pending.append(url) }
            else if try await store.checkpoint(for: "owned-capture-v1:" + signature.sourceKey) != nil { pending.append(url) }
        }
        return pending.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

extension PrivateAssetImporter {
    public func captureOriginals() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: ownedCaptures, includingPropertiesForKeys: nil).filter {
            (captureID($0) != nil || $0.lastPathComponent.hasSuffix("-original.png")) && (try? FileSignature.read(at: $0)) != nil
        }
    }
}
