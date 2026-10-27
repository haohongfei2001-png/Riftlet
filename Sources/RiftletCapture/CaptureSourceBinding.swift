import Foundation
import AppKit
import Darwin

/// A source of the system/user-selected screenshot directory. Tests provide an in-memory
/// source; the native implementation observes file events rather than polling preferences.
public protocol CaptureLocationProviding: Sendable {
    func currentDirectory() async throws -> URL
    func start(onChange: @escaping @Sendable () async -> Void) async throws
    func stop() async
}

/// Watches both the preference file and its parent: in-place writes and atomic replacement
/// are separate filesystem events. Only this one domain is parsed; no preference is written.
/// Actual Screenshot.app preference propagation remains a real-Mac acceptance case.
public actor SystemCaptureLocationProvider: CaptureLocationProviding {
    private let preferencesFile: URL
    private let fallbackDirectory: URL
    private var parentWatcher: FolderWatcher?
    private var fileWatcher: FolderWatcher?
    private var wakeObserver: NSObjectProtocol?
    private var onChange: (@Sendable () async -> Void)?
    private var running = false
    private var generation = UUID()
    private var observedSignature: FileSignature?
    private var parentLocation: URL?
    private var parentRevision = UUID()

    public init(preferencesFile: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences/com.apple.screencapture.plist"),
                fallbackDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop", isDirectory: true)) {
        self.preferencesFile = preferencesFile.standardizedFileURL
        self.fallbackDirectory = fallbackDirectory.standardizedFileURL
    }

    public func currentDirectory() throws -> URL {
        // Reading the observed file avoids a long-lived UserDefaults process cache. A
        // malformed/partial plist must not silently switch collection back to Desktop.
        let descriptor = Darwin.open(preferencesFile.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            // fileExists also returns false on denied parent traversal. Only an
            // actual absent preference permits the system's default location.
            if code == ENOENT { return fallbackDirectory }
            throw CaptureError.io("read-location-preference", code)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let signature = try FileSignature.read(descriptor: descriptor)
        guard signature.size > 0, signature.size <= 1_048_576 else { throw CaptureError.invalidLocationPreference }
        guard let data = try handle.read(upToCount: Int(signature.size) + 1),
              data.count == signature.size,
              signature == (try FileSignature.read(descriptor: descriptor)),
              signature == (try FileSignature.read(at: preferencesFile)),
              let values = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let domain = values as? [String: Any] else { throw CaptureError.invalidLocationPreference }
        guard let value = domain["location"] else { return fallbackDirectory }
        guard let path = value as? String else { throw CaptureError.invalidLocationPreference }
        guard !path.isEmpty else { return fallbackDirectory }
        let expanded = (path as NSString).expandingTildeInPath
        guard (expanded as NSString).isAbsolutePath, !expanded.utf8.contains(0) else { throw CaptureError.invalidLocationPreference }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    public func start(onChange: @escaping @Sendable () async -> Void) async throws {
        guard !running else { return }
        running = true
        generation = UUID()
        let token = generation
        self.onChange = onChange
        observedSignature = try? FileSignature.read(at: preferencesFile)
        do {
            try await attachParentIfNeeded(token: token)
            guard running, generation == token else { return }
            await attachFileIfNeeded(token: token)
            guard running, generation == token else { return }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
                    guard let provider = self else { return }
                    Task(priority: .utility) { await provider.signal(token: token, fileLost: true, force: true) }
                }
        } catch {
            if generation == token { stop() }
            throw error
        }
    }

    public func stop() {
        running = false
        generation = UUID()
        parentWatcher?.cancel(); parentWatcher = nil
        parentLocation = nil; parentRevision = UUID()
        fileWatcher?.cancel(); fileWatcher = nil
        onChange = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func attachParentIfNeeded(token: UUID) async throws {
        guard running, generation == token else { return }
        var directory = preferencesFile.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        while !FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            let ancestor = directory.deletingLastPathComponent()
            guard ancestor != directory else { throw CaptureError.invalidLocationPreference }
            directory = ancestor
        }
        guard parentWatcher == nil || parentLocation != directory else { return }
        let revision = UUID()
        parentRevision = revision
        let parent = FolderWatcher(url: directory,
            onDirty: { [weak self] in
                guard let provider = self else { return }
                Task(priority: .utility) { await provider.parentEvent(token: token, revision: revision, lost: false) }
            },
            onLost: { [weak self] in
                guard let provider = self else { return }
                Task(priority: .utility) { await provider.parentEvent(token: token, revision: revision, lost: true) }
            })
        do {
            try await parent.start()
            guard running, generation == token, parentRevision == revision else { parent.cancel(); return }
            parentWatcher?.cancel(); parentWatcher = parent; parentLocation = directory
        } catch { parent.cancel(); throw error }
    }

    private func parentEvent(token: UUID, revision: UUID, lost: Bool) async {
        guard running, generation == token, parentRevision == revision else { return }
        if lost { parentWatcher?.cancel(); parentWatcher = nil; parentLocation = nil }
        try? await attachParentIfNeeded(token: token)
        await signal(token: token, fileLost: lost, force: false)
    }

    private func attachFileIfNeeded(token: UUID) async {
        guard running, generation == token, fileWatcher == nil,
              FileManager.default.fileExists(atPath: preferencesFile.path) else { return }
        let file = FolderWatcher(url: preferencesFile, expectsDirectory: false,
            onDirty: { [weak self] in
                guard let provider = self else { return }
                Task(priority: .utility) { await provider.signal(token: token, fileLost: false, force: true) }
            },
            onLost: { [weak self] in
                guard let provider = self else { return }
                Task(priority: .utility) { await provider.signal(token: token, fileLost: true, force: true) }
            })
        fileWatcher = file
        do {
            try await file.start()
            guard running, generation == token else { file.cancel(); return }
        } catch {
            if fileWatcher === file { fileWatcher = nil }
            file.cancel()
            // The parent still observes creation/replacement; no polling or unsafe fallback.
        }
    }

    private func signal(token: UUID, fileLost: Bool, force: Bool) async {
        guard running, generation == token else { return }
        if fileLost { fileWatcher?.cancel(); fileWatcher = nil }
        try? await attachParentIfNeeded(token: token)
        await attachFileIfNeeded(token: token)
        guard running, generation == token, let onChange else { return }
        let signature = try? FileSignature.read(at: preferencesFile)
        // Other applications write the Preferences directory frequently. Their events do
        // not parse our plist or rebind the collector if this specific file is unchanged.
        guard force || signature != observedSignature else { return }
        observedSignature = signature
        await onChange()
    }
}

/// Serializes/coalesces location changes against one capture service. A failed switch leaves
/// the last working directory active; late observer callbacks cannot restart a stopped binding.
public actor CaptureSourceBinding {
    private struct BindingFailure: Error {
        let error: Error
        let context: CaptureDiagnosticContext
    }
    private let service: CaptureService
    private let provider: any CaptureLocationProviding
    private let onIssue: @Sendable (String) async -> Void
    private let onDiagnostic: @Sendable (CaptureDiagnostic) async -> Void
    private var generation = UUID()
    private var running = false
    private var starting = false
    private var processingGeneration: UUID?
    private var dirty = false

    public init(service: CaptureService,
                provider: any CaptureLocationProviding = SystemCaptureLocationProvider(),
                onIssue: @escaping @Sendable (String) async -> Void = { _ in },
                onDiagnostic: @escaping @Sendable (CaptureDiagnostic) async -> Void = { _ in }) {
        self.service = service; self.provider = provider; self.onIssue = onIssue; self.onDiagnostic = onDiagnostic
    }

    public func start() async throws {
        guard !running else { return }
        running = true; starting = true; dirty = true
        generation = UUID()
        let token = generation
        do {
            // Subscribe before reading the current value, closing the read/subscribe gap.
            try await provider.start { [weak self] in await self?.refresh(token: token) }
            guard running, generation == token else { return }
            starting = false
            try await reconcile(token: token)
        } catch {
            let failure = error as? BindingFailure
            let original = failure?.error ?? error
            if generation == token {
                let diagnostic = CaptureDiagnostic.classify(original, context: failure?.context ?? .locationPreference)
                await service.reportLocationFailure(diagnostic)
                guard running, generation == token else { throw original }
                await onDiagnostic(diagnostic)
                if running, generation == token { await stop() }
            }
            throw original
        }
    }

    public func refresh() async { await refresh(token: generation) }

    public func stop() async {
        running = false; starting = false; dirty = false
        generation = UUID()
        let token = generation
        await provider.stop()
        guard generation == token, !running else { return }
        await service.stop()
    }

    private func refresh(token: UUID) async {
        guard running, generation == token else { return }
        dirty = true
        guard !starting else { return }
        do { try await reconcile(token: token) }
        catch {
            guard running, generation == token else { return }
            let failure = error as? BindingFailure
            let diagnostic = CaptureDiagnostic.classify(failure?.error ?? error, context: failure?.context ?? .locationPreference)
            await service.reportLocationFailure(diagnostic)
            guard running, generation == token else { return }
            await onIssue(diagnostic.userMessage)
            guard running, generation == token else { return }
            await onDiagnostic(diagnostic)
        }
    }

    private func reconcile(token: UUID) async throws {
        guard processingGeneration != token else { return }
        processingGeneration = token
        defer { if processingGeneration == token { processingGeneration = nil } }
        repeat {
            dirty = false
            let next: URL
            do { next = try await provider.currentDirectory() }
            catch { throw BindingFailure(error: error, context: .locationPreference) }
            guard running, generation == token else { return }
            do { try await service.setSourceDirectory(next) }
            catch { throw BindingFailure(error: error, context: .source) }
            guard running, generation == token else { return }
            await service.locationResolved()
        } while dirty
    }
}
