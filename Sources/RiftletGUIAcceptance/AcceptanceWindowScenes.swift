import AppKit
import RiftletCore
import RiftletUI
import RiftletFeedback
import RiftletFeedbackUI

/// Existing product windows over helper-only data. The helper has no queue
/// store, capture service, browser or network-capable feedback transport.
@MainActor
final class AcceptanceWindowScenes {
    private var setup: RiftSetupController?
    private var history: RiftHistoryController?
    private var motion: ArrivalMotionSettingsController?
    private var feedback: FeedbackWindowController?
    private var feedbackLoad: Task<Void, Never>?
    private let mediaRoot: URL
    private let fixtures: [AssetRecord]
    private let record: (String, [String: Any]) -> Void
    private var settingsFixture = RiftSettingsSnapshot(entryAvailable: true)
    private var historyFixtures: [RiftHistoryEntry] = []

    private var requestedSettingsSection: RiftSettingsSection? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--visual-settings-section"), index + 1 < args.count,
              let raw = Int(args[index + 1]) else { return nil }
        return RiftSettingsSection(rawValue: raw)
    }

    init(mediaRoot: URL, fixtures: [AssetRecord], record: @escaping (String, [String: Any]) -> Void) {
        self.mediaRoot = mediaRoot; self.fixtures = fixtures; self.record = record
    }

    func show(_ name: String) {
        switch name {
        case "setup", "settings":
            if let setup {
                if name == "setup" { setup.showOnboarding() } else { setup.show(section: requestedSettingsSection) }
                captureWindowGeometry(name); return
            }
            let controller = RiftSetupController(
                onRecheck: { [weak self] in self?.action("recheck") },
                onOpenSource: { [weak self] in self?.action("source") },
                onPermission: { [weak self] in self?.action("permission") },
                onDismiss: { [weak self] in self?.action("dismiss") },
                onChooseSourceAccess: { [weak self] in self?.action("sourceAccess") },
                onToggleHidden: { [weak self] in self?.action("hide") },
                onToggleCollection: { [weak self] in self?.action("pause") },
                onOpenHistory: { [weak self] in self?.show("history") },
                onOpenEntrySettings: { [weak self] in self?.action("entrySettings") },
                onOpenDisplaySettings: { [weak self] in self?.show("motion") },
                onOpenFeedback: { [weak self] in self?.show("feedback") },
                onSettingsChange: { [weak self] change in
                    guard let self else { return RiftSettingsSnapshot() }
                    switch change {
                    case .entryEnabled(let enabled): self.settingsFixture.entryEnabled = enabled
                    case .defaultCaptureMode(let mode): self.settingsFixture.defaultCaptureMode = mode
                    case .arrivalMode(let mode):
                        self.settingsFixture.arrivalMode = mode; self.settingsFixture.hasArrivalSelection = true
                    case .preferredDisplay(let id): self.settingsFixture.preferredDisplayID = id
                    case .archiveAfterHours(let hours): self.settingsFixture.archiveAfterHours = hours
                    }
                    self.action("inMemorySettingsChange")
                    return self.settingsFixture
                })
            let localOnboarding = CommandLine.arguments.contains("--visual-local-onboarding")
            settingsFixture.entryAvailable = !localOnboarding
            controller.update(snapshot: SetupSnapshot(
                sourceLocation: "合成验收素材（不读取系统截图位置）", source: .notApplicable,
                collection: .stopped, visibleCount: 3, pendingCount: 1,
                attachment: localOnboarding ? .productionDisabled : .offlineSimulation, permission: .notNeeded,
                storage: .measured(bytes: UInt64(fixtures.reduce(Int64(0)) { $0 + $1.image.byteCount }), complete: true),
                supportDescription: "仅合成 AppKit 呈现验收；没有读取截图、检查权限、连接浏览器或授予生产准入。"))
            settingsFixture.displays = NSScreen.screens.enumerated().compactMap { index, screen in
                guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
                return RiftSettingsDisplay(id: id, name: "原生验收显示器 \(index + 1)")
            }
            controller.updateSettings(settingsFixture)
            setup = controller
            if name == "setup" { controller.showOnboarding() } else { controller.show(section: requestedSettingsSection) }
            captureWindowGeometry(name)
        case "history":
            if let history { history.show(); captureWindowGeometry(name); return }
            let controller = RiftHistoryController(mediaDirectory: mediaRoot,
                onRestore: { [weak self] _ in self?.action("historyRestore") },
                onRemove: { [weak self] _ in self?.action("historyRemove") },
                onReveal: { [weak self] _ in self?.action("historyReveal") })
            let entries = fixtures.prefix(8).enumerated().map { index, fixture in
                let state: QueueStatus = index == 1 ? .unknown : (index == 2 ? .used : .pending)
                let visibility: QueueVisibility = index == 1 || index == 2 ? .swallowed
                    : (index == 3 ? .archived : (index == 4 ? .removed : .visible))
                let reason: QueueVisibilityReason = index == 1 || index == 2 ? .uploadStarted
                    : (index == 3 ? .automaticArchive : (index == 4 ? .userRemoved : .capture))
                let projection = AssetRecord(image: fixture.image, sequence: fixture.sequence, status: state,
                    visibility: visibility, visibilityRevision: visibility == .visible ? 0 : 1,
                    visibilityReason: reason)
                return RiftHistoryEntry(record: projection, canRestore: visibility == .archived || visibility == .removed,
                    detail: "合成呈现样本。没有真实操作、上传回执或数据库状态；此窗口只验证原生视觉与可访问性。")
            }
            historyFixtures = entries
            history = controller; controller.update(entries: entries); controller.show()
            captureWindowGeometry(name)
        case "motion":
            if let motion { motion.show(); captureWindowGeometry(name); return }
            let controller = ArrivalMotionSettingsController(mode: .none, hasExplicitSelection: false) { [weak self] _ in
                self?.action("motionChoice") // The product preview updates, but no user preference is persisted.
            }
            motion = controller; controller.show(); captureWindowGeometry(name)
        case "feedback":
            if let feedback { feedback.show(); captureWindowGeometry(name); return }
            guard feedbackLoad == nil else { return }
            feedbackLoad?.cancel()
            feedbackLoad = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    // This fresh directory belongs to this invocation's helper
                    // fixtures. It never opens an existing user feedback root.
                    let store = try FeedbackStore(directory: self.mediaRoot.appendingPathComponent("feedback-fixture", isDirectory: true))
                    try await store.saveDraft(FeedbackDraft(kind: .suggestion,
                        text: "合成界面验收：希望缩略图的等待说明更容易看清。此文字仅用于检查原生反馈窗口；不会联网发送。", revision: 1))
                    try Task.checkCancellation()
                    let diagnostics = FeedbackDiagnostics()
                    let engine = FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: DisabledFeedbackTransport())
                    let controller = FeedbackWindowController(engine: engine, diagnostics: diagnostics, appVersion: "0.1.0", demo: true)
                    self.feedback = controller; controller.show(); self.captureWindowGeometry(name)
                    self.feedbackLoad = nil
                } catch is CancellationError { }
                catch {
                    self.feedbackLoad = nil
                    self.record("visual_window_unavailable", ["name": name, "syntheticOnly": true, "networkEnabled": false])
                }
            }
        default:
            record("visual_window_unavailable", ["reason": "unknownScene", "syntheticOnly": true])
        }
    }

    func cancel() { feedbackLoad?.cancel(); feedbackLoad = nil }

    /// Helper-only software navigation through the product's existing buttons.
    /// It neither requests permissions nor advances the final onboarding action.
    func prepareEvidencePage() throws {
        let args = CommandLine.arguments
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        if let index = args.firstIndex(of: "--visual-history-state"), index + 1 < args.count {
            let state = args[index + 1]
            let sorted = HistoryPresentation.matching(historyFixtures)
            guard state == "archived" || state == "unknown", let history,
                  let row = sorted.firstIndex(where: {
                      state == "archived" ? $0.record.visibility == .archived : $0.record.status == .unknown
                  }),
                  let table = NSApp.windows.filter(\.isVisible).compactMap(\.contentView)
                    .flatMap(descendants).compactMap({ $0 as? NSTableView }).first(where: { $0.delegate === history }),
                  table.numberOfRows == sorted.count else { throw NativeVisualEvidence.Failure.missingWindow }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            guard table.selectedRow == row else { throw NativeVisualEvidence.Failure.missingWindow }
            record("native_evidence_history_selection", ["fixtureState": state,
                "fixtureSequence": sorted[row].record.sequence, "softwareSelection": true, "physical": false])
        }
        guard let index = args.firstIndex(of: "--visual-onboarding-page"), index + 1 < args.count,
              let page = Int(args[index + 1]), (0...2).contains(page),
              let window = NSApp.windows.first(where: { $0.identifier == RiftSetupController.windowIdentifier }),
              let content = window.contentView else { return }
        for _ in 0..<page {
            descendants(content).compactMap { $0 as? NSButton }
                .first(where: { $0.identifier?.rawValue == "setup.next" })?.performClick(nil)
        }
        captureWindowGeometry("setup-page-\(page)")
    }

    private func action(_ name: String) {
        record("visual_window_action", ["action": name, "syntheticOnly": true,
            "permissionRequested": false, "browserAccess": false, "queueMutation": false, "networkEnabled": false])
    }

    private func captureWindowGeometry(_ name: String) {
        // Only windows in this helper process are inspected. Window titles and
        // user text are not logged. AppKit frames do not assert rendered pixels.
        let windows = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
        // Acceptance-only privacy layering. This does not change the product
        // controller or certify its ordinary cross-application window order.
        for window in windows {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            window.orderFrontRegardless()
        }
        record("visual_window_shown", ["name": name, "syntheticOnly": true, "networkEnabled": false,
            "fixtureLayerIsolation": true,
            "windows": windows.map { window in
                ["number": window.windowNumber, "x": window.frame.minX, "y": window.frame.minY,
                 "width": window.frame.width, "height": window.frame.height,
                 "backingScaleFactor": window.backingScaleFactor] as [String: Any]
            }])
    }
}
