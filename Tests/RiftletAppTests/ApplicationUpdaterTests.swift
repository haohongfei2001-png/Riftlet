import XCTest
@testable import RiftletApp

final class ApplicationUpdaterTests: XCTestCase {
    func testBothPublicVersionAndBuildAdvanceForAnUpgrade() {
        for (oldVersion, oldBuild, newVersion, newBuild, expected) in [
            ("1.0.0", "22", "1.0.1", "23", true),
            ("1.9.9", "29", "1.10.0", "31", true),
            ("1.0.1", "23", "1.0.1", "24", false),
            ("1.0.1", "23", "1.0.0", "24", false),
            ("1.0.1", "23", "1.1.0", "23", false),
            ("1.0.1", "23", "1.1.0", "22", false),
            ("1.0.0", "22", "1.0.1-beta", "23", false),
            ("1.0.0", "22", "1..1", "23", false),
            ("1.0.0", "22", "1.0.1", "999999999999999999999999", false),
            ("1.0.0", "22", "1.0.01", "23", false)
        ] {
            XCTAssertEqual(ApplicationUpdater.isUpgrade(from: oldVersion, build: oldBuild,
                to: newVersion, build: newBuild), expected)
        }
    }
}
