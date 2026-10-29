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
    private let executableURL: URL
    private let onProcessStarted: (() -> Void)?

    init(executableURL: URL = InteractiveScreenshotCommand.executable,
         onProcessStarted: (() -> Void)? = nil) {
        self.executableURL = executableURL
        self.onProcessStarted = onProcessStarted
    }

    func capture(_ request: InteractiveScreenshotRequest, outputDirectory: URL) async throws -> InteractiveScreenshotFile {
        try Task.checkCancellation()
        let output = try InteractiveScreenshotOwnedOutput.reserve(in: outputDirectory, requestID: request.id)
        defer { output.removeOwnedEmptyEntries() }
        let arguments = try InteractiveScreenshotCommand.arguments(for: request, outputURL: output.stagedURL)
        try output.requireCurrentDirectories()
        try await run(arguments: arguments)
        try Task.checkCancellation()
        let reader = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            // Keep durable publication and original-byte validation off AppKit.
            // No existing destination is ever replaced by this operation.
            let published = try output.publishWithoutReplacing()
            let result = try Self.readOriginal(at: published.url, expectedSignature: published.signature)
            try output.requireCurrentDirectories()
            return result
        }
        let result = try await withTaskCancellationHandler(operation: {
            try await reader.value
        }, onCancel: { reader.cancel() })
        try Task.checkCancellation()
        return result
    }

    func cancel() {
        guard var current = job else { return }
        current.cancelled = true; job = current
        if current.process.isRunning { current.process.terminate() }
        timeout?.cancel()
        let cancelledID = current.id, cancelledProcess = current.process
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            guard self?.job?.id == cancelledID, cancelledProcess.isRunning else { return }
            Darwin.kill(cancelledProcess.processIdentifier, SIGKILL)
        }
    }

    private func run(arguments: [String]) async throws {
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
                process.terminationHandler = { [weak self] terminated in
                    let status = terminated.terminationStatus
                    Task { @MainActor [weak self] in self?.finish(id: id, status: status) }
                }
                job = Job(id: id, process: process, continuation: continuation)
                do { try process.run(); onProcessStarted?() }
                catch {
                    job = nil; process.terminationHandler = nil
                    continuation.resume(throwing: InteractiveScreenshotError.captureToolUnavailable)
                    return
                }
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                    guard let self, var current = self.job, current.id == id, current.process.isRunning else { return }
                    current.timedOut = true; self.job = current
                    if current.process.isRunning { current.process.terminate() }
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
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
        current.process.terminationHandler = nil
        if current.cancelled { current.continuation.resume(throwing: CancellationError()) }
        else if current.timedOut { current.continuation.resume(throwing: InteractiveScreenshotError.captureTimedOut) }
        else if status != 0 { current.continuation.resume(throwing: InteractiveScreenshotError.captureFailed(status)) }
        else { current.continuation.resume() }
    }

    nonisolated static func removeEmptyReservation(directoryDescriptor: Int32, name: String,
                                                  signature: FileSignature?) {
        guard let signature, signature.size == 0,
              (try? screenshotSignature(directoryDescriptor: directoryDescriptor, name: name)) == signature else { return }
        _ = unlinkat(directoryDescriptor, name, 0)
    }

    /// Descriptor-based validation preserves original bytes and never sets screenshot metadata.
    nonisolated static func readOriginal(at url: URL, expectedSignature: FileSignature? = nil) throws -> InteractiveScreenshotFile {
        try Task.checkCancellation()
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw InteractiveScreenshotError.invalidOutput }
        defer { Darwin.close(descriptor) }
        let signature: FileSignature
        do { signature = try FileSignature.read(descriptor: descriptor) }
        catch { throw InteractiveScreenshotError.invalidOutput }
        if let expectedSignature, signature != expectedSignature { throw InteractiveScreenshotError.invalidOutput }
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

private func screenshotSignature(directoryDescriptor: Int32, name: String) throws -> FileSignature {
    let descriptor = openat(directoryDescriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw InteractiveScreenshotError.invalidOutput }
    defer { Darwin.close(descriptor) }
    return try FileSignature.read(descriptor: descriptor)
}

