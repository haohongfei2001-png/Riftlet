import XCTest
@testable import RiftletAdapters

final class PendingWebClickTests: XCTestCase {
    private func click(asset: UUID = UUID(), session: String = "original-process", window: String = "1", tab: String = "2") -> PendingWebClick {
        PendingWebClick(assetID: asset, session: session, window: window, tab: tab,
            documentWitness: UUID(), eventUptime: 100, routeFrozenUptime: 100.005)
    }
    func testDelayedReceiptDoesNotChangeOriginalRouteOrEventAndPromotesOnce() {
        let a = click()
        XCTAssertTrue(a.beginResolution(at: 100.006))
        // B activation is deliberately not an input to the original ticket.
        let b = click(session: "another-process", window: "3", tab: "4")
        XCTAssertEqual(a.window, "1"); XCTAssertEqual(a.tab, "2"); XCTAssertEqual(a.eventUptime, 100)
        XCTAssertNotEqual(a.documentWitness, b.documentWitness)
        XCTAssertTrue(a.promote(at: 100.2))
        XCTAssertFalse(a.promote(at: 100.21)); XCTAssertFalse(a.isValid(at: 100.3))
    }
    func testCancellationExpiryAndDuplicateResolverNeverPromote() {
        let cancelled = click(); XCTAssertTrue(cancelled.beginResolution(at: 100.01)); cancelled.cancel()
        XCTAssertFalse(cancelled.promote(at: 100.2))
        let expired = click(); XCTAssertTrue(expired.beginResolution(at: 100.01)); XCTAssertFalse(expired.promote(at: 105))
        let duplicate = click(); XCTAssertTrue(duplicate.beginResolution(at: 100.01)); XCTAssertFalse(duplicate.beginResolution(at: 100.02))
        XCTAssertFalse(click().promote(at: 100.02))
    }
    func testIndependentAssetsHaveIndependentBoundedCapabilities() {
        let a = click(), b = click(tab: "3")
        a.cancel(); XCTAssertTrue(b.beginResolution(at: 100.1)); XCTAssertTrue(b.promote(at: 100.3))
        XCTAssertNotEqual(a.id, b.id); XCTAssertNotEqual(a.assetID, b.assetID)
        XCTAssertEqual(b.deadlineUptime, 105)
    }
}
