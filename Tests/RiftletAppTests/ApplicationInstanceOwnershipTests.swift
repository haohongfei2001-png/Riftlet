import Foundation
import XCTest
import Darwin
import RiftletFeedback
@testable import RiftletApp

final class ApplicationInstanceOwnershipTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-startup-owner-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testHistoricalFeedbackFirstOrderingCanSplitRealStoreAndAppLocks() throws {
        let feedbackB = try FeedbackStore(directory: root.appendingPathComponent("Feedback-v01"))
        let ownerA = try ApplicationInstanceOwnership(root: root)
        defer { ownerA.close() }
        XCTAssertThrowsError(try ApplicationInstanceOwnership(root: root))
        XCTAssertThrowsError(try FeedbackStore(directory: root.appendingPathComponent("Feedback-v01")))
        withExtendedLifetime(feedbackB) {}
    }

    func testOwnershipBeforeSidecarsRejectsLoserWithoutOpeningItsFeedbackStore() throws {
        let ownerA = try ApplicationInstanceOwnership(root: root)
        defer { ownerA.close() }
        var loserStartedSidecar = false
        do {
            let ownerB = try ApplicationInstanceOwnership(root: root)
            defer { ownerB.close() }
            loserStartedSidecar = true
            _ = try FeedbackStore(directory: root.appendingPathComponent("Feedback-v01"))
            XCTFail("Second instance must be refused")
        } catch ApplicationInstanceOwnership.Failure.unavailable {}
        XCTAssertFalse(loserStartedSidecar)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Feedback-v01").path))
        let feedbackA = try FeedbackStore(directory: root.appendingPathComponent("Feedback-v01"))
        withExtendedLifetime(feedbackA) {}
    }

    func testCloseIsIdempotentAndAllowsNextOwnerWithoutDeletingHistory() throws {
        let marker = root.appendingPathComponent("preserved-history")
        let bytes = Data("original".utf8); try bytes.write(to: marker)
        let first = try ApplicationInstanceOwnership(root: root)
        first.close(); first.close()
        let second = try ApplicationInstanceOwnership(root: root)
        defer { second.close() }
        XCTAssertEqual(try Data(contentsOf: marker), bytes)
        XCTAssertThrowsError(try ApplicationInstanceOwnership(root: root))
    }

    func testTerminationRetainsOwnershipAfterObjectDestructionWhileSidecarLives() throws {
        var owner: ApplicationInstanceOwnership? = try ApplicationInstanceOwnership(root: root)
        let feedback = try FeedbackStore(directory: root.appendingPathComponent("Feedback-v01"))
        owner?.keepUntilProcessExit(); owner?.close(); owner = nil
        // Exactly one descriptor is intentionally owned by this test process
        // until its exit, matching irreversible App termination. No user root.
        XCTAssertThrowsError(try ApplicationInstanceOwnership(root: root))
        XCTAssertThrowsError(try FeedbackStore(directory: root.appendingPathComponent("Feedback-v01")))
        withExtendedLifetime(feedback) {}
    }

    func testModesRemainIndependentAndLinkedLockIsRefusedWithoutChangingTarget() throws {
        let first = try ApplicationInstanceOwnership(root: root.appendingPathComponent("one"))
        let second = try ApplicationInstanceOwnership(root: root.appendingPathComponent("two"))
        defer { first.close(); second.close() }
        let linked = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("original")
        let bytes = Data("untouched".utf8); try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("instance.lock"), withDestinationURL: target)
        XCTAssertThrowsError(try ApplicationInstanceOwnership(root: linked))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }
}
