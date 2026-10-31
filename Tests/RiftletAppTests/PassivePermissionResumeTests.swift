import Foundation
import XCTest
@testable import RiftletApp

/// Deliberately ignores task cancellation, like an OS call already in flight.
@MainActor
private final class ControlledPermissionInspection {
    private var replies: [CheckedContinuation<AutomationPermissionState, Never>] = []
    private(set) var calls = 0

    func inspect() async -> AutomationPermissionState {
        calls += 1
        return await withCheckedContinuation { replies.append($0) }
    }

    func finish(_ result: AutomationPermissionState) {
        guard !replies.isEmpty else { XCTFail("No inspection owns this reply"); return }
        replies.removeFirst().resume(returning: result)
    }

    func finishAll() {
        while !replies.isEmpty { replies.removeFirst().resume(returning: .unavailable) }
    }
}

final class PassivePermissionResumeTests: XCTestCase {
    @MainActor private func waitUntil(_ description: String, file: StaticString = #filePath,
                                     line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        XCTAssertTrue(condition(), description, file: file, line: line)
    }

    @MainActor func testStartAloneDoesNotPollAndStoppedEventsCannotProbe() async {
        let probe = ControlledPermissionInspection()
        var resumes = 0
        let recovery = PassivePermissionResume(inspect: { await probe.inspect() }, resume: { resumes += 1 })
        recovery.request()
        recovery.start(); recovery.start()
        await Task.yield()
        XCTAssertEqual(probe.calls, 0)
        XCTAssertFalse(recovery.isBusy)
        recovery.request(); recovery.stop()
        await waitUntil("Cancelled queued task drains") { !recovery.isBusy }
        recovery.request()
        XCTAssertEqual(probe.calls, 0)
        XCTAssertEqual(resumes, 0)
    }

    @MainActor func testLaterHostEventResumesAfterBrowserWasUnavailable() async {
        let probe = ControlledPermissionInspection()
        var states: [AutomationPermissionState] = [], resumes = 0
        let recovery = PassivePermissionResume(inspect: { await probe.inspect() },
            onResult: { states.append($0) }, resume: { resumes += 1 })
        defer { recovery.stop(); probe.finishAll() }
        recovery.start(); recovery.request()
        await waitUntil("Initial passive check starts") { probe.calls == 1 }
        probe.finish(.browserNotRunning)
        await waitUntil("Unavailable result ends without retry") { !recovery.isBusy }
        XCTAssertEqual(states, [.browserNotRunning]); XCTAssertEqual(resumes, 0)
        recovery.request()
        await waitUntil("A later host event makes a fresh check") { probe.calls == 2 }
        probe.finish(.granted)
        await waitUntil("Granted event resumes once") { !recovery.isBusy }
        XCTAssertEqual(states, [.browserNotRunning, .granted]); XCTAssertEqual(resumes, 1)
        XCTAssertEqual(probe.calls, 2, "No polling after a completed event")
    }

    @MainActor func testDeniedOrUnrequestedPermissionNeverResumes() async {
        let probe = ControlledPermissionInspection()
        var states: [AutomationPermissionState] = [], resumes = 0
        let recovery = PassivePermissionResume(inspect: { await probe.inspect() },
            onResult: { states.append($0) }, resume: { resumes += 1 })
        defer { recovery.stop(); probe.finishAll() }
        recovery.start()
        let unavailable: [AutomationPermissionState] = [.denied, .notRequested, .notNeeded,
                                                        .browserNotInstalled, .unavailable]
        for (index, state) in unavailable.enumerated() {
            recovery.request()
            await waitUntil("Each event is checked") { probe.calls == index + 1 }
            probe.finish(state)
            await waitUntil("Non-granted result drains") { !recovery.isBusy }
        }
        XCTAssertEqual(states, unavailable); XCTAssertEqual(resumes, 0)
    }

    @MainActor func testEventBurstCoalescesWithoutParallelInspectionOrResume() async {
        let probe = ControlledPermissionInspection()
        var resumes = 0
        let recovery = PassivePermissionResume(inspect: { await probe.inspect() }, resume: { resumes += 1 })
        defer { recovery.stop(); probe.finishAll() }
        recovery.start(); recovery.request()
        await waitUntil("First check starts") { probe.calls == 1 }
        for _ in 0..<100 { recovery.request() }
        XCTAssertEqual(probe.calls, 1)
        probe.finish(.denied)
        await waitUntil("Burst becomes one follow-up") { probe.calls == 2 }
        probe.finish(.granted)
        await waitUntil("Coalesced work drains") { !recovery.isBusy }
        XCTAssertEqual(probe.calls, 2); XCTAssertEqual(resumes, 1)
    }

