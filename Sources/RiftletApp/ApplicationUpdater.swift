import AppKit
import Sparkle
import RiftletUI

/// One controller per owning, normally launched App. Sparkle owns scheduling,
/// persistence, downloads and installation; this object projects its UI state.
@MainActor
final class ApplicationUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    private var offeredVersion: String?
    private var failure: String?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        do {
            try controller.updater.start()
        } catch {
            failure = error.localizedDescription
            return
        }
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.onChange() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.onChange() }
            }
        ]
    }

    var presentation: SettingsUpdaterPresentation {
        .init(canCheck: controller.updater.canCheckForUpdates,
              automaticChecks: observations.isEmpty ? nil : controller.updater.automaticallyChecksForUpdates,
              availableVersion: offeredVersion, failure: failure)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard !observations.isEmpty else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        onChange()
    }

    func check() {
        guard controller.updater.canCheckForUpdates else { return }
        failure = nil
        NSApp.activate(ignoringOtherApps: true) // An explicit action in this menu-bar App.
        controller.checkForUpdates(nil) // Also brings an existing Sparkle session forward.
        onChange()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false // Show a menu-bar reminder; the user's click opens Sparkle in focus.
    }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        offeredVersion = handleShowingUpdate ? nil : update.displayVersionString
        failure = nil
        onChange()
    }
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        offeredVersion = nil
        onChange()
    }
    func standardUserDriverWillFinishUpdateSession() {
        offeredVersion = nil
        onChange()
    }

    /// Sparkle uses CFBundleVersion for ordering. Riftlet's published marketing
    /// version must advance as well. This is a pre-download check on the signed feed.
    nonisolated static func isUpgrade(from currentVersion: String, build: String,
                                      to candidateVersion: String, build candidateBuild: String) -> Bool {
        func number(_ text: Substring) -> UInt? {
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
                  text.count == 1 || text.first != "0" else { return nil }
            return UInt(text)
        }
        func version(_ text: String) -> [UInt]? {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            let parsed = parts.compactMap(number)
            return parts.count == 3 && parsed.count == 3 ? parsed : nil
        }
        guard let old = version(currentVersion), let new = version(candidateVersion),
              let oldBuild = number(build[...]), let newBuild = number(candidateBuild[...]) else { return false }
        return old.lexicographicallyPrecedes(new) && newBuild > oldBuild
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard updateItem.signingValidationStatus == .succeeded else {
            throw NSError(domain: "com.riftlet.update", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "无法验证更新清单的签名。请前往 riftlet.com 查看正式版本。"])
        }
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              Self.isUpgrade(from: version, build: build, to: updateItem.displayVersionString, build: updateItem.versionString)
        else { throw NSError(domain: "com.riftlet.update", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "这个版本不能用于升级当前的 Riftlet。请前往 riftlet.com 查看正式版本。"]) }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let problem = error as NSError?
        if let problem, !(problem.domain == SUSparkleErrorDomain
            && [SUError.noUpdateError.rawValue, SUError.installationCanceledError.rawValue,
                SUError.installationAuthorizeLaterError.rawValue].map(Int.init).contains(problem.code)) {
            failure = problem.localizedDescription
        } else {
            failure = nil
        }
        onChange()
    }
}
