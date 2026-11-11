import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Darwin
import RiftletCore
import RiftletCapture
import RiftletUI
import RiftletAdapters
import RiftletFeedback

@main
enum RiftletMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--ordinary-build-info") {
            let value: [String: Any] = ["internalAcceptance": OrdinaryCaptureConfiguration.isInternalAcceptance,
                "mode": "capture", "dataDirectory": OrdinaryCaptureConfiguration.dataDirectoryName,
                "input": OrdinaryCaptureConfiguration.admission.allowsInput,
                "start": OrdinaryCaptureConfiguration.admission.allowsStart,
                "completion": OrdinaryCaptureConfiguration.admission.allowsCompletion,
                "builtInUpload": OrdinaryCaptureConfiguration.admission.productOrigins.contains(.applicationScreenshot),
                "safeRetry": false,
                "continuation": !OrdinaryCaptureConfiguration.admission.receiptPolicy.continuationProfiles.isEmpty]
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        if CommandLine.arguments.contains("--system-screenshot-candidate-self-check") {
            Task {
                do {
                    try await SystemScreenshotCandidateSelfCheck.run()
                    print("RIFTLET_SYSTEM_SCREENSHOT_CANDIDATE_SELF_CHECK_PASS: original-byte import, two independent software inputs and STARTs, stop after START, durable new-operation registration, legacy UNKNOWN unchanged, read-only restart; GENERATED_FIXTURE; CHROME_NOT_RUN; SYSTEM_SCREENSHOT_NOT_RUN; GUI_NOT_RUN")
                    exit(0)
                } catch {
                    let detail = (error as? SystemScreenshotCandidateSelfCheck.Failure)?.rawValue
                        ?? "\(String(reflecting: type(of: error))) code=\((error as NSError).code)"
                    fputs("RIFTLET_SYSTEM_SCREENSHOT_CANDIDATE_SELF_CHECK_FAIL: \(detail)\n", stderr)
                    exit(1)
                }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--first-use-self-check") {
            Task {
                do {
                    try await FirstUseSelfCheck.run()
                    print("RIFTLET_FIRST_USE_SELF_CHECK_PASS: presentation persistence, disabled-production permission isolation, honest status; PERMISSIONS_NOT_REQUESTED; GUI_NOT_RUN")
                    exit(0)
                } catch { fputs("RIFTLET_FIRST_USE_SELF_CHECK_FAIL\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--self-check") {
            Task {
                do { try await SelfCheck.run(); print("RIFTLET_SELF_CHECK_PASS: private import, durable upload-start visibility, delayed synthetic completion, restart"); exit(0) }
                catch { fputs("RIFTLET_SELF_CHECK_FAIL: \(error)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--web-acceptance-self-check") {
            Task {
                do {
                    try await WebAcceptanceSelfCheck.run()
                    print("RIFTLET_WEB_ACCEPTANCE_SELF_CHECK_PASS: bundled page source, synthetic-only start/completion policy, isolated modes; CHROME_NOT_RUN; GUI_NOT_RUN")
                    exit(0)
                } catch { fputs("RIFTLET_WEB_ACCEPTANCE_SELF_CHECK_FAIL: \(error)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        do {
            let mode = try ApplicationMode.resolve(CommandLine.arguments)
            // AppKit owns the main run loop. Do not hold a Swift executor job
            // across run(): delegate Tasks must be able to initialize the app.
            runApplication(mode: mode)
        } catch { fputs("Riftlet mode conflict; choose one explicit development mode.\n", stderr); exit(2) }
    }

    @MainActor private static func runApplication(mode: ApplicationMode) {
        let application = NSApplication.shared
        let delegate = ApplicationController(mode: mode)
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class ApplicationController: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSOpenSavePanelDelegate {
    private lazy var feedback = FeedbackHost(modeDirectory: mode.directoryName, isolatedRoot: reviewEnvironment?.root)
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var storageLine: NSMenuItem?
    private var storageMeasurement: Task<Void, Never>?
    private var settingsHost: SettingsProductHost?
    private var settingsOwnerRevision: UInt64 = 0
    private var setupStorage: SetupStorageState = .notMeasured
    private var setupIssue: SetupIssue?
    private var visibilitySettingFailed = false
    private var collectionSettingFailed = false
    private var captureStatus: CaptureStatusSnapshot?
    private var captureDiagnostic: CaptureDiagnostic?
    private var detectedSource: URL?
    private var pendingResultCount = 0
    private var initialized = false
    private var captureControl = CaptureControlGate()
    private var recheckTask: Task<Void, Never>?
    private var collectionChangePending = false
    private var captureControlBusy: Bool { captureControl.isBusy || collectionChangePending }
    private var canChangeCollection: Bool {
        mode.collectsSystemScreenshots && initialized && !collectionChangePending && captureControl.acceptsCollectionIntent
    }
    private var requestingPermission = false
    private var automationPermission: AutomationPermissionState = .notNeeded
    private var permissionPublication = AutomationPermissionPublication()
    private var attachmentObservationStarted = false
    private var attachmentObservationStarting = false
    private var terminating = false
    private var terminationPreparationPending = false
    private var terminationApproved = false
    private var permissionResumer: PassivePermissionResume?
    private var permissionActivationObserver: NSObjectProtocol?
    private var permissionWakeObserver: NSObjectProtocol?
    private var reviewEnvironment: SettingsReviewEnvironment?
    private lazy var captureLocation = reviewEnvironment?.captureLocation ?? SystemCaptureLocationProvider()
    private lazy var firstUse = FirstUsePreferences(defaults: reviewEnvironment?.defaults ?? .standard, modeName: mode.directoryName)
    private lazy var folderAccess = ScreenshotFolderAccess(defaults: reviewEnvironment?.defaults ?? .standard, modeName: mode.directoryName)
    private var folderNeedingSelection: URL?
    private var folderShownInPicker: URL?
    private var permissionGate: AutomationPermissionGate { .init(requiresChrome: mode.usesWebAdapter) }
    private var hideItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var archiveItem: NSMenuItem?
    private var store: QueueStore?
    private var capture: CaptureService?
    private var sourceBinding: CaptureSourceBinding?
    private var transfer: TransferCoordinator?
    private var rift: RiftPanelController?
    private var screenshotEntry: ScreenshotEntryHost?
    private var arrivalPreferences: ArrivalMotionPreferences?
    private var arrivalCapture: ArrivalCaptureBridge?
    private var root: URL!
    private var visibleIDs = Set<UUID>()
    private var refreshRunning = false
    private var refreshRequested = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var historyGeneration: UInt64 = 0
    private var history: RiftHistoryController?
    // Root ownership is established before installSetup first reads this owner.
    private lazy var historyDisplayPreferences = HistoryDisplayPreferences.make(mode: mode, root: root)
    private var historyOffset = 0
    private var userHidden = false
    private var captureIsPaused = false
    private var changingHidden = false
    private var lifecycleSettings = LifecycleSettings()
    private let interactionFence = QueueInteractionFence()
    private var archiveTask: Task<Void, Never>?
    private var archiveWakeObserver: NSObjectProtocol?
    private var oldestArchiveCandidate: Date?
    private var archiveNotBefore: TimeInterval = 0
    private var archiveClock: (wall: Date, uptime: TimeInterval)?
    private var completionWatch: Task<Void, Never>?
    private var originalRecoveryIDs: [UUID]?
    private var originalRecoveryTask: Task<Void, Never>?
    private var startupCompletedIDs = Set<UUID>()
    private var clickAdapter: WebAttachmentAdapter?
    private var lastForegroundSession: String?
    private var diagnosticTrace: BoundedDiagnosticTrace?
    private var visibilityTrace = AcceptanceTraceDeduplicator<UUID, [String]>()
    private var readyTrace = AcceptanceTraceDeduplicator<UUID, [String]>()
    private var frozenPress: (id: UUID, eventUptime: TimeInterval, target: Task<TargetLease, Error>)?
    private var pendingClickTargets: [UUID: Task<TargetLease, Error>] = [:]
    private let selectionAuthority = SelectionAuthority()
    private let originalReceiverPermission = OriginalReceiverPermission()
    private let selectionSubmissions = SelectionSubmissionQueue()
    private var selectionUIOwners: [UUID: UUID] = [:]
    private var preparedFeedbackOperations: [UUID: UUID] = [:]
    private var permissionSession = UUID()
    private var watchedCompletions = Set<UUID>()
    private var observationBackoff: [UUID: (failures: Int, next: Date)] = [:]
    private var instanceOwnership: ApplicationInstanceOwnership?
    private let mode: ApplicationMode
    private var simulation: Bool { mode == .simulation }

    init(mode: ApplicationMode) { self.mode = mode; super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Acquire the mode before Feedback's detached initialization can claim
        // its own lock. A losing instance must not create UI, mutate first-use
        // state, open a sidecar, or pump an already queued feedback report.
        do {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            if mode == .settingsReview {
                let environment = SettingsReviewEnvironment(identifier: try SettingsReviewEnvironment.identifier(in: CommandLine.arguments), applicationSupport: base)
                try environment.prepare(); reviewEnvironment = environment
            }
            let owner = try ApplicationInstanceOwnership(root: reviewEnvironment?.root ?? base.appendingPathComponent(mode.directoryName, isDirectory: true))
            try reviewEnvironment?.prepareFixtures()
            instanceOwnership = owner; root = owner.root
            if mode.usesWebAdapter, CommandLine.arguments.contains("--acceptance-trace") {
                diagnosticTrace = BoundedDiagnosticTrace(enabled: true,
                    directory: owner.root.appendingPathComponent("diagnostics", isDirectory: true))
            }
        } catch {
            fputs("Riftlet could not acquire its data-directory ownership; no services were started.\n", stderr)
            NSApp.terminate(nil)
            return
        }
        installMenu()
        _ = feedback // Independent sidecar initializes off the screenshot path.
        installSetup()
        // The first ordinary launch explains collection before its first source
        // read. Acceptance mode must not steal the test browser's focus.
        if mode.collectsSystemScreenshots, firstUse.needsAutomaticPresentation {
            updateSetup()
            if settingsHost?.showOnboarding() == true { firstUse.recordPresentation() }
        }
        Task { [self] in
            do {
                try await start()
                if mode == .settingsReview,
                   CommandLine.arguments.contains("--settings-review-run") || CommandLine.arguments.contains("--settings-review-restart-check"),
                   let environment = reviewEnvironment, let settingsHost, let store, let statusItem {
                    let driver = SettingsReviewDriver(environment: environment, host: settingsHost, store: store,
                        statusItem: statusItem, onRefresh: { [weak self] in await self?.refresh() },
                        onHistory: { [weak self] in self?.showHistory() },
                        onRecheck: { [weak self] in
                            guard let self, self.mode == .settingsReview else { return false }
                            self.recheckSetup()
                            return self.captureControl.action == .recheck
                        }, history: history, panel: rift)
                    let report = CommandLine.arguments.contains("--settings-review-restart-check")
                        ? await driver.verifyRestart() : await driver.run()
                    if let report { print("RIFTLET_SETTINGS_REVIEW_REPORT=" + report.path) }
                    else { fputs("RIFTLET_SETTINGS_REVIEW_FAILED: no report was produced\n", stderr) }
                    NSApp.terminate(nil)
                }
            }
            catch {
                feedback.diagnostics.record(.initializationIssue)
                setupIssue = .initializationFailed
                if CaptureDiagnostic.classify(error, context: .privateStorage).code == .insufficientStorage {
                    setupStorage = .insufficientSpace; setupIssue = .insufficientSpace
                }
                showIssue(setupIssue!.text)
                updateSetup()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Explicit return from settings/menu, not an idle timer. Recheck does
        // not grant permission or re-enable a paused collector.
        if initialized, settingsHost?.isVisible == true {
            settingsHost?.refreshSystemFacts(); recheckSetup()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard instanceOwnership != nil else { return .terminateNow }
        if terminationApproved { return .terminateNow }
        guard !terminationPreparationPending else { return .terminateCancel }
        terminationPreparationPending = true
        let afterSettings: @MainActor (Bool) -> Void = { [weak self] accepted in
            guard let self else { return }
            guard accepted else { self.terminationPreparationPending = false; return }
            self.settingsHost?.beginTerminationPreparation()
            self.feedback.prepareTermination { [weak self] ready in
                guard let self else { return }
                self.terminationPreparationPending = false
                guard ready else { self.settingsHost?.cancelTerminationPreparation(); return }
                self.terminationApproved = true
                DispatchQueue.main.async { sender.terminate(nil) }
            }
        }
        if let center = settingsHost?.center { center.requestCloseForTermination(afterSettings) }
        else { afterSettings(true) }
        // AppKit's terminateLater modal loop does not run the MainActor tasks
        // used by our real feedback save/stop path in the native regression.
        // Keep the normal loop alive, then terminate once cleanup has succeeded.
        // Never force-exit or bypass an unsaved settings/feedback refusal.
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminating = true
        guard let owner = instanceOwnership else { return }
        owner.keepUntilProcessExit()
        permissionResumer?.stop()
        if let permissionActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(permissionActivationObserver) }
        if let permissionWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(permissionWakeObserver) }
        completionWatch?.cancel()
        originalRecoveryTask?.cancel()
        archiveTask?.cancel()
        cancelSelections(reason: "termination")
        selectionSubmissions.stop()
        frozenPress?.target.cancel(); frozenPress = nil
        if let archiveWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(archiveWakeObserver) }
        screenshotEntry?.close()
        arrivalCapture?.close()
        rift?.close()
        history?.close()
        settingsHost?.close()
        folderAccess.stop()
        if let sourceBinding { Task { await sourceBinding.stop() } }
        // The mode lock remains kernel-owned until all process-side stores exit.
        instanceOwnership = nil
    }

    private func start() async throws {
        guard let owner = instanceOwnership, root == owner.root else {
            throw RiftletError.database("App data-directory ownership is unavailable")
        }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"), mode: mode.storeMode)
        self.store = store
        userHidden = try await store.userHidden()
        captureIsPaused = try await store.capturePaused()
        if mode == .webAcceptance {
            // No system collection runs in this mode. Refuse a contaminated test
            // store before constructing the real transport or recovering a request.
            guard try await store.assets(includeUsed: true).allSatisfy({ $0.image.origin == .synthetic }) else {
                throw RiftletError.modeMismatch
            }
        }
        // Journal recovery may add records. Validate the isolated synthetic store
        // after recovery as well, before any real adapter is constructed.
        if mode.generatesSyntheticImages { try await seedSyntheticImages(store: store) }
        if mode == .systemScreenshotCandidate || (mode == .capture && mode.usesWebAdapter) {
            _ = try await PrivateAssetImporter(privateRoot: root, store: store).recover()
            try await SystemScreenshotCandidateConfiguration.validateStore(store)
        }
        let configurationURL = root.appendingPathComponent("rift-configuration.json")
        var configuration: RiftConfiguration
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            configuration = try JSONDecoder().decode(RiftConfiguration.self, from: Data(contentsOf: configurationURL))
        } else {
            configuration = RiftConfiguration()
            if let screen = NSScreen.screens.first,
               let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
                configuration.preferredDisplayID = id
                if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                    configuration.preferredDisplayUUID = CFUUIDCreateString(nil, uuid) as String
                }
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: configurationURL, options: [.atomic])
        }
        try configuration.validate()
        let lifecycleURL = root.appendingPathComponent("lifecycle-settings.json")
        if FileManager.default.fileExists(atPath: lifecycleURL.path) {
            lifecycleSettings = try JSONDecoder().decode(LifecycleSettings.self, from: Data(contentsOf: lifecycleURL))
        } else { try JSONEncoder().encode(lifecycleSettings).write(to: lifecycleURL, options: .atomic) }
        try lifecycleSettings.validate()
        arrivalPreferences = ArrivalMotionPreferences(url: root.appendingPathComponent("arrival-motion-settings.json"))
        rift = RiftPanelController(mediaDirectory: root.appendingPathComponent("media"), configuration: configuration,
            arrivalMode: arrivalPreferences?.mode ?? .provisionalFallback,
            onPress: { [weak self] id, timestamp in self?.freezePress(id, timestamp: timestamp) },
            onSelectionBoundary: { [weak self] boundary in self?.recordSelection(boundary) },
            onPresentationBoundary: { [weak self] boundary in self?.recordPresentation(boundary) },
            onArrivalBoundary: { [weak self] boundary in
                var fields: [String: Any] = ["event": boundary.phase.rawValue, "assetID": boundary.assetID.uuidString,
                    "uptime": boundary.uptime, "motionMode": boundary.mode.rawValue]
                if let reason = boundary.reason { fields["reason"] = reason }
                self?.recordArrivalTrace(fields)
            },
            holdsSelectionUntilFinished: true, interactionFence: interactionFence,
            onRemove: { [weak self] id in self?.removeVisible(id) },
            onOpenOriginal: { [weak self] id in self?.openOriginal(id) }) { [weak self] id in
            guard let self else { return }
            let press = self.frozenPress?.id == id ? self.frozenPress : nil
            let revision = self.rift?.selectionRevision(for: id)
            self.frozenPress = nil
            let selectionOwner = UUID()
            let selectedAt = ProcessInfo.processInfo.systemUptime
            self.selectionUIOwners[id] = selectionOwner
            if let press { self.pendingClickTargets[selectionOwner] = press.target }
            let feedback: @MainActor (String?, RiftFeedbackTiming) -> Void = { [weak self] text, timing in
                guard let self, self.selectionUIOwners[id] == selectionOwner,
                      let revision, self.rift?.selectionRevision(for: id) == revision else { return }
                self.rift?.setFeedback(text, for: id, owner: .selection(selectionOwner),
                    visibilityRevision: revision, timing: timing)
            }
            let submit: @MainActor (UInt64) async -> Void = { ordinal in
                var selection: AcceptedSelection?
                if self.selectionUIOwners[id] == selectionOwner {
                    self.rift?.clearFeedback(matching: ProductStatus.AttachmentFeedback.waiting.text, for: id,
                        owner: .selection(selectionOwner))
                }
                self.recordAcceptance(["event": "selection_submission_started", "selectionOrdinal": ordinal,
                    "assetID": id.uuidString, "uptime": ProcessInfo.processInfo.systemUptime])
                do {
                    if self.mode.usesWebAdapter {
                        guard let press, let revision, let transfer = self.transfer else {
                            throw WebAdapterError.invalidTarget
                        }
                        // This is the read started by this click, including a cold
                        // first click. No background ACK or second click is needed.
                        let resolved = try await self.selectionAuthority.accept(id: selectionOwner,
                            assetID: id, visibilityRevision: revision, selectedAt: selectedAt, target: press.target) {
                                self.selectionUIOwners[id] == selectionOwner && !self.userHidden && !self.terminating
                                    && self.rift?.selectionRevision(for: id) == revision
                            }
                        selection = resolved
                        self.setupIssue = nil
                        self.lastForegroundSession = resolved.target.sessionID
                        self.applyAutomationPermission(.granted)
                        self.feedback.diagnostics.record(.selectionAccepted)
                        self.recordAcceptance(["event": "click_target_resolved", "assetID": id.uuidString,
                            "selectionID": resolved.id.uuidString, "uptime": ProcessInfo.processInfo.systemUptime])
                        try await transfer.select(resolved)
                    } else {
                        try await self.transfer?.select(id, visibilityRevision: revision)
                    }
                    if let record = try await self.store?.asset(id: id), record.visibility == .visible,
                       let operationID = record.activeOperationID, record.status == .failed {
                        let reason = try await self.store?.operationReason(for: operationID)
                        feedback(ProductStatus.operationFeedback(reason).text, .immediate)
                    }
                } catch is CancellationError {
                    self.cancelOriginalSelection(selection, reason: "submissionCancelled")
                } catch {
                    if self.mode.usesWebAdapter {
                        self.setupIssue = ProductStatus.clickIssue(error,
                            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, webAcceptance: true)
                        if self.setupIssue == .permissionDenied { self.applyAutomationPermission(.denied) }
                    }
                    var refusal = BoundedDiagnosticTrace.clickFailureFields(error)
                    refusal["event"] = "click_input_refused"
                    refusal["assetID"] = id.uuidString
                    refusal["phase"] = selection == nil ? "resolveSelection" : "submitSelection"
                    refusal["uptime"] = ProcessInfo.processInfo.systemUptime
                    self.diagnosticTrace?.record(refusal, critical: true)
                    feedback(!self.mode.usesWebAdapter && self.mode == .capture ? "此版本尚未启用真实截图附加；图片保留。"
                        : (ProductStatus.clickFeedback(error)?.text ?? self.setupIssue?.text
                           ?? "当前附件目标暂不可用；图片保留，可在运行状态中查看原因。"), .immediate)
                    self.feedback.diagnostics.record(.selectionRejected)
                    self.cancelOriginalSelection(selection, reason: "selectionRejected")
                    self.updateSetup()
                }
                self.finishOriginalSelection(id, token: selection, revision: revision, ownerID: selectionOwner)
                await self.refresh()
            }
            guard self.mode.usesWebAdapter else {
                Task { await submit(0) }
                return
            }
            let waitsForSubmission = self.selectionSubmissions.hasOutstandingSubmission
            let ordinal = self.selectionSubmissions.enqueue(selectionID: selectionOwner, deadline: nil,
                cancelled: { [weak self] in
                    feedback(ProductStatus.AttachmentFeedback.cancelledBeforeInput.text, .immediate)
                    press?.target.cancel()
                    self?.finishOriginalSelection(id, token: nil, revision: revision, ownerID: selectionOwner)
                }, run: submit)
            if let ordinal {
                if waitsForSubmission { feedback(ProductStatus.AttachmentFeedback.waiting.text, .waiting) }
                self.recordAcceptance(["event": "selection_enqueued", "selectionOrdinal": ordinal,
                    "assetID": id.uuidString, "uptime": ProcessInfo.processInfo.systemUptime])
            } else {
                feedback(ProductStatus.AttachmentFeedback.cancelledBeforeInput.text, .immediate)
                press?.target.cancel()
                self.finishOriginalSelection(id, token: nil, revision: revision, ownerID: selectionOwner)
            }
        }
        rift?.setUserHidden(userHidden)
        if let rift {
            arrivalCapture = ArrivalCaptureBridge(panel: rift,
                allowsMetadata: ArrivalSourceProfile.allowsMetadata(arguments: CommandLine.arguments))
        }
        let historyDisplay = historyDisplayPreferences
        history = RiftHistoryController(mediaDirectory: root.appendingPathComponent("media"),
            onRestore: { [weak self] id in self?.restoreHistory(id) },
            onRemove: { [weak self] id in self?.removeVisible(id) },
            onReveal: { [weak self] id in self?.revealHistory(id) },
            onNextPage: { [weak self] in self?.changeHistoryPage(1) },
            onPreviousPage: { [weak self] in self?.changeHistoryPage(-1) },
            displayStyle: historyDisplay.selection,
            onDisplayStyleChanged: { [weak historyDisplay] style in historyDisplay?.select(style) })
        historyDisplay.onChange = { [weak self] style in
            self?.history?.updateDisplayStyle(style)
            self?.settingsHost?.refreshHistoryDisplayStyle()
        }
        history?.onPreviewVisibilityChanged = { [weak self] visible in self?.rift?.setDetailPresented(visible) }
        let composition = try ApplicationAttachmentComposition.make(mode: mode, root: root, store: store,
            traceEnabled: CommandLine.arguments.contains("--acceptance-trace"),
            diagnosticTrace: diagnosticTrace,
            onInputTransportFinished: { [weak self] in await self?.inputTransportFinished() })
        let adapter = composition.adapter
        let policy = composition.policy
        let transfer = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root.appendingPathComponent("media"),
            policy: policy, onChange: { [weak self] in await self?.refresh() },
            onSelectionSettled: { [weak self] id in await self?.finishPreparedSelection(id) },
            onAcceptedSelectionSettled: { [weak self] selection in
                await self?.finishOriginalSelection(selection.assetID, token: selection, revision: selection.visibilityRevision)
            }, onAcceptedSelectionFinished: { [weak self] id in
                await self?.acceptedSelectionFinished(id)
            }, validateAcceptedSelection: { [weak self] selection in
                await self?.validateAcceptedSelection(selection) ?? false
            })
        self.transfer = transfer
        clickAdapter = mode.usesWebAdapter ? adapter as? WebAttachmentAdapter : nil
        // Durable crash recovery remains local even when Automation is denied.
        // No page observation is attempted until a passive check says allowed.
        if adapter is any IndependentFileInputAdapter {
            // Earlier operations are history, never a new input permission or
            // restart upload job. Preserve their SQLite rows and media exactly.
            originalRecoveryIDs = nil
            startupCompletedIDs = []
        } else {
            try await store.recoverInterruptedOperations()
            originalRecoveryIDs = mode.observesAttachments ? try await store.unresolvedOperations().map(\.id) : nil
            startupCompletedIDs = mode.observesAttachments ? Set(try await store.successfulOperations().map(\.id)) : []
        }
        recordAcceptance(["event": "local_recovery_complete", "uptime": ProcessInfo.processInfo.systemUptime])
        if mode.usesWebAdapter {
            // Process identity only, not permission or a page/attachment lease.
            lastForegroundSession = foregroundChromeSession
            installPassivePermissionRecovery()
            _ = await inspectAutomationPermission(reason: "startup")
        }
        // Original read-only observers perform their own receiver-bound checks;
        // an ambiguous foreground must not suppress recovery after restart.
        try await startAttachmentObservationIfPermitted()
        if !mode.collectsSystemScreenshots {
            statusLine?.title = simulation ? "SIMULATION · synthetic images only · no ChatGPT input"
                : "WEB ACCEPTANCE · generated images · real Chrome input"
        } else {
            do {
                detectedSource = try await captureLocation.currentDirectory()
                if let detectedSource { _ = restoreCaptureFolder(detectedSource) }
            } catch { receiveCaptureDiagnostic(.classify(error, context: .locationPreference)) }
            let service = CaptureService(store: store, privateRoot: root, sourceDirectory: detectedSource ?? reviewEnvironment?.source ?? CaptureSource.defaultDirectory(),
                                         permitsRead: { [weak self] url in await self?.permitsCaptureRead(url) ?? false },
                                         onChange: { [weak self] in await self?.refresh() },
                                         onImported: { [weak self] record, observation in
                                             Task { @MainActor [weak self] in
                                                 guard let self, !self.terminating else { return }
                                                 // A committed new screenshot is an observation
                                                 // demand, never a click or input authorization.
                                                 // Start prebinding before preview work and the
                                                 // later multi-read refresh/source lookup.
                                                 self.recordArrivalTrace(["event": "captureDurableObserved",
                                                    "assetID": record.id.uuidString, "uptime": observation.readyUptime,
                                                    "firstSeenWallTime": record.image.firstSeenAt.timeIntervalSince1970])
                                                 self.arrivalCapture?.imported(record, observation: observation)
                                                 // Publish each committed asset without awaiting source metadata
                                                 // or the rest of a multi-file collector scan.
                                                 await self.refresh()
                                             }
                                         },
                                         onDiagnostic: { [weak self] value in await self?.receiveCaptureDiagnostic(value) })
            capture = service
            let binding = CaptureSourceBinding(service: service, provider: captureLocation,
                permitsSource: { [weak self] source in await self?.restoreCaptureFolder(source) ?? false },
                onDiagnostic: { [weak self] value in await self?.receiveCaptureDiagnostic(value) })
            sourceBinding = binding
            if !captureIsPaused {
                do { try await binding.start() }
                catch { receiveCaptureDiagnostic(.classify(error, context: .source)) }
            }
            captureStatus = await service.statusSnapshot()
        }
        updateControlTitles()
        startArchiveScheduler()
        initialized = true
        if mode.collectsSystemScreenshots, let rift {
            do {
                screenshotEntry = try ScreenshotEntryHost(root: root, store: store, rift: rift,
                    onChange: { [weak self] in await self?.refresh() },
                    onIssue: { [weak self] message in self?.showIssue(message) },
                    allowsSystemCapture: mode != .settingsReview)
                screenshotEntry?.onPreferencesChanged = { [weak self] in self?.updateSetup() }
                screenshotEntry?.setHidden(userHidden)
            } catch { showIssue("截图入口暂不可用，已有截图收录和队列仍保留。") }
        }
        await refresh()
    }

    /// Host lifecycle events can recover an initially unavailable browser without
    /// requiring another settings visit. No click is stored, waited for or replayed.
    private func installPassivePermissionRecovery() {
        guard mode.usesWebAdapter, permissionResumer == nil, !terminating else { return }
        let resumer = PassivePermissionResume(inspect: { [weak self] in
            guard let self else { return .unavailable }
            return await self.inspectAutomationPermission(reason: "passiveResume")
        }, onResult: { [weak self] _ in
            self?.updateSetup()
        }, resume: { [weak self] in
            guard let self, !self.terminating else { return }
            do { try await self.startAttachmentObservationIfPermitted() }
            catch is CancellationError { return }
            catch { self.setupIssue = .targetUnavailable; self.updateSetup() }
        })
        permissionResumer = resumer; resumer.start()
        permissionActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,
                          let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.bundleIdentifier == "com.google.Chrome" else { return }
                    self.lastForegroundSession = self.foregroundChromeSession
                    self.permissionResumer?.request()
                }
            }
        permissionWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.permissionResumer?.request()
                }
            }
    }

    /// Measure the existing passive check without caching authorization or
    /// substituting another process for an original selection. Only acceptance
    /// trace logs these bounds; a session string grants no page authority.
    private func inspectAutomationPermission(reason: String, assetID: UUID? = nil,
                                             invocation: CaptureInvocationContext? = nil,
                                             expectedSession: String? = nil,
                                             requestFromUserAction: Bool = false) async -> AutomationPermissionState {
        let started = ProcessInfo.processInfo.systemUptime
        let foreground = foregroundChromeSession
        let receiver = expectedSession ?? foreground ?? lastForegroundSession
        let receiverRequest = receiver.map { originalReceiverPermission.begin(session: $0) }
        let request = permissionPublication.begin(hostEpoch: permissionSession, foregroundSession: foreground,
                                                  receiverSession: receiver)
        let result: AutomationPermissionState
        if requestFromUserAction { result = await permissionGate.requestFromUserAction(expectedSession: receiver) }
        else { result = await permissionGate.inspect(expectedSession: receiver) }
        let receiverResolution = receiverRequest.map { originalReceiverPermission.resolve($0, result: result) }
        let resolution = permissionPublication.resolve(request, state: result, hostEpoch: permissionSession,
            foregroundSession: foregroundChromeSession, terminating: terminating)
        if resolution == .publish { applyAutomationPermission(result) }
        // A stale grant cannot authorize this caller even when another fresh
        // check has since set the shared status to granted. A stale failure is
        // diagnostic only and cannot clear that newer ACK/selection authority.
        let usableResult: AutomationPermissionState = resolution.mayUseResult
            && (receiverResolution == nil || receiverResolution?.usable == result) ? result : .unavailable
        guard mode.usesWebAdapter, CommandLine.arguments.contains("--acceptance-trace") else { return usableResult }
        var fields: [String: Any] = ["event": "permission_check", "purpose": reason,
            "permissionRequestID": UUID().uuidString, "startedUptime": started,
            "endedUptime": ProcessInfo.processInfo.systemUptime, "result": String(describing: result),
            "usableResult": String(describing: usableResult), "publication": resolution.rawValue,
            "promptPermissionAllowed": requestFromUserAction, "originalSessionBound": receiver != nil]
        if !requestFromUserAction { fields["askedUser"] = false }
        if let assetID { fields["assetID"] = assetID.uuidString }
        if let invocation {
            fields["captureRequestID"] = invocation.requestID.uuidString
            fields["armAttemptID"] = invocation.armAttemptID.uuidString
            fields["hostEpoch"] = invocation.hostEpoch.uuidString
        }
        recordAcceptance(fields)
        return usableResult
    }

    /// Read-only observation follows the original receiver after a user leaves
    /// Chrome. Its permission must neither borrow B's grant nor publish A as
    /// the foreground target. Denial is retained for a later passive check.
    private func mayObserveOriginal(_ target: TargetLease) async -> Bool {
        guard !terminating else { return false }
        guard mode.usesWebAdapter else { return true }
        guard target.applicationID == "com.google.Chrome" else { return false }
        let started = ProcessInfo.processInfo.systemUptime
        let result = await originalReceiverPermission.inspectResolution(session: target.sessionID, gate: permissionGate)
        recordAcceptance(["event": "original_observation_permission", "startedUptime": started,
            "endedUptime": ProcessInfo.processInfo.systemUptime,
            "usableResult": String(describing: result.usable), "published": result.published,
            "askedUser": false, "foregroundRequired": false])
        return !terminating && result.usable == .granted
    }

    private func startOriginalRecovery() {
        guard mode.observesAttachments, !terminating, let ids = originalRecoveryIDs, let transfer else { return }
        originalRecoveryIDs = nil
        // Nothing to observe: do not queue a permission inspection ahead of
        // the first useful capture on a fresh installation.
        guard !ids.isEmpty else { return }
        originalRecoveryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.originalRecoveryTask = nil }
            self.recordAcceptance(["event": "original_recovery_started", "uptime": ProcessInfo.processInfo.systemUptime,
                "operationCount": ids.count])
            do {
                try Task.checkCancellation()
                try await transfer.recoverOriginalObservations(operationIDs: ids) { [weak self] target in
                    await self?.mayObserveOriginal(target) ?? false
                }
            } catch { self.setupIssue = .targetUnavailable; self.updateSetup() }
            self.recordAcceptance(["event": "original_recovery_finished", "uptime": ProcessInfo.processInfo.systemUptime])
        }
    }

    private func startAttachmentObservationIfPermitted() async throws {
        guard !terminating, !attachmentObservationStarting, let transfer else { return }
        attachmentObservationStarting = true
        defer { attachmentObservationStarting = false }
        guard !attachmentObservationStarted else { return }
        // All local recovery/snapshots completed before any arming or selection.
        // Remote observation is original-ID-only and cannot reset newer operations.
        try Task.checkCancellation()
        guard !terminating else { return }
        watchedCompletions = startupCompletedIDs
        attachmentObservationStarted = true
        startOriginalRecovery()
        guard mode.observesAttachments else { return }
        completionWatch = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: self?.simulation == true ? 400_000_000 : 5_000_000_000) } catch { return }
                guard let self else { return }
                guard self.originalRecoveryTask == nil, self.originalRecoveryIDs == nil else { continue }
                do {
                    try await transfer.observePending(limit: self.simulation ? 8 : 4) { [weak self] target in
                        await self?.mayObserveOriginal(target) ?? false
                    }
                }
                catch { self.showIssue("附件结果暂时无法核实；本机图片与原操作仍保留，不会自动重新附加。") }
                for id in self.watchedCompletions {
                    if Task.isCancelled { return }
                    if let backoff = self.observationBackoff[id], backoff.next > Date() { continue }
                    do {
                        let keepWatching = try await transfer.observeCompleted(operationID: id) { [weak self] target in
                            await self?.mayObserveOriginal(target) ?? false
                        }
                        if !keepWatching { self.watchedCompletions.remove(id) }
                        self.observationBackoff.removeValue(forKey: id)
                    } catch WebAdapterError.invalidTarget {
                        self.watchedCompletions.remove(id); self.observationBackoff.removeValue(forKey: id)
                    } catch {
                        let failures = min(6, (self.observationBackoff[id]?.failures ?? 0) + 1)
                        self.observationBackoff[id] = (failures, Date().addingTimeInterval(min(300, pow(2, Double(failures)) * 5)))
                    }
                }
            }
        }
    }

    private func installSetup() {
        guard let root, let statusItem else { return }
        do {
            settingsHost = try SettingsProductHost(root: root, mode: mode, statusItem: statusItem,
                owner: nextSettingsOwner(), adapter: SettingsPersistenceClosures { [weak self] request in
                    guard let self else { return .unconfirmed(nil, .ownerUnavailable) }
                    return await self.saveSettings(request)
                }, historyDisplay: historyDisplayPreferences,
                onRefresh: { [weak self] in self?.updateSetup() },
                onAction: { [weak self] in await self?.performSettingsAction($0) })
        } catch { setupIssue = .configurationUnavailable }
        updateSetup()
    }

    private func updateSetup() {
        let needsSelection = folderNeedingSelection.flatMap { blocked in
            detectedSource.map { SourceAccessSelection.matches(selected: blocked, actualSource: $0) }
        } == true
        let issue: SetupIssue? = visibilitySettingFailed ? .visibilityPreferenceUnsaved
            : (collectionSettingFailed ? .collectionPreferenceUnsaved
                : (screenshotEntry?.preferenceSaveFailed == true ? .screenshotPreferenceUnsaved
                    : (needsSelection ? .screenshotFolderNeedsSelection : (captureDiagnostic.map(ProductStatus.issue) ?? setupIssue))))
        let attachment = mode.attachmentState
        let source = ProductStatus.sourceState(detectedSource: detectedSource, observation: captureStatus,
            systemCollection: mode.collectsSystemScreenshots, paused: captureIsPaused, initialized: initialized)
        let collection = ProductStatus.collectionState(systemCollection: mode.collectsSystemScreenshots, paused: captureIsPaused,
            initialized: initialized, running: captureStatus?.isRunning == true, source: source)
        let snapshot = SetupSnapshot(sourceLocation: detectedSource?.path, source: source, collection: collection,
            isHidden: userHidden, visibleCount: visibleIDs.count, pendingCount: pendingResultCount,
            attachment: attachment, permission: ProductStatus.permission(automationPermission),
            permissionDetail: mode.usesWebAdapter ? ProductStatus.chromeJavaScriptHelp : nil,
            storage: setupStorage, issue: issue, supportDescription: ProductStatus.supportDescription,
            isChecking: captureControlBusy || requestingPermission || !initialized,
            builtInScreenshotEnabled: screenshotEntry?.isEnabled,
            defaultScreenshotMode: screenshotEntry?.defaultMode ?? .window)
        var capabilities = SettingsCapabilities()
        capabilities.initialized = initialized
        capabilities.canChangeCollection = canChangeCollection
        capabilities.canChangeVisibility = store != nil && !changingHidden
        capabilities.canCapture = mode != .settingsReview && screenshotEntry?.isEnabled == true && !userHidden
        capabilities.canRecheck = initialized && !captureControlBusy && !requestingPermission
        capabilities.canRequestAutomation = mode.usesWebAdapter && initialized && !requestingPermission
        capabilities.canChooseSource = mode.collectsSystemScreenshots && initialized && mode != .settingsReview
        capabilities.canOpenHistory = store != nil
        capabilities.canClearVisible = store != nil && !visibleIDs.isEmpty
        capabilities.canCheckStorage = root != nil && storageMeasurement == nil
        capabilities.canEditPreferences = initialized
        capabilities.canOpenConfiguration = root != nil
        settingsHost?.update(owner: nextSettingsOwner(), setup: snapshot, capabilities: capabilities,
            configurationDeferred: rift.map { $0.requestedConfiguration != $0.configuration } ?? false)
        let presentation = SetupPresentation(snapshot: snapshot)
        let summary = presentation.issueText ?? (mode.collectsSystemScreenshots ? presentation.collectionText : presentation.attachmentText)
        statusLine?.title = summary
        // Compact, demand-only feedback; no notification, success Toast or focus change.
        statusItem?.button?.toolTip = [summary, presentation.riftText, presentation.pendingText].compactMap { $0 }.joined(separator: "\n")
    }

    private func receiveCaptureDiagnostic(_ value: CaptureDiagnostic) {
        feedback.capture(value)
        captureDiagnostic = value
        switch value.code {
        case .insufficientStorage: setupStorage = .insufficientSpace
        case .privateWriteFailed: setupStorage = .writeFailed
        default: break
        }
        updateSetup()
    }

    @objc private func showFeedback() { screenshotEntry?.cancel(); feedback.open() }

    // A deliberate host window must never sit underneath a live selection
    // panel: clicking its controls would otherwise create a screenshot.
    @objc private func showSetup() {
        guard !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else { return }
        showSettingsPage(.display)
    }
    private func showSettingsPage(_ page: SettingsPage) {
        screenshotEntry?.cancel(); updateSetup(); settingsHost?.show(page: page)
    }
    @objc private func showOnboarding() {
        screenshotEntry?.cancel(); updateSetup()
        if settingsHost?.showOnboarding() == true { firstUse.recordPresentation() }
    }

    private func restoreCaptureFolder(_ source: URL) -> Bool {
        let needsSelection = folderAccess.restore(for: source) == .needsSelection
        folderNeedingSelection = needsSelection ? source : nil
        return !needsSelection
    }

    private func permitsCaptureRead(_ source: URL) -> Bool {
        let allowed = folderAccess.permitsRead(of: source)
        if !allowed, let detectedSource, SourceAccessSelection.matches(selected: source, actualSource: detectedSource) {
            folderNeedingSelection = source
        }
        return allowed
    }

    @objc private func recheckSetup() {
        guard initialized, !requestingPermission, !collectionChangePending,
              let token = captureControl.begin(.recheck) else { return }
        updateControlTitles()
        recheckTask = Task {
            defer { captureControl.finish(token); recheckTask = nil; updateControlTitles() }
            if mode.collectsSystemScreenshots, let capture, let binding = sourceBinding {
                do {
                    do { detectedSource = try await captureLocation.currentDirectory() }
                    catch { detectedSource = nil; throw error }
                    let permitted = detectedSource.map(restoreCaptureFolder) ?? false
                    // Recheck cannot undo Pause. A failed first start may be
                    // stopped; start is idempotent and handles that recovery.
                    if !permitted {
                        await capture.stop()
                    } else if !captureIsPaused {
                        try await binding.start()
                        await binding.refresh()
                        if folderNeedingSelection == nil { try await capture.recheck() }
                    }
                    captureStatus = await capture.statusSnapshot()
                    acceptCaptureStatus(preferenceIssue: nil)
                    if setupIssue == .wrongScreenshotFolder || (setupIssue == .sourceAccess && captureStatus?.sourceAccessible == true) {
                        setupIssue = nil
                    }
                } catch { receiveCaptureDiagnostic(.classify(error, context: .source)) }
            }
            let permission = await inspectAutomationPermission(reason: "setupRecheck")
            if !mode.usesWebAdapter || permission == .granted {
                do { try await startAttachmentObservationIfPermitted() }
                catch { setupIssue = .targetUnavailable }
            }
            await refresh()
            checkStorage()
        }
    }

    @objc private func openScreenshotSource() {
        guard let source = detectedSource else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            setupIssue = .sourceAccess; updateSetup(); return
        }
        if !NSWorkspace.shared.open(source) { setupIssue = .sourceAccess; updateSetup() }
    }

    private func chooseSourceAccess() {
        guard mode.collectsSystemScreenshots, !captureControlBusy, folderShownInPicker == nil, let source = detectedSource else { return }
        let panel = NSOpenPanel()
        panel.delegate = self
        panel.title = "允许 Riftlet 读取系统截图位置"
        panel.message = "请选择 macOS 保存截图的文件夹：\n" + source.path
        panel.prompt = "允许读取"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = source
        folderShownInPicker = source
        panel.begin { [weak self] response in
            self?.folderShownInPicker = nil
            guard response == .OK, let selected = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let actual = try await self.captureLocation.currentDirectory()
                    try self.folderAccess.accept(selected, actualSource: actual)
                    self.recheckSetup()
                } catch SourceAccessError.differentFolder {
                    self.setupIssue = .wrongScreenshotFolder; self.updateSetup()
                } catch { self.setupIssue = .sourceAccess; self.updateSetup() }
            }
        }
    }

    func panel(_ sender: Any, validate url: URL) throws {
        try SourceAccessSelection.validate(selected: url, actualSource: folderShownInPicker)
    }

    private func requestAutomationPermission() {
        guard mode.usesWebAdapter, !captureControlBusy, !requestingPermission else { return }
        screenshotEntry?.cancel()
        if automationPermission == .denied { openPrivacySettings(automation: true); return }
        requestingPermission = true
        updateSetup()
        Task {
            defer { requestingPermission = false; updateSetup() }
            let permission = await inspectAutomationPermission(reason: "userRequest", expectedSession: lastForegroundSession,
                                                                requestFromUserAction: true)
            if permission == .denied { setupIssue = .permissionDenied }
            else if permission == .granted {
                if setupIssue == .permissionDenied { setupIssue = nil }
                do { try await startAttachmentObservationIfPermitted() }
                catch { setupIssue = .targetUnavailable }
            }
        }
    }

    @objc private func openFilePrivacySettings() { openPrivacySettings(automation: false) }
    private func openPrivacySettings(automation: Bool) {
        screenshotEntry?.cancel()
        let pane = automation ? "Privacy_Automation" : "Privacy_FilesAndFolders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"),
           NSWorkspace.shared.open(url) { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(app)
        }
    }

    @objc private func launchSimulation() {
        guard !OrdinaryCaptureConfiguration.isInternalAcceptance, mode.collectsSystemScreenshots, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--simulate"]
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            if error != nil { Task { @MainActor [weak self] in self?.showIssue("暂时无法打开离线演示；现有截图保留。") } }
        }
    }

    /// A one-time choice of internal test mode, never a per-screenshot prompt.
    /// macOS launch acknowledgement is not candidate readiness. Keep the
    /// ordinary collector and its data intact if candidate initialization fails.
    @objc private func launchSystemScreenshotCandidate() {
        guard !OrdinaryCaptureConfiguration.isInternalAcceptance, mode == .capture, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let alert = NSAlert()
        alert.messageText = "打开真实截图内部候选？"
        alert.informativeText = "这是受限的内部候选：新系统截图保存在独立本地目录，仅支持 Chrome 中文 ChatGPT 普通已有聊天中的原样 8-bit RGBA PNG。只使用你愿意附加的新截图。真实开始后快速吞噬，独立完成证明到达后后台记录成功；旧待核实操作保持原状，安全失败与重试仍关闭。普通实例继续保留；请在「Riftlet REAL TEST」菜单查看候选状态，需要时再退出普通实例。"
        alert.addButton(withTitle: "打开内部候选")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--system-screenshot-candidate"]
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if error != nil { self?.showIssue("暂时无法打开内部候选；普通收录与已有数据保留。") }
            }
        }
    }

    private func finishOriginalSelection(_ assetID: UUID, token: AcceptedSelection?, revision: Int64?, ownerID: UUID? = nil) {
        guard let owner = token?.id ?? ownerID, selectionUIOwners[assetID] == owner else { return }
        selectionUIOwners.removeValue(forKey: assetID)
        pendingClickTargets.removeValue(forKey: owner)?.cancel()
        guard let revision, rift?.selectionRevision(for: assetID) == revision else { return }
        rift?.finishSelection(assetID)
        // The committed refresh can be deferred while this exact selection owns
        // its row. Re-read after release so a prepared explanation can attach to
        // the now-current operation; this never resubmits the selection.
        Task { [weak self] in await self?.refresh() }
    }

    private func cancelOriginalSelection(_ selection: AcceptedSelection?, reason: String) {
        guard let selection else { return }
        selection.cancel()
        selectionAuthority.cancel(id: selection.id)
        guard let transfer else { return }
        Task { try? await transfer.cancelAcceptedSelections(ids: [selection.id], reason: reason) }
    }

    private func cancelSelections(assetID: UUID? = nil, reason: String) {
        let ids = selectionAuthority.cancel(assetID: assetID)
        let pendingOwners = selectionUIOwners.filter { assetID == nil || $0.key == assetID }
        selectionSubmissions.cancel(selectionIDs: Set(ids + Array(pendingOwners.values)))
        for (imageID, owner) in pendingOwners {
            finishOriginalSelection(imageID, token: nil, revision: rift?.selectionRevision(for: imageID), ownerID: owner)
        }
        if assetID == nil || frozenPress?.id == assetID {
            frozenPress?.target.cancel(); frozenPress = nil
        }
        recordAcceptance(["event": "selection_authority_cancelled", "reason": reason,
            "uptime": ProcessInfo.processInfo.systemUptime, "singleAsset": assetID != nil])
        guard !ids.isEmpty, let transfer else { return }
        Task { try? await transfer.cancelAcceptedSelections(ids: ids, reason: reason) }
    }

    private func applyAutomationPermission(_ state: AutomationPermissionState) {
        automationPermission = state
        if mode.usesWebAdapter, state != .granted { feedback.diagnostics.record(.permissionUnavailable) }
        // Setup status cannot veto an explicit click. The actual addressed Apple
        // Event enforces OS permission and reports a concrete error if denied.
    }

    private func validateAcceptedSelection(_ selection: AcceptedSelection) async -> Bool {
        selectionAuthority.permits(selection, epoch: permissionSession, foregroundSession: nil,
            hidden: userHidden, terminating: terminating, now: ProcessInfo.processInfo.systemUptime)
    }

    private func finishPreparedSelection(_ id: UUID) {
        // Web submissions release only their exact original token/revision owner.
        guard !mode.usesWebAdapter else { return }
        // Coordinator awaits committed refresh before this callback. Releasing
        // the UI reservation cannot flush a stale pre-prepare archive snapshot.
        let hadSelection = rift?.selectionRevision(for: id) != nil
        rift?.finishSelection(id)
        if hadSelection { Task { [weak self] in await self?.refresh() } }
    }

    private var foregroundChromeSession: String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.google.Chrome" else { return nil }
        return ChromeProcessIdentity.read(pid: app.processIdentifier)?.session
    }

    private func freezePress(_ id: UUID, timestamp: TimeInterval) {
        frozenPress?.target.cancel()
        frozenPress = nil
        guard mode.usesWebAdapter, let web = clickAdapter else { return }
        let target: Task<TargetLease, Error>
        do {
            // Only native window/tab IDs and the route are read synchronously.
            // DOM discovery and first-use page initialization run off the UI.
            target = try web.targetForClick()
        } catch {
            target = Task { throw error }
        }
        frozenPress = (id, timestamp, target)
        recordAcceptance(["event": "click_target_requested", "assetID": id.uuidString,
            "originalEventUptime": timestamp, "uptime": ProcessInfo.processInfo.systemUptime])
    }

    private func inputTransportFinished() {
        recordAcceptance(["event": "input_transport_finished", "observationOnly": true,
            "uptime": ProcessInfo.processInfo.systemUptime])
    }

    private func acceptedSelectionFinished(_ id: UUID) {
        selectionAuthority.finish(id)
    }

    private func recordPresentation(_ boundary: RiftPresentationBoundary) {
        guard mode.usesWebAdapter, CommandLine.arguments.contains("--acceptance-trace") else { return }
        var fields: [String: Any] = ["event": "presentation_boundary", "phase": boundary.phase.rawValue,
            "assetID": boundary.assetID.uuidString, "visibilityRevision": boundary.visibilityRevision,
            "generation": boundary.generation, "uptime": boundary.uptime,
            "actualDuration": boundary.actualDuration, "pixelPresentationMeasured": false]
        if let id = boundary.operationID { fields["operationID"] = id.uuidString }
        recordAcceptance(fields)
    }

    private func recordSelection(_ boundary: RiftSelectionBoundary) {
        var fields: [String: Any] = ["event": "selection_boundary", "source": boundary.source.rawValue,
            "assetID": boundary.assetID.uuidString, "eventUptime": boundary.eventUptime,
            "callbackUptime": ProcessInfo.processInfo.systemUptime,
            "targetRequested": frozenPress?.id == boundary.assetID]
        if let number = boundary.eventNumber { fields["eventNumber"] = number }
        recordAcceptance(fields)
    }

    private func recordAcceptance(_ fields: [String: Any]) {
        diagnosticTrace?.record(fields)
    }

    private func seedSyntheticImages(store: QueueStore, addNewBatch: Bool = false) async throws {
        guard mode.generatesSyntheticImages else { throw RiftletError.modeMismatch }
        let importer = PrivateAssetImporter(privateRoot: root, store: store)
        _ = try await importer.recover()
        let recovered = try await store.assets(includeUsed: true)
        guard recovered.allSatisfy({ $0.image.origin == .synthetic }) else { throw RiftletError.modeMismatch }
        if !addNewBatch {
            guard recovered.isEmpty else { return }
        }
        let input = root.appendingPathComponent("synthetic-input", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let batchID = UUID().uuidString
        for index in 0..<3 {
            let file = input.appendingPathComponent("demo-\(batchID)-\(index).png")
            try SyntheticImage.write(to: file, index: index)
            _ = try await importer.importFile(at: file, origin: .synthetic)
        }
    }

    private func refresh() async {
        refreshRequested = true
        if refreshRunning {
            await withCheckedContinuation { refreshWaiters.append($0) }
            return
        }
        refreshRunning = true
        repeat {
            refreshRequested = false
            guard let store else { break }
            do {
                let active = try await store.assets()
                // A wake-up hint only: QueueStore still decides atomically whether
                // the row can leave, using its current interaction time and fence.
                oldestArchiveCandidate = active.lazy.filter {
                    $0.visibility == .visible && ($0.status == .pending || $0.status == .failed)
                }.map(\.lastInteractionAt).min()
                var snapshot = active
                let activeIDs = Set(active.map(\.id))
                // Include windows still visible during a deferred animation or
                // held selection, not just the previous backend-visible IDs.
                let panelIDs = Set(rift?.diagnosticSnapshot.rows.map(\.assetID) ?? [])
                for id in visibleIDs.union(panelIDs).subtracting(activeIDs) {
                    if let retired = try await store.asset(id: id) { snapshot.append(retired) }
                }
                let successful = mode.usesWebAdapter ? try await store.successfulOperations() : []
                let unresolved = try await store.unresolvedOperations()
                var cancelledPreparedFeedback: [UUID: (operationID: UUID, revision: Int64, text: String)] = [:]
                for (id, operationID) in preparedFeedbackOperations {
                    guard let record = snapshot.first(where: {
                        $0.id == id && $0.activeOperationID == operationID && $0.status == .failed && $0.visibility == .visible
                    }) else { continue }
                    cancelledPreparedFeedback[id] = (operationID, record.visibilityRevision,
                        ProductStatus.operationFeedback(try await store.operationReason(for: operationID)).text)
                }
                // Independent reads, not an atomic multi-row snapshot or exact COMMIT.
                let snapshotObservedUptime = ProcessInfo.processInfo.systemUptime
                var preferenceIssue: CaptureDiagnostic?
                if let capture {
                    captureStatus = await capture.statusSnapshot()
                    do { detectedSource = try await captureLocation.currentDirectory() }
                    catch { detectedSource = nil; preferenceIssue = .classify(error, context: .locationPreference) }
                }
                if refreshRequested { continue }
                if mode.usesWebAdapter, CommandLine.arguments.contains("--acceptance-trace") {
                    for record in snapshot {
                        let signature = [record.status.rawValue, record.visibility.rawValue,
                            record.visibilityReason.rawValue, String(record.visibilityRevision),
                            record.activeOperationID?.uuidString ?? "none"]
                        guard visibilityTrace.shouldRecord(signature, for: record.id) else { continue }
                        var fields: [String: Any] = ["event": "committed_visibility_observed",
                            "assetID": record.id.uuidString, "status": record.status.rawValue,
                            "visibility": record.visibility.rawValue, "visibilityReason": record.visibilityReason.rawValue,
                            "visibilityRevision": record.visibilityRevision, "commitUpperBoundUptime": snapshotObservedUptime,
                            "exactCommitMeasured": false]
                        if let id = record.activeOperationID { fields["operationID"] = id.uuidString }
                        recordAcceptance(fields)
                    }
                    for operation in successful {
                        let signature = [operation.assetID.uuidString, String(operation.attempt), operation.phase.rawValue]
                        guard readyTrace.shouldRecord(signature, for: operation.id) else { continue }
                        recordAcceptance(["event": "ready_persistence_observed", "assetID": operation.assetID.uuidString,
                            "operationID": operation.id.uuidString, "attempt": operation.attempt,
                            "phase": operation.phase.rawValue, "commitUpperBoundUptime": snapshotObservedUptime,
                            "exactCommitMeasured": false])
                    }
                }
                visibleIDs = activeIDs
                pendingResultCount = Set(unresolved.filter { $0.phase != .prepared }.map(\.assetID)).count
                acceptCaptureStatus(preferenceIssue: preferenceIssue)
                if clickAdapter == nil {
                    watchedCompletions.formUnion(successful.map(\.id))
                }
                rift?.render(snapshot)
                screenshotEntry?.configure()
                // The last observed phase may advance to input before another
                // refresh. Use neutral text, never claim ongoing no-input status.
                let prepared = Dictionary(uniqueKeysWithValues: unresolved.filter { operation in
                    operation.phase == .prepared && snapshot.contains {
                        $0.id == operation.assetID && $0.activeOperationID == operation.id && $0.visibility == .visible
                    }
                }.map { ($0.assetID, $0.id) })
                for (id, operationID) in preparedFeedbackOperations where prepared[id] != operationID {
                    rift?.clearFeedback(matching: ProductStatus.AttachmentFeedback.preparing.text, for: id,
                        owner: .operation(operationID))
                }
                for (id, value) in cancelledPreparedFeedback {
                    rift?.setFeedback(value.text, for: id, owner: .operation(value.operationID),
                        visibilityRevision: value.revision)
                }
                for (id, operationID) in prepared {
                    guard let record = snapshot.first(where: { $0.id == id }) else { continue }
                    rift?.setFeedback(ProductStatus.AttachmentFeedback.preparing.text, for: id,
                        owner: .operation(operationID), visibilityRevision: record.visibilityRevision, timing: .waiting)
                }
                preparedFeedbackOperations = prepared
                feedback.assets(snapshot) // Sampled local counts, not operation-level statistics.
                feedback.operations(successful + unresolved)
                if interactionFence.snapshot().blocked { feedback.diagnostics.record(.uiProjectionDeferred) }
                switch mode {
                case .capture:
                    statusItem?.button?.toolTip = "\(OrdinaryCaptureConfiguration.menuTitle) · \(active.count) visible screenshots\(userHidden ? " · hidden" : "")"
                case .simulation: statusItem?.button?.toolTip = "Riftlet SIMULATION — synthetic only; start then delayed result"
                case .systemScreenshotCandidate: statusItem?.button?.toolTip = "Riftlet REAL TEST · 原图候选 · 生产准入关闭 · 待核实不重传"
                case .webAcceptance: statusItem?.button?.toolTip = "Riftlet WEB ACCEPTANCE · \(active.count) visible test images · unresolved records stay in local history"
                case .settingsReview: statusItem?.button?.toolTip = "Riftlet 设置验收 · 独立本地数据 · 无上传"
                }
                if history?.isVisible == true { await refreshHistory() }
                updateSetup()
            } catch { feedback.diagnostics.record(.queueReadIssue); showIssue("Queue read failed; durable data is preserved.") }
        } while refreshRequested
        refreshRunning = false
        let waiters = refreshWaiters; refreshWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func acceptCaptureStatus(preferenceIssue: CaptureDiagnostic?) {
        if let preferenceIssue { captureDiagnostic = preferenceIssue; return }
        guard let captureStatus else { return }
        if let diagnostic = captureStatus.latestDiagnostic { captureDiagnostic = diagnostic; return }
        // A paused/not-started service has no read result; nil is not evidence
        // that a previously denied source or failed write has recovered.
        if let detectedSource, captureStatus.sourceAccessible,
           SourceAccessSelection.matches(selected: captureStatus.sourceDirectory, actualSource: detectedSource) {
            let recovered = captureDiagnostic != nil
            captureDiagnostic = nil
            if recovered && (setupStorage == .insufficientSpace || setupStorage == .writeFailed) { setupStorage = .notMeasured }
        } else if captureDiagnostic?.code == .sourcePreferenceUnreadable {
            // Only the preference read (not directory access) succeeded above.
            captureDiagnostic = nil
        }
    }

    private func refreshHistory() async {
        guard let store, let history else { return }
        historyGeneration &+= 1
        let generation = historyGeneration, offset = historyOffset
        do {
            let page = try await store.historySnapshot(limit: 201, offset: offset)
            guard historyGeneration == generation, historyOffset == offset else { return }
            let entries = page.prefix(200).map {
                RiftHistoryEntry(record: $0.record, operation: $0.operation, lastReceipt: $0.receipt,
                                 canRestore: $0.canRestore, detail: $0.reason)
            }
            history.update(entries: entries, pageOffset: offset, hasEarlier: page.count > 200)
        } catch { showIssue("Local history could not be read; data preserved.") }
    }

    private func changeHistoryPage(_ direction: Int) {
        historyOffset = max(0, historyOffset + direction * 200)
        Task { await refreshHistory() }
    }

    @objc private func showHistory() {
        guard let history else { return }
        // An explicit auxiliary action ends the capture session so its full-
        // screen selection overlay cannot intercept this window's controls.
        screenshotEntry?.cancel()
        history.show()
        Task { await refreshHistory() }
    }

    private func openOriginal(_ id: UUID) {
        guard let store else { return }
        screenshotEntry?.cancel()
        rift?.setDetailPresented(true)
        Task {
            do {
                guard let record = try await store.asset(id: id) else { rift?.setDetailPresented(false); return }
                guard !terminating else { rift?.setDetailPresented(false); return }
                history?.openOriginal(entry: RiftHistoryEntry(record: record))
            } catch { rift?.setDetailPresented(false); showIssue("原图暂不可读取，截图与记录仍保留。") }
        }
    }

    private func restoreHistory(_ id: UUID) {
        guard let store else { return }
        Task {
            do {
                try await store.restoreToQueue(id)
                await refresh()
                rift?.showAsset(id)
            } catch { showIssue("This image cannot safely return to the queue; local history is preserved.") }
        }
    }

    private func revealHistory(_ id: UUID) {
        guard let store, let root else { return }
        Task {
            guard let record = try? await store.asset(id: id) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent("media").appendingPathComponent(record.image.fileName)])
        }
    }

    private func removeVisible(_ id: UUID) {
        guard let store else { return }
        cancelSelections(assetID: id, reason: "removed")
        Task {
            do { try await store.removeFromQueue(id); await refresh() }
            catch { showIssue("Could not remove this image from the rift; files are preserved.") }
        }
    }

    @objc private func clearVisible() {
        guard let store else { return }
        cancelSelections(reason: "clearVisible")
        Task {
            do { _ = try await store.clearVisibleQueue(); await refresh() }
            catch { showIssue("Could not clear the visible queue; files and attachments are preserved.") }
        }
    }

    private func updateControlTitles() {
        hideItem?.title = userHidden ? "显示裂缝" : "隐藏裂缝"
        pauseItem?.title = captureIsPaused ? "继续收录截图" : "暂停收录（保留已有图片）"
        pauseItem?.isEnabled = canChangeCollection
        if let interval = lifecycleSettings.archiveAfterSeconds {
            archiveItem?.title = String(format: "闲置归档：%g 分钟…", interval / 60)
        } else { archiveItem?.title = "闲置归档：已关闭…" }
        updateSetup()
    }

    @objc private func toggleHidden() {
        let target = !userHidden
        Task { await settingsHost?.perform(.settings(.setHidden(target))) }
    }

    @objc private func toggleCollection() {
        let target = !captureIsPaused
        Task { await settingsHost?.perform(.settings(.setCollectionPaused(target))) }
    }

    private func setHidden(_ requested: Bool) async throws {
        guard let store, !changingHidden else { throw CocoaError(.fileWriteUnknown) }
        changingHidden = true
        defer { changingHidden = false; updateControlTitles() }
        // Stop displaying immediately; resuming display waits for persistence.
        if requested {
            cancelSelections(reason: "hidden"); frozenPress = nil
            userHidden = true; screenshotEntry?.setHidden(true); rift?.setUserHidden(true)
            updateControlTitles()
        }
        do { try await store.setUserHidden(requested); visibilitySettingFailed = false }
        catch { visibilitySettingFailed = true; throw error }
        userHidden = requested; rift?.setUserHidden(requested); screenshotEntry?.setHidden(requested)
        await refresh()
    }

    private func setCollectionPaused(_ requested: Bool) async throws {
        guard mode.collectsSystemScreenshots, initialized, !collectionChangePending,
              let store, let binding = sourceBinding else { throw CocoaError(.fileWriteUnknown) }
        // A control can accept this immutable intent just before an activation
        // recheck starts. Wait for that real check rather than reporting a disk
        // failure, and reserve this turn so another recheck cannot cut ahead.
        collectionChangePending = true
        defer { collectionChangePending = false; updateControlTitles() }
        if let recheckTask { await recheckTask.value }
        try Task.checkCancellation()
        guard !terminating else { throw CancellationError() }
        guard let token = captureControl.begin(.changeCollection) else { throw CocoaError(.fileWriteUnknown) }
        defer { captureControl.finish(token); updateControlTitles() }
        updateControlTitles()
        if requested { await binding.stop(); captureIsPaused = true }
        do { try await store.setCapturePaused(requested); collectionSettingFailed = false }
        catch {
            if let capture { captureStatus = await capture.statusSnapshot() }
            collectionSettingFailed = true; throw error
        }
        // A persisted resume intent does not claim the source is readable.
        captureIsPaused = requested
        do { if !requested { try await binding.start() } }
        catch { receiveCaptureDiagnostic(.classify(error, context: .source)) }
        if let capture { captureStatus = await capture.statusSnapshot() }
        await refresh()
    }

    @objc private func configureArchive() { showSettingsPage(.history) }

    private func startArchiveScheduler() {
        archiveNotBefore = ProcessInfo.processInfo.systemUptime + 30
        archiveWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.archiveNotBefore = ProcessInfo.processInfo.systemUptime + 30
                    self?.archiveClock = nil
                }
            }
        archiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.archiveCheckDelay() else { return }
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
                guard let self else { return }
                await self.archiveIdleImages()
            }
        }
    }

    private func archiveCheckDelay() -> TimeInterval {
        guard let oldestArchiveCandidate, let interval = lifecycleSettings.archiveAfterSeconds else { return 30 }
        let due = oldestArchiveCandidate.addingTimeInterval(interval).timeIntervalSinceNow
        let grace = archiveNotBefore - ProcessInfo.processInfo.systemUptime
        // Do not spin for a thumbnail under the pointer, or overshoot a new
        // two-minute deadline by the old fixed thirty-second polling interval.
        let retry: TimeInterval = interactionFence.snapshot().blocked ? 2 : 1
        return min(30, max(retry, due, grace))
    }

    private func archiveIdleImages() async {
        guard let store, let interval = lifecycleSettings.archiveAfterSeconds else { return }
        let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
        if let clock = archiveClock,
           abs(now.timeIntervalSince(clock.wall) - (uptime - clock.uptime)) > 5 {
            archiveNotBefore = uptime + 30
        }
        archiveClock = (now, uptime)
        let state = interactionFence.snapshot()
        guard uptime >= archiveNotBefore, !state.blocked, let oldestArchiveCandidate,
              oldestArchiveCandidate <= now.addingTimeInterval(-interval) else { return }
        do {
            // Small atomic batches after a quiet interval avoid wake-time mass
            // disappearance. Core and UI both check the interaction boundary.
            let archived = try await store.archiveIdle(before: now.addingTimeInterval(-interval),
                fence: interactionFence, revision: state.revision, limit: 3)
            if !archived.isEmpty { await refresh() }
        } catch { showIssue("Idle archive deferred; screenshots remain available.") }
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = mode.menuTitle
        statusItem = item
        // SettingsProductHost installs a left-click popover and a right-click
        // context menu using the same state and immutable command targets.
        // Standard application shortcuts are active only while Riftlet owns
        // the foreground application. No global monitor or hotkey is added.
        let applicationMenu = NSMenu(title: "Riftlet")
        add(applicationMenu, "设置…", #selector(showSetup), key: ",")
        applicationMenu.addItem(.separator())
        add(applicationMenu, "退出 Riftlet", #selector(quit), key: "q")
        let applicationItem = NSMenuItem(title: "Riftlet", action: nil, keyEquivalent: "")
        applicationItem.submenu = applicationMenu
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        mainMenu.insertItem(applicationItem, at: 0)
        // Preserve any existing responder menus; a menu-bar-only launch has
        // none, so supply the standard editing routes for text windows.
        if !mainMenu.items.contains(where: { $0.submenu?.items.contains(where: { $0.action == #selector(NSText.copy(_:)) }) == true }) {
            let editMenu = NSMenu(title: "编辑")
            let editing: [(String, Selector, String)] = [
                ("撤销", Selector(("undo:")), "z"), ("重做", Selector(("redo:")), "Z"),
                ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"),
                ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")
            ]
            for (title, action, key) in editing {
                // nil target dispatches to the current responder, not App state.
                editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
            }
            let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
            editItem.submenu = editMenu; mainMenu.addItem(editItem)
        }
        if !mainMenu.items.contains(where: { $0.submenu?.items.contains(where: { $0.action == #selector(NSWindow.performClose(_:)) }) == true }) {
            let windowMenu = NSMenu(title: "窗口")
            // The native responder chain reaches the current window delegate,
            // including the settings draft confirmation. No global shortcut.
            windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
            let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
            windowItem.submenu = windowMenu; mainMenu.addItem(windowItem)
        }
        NSApp.mainMenu = mainMenu
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(showSetup) { return !NSApp.windows.contains { $0.attachedSheet != nil } }
        if item.action == #selector(beginScreenshot) { return screenshotEntry?.isEnabled == true && !userHidden }
        if item.action == #selector(toggleCollection) { return canChangeCollection }
        if item.action == #selector(recheckSetup) || item.action == #selector(reload) {
            return initialized && !captureControlBusy && !requestingPermission
        }
        if item.action == #selector(toggleHidden) { return store != nil && !changingHidden }
        return true
    }
    private func showIssue(_ message: String) { statusLine?.title = message; statusItem?.button?.toolTip = message }
    @objc private func beginScreenshot() { screenshotEntry?.beginFromMenu() }
    @objc private func showLatest() { rift?.showLatest() }
    @objc private func showOldest() { rift?.showOldest() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func showArrivalSettings() { showSettingsPage(.motion) }

    private func nextSettingsOwner() -> SettingsOwnerSnapshot {
        settingsOwnerRevision += 1
        let mainID = (NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return SettingsOwnerSnapshot(revision: settingsOwnerRevision, settings: settingsSnapshot(),
            collectionPaused: captureIsPaused, isHidden: userHidden, mainDisplayID: mainID,
            effectiveDisplayID: rift?.arrivalDestinationDisplayID)
    }

    private func saveSettings(_ request: SettingsSaveRequest) async -> SettingsSaveOutcome {
        guard initialized, let root else { return .unconfirmed(nextSettingsOwner(), .ownerUnavailable) }
        do {
            switch request.intent {
            case .collectionPaused(let target): try await setCollectionPaused(target)
            case .hidden(let target): try await setHidden(target)
            case .entryEnabled(let target): _ = try applySettings(.entryEnabled(target))
            case .captureMode(let target): _ = try applySettings(.defaultCaptureMode(target))
            case .arrival(let target): _ = try applySettings(.arrivalMode(target))
            case .archiveMinutes(let target): _ = try applySettings(.archiveAfterMinutes(target))
            case .layout, .placement, .display, .desktopForm, .trayTheme, .trayFavorite:
                guard let configuration = request.configuration, rift != nil else { throw CocoaError(.fileWriteUnknown) }
                if case .display(let selected) = request.intent {
                    guard settingsSnapshot().displays.contains(where: { $0.id == selected.id && $0.uuid == selected.uuid }) else {
                        return .unconfirmed(nextSettingsOwner(), .ownerUnavailable)
                    }
                }
                try persistRiftConfiguration(configuration, root: root, displayChanged: request.intent.domain == .display)
                updateControlTitles()
            }
            if [.entry, .captureMode].contains(request.intent.domain), screenshotEntry?.preferenceSaveFailed == true {
                return .unconfirmed(nextSettingsOwner(), .writeUnconfirmed)
            }
            return .confirmed(nextSettingsOwner())
        } catch {
            updateSetup()
            return .unconfirmed(nextSettingsOwner(), .writeUnconfirmed)
        }
    }

    private func performSettingsAction(_ action: SettingsProductAction) async {
        if mode == .settingsReview {
            switch action {
            case .capture, .chooseSourceAccess, .requestAutomation, .openFilePrivacy, .openScreenRecordingPrivacy:
                showIssue("设置验收环境不申请系统授权、不抓取屏幕。")
                return
            default: break
            }
        }
        switch action {
        case .openSettings(let page): showSettingsPage(page)
        case .openOnboarding: showOnboarding()
        case .capture: beginScreenshot()
        case .openHistory: showHistory()
        case .openFeedback: showFeedback()
        case .clearVisible: confirmClearVisible()
        case .recheck: recheckSetup()
        case .openSource: openScreenshotSource()
        case .chooseSourceAccess: chooseSourceAccess()
        case .requestAutomation: requestAutomationPermission()
        case .openFilePrivacy: openFilePrivacySettings()
        case .openScreenRecordingPrivacy:
            screenshotEntry?.cancel()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .restorePreferredDisplay:
            rift?.restorePreferredDisplay(); screenshotEntry?.configure(); updateSetup()
        case .checkStorage: checkStorage()
        case .revealDataFolder:
            if initialized, let root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
        case .reloadConfiguration: reload(); updateSetup()
        case .openConfiguration: openGeometry()
        case .showLatest: showLatest()
        case .showOldest: showOldest()
        case .quit: quit()
        case .settings, .appearance, .retryAppearance, .historyDisplayStyle, .loginEnabled, .retryLogin, .openLoginSettings, .finishOnboarding:
            break // Owned by SettingsProductHost; never recursively dispatched.
        }
    }

    private func confirmClearVisible() {
        guard store != nil, !visibleIDs.isEmpty else { return }
        screenshotEntry?.cancel(); settingsHost?.control.close()
        let alert = NSAlert()
        alert.messageText = "清空可见队列？"
        alert.informativeText = "图片会移入本地历史，不会删除系统原图或 ChatGPT 附件，也不会重新上传。可在历史中按实际状态逐张恢复。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "清空队列")
        if let window = settingsHost?.center.window, window.isVisible {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertSecondButtonReturn { self?.clearVisible() }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn { clearVisible() }
        }
    }

    private func settingsSnapshot() -> RiftSettingsSnapshot {
        let displays = NSScreen.screens.compactMap { screen -> RiftSettingsDisplay? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            return RiftSettingsDisplay(id: id, name: screen.localizedName, uuid: uuid)
        }
        return RiftSettingsSnapshot(entryAvailable: screenshotEntry != nil,
            entryEnabled: screenshotEntry?.isEnabled ?? false,
            capturePreferencesSaveFailed: screenshotEntry?.preferenceSaveFailed ?? false,
            defaultCaptureMode: screenshotEntry?.defaultMode ?? .window,
            arrivalMode: arrivalPreferences?.mode ?? .provisionalFallback,
            hasArrivalSelection: arrivalPreferences?.selectedMode != nil,
            displays: displays, preferredDisplayID: rift?.configuration.preferredDisplayID,
            archiveAfterMinutes: lifecycleSettings.archiveAfterSeconds.map { $0 / 60 },
            configuration: rift?.requestedConfiguration ?? .init(), displayRestoreAvailable: rift?.displayRestoreAvailable ?? false)
    }

    private func applySettings(_ change: RiftSettingsChange) throws -> RiftSettingsSnapshot {
        guard initialized, let root else { throw CocoaError(.fileWriteUnknown) }
        switch change {
        case .entryEnabled(let enabled):
            guard let screenshotEntry else { throw CocoaError(.fileWriteUnknown) }
            screenshotEntry.setEnabled(enabled)
        case .defaultCaptureMode(let mode):
            guard let screenshotEntry else { throw CocoaError(.fileWriteUnknown) }
            screenshotEntry.saveDefault(mode)
        case .arrivalMode(let mode):
            guard var value = arrivalPreferences else { throw CocoaError(.fileWriteUnknown) }
            try value.select(mode)
            arrivalPreferences = value; arrivalCapture?.cancel(); rift?.setArrivalMode(mode)
        case .preferredDisplay(let displayID):
            guard let rift else { throw CocoaError(.fileWriteUnknown) }
            let chosenID = displayID ?? (NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            var configuration = rift.requestedConfiguration; configuration.preferredDisplayID = chosenID
            configuration.preferredDisplayUUID = chosenID.flatMap { id in
                CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            }
            configuration.placementSource = .user
            try configuration.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: root.appendingPathComponent("rift-configuration.json"), options: .atomic)
            cancelSelections(reason: "displayPreferenceChanged"); frozenPress = nil
            screenshotEntry?.cancel(); arrivalCapture?.cancel()
            try rift.updateConfiguration(configuration); screenshotEntry?.configure()
        case .geometry(let fraction, let inset, let count):
            guard let rift else { throw CocoaError(.fileWriteUnknown) }
            var config = rift.requestedConfiguration
            config.hiddenFraction = fraction; config.outerInset = inset; config.visibleCountPreference = count
            try persistRiftConfiguration(config, root: root)
        case .placement(let placement):
            guard let rift else { throw CocoaError(.fileWriteUnknown) }
            var config = rift.requestedConfiguration; config.placement = placement; config.placementSource = .user
            try persistRiftConfiguration(config, root: root)
        case .restorePreferredDisplay:
            rift?.restorePreferredDisplay(); screenshotEntry?.configure()
        case .archiveAfterMinutes(let minutes):
            var value = lifecycleSettings
            value.archiveAfterSeconds = minutes.map { $0 * 60 }
            try value.validate()
            try JSONEncoder().encode(value).write(to: root.appendingPathComponent("lifecycle-settings.json"), options: .atomic)
            lifecycleSettings = value; archiveNotBefore = ProcessInfo.processInfo.systemUptime + 30
        }
        updateControlTitles()
        return settingsSnapshot()
    }

    private func persistRiftConfiguration(_ config: RiftConfiguration, root: URL, displayChanged: Bool = false) throws {
        try config.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: root.appendingPathComponent("rift-configuration.json"), options: .atomic)
        if displayChanged {
            cancelSelections(reason: "displayPreferenceChanged"); frozenPress = nil
            screenshotEntry?.cancel()
        }
        arrivalCapture?.cancel()
        try rift?.updateConfiguration(config)
        screenshotEntry?.configure()
    }

    private func recordArrivalTrace(_ fields: [String: Any]) {
        guard CommandLine.arguments.contains("--arrival-trace") else { return }
        var event = fields
        event["scope"] = "software_boundaries_not_physical_pixels"
        event["metadataCandidate"] = CommandLine.arguments.contains(ArrivalSourceProfile.candidateArgument)
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        print("RIFTLET_ARRIVAL_TRACE " + line)
    }
    @objc private func addWebTestImages() {
        guard mode.generatesSyntheticImages, let store else { return }
        Task {
            do { try await seedSyntheticImages(store: store, addNewBatch: true); await refresh() }
            catch { showIssue("Could not create test images; existing queue preserved.") }
        }
    }
    @objc private func openGeometry() {
        guard let root else { return }; NSWorkspace.shared.open(root.appendingPathComponent("rift-configuration.json"))
    }
    @objc private func checkStorage() {
        guard let root, storageMeasurement == nil else { return }
        storageLine?.title = "正在检查私有存储…"
        setupStorage = .measuring; updateSetup()
        // Metadata work stays off MainActor and runs only after this explicit menu action.
        storageMeasurement = Task { [weak self] in
            defer { self?.storageMeasurement = nil; self?.updateSetup() }
            do {
                let usage = try await Task.detached(priority: .utility) {
                    try PrivateStorageUsage.measure(privateRoot: root)
                }.value
                let size: String
                if let bytes = usage.logicalBytes, bytes <= UInt64(Int64.max) {
                    size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                } else { size = "用量不明" }
                let scope = usage.isComplete ? "" : " · 部分统计"
                self?.storageLine?.title = "私有存储：\(size) · \(usage.regularFileCount) 个文件\(scope)"
                self?.storageLine?.toolTip = "文件逻辑大小包括已用图片、恢复记录与数据库；没有删除文件。"
                if let bytes = usage.logicalBytes { self?.setupStorage = .measured(bytes: bytes, complete: usage.isComplete) }
                else { self?.setupStorage = .unavailable }
            } catch {
                self?.storageLine?.title = "私有存储暂不可读；已有文件保留"
                self?.setupStorage = .unavailable
            }
        }
    }
    @objc private func reload() {
        // Source changes use the one gated first-use recheck entry. Geometry
        // reload must not start an untracked task that can outlive Pause.
        guard let root else { return }
        do {
            let config = try JSONDecoder().decode(RiftConfiguration.self, from: Data(contentsOf: root.appendingPathComponent("rift-configuration.json")))
            try rift?.updateConfiguration(config)
        } catch { setupIssue = .configurationUnavailable; updateSetup() }
    }
}

/// Checks the packaged development boundary without touching Chrome, the real
/// capture folder, the pasteboard, or the user's persistent application data.
private enum WebAcceptanceSelfCheck {
    static func run() async throws {
        let program = try ChatGPTWebPageProgram.load()
        guard !program.sourceID.isEmpty, !program.functionSource.isEmpty,
              program.functionSource.utf8.count <= 128 * 1024,
              try ApplicationMode.resolve([]) == .capture,
              try ApplicationMode.resolve(["--simulate"]) == .simulation,
              try ApplicationMode.resolve(["--web-acceptance"]) == .webAcceptance,
              Set([ApplicationMode.capture.directoryName, ApplicationMode.simulation.directoryName,
                   ApplicationMode.webAcceptance.directoryName]).count == 3 else {
            throw RiftletError.modeMismatch
        }
        do {
            _ = try ApplicationMode.resolve(["--web-acceptance", "--simulate"])
            throw RiftletError.invalidTransition
        } catch RiftletError.modeMismatch {}
        let profile = ChatGPTWebPageProgram.acceptanceProfile
        let policy = WebAcceptanceConfiguration.receiptPolicy
        guard policy.admittedProfiles.isEmpty, policy.uploadStartProfiles.isEmpty,
              policy.retrySafeProfiles.isEmpty, policy.syntheticRetrySafeProfiles.isEmpty,
              ReceiptPolicy().syntheticAcceptanceProfiles.isEmpty,
              ReceiptPolicy().syntheticUploadStartProfiles.isEmpty else { throw RiftletError.invalidTransition }
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "self-check", windowID: "1", tabID: "1",
            documentID: "synthetic-self-check", composerID: "synthetic", draftGeneration: "1")
        for origin in [AssetOrigin.synthetic, .systemScreenshot] {
            let image = ImportedAsset(sourceKey: "policy-\(origin.rawValue)", fileName: "self-check.png",
                sha256: String(repeating: "a", count: 64), byteCount: 1, pixelWidth: 1, pixelHeight: 1,
                mediaType: "image/png", origin: origin)
            let receipt = TransferReceipt(operationID: UUID(), assetID: image.id, attempt: 1,
                assetSHA256: image.sha256, target: target, outcome: .verifiedReady, profileID: profile.profileID,
                attachmentID: "synthetic-self-check-card", positiveReady: true, belongsToOriginalDraft: true)
            let start = TransferReceipt(operationID: receipt.operationID, assetID: image.id, attempt: 1,
                assetSHA256: image.sha256, target: target, outcome: .uploadStarted, profileID: profile.profileID,
                attachmentID: "synthetic-self-check-card", belongsToOriginalDraft: true, isUploading: true,
                uploadStartEvidence: UploadStartEvidence(profileID: ChatGPTWebPageProgram.acceptanceUploadStartProfileID,
                    signal: .correlatedProgress, evidenceID: UUID().uuidString, inputCount: 1))
            guard policy.allowsUploadStart(receipt: start, asset: image, mode: .production) == (origin == .synthetic),
                  !ReceiptPolicy().allowsUploadStart(receipt: start, asset: image, mode: .production),
                  policy.allowsConsumption(receipt: receipt, asset: image, mode: .production) == (origin == .synthetic),
                  !ReceiptPolicy().allowsConsumption(receipt: receipt, asset: image, mode: .production) else {
                throw RiftletError.modeMismatch
            }
        }
    }
}

private enum SyntheticImage {
    static func write(to url: URL, index: Int) throws {
        let width = index % 2 == 0 ? 420 : 240
        let height = index % 2 == 0 ? 260 : 400
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RiftletError.invalidAsset("Synthetic context") }
        context.setFillColor(CGColor(red: 0.86, green: 0.90, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for row in 0..<6 {
            context.setFillColor(CGColor(red: 0.12 + Double(index) * 0.08, green: 0.30, blue: 0.50, alpha: 0.65))
            context.fill(CGRect(x: 24, y: 25 + row * 32, width: width - 48 - row * 12, height: 12))
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw RiftletError.invalidAsset("Synthetic PNG") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RiftletError.invalidAsset("Synthetic write") }
    }
}

private enum SelfCheck {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-self-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("synthetic.png")
        try SyntheticImage.write(to: source, index: 0)
        let privateRoot = root.appendingPathComponent("private")
        let databaseURL = privateRoot.appendingPathComponent("queue.sqlite")
        let store = try QueueStore(databaseURL: databaseURL, mode: .simulation)
        let importer = PrivateAssetImporter(privateRoot: privateRoot, store: store)
        let record = try await importer.importFile(at: source, origin: .synthetic)
        let coordinator = TransferCoordinator(store: store, adapter: SimulationAdapter(settlementDelay: 0), mediaDirectory: privateRoot.appendingPathComponent("media"))
        try await coordinator.select(record.id)
        guard let started = try await store.asset(id: record.id), started.visibility == .swallowed,
              started.status != .used, let operationID = started.activeOperationID,
              try await store.uploadStartReceipt(for: operationID) != nil else { throw RiftletError.invalidTransition }
        try await coordinator.observePending()
        let reopened = try QueueStore(databaseURL: databaseURL, mode: .simulation)
        try await reopened.recoverInterruptedOperations()
        guard try await reopened.assets().isEmpty,
              try await reopened.asset(id: record.id)?.status == .used,
              FileManager.default.fileExists(atPath: source.path),
              FileManager.default.fileExists(atPath: privateRoot.appendingPathComponent("media").appendingPathComponent(record.image.fileName).path) else {
            throw RiftletError.invalidTransition
        }
        let usage = try PrivateStorageUsage.measure(privateRoot: privateRoot)
        guard usage.isComplete,
              usage.areas.first(where: { $0.area == .media })?.regularFileCount == 1,
              (usage.logicalBytes ?? 0) >= UInt64(record.image.byteCount) else {
            throw RiftletError.invalidTransition
        }
    }
}
