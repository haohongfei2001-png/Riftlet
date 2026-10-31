import XCTest
import Foundation
import Carbon
import Darwin
@testable import RiftletAdapters
@testable import RiftletApp

private actor PermissionProbe: AutomationPermissionChecking {
    private var results: [AutomationPermissionState]
    private var requests: [Bool] = []
    init(_ results: [AutomationPermissionState]) { self.results = results }
    func check(askUserIfNeeded: Bool) -> AutomationPermissionState {
        requests.append(askUserIfNeeded)
        return results.isEmpty ? .unavailable : results.removeFirst()
    }
    func calls() -> [Bool] { requests }
}

private actor BoundPermissionProbe: AutomationPermissionChecking {
    var sessions: [String?] = []
    func check(askUserIfNeeded: Bool) -> AutomationPermissionState { .unavailable }
    func check(askUserIfNeeded: Bool, expectedSession: String?) -> AutomationPermissionState {
        sessions.append(expectedSession)
        return .granted
    }
    func recorded() -> [String?] { sessions }
}

final class AutomationPermissionTests: XCTestCase {
    func testOrdinaryCaptureCannotProbeOrRequestChrome() async {
        let probe = PermissionProbe([.granted])
        let gate = AutomationPermissionGate(requiresChrome: false, checker: probe)
        let status = await gate.inspect(), request = await gate.requestFromUserAction(), calls = await probe.calls()
        XCTAssertEqual(status, .notNeeded); XCTAssertEqual(request, .notNeeded); XCTAssertTrue(calls.isEmpty)
    }

    func testBackgroundInspectionNeverAsksUser() async {
        let probe = PermissionProbe([.notRequested])
        let status = await AutomationPermissionGate(requiresChrome: true, checker: probe).inspect()
        let calls = await probe.calls()
        XCTAssertEqual(status, .notRequested); XCTAssertEqual(calls, [false])
    }

    func testOnlyExplicitNeedCanRequestAfterPassiveCheck() async {
        let probe = PermissionProbe([.notRequested, .granted])
        let status = await AutomationPermissionGate(requiresChrome: true, checker: probe).requestFromUserAction()
        let calls = await probe.calls()
        XCTAssertEqual(status, .granted); XCTAssertEqual(calls, [false, true])
    }

    func testDeniedGrantedOrMissingBrowserNeverPromptAgain() async {
        for result in [AutomationPermissionState.denied, .granted, .browserNotRunning, .browserNotInstalled, .unavailable] {
            let probe = PermissionProbe([result])
            let status = await AutomationPermissionGate(requiresChrome: true, checker: probe).requestFromUserAction()
            let calls = await probe.calls()
            XCTAssertEqual(status, result); XCTAssertEqual(calls, [false])
        }
    }

    func testEveryDispatchPermissionCheckUsesOriginalSessionWithoutCaching() async {
        let probe = BoundPermissionProbe()
        let gate = AutomationPermissionGate(requiresChrome: true, checker: probe)
        let first = await gate.inspect(expectedSession: "original-process")
        let second = await gate.inspect(expectedSession: "original-process")
        let sessions = await probe.recorded()
        XCTAssertEqual(first, .granted); XCTAssertEqual(second, .granted)
        XCTAssertEqual(sessions, ["original-process", "original-process"])
    }

    func testMultipleChromeInstancesSelectExactOriginalSessionOrForegroundNeverFirst() {
        let first = permissionIdentity(pid: 11, seconds: 1)
        let second = permissionIdentity(pid: 22, seconds: 2)
        XCTAssertEqual(PermissionBrowserIdentity.select([first, second], foregroundPID: 22, expectedSession: nil), second)
        XCTAssertEqual(PermissionBrowserIdentity.select([first, second], foregroundPID: 11, expectedSession: second.session), second)
        XCTAssertNil(PermissionBrowserIdentity.select([first, second], foregroundPID: 33, expectedSession: nil))
        XCTAssertNil(PermissionBrowserIdentity.select([first, second], foregroundPID: 22, expectedSession: "22:1.0"))
        XCTAssertNil(PermissionBrowserIdentity.select([second, second], foregroundPID: 22, expectedSession: second.session))
        XCTAssertEqual(PermissionBrowserIdentity.select([first], foregroundPID: nil, expectedSession: nil), first)
    }

    private func permissionIdentity(pid: pid_t, seconds: UInt64, date: Date? = nil) -> PermissionBrowserIdentity {
        var record = proc_bsdinfo(); record.pbi_pid = UInt32(pid); record.pbi_start_tvsec = seconds
        let birth = KernelProcessBirth(requestedPID: pid, record: record,
                                     bytesRead: Int32(MemoryLayout<proc_bsdinfo>.size))!
        return PermissionBrowserIdentity(process: ChromeProcessIdentity(birth: birth,
            applicationID: "com.google.Chrome", terminated: false, launchDate: date)!)
    }

    func testMissingLaunchDateForegroundWinsAndOldExpectedSessionCannotSelectOtherProcess() {
        let missingDate = permissionIdentity(pid: 11, seconds: 1)
        let other = permissionIdentity(pid: 22, seconds: 2, date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(PermissionBrowserIdentity.select([other, missingDate], foregroundPID: 11,
                                                       expectedSession: nil), missingDate)
        XCTAssertNil(PermissionBrowserIdentity.select([other, missingDate], foregroundPID: 11,
                                                     expectedSession: "11:1.0"))
        XCTAssertEqual(PermissionBrowserIdentity.select([other, missingDate], foregroundPID: 11,
                                                       expectedSession: "22:2.0"), other)
        let reusedPID = permissionIdentity(pid: 11, seconds: 3)
        XCTAssertNil(PermissionBrowserIdentity.select([other, reusedPID], foregroundPID: 11,
                                                     expectedSession: missingDate.session))
    }

    func testNativePermissionCodesNeverConflateDenialWithUnavailable() {
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(noErr), .granted)
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(OSStatus(errAEEventNotPermitted)), .denied)
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(OSStatus(errAEEventWouldRequireUserConsent)), .notRequested)
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(OSStatus(procNotFound)), .browserNotRunning)
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(-1), .unavailable)
    }
}
