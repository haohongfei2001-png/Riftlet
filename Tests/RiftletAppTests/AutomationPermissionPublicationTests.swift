import Foundation
import XCTest
import RiftletCore
@testable import RiftletApp

/// Completion order is controlled, including OS work that ignores cancellation.
/// No Chrome process, TCC prompt or input is used by these scheduling regressions.
private actor PublicationPermissionProbe: AutomationPermissionChecking {
    private var continuations: [Int: CheckedContinuation<AutomationPermissionState, Never>] = [:]
    private var sessions: [String?] = []

    func check(askUserIfNeeded: Bool) async -> AutomationPermissionState {
        await check(askUserIfNeeded: askUserIfNeeded, expectedSession: nil)
    }

    func check(askUserIfNeeded: Bool, expectedSession: String?) async -> AutomationPermissionState {
        let index = sessions.count
        sessions.append(expectedSession)
        return await withCheckedContinuation { continuations[index] = $0 }
    }

    func count() -> Int { sessions.count }
    func recordedSessions() -> [String?] { sessions }
    func finish(_ index: Int, with state: AutomationPermissionState) {
        continuations.removeValue(forKey: index)?.resume(returning: state)
    }
}

/// Exercises the production publication policy and native-check interface with
/// suspended replies. This is not an AppKit wiring or live permission test.
@MainActor
private final class PermissionPublicationHarness {
    var epoch = UUID()
    var foreground: String? = "chrome-A"
    var terminating = false
    var status: AutomationPermissionState = .granted
    var armed: ArmedTarget?
    var cancellations = 0
    var publications = 0
    private var policy = AutomationPermissionPublication()
    private let gate: AutomationPermissionGate

    init(probe: PublicationPermissionProbe) { gate = .init(requiresChrome: true, checker: probe) }

    func check(expected: String? = nil) async -> AutomationPermissionState {
        let receiver = expected ?? foreground
        let request = policy.begin(hostEpoch: epoch, foregroundSession: foreground, receiverSession: receiver)
        let observed = await gate.inspect(expectedSession: receiver)
        let resolution = policy.resolve(request, state: observed, hostEpoch: epoch,
                                        foregroundSession: foreground, terminating: terminating)
        if resolution == .publish {
            publications += 1
            status = observed
            if observed != .granted { armed = nil; cancellations += 1 }
        }
        return resolution.mayUseResult ? observed : .unavailable
    }

    func publishTarget() -> TargetLease {
        let target = TargetLease(adapterID: "fixture", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: foreground ?? "background",
            windowID: "original-window", tabID: "original-tab", documentID: "original-document",
            composerID: "original-composer", draftGeneration: "original-draft")
        armed = .init(target: target, acknowledgedUptime: 1, hostSession: epoch)
        return target
    }
}

final class AutomationPermissionPublicationTests: XCTestCase {
    @MainActor private func waitForChecks(_ count: Int, probe: PublicationPermissionProbe,
                                         file: StaticString = #filePath, line: UInt = #line) async {
        let limit = ProcessInfo.processInfo.systemUptime + 2
        while await probe.count() < count, ProcessInfo.processInfo.systemUptime < limit { await Task.yield() }
        let actual = await probe.count()
        XCTAssertEqual(actual, count, file: file, line: line)
    }

    @MainActor func testOldForegroundFailureCannotRevokeNewPreEventACK() async {
        let probe = PublicationPermissionProbe()
        let current = PermissionPublicationHarness(probe: probe)
        let old = Task { await current.check() }
        await waitForChecks(1, probe: probe)
        current.epoch = UUID(); current.foreground = "chrome-B"
        let fresh = Task { await current.check() }
        await waitForChecks(2, probe: probe)
        await probe.finish(1, with: .granted)
        let reply1 = await fresh.value
        XCTAssertEqual(reply1, .granted)
        let target = current.publishTarget()
        await probe.finish(0, with: .browserNotRunning)
        let reply2 = await old.value
        XCTAssertEqual(reply2, .unavailable)
        XCTAssertEqual(current.status, .granted)
        XCTAssertEqual(current.publications, 1); XCTAssertEqual(current.cancellations, 0)
        XCTAssertEqual(current.armed?.freeze(eventUptime: 2, nowUptime: 3, hostSession: current.epoch,
                                            foregroundSession: current.foreground), target)
    }

    @MainActor func testLateOldGrantCannotAuthorizeCallerAfterEpochChanged() async {
        let probe = PublicationPermissionProbe()
        let current = PermissionPublicationHarness(probe: probe)
        current.status = .denied
        let old = Task { await current.check() }
        await waitForChecks(1, probe: probe)
        current.epoch = UUID()
        await probe.finish(0, with: .granted)
        let reply3 = await old.value
        XCTAssertEqual(reply3, .unavailable)
        XCTAssertEqual(current.status, .denied)
        XCTAssertEqual(current.publications, 0); XCTAssertNil(current.armed)
    }

