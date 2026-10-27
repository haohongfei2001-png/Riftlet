import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin
import RiftletCore
import RiftletCapture
import RiftletUI
import RiftletAdapters

private enum ApplicationMode: Equatable {
    case capture, simulation, webAcceptance

    static func resolve(_ arguments: [String]) throws -> ApplicationMode {
        guard !(arguments.contains("--simulate") && arguments.contains("--web-acceptance")) else {
            throw RiftletError.modeMismatch
        }
        if arguments.contains("--web-acceptance") { return .webAcceptance }
        return arguments.contains("--simulate") ? .simulation : .capture
    }

    var directoryName: String {
        switch self {
        case .capture: return "Riftlet"
        case .simulation: return "Riftlet-Simulation"
        case .webAcceptance: return "Riftlet-Web-Acceptance"
        }
    }
}

@main
enum RiftletMain {
    @MainActor static func main() {
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
                    print("RIFTLET_WEB_ACCEPTANCE_SELF_CHECK_PASS: bundled page source, synthetic-only policy, isolated modes; CHROME_NOT_RUN; GUI_NOT_RUN")
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
private final class ApplicationController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var storageLine: NSMenuItem?
    private var storageMeasurement: Task<Void, Never>?
    private var hideItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var archiveItem: NSMenuItem?
    private var store: QueueStore?
    private var capture: CaptureService?
    private var sourceBinding: CaptureSourceBinding?
    private var transfer: TransferCoordinator?
    private var rift: RiftPanelController?
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
    private var changingCapture = false
    private var changingHidden = false
    private var lifecycleSettings = LifecycleSettings()
    private let interactionFence = QueueInteractionFence()
    private var archiveTask: Task<Void, Never>?
    private var archiveWakeObserver: NSObjectProtocol?
    private var archiveNotBefore: TimeInterval = 0
    private var archiveClock: (wall: Date, uptime: TimeInterval)?
    private var completionWatch: Task<Void, Never>?
    private var targetArmer: Task<Void, Never>?
    private var armScheduler = TargetArmScheduler()
    private var armingAdapter: (any AttachmentAdapter)?
    private var activationObserver: NSObjectProtocol?
    private var lastForegroundSession: String?
    private var diagnosticEvents = 0
    private var pendingArmReason = "startup"
    private var chromeActivity: ChromeActivityObserver?
    private var armedTarget: ArmedTarget?
    private var armedCaptureDiagnostics: CapturedTargetDiagnostics?
    private var activeCaptureInvocation: CaptureInvocationContext?
    private var frozenPress: (id: UUID, target: TargetLease?, refusalReason: String)?
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
        Task { do { try await start() } catch { showIssue("Initialization failed; data preserved. \(error)") } }
    }

