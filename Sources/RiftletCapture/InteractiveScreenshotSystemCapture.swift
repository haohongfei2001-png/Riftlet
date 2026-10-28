import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin

@MainActor
protocol InteractiveScreenshotPermissionChecking: AnyObject {
    func hasAccess() -> Bool
    func requestAccess() -> Bool
}

@MainActor
final class InteractiveScreenshotPermission: InteractiveScreenshotPermissionChecking {
    func hasAccess() -> Bool { CGPreflightScreenCaptureAccess() }
    func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }
}

struct InteractiveScreenshotFile: Sendable {
    let sourceURL: URL
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let hasSystemScreenshotMetadata: Bool
}

@MainActor
protocol InteractiveScreenshotCapturing: AnyObject {
    func capture(_ request: InteractiveScreenshotRequest, outputDirectory: URL) async throws -> InteractiveScreenshotFile
    func cancel()
}

/// No shell, interactive system capture, image conversion or manufactured xattr.
/// `screencapture -h` is checked separately on macOS CI; those public tool flags
/// are consumed directly, with one already selected window ID or rectangle.
@MainActor
final class InteractiveScreenshotSystemCapture: InteractiveScreenshotCapturing {
    private struct Job {
        let id: UUID
        let process: Process
        let continuation: CheckedContinuation<Void, Error>
        var cancelled = false
        var timedOut = false
    }
    private var job: Job?
    private var timeout: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private let executableURL: URL
    private let timeoutNanoseconds: UInt64
    private let cancellationGraceNanoseconds: UInt64
    private let terminationDeliveryDelayNanoseconds: UInt64
    var hasRunningProcess: Bool { job?.process.isRunning == true }

    init(executableURL: URL = InteractiveScreenshotCommand.executable,
         timeoutNanoseconds: UInt64 = 30_000_000_000,
         cancellationGraceNanoseconds: UInt64 = 1_000_000_000,
         terminationDeliveryDelayNanoseconds: UInt64 = 0) {
        self.executableURL = executableURL
        self.timeoutNanoseconds = timeoutNanoseconds
        self.cancellationGraceNanoseconds = cancellationGraceNanoseconds
        self.terminationDeliveryDelayNanoseconds = terminationDeliveryDelayNanoseconds
    }

