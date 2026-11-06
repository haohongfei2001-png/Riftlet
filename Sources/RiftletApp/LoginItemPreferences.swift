import Foundation
import ServiceManagement

/// System facts, not a second persisted launch-at-login preference.
enum LoginItemStatus: Equatable, Sendable {
    case notRegistered, enabled, requiresApproval, notFound, unknown(Int)

    init(systemStatus: SMAppService.Status) {
        switch systemStatus {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .unknown(systemStatus.rawValue)
        }
    }

    /// Approval-pending is an existing request, but is not allowed to launch.
    var switchValue: Bool? {
        switch self {
        case .notRegistered: return false
        case .enabled, .requiresApproval: return true
        case .notFound, .unknown: return nil
        }
    }
    var launchAllowed: Bool? {
        switch self {
        case .enabled: return true
        case .notRegistered, .requiresApproval: return false
        case .notFound, .unknown: return nil
        }
    }
}

enum LoginItemAvailability: Equatable, Sendable {
    case available
    case isolatedMode, internalAcceptance, testProcess, notPackagedApplication
}

enum LoginItemDisposition: Equatable, Sendable {
    /// The read-back status satisfies this target; check serviceError separately.
    case satisfied, awaitingApproval, notConfirmed, unavailable, busy
}

struct LoginItemCommandResult: Equatable, Sendable {
    let target: Bool
    let status: LoginItemStatus?
    let disposition: LoginItemDisposition
    /// NSError code only; no path-bearing localized description or userInfo.
    let serviceError: Int?
    let serviceCalled: Bool
    var isSuccessful: Bool { disposition == .satisfied && serviceError == nil }
}

struct LoginItemSnapshot: Equatable, Sendable {
    let revision: UInt64
    let availability: LoginItemAvailability
    let status: LoginItemStatus?
    let inFlightTarget: Bool?
    let lastCommand: LoginItemCommandResult?
    var isBusy: Bool { inFlightTarget != nil }
    var switchValue: Bool? { status?.switchValue }
    var launchAllowed: Bool? { status?.launchAllowed }
}

@MainActor protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() async throws
    func openSystemSettings()
}

/// All writes originate in an explicit setEnabled call.
/// Read/refresh never register, retry, open settings, or write a local Boolean.
@MainActor final class LoginItemPreferences {
    var onChange: (@MainActor (LoginItemSnapshot) -> Void)?
    private let service: (any LoginItemService)?
    private let availability: LoginItemAvailability
    private var status: LoginItemStatus?
    private var revision: UInt64 = 0
    private var inFlightTarget: Bool?
    private var lastCommand: LoginItemCommandResult?

    /// Injection is for host composition and synthetic adapters. The concrete
    /// SMAppService adapter is private and only constructed by live(mode:).
    init(service: any LoginItemService, availability: LoginItemAvailability = .available) {
        self.availability = availability
        self.service = availability == .available ? service : nil
    }

    private init(unavailable: LoginItemAvailability) {
        availability = unavailable; service = nil
    }

    static func live(mode: ApplicationMode) -> LoginItemPreferences {
        let bundle = Bundle.main
        let arguments = CommandLine.arguments
        let environment = ProcessInfo.processInfo.environment
        let testProcess = NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest.XCTestCase") != nil ||
            ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"].contains { environment[$0] != nil } ||
            arguments.contains { $0.hasSuffix(".xctest") || $0.hasSuffix("-self-check") || $0 == "--self-check" || $0 == "--ordinary-build-info" }
        let actualMode = try? ApplicationMode.resolve(arguments)
        let availability = availability(mode: actualMode == mode ? mode : .simulation,
            isInternalAcceptance: OrdinaryCaptureConfiguration.isInternalAcceptance,
            isPackagedApplication: isPackagedApplication(bundleIdentifier: bundle.bundleIdentifier,
                packageType: bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String,
                bundleURL: bundle.bundleURL, executableURL: bundle.executableURL),
            isTestProcess: testProcess)
        guard availability == .available else { return .init(unavailable: availability) }
        return .init(service: MainAppLoginItemService())
    }