    func applicationWillTerminate(_ notification: Notification) {
        completionWatch?.cancel()
        archiveTask?.cancel()
        targetArmer?.cancel()
        armScheduler.stop(); armedTarget = nil; frozenPress = nil
        armedCaptureDiagnostics = nil
        chromeActivity?.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let archiveWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(archiveWakeObserver) }
        rift?.close()
        history?.close()
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
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"), mode: simulation ? .simulation : .production)
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
        if mode != .capture { try await seedSyntheticImages(store: store) }
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
            holdsSelectionUntilFinished: true, interactionFence: interactionFence,
            onRemove: { [weak self] id in self?.removeVisible(id) }) { [weak self] id in
            guard let self else { return }
            let frozen = self.frozenPress?.id == id ? self.frozenPress?.target : nil
            let revision = self.rift?.selectionRevision(for: id)
            self.frozenPress = nil
            Task {
                guard self.mode != .webAcceptance || self.watchedCompletions.count < 64 else {
                    self.showIssue("Acceptance observation limit reached; images retained.")
                    self.rift?.finishSelection(id)
                    return
                }
                do {
                    if self.mode == .webAcceptance { try await self.transfer?.select(id, frozenTarget: frozen, visibilityRevision: revision) }
                    else { try await self.transfer?.select(id, visibilityRevision: revision) }
                    if let record = try await self.store?.asset(id: id), record.visibility == .visible,
                       let operationID = record.activeOperationID, record.status == .failed {
                        let reason = try await self.store?.operationReason(for: operationID)
                        self.rift?.setFeedback(reason, for: id)
                    }
                }
                catch {
                    let diagnostic = (error as? WebAdapterError).map { String(describing: $0) } ?? "targetUnavailable"
                    self.showIssue(self.mode == .webAcceptance
                        ? "Test image retained. Chrome diagnostic: \(diagnostic)."
                        : "Screenshot retained. ChatGPT attachment adapter is not enabled in this build.")
                    self.rift?.setFeedback(self.mode == .capture ? "Attachment support is not enabled; image kept."
                        : "Current draft could not be verified; image kept.", for: id)
                }
                await self.refresh()
            }
        }
        rift?.setUserHidden(userHidden)
        history = RiftHistoryController(mediaDirectory: root.appendingPathComponent("media"),
            onRestore: { [weak self] id in self?.restoreHistory(id) },
            onRemove: { [weak self] id in self?.removeVisible(id) },
            onReveal: { [weak self] id in self?.revealHistory(id) },
            onNextPage: { [weak self] in self?.changeHistoryPage(1) },
            onPreviousPage: { [weak self] in self?.changeHistoryPage(-1) })
        let adapter: any AttachmentAdapter
        let policy: ReceiptPolicy
        switch mode {
        case .capture:
            adapter = UnavailableAdapter(); policy = .init()
        case .simulation:
            adapter = SimulationAdapter(); policy = .init()
        case .webAcceptance:
            adapter = WebAttachmentAdapter(mediaDirectory: root.appendingPathComponent("media"),
                executor: ChromeAppleEventsExecutor(traceEnabled: CommandLine.arguments.contains("--acceptance-trace")), program: try ChatGPTWebPageProgram.load(),
                mode: .syntheticDevelopment, profile: ChatGPTWebPageProgram.acceptanceProfile)
            policy = ReceiptPolicy(syntheticAcceptanceProfiles: [ChatGPTWebPageProgram.acceptanceProfile.profileID: .webChat])
        }
        let transfer = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root.appendingPathComponent("media"),
            policy: policy, onChange: { [weak self] in await self?.refresh() },
            onSelectionSettled: { [weak self] id in await self?.finishPreparedSelection(id) })
        self.transfer = transfer
        if mode == .webAcceptance { startArming(adapter: adapter) }
        // Recovery only observes original unresolved operations. In Web acceptance
        // this may contact Chrome after restart; it never dispatches a new input.
        try await transfer.recover()
        if mode != .capture {
            watchedCompletions = Set(try await store.successfulOperations().map(\.id))
            completionWatch = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: self?.simulation == true ? 400_000_000 : 5_000_000_000) } catch { return }
                    guard let self else { return }
                    do { try await transfer.observePending(limit: self.simulation ? 8 : 4) }
                    catch { self.showIssue("Pending attachment observation unavailable; local records kept.") }
                    for id in self.watchedCompletions {
                        if Task.isCancelled { return }
                        if let backoff = self.observationBackoff[id], backoff.next > Date() { continue }
                        do {
                            if try await !transfer.observeCompleted(operationID: id) {
                                self.watchedCompletions.remove(id)
                            }
                            self.observationBackoff.removeValue(forKey: id)
                        } catch WebAdapterError.invalidTarget {
                            // The original process/session no longer exists.
                            self.watchedCompletions.remove(id)
                            self.observationBackoff.removeValue(forKey: id)
                        } catch {
                            // Loss of transport is not proof of a late failure.
                            // Preserve success; back off observation without input.
                            let failures = min(6, (self.observationBackoff[id]?.failures ?? 0) + 1)
                            self.observationBackoff[id] = (failures, Date().addingTimeInterval(min(300, pow(2, Double(failures)) * 5)))
                        }
                    }
                }
            }
        }
        if mode != .capture {
            statusLine?.title = simulation ? "SIMULATION · synthetic images only · no ChatGPT input"
                : "WEB ACCEPTANCE · generated images · real Chrome input"
        } else {
            let service = CaptureService(store: store, privateRoot: root, sourceDirectory: CaptureSource.defaultDirectory(),
                                         onChange: { [weak self] in await self?.refresh() },
                                         onIssue: { [weak self] message in await self?.showIssue(message) })
            capture = service
            let binding = CaptureSourceBinding(service: service,
                onIssue: { [weak self] message in await self?.showIssue(message) })
            sourceBinding = binding
            if !captureIsPaused { try await binding.start() }
            statusLine?.title = captureIsPaused ? "Capture paused · stored screenshots kept"
                : "Capture active · ChatGPT adapter pending validation"
        }
        updateControlTitles()
        startArchiveScheduler()
        await refresh()
    }

    private func finishPreparedSelection(_ id: UUID) {
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
        frozenPress = (id, target, refusal)
    }

    private func startArming(adapter: any AttachmentAdapter) {
        armingAdapter = adapter
        armScheduler.start(); armSession = armScheduler.epoch
        lastForegroundSession = foregroundChromeSession
        chromeActivity = ChromeActivityObserver { [weak self] reason in self?.requestArm(reason: reason) }
        let activityAvailable = chromeActivity?.bind(to: NSWorkspace.shared.frontmostApplication) ?? false
        recordAcceptance(["event": "chrome_activity_binding", "available": activityAvailable])
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
                    let available = self.chromeActivity?.bind(to: NSWorkspace.shared.frontmostApplication) ?? false
                    self.recordAcceptance(["event": "chrome_activity_binding", "available": available])
                    self.requestArm(reason: "activation", invalidate: true)
                }
            }
        performPendingArm()
    }

    private func requestArm(reason: String = "fallback", invalidate: Bool = false) {
        pendingArmReason = reason
        if invalidate { armedTarget = nil; armedCaptureDiagnostics = nil; frozenPress = nil }
        let wake = armScheduler.request(invalidateEpoch: invalidate)
        armSession = armScheduler.epoch
        if wake { performPendingArm() }
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
            var result: TargetLease?
            var diagnostics: CapturedTargetDiagnostics?
            var errorCode = "browserNotFrontmost"
            if self.foregroundChromeSession != nil {
                do {
                    if let web = adapter as? WebAttachmentAdapter {
                        diagnostics = try await web.captureTargetWithDiagnostics(context: invocation)
                        result = diagnostics?.target
                    } else { result = try await adapter.captureTarget() }
                    errorCode = "none"
                }
                catch { errorCode = (error as? WebAdapterError).map { String(describing: $0) } ?? "unclassified" }
            }
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
                "endedUptime": ProcessInfo.processInfo.systemUptime, "error": errorCode,
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
        fields["foregroundSessionMatches"] = armedTarget?.target.sessionID == foregroundChromeSession
        if let ack = armedTarget?.acknowledgedUptime { fields["ackUptime"] = ack }
        if let number = boundary.eventNumber { fields["eventNumber"] = number }
        recordAcceptance(fields)
    }

    private func recordAcceptance(_ fields: [String: Any]) {
        guard mode == .webAcceptance, CommandLine.arguments.contains("--acceptance-trace"), diagnosticEvents < 2048 else { return }
        diagnosticEvents += 1
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
            try? FileHandle.standardError.write(contentsOf: data + Data([10]))
        }
    }

    private func seedSyntheticImages(store: QueueStore, addNewBatch: Bool = false) async throws {
        guard mode != .capture else { throw RiftletError.modeMismatch }
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
                let successful = mode == .webAcceptance ? try await store.successfulOperations() : []
                if refreshRequested { continue }
                let hasNewImages = !activeIDs.subtracting(visibleIDs).isEmpty
                visibleIDs = activeIDs
                watchedCompletions.formUnion(successful.map(\.id))
                if hasNewImages && mode == .webAcceptance { requestArm(reason: "newImages") }
                rift?.render(snapshot)
                switch mode {
                case .capture:
                    statusItem?.button?.toolTip = "Riftlet · \(active.count) visible screenshots\(userHidden ? " · hidden" : "")"
                case .simulation: statusItem?.button?.toolTip = "Riftlet SIMULATION — synthetic only; start then delayed result"
                case .webAcceptance: statusItem?.button?.toolTip = "Riftlet WEB ACCEPTANCE · \(active.count) visible test images · unresolved records stay in local history"
                }
                if history?.isVisible == true { await refreshHistory() }
            } catch { showIssue("Queue read failed; durable data is preserved.") }
        } while refreshRequested
        refreshRunning = false
        let waiters = refreshWaiters; refreshWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
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
        Task {
            do { try await store.removeFromQueue(id); await refresh() }
            catch { showIssue("Could not remove this image from the rift; files are preserved.") }
        }
    }

    @objc private func clearVisible() {
        guard let store else { return }
        Task {
            do { _ = try await store.clearVisibleQueue(); await refresh() }
            catch { showIssue("Could not clear the visible queue; files and attachments are preserved.") }
        }
    }

    private func updateControlTitles() {
        hideItem?.title = userHidden ? "Show rift" : "Hide rift"
        pauseItem?.title = captureIsPaused ? "Resume collection" : "Pause collection"
        pauseItem?.isEnabled = mode == .capture && !changingCapture
        if let interval = lifecycleSettings.archiveAfterSeconds {
            archiveItem?.title = String(format: "Idle archive: %.2g hours…", interval / 3600)
        } else { archiveItem?.title = "Idle archive: off…" }
    }

    @objc private func toggleHidden() {
        guard let store, !changingHidden else { return }
        changingHidden = true
        let requested = !userHidden
        // Hide immediately; showing requires the persistent change to succeed.
        if requested { userHidden = true; rift?.setUserHidden(true); updateControlTitles() }
        Task {
            defer { changingHidden = false; updateControlTitles() }
            do {
                try await store.setUserHidden(requested)
                userHidden = requested; rift?.setUserHidden(requested)
                await refresh()
            } catch { showIssue("The visibility preference could not be saved; the rift stays hidden.") }
        }
    }

    @objc private func toggleCollection() {
        guard mode == .capture, let store, let binding = sourceBinding, !changingCapture else { return }
        changingCapture = true; updateControlTitles()
        let requested = !captureIsPaused
        Task {
            defer { changingCapture = false; updateControlTitles() }
            do {
                if requested { await binding.stop(); captureIsPaused = true }
                try await store.setCapturePaused(requested)
                if !requested { try await binding.start(); captureIsPaused = false }
                statusLine?.title = captureIsPaused ? "Capture paused · stored screenshots kept"
                    : "Capture active · ChatGPT adapter pending validation"
            } catch { showIssue("Collection preference could not be applied; existing screenshots are preserved.") }
        }
    }

    @objc private func configureArchive() {
        guard let root else { return }
        let alert = NSAlert()
        alert.messageText = "Archive idle screenshots"
        alert.informativeText = "Hours since last use. Enter 0 to turn off. Archiving keeps the files in local history."
        let field = NSTextField(string: lifecycleSettings.archiveAfterSeconds.map { String($0 / 3600) } ?? "0")
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
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
        item.button?.title = simulation ? "Riftlet SIM" : (mode == .webAcceptance ? "Riftlet WEB TEST" : "Riftlet")
        let menu = NSMenu()
        let heading = NSMenuItem(title: simulation ? "SIMULATION — no real uploads"
            : (mode == .webAcceptance ? "WEB ACCEPTANCE — generated images, real uploads" : "Engineering foundation — capture only"), action: nil, keyEquivalent: "")
        menu.addItem(heading); statusLine = heading
        if mode == .webAcceptance {
            menu.addItem(NSMenuItem(title: "Chrome · ChatGPT Chat · Chinese UI · PNG test images", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "No message sending · UNKNOWN never retransmits", action: nil, keyEquivalent: ""))
            add(menu, "Add 3 generated test images", #selector(addWebTestImages))
        }
        if simulation { add(menu, "Add 3 synthetic demo images", #selector(addWebTestImages)) }
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide rift", action: #selector(toggleHidden), keyEquivalent: "")
        hide.target = self; menu.addItem(hide); hideItem = hide
        if mode == .capture {
            let pause = NSMenuItem(title: "Pause collection", action: #selector(toggleCollection), keyEquivalent: "")
            pause.target = self; menu.addItem(pause); pauseItem = pause
        }
        add(menu, "Local screenshot history…", #selector(showHistory))
        add(menu, "Clear visible queue", #selector(clearVisible))
        let archive = NSMenuItem(title: "Idle archive…", action: #selector(configureArchive), keyEquivalent: "")
        archive.target = self; menu.addItem(archive); archiveItem = archive
        menu.addItem(.separator())
        add(menu, "Show latest screenshot", #selector(showLatest))
        add(menu, "Show oldest screenshot", #selector(showOldest))
        add(menu, "Reload source and geometry", #selector(reload))
        add(menu, "Open adjustable geometry file", #selector(openGeometry))
        add(menu, "Check local storage", #selector(checkStorage))
        let storage = NSMenuItem(title: "Retained files: not measured", action: nil, keyEquivalent: "")
        menu.addItem(storage); storageLine = storage
        menu.addItem(.separator())
        add(menu, "Quit Riftlet", #selector(quit), key: "q")
        item.menu = menu; statusItem = item
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    private func showIssue(_ message: String) { statusLine?.title = message; statusItem?.button?.toolTip = message }
    @objc private func showLatest() { rift?.showLatest() }
    @objc private func showOldest() { rift?.showOldest() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func addWebTestImages() {
        guard mode != .capture, let store else { return }
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
        storageLine?.title = "Measuring retained files…"
        // Metadata work stays off MainActor and runs only after this explicit menu action.
        storageMeasurement = Task { [weak self] in
            defer { self?.storageMeasurement = nil }
            do {
                let usage = try await Task.detached(priority: .utility) {
                    try PrivateStorageUsage.measure(privateRoot: root)
                }.value
                let size: String
                if let bytes = usage.logicalBytes, bytes <= UInt64(Int64.max) {
                    size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                } else { size = "size unavailable" }
                let scope = usage.isComplete ? "" : " · partial count"
                self?.storageLine?.title = "Retained files: \(size) · \(usage.regularFileCount) files\(scope)"
                self?.storageLine?.toolTip = "Logical size includes used images, import journals and the database; files are preserved."
            } catch {
                self?.storageLine?.title = "Storage unavailable; files preserved"
            }
        }
    }
    @objc private func reload() {
        Task {
            await reloadSource()
            guard let root else { return }
            do {
                let config = try JSONDecoder().decode(RiftConfiguration.self, from: Data(contentsOf: root.appendingPathComponent("rift-configuration.json")))
                try rift?.updateConfiguration(config)
            } catch { showIssue("Geometry file is invalid; previous geometry retained.") }
        }
    }
    private func reloadSource() async {
        guard mode == .capture, !captureIsPaused, let capture, let sourceBinding else { return }
        do {
            await sourceBinding.refresh()
            try await capture.rescan()
        } catch { showIssue("Screenshot folder needs access; existing copies retained.") }
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
        let policy = ReceiptPolicy(syntheticAcceptanceProfiles: [profile.profileID: .webChat])
        guard policy.admittedProfiles.isEmpty, policy.retrySafeProfiles.isEmpty,
              ReceiptPolicy().syntheticAcceptanceProfiles.isEmpty else { throw RiftletError.invalidTransition }
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
            guard policy.allowsConsumption(receipt: receipt, asset: image, mode: .production) == (origin == .synthetic),
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