    func capture(_ request: InteractiveScreenshotRequest, outputDirectory: URL) async throws -> InteractiveScreenshotFile {
        try Task.checkCancellation()
        try Self.prepareDirectory(outputDirectory)
        let outputURL = outputDirectory.appendingPathComponent(request.id.uuidString.lowercased() + ".png")
        let arguments = try InteractiveScreenshotCommand.arguments(for: request, outputURL: outputURL)
        // Reserve a private, new name; never overwrite a previous original capture.
        let descriptor = Darwin.open(outputURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        let reservation = try? FileSignature.read(descriptor: descriptor)
        Darwin.close(descriptor)
        do {
            try await run(arguments: arguments)
            try Task.checkCancellation()
            let reader = Task.detached(priority: .userInitiated) {
                try Self.readOriginal(at: outputURL)
            }
            let result = try await withTaskCancellationHandler(operation: {
                try await reader.value
            }, onCancel: { reader.cancel() })
            try Task.checkCancellation()
            try Self.validatePixelDimensions(result, for: request)
            return result
        } catch {
            // Only remove our unchanged, empty reservation. A nonempty original
            // (including one completed during cancellation) is always retained.
            Self.removeEmptyReservation(at: outputURL, signature: reservation)
            throw error
        }
    }

    func cancel() {
        guard var current = job, !current.cancelled else { return }
        current.cancelled = true; job = current
        if current.process.isRunning { current.process.terminate() }
        timeout?.cancel()
        let cancelledID = current.id, cancelledProcess = current.process
        let grace = cancellationGraceNanoseconds
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: grace) } catch { return }
            guard self?.job?.id == cancelledID, cancelledProcess.isRunning else { return }
            Darwin.kill(cancelledProcess.processIdentifier, SIGKILL)
        }
    }

    /// Internal seam also permits process-lifetime regression tests to execute a
    /// harmless fixture process. Production always uses Apple's fixed executable.
    func run(arguments: [String]) async throws {
        if let previous = job {
            guard previous.cancelled || previous.timedOut else {
                throw InteractiveScreenshotError.captureFailed(-1)
            }
            // Cancel followed immediately by re-enable must not fail merely
            // because the old owned child has not delivered termination yet.
            await withCheckedContinuation { idleWaiters.append($0) }
        }
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard job == nil else { continuation.resume(throwing: InteractiveScreenshotError.captureFailed(-1)); return }
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                let deliveryDelay = terminationDeliveryDelayNanoseconds
                process.terminationHandler = { [weak self] terminated in
                    let status = terminated.terminationStatus
                    Task { @MainActor [weak self] in
                        // Zero in production; the internal test seam reproduces
                        // a delayed actor delivery after a real child has exited.
                        if deliveryDelay > 0 { try? await Task.sleep(nanoseconds: deliveryDelay) }
                        self?.finish(id: id, status: status)
                    }
                }
                job = Job(id: id, process: process, continuation: continuation)
                do { try process.run() }
                catch {
                    job = nil; process.terminationHandler = nil
                    continuation.resume(throwing: InteractiveScreenshotError.captureToolUnavailable)
                    return
                }
                let limit = timeoutNanoseconds, grace = cancellationGraceNanoseconds
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: limit) } catch { return }
                    guard let self, var current = self.job, current.id == id,
                          current.process.isRunning else { return }
                    current.timedOut = true; self.job = current
                    if current.process.isRunning { current.process.terminate() }
                    do { try await Task.sleep(nanoseconds: grace) } catch { return }
                    if self.job?.id == id, current.process.isRunning {
                        // This is exclusively our still-running child process.
                        Darwin.kill(current.process.processIdentifier, SIGKILL)
                    }
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.job?.id == id else { return }
                self?.cancel()
            }
        })
    }

    private func finish(id: UUID, status: Int32) {
        guard let current = job, current.id == id else { return }
        timeout?.cancel(); timeout = nil; job = nil
        let waiters = idleWaiters; idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
        current.process.terminationHandler = nil
        if current.cancelled { current.continuation.resume(throwing: CancellationError()) }
        else if current.timedOut { current.continuation.resume(throwing: InteractiveScreenshotError.captureTimedOut) }
        else if status != 0 { current.continuation.resume(throwing: InteractiveScreenshotError.captureFailed(status)) }
        else { current.continuation.resume() }
    }

    nonisolated static func removeEmptyReservation(at url: URL, signature: FileSignature?) {
        guard let signature, signature.size == 0,
              (try? FileSignature.read(at: url)) == signature else { return }
        _ = unlink(url.path)
    }

    /// Enforce the frozen single-display native-scale contract without resizing
    /// or rewriting the output. A returned mismatch is retained for diagnosis,
    /// never silently admitted as the requested capture. Mixed-display output
    /// and window shadows need separate empirical contracts and are not inferred.
    nonisolated static func validatePixelDimensions(_ file: InteractiveScreenshotFile,
                                                    for request: InteractiveScreenshotRequest) throws {
        guard request.mode != .window, request.target.displays.count == 1,
              let display = request.target.displays.first,
              display.frame.contains(request.target.rect),
              display.quartzFrame.contains(request.target.quartzRect) else { return }
        let width = request.target.quartzRect.width * display.scale
        let height = request.target.quartzRect.height * display.scale
        guard display.scale.isFinite, display.scale > 0,
              width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 50_000, height <= 50_000,
              width == width.rounded(), height == height.rounded(),
              file.pixelWidth == Int(width), file.pixelHeight == Int(height) else {
            throw InteractiveScreenshotError.unexpectedPixelDimensions
        }
    }

    private static func prepareDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                  info.st_uid == geteuid() else { throw InteractiveScreenshotError.unsafeOutputDirectory }
            guard chmod(url.path, 0o700) == 0 else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        } catch { throw InteractiveScreenshotError.unsafeOutputDirectory }
    }

    /// Descriptor-based validation preserves original bytes and never sets screenshot metadata.
    nonisolated static func readOriginal(at url: URL) throws -> InteractiveScreenshotFile {
        try Task.checkCancellation()
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw InteractiveScreenshotError.invalidOutput }
        defer { Darwin.close(descriptor) }
        let signature: FileSignature
        do { signature = try FileSignature.read(descriptor: descriptor) }
        catch { throw InteractiveScreenshotError.invalidOutput }
        guard signature.size > 0 else { throw InteractiveScreenshotError.invalidOutput }
        guard signature.size <= ValidatedImage.maximumBytes else { throw InteractiveScreenshotError.imageTooLarge }
        guard fchmod(descriptor, 0o600) == 0 else { throw InteractiveScreenshotError.invalidOutput }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try file.readToEnd(), Int64(data.count) == signature.size,
              (try? FileSignature.read(descriptor: descriptor)) == signature else {
            throw InteractiveScreenshotError.invalidOutput
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let typeID = CGImageSourceGetType(source), typeID as String == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw InteractiveScreenshotError.invalidOutput }
        guard width <= 50_000, height <= 50_000,
              Int64(width) * Int64(height) <= ValidatedImage.maximumPixels else {
            throw InteractiveScreenshotError.imageTooLarge
        }
        let thumbnail: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceShouldCacheImmediately: true]
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) != nil else {
            throw InteractiveScreenshotError.invalidOutput
        }
        let marker = (try? CaptureSource.isScreenshot(descriptor: descriptor)) == true
        try Task.checkCancellation()
        guard (try? FileSignature.read(at: url)) == signature else { throw InteractiveScreenshotError.invalidOutput }
        return InteractiveScreenshotFile(sourceURL: url, data: data, pixelWidth: width,
                                         pixelHeight: height, hasSystemScreenshotMetadata: marker)
    }
}
