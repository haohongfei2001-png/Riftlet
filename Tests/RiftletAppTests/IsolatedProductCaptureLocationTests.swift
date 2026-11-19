import XCTest
import Foundation
import RiftletCapture
@testable import RiftletApp

final class IsolatedProductCaptureLocationTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("riftlet-isolated-source-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testFixedSourcePreservesExistingFilesAcrossRestart() async throws {
        let root = try fixture(), provider = IsolatedProductCaptureLocation(root: root)
        let source = try await provider.currentDirectory()
        XCTAssertEqual(source.path, root.appendingPathComponent("capture-source").path)
        let original = source.appendingPathComponent("original.txt")
        try Data("retained".utf8).write(to: original)
        try await provider.start(onChange: { XCTFail("A fixed source cannot signal a preference change") })
        await provider.stop()
        let restarted = try await provider.currentDirectory()
        XCTAssertEqual(restarted, source)
        XCTAssertEqual(try Data(contentsOf: original), Data("retained".utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testRejectsSourceSymlinkInsteadOfWatchingItsDestination() async throws {
        let root = try fixture(), outside = try fixture()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("capture-source"),
                                                  withDestinationURL: outside)
        do {
            _ = try await IsolatedProductCaptureLocation(root: root).currentDirectory()
            XCTFail("Linked screenshot sources must be refused")
        } catch IsolatedProductCaptureLocation.Failure.unsafeDirectory {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testRejectsSharedSourceWithoutChangingItsPermissions() async throws {
        let root = try fixture(), source = root.appendingPathComponent("capture-source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o755])
        do {
            _ = try await IsolatedProductCaptureLocation(root: root).currentDirectory()
            XCTFail("A shared source must not be used")
        } catch IsolatedProductCaptureLocation.Failure.unsafeDirectory {}
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testReadGateRejectsPermissionsOrSourceReplacementAfterStartup() async throws {
        let root = try fixture(), outside = try fixture()
        let source = try await IsolatedProductCaptureLocation(root: root).currentDirectory()
        XCTAssertTrue(IsolatedProductCaptureLocation.permitsRead(source, root: root))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        XCTAssertFalse(IsolatedProductCaptureLocation.permitsRead(source, root: root))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: source.path)
        let retained = root.appendingPathComponent("retained-source")
        try FileManager.default.moveItem(at: source, to: retained)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
        XCTAssertFalse(IsolatedProductCaptureLocation.permitsRead(source, root: root))
        XCTAssertFalse(IsolatedProductCaptureLocation.permitsRead(outside, root: root))
    }

    func testReadGateRejectsSharedOrLinkedRoot() async throws {
        let root = try fixture(), links = try fixture()
        let source = try await IsolatedProductCaptureLocation(root: root).currentDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        XCTAssertFalse(IsolatedProductCaptureLocation.permitsRead(source, root: root))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let alias = links.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        XCTAssertFalse(IsolatedProductCaptureLocation.permitsRead(alias.appendingPathComponent("capture-source"), root: alias))
    }

    func testFactoryKeepsCompilerSelectedFallback() throws {
        let root = try fixture()
        var systemReads = 0
        let systemSource = root.appendingPathComponent("system-source")
        let result = OrdinaryCaptureConfiguration.initialCaptureSource(root: root) {
            systemReads += 1; return systemSource
        }
        #if RIFTLET_ISOLATED_PRODUCT_ACCEPTANCE
        XCTAssertEqual(systemReads, 0)
        XCTAssertEqual(result, IsolatedProductCaptureLocation.directory(in: root))
        #else
        XCTAssertEqual(systemReads, 1)
        XCTAssertEqual(result, systemSource)
        #endif
    }
}
