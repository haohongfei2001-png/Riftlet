import Foundation
import AppKit
import CryptoKit
import RiftletCore

private struct SourceCheckpoint: Codable {
    let version: Int
    let baselineSourceKeys: Set<String>
}

private struct Observation {
    let url: URL
    var signature: FileSignature
    let firstSeenAt: Date
    var stableSince: Date
}

private struct PendingSourceCapture: Codable, Sendable {
    let url: URL
    var signature: FileSignature
    let firstSeenAt: Date
    var stableSince: Date
}

private struct CaptureEpoch: Codable {
    let version: Int
    let beganAt: Date
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
    private let now: @Sendable () -> Date
    private var watcher: FolderWatcher?
    private var parentWatcher: FolderWatcher?
    private var wakeObserver: NSObjectProtocol?
    private var retryTask: Task<Void, Never>?
    private var running = false
    private var initializing = false
    private var generation = UUID()
    private var scanningGeneration: UUID?
    private var rebindRequest = UUID()
    private var dirty = false
    private var retryIndex = 0
    private var observations: [String: Observation] = [:]
    private var baseline: Set<String>?
    private var installationStart = Date()
    private var reportedIssues = Set<String>()
    private var pendingHandoffs: [String: PendingSourceCapture] = [:]
    private var drainingHandoffs = false
    private static let handoffCheckpoint = "capture-pending-handoffs-v1"
    private static let epochCheckpoint = "capture-collection-epoch-v1"
    private let retryDelays: [UInt64] = [150_000_000, 350_000_000, 800_000_000, 2_000_000_000, 5_000_000_000]

    public init(store: QueueStore, privateRoot: URL, sourceDirectory: URL,
                onChange: @escaping @Sendable () async -> Void = {},
                onIssue: @escaping @Sendable (String) async -> Void = { _ in },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        importer = PrivateAssetImporter(privateRoot: privateRoot, store: store)
        self.sourceDirectory = sourceDirectory.standardizedFileURL
        self.onChange = onChange; self.onIssue = onIssue
        self.now = now
    }

