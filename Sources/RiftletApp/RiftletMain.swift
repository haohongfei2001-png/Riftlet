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
        if CommandLine.arguments.contains("--system-screenshot-candidate-self-check") {
            Task {
                do {
                    try await SystemScreenshotCandidateSelfCheck.run()
                    print("RIFTLET_SYSTEM_SCREENSHOT_CANDIDATE_SELF_CHECK_PASS: original-byte import, one software input, restricted start then independent completion, durable new-operation registration, legacy UNKNOWN unchanged, read-only restart; GENERATED_FIXTURE; CHROME_NOT_RUN; SYSTEM_SCREENSHOT_NOT_RUN; GUI_NOT_RUN")
                    exit(0)
                } catch { fputs("RIFTLET_SYSTEM_SCREENSHOT_CANDIDATE_SELF_CHECK_FAIL\n", stderr); exit(1) }
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
private final class ApplicationController: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private lazy var feedback = FeedbackHost(modeDirectory: mode.directoryName)
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var storageLine: NSMenuItem?
    private var storageMeasurement: Task<Void, Never>?
    private var setup: RiftSetupController?
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
    private var requestingPermission = false
    private var automationPermission: AutomationPermissionState = .notNeeded
    private var attachmentObservationStarted = false
    private var attachmentObservationStarting = false
    private var terminating = false
    private var permissionResumer: PassivePermissionResume?
    private var permissionActivationObserver: NSObjectProtocol?
    private var permissionWakeObserver: NSObjectProtocol?
    private let captureLocation = SystemCaptureLocationProvider()
    private lazy var firstUse = FirstUsePreferences(modeName: mode.directoryName)
    private lazy var folderAccess = ScreenshotFolderAccess(modeName: mode.directoryName)
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
    private var root: URL!
    private var visibleIDs = Set<UUID>()
    private var refreshRunning = false
    private var refreshRequested = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var historyGeneration: UInt64 = 0
    private var history: RiftHistoryController?
    private var historyOffset = 0
    private var userHidden = false
    private var captureIsPaused = false
    private var changingHidden = false
    private var lifecycleSettings = LifecycleSettings()
    private let interactionFence = QueueInteractionFence()
    private var archiveTask: Task<Void, Never>?
    private var archiveWakeObserver: NSObjectProtocol?
    private var archiveNotBefore: TimeInterval = 0
    private var archiveClock: (wall: Date, uptime: TimeInterval)?
    private var completionWatch: Task<Void, Never>?
    private var originalRecoveryIDs: [UUID]?
    private var originalRecoveryTask: Task<Void, Never>?
    private var startupCompletedIDs = Set<UUID>()
    private var targetArmer: Task<Void, Never>?
    private var armScheduler = TargetArmScheduler()
    private var armingAdapter: (any AttachmentAdapter)?
    private var activationObserver: NSObjectProtocol?
    private var lastForegroundSession: String?
    private var diagnosticEvents = 0
    private var visibilityTrace = AcceptanceTraceDeduplicator<UUID, [String]>()
    private var readyTrace = AcceptanceTraceDeduplicator<UUID, [String]>()
    private var pendingArmReason = "startup"
    private var chromeActivity: ChromeActivityObserver?
    private var deferredChromeActivityBinding = DeferredChromeActivityBinding()
    private var armedTarget: ArmedTarget?
    private var armedCaptureDiagnostics: CapturedTargetDiagnostics?
    private var activeCaptureInvocation: CaptureInvocationContext?
    private var frozenPress: (id: UUID, target: TargetLease?, refusalReason: String,
        eventUptime: TimeInterval, acceptedUptime: TimeInterval, acknowledgedUptime: TimeInterval?, epoch: UUID,
        captureRequestID: UUID?, armAttemptID: UUID?)?
    private let selectionAuthority = SelectionAuthority()
    private let selectionSubmissions = SelectionSubmissionQueue()
    private var selectionUIOwners: [UUID: UUID] = [:]
    private var preparedFeedbackOperations: [UUID: UUID] = [:]
    private var armSession = UUID()
    private var wakeObserver: NSObjectProtocol?
    private var watchedCompletions = Set<UUID>()
    private var observationBackoff: [UUID: (failures: Int, next: Date)] = [:]
    private var instanceDescriptor: Int32 = -1
    private let mode: ApplicationMode
    private var simulation: Bool { mode == .simulation }

    init(mode: ApplicationMode) { self.mode = mode; super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        _ = feedback // Independent sidecar initializes off the screenshot path.
        installSetup()
        // The first ordinary launch explains collection before its first source
        // read. Acceptance mode must not steal the test browser's focus.
        if mode.collectsSystemScreenshots, firstUse.needsAutomaticPresentation {
            showSetup(); firstUse.recordPresentation()
        }
        Task {
            do { try await start() }
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
        if initialized, setup?.isVisible == true { recheckSetup() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        feedback.prepareTermination { accepted in sender.reply(toApplicationShouldTerminate: accepted) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminating = true
        permissionResumer?.stop()
        if let permissionActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(permissionActivationObserver) }
        if let permissionWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(permissionWakeObserver) }
        completionWatch?.cancel()
        originalRecoveryTask?.cancel()
        archiveTask?.cancel()
        targetArmer?.cancel()
        cancelSelections(reason: "termination")
        selectionSubmissions.stop()
        armScheduler.stop(); armedTarget = nil; frozenPress = nil
        armedCaptureDiagnostics = nil
        deferredChromeActivityBinding.cancel()
        chromeActivity?.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let archiveWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(archiveWakeObserver) }
        screenshotEntry?.close()
        rift?.close()
        history?.close()
        setup?.close()
        folderAccess.stop()
        if let sourceBinding { Task { await sourceBinding.stop() } }
        if instanceDescriptor >= 0 { flock(instanceDescriptor, LOCK_UN); Darwin.close(instanceDescriptor) }
    }

    private func start() async throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = base.appendingPathComponent(mode.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        instanceDescriptor = Darwin.open(root.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard instanceDescriptor >= 0, flock(instanceDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw RiftletError.database("This data directory already has a running Riftlet instance")
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
        if mode == .systemScreenshotCandidate {
            _ = try await PrivateAssetImporter(privateRoot: root, store: store).recover()
            try await SystemScreenshotCandidateConfiguration.validateStore(store)
        }
        let configurationURL = root.appendingPathComponent("rift-configuration.json")
        let configuration: RiftConfiguration
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            configuration = try JSONDecoder().decode(RiftConfiguration.self, from: Data(contentsOf: configurationURL))
        } else {
            configuration = RiftConfiguration()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: configurationURL, options: [.atomic])
        }
        try configuration.validate()
        let lifecycleURL = root.appendingPathComponent("lifecycle-settings.json")
        if FileManager.default.fileExists(atPath: lifecycleURL.path) {
            lifecycleSettings = try JSONDecoder().decode(LifecycleSettings.self, from: Data(contentsOf: lifecycleURL))
        } else { try JSONEncoder().encode(lifecycleSettings).write(to: lifecycleURL, options: .atomic) }
        try lifecycleSettings.validate()
        rift = RiftPanelController(mediaDirectory: root.appendingPathComponent("media"), configuration: configuration,
            onPress: { [weak self] id, timestamp in self?.freezePress(id, timestamp: timestamp) },
            onSelectionBoundary: { [weak self] boundary in self?.recordSelection(boundary) },
            onApproach: { [weak self] in self?.requestArm(reason: "pointerApproach") },
            onPresentationBoundary: { [weak self] boundary in self?.recordPresentation(boundary) },
            holdsSelectionUntilFinished: true, interactionFence: interactionFence,
            onRemove: { [weak self] id in self?.removeVisible(id) }) { [weak self] id in
            guard let self else { return }
            let press = self.frozenPress?.id == id ? self.frozenPress : nil
            let frozen = press?.target
            let revision = self.rift?.selectionRevision(for: id)
            self.frozenPress = nil
            var accepted: AcceptedSelection?
            if self.mode.usesWebAdapter, let press, let target = frozen, let revision, let ack = press.acknowledgedUptime {
                let token = AcceptedSelection(assetID: id, target: target, hostEpoch: press.epoch,
                    acknowledgedUptime: ack, eventUptime: press.eventUptime, acceptedUptime: press.acceptedUptime,
                    visibilityRevision: revision, deadlineUptime: press.acceptedUptime + 30,
                    captureRequestID: press.captureRequestID, armAttemptID: press.armAttemptID)
                if self.selectionAuthority.insert(token, now: ProcessInfo.processInfo.systemUptime) { accepted = token }
            }
            if accepted != nil { self.feedback.diagnostics.record(.selectionAccepted) }
            let originalSelection = accepted
            let selectionOwner = originalSelection?.id ?? UUID()
            self.selectionUIOwners[id] = selectionOwner
            let feedback: @MainActor (String?) -> Void = { [weak self] text in
                guard let self, self.selectionUIOwners[id] == selectionOwner,
                      let revision, self.rift?.selectionRevision(for: id) == revision else { return }
                self.rift?.setFeedback(text, for: id)
            }
            let submit: @MainActor (UInt64) async -> Void = { ordinal in
                if self.selectionUIOwners[id] == selectionOwner {
                    self.rift?.clearFeedback(matching: ProductStatus.AttachmentFeedback.waiting.text, for: id)
                }
                self.recordAcceptance(["event": "selection_submission_started", "selectionOrdinal": ordinal,
                    "assetID": id.uuidString, "uptime": ProcessInfo.processInfo.systemUptime])
                guard !self.mode.usesWebAdapter || self.watchedCompletions.count < 64 else {
                    self.showIssue("Acceptance observation limit reached; images retained.")
                    self.cancelOriginalSelection(originalSelection, reason: "observationLimit")
                    self.finishOriginalSelection(id, token: originalSelection, revision: revision, ownerID: selectionOwner)
                    return
                }
                do {
                    if self.mode.usesWebAdapter, originalSelection == nil {
                        self.applyAutomationPermission(await self.inspectAutomationPermission(reason: "selection", assetID: id, expectedSession: frozen?.sessionID))
                        guard self.automationPermission == .granted else {
                            feedback("Chrome 附件访问暂不可用；图片保留。请在运行状态中查看原因。")
                            self.finishOriginalSelection(id, token: originalSelection, revision: revision, ownerID: selectionOwner); self.updateSetup()
                            return
                        }
                    }
                    if self.mode.usesWebAdapter {
                        if let originalSelection { try await self.transfer?.select(originalSelection) }
                        else {
                            // No original pre-event ACK: the old path may only
                            // reconcile an existing operation, never capture.
                            try await self.transfer?.select(id, frozenTarget: nil, visibilityRevision: revision)
                        }
                    }
                    else { try await self.transfer?.select(id, visibilityRevision: revision) }
                    if let record = try await self.store?.asset(id: id), record.visibility == .visible,
                       let operationID = record.activeOperationID, record.status == .failed {
                        let reason = try await self.store?.operationReason(for: operationID)
                        feedback(ProductStatus.operationFeedback(reason).text)
                    }
                }
                catch {
                    if self.mode.usesWebAdapter {
                        self.setupIssue = ProductStatus.clickIssue(error,
                            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, webAcceptance: true)
                        if self.setupIssue == .permissionDenied { self.applyAutomationPermission(.denied) }
                    }
                    feedback(self.mode == .capture ? "此版本尚未启用真实截图附加；图片保留。"
                        : (ProductStatus.clickFeedback(error)?.text ?? self.setupIssue?.text
                           ?? "当前附件目标暂不可用；图片保留，可在运行状态中查看原因。"))
                    self.feedback.diagnostics.record(.selectionRejected)
                    self.cancelOriginalSelection(originalSelection, reason: "selectionRejected")
                    self.finishOriginalSelection(id, token: originalSelection, revision: revision, ownerID: selectionOwner)
                    self.updateSetup()
                }
                self.finishOriginalSelection(id, token: originalSelection, revision: revision, ownerID: selectionOwner)
                await self.refresh()
            }
            guard self.mode.usesWebAdapter else {
                Task { await submit(0) }
                return
            }
            let waitsForSubmission = self.selectionSubmissions.hasOutstandingSubmission
            let ordinal = self.selectionSubmissions.enqueue(selectionID: originalSelection?.id,
                deadline: originalSelection?.deadlineUptime,
                cancelled: { [weak self] in
                    feedback(ProductStatus.AttachmentFeedback.cancelledBeforeInput.text)
                    self?.cancelOriginalSelection(originalSelection, reason: "submissionCancelled")
                    self?.finishOriginalSelection(id, token: originalSelection, revision: revision, ownerID: selectionOwner)
                }, run: submit)
            if let ordinal {
                if waitsForSubmission, originalSelection != nil {
                    feedback(ProductStatus.AttachmentFeedback.waiting.text)
                }
                self.recordAcceptance(["event": "selection_enqueued", "selectionOrdinal": ordinal,
                    "assetID": id.uuidString, "uptime": ProcessInfo.processInfo.systemUptime])
            } else {
                feedback(ProductStatus.AttachmentFeedback.cancelledBeforeInput.text)
                self.cancelOriginalSelection(originalSelection, reason: "submissionLimit")
                self.finishOriginalSelection(id, token: originalSelection, revision: revision, ownerID: selectionOwner)
            }
        }
        rift?.setUserHidden(userHidden)
        history = RiftHistoryController(mediaDirectory: root.appendingPathComponent("media"),
            onRestore: { [weak self] id in self?.restoreHistory(id) },
            onRemove: { [weak self] id in self?.removeVisible(id) },
            onReveal: { [weak self] id in self?.revealHistory(id) },
            onNextPage: { [weak self] in self?.changeHistoryPage(1) },
            onPreviousPage: { [weak self] in self?.changeHistoryPage(-1) })
        let composition = try ApplicationAttachmentComposition.make(mode: mode, root: root, store: store,
            traceEnabled: CommandLine.arguments.contains("--acceptance-trace"))
        let adapter = composition.adapter
        let policy = composition.policy
        let transfer = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root.appendingPathComponent("media"),
            policy: policy, onChange: { [weak self] in await self?.refresh() },
            onSelectionSettled: { [weak self] id in await self?.finishPreparedSelection(id) },
            onAcceptedSelectionSettled: { [weak self] selection in
                await self?.finishOriginalSelection(selection.assetID, token: selection, revision: selection.visibilityRevision)
            }, onAcceptedSelectionFinished: { [weak self] id in
                await self?.selectionAuthority.finish(id)
            }, validateAcceptedSelection: { [weak self] selection in
                await self?.validateAcceptedSelection(selection) ?? false
            })
        self.transfer = transfer
        armingAdapter = mode.usesWebAdapter ? adapter : nil
        // Durable crash recovery remains local even when Automation is denied.
        // No page observation is attempted until a passive check says allowed.
        try await store.recoverInterruptedOperations()
        originalRecoveryIDs = try await store.unresolvedOperations().map(\.id)
        startupCompletedIDs = mode != .capture ? Set(try await store.successfulOperations().map(\.id)) : []
        recordAcceptance(["event": "local_recovery_complete", "uptime": ProcessInfo.processInfo.systemUptime])
        if mode.usesWebAdapter {
            // Process identity only, not permission or a page/attachment lease.
            lastForegroundSession = foregroundChromeSession
            installPassivePermissionRecovery()
            applyAutomationPermission(await inspectAutomationPermission(reason: "startup"))
        }
        try await startAttachmentObservationIfPermitted()
        if !mode.collectsSystemScreenshots {
            statusLine?.title = simulation ? "SIMULATION · synthetic images only · no ChatGPT input"
                : "WEB ACCEPTANCE · generated images · real Chrome input"
        } else {
            do {
                detectedSource = try await captureLocation.currentDirectory()
                if let detectedSource { folderAccess.restore(for: detectedSource) }
            } catch { receiveCaptureDiagnostic(.classify(error, context: .locationPreference)) }
            let service = CaptureService(store: store, privateRoot: root, sourceDirectory: detectedSource ?? CaptureSource.defaultDirectory(),
                                         onChange: { [weak self] in await self?.refresh() },
                                         onDiagnostic: { [weak self] value in await self?.receiveCaptureDiagnostic(value) })
            capture = service
            let binding = CaptureSourceBinding(service: service, provider: captureLocation,
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
                    onIssue: { [weak self] message in self?.showIssue(message) })
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
        }, onResult: { [weak self] result in
            self?.applyAutomationPermission(result); self?.updateSetup()
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
                    guard let self, !self.attachmentObservationStarted,
                          let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.bundleIdentifier == "com.google.Chrome" else { return }
                    self.lastForegroundSession = self.foregroundChromeSession
                    self.permissionResumer?.request()
                }
            }
        permissionWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.attachmentObservationStarted else { return }
                    self.permissionResumer?.request()
                }
            }
    }

    /// Measure the existing passive check without caching authorization or
    /// substituting another process for an original selection. Only acceptance
    /// trace logs these bounds; a session string grants no page authority.
    private func inspectAutomationPermission(reason: String, assetID: UUID? = nil,
                                             invocation: CaptureInvocationContext? = nil,
                                             expectedSession: String? = nil) async -> AutomationPermissionState {
        let started = ProcessInfo.processInfo.systemUptime
        let result = await permissionGate.inspect(expectedSession: expectedSession)
        guard mode.usesWebAdapter, CommandLine.arguments.contains("--acceptance-trace") else { return result }
        var fields: [String: Any] = ["event": "permission_check", "purpose": reason,
            "permissionRequestID": UUID().uuidString, "startedUptime": started,
            "endedUptime": ProcessInfo.processInfo.systemUptime, "result": String(describing: result),
            "askedUser": false, "originalSessionBound": expectedSession != nil]
        if let assetID { fields["assetID"] = assetID.uuidString }
        if let invocation {
            fields["captureRequestID"] = invocation.requestID.uuidString
            fields["armAttemptID"] = invocation.armAttemptID.uuidString
            fields["hostEpoch"] = invocation.hostEpoch.uuidString
        }
        recordAcceptance(fields)
        return result
    }

    private func startOriginalRecovery() {
        guard !terminating, let ids = originalRecoveryIDs, let transfer else { return }
        originalRecoveryIDs = nil
        originalRecoveryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.originalRecoveryTask = nil }
            self.recordAcceptance(["event": "original_recovery_started", "uptime": ProcessInfo.processInfo.systemUptime,
                "operationCount": ids.count])
            do {
                // Recheck permission independently after prebinding. This never
                // captures a target or replays a previously refused selection.
                if self.mode.usesWebAdapter {
                    self.applyAutomationPermission(await self.inspectAutomationPermission(reason: "originalRecovery"))
                    guard self.automationPermission == .granted else { return }
                }
                try Task.checkCancellation()
                try await transfer.recoverOriginalObservations(operationIDs: ids)
            } catch { self.setupIssue = .targetUnavailable; self.updateSetup() }
            self.recordAcceptance(["event": "original_recovery_finished", "uptime": ProcessInfo.processInfo.systemUptime])
        }
    }

    private func startAttachmentObservationIfPermitted() async throws {
        guard !terminating, !attachmentObservationStarted, !attachmentObservationStarting, let transfer,
              !mode.usesWebAdapter || automationPermission == .granted else { return }
        attachmentObservationStarting = true
        defer { attachmentObservationStarting = false }
        // All local recovery/snapshots completed before any arming or selection.
        // Remote observation is original-ID-only and cannot reset newer operations.
        try Task.checkCancellation()
        guard !terminating else { return }
        watchedCompletions = startupCompletedIDs
        attachmentObservationStarted = true
        if mode.usesWebAdapter, let armingAdapter { startArming(adapter: armingAdapter) }
        else { startOriginalRecovery() }
        guard mode != .capture else { return }
        completionWatch = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: self?.simulation == true ? 400_000_000 : 5_000_000_000) } catch { return }
                guard let self else { return }
                guard self.originalRecoveryTask == nil, self.originalRecoveryIDs == nil else { continue }
                if self.mode.usesWebAdapter {
                    self.applyAutomationPermission(await self.inspectAutomationPermission(reason: "backgroundObservation"))
                    self.updateSetup()
                    guard self.automationPermission == .granted else {
                        self.armedTarget = nil; self.armedCaptureDiagnostics = nil; self.frozenPress = nil
                        continue
                    }
                }
                do { try await transfer.observePending(limit: self.simulation ? 8 : 4) }
                catch { self.showIssue("附件结果暂时无法核实；本机图片与原操作仍保留，不会自动重新附加。") }
                for id in self.watchedCompletions {
                    if Task.isCancelled { return }
                    if let backoff = self.observationBackoff[id], backoff.next > Date() { continue }
                    do {
                        if try await !transfer.observeCompleted(operationID: id) { self.watchedCompletions.remove(id) }
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
        setup = RiftSetupController(onRecheck: { [weak self] in self?.recheckSetup() },
            onOpenSource: { [weak self] in self?.openScreenshotSource() },
            onPermission: { [weak self] in self?.requestAutomationPermission() },
            onDismiss: {},
            onChooseSourceAccess: mode.collectsSystemScreenshots ? { [weak self] in self?.chooseSourceAccess() } : nil,
            onToggleHidden: { [weak self] in self?.toggleHidden() },
            onToggleCollection: mode.collectsSystemScreenshots ? { [weak self] in self?.toggleCollection() } : nil,
            onOpenHistory: { [weak self] in self?.showHistory() })
        updateSetup()
    }

    private func updateSetup() {
        let issue: SetupIssue? = visibilitySettingFailed ? .visibilityPreferenceUnsaved
            : (collectionSettingFailed ? .collectionPreferenceUnsaved : (captureDiagnostic.map(ProductStatus.issue) ?? setupIssue))
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
            isChecking: captureControl.isBusy || requestingPermission || !initialized)
        if setup?.presentation.snapshot != snapshot { setup?.update(snapshot: snapshot) }
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

    @objc private func showFeedback() { feedback.open() }

    @objc private func showSetup() { updateSetup(); setup?.show() }

    @objc private func recheckSetup() {
        guard initialized, !requestingPermission, let token = captureControl.begin(.recheck) else { return }
        updateControlTitles()
        Task {
            defer { captureControl.finish(token); updateControlTitles() }
            if mode.collectsSystemScreenshots, let capture, let binding = sourceBinding {
                do {
                    do { detectedSource = try await captureLocation.currentDirectory() }
                    catch { detectedSource = nil; throw error }
                    if let detectedSource { folderAccess.restore(for: detectedSource) }
                    // Recheck cannot undo Pause. A failed first start may be
                    // stopped; start is idempotent and handles that recovery.
                    if !captureIsPaused {
                        try await binding.start()
                        await binding.refresh()
                        try await capture.recheck()
                    }
                    captureStatus = await capture.statusSnapshot()
                    acceptCaptureStatus(preferenceIssue: nil)
                    if setupIssue == .sourceAccess, captureStatus?.sourceAccessible == true { setupIssue = nil }
                } catch { receiveCaptureDiagnostic(.classify(error, context: .source)) }
            }
            applyAutomationPermission(await inspectAutomationPermission(reason: "setupRecheck"))
            do { try await startAttachmentObservationIfPermitted() }
            catch { setupIssue = .targetUnavailable }
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
        guard mode.collectsSystemScreenshots, !captureControl.isBusy, let source = detectedSource else { return }
        let panel = NSOpenPanel()
        panel.title = "允许 Riftlet 读取系统截图位置"
        panel.message = "请选择下方显示的系统截图文件夹。只授予读取权限，不更改系统保存位置，也不导入其他文件夹。"
        panel.prompt = "允许读取"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = source
        panel.begin { [weak self] response in
            guard response == .OK, let selected = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let actual = try await self.captureLocation.currentDirectory()
                    try self.folderAccess.accept(selected, actualSource: actual)
                    self.recheckSetup()
                } catch { self.setupIssue = .sourceAccess; self.updateSetup() }
            }
        }
    }

    private func requestAutomationPermission() {
        guard mode.usesWebAdapter, !captureControl.isBusy, !requestingPermission else { return }
        if automationPermission == .denied { openPrivacySettings(automation: true); return }
        requestingPermission = true
        updateSetup()
        Task {
            defer { requestingPermission = false; updateSetup() }
            applyAutomationPermission(await permissionGate.requestFromUserAction(expectedSession: lastForegroundSession))
            if automationPermission == .denied { setupIssue = .permissionDenied }
            else if automationPermission == .granted {
                if setupIssue == .permissionDenied { setupIssue = nil }
                do { try await startAttachmentObservationIfPermitted() }
                catch { setupIssue = .targetUnavailable }
            }
        }
    }

    @objc private func openFilePrivacySettings() { openPrivacySettings(automation: false) }
    private func openPrivacySettings(automation: Bool) {
        let pane = automation ? "Privacy_Automation" : "Privacy_FilesAndFolders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"),
           NSWorkspace.shared.open(url) { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(app)
        }
    }

    @objc private func launchSimulation() {
        guard mode.collectsSystemScreenshots, Bundle.main.bundleURL.pathExtension == "app" else { return }
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
        guard mode == .capture, Bundle.main.bundleURL.pathExtension == "app" else { return }
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
        guard let revision, rift?.selectionRevision(for: assetID) == revision else { return }
        rift?.finishSelection(assetID)
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
        selectionSubmissions.cancel(selectionIDs: Set(ids))
        recordAcceptance(["event": "selection_authority_cancelled", "reason": reason,
            "uptime": ProcessInfo.processInfo.systemUptime, "singleAsset": assetID != nil])
        guard !ids.isEmpty, let transfer else { return }
        Task { try? await transfer.cancelAcceptedSelections(ids: ids, reason: reason) }
    }

    private func applyAutomationPermission(_ state: AutomationPermissionState) {
        let lostPermission = automationPermission == .granted && state != .granted
        automationPermission = state
        if mode.usesWebAdapter, state != .granted { feedback.diagnostics.record(.permissionUnavailable) }
        guard mode.usesWebAdapter, state != .granted else { return }
        cancelSelections(reason: "permissionUnavailable")
        armedTarget = nil; armedCaptureDiagnostics = nil; frozenPress = nil
        if lostPermission {
            let wake = armScheduler.request(invalidateEpoch: true)
            armSession = armScheduler.epoch
            deferredChromeActivityBinding.request(afterCaptureIn: armSession)
            // An idle scheduler has no capture completion to deliver this wake.
            // Dropping it leaves pending=true forever: later fallback/activation
            // requests coalesce without starting a fresh target observation.
            if wake { performPendingArm() }
        }
    }

    private func validateAcceptedSelection(_ selection: AcceptedSelection) async -> Bool {
        func permits() -> Bool {
            selectionAuthority.permits(selection, epoch: armSession, foregroundSession: foregroundChromeSession,
                hidden: userHidden, terminating: terminating, now: ProcessInfo.processInfo.systemUptime)
        }
        guard permits() else { return false }
        let permission = await inspectAutomationPermission(reason: "acceptedSelectionValidation", assetID: selection.assetID,
            expectedSession: selection.target.sessionID)
        applyAutomationPermission(permission)
        let accepted = permission == .granted && permits()
        var fields: [String: Any] = ["event": "accepted_selection_validation", "selectionID": selection.id.uuidString,
            "assetID": selection.assetID.uuidString, "hostEpoch": selection.hostEpoch.uuidString,
            "originalEventUptime": selection.eventUptime, "acceptedUptime": selection.acceptedUptime,
            "effectiveAckUptime": selection.acknowledgedUptime, "visibilityRevision": selection.visibilityRevision,
            "deadlineUptime": selection.deadlineUptime, "uptime": ProcessInfo.processInfo.systemUptime,
            "accepted": accepted]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(selection.target) {
            fields["targetDigest"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        if let id = selection.captureRequestID { fields["captureRequestID"] = id.uuidString }
        if let id = selection.armAttemptID { fields["armAttemptID"] = id.uuidString }
        recordAcceptance(fields)
        return accepted
    }

    private func finishPreparedSelection(_ id: UUID) {
        // Web submissions release only their exact original token/revision owner.
        guard !mode.usesWebAdapter else { return }
        // Coordinator awaits committed refresh before this callback. Releasing
        // the UI reservation cannot flush a stale pre-prepare archive snapshot.
        rift?.finishSelection(id)
    }

    private var foregroundChromeSession: String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.google.Chrome", let launch = app.launchDate else { return nil }
        return "\(app.processIdentifier):\(launch.timeIntervalSince1970)"
    }

    private func freezePress(_ id: UUID, timestamp: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        let target = armedTarget?.freeze(eventUptime: timestamp, nowUptime: now,
            hostSession: armSession, foregroundSession: foregroundChromeSession)
        // Classification is diagnostic only. ArmedTarget.freeze remains the sole
        // timing/epoch gate; no native diagnostic time supplies click authority.
        let refusal: String
        if target != nil { refusal = "none" }
        else if let armed = armedTarget {
            if armed.hostSession != armSession { refusal = "hostEpochMismatch" }
            else if armed.target.sessionID != foregroundChromeSession { refusal = "foregroundSessionMismatch" }
            else if !armed.acknowledgedUptime.isFinite || !timestamp.isFinite || !now.isFinite || armed.acknowledgedUptime < 0 {
                refusal = "invalidClock"
            } else if armed.acknowledgedUptime >= timestamp { refusal = "ackNotBeforeOriginalEvent" }
            else { refusal = "originalEventInFuture" }
        } else { refusal = "noPublishedTarget" }
        frozenPress = (id, target, refusal, timestamp, now, armedTarget?.acknowledgedUptime, armSession,
            armedCaptureDiagnostics?.context.requestID, armedCaptureDiagnostics?.context.armAttemptID)
    }

    private func startArming(adapter: any AttachmentAdapter) {
        guard !armScheduler.isRunning, !terminating else { return }
        recordAcceptance(["event": "arming_started", "uptime": ProcessInfo.processInfo.systemUptime])
        armingAdapter = adapter
        armScheduler.start(); armSession = armScheduler.epoch
        lastForegroundSession = foregroundChromeSession
        chromeActivity = ChromeActivityObserver { [weak self] reason in self?.requestArm(reason: reason) }
        // AX notifications are hints. Their synchronous remote registration must
        // not precede the first authoritative capture/ACK or epoch revocation.
        deferredChromeActivityBinding.request(afterCaptureIn: armSession)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.requestArm(reason: "wake", invalidate: true)
                }
            }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.lastForegroundSession != self.foregroundChromeSession else { return }
                    self.lastForegroundSession = self.foregroundChromeSession
                    self.requestArm(reason: "activation", invalidate: true)
                }
            }
        performPendingArm()
    }

    private func requestArm(reason: String = "fallback", invalidate: Bool = false) {
        pendingArmReason = reason
        if invalidate {
            cancelSelections(reason: reason)
            armedTarget = nil; armedCaptureDiagnostics = nil; frozenPress = nil
        }
        let wake = armScheduler.request(invalidateEpoch: invalidate)
        armSession = armScheduler.epoch
        if invalidate { deferredChromeActivityBinding.request(afterCaptureIn: armSession) }
        if wake { performPendingArm() }
    }

    private func bindDeferredChromeActivity(afterCaptureIn epoch: UUID) {
        guard !terminating, epoch == armSession,
              deferredChromeActivityBinding.take(afterCaptureIn: epoch, isRunning: armScheduler.isRunning) else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let available = chromeActivity?.bind(to: NSWorkspace.shared.frontmostApplication) ?? false
        let ended = ProcessInfo.processInfo.systemUptime
        recordAcceptance(["event": "chrome_activity_binding", "available": available,
            "hostEpoch": epoch.uuidString, "phase": "afterCaptureCompletion",
            "startedUptime": started, "endedUptime": ended, "elapsedMS": (ended - started) * 1000,
            "authorizesInput": false])
    }

    private func performPendingArm() {
        guard let adapter = armingAdapter, let attempt = armScheduler.begin() else { return }
        targetArmer?.cancel() // Only the fallback sleep; never an in-flight capture.
        targetArmer = nil
        let reason = pendingArmReason
        let started = ProcessInfo.processInfo.systemUptime
        let invocation = CaptureInvocationContext(armAttemptID: attempt.id, hostEpoch: attempt.epoch)
        activeCaptureInvocation = invocation
        Task { [weak self] in
            guard let self else { return }
            let taskEntered = ProcessInfo.processInfo.systemUptime
            var result: TargetLease?
            var diagnostics: CapturedTargetDiagnostics?
            var errorCode = "browserNotFrontmost"
            if let originalSession = self.foregroundChromeSession {
                do {
                    self.applyAutomationPermission(await self.inspectAutomationPermission(reason: "targetArming", invocation: invocation, expectedSession: originalSession))
                    guard self.automationPermission == .granted,
                          self.foregroundChromeSession == originalSession,
                          self.armSession == attempt.epoch else { throw WebAdapterError.disabled }
                    if let web = adapter as? WebAttachmentAdapter {
                        diagnostics = try await web.captureTargetWithDiagnostics(context: invocation)
                        result = diagnostics?.target
                    } else { result = try await adapter.captureTarget() }
                    errorCode = "none"
                }
                catch { errorCode = (error as? WebAdapterError).map { String(describing: $0) } ?? "unclassified" }
            }
            self.updateSetup()
            if self.activeCaptureInvocation == invocation { self.activeCaptureInvocation = nil }
            guard let completion = self.armScheduler.complete(attempt) else {
                self.recordAcceptance(["event": "arm_completion", "captureRequestID": invocation.requestID.uuidString,
                    "armAttemptID": attempt.id.uuidString, "hostEpoch": attempt.epoch.uuidString,
                    "publicationResult": "rejectedUnmatchedAttempt", "epochAccepted": false])
                return
            }
            var publication: TimeInterval?
            var reused = false
            var publicationResult = "rejectedEpochOrStopped"
            if completion.acceptsAcknowledgement {
                if let target = result, target.sessionID == self.foregroundChromeSession {
                    reused = self.armedTarget?.target == target
                    if !reused {
                        self.armedTarget = ArmedTarget(target: target,
                            acknowledgedUptime: ProcessInfo.processInfo.systemUptime, hostSession: attempt.epoch)
                        self.armedCaptureDiagnostics = diagnostics
                    }
                    // Actual acceptance on MainActor, never the earlier native
                    // arrival. Reused targets keep their original effective ACK.
                    publication = ProcessInfo.processInfo.systemUptime
                    publicationResult = reused ? "acceptedExistingTarget" : "publishedNewTarget"
                } else {
                    self.armedTarget = nil; self.armedCaptureDiagnostics = nil
                    publicationResult = result == nil ? "captureFailed" : "foregroundSessionChanged"
                }
            }
            var fields: [String: Any] = ["event": "arm_completion", "reason": reason, "startedUptime": started,
                "taskEnteredUptime": taskEntered, "endedUptime": ProcessInfo.processInfo.systemUptime, "error": errorCode,
                "captureRequestID": invocation.requestID.uuidString, "armAttemptID": attempt.id.uuidString,
                "hostEpoch": attempt.epoch.uuidString, "publicationResult": publicationResult,
                "reusedExistingArmedTarget": reused,
                "epochAccepted": completion.acceptsAcknowledgement, "armed": self.armedTarget != nil]
            if let diagnostics {
                fields["targetDigest"] = diagnostics.targetDigest
                fields["adapterValidatedUptime"] = diagnostics.adapterValidatedUptime
            }
            if let publication { fields["mainPublishedUptime"] = publication }
            if let armed = self.armedTarget { fields["effectiveAckUptime"] = armed.acknowledgedUptime }
            if let effective = self.armedCaptureDiagnostics {
                fields["effectiveCaptureRequestID"] = effective.context.requestID.uuidString
                fields["effectiveArmAttemptID"] = effective.context.armAttemptID.uuidString
            }
            self.recordAcceptance(fields)
            // Failed current-epoch captures also install the hint observer so
            // later focus/window activity can recover. Stale completions cannot.
            self.bindDeferredChromeActivity(afterCaptureIn: attempt.epoch)
            // The first prebind finishes before remote recovery enters the shared
            // adapter/transport, avoiding a startup queue behind old observations.
            self.startOriginalRecovery()
            if completion.shouldWake { self.performPendingArm() }
            else if self.armScheduler.isRunning {
                self.targetArmer = Task { [weak self] in
                    guard let self else { return }
                    do { try await Task.sleep(nanoseconds: self.visibleIDs.isEmpty ? 3_000_000_000 : 1_000_000_000) }
                    catch { return }
                    self.requestArm()
                }
            }
        }
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
        let now = ProcessInfo.processInfo.systemUptime
        var fields: [String: Any] = ["event": "selection_boundary", "source": boundary.source.rawValue,
            "assetID": boundary.assetID.uuidString, "eventUptime": boundary.eventUptime,
            "originalEventUptime": boundary.eventUptime, "callbackUptime": now, "selectionHandlerUptime": now,
            "hostEpoch": armSession.uuidString,
            "frozen": frozenPress?.id == boundary.assetID && frozenPress?.target != nil]
        if let frozen = frozenPress, frozen.id == boundary.assetID {
            fields["freezeResult"] = frozen.target == nil ? "refused" : "accepted"
            fields["refusalReason"] = frozen.refusalReason
        }
        if let effective = armedCaptureDiagnostics {
            fields["effectiveCaptureRequestID"] = effective.context.requestID.uuidString
            fields["effectiveArmAttemptID"] = effective.context.armAttemptID.uuidString
            fields["targetDigest"] = effective.targetDigest
        }
        if let pending = activeCaptureInvocation {
            fields["inFlightCaptureRequestID"] = pending.requestID.uuidString
            fields["inFlightArmAttemptID"] = pending.armAttemptID.uuidString
        }
        fields["armInFlight"] = armScheduler.inFlight != nil
        fields["hostEpochMatches"] = armedTarget?.hostSession == armSession
        fields["foregroundSessionMatches"] = armedTarget.map { $0.target.sessionID == foregroundChromeSession } ?? false
        if let ack = armedTarget?.acknowledgedUptime { fields["ackUptime"] = ack }
        if let number = boundary.eventNumber { fields["eventNumber"] = number }
        recordAcceptance(fields)
    }

    private func recordAcceptance(_ fields: [String: Any]) {
        guard mode.usesWebAdapter, CommandLine.arguments.contains("--acceptance-trace"), diagnosticEvents < 2048 else { return }
        diagnosticEvents += 1
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
            try? FileHandle.standardError.write(contentsOf: data + Data([10]))
        }
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
                var cancelledPreparedFeedback: [UUID: String] = [:]
                for (id, operationID) in preparedFeedbackOperations {
                    guard snapshot.contains(where: {
                        $0.id == id && $0.activeOperationID == operationID && $0.status == .failed && $0.visibility == .visible
                    }) else { continue }
                    cancelledPreparedFeedback[id] = ProductStatus.operationFeedback(
                        try await store.operationReason(for: operationID)).text
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
                let hasNewImages = !activeIDs.subtracting(visibleIDs).isEmpty
                visibleIDs = activeIDs
                pendingResultCount = Set(unresolved.filter { $0.phase != .prepared }.map(\.assetID)).count
                acceptCaptureStatus(preferenceIssue: preferenceIssue)
                watchedCompletions.formUnion(successful.map(\.id))
                if hasNewImages && mode.usesWebAdapter { requestArm(reason: "newImages") }
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
                    rift?.clearFeedback(matching: ProductStatus.AttachmentFeedback.preparing.text, for: id)
                }
                for (id, text) in cancelledPreparedFeedback { rift?.setFeedback(text, for: id) }
                for id in prepared.keys { rift?.setFeedback(ProductStatus.AttachmentFeedback.preparing.text, for: id) }
                preparedFeedbackOperations = prepared
                feedback.assets(snapshot) // Sampled local counts, not operation-level statistics.
                feedback.operations(successful + unresolved)
                if interactionFence.snapshot().blocked { feedback.diagnostics.record(.uiProjectionDeferred) }
                switch mode {
                case .capture:
                    statusItem?.button?.toolTip = "Riftlet · \(active.count) visible screenshots\(userHidden ? " · hidden" : "")"
                case .simulation: statusItem?.button?.toolTip = "Riftlet SIMULATION — synthetic only; start then delayed result"
                case .systemScreenshotCandidate: statusItem?.button?.toolTip = "Riftlet REAL TEST · 原图候选 · 生产准入关闭 · 待核实不重传"
                case .webAcceptance: statusItem?.button?.toolTip = "Riftlet WEB ACCEPTANCE · \(active.count) visible test images · unresolved records stay in local history"
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
        history.show()
        Task { await refreshHistory() }
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
        pauseItem?.isEnabled = mode.collectsSystemScreenshots && initialized && !captureControl.isBusy
        if let interval = lifecycleSettings.archiveAfterSeconds {
            archiveItem?.title = String(format: "闲置归档：%.2g 小时…", interval / 3600)
        } else { archiveItem?.title = "闲置归档：已关闭…" }
        updateSetup()
    }

    @objc private func toggleHidden() {
        guard let store, !changingHidden else { return }
        changingHidden = true
        let requested = !userHidden
        // Hide immediately; showing requires the persistent change to succeed.
        if requested {
            cancelSelections(reason: "hidden")
            frozenPress = nil
            userHidden = true; screenshotEntry?.setHidden(true); rift?.setUserHidden(true); updateControlTitles()
        }
        Task {
            defer { changingHidden = false; updateControlTitles() }
            do {
                try await store.setUserHidden(requested)
                visibilitySettingFailed = false
                userHidden = requested; rift?.setUserHidden(requested)
                screenshotEntry?.setHidden(requested)
                await refresh()
            } catch { visibilitySettingFailed = true; updateSetup() }
        }
    }

    @objc private func toggleCollection() {
        guard mode.collectsSystemScreenshots, initialized, let store, let binding = sourceBinding,
              let token = captureControl.begin(.changeCollection) else { return }
        updateControlTitles()
        let requested = !captureIsPaused
        Task {
            defer { captureControl.finish(token); updateControlTitles() }
            if requested { await binding.stop(); captureIsPaused = true }
            do {
                try await store.setCapturePaused(requested)
                collectionSettingFailed = false
            } catch {
                if let capture { captureStatus = await capture.statusSnapshot() }
                collectionSettingFailed = true
                updateSetup()
                return
            }
            do {
                // Persisted intent and actual running state are separate. A
                // failed resume must not be displayed as an explicit Pause.
                captureIsPaused = requested
                if !requested { try await binding.start() }
                if let capture { captureStatus = await capture.statusSnapshot() }
                await refresh()
            } catch {
                if let capture { captureStatus = await capture.statusSnapshot() }
                receiveCaptureDiagnostic(.classify(error, context: .source))
            }
        }
    }

    @objc private func configureArchive() {
        guard let root else { return }
        let alert = NSAlert()
        alert.messageText = "闲置截图归档"
        alert.informativeText = "距上次使用的小时数。输入 0 关闭；归档保留本机图片，不修改 ChatGPT 附件。时长可随时调整。"
        let field = NSTextField(string: lifecycleSettings.archiveAfterSeconds.map { String($0 / 3600) } ?? "0")
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn,
              let hours = Double(field.stringValue), hours.isFinite, hours >= 0 else { return }
        var settings = lifecycleSettings
        settings.archiveAfterSeconds = hours == 0 ? nil : hours * 3600
        do {
            try settings.validate()
            try JSONEncoder().encode(settings).write(to: root.appendingPathComponent("lifecycle-settings.json"), options: .atomic)
            lifecycleSettings = settings; archiveNotBefore = ProcessInfo.processInfo.systemUptime + 30
            updateControlTitles()
        } catch { showIssue("Archive setting was not saved; previous setting kept.") }
    }

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
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard let self else { return }
                await self.archiveIdleImages()
            }
        }
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
        guard uptime >= archiveNotBefore, !state.blocked else { return }
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
        let menu = NSMenu()
        let heading = NSMenuItem(title: simulation ? "离线模拟 · 没有真实上传"
            : (mode == .webAcceptance ? "Web 验收 · 仅生成图片" : "正在准备本地截图收录…"), action: nil, keyEquivalent: "")
        menu.addItem(heading); statusLine = heading
        add(menu, "开始使用与运行状态…", #selector(showSetup))
        add(menu, "反馈与建议…", #selector(showFeedback))
        if mode.collectsSystemScreenshots { add(menu, "文件访问设置…", #selector(openFilePrivacySettings)) }
        if mode == .webAcceptance {
            menu.addItem(NSMenuItem(title: "Chrome · ChatGPT Chat · Chinese UI · PNG test images", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "No message sending · UNKNOWN never retransmits", action: nil, keyEquivalent: ""))
            add(menu, "Add 3 generated test images", #selector(addWebTestImages))
        }
        if mode == .systemScreenshotCandidate {
            menu.addItem(NSMenuItem(title: "真实截图内部候选 · 未生产准入", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "普通已有聊天 · RGBA8 PNG · 开始即吞噬 · 不重传", action: nil, keyEquivalent: ""))
        }
        if simulation { add(menu, "Add 3 synthetic demo images", #selector(addWebTestImages)) }
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide rift", action: #selector(toggleHidden), keyEquivalent: "")
        hide.target = self; menu.addItem(hide); hideItem = hide
        if mode.collectsSystemScreenshots {
            add(menu, "截图…", #selector(beginScreenshot))
            let pause = NSMenuItem(title: "Pause collection", action: #selector(toggleCollection), keyEquivalent: "")
            pause.target = self; menu.addItem(pause); pauseItem = pause
        }
        add(menu, "内部截图历史…", #selector(showHistory))
        add(menu, "清空可见队列（保留文件）", #selector(clearVisible))
        let archive = NSMenuItem(title: "Idle archive…", action: #selector(configureArchive), keyEquivalent: "")
        archive.target = self; menu.addItem(archive); archiveItem = archive
        menu.addItem(.separator())
        add(menu, "显示最新截图", #selector(showLatest))
        add(menu, "显示最早截图", #selector(showOldest))
        add(menu, "重新检查截图来源与权限", #selector(recheckSetup))
        add(menu, "检查本机存储用量", #selector(checkStorage))
        let storage = NSMenuItem(title: "私有存储：尚未检查", action: nil, keyEquivalent: "")
        menu.addItem(storage); storageLine = storage
        if mode.collectsSystemScreenshots { add(menu, "打开离线合成演示…", #selector(launchSimulation)) }
        if mode == .capture { add(menu, "打开真实截图内部候选…", #selector(launchSystemScreenshotCandidate)) }
        let advanced = NSMenu()
        add(advanced, "重新载入几何参数", #selector(reload))
        add(advanced, "打开工程几何参数文件", #selector(openGeometry))
        let advancedItem = NSMenuItem(title: "工程调校", action: nil, keyEquivalent: "")
        advancedItem.submenu = advanced; menu.addItem(advancedItem)
        menu.addItem(.separator())
        add(menu, "退出 Riftlet", #selector(quit), key: "q")
        item.menu = menu; statusItem = item
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(beginScreenshot) { return screenshotEntry != nil && !userHidden }
        if item.action == #selector(toggleCollection) { return mode.collectsSystemScreenshots && initialized && !captureControl.isBusy }
        if item.action == #selector(recheckSetup) || item.action == #selector(reload) {
            return initialized && !captureControl.isBusy && !requestingPermission
        }
        if item.action == #selector(toggleHidden) { return store != nil && !changingHidden }
        return true
    }
    private func showIssue(_ message: String) { statusLine?.title = message; statusItem?.button?.toolTip = message }
    @objc private func beginScreenshot() { screenshotEntry?.beginFromMenu() }
    @objc private func showLatest() { rift?.showLatest() }
    @objc private func showOldest() { rift?.showOldest() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
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