    @MainActor func testNewerGrantSuppressesOlderFailureInSameForeground() async {
        let probe = PublicationPermissionProbe()
        let current = PermissionPublicationHarness(probe: probe)
        let older = Task { await current.check() }
        await waitForChecks(1, probe: probe)
        let newer = Task { await current.check() }
        await waitForChecks(2, probe: probe)
        await probe.finish(1, with: .granted)
        let reply4 = await newer.value
        XCTAssertEqual(reply4, .granted)
        let target = current.publishTarget()
        await probe.finish(0, with: .denied)
        let reply5 = await older.value
        XCTAssertEqual(reply5, .unavailable)
        XCTAssertEqual(current.status, .granted); XCTAssertEqual(current.cancellations, 0)
        XCTAssertEqual(current.armed?.target, target)
    }

    @MainActor func testTwoActualGrantsDoNotSpuriouslyCancelOriginalCheck() async {
        let probe = PublicationPermissionProbe(), host = PermissionPublicationHarness(probe: probe)
        let selectionCheck = Task { await host.check(expected: "chrome-A") }
        await waitForChecks(1, probe: probe)
        let backgroundCheck = Task { await host.check() }
        await waitForChecks(2, probe: probe)
        await probe.finish(1, with: .granted)
        let reply6 = await backgroundCheck.value
        XCTAssertEqual(reply6, .granted)
        await probe.finish(0, with: .granted)
        let reply7 = await selectionCheck.value
        XCTAssertEqual(reply7, .granted)
        XCTAssertEqual(host.publications, 1); XCTAssertEqual(host.cancellations, 0)
        let sessions = await probe.recordedSessions()
        XCTAssertEqual(sessions, ["chrome-A", "chrome-A"], "Each grant came from its own original-session native check")
    }

    @MainActor func testNewerDenialCannotBeOverwrittenByOlderGrant() async {
        let probe = PublicationPermissionProbe(), host = PermissionPublicationHarness(probe: probe)
        let older = Task { await host.check() }
        await waitForChecks(1, probe: probe)
        let newer = Task { await host.check() }
        await waitForChecks(2, probe: probe)
        await probe.finish(1, with: .denied)
        let reply8 = await newer.value
        XCTAssertEqual(reply8, .denied)
        await probe.finish(0, with: .granted)
        let reply9 = await older.value
        XCTAssertEqual(reply9, .unavailable)
        XCTAssertEqual(host.status, .denied); XCTAssertEqual(host.publications, 1)
        XCTAssertEqual(host.cancellations, 1)
    }

    @MainActor func testReturningToSameSessionStillRequiresOriginalHostEpoch() async {
        let probe = PublicationPermissionProbe(), host = PermissionPublicationHarness(probe: probe)
        let old = Task { await host.check() }
        await waitForChecks(1, probe: probe)
        host.foreground = "chrome-B"; host.epoch = UUID()
        host.foreground = "chrome-A"; host.epoch = UUID()
        let target = host.publishTarget()
        await probe.finish(0, with: .unavailable)
        let reply10 = await old.value
        XCTAssertEqual(reply10, .unavailable)
        XCTAssertEqual(host.armed?.target, target); XCTAssertEqual(host.cancellations, 0)
        XCTAssertEqual(host.publications, 0)
    }

    @MainActor func testChangedReceiverOrTerminationMakesGrantUnusable() async {
        let cases: [(String?, Bool)] = [("chrome-A-relaunched", false), (nil, false), ("chrome-A", true)]
        for (foreground, terminating) in cases {
            let probe = PublicationPermissionProbe(), host = PermissionPublicationHarness(probe: probe)
            let pending = Task { await host.check(expected: "chrome-A") }
            await waitForChecks(1, probe: probe)
            host.foreground = foreground; host.terminating = terminating
            await probe.finish(0, with: .granted)
            let reply11 = await pending.value
            XCTAssertEqual(reply11, .unavailable)
            XCTAssertEqual(host.publications, 0)
        }
    }

    func testWrongExplicitReceiverDoesNotDescribeCurrentForegroundPermission() {
        var policy = AutomationPermissionPublication()
        let epoch = UUID()
        let request = policy.begin(hostEpoch: epoch, foregroundSession: "chrome-B", receiverSession: "chrome-A")
        let result = policy.resolve(request, state: .granted, hostEpoch: epoch,
                                    foregroundSession: "chrome-B", terminating: false)
        XCTAssertEqual(result, .staleContext); XCTAssertFalse(result.mayUseResult)
    }

