import Foundation
import Darwin
import XCTest
@testable import RiftletCapture

final class StorageUsageTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func directory(_ name: String) throws -> URL {
        let result = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return result
    }

    @discardableResult
    private func file(_ name: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 0x61, count: bytes).write(to: url)
        return url
    }

    private func area(_ type: StorageUsageArea, in result: StorageUsageSnapshot) throws -> StorageAreaUsage {
        try XCTUnwrap(result.areas.first { $0.area == type })
    }

    func testCountsOnlyFixedManagedAreasAndDatabaseSidecars() throws {
        _ = try directory("media"); _ = try directory("staging"); _ = try directory("journal")
        let original = try file("media/fixture.png", bytes: 11)
        _ = try file("media/second.png", bytes: 7)
        _ = try file("staging/partial.part", bytes: 3)
        _ = try file("journal/manifest.json", bytes: 5)
        _ = try file("queue.sqlite", bytes: 13)
        _ = try file("queue.sqlite-wal", bytes: 17)
        _ = try file("queue.sqlite-shm", bytes: 19)
        _ = try file("unrelated-root-file", bytes: 101)
        let result = try PrivateStorageUsage.measure(privateRoot: root)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.regularFileCount, 7)
        XCTAssertEqual(result.logicalBytes, 75)
        XCTAssertEqual(try area(.media, in: result).logicalBytes, 18)
        XCTAssertEqual(try area(.database, in: result).regularFileCount, 3)
        XCTAssertEqual(try Data(contentsOf: original), Data(repeating: 0x61, count: 11))
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(encoded.contains(root.path))
        XCTAssertFalse(encoded.contains("fixture.png"))
    }

    func testAbsentAreasAreExplicitAndDoNotCreateDirectories() throws {
        let result = try PrivateStorageUsage.measure(privateRoot: root)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.regularFileCount, 0)
        XCTAssertEqual(result.logicalBytes, 0)
        XCTAssertTrue(result.areas.allSatisfy { $0.availability == .absent })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testSymlinksAndNestedDirectoriesAreNotTraversed() throws {
        let privateRoot = try directory("private")
        _ = try directory("private/media")
        let outside = try directory("outside")
        _ = try file("outside/private-data", bytes: 2_048)
        try FileManager.default.createSymbolicLink(at: privateRoot.appendingPathComponent("media/link"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: privateRoot.appendingPathComponent("staging"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: privateRoot.appendingPathComponent("queue.sqlite-wal"),
                                                  withDestinationURL: outside.appendingPathComponent("private-data"))
        _ = try directory("private/media/nested")
        _ = try file("private/media/nested/hidden", bytes: 512)
        _ = try file("private/media/regular.png", bytes: 5)
        let result = try PrivateStorageUsage.measure(privateRoot: privateRoot)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.regularFileCount, 1)
        XCTAssertEqual(result.logicalBytes, 5)
        XCTAssertEqual(result.skippedEntryCount, 4)
        XCTAssertEqual(try area(.staging, in: result).availability, .unavailable)
        XCTAssertTrue(try area(.media, in: result).issues.contains(.unsafeEntry))
        XCTAssertTrue(try area(.media, in: result).issues.contains(.unsupportedType))
        XCTAssertTrue(try area(.database, in: result).issues.contains(.unsafeEntry))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("private-data").path))
    }

    func testRootSymlinkIsRejectedInsteadOfFollowingIt() throws {
        let actual = try directory("actual")
        let link = root.appendingPathComponent("root-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
        XCTAssertThrowsError(try PrivateStorageUsage.measure(privateRoot: link))
    }

    func testMetadataAccountingDoesNotNeedFileReadAccessOrOpenSpecialFiles() throws {
        _ = try directory("media")
        let unreadable = try file("media/no-read-permission", bytes: 9)
        XCTAssertEqual(chmod(unreadable.path, 0), 0)
        defer { _ = chmod(unreadable.path, 0o600) }
        let fifo = root.appendingPathComponent("media/pipe")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let result = try PrivateStorageUsage.measure(privateRoot: root)
        XCTAssertEqual(result.regularFileCount, 1)
        XCTAssertEqual(result.logicalBytes, 9)
        XCTAssertEqual(result.skippedEntryCount, 1)
        XCTAssertTrue(try area(.media, in: result).issues.contains(.unsupportedType))
        var metadata = stat()
        XCTAssertEqual(lstat(unreadable.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & 0o777, 0)
    }

    func testEnumerationLimitIsExplicitlyPartialWithoutDeletingEntries() throws {
        _ = try directory("media")
        for index in 0..<3 { _ = try file("media/\(index).png", bytes: 4) }
        let result = try PrivateStorageUsage.measure(privateRoot: root, maximumEntriesPerArea: 1)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.regularFileCount, 1)
        XCTAssertEqual(result.logicalBytes, 4)
        XCTAssertTrue(try area(.media, in: result).issues.contains(.entryLimit))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("media").path).count, 3)
    }

    func testByteOverflowBecomesUnknownInsteadOfWrapping() {
        var result = StorageAreaUsage(area: .media, availability: .present)
        result.observeRegularFile(logicalBytes: UInt64(Int64.max))
        result.observeRegularFile(logicalBytes: UInt64(Int64.max))
        XCTAssertEqual(result.logicalBytes, UInt64.max - 1)
        result.observeRegularFile(logicalBytes: 2)
        XCTAssertNil(result.logicalBytes)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.regularFileCount, 3)
        XCTAssertTrue(result.issues.contains(.arithmeticOverflow))
    }

    func testInaccessibleDirectoryIsReportedWithoutAPath() throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission-denial fixture requires an unprivileged executor") }
        let media = try directory("media")
        _ = try file("media/item", bytes: 4)
        XCTAssertEqual(chmod(media.path, 0), 0)
        defer { _ = chmod(media.path, 0o700) }
        let result = try PrivateStorageUsage.measure(privateRoot: root)
        let item = try area(.media, in: result)
        XCTAssertEqual(item.availability, .unavailable)
        XCTAssertTrue(item.issues.contains(.inaccessible))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.regularFileCount, 0)
    }

    func testInvalidRootAndLimitsFailWithoutNetworkOrDirectoryCreation() throws {
        XCTAssertThrowsError(try PrivateStorageUsage.measure(privateRoot: URL(string: "https://example.invalid/private")!)) {
            XCTAssertEqual($0 as? StorageUsageError, .invalidRoot)
        }
        XCTAssertThrowsError(try PrivateStorageUsage.measure(privateRoot: root, maximumEntriesPerArea: 0)) {
            XCTAssertEqual($0 as? StorageUsageError, .invalidLimit)
        }
        XCTAssertThrowsError(try PrivateStorageUsage.measure(privateRoot: root.appendingPathComponent("missing")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing").path))
    }
}
