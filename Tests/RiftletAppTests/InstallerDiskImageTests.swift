import Foundation
import XCTest
@testable import RiftletApp

final class InstallerDiskImageTests: XCTestCase {
    func testOnlyReadOnlyInstallerRootWithShippedApplicationsLinkMatches() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Riftlet 1", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root.deletingLastPathComponent()) }
        let app = root.appendingPathComponent("Riftlet.app", isDirectory: true)
        let applications = root.appendingPathComponent("Applications")
        func matches(_ app: URL, name: String? = "Riftlet", readOnly: Bool? = true, model: String? = "Disk Image") -> Bool {
            InstallerDiskImage.matches(app: app, volumeRoot: root, volumeName: name, readOnly: readOnly, diskModel: { _ in model })
        }

        XCTAssertFalse(matches(app))
        try manager.createSymbolicLink(atPath: applications.path, withDestinationPath: "/Users/Shared")
        XCTAssertFalse(matches(app))
        try manager.removeItem(at: applications)
        try manager.createSymbolicLink(atPath: applications.path, withDestinationPath: "/Applications")
        XCTAssertTrue(matches(app), "Finder may mount a second copy at Riftlet 1")
        XCTAssertFalse(matches(app, readOnly: false))
        XCTAssertFalse(matches(app, readOnly: nil))
        XCTAssertFalse(matches(app, name: "Backup"))
        XCTAssertFalse(matches(app, model: "External SSD"))
        XCTAssertFalse(matches(app, model: nil))
        XCTAssertFalse(matches(root.appendingPathComponent("Subfolder/Riftlet.app")))
        XCTAssertFalse(matches(URL(fileURLWithPath: "/Applications/Riftlet.app")))
        XCTAssertFalse(matches(URL(fileURLWithPath: "/private/var/folders/test/AppTranslocation/id/d/Riftlet.app")))
    }
}
