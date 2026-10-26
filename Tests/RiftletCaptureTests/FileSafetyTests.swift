import Foundation
import Darwin
import XCTest
import RiftletCore
@testable import RiftletCapture

private final class FileReadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Void, Error>?
    func finish(_ result: Result<Void, Error>) { lock.lock(); stored = result; lock.unlock() }
    func value() -> Result<Void, Error>? { lock.lock(); defer { lock.unlock() }; return stored }
}

final class FileSafetyTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-file-safety-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func completedResult(_ result: FileReadResult, fifo: URL) async -> Result<Void, Error>? {
        // A regressed O_RDONLY-only implementation must fail the deadline rather than
        // hang the runner. Retry a bounded rescue window in case the worker was not yet
        // scheduled at the first check. Never await the worker indefinitely on failure.
        for _ in 0..<20 {
            if let completed = result.value() { return completed }
            let writer = Darwin.open(fifo.path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
            if writer >= 0 { Darwin.close(writer) }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return result.value()
    }

    func testRegularFileReadersRejectFIFOWithoutWaitingForWriter() async throws {
        let fifo = root.appendingPathComponent("named-pipe.png")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let readers: [(String, @Sendable (URL) async throws -> Void)] = [
            ("signature", { _ = try FileSignature.read(at: $0) }),
            ("private hash", { _ = try PrivateFiles.hashFile($0) }),
            ("preference", { url in
                let provider = SystemCaptureLocationProvider(preferencesFile: url,
                    fallbackDirectory: url.deletingLastPathComponent())
                _ = try await provider.currentDirectory()
            })
        ]
        for (name, read) in readers {
            let completed = expectation(description: "\(name) rejects a FIFO without a writer")
            let result = FileReadResult()
            Task.detached {
                defer { completed.fulfill() }
                do { try await read(fifo); result.finish(.success(())) }
                catch { result.finish(.failure(error)) }
            }
            await fulfillment(of: [completed], timeout: 2)
            guard let finished = await completedResult(result, fifo: fifo) else {
                XCTFail("Reader did not finish within the bounded rescue window"); continue
            }
            switch finished {
            case .success: XCTFail("A FIFO is not a regular screenshot/preference file")
            case .failure(let error): XCTAssertEqual(error as? CaptureError, .notRegularFile)
            }
        }
    }

    func testNamedPipeCannotBlockCollectorStartOrStop() async throws {
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let fifo = source.appendingPathComponent("screenshot-like.png")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let privateRoot = root.appendingPathComponent("private")
        let store = try QueueStore(databaseURL: privateRoot.appendingPathComponent("queue.sqlite"))
        let service = CaptureService(store: store, privateRoot: privateRoot, sourceDirectory: source)
        let completed = expectation(description: "Collector remains stoppable with an unrelated FIFO")
        let result = FileReadResult()
        Task {
            defer { completed.fulfill() }
            do {
                try await service.start()
                await service.stop()
                result.finish(.success(()))
            } catch { result.finish(.failure(error)) }
        }
        await fulfillment(of: [completed], timeout: 2)
        guard let finished = await completedResult(result, fifo: fifo) else {
            XCTFail("Collector did not finish within the bounded rescue window"); return
        }
        try finished.get()
        let records = try await store.assets()
        XCTAssertTrue(records.isEmpty)
        var metadata = stat()
        XCTAssertEqual(lstat(fifo.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & mode_t(S_IFMT), mode_t(S_IFIFO))
    }
}
