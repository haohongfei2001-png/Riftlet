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
    private let url: URL
    private let queue = DispatchQueue(label: "com.riftlet.capture.folder", qos: .utility)
    private let onDirty: @Sendable () -> Void
    private let onLost: @Sendable () -> Void
    private let expectsDirectory: Bool
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var cancelled = false

    init(url: URL, expectsDirectory: Bool = true,
         onDirty: @escaping @Sendable () -> Void, onLost: @escaping @Sendable () -> Void) {
        self.url = url; self.expectsDirectory = expectsDirectory
        self.onDirty = onDirty; self.onLost = onLost
    }

    @discardableResult
    func start() async throws -> OpenedWatch {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OpenedWatch, Error>) in
            queue.async {
                guard !self.cancelled, self.source == nil else {
                    continuation.resume(throwing: CaptureError.io("watcher-already-started", EINVAL)); return
                }
                let fd = Darwin.open(self.url.path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else {
                    continuation.resume(throwing: CaptureError.io("watch-directory", errno)); return
                }
                var info = stat()
                let expectedType = self.expectsDirectory ? S_IFDIR : S_IFREG
                guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(expectedType) else {
                    Darwin.close(fd)
                    continuation.resume(throwing: CaptureError.notRegularFile); return
                }
                let live = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                    eventMask: [.write, .rename, .delete, .revoke, .attrib], queue: self.queue)
                live.setEventHandler { [weak self] in self?.handleEvent() }
                live.setCancelHandler { Darwin.close(fd) }
                self.source = live
                live.resume()
                let identity = WatchedFileIdentity(info, descriptor: fd)
                let localVolume = self.expectsDirectory ? Self.localAPFSVolume(fd, volume: identity.volumeUUID) : nil
                continuation.resume(returning: (identity, localVolume))
            }
        }
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
        pending?.cancel(); pending = nil
        source?.cancel(); source = nil
    }
}
