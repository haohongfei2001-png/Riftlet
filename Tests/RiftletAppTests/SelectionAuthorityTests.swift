import XCTest
import RiftletCore
@testable import RiftletApp

@MainActor
final class SelectionAuthorityTests: XCTestCase {
    private let epoch = UUID()
    private let target = TargetLease(adapterID: "fixture", surface: .webChat,
        applicationID: "com.google.Chrome", sessionID: "original-process", windowID: "1", tabID: "1",
        documentID: "original-document", composerID: "original-composer", draftGeneration: "original")

    private func token(asset: UUID = UUID(), accepted: Double = 2) -> AcceptedSelection {
        AcceptedSelection(assetID: asset, target: target, hostEpoch: epoch, acknowledgedUptime: 0.5, eventUptime: 1,
            acceptedUptime: accepted, visibilityRevision: 7, deadlineUptime: accepted + 30,
            captureRequestID: UUID(), armAttemptID: UUID())
    }
    private func permits(_ authority: SelectionAuthority, _ value: AcceptedSelection,
                         at: Double = 3, epoch: UUID? = nil, session: String = "original-process",
                         hidden: Bool = false, terminating: Bool = false) -> Bool {
        authority.permits(value, epoch: epoch ?? self.epoch, foregroundSession: session,
            hidden: hidden, terminating: terminating, now: at)
    }

    func testOriginalIdentityIsRetainedAndEveryCancellationBoundaryRefuses() {
        let authority = SelectionAuthority(), original = token()
        XCTAssertTrue(authority.insert(original, now: 2))
        XCTAssertTrue(permits(authority, original))
        XCTAssertFalse(permits(authority, original, epoch: UUID()))
        XCTAssertFalse(permits(authority, original, session: "another-process"))
        XCTAssertFalse(permits(authority, original, hidden: true))
        XCTAssertFalse(permits(authority, original, terminating: true))
        XCTAssertFalse(permits(authority, original, at: 32))
        XCTAssertEqual(authority.cancel(assetID: original.assetID), [original.id])
        XCTAssertFalse(original.isValid(at: 3))
        XCTAssertFalse(permits(authority, original))
    }

    func testLateCompletionCannotRemoveNewSelectionAndForgedEqualFieldsHaveNoAuthority() {
        let authority = SelectionAuthority(), original = token()
        XCTAssertTrue(authority.insert(original, now: 2))
        authority.cancel()
        let replacement = token(asset: original.assetID)
        XCTAssertTrue(authority.insert(replacement, now: 2))
        authority.finish(original.id)
        XCTAssertTrue(permits(authority, replacement))
        let copied = AcceptedSelection(id: replacement.id, assetID: replacement.assetID, target: target,
            hostEpoch: epoch, acknowledgedUptime: 0.5, eventUptime: 1, acceptedUptime: 2, visibilityRevision: 7, deadlineUptime: 32)
        XCTAssertFalse(permits(authority, copied))
    }

    func testUnpublishedTargetCannotBeTurnedIntoAcceptedSelectionAfterEvent() {
        let late = ArmedTarget(target: target, acknowledgedUptime: 1.1, hostSession: epoch)
        XCTAssertNil(late.freeze(eventUptime: 1, nowUptime: 2, hostSession: epoch, foregroundSession: target.sessionID))
        let earlier = ArmedTarget(target: target, acknowledgedUptime: 0.9, hostSession: epoch)
        XCTAssertEqual(earlier.freeze(eventUptime: 1, nowUptime: 2, hostSession: epoch,
            foregroundSession: target.sessionID), target)
    }

    func testBoundedAuthorityRejectsDuplicatesAndCapacityThenReclaimsExpiredTokens() {
        let authority = SelectionAuthority(), original = token()
        XCTAssertTrue(authority.insert(original, now: 2))
        XCTAssertFalse(authority.insert(token(asset: original.assetID), now: 2))
        for _ in 1..<16 { XCTAssertTrue(authority.insert(token(), now: 2)) }
        XCTAssertFalse(authority.insert(token(), now: 2))
        XCTAssertTrue(authority.insert(token(accepted: 33), now: 33))
        XCTAssertFalse(permits(authority, original, at: 33))
    }
}