private struct ScreenshotDirectoryIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
    let birthSeconds: Int64
    let birthNanoseconds: Int64

    init(_ value: stat) throws {
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), value.st_uid == geteuid(),
              value.st_mode & 0o777 == 0o700 else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        device = UInt64(value.st_dev); inode = UInt64(value.st_ino)
        birthSeconds = Int64(value.st_birthtimespec.tv_sec)
        birthNanoseconds = Int64(value.st_birthtimespec.tv_nsec)
    }

    static func read(descriptor: Int32) throws -> Self {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        return try Self(value)
    }
}

/// A single capture owns these descriptors until its awaited reader finishes.
/// Creation and cleanup are serial with publishing; the unchecked conformance
/// only transfers that exclusive ownership into the detached storage task.
private final class InteractiveScreenshotOwnedOutput: @unchecked Sendable {
    let stagedURL: URL
    private let directoryURL: URL
    private let directoryDescriptor: Int32
    private let directoryIdentity: ScreenshotDirectoryIdentity
    private let stageName: String
    private let stageDescriptor: Int32
    private let stageIdentity: ScreenshotDirectoryIdentity
    private let filename: String
    private let finalName: String
    private let reservation: FileSignature

    private init(directoryURL: URL, directoryDescriptor: Int32, directoryIdentity: ScreenshotDirectoryIdentity,
                 stageName: String, stageDescriptor: Int32, stageIdentity: ScreenshotDirectoryIdentity,
                 filename: String, finalName: String, reservation: FileSignature) {
        self.directoryURL = directoryURL; self.directoryDescriptor = directoryDescriptor
        self.directoryIdentity = directoryIdentity; self.stageName = stageName
        self.stageDescriptor = stageDescriptor; self.stageIdentity = stageIdentity
        self.filename = filename; self.finalName = finalName; self.reservation = reservation
        stagedURL = directoryURL.appendingPathComponent(stageName, isDirectory: true).appendingPathComponent(filename)
    }

    deinit { Darwin.close(stageDescriptor); Darwin.close(directoryDescriptor) }