    public func start() async throws {
        guard !running else { return }
        guard await store.mode == .production else { throw RiftletError.modeMismatch }
        guard !running else { return }
        running = true
        initializing = true
        installationStart = now()
        generation = UUID()
        let token = generation
        do {
            // Acknowledged watch first: later scan and import awaits cannot open an event gap.
            try await attachWatcher()
            guard running, generation == token else { return }
            if let data = try await store.checkpoint(for: Self.epochCheckpoint) {
                guard running, generation == token else { return }
                let epoch = try JSONDecoder().decode(CaptureEpoch.self, from: data)
                guard epoch.version == 1 else { throw CaptureError.invalidManifest }
                installationStart = epoch.beganAt
            } else {
                let epoch = CaptureEpoch(version: 1, beganAt: installationStart)
                try await store.saveCheckpoint(try JSONEncoder().encode(epoch), for: Self.epochCheckpoint)
            }
            guard running, generation == token else { return }
            let report = try await importer.recover()
            guard running, generation == token else { return }
            if let data = try await store.checkpoint(for: Self.handoffCheckpoint) {
                guard running, generation == token else { return }
                let restored = try JSONDecoder().decode([PendingSourceCapture].self, from: data)
                pendingHandoffs = Dictionary(restored.map { ($0.signature.sourceKey, $0) }, uniquingKeysWith: { first, _ in first })
            }
            if !report.missing.isEmpty { await reportIssue("Some private copies are missing; their queue records are preserved.") }
            if !report.invalid.isEmpty { await reportIssue("Some import journals need recovery; valid captures remain available.") }
            let key = checkpointKey
            if let data = try await store.checkpoint(for: key) {
                guard running, generation == token else { return }
                let checkpoint = try JSONDecoder().decode(SourceCheckpoint.self, from: data)
                guard checkpoint.version == 1 else { throw CaptureError.invalidManifest }
                baseline = checkpoint.baselineSourceKeys
            }
            guard running, generation == token else { return }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
                    guard let service = self else { return }
                    Task(priority: .utility) { await service.refreshAfterWake() }
                }
            initializing = false
            try await rescan()
        } catch {
            if generation == token { stop() }
            throw error
        }
    }

    public func stop() {
        running = false
        initializing = false
        generation = UUID()
        rebindRequest = UUID()
        scanningGeneration = nil
        watcher?.cancel(); watcher = nil
        parentWatcher?.cancel(); parentWatcher = nil
        retryTask?.cancel(); retryTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    public func currentSourceDirectory() -> URL { sourceDirectory }

    /// Rebind only to a directory already selected by the system/user. Prepare the new
    /// descriptor and checkpoint before releasing the old watch. No access is granted here.
    public func setSourceDirectory(_ directory: URL) async throws {
        guard directory.isFileURL else { throw CaptureError.invalidLocationPreference }
        let destination = directory.standardizedFileURL
        if destination == sourceDirectory {
            if !running { try await start() }
            return
        }
        guard running else {
            sourceDirectory = destination
            baseline = nil; observations.removeAll()
            try await start()
            return
        }

        let originalGeneration = generation
        let request = UUID()
        rebindRequest = request
        let nextGeneration = UUID()
        let next = makeWatcher(directory: destination, token: nextGeneration)
        do {
            try await next.start()
            guard running, generation == originalGeneration, rebindRequest == request else { next.cancel(); return }
            var nextBaseline: Set<String>?
            if let data = try await store.checkpoint(for: Self.checkpointKey(for: destination)) {
                let checkpoint = try JSONDecoder().decode(SourceCheckpoint.self, from: data)
                guard checkpoint.version == 1 else { throw CaptureError.invalidManifest }
                nextBaseline = checkpoint.baselineSourceKeys
            }
            guard running, generation == originalGeneration, rebindRequest == request else { next.cancel(); return }

            // Journal unresolved old-source candidates before closing its descriptor. A
            // partial screenshot can then complete after the switch or after a restart.
            let departingCandidates = ((try? candidateFiles(in: sourceDirectory)) ?? [])
                + observations.values.map { ($0.url, $0.signature) }
            for (url, signature) in departingCandidates {
                guard baseline?.contains(signature.sourceKey) != true else { continue }
                if baseline == nil, signature.createdAt < installationStart { continue }
                if try await store.containsSource(key: signature.sourceKey) { continue }
                guard running, generation == originalGeneration, rebindRequest == request else { next.cancel(); return }
                if pendingHandoffs[signature.sourceKey] == nil {
                    let observed = observations[signature.sourceKey]
                    pendingHandoffs[signature.sourceKey] = PendingSourceCapture(url: url, signature: signature,
                        firstSeenAt: observed?.firstSeenAt ?? now(), stableSince: observed?.stableSince ?? now())
                }
            }
            try await saveHandoffs()
            guard running, generation == originalGeneration, rebindRequest == request else { next.cancel(); return }

            // No await between invalidating old callbacks and publishing the prepared watch.
            generation = nextGeneration
            watcher?.cancel(); watcher = next
            parentWatcher?.cancel(); parentWatcher = nil
            retryTask?.cancel(); retryTask = nil
            sourceDirectory = destination
            baseline = nextBaseline
            observations.removeAll(); retryIndex = 0; reportedIssues.removeAll()
            initializing = false
            // Retain installationStart: a screenshot saved into the newly selected folder
            // before its preference notification arrives must not become historical baseline.
            try await rescan()
        } catch {
            if generation != nextGeneration { next.cancel() }
            throw error
        }
    }

    public func rescan() async throws {
        guard running else { return }
        dirty = true
        guard !initializing else { return }
        let token = generation
        guard scanningGeneration != token else { return }
        scanningGeneration = token
        defer { if scanningGeneration == token { scanningGeneration = nil } }
        var passes = 0
        repeat {
            dirty = false
            try await scanOnce()
            guard running, generation == token else { return }
            if try await drainHandoffs() { scheduleRetry() }
            passes += 1
        } while dirty && running && generation == token && passes < 2
        if dirty, generation == token { scheduleRetry() }
    }

    private var checkpointKey: String {
        Self.checkpointKey(for: sourceDirectory)
    }

    private static func checkpointKey(for directory: URL) -> String {
        let digest = SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return "capture-source-v1:" + digest
    }

    private func scanOnce() async throws {
        let token = generation
        let key = checkpointKey
        let candidates = try candidateFiles(in: sourceDirectory)
        if baseline == nil {
            // First installation excludes existing history. A screenshot actually created
            // after watch startup is still new even if it arrives during the initial scan.
            let initial = Set(candidates.filter { $0.1.createdAt < installationStart }.map { $0.1.sourceKey })
            let checkpoint = SourceCheckpoint(version: 1, baselineSourceKeys: initial)
            try await store.saveCheckpoint(try JSONEncoder().encode(checkpoint), for: key)
            guard running, generation == token else { return }
            baseline = initial
        }
        let now = self.now()
        var needsRetry = false
        var imported = false
        var importedCount = 0
        let currentKeys = Set(candidates.map { $0.1.sourceKey })
        observations = observations.filter { currentKeys.contains($0.key) }
        for (url, signature) in candidates {
            guard running, generation == token else { return }
            guard baseline?.contains(signature.sourceKey) != true else { continue }
            let alreadyStored = try await store.containsSource(key: signature.sourceKey)
            guard running, generation == token else { return }
            if alreadyStored { observations.removeValue(forKey: signature.sourceKey); continue }
            // Bound expensive copies, not failed/non-screenshot candidates. Otherwise 128
            // ordinary images could permanently starve a later genuine screenshot.
            if importedCount >= 128 { needsRetry = true; break }
            if let previous = observations[signature.sourceKey] {
                if previous.signature != signature {
                    observations[signature.sourceKey] = Observation(url: url, signature: signature,
                        firstSeenAt: previous.firstSeenAt, stableSince: now)
                    needsRetry = true; continue
                }
                if now.timeIntervalSince(previous.stableSince) < 0.12 { needsRetry = true; continue }
            } else {
                observations[signature.sourceKey] = Observation(url: url, signature: signature, firstSeenAt: now, stableSince: now)
                needsRetry = true; continue
            }
            do {
                _ = try await importer.importStableFile(at: url, signature: signature,
                    firstSeenAt: observations[signature.sourceKey]?.firstSeenAt ?? now)
                guard running, generation == token else { await onChange(); return }
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
        if needsRetry, generation == token { scheduleRetry() }
    }

    private func candidateFiles(in directory: URL) throws -> [(URL, FileSignature)] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
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
        return candidates
    }

    private func saveHandoffs() async throws {
        let values = pendingHandoffs.values.sorted { $0.signature.sourceKey < $1.signature.sourceKey }
        try await store.saveCheckpoint(try JSONEncoder().encode(values), for: Self.handoffCheckpoint)
    }

    private func drainHandoffs() async throws -> Bool {
        guard !pendingHandoffs.isEmpty else { return false }
        guard !drainingHandoffs else { return true }
        drainingHandoffs = true
        defer { drainingHandoffs = false }
        var changed = false
        var imported = false
        var copyCount = 0
        for key in pendingHandoffs.keys.sorted() {
            guard running else { break }
            guard var item = pendingHandoffs[key] else { continue }
            if try await store.containsSource(key: key) {
                pendingHandoffs.removeValue(forKey: key); changed = true; continue
            }
            if copyCount >= 128 { break }
            do {
                let current = try FileSignature.read(at: item.url)
                // A replaced inode is a new capture occurrence, not completion of this one.
                guard current.sourceKey == key else { continue }
                if current != item.signature {
                    item.signature = current; item.stableSince = now()
                    pendingHandoffs[key] = item; changed = true; continue
                }
                guard now().timeIntervalSince(item.stableSince) >= 0.12 else { continue }
                _ = try await importer.importStableFile(at: item.url, signature: current, firstSeenAt: item.firstSeenAt)
                pendingHandoffs.removeValue(forKey: key)
                changed = true; imported = true; copyCount += 1
            } catch CaptureError.notScreenshot {
                pendingHandoffs.removeValue(forKey: key); changed = true
            } catch {
                // Unfinished/unreadable captures remain durably addressable. Retry is bounded
                // by the same event/wake budget as the active source; never delete the source.
            }
        }
        if changed { try await saveHandoffs() }
        if imported { await onChange() }
        return !pendingHandoffs.isEmpty
    }

    private func attachWatcher() async throws {
        let token = generation
        let next = makeWatcher(directory: sourceDirectory, token: token)
        try await next.start()
        guard running, generation == token else { next.cancel(); return }
        watcher?.cancel(); watcher = next
        parentWatcher?.cancel(); parentWatcher = nil
    }

    private func makeWatcher(directory: URL, token: UUID) -> FolderWatcher {
        FolderWatcher(url: directory,
            onDirty: { [weak self] in
                guard let service = self else { return }
                Task(priority: .utility) { await service.event(generation: token, lost: false) }
            },
            onLost: { [weak self] in
                guard let service = self else { return }
                Task(priority: .utility) { await service.event(generation: token, lost: true) }
            })
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
            do {
                try await parent.start()
                guard running, generation == token else { parent.cancel(); return }
                parentWatcher?.cancel(); parentWatcher = parent
            }
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

    private func refreshAfterWake() async {
        await wake(generation: generation)
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
        guard running, token == generation else { return }
        retryTask = nil
        do { try await rescan() }
        catch { await reportIssue("A pending screenshot could not be rescanned; its source is preserved.") }
    }

    private func reportIssue(_ message: String) async {
        guard reportedIssues.insert(message).inserted else { return }
        await onIssue(message)
    }
}
