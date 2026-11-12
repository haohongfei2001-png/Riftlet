import AppKit
import XCTest
@testable import RiftletUI

/// WindowServer dictionary fixtures in Quartz points, without a dependency on
/// the test runner being allowed to read window titles.
final class SaytilePanelGeometryTests: XCTestCase {
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let companionPID: pid_t = 308
    private let voice = CGRect(x: 1190, y: 50, width: 220, height: 110)

    private func window(_ bounds: CGRect, owner: pid_t = 308, level: NSWindow.Level = .floating,
                        alpha: CGFloat = 1, title: String? = "Saytile · 此刻") -> [String: Any] {
        var info: [String: Any] = [kCGWindowOwnerPID as String: NSNumber(value: owner),
                                   kCGWindowLayer as String: level.rawValue,
                                   kCGWindowBounds as String: bounds.dictionaryRepresentation,
                                   kCGWindowAlpha as String: alpha]
        info[kCGWindowName as String] = title
        return info
    }

    func testMatchesVisibleVoicePanelOfExactProcessAndConvertsQuartzCoordinates() {
        let launcher = CGRect(x: 44, y: 60, width: 42, height: 42)
        let otherWindows = [window(voice, owner: 999), window(voice, level: .normal), window(launcher, title: nil),
                            window(voice, alpha: 0, title: nil), window(voice, title: "Saytile 设置")]
        func resolve(_ windows: [[String: Any]]) -> CGRect? {
            SaytilePanelGeometry.voicePanel(in: windows, owners: [companionPID], primaryTop: primary.maxY,
                                           displays: [primary], target: primary)
        }
        XCTAssertNil(resolve(otherWindows))
        let expected = CGRect(x: 1190, y: 740, width: 220, height: 110)
        for title in ["Saytile · 此刻", nil, ""] {
            XCTAssertEqual(resolve(otherWindows + [window(voice, title: title)]), expected)
        }
    }

    func testStraddlingVoicePanelBelongsToDisplayContainingMostOfIt() {
        let left = CGRect(x: -1280, y: 200, width: 1280, height: 900)
        let screens = [primary, left]
        let spanning = window(CGRect(x: -160, y: -50, width: 220, height: 100), title: nil)
        func resolve(_ windows: [[String: Any]], target: CGRect) -> CGRect? {
            SaytilePanelGeometry.voicePanel(in: windows, owners: [companionPID], primaryTop: primary.maxY,
                                           displays: screens, target: target)
        }
        XCTAssertEqual(resolve([spanning], target: left), CGRect(x: -160, y: 850, width: 220, height: 100))
        XCTAssertNil(resolve([spanning], target: primary))
        XCTAssertNil(resolve([window(voice)], target: left))
        XCTAssertNil(resolve([window(CGRect(x: 1500, y: 100, width: 200, height: 100))], target: primary))
    }
}
