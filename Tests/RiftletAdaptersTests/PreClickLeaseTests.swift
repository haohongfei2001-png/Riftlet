import XCTest
import RiftletCore
@testable import RiftletAdapters

final class PreClickLeaseTests: XCTestCase {
    private let epoch = UUID()
    private func ticket(_ name: String = "original") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "chrome-kernel-v1:1:2:3", windowID: "12", tabID: "34", documentID: name,
            composerID: "editor", draftGeneration: "draft", clickBindingID: UUID())
    }
    private func ack(_ target: TargetLease, start: Double = 1, at time: Double = 2) -> PreClickLeasePool<Int>.Entry {
        .init(arm: ArmedTarget(target: target, acknowledgedUptime: time, hostSession: epoch), destination: 5, preparationStarted: start)
    }
    private func click(_ pool: inout PreClickLeasePool<Int>, at time: Double, tab: String = "34") -> TargetLease? {
        pool.freeze(press: time, now: time + 0.001, epoch: epoch, session: "chrome-kernel-v1:1:2:3",
            window: "12", tab: tab)?.arm.target
    }

    func testNoPendingOrLateReplyCanGrantAnEarlierPress() {
        var pool = PreClickLeasePool<Int>()
        let original = ticket()
        XCTAssertNil(click(&pool, at: 1.4))
        XCTAssertTrue(pool.acknowledge(ack(original)).isEmpty)
        XCTAssertNil(click(&pool, at: 1.4))
        XCTAssertNil(click(&pool, at: 2))
        XCTAssertNil(click(&pool, at: 2.1, tab: "35"))
        XCTAssertEqual(click(&pool, at: 2.2), original)
        XCTAssertNil(click(&pool, at: 2.3))
    }

    func testTwoDistinctPressesGetDifferentPreAcknowledgedReceivers() {
        var pool = PreClickLeasePool<Int>()
        let a = ticket(), b = ticket()
        _ = pool.acknowledge(ack(a)); _ = pool.acknowledge(ack(b))
        XCTAssertEqual(click(&pool, at: 3), b)
        XCTAssertNil(click(&pool, at: 3))
        XCTAssertEqual(click(&pool, at: 3.015), a)
        XCTAssertNil(click(&pool, at: 3.02))
    }

    func testNewDraftOrEpochCannotReuseOriginal() {
        var pool = PreClickLeasePool<Int>()
        let a = ticket(), b = ticket("replacement")
        _ = pool.acknowledge(ack(a))
        XCTAssertEqual(pool.acknowledge(ack(b)).map(\.arm.target), [a])
        XCTAssertNil(pool.freeze(press: 3, now: 3, epoch: UUID(), session: b.sessionID, window: "12", tab: "34"))
        XCTAssertEqual(click(&pool, at: 4), b)
    }

    func testRenewalExtendsOnlyAStillArmedOriginalWithoutChangingItsFirstAcknowledgement() {
        var pool = PreClickLeasePool<Int>()
        let a = ticket()
        _ = pool.acknowledge(ack(a))
        XCTAssertEqual(pool.nextRenewalUptime, 241)
        XCTAssertFalse(pool.renew(ticket("new"), epoch: epoch, requested: 241, received: 242))
        XCTAssertTrue(pool.renew(a, epoch: epoch, requested: 241, received: 242))
        XCTAssertTrue(pool.renew(a, epoch: epoch, requested: 481, received: 482))
        XCTAssertEqual(pool.armedEntries.first?.arm.acknowledgedUptime, 2)
        XCTAssertEqual(click(&pool, at: 700), a)
        XCTAssertFalse(pool.renew(a, epoch: epoch, requested: 700, received: 701))
        XCTAssertNil(click(&pool, at: 702))
    }

    func testExpiredTicketCannotBeRevivedOrFrozen() {
        var pool = PreClickLeasePool<Int>()
        let a = ticket()
        _ = pool.acknowledge(ack(a))
        XCTAssertFalse(pool.renew(a, epoch: epoch, requested: 539, received: 541))
        XCTAssertNil(click(&pool, at: 541))
        XCTAssertEqual(pool.removeAll().count, 1)
        XCTAssertTrue(pool.armedEntries.isEmpty)
    }

    func testPrivateQARestrictionRequiresOneCanonicalBrowserSessionAndNativeTab() throws {
        let good = #"{"applicationID":"com.microsoft.edgemac","session":"edge-kernel-v1:1234:670:16","windowID":"21","tabID":"42"}"#
        XCTAssertEqual(try QAOriginalBrowserTab.decode(good).tabID, "42")
        XCTAssertThrowsError(try QAOriginalBrowserTab.decode(nil))
        for invalid in [good.replacingOccurrences(of: "edge-kernel", with: "chrome-kernel"),
                        good.replacingOccurrences(of: "1234", with: "0"),
                        good.replacingOccurrences(of: "21", with: "021"),
                        good.replacingOccurrences(of: "42", with: "provider-tab-42"),
                        good.replacingOccurrences(of: "edgemac", with: "Owl")] {
            XCTAssertThrowsError(try QAOriginalBrowserTab.decode(invalid))
        }
    }

    func testBeginAndCommitCanOnlyBeEnteredOncePerExactInvocation() {
        let a = ticket(), invocation = UUID()
        let identity = ObservationIdentity(operationID: UUID(), assetID: UUID(), attempt: 1,
            assetSHA256: String(repeating: "a", count: 64), target: a)
        func command(_ action: WebBridgeAction, _ id: UUID) -> WebBridgeCommand {
            .init(action: action, target: a, identity: identity, invocationID: id)
        }
        var once = FrozenAttachmentInvocation()
        XCTAssertFalse(once.admits(command(.commit, invocation), for: a))
        XCTAssertTrue(once.admits(command(.begin, invocation), for: a))
        XCTAssertFalse(once.admits(command(.begin, UUID()), for: a))
        XCTAssertFalse(once.admits(command(.chunk, UUID()), for: a))
        XCTAssertTrue(once.admits(command(.chunk, invocation), for: a))
        XCTAssertTrue(once.admits(command(.commit, invocation), for: a))
        XCTAssertFalse(once.admits(command(.commit, invocation), for: a))
        XCTAssertFalse(once.admits(command(.discard, invocation), for: a))
    }
}
