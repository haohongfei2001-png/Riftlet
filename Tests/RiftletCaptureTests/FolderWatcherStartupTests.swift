import Darwin
import Foundation
@testable import RiftletCapture
#if !RIFTLET_STANDALONE_WATCH_CHECK
import XCTest
#endif

private enum WatchCheckError: Error { case timedOut, wrongOutcome }
private final class OpenProbe: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var entered = false, finished = false
    private var descriptor: Int32 = -1
    private var callbacks = 0
    var state: (entered: Bool, finished: Bool, fd: Int32, callbacks: Int) {
        lock.withLock { (entered, finished, descriptor, callbacks) }
    }
    func dirty() { lock.withLock { callbacks += 1 } }
    func completed() { lock.withLock { finished = true } }
    func open(_ url: URL, succeeds: Bool) -> Int32 {
        let initial = Darwin.open(url.path, O_EVTONLY | O_DIRECTORY | O_CLOEXEC)
        let fd = initial >= 0 ? fcntl(initial, F_DUPFD_CLOEXEC, 192) : -1
        if initial >= 0 { Darwin.close(initial) }
        lock.withLock { entered = true; descriptor = fd }
        release.wait()
        if succeeds { return fd }
        if fd >= 0 { Darwin.close(fd) }
        errno = EACCES
        return -1
    }
}

private func eventually(_ condition: () -> Bool) async throws {
    let deadline = DispatchTime.now() + .seconds(3)
    while !condition() {
        guard DispatchTime.now() < deadline else { throw WatchCheckError.timedOut }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

private func delayedOpen(_ directory: URL, cancelTask: Bool, succeeds: Bool) async throws {
    let probe = OpenProbe()
    let watcher = FolderWatcher(url: directory, openFile: { probe.open($0, succeeds: succeeds) },
                                onDirty: { probe.dirty() }, onLost: { probe.dirty() })
    let start = Task {
        defer { probe.completed() }
        return try await watcher.start()
    }
    // Unblock the worker even on a failing assertion/timeout.
    defer { probe.release.signal(); watcher.cancel() }
    try await eventually { probe.state.entered }
    guard probe.state.fd >= 0 else { throw WatchCheckError.wrongOutcome }

    // A cancelled concurrent caller must not retire the first caller's attempt.
    let duplicate = Task { try await watcher.start() }
    duplicate.cancel()
    guard (try? await duplicate.value) == nil, !probe.state.finished else { throw WatchCheckError.wrongOutcome }
    if cancelTask { start.cancel() } else { watcher.cancel() }
    try await eventually { probe.state.finished }
    do { _ = try await start.value; throw WatchCheckError.wrongOutcome }
    catch is CancellationError {}

    // The retirement acknowledgement must precede release of the blocked syscall.
    let ack = OpenProbe()
    let retired = Task { _ = await watcher.cancelAndWait(); ack.completed() }
    try await eventually { ack.state.finished }
    await retired.value
    probe.release.signal()
    try await eventually { fcntl(probe.state.fd, F_GETFD) == -1 && errno == EBADF }
    try Data([42]).write(to: directory.appendingPathComponent(UUID().uuidString))
    try await Task.sleep(nanoseconds: 120_000_000)
    guard probe.state.callbacks == 0 else { throw WatchCheckError.wrongOutcome }
}

private func checkStartup() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try await delayedOpen(root,cancelTask: true,succeeds: true)
    try await delayedOpen(root,cancelTask: true,succeeds: false)
    try await delayedOpen(root,cancelTask: false,succeeds: true)
    let probe = OpenProbe()
    let watcher = FolderWatcher(url:root,onDirty:{probe.dirty()},onLost:{probe.dirty()})
    let opened = try await watcher.start()
    guard opened.identity.matchesDirectory(root) else { throw WatchCheckError.wrongOutcome }
    try Data([1]).write(to:root.appendingPathComponent("normal"))
    try await eventually { probe.state.callbacks > 0 }
    _ = await watcher.cancelAndWait()
    let n = probe.state.callbacks
    try Data([2]).write(to:root.appendingPathComponent("retired"))
    try await Task.sleep(nanoseconds:120_000_000)
    guard probe.state.callbacks == n else { throw WatchCheckError.wrongOutcome }
}

#if RIFTLET_STANDALONE_WATCH_CHECK
@main struct FolderWatcherStartupCheck {
    static func main() async throws {
        try await checkStartup()
        print("PASS: blocked open cancellation, late fd/error, watch retirement, normal start and event")
    }
}
#else
final class FolderWatcherStartupTests: XCTestCase {
    func testBlockedOpenDoesNotHoldAwaiterOrRetirement() async throws { try await checkStartup() }
}
#endif
