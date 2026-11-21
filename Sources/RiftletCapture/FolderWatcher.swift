// Lifecycle adapted from Sukurini FolderWatcher.swift
// @ c74210f81347a1df4ef407523361e7a45c12ab3e, Copyright 2026 Suhun Han.
// Apache-2.0; see ThirdPartyNotices/Sukurini/{LICENSE,NOTICE}.
// Modified for Riftlet: acknowledged startup, bounded coalescing, no project logger,
// no path logging, and actor-owned source generations / reattachment.
import Foundation
import Darwin

struct WatchedFileIdentity: Codable, Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let birthSeconds: Int
    let birthNanoseconds: Int
    let volumeUUID: UUID?

    init(_ info: stat, descriptor: Int32) {
        device = info.st_dev; inode = info.st_ino
        birthSeconds = info.st_birthtimespec.tv_sec; birthNanoseconds = info.st_birthtimespec.tv_nsec
        volumeUUID = CaptureVolume.identifier(of: descriptor)
    }

    func matches(_ info: stat, descriptor: Int32) -> Bool {
        guard let volumeUUID, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_ino == inode, info.st_birthtimespec.tv_sec == birthSeconds,
              info.st_birthtimespec.tv_nsec == birthNanoseconds else { return false }
        return volumeUUID == CaptureVolume.identifier(of: descriptor)
    }

    func matchesDirectory(_ url: URL) -> Bool {
        let fd = Darwin.open(url.path, O_EVTONLY | O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var info = stat()
        return fstat(fd, &info) == 0 && matches(info, descriptor: fd)
    }
}

final class FolderWatcher: @unchecked Sendable {
    typealias OpenedWatch = (identity: WatchedFileIdentity, localAPFSVolume: UUID?)
    private typealias StartContinuation = CheckedContinuation<OpenedWatch, Error>
    // Read and mutated only on the watch queue, including task cancellation.
    private final class StartAttempt: @unchecked Sendable {
        var waiter: StartContinuation?
        var cancelled = false
    }

    private let url: URL
    private let openFile: @Sendable (URL) -> Int32
    private var opening: StartAttempt?
    private let queue = DispatchQueue(label: "com.riftlet.capture.folder", qos: .utility)
    private let onDirty: @Sendable () -> Void
    private let onLost: @Sendable () -> Void
    private let expectsDirectory: Bool
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var cancelled = false

    init(url: URL, expectsDirectory: Bool = true,
         openFile: @escaping @Sendable (URL) -> Int32 = { Darwin.open($0.path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC) },
         onDirty: @escaping @Sendable () -> Void, onLost: @escaping @Sendable () -> Void) {
        self.url = url; self.expectsDirectory = expectsDirectory; self.openFile = openFile
        self.onDirty = onDirty; self.onLost = onLost
    }

    @discardableResult
    func start() async throws -> OpenedWatch {
        let attempt = StartAttempt()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: StartContinuation) in
                queue.async {
                    guard !attempt.cancelled else { continuation.resume(throwing: CancellationError()); return }
                    guard !self.cancelled, self.source == nil, self.opening == nil else {
                        continuation.resume(throwing: CaptureError.io("watcher-already-started", EINVAL)); return
                    }
                    attempt.waiter = continuation
                    self.opening = attempt
                    self.beginOpen(attempt)
                }
            }
        } onCancel: {
            self.queue.async { self.cancelStartup(attempt) }
        }
    }

    // open can wait for a macOS permission prompt indefinitely. The watch queue
    // must remain available to acknowledge retirement and resume the waiter.
    private func beginOpen(_ attempt: StartAttempt) {
        DispatchQueue.global(qos: .utility).async { [weak self, openFile, url, queue] in
            let fd = openFile(url)
            let error = errno
            queue.async { [weak self] in
                guard let self else {
                    if fd >= 0 { Darwin.close(fd) }
                    return
                }
                self.finishOpen(attempt, fd: fd, error: error)
            }
        }
    }

    private func cancelStartup(_ attempt: StartAttempt) {
        attempt.cancelled = true
        attempt.waiter?.resume(throwing: CancellationError())
        attempt.waiter = nil
        // Keep the pending open reserved until its syscall finishes. An unrelated
        // start task must not start a second open while the prompt is pending.
    }

    private func finishOpen(_ attempt: StartAttempt, fd: Int32, error: Int32) {
        assert(opening === attempt)
        opening = nil
        guard let waiter = attempt.waiter, !cancelled else {
            if fd >= 0 { Darwin.close(fd) }
            return
        }
        attempt.waiter = nil
        guard fd >= 0 else { waiter.resume(throwing: CaptureError.io("watch-directory", error)); return }
        var info = stat()
        let expectedType = expectsDirectory ? S_IFDIR : S_IFREG
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(expectedType) else {
            Darwin.close(fd)
            waiter.resume(throwing: CaptureError.notRegularFile); return
        }
        let live = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .revoke, .attrib], queue: queue)
        live.setEventHandler { [weak self] in self?.handleEvent() }
        live.setCancelHandler { Darwin.close(fd) }
        source = live
        live.resume()
        let identity = WatchedFileIdentity(info, descriptor: fd)
        let localVolume = expectsDirectory ? Self.localAPFSVolume(fd, volume: identity.volumeUUID) : nil
        waiter.resume(returning: (identity, localVolume))
    }

    static func localAPFSVolume(_ descriptor: Int32, volume: UUID?) -> UUID? {
        var filesystem = statfs()
        guard let volume, fstatfs(descriptor, &filesystem) == 0, isLocalAPFS(filesystem) else { return nil }
        return volume
    }

    static func isLocalAPFS(_ filesystem: statfs) -> Bool {
        filesystem.f_flags & UInt32(MNT_LOCAL) != 0 && withUnsafeBytes(of: filesystem.f_fstypename) {
            $0.starts(with: "apfs\0".utf8)
        }
    }

    func cancel() {
        queue.async { self.cancelOnQueue() }
    }

    /// Establishes a retirement boundary after all earlier work on the watch queue. Once
    /// acknowledged, no later dirty callback can be emitted by this watcher.
    func cancelAndWait() async -> Date {
        await withCheckedContinuation { continuation in
            queue.async {
                self.cancelOnQueue()
                continuation.resume(returning: Date())
            }
        }
    }

    deinit { source?.cancel() }

    private func handleEvent() {
        guard !cancelled, let source else { return }
        if !source.data.intersection([.rename, .delete, .revoke]).isEmpty {
            cancelOnQueue()
            onLost()
            return
        }
        // First event starts the window. Later events cannot postpone it indefinitely.
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.cancelled else { return }
            self.pending = nil
            self.onDirty()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + .milliseconds(60), execute: work)
    }

    private func cancelOnQueue() {
        guard !cancelled else { return }
        cancelled = true
        if let opening { cancelStartup(opening) }
        pending?.cancel(); pending = nil
        source?.cancel(); source = nil
    }
}
