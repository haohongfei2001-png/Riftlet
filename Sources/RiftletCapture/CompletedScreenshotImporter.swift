import Foundation
import RiftletCore

extension PrivateAssetImporter {
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
