import Foundation
import RiftletCore
import RiftletUI

/// Runs in a relocated packaged App without opening a window, reading the user's
/// screenshot directory, contacting Chrome or invoking a system consent dialog.
enum FirstUseSelfCheck {
    private actor UnexpectedPermissionProbe: AutomationPermissionChecking {
        var count = 0
        func check(askUserIfNeeded: Bool) -> AutomationPermissionState { count += 1; return .unavailable }
        func calls() -> Int { count }
    }

    static func run() async throws {
        try await SelectionFlowSelfCheck.run()
        var binding = DeferredChromeActivityBinding()
        let originalEpoch = UUID(), currentEpoch = UUID()
        binding.request(afterCaptureIn: originalEpoch)
        binding.request(afterCaptureIn: currentEpoch)
        guard !binding.take(afterCaptureIn: originalEpoch, isRunning: true),
              binding.take(afterCaptureIn: currentEpoch, isRunning: true),
              !binding.take(afterCaptureIn: currentEpoch, isRunning: true) else {
            throw RiftletError.invalidTransition
        }
        binding.request(afterCaptureIn: currentEpoch); binding.cancel()
        guard !binding.take(afterCaptureIn: currentEpoch, isRunning: true) else { throw RiftletError.invalidTransition }
        var trace = AcceptanceTraceDeduplicator<Int, String>(capacity: 2)
        guard trace.shouldRecord("visible", for: 1), !trace.shouldRecord("visible", for: 1),
              trace.shouldRecord("swallowed", for: 1), trace.shouldRecord("used", for: 2),
              trace.shouldRecord("new", for: 3), trace.count == 2,
              trace.shouldRecord("swallowed", for: 1), trace.count == 2 else {
            throw RiftletError.invalidTransition
        }
        let probe = UnexpectedPermissionProbe()
        let gate = AutomationPermissionGate(requiresChrome: false, checker: probe)
        let inspected = await gate.inspect(), requested = await gate.requestFromUserAction()
        guard inspected == .notNeeded, requested == .notNeeded, await probe.calls() == 0 else {
            throw RiftletError.invalidTransition
        }
        let suite = "Riftlet.FirstUseSelfCheck.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw RiftletError.invalidTransition }
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = FirstUsePreferences(defaults: defaults, modeName: "isolated")
        guard first.needsAutomaticPresentation else { throw RiftletError.invalidTransition }
        first.recordPresentation()
        guard !FirstUsePreferences(defaults: defaults, modeName: "isolated").needsAutomaticPresentation else {
            throw RiftletError.invalidTransition
        }
        let presentation = SetupPresentation(snapshot: .init(source: .notChecked, collection: .paused,
            isHidden: true, pendingCount: 1, attachment: .productionDisabled, permission: .denied,
            supportDescription: ProductStatus.supportDescription))
        guard !presentation.canRequestPermission, presentation.permissionText == nil,
              presentation.pendingText?.contains("待核实") == true,
              presentation.riftText.contains("隐藏"), presentation.collectionText.contains("暂停"),
              ReceiptPolicy().admittedProfiles.isEmpty, ReceiptPolicy().retrySafeProfiles.isEmpty else {
            throw RiftletError.invalidTransition
        }
    }
}
