import Foundation
import AppKit
import CryptoKit
import RiftletCore

private struct SourceCheckpoint: Codable {
    let version: Int
    let baselineSourceKeys: Set<String>
}

private struct Observation {
    var signature: FileSignature
    let firstSeenAt: Date
    var stableSince: Date
}

/// Directory events request reconciliation; they are not one-event/one-image assertions.
/// There is no idle polling. A burst may schedule up to five bounded retries for late
/// metadata / partial writes, and wake or an explicit rescan can retry later.
public actor CaptureService {
    private let store: QueueStore
    public let importer: PrivateAssetImporter
    private var sourceDirectory: URL
    private let onChange: @Sendable () async -> Void
    private let onIssue: @Sendable (String) async -> Void
    private var watcher: FolderWatcher?
    private var parentWatcher: FolderWatcher?
    private var wakeObserver: NSObjectProtocol?
    private var retryTask: Task<Void, Never>?
    private var running = false
    private var initializing = false
    private var generation = UUID()
    private var scanning = false
    private var dirty = false
    private var retryIndex = 0
    private var observations: [String: Observation] = [:]
    private var baseline: Set<String>?
    private var installationStart = Date()
    private var reportedIssues = Set<String>()
    private let retryDelays: [UInt64] = [150_000_000, 350_000_000, 800_000_000, 2_000_000_000, 5_000_000_000]

    public init(store: QueueStore, privateRoot: URL, sourceDirectory: URL,
                onChange: @escaping @Sendable () async -> Void = {},
                onIssue: @escaping @Sendable (String) async -> Void = { _ in }) {
        self.store = store
        importer = PrivateAssetImporter(privateRoot: privateRoot, store: store)
        self.sourceDirectory = sourceDirectory.standardizedFileURL
        self.onChange = onChange; self.onIssue = onIssue
    }

    public func start() async throws {
        guard !running else { return }
        guard await store.mode == .production else { throw RiftletError.modeMismatch }
        running = true
        initializing = true
        installationStart = Date()
        generation = UUID()
        do {
            // Acknowledged watch first: later scan and import awaits cannot open an event gap.
            try await attachWatcher()
            let report = try await importer.recover()
            if !report.missing.isEmpty { await reportIssue("Some private copies are missing; their queue records are preserved.") }
            if !report.invalid.isEmpty { await reportIssue("Some import journals need recovery; valid captures remain available.") }
            if let data = try await store.checkpoint(for: checkpointKey) {
                let checkpoint = try JSONDecoder().decode(SourceCheckpoint.self, from: data)
                guard checkpoint.version == 1 else { throw CaptureError.invalidManifest }
                baseline = checkpoint.baselineSourceKeys
            }
            let token = generation
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
                    guard let service = self else { return }
                    Task(priority: .utility) { await service.wake(generation: token) }
                }
            initializing = false
            try await rescan()
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        running = false
        initializing = false
        generation = UUID()
        watcher?.cancel(); watcher = nil
        parentWatcher?.cancel(); parentWatcher = nil
        retryTask?.cancel(); retryTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// Call on an explicitly selected source change, never by silently granting new access.
    public func setSourceDirectory(_ directory: URL) async throws {
        stop()
        sourceDirectory = directory.standardizedFileURL
        baseline = nil; observations.removeAll(); retryIndex = 0; reportedIssues.removeAll()
        try await start()
    }

    public func rescan() async throws {
        guard running else { return }
        dirty = true
        guard !initializing else { return }
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        var passes = 0
        repeat {
            dirty = false
            try await scanOnce()
            passes += 1
        } while dirty && running && passes < 2
        if dirty { scheduleRetry() }
    }

    private var checkpointKey: String {
        let digest = SHA256.hash(data: Data(sourceDirectory.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return "capture-source-v1:" + digest
    }

    private func scanOnce() async throws {
        let token = generation
        let urls = try FileManager.default.contentsOfDirectory(at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var candidates: [(URL, FileSignature)] = []
        for url in urls {
            // The encoding is validated from bytes later. This only bounds metadata work.
            guard ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(url.pathExtension.lowercased()) else { continue }
            do {
                let signature = try FileSignature.read(at: url)
                candidates.append((url, signature))
            } catch CaptureError.notRegularFile { continue }
            catch { continue } // transient rename/unreadable candidates never become known/consumed
        }
        candidates.sort {
            if $0.1.createdAt != $1.1.createdAt { return $0.1.createdAt < $1.1.createdAt }
            return $0.1.sourceKey < $1.1.sourceKey
        }
        if baseline == nil {
            // First installation excludes existing history. A screenshot actually created
            // after watch startup is still new even if it arrives during the initial scan.
            let initial = Set(candidates.filter { $0.1.createdAt < installationStart }.map { $0.1.sourceKey })
            let checkpoint = SourceCheckpoint(version: 1, baselineSourceKeys: initial)
            try await store.saveCheckpoint(try JSONEncoder().encode(checkpoint), for: checkpointKey)
            guard generation == token else { return }
            baseline = initial
        }
        let now = Date()
        var needsRetry = false
        var imported = false
        var importedCount = 0
        let currentKeys = Set(candidates.map { $0.1.sourceKey })
        observations = observations.filter { currentKeys.contains($0.key) }
        for (url, signature) in candidates {
            guard running, generation == token else { return }
            guard baseline?.contains(signature.sourceKey) != true else { continue }
            if try await store.containsSource(key: signature.sourceKey) { observations.removeValue(forKey: signature.sourceKey); continue }
            // Bound expensive copies, not failed/non-screenshot candidates. Otherwise 128
            // ordinary images could permanently starve a later genuine screenshot.
            if importedCount >= 128 { needsRetry = true; break }
            if let previous = observations[signature.sourceKey] {
                if previous.signature != signature {
                    observations[signature.sourceKey] = Observation(signature: signature,
                        firstSeenAt: previous.firstSeenAt, stableSince: now)
                    needsRetry = true; continue
                }
                if now.timeIntervalSince(previous.stableSince) < 0.12 { needsRetry = true; continue }
            } else {
                observations[signature.sourceKey] = Observation(signature: signature, firstSeenAt: now, stableSince: now)
                needsRetry = true; continue
            }
            do {
                _ = try await importer.importStableFile(at: url, signature: signature,
                    firstSeenAt: observations[signature.sourceKey]?.firstSeenAt ?? now)
                observations.removeValue(forKey: signature.sourceKey)
                imported = true
                importedCount += 1
            } catch CaptureError.notScreenshot {
                // Present false metadata is not collected and does not keep a timer alive.
            } catch CaptureError.metadataPending { needsRetry = true }
              catch CaptureError.unstableFile { needsRetry = true }
              catch CaptureError.incompleteImage { needsRetry = true }
              catch CaptureError.importInProgress { needsRetry = true }
              catch CaptureError.unsupportedImage { await reportIssue("A screenshot encoding is not supported; the source remains untouched.") }
              catch CaptureError.imageTooLarge { await reportIssue("A screenshot exceeds the local decode limit; the source remains untouched.") }
              catch {
                needsRetry = true
                await reportIssue("A screenshot could not be stored. Check source access and available disk space; the original is preserved.")
            }
        }
        if imported { await onChange() }
        if needsRetry { scheduleRetry() }
    }

    private func attachWatcher() async throws {
        let token = generation
        let next = FolderWatcher(url: sourceDirectory,
            onDirty: { [weak self] in
                guard let service = self else { return }
                Task(priority: .utility) { await service.event(generation: token, lost: false) }
            },
            onLost: { [weak self] in
                guard let service = self else { return }
                Task(priority: .utility) { await service.event(generation: token, lost: true) }
            })
        try await next.start()
        watcher?.cancel(); watcher = next
        parentWatcher?.cancel(); parentWatcher = nil
    }

    private func event(generation token: UUID, lost: Bool) async {
        guard running, token == generation else { return }
        retryIndex = 0
        reportedIssues.removeAll()
        if lost {
            watcher?.cancel(); watcher = nil
            await reportIssue("The screenshot folder became unavailable. Captured private copies remain available.")
            let parent = FolderWatcher(url: sourceDirectory.deletingLastPathComponent(),
                onDirty: { [weak self] in
                    guard let service = self else { return }
                    Task(priority: .utility) { await service.wake(generation: token) }
                },
                onLost: { [weak self] in
                    guard let service = self else { return }
                    Task(priority: .utility) { await service.reportIssue("The screenshot folder needs access again.") }
                })
            do { try await parent.start(); parentWatcher = parent }
            catch { await reportIssue("The screenshot folder needs access again.") }
            return
        }
        do { try await rescan() }
        catch { await reportIssue("The screenshot directory could not be scanned; existing captures are preserved.") }
    }

    private func wake(generation token: UUID) async {
        guard running, generation == token else { return }
        retryIndex = 0
        do {
            // Reopen on wake, including when a prior directory descriptor became stale.
            try await attachWatcher()
            try await rescan()
        } catch { await reportIssue("The screenshot folder is not currently accessible; retry after restoring access.") }
    }

    private func scheduleRetry() {
        guard running, retryTask == nil, retryIndex < retryDelays.count else { return }
        let delay = retryDelays[retryIndex]
        retryIndex += 1
        let token = generation
        retryTask = Task(priority: .utility) { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            await self?.retry(generation: token)
        }
    }

    private func retry(generation token: UUID) async {
        retryTask = nil
        guard running, token == generation else { return }
        do { try await rescan() }
        catch { await reportIssue("A pending screenshot could not be rescanned; its source is preserved.") }
    }

    private func reportIssue(_ message: String) async {
        guard reportedIssues.insert(message).inserted else { return }
        await onIssue(message)
    }
}
