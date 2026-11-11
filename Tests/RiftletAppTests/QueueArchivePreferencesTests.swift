import Foundation
import XCTest
@testable import RiftletApp

final class QueueArchivePreferencesTests: XCTestCase {
    func testFirstRunAndLegacyHourPresetsUseTwoMinutesWithoutTurningOffOn() throws {
        XCTAssertEqual(LifecycleSettings().archiveAfterSeconds, 120)
        for old in [30, 601, 3_600, 86_400] {
            let data = Data("{\"archiveAfterSeconds\":\(old)}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(LifecycleSettings.self, from: data).archiveAfterSeconds, 120)
        }
        for oldOff in ["{}", "{\"archiveAfterSeconds\":null}"] {
            let off = try JSONDecoder().decode(LifecycleSettings.self, from: Data(oldOff.utf8))
            XCTAssertNil(off.archiveAfterSeconds)
            XCTAssertEqual(try JSONDecoder().decode(LifecycleSettings.self, from: JSONEncoder().encode(off)), off)
        }
    }

    func testInRangeSecondsSurviveRestartAndNewWritesRejectOutOfRange() throws {
        var setting = LifecycleSettings()
        for seconds in [60.0, 90.0, 120.0, 339.5, 600.0] {
            setting.archiveAfterSeconds = seconds
            try setting.validate()
            XCTAssertEqual(try JSONDecoder().decode(LifecycleSettings.self, from: JSONEncoder().encode(setting)), setting)
        }
        for invalid in [59.9, 600.01, 0, -1, Double.infinity, Double.nan] {
            setting.archiveAfterSeconds = invalid
            XCTAssertThrowsError(try setting.validate())
        }
        XCTAssertThrowsError(try JSONDecoder().decode(LifecycleSettings.self, from: Data("{\"archiveAfterSeconds\":-2}".utf8)))
    }
}
