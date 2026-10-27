import XCTest
@testable import RiftletApp

final class AcceptanceTraceDeduplicatorTests: XCTestCase {
    func testUnchangedRefreshDoesNotConsumeEventAndEveryVisibilityFieldChangeRemainsVisible() {
        var trace = AcceptanceTraceDeduplicator<Int, [String]>()
        let original = ["pending", "visible", "newCapture", "0", "none"]
        XCTAssertTrue(trace.shouldRecord(original, for: 1))
        for _ in 0..<3000 { XCTAssertFalse(trace.shouldRecord(original, for: 1)) }
        for index in original.indices {
            var changed = original
            changed[index] = "different-\(index)"
            XCTAssertTrue(trace.shouldRecord(changed, for: 1))
            XCTAssertTrue(trace.shouldRecord(original, for: 1)) // A → B → A is still a change.
        }
        XCTAssertTrue(trace.shouldRecord(original, for: 2))
        XCTAssertEqual(trace.count, 2)
    }

    func testReadyRecordsAreIndependentAndAttemptPhaseOrAssetChangesAreNotHidden() {
        var trace = AcceptanceTraceDeduplicator<Int, [String]>()
        let original = ["asset", "1", "succeeded"]
        XCTAssertTrue(trace.shouldRecord(original, for: 10))
        XCTAssertFalse(trace.shouldRecord(original, for: 10))
        XCTAssertTrue(trace.shouldRecord(original, for: 11))
        for index in original.indices {
            var changed = original
            changed[index] = "different-\(index)"
            XCTAssertTrue(trace.shouldRecord(changed, for: 10))
        }
    }

    func testBoundedEvictionMayRepeatButCannotSuppressTransition() {
        var trace = AcceptanceTraceDeduplicator<Int, String>(capacity: Int.max)
        for key in 0..<1000 {
            XCTAssertTrue(trace.shouldRecord("same", for: key))
            XCTAssertLessThanOrEqual(trace.count, 128)
        }
        XCTAssertTrue(trace.shouldRecord("same", for: 0)) // Evicted values can be logged again.
        XCTAssertFalse(trace.shouldRecord("same", for: 999))
        XCTAssertTrue(trace.shouldRecord("changed", for: 999))
        XCTAssertEqual(trace.count, 128)
    }
}
