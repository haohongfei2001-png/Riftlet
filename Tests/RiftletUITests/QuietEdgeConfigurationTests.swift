import XCTest
@testable import RiftletUI

final class QuietEdgeConfigurationTests: XCTestCase {
    func testFreshDefaultsAndBoundaries() throws {
        let c = RiftConfiguration()
        XCTAssertEqual(c.outerInset, 6); XCTAssertEqual(c.hiddenFraction, 0.25)
        XCTAssertEqual(c.visibleCountPreference, 3); XCTAssertEqual(c.placement, .leftMiddle)
        for h in [0.0, 0.25, 0.75, 0.9] { for d in [0.0,6,256] { for n in [1,3,10] {
            var value = c; value.hiddenFraction = h; value.outerInset = d; value.visibleCountPreference = n
            try value.validate(); XCTAssertEqual(try JSONDecoder().decode(RiftConfiguration.self, from: JSONEncoder().encode(value)),value)
        } } }
        var invalid = c; invalid.visibleCountPreference = 11; XCTAssertThrowsError(try invalid.validate())
        invalid = c; invalid.outerInset = 257; XCTAssertThrowsError(try invalid.validate())
    }
    func testOldScalarsAndAbsolutePlacementSurviveMigration() throws {
        let data = Data(#"{"outerInset":0,"firstCenterFromTop":180,"hiddenFraction":0.75,"preferredDisplayID":77}"#.utf8)
        let old = try JSONDecoder().decode(RiftConfiguration.self,from:data)
        XCTAssertNil(old.placement); XCTAssertEqual(old.placementSource,.legacy)
        XCTAssertEqual(old.outerInset,0); XCTAssertEqual(old.firstCenterFromTop,180)
        XCTAssertEqual(old.hiddenFraction,0.75); XCTAssertEqual(old.preferredDisplayID,77)
        XCTAssertEqual(try JSONDecoder().decode(RiftConfiguration.self,from:JSONEncoder().encode(old)),old)
    }
    func testReconnectionNeedsExplicitRestoreAndUserChoiceSupersedesOffer() {
        var s = RiftDisplaySessionSelection()
        let a = RiftDisplaySessionSelection.Display(id:1,uuid:"A"), b = RiftDisplaySessionSelection.Display(id:2,uuid:"B")
        XCTAssertEqual(s.resolve(preferred:2,uuid:"B",main:1,available:[a,b]),2)
        XCTAssertEqual(s.resolve(preferred:2,uuid:"B",main:1,available:[a]),1)
        XCTAssertEqual(s.resolve(preferred:2,uuid:"B",main:1,available:[a,b]),1)
        XCTAssertTrue(s.restoreAvailable)
        XCTAssertEqual(s.resolve(preferred:2,uuid:"B",main:1,available:[a,b],restore:true),2)
        XCTAssertFalse(s.restoreAvailable)
        _ = s.resolve(preferred:2,uuid:"B",main:1,available:[a])
        s.userSelectedDisplay()
        XCTAssertEqual(s.resolve(preferred:1,uuid:"A",main:1,available:[a,b]),1)
        XCTAssertFalse(s.restoreAvailable)
    }
    func testAmbiguousUUIDNeverGuessesAndScalingIDChangeMatchesStableUUID() {
        var s = RiftDisplaySessionSelection()
        let a = RiftDisplaySessionSelection.Display(id:1,uuid:"A"), b = RiftDisplaySessionSelection.Display(id:2,uuid:"B")
        XCTAssertEqual(s.resolve(preferred:99,uuid:"B",main:1,available:[a,b]),2)
        s.userSelectedDisplay()
        XCTAssertEqual(s.resolve(preferred:2,uuid:"B",main:1,available:[a,b,.init(id:3,uuid:"B")]),1)
    }
}
