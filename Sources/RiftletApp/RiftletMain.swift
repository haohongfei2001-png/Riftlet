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
                do { try await SelfCheck.run(); print("RIFTLET_SELF_CHECK_PASS: private import, durable queue, synthetic receipt, restart"); exit(0) }
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
    private var store: QueueStore?
    private var capture: CaptureService?
    private var sourceBinding: CaptureSourceBinding?
    private var transfer: TransferCoordinator?
    private var rift: RiftPanelController?
    private var root: URL!
    private var visibleIDs = Set<UUID>()
    private var completionWatch: Task<Void, Never>?
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
        rift?.close()
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
        rift = RiftPanelController(mediaDirectory: root.appendingPathComponent("media"), configuration: configuration) { [weak self] id in
            guard let self else { return }
            Task {
                guard self.mode != .webAcceptance || self.watchedCompletions.count < 64 else {
                    self.showIssue("Acceptance observation limit reached; images retained.")
                    return
                }
                do { try await self.transfer?.select(id) }
                catch {
                    let diagnostic = (error as? WebAdapterError).map { String(describing: $0) } ?? "targetUnavailable"
                    self.showIssue(self.mode == .webAcceptance
                        ? "Test image retained. Chrome diagnostic: \(diagnostic)."
                        : "Screenshot retained. ChatGPT attachment adapter is not enabled in this build.")
                }
                await self.refresh()
            }
        }
        let adapter: any AttachmentAdapter
        let policy: ReceiptPolicy
        switch mode {
        case .capture:
            adapter = UnavailableAdapter(); policy = .init()
        case .simulation:
            adapter = SimulationAdapter(); policy = .init()
        case .webAcceptance:
            adapter = WebAttachmentAdapter(mediaDirectory: root.appendingPathComponent("media"),
                executor: ChromeAppleEventsExecutor(), program: try ChatGPTWebPageProgram.load(),
                mode: .syntheticDevelopment, profile: ChatGPTWebPageProgram.acceptanceProfile)
            policy = ReceiptPolicy(syntheticAcceptanceProfiles: [ChatGPTWebPageProgram.acceptanceProfile.profileID: .webChat])
        }
        let transfer = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root.appendingPathComponent("media"),
                                           policy: policy, onChange: { [weak self] in await self?.refresh() })
        self.transfer = transfer
        // Recovery only observes original unresolved operations. In Web acceptance
        // this may contact Chrome after restart; it never dispatches a new input.
        try await transfer.recover()
        if mode == .webAcceptance {
            watchedCompletions = Set(try await store.successfulOperations().map(\.id))
            completionWatch = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                    guard let self else { return }
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
            try await binding.start()
            statusLine?.title = "Capture active · ChatGPT adapter pending validation"
        }
        await refresh()
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
        guard let store else { return }
        do {
            let active = try await store.assets()
            var snapshot = active
            let activeIDs = Set(active.map(\.id))
            // Include only newly consumed rows, rather than loading a growing used-image history.
            for id in visibleIDs.subtracting(activeIDs) {
                if let consumed = try await store.asset(id: id), consumed.status == .used {
                    snapshot.append(consumed)
                    if mode == .webAcceptance, let operationID = consumed.activeOperationID {
                        watchedCompletions.insert(operationID)
                    }
                }
            }
            visibleIDs = activeIDs
            rift?.render(snapshot)
            switch mode {
            case .capture: statusItem?.button?.toolTip = "Riftlet · \(active.count) retained screenshots"
            case .simulation: statusItem?.button?.toolTip = "Riftlet SIMULATION — synthetic only"
            case .webAcceptance:
                let unknownCount = active.filter { $0.status == .unknown }.count
                statusItem?.button?.toolTip = "Riftlet WEB ACCEPTANCE · \(active.count) retained test images · \(unknownCount) UNKNOWN; click UNKNOWN only observes its original operation"
            }
        } catch { showIssue("Queue read failed; durable data is preserved.") }
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = simulation ? "Riftlet SIM" : (mode == .webAcceptance ? "Riftlet WEB TEST" : "Riftlet")
        let menu = NSMenu()
        let heading = NSMenuItem(title: simulation ? "SIMULATION — no real uploads"
            : (mode == .webAcceptance ? "WEB ACCEPTANCE — generated images, real uploads" : "Engineering foundation — capture only"), action: nil, keyEquivalent: "")
        menu.addItem(heading); statusLine = heading
        if mode == .webAcceptance {
            menu.addItem(NSMenuItem(title: "Chrome · ChatGPT home · Chinese UI · PNG test images", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "No message sending · UNKNOWN never retransmits", action: nil, keyEquivalent: ""))
            add(menu, "Add 3 generated test images", #selector(addWebTestImages))
        }
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
        guard mode == .webAcceptance, let store else { return }
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
        guard mode == .capture, let capture, let sourceBinding else { return }
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
        let coordinator = TransferCoordinator(store: store, adapter: SimulationAdapter(), mediaDirectory: privateRoot.appendingPathComponent("media"))
        try await coordinator.select(record.id)
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
