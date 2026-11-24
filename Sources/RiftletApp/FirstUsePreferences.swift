import Foundation
import RiftletCore

/// Presentation only. Never stores permission, upload admission or queue state.
struct FirstUsePreferences {
    struct Click: Equatable, Codable {
        let assetID: UUID
        let bindingID: UUID
    }

    static let clickLimit = 16
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
        defaults.string(forKey: progressKey) == "awaitingAttachment" || !pendingClicks.isEmpty
    }

    var pendingClicks: [Click] {
        guard let data = defaults.data(forKey: progressKey),
              let clicks = try? PropertyListDecoder().decode([Click].self, from: data) else { return [] }
        return Array(clicks.suffix(Self.clickLimit))
    }

    /// One preference owns the phase and its candidates. Completing or skipping
    /// atomically replaces the candidates with the terminal phase.
    func recordClick(assetID: UUID, bindingID: UUID) {
        guard awaitingFirstAttachment else { return }
        let click = Click(assetID: assetID, bindingID: bindingID)
        var clicks = pendingClicks
        guard !clicks.contains(click) else { return }
        clicks.append(click)
        guard let data = try? PropertyListEncoder().encode(Array(clicks.suffix(Self.clickLimit))) else { return }
        defaults.set(data, forKey: progressKey)
        // Finish writing the identity before the transfer can persist its START.
        defaults.synchronize()
    }

    /// Read only the assets selected during first use, including swallowed ones
    /// that aren't part of the tray snapshot after relaunch.
    @MainActor func reconcileFirstAttachment(in store: QueueStore) async -> Bool {
        for click in pendingClicks {
            guard let asset = try? await store.asset(id: click.assetID),
                  let id = asset.activeOperationID,
                  let start = try? await store.uploadStartReceipt(for: id),
                  start.operationID == id, start.assetID == click.assetID,
                  finishAfterFirstAttachment(start, clickedBinding: click.bindingID) else { continue }
            return true
        }
        return false
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
        defaults.synchronize()
    }

    /// The caller reads the original operation's admitted START from QueueStore.
    @discardableResult
    func finishAfterFirstAttachment(_ start: TransferReceipt?, clickedBinding: UUID) -> Bool {
        guard let start, start.target.clickBindingID == clickedBinding,
              pendingClicks.contains(Click(assetID: start.assetID, bindingID: clickedBinding)),
              start.outcome == .uploadStarted,
              start.uploadStartEvidence?.signal == .attachmentAccepted,
              start.belongsToOriginalDraft, !start.hasError else { return false }
        defaults.set("completed", forKey: progressKey)
        defaults.synchronize()
        return true
    }
}
