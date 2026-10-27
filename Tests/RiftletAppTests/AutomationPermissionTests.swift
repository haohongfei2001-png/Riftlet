import XCTest
import Carbon
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

    func testMultipleChromeInstancesSelectExactOriginalSessionOrForegroundNeverFirst() {
        let first = PermissionBrowserIdentity(pid: 11, launched: Date(timeIntervalSince1970: 1))
        let second = PermissionBrowserIdentity(pid: 22, launched: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(PermissionBrowserIdentity.select([first, second], foregroundPID: 22, expectedSession: nil), second)
        XCTAssertEqual(PermissionBrowserIdentity.select([first, second], foregroundPID: 11, expectedSession: second.session), second)
        XCTAssertNil(PermissionBrowserIdentity.select([first, second], foregroundPID: 33, expectedSession: nil))
        XCTAssertNil(PermissionBrowserIdentity.select([first, second], foregroundPID: 22, expectedSession: "22:1.0"))
        XCTAssertNil(PermissionBrowserIdentity.select([second, second], foregroundPID: 22, expectedSession: second.session))
        XCTAssertEqual(PermissionBrowserIdentity.select([first], foregroundPID: nil, expectedSession: nil), first)
    }

    func testNativePermissionCodesNeverConflateDenialWithUnavailable() {
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(noErr), .granted)
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(OSStatus(errAEEventNotPermitted)), .denied)
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(OSStatus(errAEEventWouldRequireUserConsent)), .notRequested)
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(OSStatus(procNotFound)), .browserNotRunning)
        XCTAssertEqual(NativeAutomationPermissionChecker.classify(-1), .unavailable)
    }
}
