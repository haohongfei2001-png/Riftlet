import Foundation
import RiftletCore

extension PrivateAssetImporter {
    /// An owned built-in capture remains a distinct source even when the
    /// macOS encoder writes genuine system-screenshot metadata. That metadata
    /// cannot grant the existing system-only upload admission.
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
            source = InteractiveScreenshotOutput.editedURL(in: expected)
            // Reuse the importer's serial storage actor and hidden final names.
            // The original is never rewritten by the optional editor output.
            try PrivateFiles.atomicPrivateWrite(editedPNG, to: source)
        } else {
            source = original
        }
        let record = try await importCompletedScreenshot(at: source, origin: .applicationScreenshot,
                                                        firstSeenAt: firstSeenAt)
        // Source-key deduplication may return an older record. Its provenance
        // remains immutable: reject another origin instead of retagging it.
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