    static func reserve(in requestedDirectory: URL, requestID: UUID) throws -> InteractiveScreenshotOwnedOutput {
        guard requestedDirectory.isFileURL else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        let directory = requestedDirectory.standardizedFileURL
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { throw InteractiveScreenshotError.unsafeOutputDirectory }
        let rootFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        var transferred = false
        defer { if !transferred { Darwin.close(rootFD) } }
        var rootStat = stat()
        guard fstat(rootFD, &rootStat) == 0, rootStat.st_uid == geteuid(), fchmod(rootFD, 0o700) == 0 else {
            throw InteractiveScreenshotError.unsafeOutputDirectory
        }
        let rootIdentity = try ScreenshotDirectoryIdentity.read(descriptor: rootFD)
        let filename = requestID.uuidString.lowercased() + ".png", finalName = "." + filename
        var existing = stat()
        guard fstatat(rootFD, finalName, &existing, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            throw InteractiveScreenshotError.unsafeOutputDirectory
        }
        // Apple's tool is given an ordinary filename. A fresh hidden directory
        // isolates the entire write from the independent, nonrecursive system
        // collector, including while markup has not yet imported the capture.
        let stageName = ".capture-" + UUID().uuidString.lowercased()
        guard mkdirat(rootFD, stageName, 0o700) == 0 else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        let stageFD = openat(rootFD, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stageFD >= 0 else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        defer { if !transferred { Darwin.close(stageFD) } }
        let stageIdentity = try ScreenshotDirectoryIdentity.read(descriptor: stageFD)
        var reservation: FileSignature?
        defer {
            if !transferred {
                InteractiveScreenshotSystemCapture.removeEmptyReservation(directoryDescriptor: stageFD,
                                                                          name: filename, signature: reservation)
                var current = stat()
                if fstatat(rootFD, stageName, &current, AT_SYMLINK_NOFOLLOW) == 0,
                   (try? ScreenshotDirectoryIdentity(current)) == stageIdentity {
                    _ = unlinkat(rootFD, stageName, AT_REMOVEDIR)
                }
            }
        }
        let descriptor = openat(stageFD, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw InteractiveScreenshotError.unsafeOutputDirectory }
        defer { Darwin.close(descriptor) }
        let signature = try FileSignature.read(descriptor: descriptor)
        reservation = signature
        let output = InteractiveScreenshotOwnedOutput(directoryURL: directory, directoryDescriptor: rootFD,
            directoryIdentity: rootIdentity, stageName: stageName, stageDescriptor: stageFD,
            stageIdentity: stageIdentity, filename: filename, finalName: finalName, reservation: signature)
        transferred = true
        do { try output.requireCurrentDirectories() }
        catch { output.removeOwnedEmptyEntries(); throw error }
        return output
    }

    func requireCurrentDirectories() throws {
        var root = stat(), stage = stat()
        guard lstat(directoryURL.path, &root) == 0,
              (try? ScreenshotDirectoryIdentity(root)) == directoryIdentity,
              fstatat(directoryDescriptor, stageName, &stage, AT_SYMLINK_NOFOLLOW) == 0,
              (try? ScreenshotDirectoryIdentity(stage)) == stageIdentity else {
            throw InteractiveScreenshotError.unsafeOutputDirectory
        }
    }

    func publishWithoutReplacing() throws -> (url: URL, signature: FileSignature) {
        try Task.checkCancellation()
        try requireCurrentDirectories()
        let descriptor = openat(stageDescriptor, filename, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw InteractiveScreenshotError.invalidOutput }
        defer { Darwin.close(descriptor) }
        let signature: FileSignature
        do { signature = try FileSignature.read(descriptor: descriptor) }
        catch { throw InteractiveScreenshotError.invalidOutput }
        var info = stat()
        guard signature.size <= ValidatedImage.maximumBytes else { throw InteractiveScreenshotError.imageTooLarge }
        guard signature.size > 0, fstat(descriptor, &info) == 0, info.st_uid == geteuid(),
              fchmod(descriptor, 0o600) == 0, fsync(descriptor) == 0,
              (try? FileSignature.read(descriptor: descriptor)) == signature,
              (try? screenshotSignature(directoryDescriptor: stageDescriptor, name: filename)) == signature else {
            throw InteractiveScreenshotError.invalidOutput
        }
        try Task.checkCancellation()
        try requireCurrentDirectories()
        // linkat never replaces a destination. The directory descriptors prevent
        // a swapped pathname from redirecting publication or stage-file removal.
        guard linkat(stageDescriptor, filename, directoryDescriptor, finalName, 0) == 0 else {
            throw InteractiveScreenshotError.unsafeOutputDirectory
        }
        // A hard link changes ctime/nlink, neither of which is in FileSignature.
        // Compare inode/device/birth/mtime/size before removing the owned name.
        guard (try? screenshotSignature(directoryDescriptor: directoryDescriptor, name: finalName)) == signature,
              (try? screenshotSignature(directoryDescriptor: stageDescriptor, name: filename)) == signature,
              (try? FileSignature.read(descriptor: descriptor)) == signature,
              fsync(directoryDescriptor) == 0 else { throw InteractiveScreenshotError.invalidOutput }
        try requireCurrentDirectories()
        // A flush can yield time to external file operations. Recheck both
        // directory entries after it, before removing this capture's stage name.
        guard (try? screenshotSignature(directoryDescriptor: directoryDescriptor, name: finalName)) == signature,
              (try? screenshotSignature(directoryDescriptor: stageDescriptor, name: filename)) == signature,
              (try? FileSignature.read(descriptor: descriptor)) == signature else {
            throw InteractiveScreenshotError.invalidOutput
        }
        guard unlinkat(stageDescriptor, filename, 0) == 0 else { throw InteractiveScreenshotError.invalidOutput }
        guard (try? screenshotSignature(directoryDescriptor: directoryDescriptor, name: finalName)) == signature else {
            throw InteractiveScreenshotError.invalidOutput
        }
        try requireCurrentDirectories()
        return (directoryURL.appendingPathComponent(finalName), signature)
    }

    func removeOwnedEmptyEntries() {
        // Never search for another tool-generated name, recursively remove a
        // directory, or delete a nonempty output after cancellation/failure.
        InteractiveScreenshotSystemCapture.removeEmptyReservation(directoryDescriptor: stageDescriptor,
                                                                  name: filename, signature: reservation)
        guard (try? requireCurrentDirectories()) != nil else { return }
        _ = unlinkat(directoryDescriptor, stageName, AT_REMOVEDIR)
    }
}
