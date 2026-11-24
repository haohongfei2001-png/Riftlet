import Foundation
import RiftletCore

/// Presentation only. Never stores permission, upload admission or queue state.
struct FirstUsePreferences {
    private let defaults: UserDefaults
    private let presentedKey: String
    private let progressKey: String

    init(defaults: UserDefaults = .standard, modeName: String) {
        self.defaults = defaults
        presentedKey = "Riftlet.firstUse.presented.v1.\(modeName)"
        progressKey = "Riftlet.firstUse.setup.v2.\(modeName)"
    }

    var hasPresented: Bool { defaults.bool(forKey: presentedKey) }

    var needsAutomaticPresentation: Bool {
        !hasPresented && defaults.object(forKey: progressKey) == nil
    }

    var awaitingFirstAttachment: Bool {
        defaults.string(forKey: progressKey) == "awaitingAttachment"
    }

    /// Mark when the window is actually presented, not on a background refresh.
    /// Closing it is not consent to any system permission or external input.
    func recordPresentation() {
        guard needsAutomaticPresentation else { return }
        defaults.set("awaitingAttachment", forKey: progressKey)
        defaults.set(true, forKey: presentedKey)
    }

    func deferPresentation() {
        guard awaitingFirstAttachment else { return }
        defaults.set("deferred", forKey: progressKey)
    }

    /// The caller reads the original operation's admitted START from QueueStore.
    @discardableResult
    func finishAfterFirstAttachment(_ start: TransferReceipt?, clickedBinding: UUID) -> Bool {
        guard awaitingFirstAttachment, let start, start.target.clickBindingID == clickedBinding,
              start.outcome == .uploadStarted,
              start.uploadStartEvidence?.signal == .attachmentAccepted,
              start.belongsToOriginalDraft, !start.hasError else { return false }
        defaults.set("completed", forKey: progressKey)
        return true
    }
}
