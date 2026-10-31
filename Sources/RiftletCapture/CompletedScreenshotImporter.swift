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
        let source: URL
        if let editedPNG {
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
            source = expected.appendingPathComponent("." + UUID().uuidString.lowercased() + "-edited.png")
            try PrivateFiles.atomicPrivateWrite(editedPNG, to: source)
        } else {
            source = original
        }
        let record = try await importCompletedScreenshot(at: source, origin: .applicationScreenshot,
                                                        firstSeenAt: firstSeenAt)
        // Existing source-key records are immutable provenance. Never return a
        // pre-existing system/synthetic record as successful built-in admission,
        // and never retag historical records or their operations to repair it.
        guard record.image.origin == .applicationScreenshot else { throw RiftletError.modeMismatch }
        return record
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
