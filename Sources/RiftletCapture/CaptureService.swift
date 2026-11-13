import Foundation
import AppKit
import CryptoKit
import Darwin
import RiftletCore

private struct SourceCheckpoint: Codable {
    let version: Int
    let baselineSourceKeys: Set<String>
}

private struct SourceBaseline {
    let keys: Set<String>
    private let earlierFileIDs: Set<String>

    init(_ keys: Set<String>) {
        self.keys = keys
        earlierFileIDs = Set(keys.compactMap(FileSignature.legacyFileID))
    }
    func excludes(_ candidate: FileSignature, collectionBeganAt: Date) -> Bool {
        // The old baseline held only files older than this collection epoch.
        // Preserve that exclusion without assigning an old asset to this volume.
        keys.contains(candidate.sourceKey) ||
            (candidate.createdAt < collectionBeganAt && earlierFileIDs.contains(candidate.fileID))
    }
}

private struct Observation {
    let url: URL
    var signature: FileSignature
    let firstSeenAt: Date
    var stableSince: Date
    var historicalHold: (generation: UUID, directory: WatchedFileIdentity?, changedAt: Duration)?
}

private struct PendingSourceCapture: Codable, Equatable, Sendable {
    let url: URL
    var signature: FileSignature
    let firstSeenAt: Date
    var stableSince: Date
}

private struct CaptureEpoch: Codable {
    let version: Int
    let beganAt: Date
}

private struct DepartingCaptureSource: Codable, Sendable {
    let id: UUID
    let directory: URL
    let directoryIdentity: WatchedFileIdentity?
    let baselineKeys: Set<String>
    let collectionBeganAt: Date
    let knownCandidates: [PendingSourceCapture]
    var knownCandidatesQueued: Bool?
    var retiredAt: Date?
}

private struct CaptureHandoffCheckpoint: Codable {
    let version: Int
    let candidates: [PendingSourceCapture]
    let departures: [DepartingCaptureSource]
}

enum CaptureLifecycleCheckpoint: Equatable, Sendable {
    case beforeModeRead, departureRecorded, watcherRetired
}