    @MainActor func testStopRejectsLateGrantedResultAndDropsPendingEvents() async {
        let probe = ControlledPermissionInspection()
        var states: [AutomationPermissionState] = [], resumes = 0
        let recovery = PassivePermissionResume(inspect: { await probe.inspect() },
            onResult: { states.append($0) }, resume: { resumes += 1 })
        defer { recovery.stop(); probe.finishAll() }
        recovery.start(); recovery.request()
        await waitUntil("OS inspection starts") { probe.calls == 1 }
        recovery.request(); recovery.stop()
        XCTAssertTrue(recovery.isBusy, "Cancellation must not pretend the OS call returned")
        probe.finish(.granted)
        await waitUntil("Late reply releases its slot") { !recovery.isBusy }
        XCTAssertEqual(probe.calls, 1); XCTAssertTrue(states.isEmpty); XCTAssertEqual(resumes, 0)
    }

    @MainActor func testRestartWaitsForOldCallAndNeverUsesItsGrant() async {
        let probe = ControlledPermissionInspection()
        var states: [AutomationPermissionState] = [], resumes = 0
        let recovery = PassivePermissionResume(inspect: { await probe.inspect() },
            onResult: { states.append($0) }, resume: { resumes += 1 })
        defer { recovery.stop(); probe.finishAll() }
        recovery.start(); recovery.request()
        await waitUntil("Old check starts") { probe.calls == 1 }
        recovery.stop(); recovery.start(); recovery.request()
        XCTAssertEqual(probe.calls, 1)
        probe.finish(.granted)
        await waitUntil("Replacement starts only after old call drains") { probe.calls == 2 }
        XCTAssertTrue(states.isEmpty); XCTAssertEqual(resumes, 0)
        probe.finish(.denied)
        await waitUntil("Replacement result finishes") { !recovery.isBusy }
        XCTAssertEqual(states, [.denied]); XCTAssertEqual(resumes, 0)
    }

    @MainActor func testStateCallbackCanStopBeforeGrantedResumption() async {
        let probe = ControlledPermissionInspection()
        var resumes = 0
        var recovery: PassivePermissionResume!
        recovery = PassivePermissionResume(inspect: { await probe.inspect() },
            onResult: { _ in recovery.stop() }, resume: { resumes += 1 })
        defer { recovery.stop(); probe.finishAll(); recovery = nil }
        recovery.start(); recovery.request()
        await waitUntil("Check starts") { probe.calls == 1 }
        probe.finish(.granted)
        await waitUntil("Reentrant stop drains without resume") { !recovery.isBusy }
        XCTAssertEqual(resumes, 0)
    }

    @MainActor func testResumeOwnsFlightUntilItsAwaitFinishesAndReceivesCancellation() async {
        let probe = ControlledPermissionInspection()
        var resumeContinuation: CheckedContinuation<Void, Never>?
        var resumes = 0, cancellations = 0
        let recovery = PassivePermissionResume(inspect: { await probe.inspect() }, resume: {
            resumes += 1
            await withCheckedContinuation { resumeContinuation = $0 }
            if Task.isCancelled { cancellations += 1 }
        })
        defer { recovery.stop(); probe.finishAll(); resumeContinuation?.resume(); resumeContinuation = nil }
        recovery.start(); recovery.request()
        await waitUntil("First check starts") { probe.calls == 1 }
        probe.finish(.granted)
        await waitUntil("Resume enters its own await") { resumeContinuation != nil }
        for _ in 0..<100 { recovery.request() }
        XCTAssertTrue(recovery.isBusy); XCTAssertEqual(probe.calls, 1); XCTAssertEqual(resumes, 1)
        recovery.stop(); recovery.start(); recovery.request()
        XCTAssertEqual(probe.calls, 1, "Restart must not overlap an existing resume")
        resumeContinuation?.resume(); resumeContinuation = nil
        await waitUntil("Cancelled resume drains before new inspection") { probe.calls == 2 }
        XCTAssertEqual(cancellations, 1)
        probe.finish(.denied)
        await waitUntil("Fresh denied event finishes") { !recovery.isBusy }
        XCTAssertEqual(resumes, 1, "An old grant never supplies a new resumption")
    }
}