    /// Pure eligibility projection, separately testable without SMAppService.
    static func availability(mode: ApplicationMode, isInternalAcceptance: Bool,
                             isPackagedApplication: Bool, isTestProcess: Bool) -> LoginItemAvailability {
        if isTestProcess { return .testProcess }
        if isInternalAcceptance { return .internalAcceptance }
        if mode != .capture { return .isolatedMode }
        if !isPackagedApplication { return .notPackagedApplication }
        return .available
    }

    static func isPackagedApplication(bundleIdentifier: String?, packageType: String?,
                                      bundleURL: URL, executableURL: URL?) -> Bool {
        guard bundleIdentifier == "com.riftlet.app", packageType == "APPL", bundleURL.isFileURL,
              bundleURL.pathExtension.lowercased() == "app", let executableURL, executableURL.isFileURL else { return false }
        return executableURL.standardizedFileURL == bundleURL.standardizedFileURL
            .appendingPathComponent("Contents/MacOS/Riftlet", isDirectory: false)
    }

    var snapshot: LoginItemSnapshot {
        .init(revision: revision, availability: availability, status: status,
              inFlightTarget: inFlightTarget, lastCommand: lastCommand)
    }

    @discardableResult func refresh() -> LoginItemSnapshot {
        if let service { status = service.status; revision += 1 }
        // A status refresh is not an acknowledgement of an earlier call error.
        onChange?(snapshot)
        return snapshot
    }

    @discardableResult func setEnabled(_ target: Bool) async -> LoginItemCommandResult {
        guard let service else { return record(target, disposition: .unavailable, called: false) }
        guard inFlightTarget == nil else {
            return .init(target: target, status: status, disposition: .busy, serviceError: nil, serviceCalled: false)
        }
        refresh() // External System Settings changes win over the last UI snapshot.
        switch status {
        case .enabled? where target, .notRegistered? where !target:
            return record(target, disposition: .satisfied, called: false)
        case .requiresApproval? where target:
            return record(target, disposition: .awaitingApproval, called: false)
        case .notFound?, .unknown?, nil:
            return record(target, disposition: .unavailable, called: false)
        default: break
        }
        inFlightTarget = target; revision += 1; onChange?(snapshot)
        var errorCode: Int?
        do {
            if target { try service.register() }
            else { try await service.unregister() }
        } catch { errorCode = (error as NSError).code }
        // Even a throwing call can have changed the system state. Never roll back
        // the display speculatively, and never infer enabled from a normal return.
        refresh()
        inFlightTarget = nil
        let disposition: LoginItemDisposition
        switch status {
        case .enabled? where target, .notRegistered? where !target: disposition = .satisfied
        case .requiresApproval? where target: disposition = .awaitingApproval
        case .notFound?, .unknown?, nil: disposition = .unavailable
        default: disposition = .notConfirmed
        }
        return record(target, disposition: disposition, error: errorCode, called: true)
    }

    /// The future dedicated button may call this. No lifecycle/read/write path
    /// calls it implicitly; returning true means only that the action was sent.
    @discardableResult func openSystemSettings() -> Bool {
        guard let service else { return false }
        service.openSystemSettings(); return true
    }

    private func record(_ target: Bool, disposition: LoginItemDisposition, error: Int? = nil,
                        called: Bool) -> LoginItemCommandResult {
        let result = LoginItemCommandResult(target: target, status: status, disposition: disposition,
                                           serviceError: error, serviceCalled: called)
        lastCommand = result; revision += 1; onChange?(snapshot); return result
    }
}

/// This type is inaccessible to tests/other hosts. Tests inject a fake instead
/// of changing a real login item.
@MainActor private final class MainAppLoginItemService: LoginItemService {
    private let service = SMAppService.mainApp
    var status: LoginItemStatus { .init(systemStatus: service.status) }
    func register() throws { try service.register() }

    func unregister() async throws {
        // Explicitly use the completion API, not the similarly named synchronous
        // overload. The SDK documents its callback on a background dispatch queue.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            service.unregister(completionHandler: { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
