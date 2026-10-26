// Lifecycle adapted from Sukurini FolderWatcher.swift
// @ c74210f81347a1df4ef407523361e7a45c12ab3e, Copyright 2026 Suhun Han.
// Apache-2.0; see ThirdPartyNotices/Sukurini/{LICENSE,NOTICE}.
// Modified for Riftlet: acknowledged startup, bounded coalescing, no project logger,
// no path logging, and actor-owned source generations / reattachment.
import Foundation
import Darwin

final class FolderWatcher: @unchecked Sendable {
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

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
                continuation.resume()
            }
        }
    }

    func cancel() {
        queue.async { self.cancelOnQueue() }
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
