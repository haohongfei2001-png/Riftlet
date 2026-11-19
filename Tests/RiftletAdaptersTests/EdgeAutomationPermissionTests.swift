import Darwin
import XCTest
@testable import RiftletAdapters

private final class EdgePermissionCalls: @unchecked Sendable {
    var asked: [Bool] = []
    var status: Int32 = -1744
    var atCall: (() -> Void)?
    func determine(_ process: EdgeProcessIdentity, _ ask: Bool) async -> Int32 {
        asked.append(ask); atCall?(); return status
    }
}

@MainActor private final class EdgeSigningPause {
    private var paused: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func suspend() async {
        await withCheckedContinuation { continuation in
            paused = continuation
            observer?.resume(); observer = nil
        }
    }
    func waitForEntry() async {
        if paused != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { paused?.resume(); paused = nil }
}

final class EdgeAutomationPermissionTests: XCTestCase {
    private func identity(pid: pid_t = 71, second: UInt64 = 10) -> EdgeProcessIdentity {
        var record = proc_bsdinfo(); record.pbi_pid = UInt32(pid); record.pbi_start_tvsec = second
        return EdgeProcessIdentity(birth: KernelProcessBirth(requestedPID: pid, record: record,
            bytesRead: Int32(MemoryLayout.size(ofValue: record)))!, applicationID: "com.microsoft.edgemac", terminated: false)!
    }
    private let signature = EdgeAutomationCodeIdentity(signatureValid: true,
        signingIdentifier: "org.riftlet.synthetic", teamIdentifier: nil)

    @MainActor func testConsentNeededRequestsOnceOnlyFromExplicitAction() async {
        let receiver = identity(), calls = EdgePermissionCalls()
        let gate = EdgeAutomationPermissionController(foreground: { receiver }, current: { $0 == receiver },
            determine: { process, ask in await calls.determine(process, ask) }, signing: { _ in self.signature })
        let initial = await gate.checkCurrent(expectedSession: receiver.session)
        XCTAssertEqual(initial.state, .notRequested)
        XCTAssertEqual(initial.osStatus, -1744)
        XCTAssertFalse(initial.prompted)
        let first = await gate.requestFromUserAction(expectedSession: receiver.session)
        XCTAssertTrue(first.prompted)
        let second = await gate.requestFromUserAction(expectedSession: receiver.session)
        XCTAssertFalse(second.prompted)
        XCTAssertEqual(calls.asked, [false, false, true, false])
        XCTAssertEqual(first.sender, signature); XCTAssertEqual(first.receiver, signature)
    }

    @MainActor func testDeniedAndReceiverSwitchNeverPromptOrBorrowAnotherProcess() async {
        let original = identity(), other = identity(second: 11), calls = EdgePermissionCalls()
        var front = original
        let gate = EdgeAutomationPermissionController(foreground: { front }, current: { $0 == front },
            determine: { process, ask in await calls.determine(process, ask) }, signing: { _ in self.signature })
        calls.status = -1743
        let denied = await gate.requestFromUserAction(expectedSession: original.session)
        XCTAssertEqual(denied.state, .denied); XCTAssertEqual(calls.asked, [false])
        calls.status = -1744; calls.atCall = { front = other }
        let switched = await gate.requestFromUserAction(expectedSession: original.session)
        XCTAssertEqual(switched.state, .receiverChanged); XCTAssertEqual(calls.asked, [false, false])
        let wrong = await gate.requestFromUserAction(expectedSession: original.session)
        XCTAssertEqual(wrong.state, .receiverChanged); XCTAssertEqual(calls.asked, [false, false])
    }

    @MainActor func testOriginalObservationIsPassiveAndIndependentOfForeground() async {
        let original = identity(), calls = EdgePermissionCalls()
        var alive = true
        let gate = EdgeAutomationPermissionController(foreground: { nil }, current: { _ in alive },
            determine: { process, ask in await calls.determine(process, ask) }, signing: { _ in self.signature },
            recover: { $0 == original.session && alive ? original : nil })
        calls.status = 0
        let result = await gate.checkOriginal(session: original.session)
        XCTAssertEqual(result.state, .granted); XCTAssertFalse(result.prompted)
        XCTAssertEqual(calls.asked, [false])
        let unknown = await gate.checkOriginal(session: identity(second: 11).session)
        XCTAssertEqual(unknown.state, .receiverChanged); XCTAssertEqual(calls.asked, [false])
        calls.atCall = { alive = false }
        let exited = await gate.checkOriginal(session: original.session)
        XCTAssertEqual(exited.state, .receiverChanged); XCTAssertEqual(calls.asked, [false, false])
    }

    @MainActor func testForegroundSwitchDuringEitherSigningAwaitRefusesWithoutAppleEvents() async {
        for pauseSender in [true, false] {
            let original = identity(), other = identity(pid: 72, second: 11), calls = EdgePermissionCalls(), pause = EdgeSigningPause()
            var front = original
            let pausedPID = pauseSender ? getpid() : original.pid
            let gate = EdgeAutomationPermissionController(foreground: { front }, current: { $0 == original || $0 == other },
                determine: { process, ask in await calls.determine(process, ask) }, signing: { pid in
                    if pid == pausedPID { await pause.suspend() }
                    return self.signature
                })
            let request = Task { await gate.requestFromUserAction() }
            await pause.waitForEntry()
            front = other
            pause.resume()
            let result = await request.value
            XCTAssertEqual(result.state, .receiverChanged)
            XCTAssertNil(result.osStatus)
            XCTAssertFalse(result.prompted)
            XCTAssertTrue(calls.asked.isEmpty)
        }
    }

    @MainActor func testOriginalProcessExitDuringEitherSigningAwaitRefusesWithoutForegroundLookup() async {
        for pauseSender in [true, false] {
            let original = identity(), calls = EdgePermissionCalls(), pause = EdgeSigningPause()
            var alive = true, foregroundReads = 0
            let pausedPID = pauseSender ? getpid() : original.pid
            let gate = EdgeAutomationPermissionController(foreground: { foregroundReads += 1; return nil },
                current: { _ in alive }, determine: { process, ask in await calls.determine(process, ask) }, signing: { pid in
                    if pid == pausedPID { await pause.suspend() }
                    return self.signature
                }, recover: { $0 == original.session && alive ? original : nil })
            let request = Task { await gate.checkOriginal(session: original.session) }
            await pause.waitForEntry()
            alive = false
            pause.resume()
            let result = await request.value
            XCTAssertEqual(result.state, .receiverChanged)
            XCTAssertNil(result.osStatus)
            XCTAssertFalse(result.prompted)
            XCTAssertTrue(calls.asked.isEmpty)
            XCTAssertEqual(foregroundReads, 0)
        }
    }

    func testSessionParserRejectsLegacyChromeAliasesAndNoncanonicalKernelFields() {
        XCTAssertEqual(EdgeProcessIdentity.sessionPID(identity().session), 71)
        for invalid in ["71:10.0", "chrome-kernel-v1:71:10:0", "edge-kernel-v1:071:10:0",
                        "edge-kernel-v1:71:0:0", "edge-kernel-v1:71:10:1000000", "edge-kernel-v1:71:10:00"] {
            XCTAssertNil(EdgeProcessIdentity.sessionPID(invalid))
        }
    }
}
