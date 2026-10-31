import Foundation
import Darwin

typealias ImportCapacityCheck = @Sendable (URL, Int64) throws -> Void

/// A preflight guard, not a reservation or a claim that later writes cannot fail.
/// Only a new private copy uses this guard; existing durable journals must still recover.
enum PrivateStorageCapacity {
    // Engineering headroom for the small manifest, SQLite/WAL and directory writes.
    // This is not a user retention quota and authorizes no cleanup or deletion.
    static let metadataHeadroom: UInt64 = 4 * 1_024 * 1_024

    static func check(directory: URL, copyBytes: Int64) throws {
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CaptureError.io("open-private-capacity", errno) }
        defer { Darwin.close(descriptor) }
        var space = statfs()
        guard fstatfs(descriptor, &space) == 0 else { throw CaptureError.io("read-private-capacity", errno) }
        let available = UInt64(space.f_bavail).multipliedReportingOverflow(by: UInt64(space.f_bsize))
        guard !available.overflow else { throw CaptureError.io("read-private-capacity", EOVERFLOW) }
        try require(availableBytes: available.partialValue, copyBytes: copyBytes)
    }

    static func require(availableBytes: UInt64, copyBytes: Int64) throws {
        guard copyBytes > 0 else { throw CaptureError.imageTooLarge }
        let required = UInt64(copyBytes).addingReportingOverflow(metadataHeadroom)
        guard !required.overflow, availableBytes >= required.partialValue else { throw CaptureError.insufficientStorage }
    }
}
