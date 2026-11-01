import XCTest
import RiftletCore
@testable import RiftletApp

private actor ReceiverProbe: AutomationPermissionChecking {
    private var pending: [Int: CheckedContinuation<AutomationPermissionState, Never>] = [:]
    private var receivers: [String?] = []
    func check(askUserIfNeeded: Bool) async -> AutomationPermissionState { .unavailable }
    func check(askUserIfNeeded: Bool, expectedSession: String?) async -> AutomationPermissionState {
        let index = receivers.count
        receivers.append(expectedSession)
        return await withCheckedContinuation { pending[index] = $0 }
    }
    func count() -> Int { receivers.count }
    func sessions() -> [String?] { receivers }
    func finish(_ i: Int, _ result: AutomationPermissionState) { pending.removeValue(forKey: i)?.resume(returning: result) }
}

final class PinnedSelectionTests: XCTestCase {
    private func target(pin: UUID? = UUID()) -> TargetLease {
        .init(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
              sessionID: "A", windowID: "1", tabID: "2", documentID: "doc-A", composerID: "editor-A",
              draftGeneration: "draft-A", clickBindingID: pin)
    }
    private func token(_ target: TargetLease, authorization: AcceptedSelection.Authorization = .nativeClickPin) -> AcceptedSelection {
        .init(assetID: UUID(), target: target, hostEpoch: UUID(), acknowledgedUptime: 10.1,
              eventUptime: 10, acceptedUptime: 10.2, visibilityRevision: 0, deadlineUptime: 40.2,
              authorization: authorization)
    }
    @MainActor func testPinnedAContinuesAcrossFutureEpochProcessAndNoForegroundButExplicitCancellationWins() {
        for foreground in ["A", "B", nil] as [String?] {
            let authority = SelectionAuthority(), selection = token(target())
            XCTAssertTrue(authority.insert(selection, now: 10.2))
            XCTAssertEqual(authority.cancelUnpinned(), [])
            XCTAssertTrue(authority.permits(selection, epoch: UUID(), foregroundSession: foreground,
                hidden: false, terminating: false, now: 11))
            XCTAssertFalse(authority.permits(selection, epoch: UUID(), foregroundSession: foreground,
                hidden: true, terminating: false, now: 11))
            XCTAssertFalse(authority.permits(selection, epoch: UUID(), foregroundSession: foreground,
                hidden: false, terminating: true, now: 11))
            XCTAssertEqual(authority.cancel(assetID: selection.assetID), [selection.id])
            XCTAssertFalse(selection.isValid(at: 11))
        }
    }
    func testPinAuthorizationDoesNotBackdateACKOrAdmitPlainLateLease() {
        XCTAssertTrue(token(target()).isValid(at: 11))
        XCTAssertFalse(token(target(pin: nil)).isValid(at: 11))
        XCTAssertFalse(token(target(), authorization: .preEventAcknowledgement).isValid(at: 11))
        XCTAssertFalse(token(target(pin: nil), authorization: .preEventAcknowledgement).isValid(at: 11))
        XCTAssertFalse(token(target()).isValid(at: 40.2))
        let invalidEvent = AcceptedSelection(assetID: UUID(), target: target(), hostEpoch: UUID(),
            acknowledgedUptime: 10, eventUptime: -1, acceptedUptime: 10.2, visibilityRevision: 0,
            deadlineUptime: 40.2, authorization: .nativeClickPin)
        XCTAssertFalse(invalidEvent.isValid(at: 11))
    }
    func testLegacyDecodeAndUnknownConflictStillIgnoreNewClickCapabilityForLocking() throws {
        let original = target(pin: nil)
        let data = try JSONEncoder().encode(original)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("clickBindingID"))
        XCTAssertEqual(try JSONDecoder().decode(TargetLease.self, from: data), original)
        let a = target(), b = target()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.serializationKey, b.serializationKey)
        XCTAssertTrue(a.conflictsForDispatch(with: b))
        XCTAssertTrue(a.conflictsForDispatch(with: original))
        XCTAssertEqual(try JSONDecoder().decode(TargetLease.self, from: JSONEncoder().encode(a)), a)
    }
    @MainActor private func wait(_ n: Int, _ probe: ReceiverProbe) async {
        for _ in 0..<2000 { if await probe.count() == n { return }; await Task.yield() }
        XCTFail("permission probe did not start")
    }
    @MainActor func testBPermissionCannotCancelIndependentOriginalAInspection() async {
        let probe = ReceiverProbe(), policy = OriginalReceiverPermission()
        let gate = AutomationPermissionGate(requiresChrome: true, checker: probe)
        let a = Task { await policy.inspect(session: "A", gate: gate) }
        await wait(1, probe)
        let b = Task { await policy.inspect(session: "B", gate: gate) }
        await wait(2, probe)
        await probe.finish(1, .denied); let br = await b.value
        XCTAssertEqual(br, .denied)
        await probe.finish(0, .granted); let ar = await a.value
        XCTAssertEqual(ar, .granted)
        let sessions = await probe.sessions(); XCTAssertEqual(sessions, ["A", "B"])
    }
    @MainActor func testForegroundPermissionResultAndClickInspectionShareReceiverOrder() async {
        let probe = ReceiverProbe(), policy = OriginalReceiverPermission()
        let gate = AutomationPermissionGate(requiresChrome: true, checker: probe)
        let original = Task { await policy.inspect(session: "A", gate: gate) }
        await wait(1, probe)
        let foregroundRequest = policy.begin(session: "A")
        XCTAssertTrue(policy.resolve(foregroundRequest, result: .denied).published)
        await probe.finish(0, .granted)
        let reply = await original.value
        XCTAssertEqual(reply, .unavailable)
        let authority = SelectionAuthority(), a = token(target())
        XCTAssertTrue(authority.insert(a, now: 10.2))
        XCTAssertEqual(authority.cancelPinned(session: "B"), [])
        XCTAssertTrue(a.isValid(at: 11))
        XCTAssertEqual(authority.cancelPinned(session: "A"), [a.id])
        XCTAssertFalse(a.isValid(at: 11))
    }

    @MainActor func testNewerOriginalReceiverDenialVetoesLateGrant() async {
        let probe = ReceiverProbe(), policy = OriginalReceiverPermission()
        let gate = AutomationPermissionGate(requiresChrome: true, checker: probe)
        let old = Task { await policy.inspect(session: "A", gate: gate) }
        await wait(1, probe)
        let fresh = Task { await policy.inspect(session: "A", gate: gate) }
        await wait(2, probe)
        await probe.finish(1, .denied); _ = await fresh.value
        await probe.finish(0, .granted); let result = await old.value
        XCTAssertEqual(result, .unavailable)
    }
}
