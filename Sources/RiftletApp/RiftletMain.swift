import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin
import RiftletCore
import RiftletCapture
import RiftletUI

@main
enum RiftletMain {
    static func main() async {
        if CommandLine.arguments.contains("--self-check") {
            do { try await SelfCheck.run(); print("RIFTLET_SELF_CHECK_PASS: private import, durable queue, synthetic receipt, restart") }
            catch { fputs("RIFTLET_SELF_CHECK_FAIL: \(error)\n", stderr); exit(1) }
            return
        }
        await MainActor.run { runApplication() }
    }

    @MainActor private static func runApplication() {
        let application = NSApplication.shared
        let delegate = ApplicationController()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class ApplicationController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var store: QueueStore?
    private var capture: CaptureService?
    private var transfer: TransferCoordinator?
    private var rift: RiftPanelController?
    private var root: URL!
    private var source: URL?
    private var visibleIDs = Set<UUID>()
    private var instanceDescriptor: Int32 = -1
    private var wakeObserver: NSObjectProtocol?
    private let simulation = CommandLine.arguments.contains("--simulate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        Task { do { try await start() } catch { showIssue("Initialization failed; data preserved. \(error)") } }
    }

    func applicationWillTerminate(_ notification: Notification) {
        rift?.close()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if instanceDescriptor >= 0 { flock(instanceDescriptor, LOCK_UN); Darwin.close(instanceDescriptor) }
    }

    private func start() async throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = base.appendingPathComponent(simulation ? "Riftlet-Simulation" : "Riftlet", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        instanceDescriptor = Darwin.open(root.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard instanceDescriptor >= 0, flock(instanceDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw RiftletError.database("This data directory already has a running Riftlet instance")
        }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"), mode: simulation ? .simulation : .production)
        self.store = store
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
                do { try await self.transfer?.select(id) }
                catch { self.showIssue("Screenshot retained. ChatGPT attachment adapter is not enabled in this build.") }
                await self.refresh()
            }
        }
        let adapter: any AttachmentAdapter = simulation ? SimulationAdapter() : UnavailableAdapter()
        let transfer = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root.appendingPathComponent("media"),
                                           onChange: { [weak self] in await self?.refresh() })
        self.transfer = transfer
        try await transfer.recover()
        if simulation {
            try await seedSimulation(store: store)
            statusLine?.title = "SIMULATION · synthetic images only · no ChatGPT input"
        } else {
            source = CaptureSource.defaultDirectory()
            let service = CaptureService(store: store, privateRoot: root, sourceDirectory: source!,
                                         onChange: { [weak self] in await self?.refresh() },
                                         onIssue: { [weak self] message in await self?.showIssue(message) })
            capture = service
            try await service.start()
            statusLine?.title = "Capture active · ChatGPT adapter pending validation"
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                object: nil, queue: .main) { [weak self] _ in
                    guard let controller = self else { return }
                    Task { @MainActor in await controller.reloadSource() }
                }
        }
        await refresh()
    }

    private func seedSimulation(store: QueueStore) async throws {
        let importer = PrivateAssetImporter(privateRoot: root, store: store)
        _ = try await importer.recover()
        guard try await store.assets(includeUsed: true).isEmpty else { return }
        let input = root.appendingPathComponent("synthetic-input", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for index in 0..<3 {
            let file = input.appendingPathComponent("demo-\(index).png")
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
                if let consumed = try await store.asset(id: id), consumed.status == .used { snapshot.append(consumed) }
            }
            visibleIDs = activeIDs
            rift?.render(snapshot)
            statusItem?.button?.toolTip = simulation ? "Riftlet SIMULATION — synthetic only" : "Riftlet · \(active.count) retained screenshots"
        } catch { showIssue("Queue read failed; durable data is preserved.") }
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = simulation ? "Riftlet SIM" : "Riftlet"
        let menu = NSMenu()
        let heading = NSMenuItem(title: simulation ? "SIMULATION — no real uploads" : "Engineering foundation — capture only", action: nil, keyEquivalent: "")
        menu.addItem(heading); statusLine = heading
        menu.addItem(.separator())
        add(menu, "Show latest screenshot", #selector(showLatest))
        add(menu, "Show oldest screenshot", #selector(showOldest))
        add(menu, "Reload source and geometry", #selector(reload))
        add(menu, "Open adjustable geometry file", #selector(openGeometry))
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
    @objc private func openGeometry() {
        guard let root else { return }; NSWorkspace.shared.open(root.appendingPathComponent("rift-configuration.json"))
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
        guard !simulation, let capture else { return }
        do {
            let next = CaptureSource.defaultDirectory()
            if next != source { try await capture.setSourceDirectory(next); source = next }
            else { try await capture.rescan() }
        } catch { showIssue("Screenshot folder needs access; existing copies retained.") }
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
    }
}