    func testSettingsBackgroundStatusRetainsOriginalReceiverAndDoesNotCreateTarget() {
        var policy = AutomationPermissionPublication()
        let epoch = UUID()
        let request = policy.begin(hostEpoch: epoch, foregroundSession: nil, receiverSession: "chrome-A")
        XCTAssertEqual(policy.resolve(request, state: .notRequested, hostEpoch: epoch,
                                      foregroundSession: nil, terminating: false), .publish)
        let new = policy.begin(hostEpoch: epoch, foregroundSession: nil, receiverSession: "chrome-B")
        XCTAssertEqual(policy.resolve(new, state: .granted, hostEpoch: epoch,
                                      foregroundSession: nil, terminating: false), .publish)
        XCTAssertEqual(policy.resolve(request, state: .granted, hostEpoch: epoch,
                                      foregroundSession: nil, terminating: false), .superseded)
    }

    func testSkippedCaptureRetainsOnlyAnExistingOriginalEpochAndSessionACK() {
        func disposition(attempted: Bool = false, existing: String? = "chrome-A",
                         matches: Bool = true, foreground: String? = "chrome-A") -> AutomationPermissionPublication.TargetDisposition {
            AutomationPermissionPublication.targetDisposition(epochAccepted: true, captureAttempted: attempted,
                returnedSession: nil, existingSession: existing, existingEpochMatches: matches,
                foregroundSession: foreground)
        }
        XCTAssertEqual(disposition(), .retainExisting,
            "An obsolete permission reply, with zero page capture, supplies no page invalidation evidence")
        XCTAssertEqual(disposition(attempted: true), .clear, "Actual failed page capture remains a veto")
        XCTAssertEqual(disposition(existing: nil), .clear, "No target may be manufactured for an unarmed click")
        XCTAssertEqual(disposition(matches: false), .clear)
        XCTAssertEqual(disposition(foreground: "chrome-B"), .clear)
        XCTAssertEqual(disposition(foreground: nil), .clear)
    }

    func testCapturePublicationRejectsStaleEpochAndWrongReturnedReceiver() {
        func disposition(accepted: Bool = true, attempted: Bool = true,
                         returned: String? = "chrome-A") -> AutomationPermissionPublication.TargetDisposition {
            AutomationPermissionPublication.targetDisposition(epochAccepted: accepted, captureAttempted: attempted,
                returnedSession: returned, existingSession: "chrome-A", existingEpochMatches: true,
                foregroundSession: "chrome-A")
        }
        XCTAssertEqual(disposition(), .publish)
        XCTAssertEqual(disposition(accepted: false), .staleEpoch)
        XCTAssertEqual(disposition(accepted: false, returned: nil), .staleEpoch)
        XCTAssertEqual(disposition(returned: "chrome-B"), .clear)
        XCTAssertEqual(disposition(attempted: false), .clear, "A fabricated result without an executed capture never publishes")
    }

    func testSupersededCaptureNeverPublishesAndOnlyRetainsOriginalEpochSession() {
        func result(epoch: Bool = true, matches: Bool = true, foreground: String? = "A",
                    returned: String? = nil) -> AutomationPermissionPublication.TargetDisposition {
            AutomationPermissionPublication.targetDisposition(epochAccepted: epoch, captureAttempted: true,
                returnedSession: returned, existingSession: "A", existingEpochMatches: matches,
                foregroundSession: foreground, captureSuperseded: true)
        }
        XCTAssertEqual(result(), .retainExisting)
        XCTAssertEqual(result(epoch: false), .staleEpoch)
        XCTAssertEqual(result(matches: false), .clear)
        XCTAssertEqual(result(foreground: "B"), .clear)
        XCTAssertEqual(result(foreground: nil), .clear)
        XCTAssertEqual(result(returned: "A"), .clear, "Even a valid late capture cannot become a new ACK")
    }

    func testSupersededCaptureDrainsSchedulerOnceAndDoesNotAuthorizeItsSuccessor() throws {
        var scheduler = TargetArmScheduler()
        XCTAssertTrue(scheduler.start())
        let old = try XCTUnwrap(scheduler.begin())
        XCTAssertFalse(scheduler.request(invalidateEpoch: true))
        let completion = try XCTUnwrap(scheduler.complete(old))
        XCTAssertFalse(completion.acceptsAcknowledgement); XCTAssertTrue(completion.shouldWake)
        XCTAssertEqual(AutomationPermissionPublication.targetDisposition(
            epochAccepted: completion.acceptsAcknowledgement, captureAttempted: true,
            returnedSession: nil, existingSession: "A", existingEpochMatches: true,
            foregroundSession: "A", captureSuperseded: true), .staleEpoch)
        XCTAssertNil(scheduler.complete(old))
        let fresh = try XCTUnwrap(scheduler.begin())
        XCTAssertNotEqual(fresh.id, old.id); XCTAssertNil(scheduler.begin())
        XCTAssertNil(scheduler.complete(old)); XCTAssertEqual(scheduler.inFlight, fresh)
    }
}