/// Directory events request reconciliation; they are not one-event/one-image assertions.
/// There is no idle polling. A burst may schedule up to five bounded retries for late
/// metadata / partial writes, and wake or an explicit rescan can retry later.
public actor CaptureService {
    private let store: QueueStore
    public let importer: PrivateAssetImporter
    private var sourceDirectory: URL
    private let permitsRead: (@Sendable (URL) async -> Bool)?
    private let onChange: @Sendable () async -> Void
    private let onImported: @Sendable (AssetRecord, ScreenshotSourceObservation) -> Void
    private let onIssue: @Sendable (String) async -> Void
    private let onDiagnostic: @Sendable (CaptureDiagnostic) async -> Void
    private var sourceAccessible = false
    private var latestDiagnostic: CaptureDiagnostic?
    // A failed preference switch leaves the last working source active. A scan
    // of that old source must not erase the unresolved requested-location error.
    private var locationDiagnostic: CaptureDiagnostic?
    private var diagnosticSourceKey: String?
    private var diagnosticRevision = UUID()
    private let now: @Sendable () -> Date
    private var watcher: FolderWatcher?
    private var watchedSource: FolderWatcher.OpenedWatch?
    private var watchedIdentity: WatchedFileIdentity? { watchedSource?.identity }
    private var parentWatcher: FolderWatcher?
    private var wakeObserver: NSObjectProtocol?
    private var retryTask: Task<Void, Never>?
    private var running = false
    private var initializing = false
    private var stoppingForExit = false
    private var activeLifecycleOperations = 0
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []
    private var generation = UUID()
    private var scanningGeneration: UUID?
    private var rebindRequest = UUID()
    private var dirty = false
    private var retryIndex = 0
    private var observations: [String: Observation] = [:]
    private var baseline: SourceBaseline?
    private var unconfirmedHandoffIDs: Set<String> = []
    private var installationStart = Date()
    private var reportedIssues = Set<String>()
    private var pendingHandoffs: [String: PendingSourceCapture] = [:]
    private var drainingHandoffs = false
    private var departingSources: [UUID: DepartingCaptureSource] = [:]
    private var departuresInProgress = Set<UUID>()
    private var lifecycleProbe: (@Sendable (CaptureLifecycleCheckpoint) async -> Void)?
    private static let handoffCheckpoint = "capture-pending-handoffs-v1"
    private static let epochCheckpoint = "capture-collection-epoch-v1"
    private let retryDelays: [UInt64] = [150_000_000, 350_000_000, 800_000_000, 2_000_000_000, 5_000_000_000]

    public init(store: QueueStore, privateRoot: URL, sourceDirectory: URL,
                permitsRead: (@Sendable (URL) async -> Bool)? = nil,
                onChange: @escaping @Sendable () async -> Void = {},
                onImported: @escaping @Sendable (AssetRecord, ScreenshotSourceObservation) -> Void = { _, _ in },
                onIssue: @escaping @Sendable (String) async -> Void = { _ in },
                onDiagnostic: @escaping @Sendable (CaptureDiagnostic) async -> Void = { _ in },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        importer = PrivateAssetImporter(privateRoot: privateRoot, store: store)
        self.sourceDirectory = sourceDirectory.standardizedFileURL
        self.permitsRead = permitsRead
        self.onChange = onChange; self.onIssue = onIssue; self.onDiagnostic = onDiagnostic
        self.onImported = onImported
        self.now = now
    }

    public func start() async throws {
        guard !stoppingForExit else { return }
        activeLifecycleOperations += 1
        defer { finishLifecycleOperation() }
        guard !running else { return }
        let requestedGeneration = generation
        await lifecycleProbe?(.beforeModeRead)
        guard await store.mode == .production else { throw RiftletError.modeMismatch }
        guard !running, generation == requestedGeneration else { return }
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
                let decoder = JSONDecoder()
                if let checkpoint = try? decoder.decode(CaptureHandoffCheckpoint.self, from: data) {
                    guard checkpoint.version == 2 else { throw CaptureError.invalidManifest }
                    pendingHandoffs = Dictionary(checkpoint.candidates.map { ($0.signature.sourceKey, $0) },
                        uniquingKeysWith: { first, _ in first })
                    departingSources = Dictionary(checkpoint.departures.map { ($0.id, $0) },
                        uniquingKeysWith: { first, _ in first })
                } else {
                    // The first C1 build stored only a candidate array. Preserve that data.
                    let restored = try decoder.decode([PendingSourceCapture].self, from: data)
                    pendingHandoffs = Dictionary(restored.map { ($0.signature.sourceKey, $0) },
                        uniquingKeysWith: { first, _ in first })
                    departingSources.removeAll()
                }
                // A legacy pending intent has no persistent volume witness.
                // Retain its evidence; an active rescan cannot silently adopt it.
                let pending = Array(pendingHandoffs.values) + departingSources.values.flatMap(\.knownCandidates)
                unconfirmedHandoffIDs.removeAll()
                for key in Set(pending.map(\.signature.sourceKey)) {
                    if let fileID = FileSignature.legacyFileID(key), try await !store.containsSource(key: key) {
                        unconfirmedHandoffIDs.insert(fileID)
                    }
                    guard running, generation == token else { return }
                }
            }
            if !report.missing.isEmpty { await reportDiagnostic(.init(code: .missingPrivateCopy)) }
            guard running, generation == token else { return }
            if !report.invalid.isEmpty { await reportDiagnostic(.init(code: .recoveryRequired)) }
            guard running, generation == token else { return }
            if report.missing.isEmpty && report.invalid.isEmpty, let code = latestDiagnostic?.code,
               [.missingPrivateCopy, .recoveryRequired].contains(code) { clearDiagnostic() }
            let key = checkpointKey
            if let data = try await store.checkpoint(for: key) {
                guard running, generation == token else { return }
                let checkpoint = try JSONDecoder().decode(SourceCheckpoint.self, from: data)
                guard checkpoint.version == 1 else { throw CaptureError.invalidManifest }
                baseline = SourceBaseline(checkpoint.baselineSourceKeys)
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
            if generation == token {
                await reportDiagnostic(.classify(error, context: .source))
                if generation == token { stop() }
            }
            throw error
        }
    }

    public func stop() {
        running = false
        sourceAccessible = false
        initializing = false
        generation = UUID()
        diagnosticRevision = UUID()
        rebindRequest = UUID()
        scanningGeneration = nil
        departuresInProgress.removeAll()
        watcher?.cancel(); watcher = nil
        watchedSource = nil
        parentWatcher?.cancel(); parentWatcher = nil
        retryTask?.cancel(); retryTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// The watcher may be inside an async importer or journal write when stop()
    /// invalidates its generation. Wait for those frames before replacing the App.
    public func finishForApplicationExit() async {
        stoppingForExit = true
        stop()
        if activeLifecycleOperations > 0 {
            await withCheckedContinuation { exitWaiters.append($0) }
        }
    }

    private func finishLifecycleOperation() {
        activeLifecycleOperations -= 1
        if activeLifecycleOperations == 0 && !exitWaiters.isEmpty {
            let waiters = exitWaiters
            exitWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    public func currentSourceDirectory() -> URL { sourceDirectory }

    public func statusSnapshot() -> CaptureStatusSnapshot {
        CaptureStatusSnapshot(sourceDirectory: sourceDirectory, isRunning: running,
                              sourceAccessible: sourceAccessible, latestDiagnostic: locationDiagnostic ?? latestDiagnostic)
    }

    /// An explicit setup/menu recheck reopens the watch, so a revoked/regranted directory
    /// is recoverable even without a new file event. No permission is requested here.
    public func recheck() async throws {
        if !running { try await start(); return }
        let token = generation
        retryIndex = 0
        reportedIssues.removeAll()
        do {
            try await attachWatcher()
            guard running, generation == token else { return }
            try await rescan()
        } catch {
            if running, generation == token { await reportDiagnostic(.classify(error, context: .source)) }
            throw error
        }
    }

    func reportLocationFailure(_ diagnostic: CaptureDiagnostic) async {
        locationDiagnostic = diagnostic
        await reportDiagnostic(diagnostic)
    }

    func locationResolved() {
        let resolved = locationDiagnostic
        locationDiagnostic = nil
        if latestDiagnostic == resolved || latestDiagnostic?.code == .sourcePreferenceUnreadable { clearDiagnostic() }
    }

    /// Internal controlled scheduling seam; production has no hook or configuration entry.
    func setLifecycleProbe(_ probe: @escaping @Sendable (CaptureLifecycleCheckpoint) async -> Void) {
        lifecycleProbe = probe
    }

    /// Rebind only to a directory already selected by the system/user. Prepare the new
    /// descriptor and checkpoint before releasing the old watch. No access is granted here.
    public func setSourceDirectory(_ directory: URL) async throws {
        guard !stoppingForExit else { return }
        activeLifecycleOperations += 1
        defer { finishLifecycleOperation() }
        guard directory.isFileURL else { throw CaptureError.invalidLocationPreference }
        let destination = directory.standardizedFileURL
        if destination == sourceDirectory {
            if !running { try await start() }
            return
        }
        guard running else {
            sourceDirectory = destination
            sourceAccessible = false
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
            let nextSource = try await next.start()
            guard running, generation == originalGeneration, rebindRequest == request else { next.cancel(); return }
            var nextBaseline: SourceBaseline?
            if let data = try await store.checkpoint(for: Self.checkpointKey(for: destination)) {
                let checkpoint = try JSONDecoder().decode(SourceCheckpoint.self, from: data)
                guard checkpoint.version == 1 else { throw CaptureError.invalidManifest }
                nextBaseline = SourceBaseline(checkpoint.baselineSourceKeys)
            }
            guard running, generation == originalGeneration, rebindRequest == request else { next.cancel(); return }

            // Persist the directory, not a finite early file list: captures may still arrive
            // while SQLite awaits. An interrupted handoff can therefore enumerate it later.
            let departure = DepartingCaptureSource(id: request, directory: sourceDirectory, directoryIdentity: watchedIdentity,
                baselineKeys: baseline?.keys ?? [], collectionBeganAt: installationStart,
                knownCandidates: observations.values.map {
                    PendingSourceCapture(url: $0.url, signature: $0.signature,
                                         firstSeenAt: $0.firstSeenAt, stableSince: $0.stableSince)
                }, retiredAt: nil)
            departingSources[request] = departure
            departuresInProgress.insert(request)
            defer { departuresInProgress.remove(request) }
            try await saveHandoffs()
            await lifecycleProbe?(.departureRecorded)
            guard running, generation == originalGeneration, rebindRequest == request else { next.cancel(); return }

            // No await between invalidating old callbacks and publishing the prepared watch.
            let oldWatcher = watcher
            generation = nextGeneration
            watcher = next
            watchedSource = nextSource
            parentWatcher?.cancel(); parentWatcher = nil
            retryTask?.cancel(); retryTask = nil
            sourceDirectory = destination
            sourceAccessible = false
            baseline = nextBaseline
            observations.removeAll(); retryIndex = 0; reportedIssues.removeAll()
            initializing = false
            // Retain installationStart: a screenshot saved into the newly selected folder
            // before its preference notification arrives must not become historical baseline.
            let retirement = await oldWatcher?.cancelAndWait() ?? Date()
            guard running, generation == nextGeneration, rebindRequest == request else { return }
            if var saved = departingSources[request] {
                saved.retiredAt = retirement
                departingSources[request] = saved
            }
            await lifecycleProbe?(.watcherRetired)
            guard running, generation == nextGeneration, rebindRequest == request else { return }
            // Final enumeration occurs only after retirement acknowledgement. There is no
            // await between enumeration/filtering and recording the complete candidate set.
            if await permitsRead?(departure.directory) != false {
                guard running, generation == nextGeneration, rebindRequest == request else { return }
                finishDeparture(request)
            }
            try await saveHandoffs()
            try await rescan()
        } catch {
            if generation != nextGeneration { next.cancel() }
            throw error
        }
    }

    public func rescan() async throws {
        guard !stoppingForExit else { return }
        activeLifecycleOperations += 1
        defer { finishLifecycleOperation() }
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
            try await recoverDepartures()
            guard running, generation == token else { return }
            let needsHandoffRetry = try await drainHandoffs()
            if generation == token, needsHandoffRetry || departingSources.values.contains(where: { $0.directoryIdentity != nil }) {
                scheduleRetry()
            }
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
        guard try await confirmCurrentSource(generation: token) else { return }
        let key = checkpointKey
        let observedDirectory = watchedIdentity
        let localAPFSVolume = watchedSource?.localAPFSVolume
        let candidates: [(URL, FileSignature, Duration)]
        do { candidates = try candidateFiles(in: sourceDirectory) }
        catch {
            sourceAccessible = false
            await reportDiagnostic(.init(code: .sourceUnavailable))
            throw error
        }
        sourceAccessible = true
        if latestDiagnostic?.code == .sourceUnavailable { clearDiagnostic() }
        if baseline == nil {
            // First installation excludes existing history. A screenshot actually created
            // after watch startup is still new even if it arrives during the initial scan.
            // A pre-epoch file without a volume witness may still be excluded from
            // collection. An exclusion cannot authorize an import or identify an asset.
            let initial = Set(candidates.filter { $0.1.createdAt < installationStart }.map { $0.1.sourceKey })
            let checkpoint = SourceCheckpoint(version: 1, baselineSourceKeys: initial)
            try await store.saveCheckpoint(try JSONEncoder().encode(checkpoint), for: key)
            guard running, generation == token else { return }
            baseline = SourceBaseline(initial)
        }
        let now = self.now()
        var needsRetry = false
        var imported = false
        var importedCount = 0
        let currentKeys = Set(candidates.map { $0.1.sourceKey })
        observations = observations.filter { currentKeys.contains($0.key) }
        if let watchedIdentity, watchedIdentity.volumeUUID == nil {
            if latestDiagnostic?.code != .sourceVolumeUnidentified { await reportDiagnostic(.init(code: .sourceVolumeUnidentified)) }
            return
        }
        // A new source or a removed ambiguous file can resolve these diagnostics
        // without importing that item. Leave other recovery errors intact.
        var sourceIssueCleared = false
        if let code = latestDiagnostic?.code, [.sourceVolumeUnidentified, .fileVolumeUnidentified, .historicalSourceUnconfirmed].contains(code),
           diagnosticSourceKey.map({ !currentKeys.contains($0) }) ?? true {
            clearDiagnostic()
            reportedIssues.remove(code.rawValue)
            sourceIssueCleared = true
        }
        for (url, signature, changedAt) in candidates {
            guard running, generation == token else { return }
            guard baseline?.excludes(signature, collectionBeganAt: installationStart) != true else { continue }
            guard let volume = signature.volumeUUID else {
                await reportDiagnostic(.init(code: .fileVolumeUnidentified), sourceKey: signature.sourceKey)
                continue
            }
            let alreadyStored = try await store.containsSource(key: signature.sourceKey)
            guard running, generation == token else { return }
            if alreadyStored { observations.removeValue(forKey: signature.sourceKey); continue }
            if unconfirmedHandoffIDs.contains(signature.fileID) {
                await reportDiagnostic(.init(code: .historicalSourceUnconfirmed), sourceKey: signature.sourceKey)
                continue
            }
            // Bound expensive copies, not failed/non-screenshot candidates. Otherwise 128
            // ordinary images could permanently starve a later genuine screenshot.
            if importedCount >= 128 { needsRetry = true; break }
            if let previous = observations[signature.sourceKey] {
                if let hold = previous.historicalHold {
                    // Only a completed negative decision is reusable. Even xattr
                    // changes invalidate it without changing file size or mtime.
                    if volume == localAPFSVolume, previous.signature == signature, hold.generation == token,
                       hold.directory == observedDirectory, hold.changedAt == changedAt {
                        await reportDiagnostic(.init(code: .historicalSourceUnconfirmed), sourceKey: signature.sourceKey)
                        continue
                    }
                    observations[signature.sourceKey]?.historicalHold = nil
                    if clearHistoricalDiagnostic(for: signature.sourceKey) { sourceIssueCleared = true }
                }
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
                guard try await confirmCurrentSource(generation: token) else { return }
                let record = try await importer.importStableFile(at: url, signature: signature,
                    firstSeenAt: observations[signature.sourceKey]?.firstSeenAt ?? now)
                guard running, generation == token else { await onChange(); return }
                // Optional presentation observation AFTER durable commit, with
                // no wait for metadata, animation or a second stability window.
                onImported(record, ScreenshotSourceObservation(url: url, signature: signature, assetID: record.id))
                observations.removeValue(forKey: signature.sourceKey)
                imported = true
                importedCount += 1
                if diagnosticSourceKey == signature.sourceKey { clearDiagnostic() }
            } catch CaptureError.notScreenshot {
                // Present false metadata is not collected and does not keep a timer alive.
                guard running, generation == token else { return }
                if clearHistoricalDiagnostic(for: signature.sourceKey) { sourceIssueCleared = true }
            } catch CaptureError.metadataPending { needsRetry = true }
              catch CaptureError.unstableFile { needsRetry = true }
              catch CaptureError.incompleteImage { needsRetry = true }
              catch CaptureError.importInProgress { needsRetry = true }
              catch CaptureError.historicalSourceUnconfirmed {
                guard running, generation == token else { return }
                // Other filesystems can store xattrs separately from the source inode.
                if volume == localAPFSVolume {
                    observations[signature.sourceKey]?.historicalHold = (token, observedDirectory, changedAt)
                }
                await reportDiagnostic(.init(code: .historicalSourceUnconfirmed), sourceKey: signature.sourceKey)
            } catch CaptureError.unsupportedImage {
                guard running, generation == token else { return }
                await reportDiagnostic(.init(code: .unsupportedFormat), sourceKey: signature.sourceKey)
            } catch CaptureError.imageTooLarge {
                guard running, generation == token else { return }
                await reportDiagnostic(.init(code: .imageTooLarge), sourceKey: signature.sourceKey)
            }
              catch {
                guard running, generation == token else { return }
                needsRetry = true
                await reportDiagnostic(.classify(error, context: .privateStorage), sourceKey: signature.sourceKey)
            }
        }
        if imported || sourceIssueCleared { await onChange() }
        if needsRetry, generation == token { scheduleRetry() }
    }

    private func candidateFiles(in directory: URL) throws -> [(URL, FileSignature, Duration)] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var candidates: [(URL, FileSignature, Duration)] = []
        for url in urls {
            // The encoding is validated from bytes later. This only bounds metadata work.
            guard CaptureSource.mayBeImage(url) else { continue }
            do {
                let observation = try FileSignature.observe(at: url)
                candidates.append((url, observation.signature, observation.changedAt))
            } catch CaptureError.notRegularFile { continue }
            catch CaptureError.io(_, let code) where code == ELOOP { continue } // symlinks are never candidates
            catch { continue }
        }
        candidates.sort {
            if $0.1.createdAt != $1.1.createdAt { return $0.1.createdAt < $1.1.createdAt }
            return $0.1.sourceKey < $1.1.sourceKey
        }
        return candidates
    }

    private func saveHandoffs() async throws {
        let values = pendingHandoffs.values.sorted { $0.signature.sourceKey < $1.signature.sourceKey }
        let departures = departingSources.values.sorted { $0.id.uuidString < $1.id.uuidString }
        let checkpoint = CaptureHandoffCheckpoint(version: 2, candidates: values, departures: departures)
        try await store.saveCheckpoint(try JSONEncoder().encode(checkpoint), for: Self.handoffCheckpoint)
    }

    @discardableResult
    private func finishDeparture(_ id: UUID) -> Bool {
        guard var departure = departingSources[id] else { return false }
        var changed = false
        // On interrupted handoff, conservatively retain screenshots through this recovery
        // snapshot. Future old-directory writes are excluded once this snapshot is saved.
        if departure.retiredAt == nil {
            departure.retiredAt = Date()
            departingSources[id] = departure
            changed = true
        }
        let cutoff = departure.retiredAt!
        let exclusion = SourceBaseline(departure.baselineKeys)
        // Even an older checkpoint with no directory identity can recover its
        // recorded file identities. Keep the departure until its directory is proven.
        if departure.knownCandidatesQueued != true {
            for candidate in departure.knownCandidates where pendingHandoffs[candidate.signature.sourceKey] == nil {
                guard !exclusion.excludes(candidate.signature, collectionBeganAt: departure.collectionBeganAt),
                      candidate.signature.createdAt <= cutoff else { continue }
                pendingHandoffs[candidate.signature.sourceKey] = candidate
            }
            departure.knownCandidatesQueued = true
            departingSources[id] = departure
            changed = true
        }
        guard let identity = departure.directoryIdentity,
              let directory = RetiredCaptureDirectory(url: departure.directory, identity: identity) else { return changed }
        let snapshot = directory.candidates()
        for (url, signature) in snapshot.files {
            guard signature.createdAt >= departure.collectionBeganAt,
                  signature.createdAt <= cutoff, !exclusion.excludes(signature, collectionBeganAt: departure.collectionBeganAt) else { continue }
            let previous = departure.knownCandidates.first { $0.signature.sourceKey == signature.sourceKey }
            let pending = pendingHandoffs[signature.sourceKey]
            let stableSince: Date
            if let pending, pending.signature == signature { stableSince = pending.stableSince }
            else if let previous, previous.signature == signature { stableSince = previous.stableSince }
            else { stableSince = now() }
            let next = PendingSourceCapture(url: url, signature: signature,
                firstSeenAt: pending?.firstSeenAt ?? previous?.firstSeenAt ?? now(),
                stableSince: stableSince)
            if pending != next { pendingHandoffs[signature.sourceKey] = next; changed = true }
        }
        if snapshot.complete { departingSources.removeValue(forKey: id); changed = true }
        return changed
    }

    private func recoverDepartures() async throws {
        let token = generation
        var changed = false
        for id in departingSources.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard !departuresInProgress.contains(id), let departure = departingSources[id] else { continue }
            // An interrupted request that never switched away is still the active source.
            guard departure.directory != sourceDirectory || departure.retiredAt != nil else { continue }
            guard await permitsRead?(departure.directory) != false else { continue }
            guard running, generation == token else { return }
            if finishDeparture(id) { changed = true }
        }
        if changed { try await saveHandoffs() }
    }

    private func drainHandoffs() async throws -> Bool {
        guard !pendingHandoffs.isEmpty else { return false }
        guard !drainingHandoffs else { return true }
        drainingHandoffs = true
        defer { drainingHandoffs = false }
        var changed = false
        var imported = false
        var copyCount = 0
        let token = generation
        for key in pendingHandoffs.keys.sorted() {
            guard running else { break }
            guard var item = pendingHandoffs[key] else { continue }
            if try await store.containsSource(key: key) {
                pendingHandoffs.removeValue(forKey: key); changed = true; continue
            }
            if copyCount >= 128 { break }
            do {
                guard await permitsRead?(item.url.deletingLastPathComponent()) != false else { continue }
                guard running, generation == token else { break }
                let current = try FileSignature.read(at: item.url)
                // A replaced inode is a new capture occurrence, not completion of this one.
                guard current.sourceKey == key else { continue }
                guard current.volumeUUID != nil, !unconfirmedHandoffIDs.contains(current.fileID) else { continue }
                if current != item.signature {
                    item.signature = current; item.stableSince = now()
                    pendingHandoffs[key] = item; changed = true; continue
                }
                guard now().timeIntervalSince(item.stableSince) >= 0.12 else { continue }
                let record = try await importer.importStableFile(at: item.url, signature: current, firstSeenAt: item.firstSeenAt)
                onImported(record, ScreenshotSourceObservation(url: item.url, signature: current, assetID: record.id))
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
        guard try await confirmCurrentSource(generation: token) else { return }
        let next = makeWatcher(directory: sourceDirectory, token: token)
        let source = try await next.start()
        guard running, generation == token else { next.cancel(); return }
        watcher?.cancel(); watcher = next
        watchedSource = source
        parentWatcher?.cancel(); parentWatcher = nil
    }

    // A parent watch, wake or retry can arrive without a screenshot-location
    // preference change. Never reopen or enumerate a replacement via that path.
    private func confirmCurrentSource(generation token: UUID) async throws -> Bool {
        let allowed = await permitsRead?(sourceDirectory) != false
        guard running, generation == token else { return false }
        guard allowed else {
            stop()
            let failure = CocoaError(.fileReadNoPermission)
            await reportDiagnostic(.classify(failure, context: .source))
            await onChange()
            throw failure
        }
        return true
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
            sourceAccessible = false
            let parent = FolderWatcher(url: sourceDirectory.deletingLastPathComponent(),
                onDirty: { [weak self] in
                    guard let service = self else { return }
                    Task(priority: .utility) { await service.wake(generation: token) }
                },
                onLost: { [weak self] in
                    guard let service = self else { return }
                    Task(priority: .utility) { await service.reportLostParent(generation: token) }
                })
            do {
                try await parent.start()
                guard running, generation == token else { parent.cancel(); return }
                parentWatcher?.cancel(); parentWatcher = parent
                // An exchange can finish before the parent watch is armed.
                // Validate the current path now; later changes reach the parent.
                await wake(generation: token)
            }
            catch {
                guard running, generation == token else { return }
                await reportDiagnostic(.init(code: .sourceUnavailable))
            }
            // A missing or unreadable path leaves the parent watching for recovery.
            if running, generation == token, !sourceAccessible { await onChange() }
            return
        }
        do { try await rescan() }
        catch {
            guard running, generation == token else { return }
            await reportDiagnostic(.classify(error, context: .source))
        }
    }

    private func wake(generation token: UUID) async {
        guard running, generation == token else { return }
        let wasAccessible = sourceAccessible
        retryIndex = 0
        do {
            // Reopen on wake, including when a prior directory descriptor became stale.
            try await attachWatcher()
            guard running, generation == token else { return }
            try await rescan()
        } catch {
            guard running, generation == token else { return }
            sourceAccessible = false
            await reportDiagnostic(.classify(error, context: .source))
        }
        if running, generation == token, wasAccessible != sourceAccessible { await onChange() }
    }

    private func refreshAfterWake() async {
        await wake(generation: generation)
    }

    private func reportLostParent(generation token: UUID) async {
        guard running, generation == token, watcher == nil else { return }
        sourceAccessible = false
        await reportDiagnostic(.init(code: .sourceUnavailable))
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
        catch {
            guard running, generation == token else { return }
            await reportDiagnostic(.classify(error, context: .source))
        }
    }

    private func clearDiagnostic() {
        latestDiagnostic = nil
        diagnosticSourceKey = nil
        diagnosticRevision = UUID()
    }

    private func clearHistoricalDiagnostic(for key: String) -> Bool {
        guard diagnosticSourceKey == key, latestDiagnostic?.code == .historicalSourceUnconfirmed else { return false }
        clearDiagnostic()
        reportedIssues.remove(CaptureDiagnosticCode.historicalSourceUnconfirmed.rawValue)
        return true
    }

    private func reportDiagnostic(_ diagnostic: CaptureDiagnostic, sourceKey: String? = nil) async {
        latestDiagnostic = diagnostic
        diagnosticSourceKey = sourceKey
        diagnosticRevision = UUID()
        let revision = diagnosticRevision
        guard reportedIssues.insert(diagnostic.code.rawValue).inserted else { return }
        await onIssue(diagnostic.userMessage)
        guard diagnosticRevision == revision else { return }
        await onDiagnostic(diagnostic)
    }
}
