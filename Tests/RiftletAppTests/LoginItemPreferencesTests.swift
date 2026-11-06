import Foundation
import ServiceManagement
import XCTest
@testable import RiftletApp

/// Every executable service is fake. No test registers an App or opens Settings.
final class LoginItemPreferencesTests: XCTestCase {
    @MainActor private final class Gate {
        let entered = XCTestExpectation(description: "Synthetic unregister is pending")
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        var isSuspended: Bool { continuation != nil }
        func suspend() async {
            guard !released else { return }
            await withCheckedContinuation { continuation = $0; entered.fulfill() }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    @MainActor private final class Service: LoginItemService {
        var value: LoginItemStatus
        var readCount = 0
        var registerCount = 0
        var unregisterCount = 0
        var settingsCount = 0
        var registerNext: LoginItemStatus? = .enabled
        var unregisterNext: LoginItemStatus? = .notRegistered
        var registerError: Error?
        var unregisterError: Error?
        var unregisterGate: Gate?
        init(_ status: LoginItemStatus) { value = status }
        var status: LoginItemStatus { readCount += 1; return value }
        func register() throws {
            registerCount += 1
            if let registerNext { value = registerNext }
            if let registerError { throw registerError }
        }
        func unregister() async throws {
            unregisterCount += 1
            await unregisterGate?.suspend()
            if let unregisterNext { value = unregisterNext }
            if let unregisterError { throw unregisterError }
        }
        func openSystemSettings() { settingsCount += 1 }
    }

    private func error(_ code: Int) -> Error { NSError(domain: "SyntheticLoginItemTest", code: code) }

    func testSDKStatusMappingAndUnknownAreNotAnEnabledBoolean() {
        XCTAssertEqual(LoginItemStatus(systemStatus: .notRegistered), .notRegistered)
        XCTAssertEqual(LoginItemStatus(systemStatus: .enabled), .enabled)
        XCTAssertEqual(LoginItemStatus(systemStatus: .requiresApproval), .requiresApproval)
        XCTAssertEqual(LoginItemStatus(systemStatus: .notFound), .notFound)
        XCTAssertEqual(LoginItemStatus.notRegistered.switchValue, false)
        XCTAssertEqual(LoginItemStatus.enabled.launchAllowed, true)
        XCTAssertEqual(LoginItemStatus.requiresApproval.switchValue, true)
        XCTAssertEqual(LoginItemStatus.requiresApproval.launchAllowed, false)
        XCTAssertNil(LoginItemStatus.notFound.switchValue)
        XCTAssertNil(LoginItemStatus.unknown(42).launchAllowed)
    }

    @MainActor func testConstructionAndRefreshNeverRegisterOrOpenSettings() {
        let service = Service(.notRegistered); let owner = LoginItemPreferences(service: service)
        XCTAssertNil(owner.snapshot.status); XCTAssertEqual(service.readCount, 0)
        XCTAssertEqual(owner.refresh().status, .notRegistered)
        service.value = .enabled
        XCTAssertEqual(owner.refresh().status, .enabled)
        service.value = .requiresApproval
        XCTAssertEqual(owner.refresh().status, .requiresApproval)
        XCTAssertEqual(service.readCount, 3)
        XCTAssertEqual(service.registerCount + service.unregisterCount + service.settingsCount, 0)
    }

    @MainActor func testExplicitEnableReadsActualResultAndIsIdempotent() async {
        let service = Service(.notRegistered); let owner = LoginItemPreferences(service: service)
        let enabled = await owner.setEnabled(true)
        XCTAssertEqual(enabled.disposition, .satisfied); XCTAssertTrue(enabled.isSuccessful)
        XCTAssertTrue(enabled.serviceCalled); XCTAssertEqual(owner.snapshot.status, .enabled)
        XCTAssertEqual(service.readCount, 2, "Before and after the real command")
        let repeated = await owner.setEnabled(true)
        XCTAssertTrue(repeated.isSuccessful); XCTAssertFalse(repeated.serviceCalled)
        XCTAssertEqual(service.registerCount, 1); XCTAssertEqual(service.unregisterCount, 0)
    }

    @MainActor func testApprovalIsExistingRequestAndNeverClaimsLaunchOrSaveSuccess() async {
        let service = Service(.notRegistered); service.registerNext = .requiresApproval
        let owner = LoginItemPreferences(service: service)
        let pending = await owner.setEnabled(true)
        XCTAssertEqual(pending.disposition, .awaitingApproval)
        XCTAssertNil(pending.serviceError); XCTAssertFalse(pending.isSuccessful)
        XCTAssertEqual(owner.snapshot.switchValue, true); XCTAssertEqual(owner.snapshot.launchAllowed, false)
        let repeated = await owner.setEnabled(true)
        XCTAssertEqual(repeated.disposition, .awaitingApproval); XCTAssertFalse(repeated.serviceCalled)
        owner.refresh(); owner.refresh()
        XCTAssertEqual(service.registerCount, 1); XCTAssertEqual(service.settingsCount, 0)
    }

    @MainActor func testApprovalCanBeCancelledWithOneUnregister() async {
        let service = Service(.requiresApproval); let owner = LoginItemPreferences(service: service)
        let result = await owner.setEnabled(false)
        XCTAssertTrue(result.isSuccessful); XCTAssertEqual(result.status, .notRegistered)
        XCTAssertEqual(service.unregisterCount, 1); XCTAssertEqual(service.registerCount, 0)
        let repeated = await owner.setEnabled(false)
        XCTAssertTrue(repeated.isSuccessful); XCTAssertFalse(repeated.serviceCalled)
        XCTAssertEqual(service.unregisterCount, 1)
    }

    @MainActor func testUnregisterWaitsForCompletionAndDoesNotQueueOppositeOrDuplicateRequests() async {
        let service = Service(.enabled); let gate = Gate(); service.unregisterGate = gate
        let owner = LoginItemPreferences(service: service)
        defer { gate.release() }
        let disabling = Task { await owner.setEnabled(false) }
        await fulfillment(of: [gate.entered], timeout: 5)
        guard gate.isSuspended else { return }
        XCTAssertTrue(owner.snapshot.isBusy); XCTAssertEqual(owner.snapshot.inFlightTarget, false)
        XCTAssertEqual(owner.refresh().status, .enabled, "Waiting is not optimistic OFF")
        XCTAssertNil(owner.snapshot.lastCommand)
        let duplicate = await owner.setEnabled(false)
        let opposite = await owner.setEnabled(true)
        XCTAssertEqual(duplicate.disposition, .busy); XCTAssertEqual(opposite.disposition, .busy)
        XCTAssertEqual(service.unregisterCount, 1); XCTAssertEqual(service.registerCount, 0)
        gate.release()
        let result = await disabling.value
        XCTAssertTrue(result.isSuccessful); XCTAssertFalse(owner.snapshot.isBusy)
        XCTAssertEqual(owner.snapshot.status, .notRegistered)
        XCTAssertEqual(service.registerCount, 0, "The rejected opposite request was not replayed")
    }

    @MainActor func testRegisterFailurePreservesActualOffAndExplicitRetryUsesSameTarget() async {
        let service = Service(.notRegistered); service.registerNext = nil; service.registerError = error(101)
        let owner = LoginItemPreferences(service: service)
        let failed = await owner.setEnabled(true)
        XCTAssertEqual(failed.disposition, .notConfirmed); XCTAssertEqual(failed.serviceError, 101)
        XCTAssertEqual(owner.snapshot.status, .notRegistered)
        owner.refresh()
        XCTAssertEqual(owner.snapshot.lastCommand, failed); XCTAssertEqual(service.registerCount, 1)
        service.registerError = nil; service.registerNext = .enabled
        let retried = await owner.setEnabled(true)
        XCTAssertTrue(retried.isSuccessful); XCTAssertEqual(service.registerCount, 2)
        XCTAssertEqual(service.unregisterCount, 0)
    }

    @MainActor func testThrowAfterRegistrationDoesNotRollBackActualEnabledOrHideError() async {
        let service = Service(.notRegistered); service.registerError = error(102)
        let owner = LoginItemPreferences(service: service)
        let result = await owner.setEnabled(true)
        XCTAssertEqual(result.status, .enabled); XCTAssertEqual(result.disposition, .satisfied)
        XCTAssertEqual(result.serviceError, 102); XCTAssertFalse(result.isSuccessful)
        XCTAssertEqual(owner.snapshot.switchValue, true)
        let repeated = await owner.setEnabled(true)
        XCTAssertTrue(repeated.isSuccessful); XCTAssertFalse(repeated.serviceCalled)
        XCTAssertEqual(service.registerCount, 1)
    }

    @MainActor func testThrowWithApprovalStillProjectsApprovalSeparatelyFromCallError() async {
        let service = Service(.notRegistered); service.registerNext = .requiresApproval; service.registerError = error(103)
        let owner = LoginItemPreferences(service: service)
        let result = await owner.setEnabled(true)
        XCTAssertEqual(result.disposition, .awaitingApproval); XCTAssertEqual(result.serviceError, 103)
        XCTAssertFalse(result.isSuccessful); XCTAssertEqual(owner.snapshot.launchAllowed, false)
        owner.refresh()
        XCTAssertEqual(owner.snapshot.lastCommand, result); XCTAssertEqual(service.registerCount, 1)
    }

    @MainActor func testUnregisterFailureReadsActualEnabledAndPreservesItsTarget() async {
        let service = Service(.enabled); service.unregisterNext = nil; service.unregisterError = error(104)
        let owner = LoginItemPreferences(service: service)
        let failed = await owner.setEnabled(false)
        XCTAssertEqual(failed.target, false); XCTAssertEqual(failed.status, .enabled)
        XCTAssertEqual(failed.disposition, .notConfirmed); XCTAssertEqual(failed.serviceError, 104)
        service.unregisterError = nil; service.unregisterNext = .notRegistered
        let retried = await owner.setEnabled(false)
        XCTAssertTrue(retried.isSuccessful); XCTAssertEqual(service.unregisterCount, 2)
        XCTAssertEqual(service.registerCount, 0)
    }

    @MainActor func testThrowAfterUnregisterShowsActualOffWithoutInventingRollback() async {
        let service = Service(.enabled); service.unregisterError = error(105)
        let owner = LoginItemPreferences(service: service)
        let result = await owner.setEnabled(false)
        XCTAssertEqual(result.status, .notRegistered); XCTAssertEqual(result.serviceError, 105)
        XCTAssertFalse(result.isSuccessful); XCTAssertEqual(owner.snapshot.switchValue, false)
        let repeated = await owner.setEnabled(false)
        XCTAssertTrue(repeated.isSuccessful); XCTAssertFalse(repeated.serviceCalled)
        XCTAssertEqual(service.unregisterCount, 1)
    }

    @MainActor func testNormalReturnWithoutRequestedStatusIsNotSuccess() async {
        let service = Service(.notRegistered); service.registerNext = nil
        let owner = LoginItemPreferences(service: service)
        let registration = await owner.setEnabled(true)
        XCTAssertEqual(registration.disposition, .notConfirmed)
        XCTAssertNil(registration.serviceError); XCTAssertFalse(registration.isSuccessful)
        service.value = .enabled; service.unregisterNext = .requiresApproval
        let cancellation = await owner.setEnabled(false)
        XCTAssertEqual(cancellation.disposition, .notConfirmed)
        XCTAssertEqual(cancellation.status, .requiresApproval); XCTAssertFalse(cancellation.isSuccessful)
    }

    @MainActor func testMissingAndUnknownServiceNeverInventOffOrInvokeRegistration() async {
        for status in [LoginItemStatus.notFound, .unknown(91)] {
            let service = Service(status); let owner = LoginItemPreferences(service: service)
            let on = await owner.setEnabled(true); let off = await owner.setEnabled(false)
            XCTAssertEqual(on.disposition, .unavailable); XCTAssertEqual(off.disposition, .unavailable)
            XCTAssertNil(owner.snapshot.switchValue); XCTAssertNil(owner.snapshot.launchAllowed)
            XCTAssertEqual(service.registerCount + service.unregisterCount, 0)
            service.value = .notRegistered; owner.refresh()
            let recovered = await owner.setEnabled(true)
            XCTAssertTrue(recovered.isSuccessful); XCTAssertEqual(service.registerCount, 1)
        }
    }

    @MainActor func testExternalApprovalAndRevocationRefreshNeverReregister() async {
        let service = Service(.requiresApproval); let owner = LoginItemPreferences(service: service)
        let waiting = await owner.setEnabled(true)
        service.value = .enabled; owner.refresh()
        XCTAssertEqual(owner.snapshot.launchAllowed, true)
        XCTAssertEqual(owner.snapshot.lastCommand, waiting, "Last command is historical; current status is authoritative")
        service.value = .requiresApproval; owner.refresh()
        XCTAssertEqual(owner.snapshot.launchAllowed, false)
        XCTAssertEqual(service.registerCount + service.unregisterCount + service.settingsCount, 0)
    }

    @MainActor func testExplicitCommandChecksExternalStatusBeforeUsingCachedUIValue() async {
        let service = Service(.enabled); let owner = LoginItemPreferences(service: service)
        owner.refresh()
        service.value = .notRegistered
        let alreadyOff = await owner.setEnabled(false)
        XCTAssertTrue(alreadyOff.isSuccessful); XCTAssertFalse(alreadyOff.serviceCalled)
        service.value = .enabled
        let alreadyOn = await owner.setEnabled(true)
        XCTAssertTrue(alreadyOn.isSuccessful); XCTAssertFalse(alreadyOn.serviceCalled)
        XCTAssertEqual(service.registerCount + service.unregisterCount, 0)
        service.value = .notRegistered
        let newRequest = await owner.setEnabled(true)
        XCTAssertTrue(newRequest.serviceCalled); XCTAssertEqual(service.registerCount, 1)
    }

    @MainActor func testOnlyExplicitSettingsActionOpensTheFakePanel() async {
        let service = Service(.requiresApproval); let owner = LoginItemPreferences(service: service)
        owner.refresh(); await owner.setEnabled(true)
        XCTAssertEqual(service.settingsCount, 0)
        XCTAssertTrue(owner.openSystemSettings()); XCTAssertEqual(service.settingsCount, 1)
        XCTAssertEqual(owner.snapshot.status, .requiresApproval, "Opening settings is not approval")
        XCTAssertEqual(service.registerCount + service.unregisterCount, 0)
    }

    @MainActor func testUnavailableEnvironmentNeverEvenReadsInjectedService() async {
        for availability in [LoginItemAvailability.isolatedMode, .internalAcceptance, .testProcess, .notPackagedApplication] {
            let service = Service(.enabled); let owner = LoginItemPreferences(service: service, availability: availability)
            XCTAssertEqual(owner.refresh().availability, availability)
            let on = await owner.setEnabled(true); let off = await owner.setEnabled(false)
            XCTAssertEqual(on.disposition, .unavailable); XCTAssertEqual(off.disposition, .unavailable)
            XCTAssertFalse(owner.openSystemSettings()); XCTAssertNil(owner.snapshot.status)
            XCTAssertEqual(service.readCount + service.registerCount + service.unregisterCount + service.settingsCount, 0)
        }
    }

    @MainActor func testOnlyOrdinaryPackagedNonTestContextCanMakeLiveAdapter() {
        for mode in ApplicationMode.allCases {
            let value = LoginItemPreferences.availability(mode: mode, isInternalAcceptance: false,
                isPackagedApplication: true, isTestProcess: false)
            XCTAssertEqual(value, mode == .capture ? .available : .isolatedMode)
        }
        XCTAssertEqual(LoginItemPreferences.availability(mode: .capture, isInternalAcceptance: true,
            isPackagedApplication: true, isTestProcess: false), .internalAcceptance)
        XCTAssertEqual(LoginItemPreferences.availability(mode: .capture, isInternalAcceptance: false,
            isPackagedApplication: false, isTestProcess: false), .notPackagedApplication)
        XCTAssertEqual(LoginItemPreferences.availability(mode: .capture, isInternalAcceptance: false,
            isPackagedApplication: true, isTestProcess: true), .testProcess)
    }

    @MainActor func testPackagedIdentityRequiresMainAppExecutableAndBundleIdentity() {
        let app = URL(fileURLWithPath: "/synthetic/Renamed Riftlet.app", isDirectory: true)
        let binary = app.appendingPathComponent("Contents/MacOS/Riftlet")
        XCTAssertTrue(LoginItemPreferences.isPackagedApplication(bundleIdentifier: "com.riftlet.app",
            packageType: "APPL", bundleURL: app, executableURL: binary))
        XCTAssertFalse(LoginItemPreferences.isPackagedApplication(bundleIdentifier: "com.riftlet.app.tests",
            packageType: "APPL", bundleURL: app, executableURL: binary))
        XCTAssertFalse(LoginItemPreferences.isPackagedApplication(bundleIdentifier: "com.riftlet.app",
            packageType: "BNDL", bundleURL: app, executableURL: binary))
        XCTAssertFalse(LoginItemPreferences.isPackagedApplication(bundleIdentifier: "com.riftlet.app",
            packageType: "APPL", bundleURL: app, executableURL: URL(fileURLWithPath: "/synthetic/Riftlet")))
        XCTAssertFalse(LoginItemPreferences.isPackagedApplication(bundleIdentifier: "com.riftlet.app",
            packageType: "APPL", bundleURL: app.deletingPathExtension(), executableURL: binary))
    }

    @MainActor func testLiveFactoryInXCTestStaysUnavailableWithoutCreatingSystemService() async {
        // Actual Bundle/process facts fail before the private live adapter exists.
        let owner = LoginItemPreferences.live(mode: .capture)
        XCTAssertNotEqual(owner.snapshot.availability, .available)
        XCTAssertNil(owner.refresh().status)
        let result = await owner.setEnabled(true)
        XCTAssertEqual(result.disposition, .unavailable); XCTAssertFalse(result.serviceCalled)
        XCTAssertFalse(owner.openSystemSettings())
    }
}
