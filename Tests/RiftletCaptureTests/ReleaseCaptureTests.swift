import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import RiftletCapture
import RiftletCore

private actor ReleaseDiagnosticLog {
    var values: [CaptureDiagnostic] = []
    func append(_ value: CaptureDiagnostic) { values.append(value) }
}

private final class ReleaseCaptureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance() { lock.lock(); value.addTimeInterval(1); lock.unlock() }
}

private actor DiagnosticReentry {
    private var service: CaptureService?
    private var replacement: URL?
    func configure(service: CaptureService, replacement: URL) { self.service = service; self.replacement = replacement }
    func recoverOnce() async {
        guard let service, let replacement else { return }
        self.service = nil; self.replacement = nil
        await service.stop()
        try? await service.setSourceDirectory(replacement)
    }
}

private actor DiagnosticLocationProvider: CaptureLocationProviding {
    private var directory: URL
    init(_ directory: URL) { self.directory = directory }
    func currentDirectory() -> URL { directory }
    func setDirectory(_ value: URL) { directory = value }
    func start(onChange: @escaping @Sendable () async -> Void) { }
    func stop() { }
}

private actor DiagnosticBindingReentry {
    private var binding: CaptureSourceBinding?
    private var provider: DiagnosticLocationProvider?
    private var replacement: URL?
    func configure(binding: CaptureSourceBinding, provider: DiagnosticLocationProvider, replacement: URL) {
        self.binding = binding; self.provider = provider; self.replacement = replacement
    }
    func recoverOnce() async {
        guard let binding, let provider, let replacement else { return }
        self.binding = nil; self.provider = nil; self.replacement = nil
        await binding.stop()
        await provider.setDirectory(replacement)
        try? await binding.start()
    }
}

/// Uses generated files only. TCC prompts and physical system screenshot capture are
/// deliberately not simulated as passing by these filesystem and ImageIO tests.
final class ReleaseCaptureTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let source: URL
        let privateRoot: URL
        let store: QueueStore
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-release-capture-" + UUID().uuidString)
            source = root.appendingPathComponent("source", isDirectory: true)
            privateRoot = root.appendingPathComponent("private", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)
            store = try QueueStore(databaseURL: privateRoot.appendingPathComponent("queue.sqlite"))
        }
        func close() { try? FileManager.default.removeItem(at: root) }
        func files(_ area: String) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: privateRoot.appendingPathComponent(area), includingPropertiesForKeys: nil)
        }
    }

    private func image(_ url: URL, type: UTType = .png, orientation: Int = 1) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8,
            bytesPerRow: 0, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 20))
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(context.makeImage()),
                                  [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
    }

    private func mark(_ url: URL, screenshot: Bool = true) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: screenshot, format: .binary, options: 0)
        XCTAssertEqual(data.withUnsafeBytes { setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }, 0)
    }

    private func importNow(_ importer: PrivateAssetImporter, _ url: URL) async throws -> AssetRecord {
        try await importer.importStableFile(at: url, signature: FileSignature.read(at: url), firstSeenAt: Date())
    }

    func testDiagnosticClassificationSeparatesSourceStorageFormatAndSizeWithoutPrivateDetails() {
        let cases: [(Error, CaptureDiagnosticContext, CaptureDiagnosticCode)] = [
            (CaptureError.io("open-source", EACCES), .privateStorage, .sourceUnavailable),
            (CaptureError.io("write-private-data", EACCES), .source, .privateWriteFailed),
            (CaptureError.io("inspect-private-copy", EACCES), .source, .privateWriteFailed),
            (CaptureError.io("stat-private-copy", EIO), .source, .privateWriteFailed),
            (CaptureError.io("open-source", EACCES), .locationPreference, .sourcePreferenceUnreadable),
            (CaptureError.io("write-private-data", ENOSPC), .source, .insufficientStorage),
            (CaptureError.io("write-private-data", EDQUOT), .privateStorage, .insufficientStorage),
            (CaptureError.invalidLocationPreference, .source, .sourcePreferenceUnreadable),
            (CaptureError.unsupportedImage, .privateStorage, .unsupportedFormat),
            (CaptureError.imageTooLarge, .privateStorage, .imageTooLarge),
            (CaptureError.invalidManifest, .privateStorage, .recoveryRequired),
            (RiftletError.database("private path must not appear"), .source, .privateWriteFailed)
        ]
        for (error, context, expected) in cases {
            let diagnostic = CaptureDiagnostic.classify(error, context: context)
            XCTAssertEqual(diagnostic.code, expected)
            XCTAssertFalse(diagnostic.userMessage.contains("private path must not appear"))
        }
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)),
                       NSFilePathErrorKey: "/private/real-screenshot-name.png"])
        let diagnostic = CaptureDiagnostic.classify(wrapped, context: .privateStorage)
        XCTAssertEqual(diagnostic.code, .insufficientStorage)
        XCTAssertFalse(diagnostic.userMessage.contains("real-screenshot-name"))
    }

    func testUnknownCapacityIsNotReportedAsProvenLowSpace() {
        let diagnostic = CaptureDiagnostic.classify(CaptureError.io("read-private-capacity", EIO), context: .privateStorage)
        XCTAssertEqual(diagnostic.code, .privateWriteFailed)
        XCTAssertNotEqual(diagnostic.code, .insufficientStorage)
        XCTAssertThrowsError(try PrivateStorageCapacity.require(availableBytes: PrivateStorageCapacity.metadataHeadroom + 99,
                                                               copyBytes: 100)) {
            XCTAssertEqual($0 as? CaptureError, .insufficientStorage)
        }
        XCTAssertNoThrow(try PrivateStorageCapacity.require(availableBytes: PrivateStorageCapacity.metadataHeadroom + 100,
                                                            copyBytes: 100))
    }

    func testDeniedPreferenceParentNeverFallsBackToDesktopAndRecoversAfterAccessReturns() async throws {
        guard geteuid() != 0 else { throw XCTSkip("Controlled POSIX denial requires an unprivileged macOS test user; this is not a TCC test") }
        let f = try Fixture(); defer { f.close() }
        let parent = f.root.appendingPathComponent("preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let preference = parent.appendingPathComponent("com.apple.screencapture.plist")
        try PropertyListSerialization.data(fromPropertyList: ["location": f.source.path], format: .binary, options: 0).write(to: preference)
        let fallback = f.root.appendingPathComponent("fallback")
        let provider = SystemCaptureLocationProvider(preferencesFile: preference, fallbackDirectory: fallback)
        XCTAssertEqual(chmod(parent.path, 0), 0)
        defer { _ = chmod(parent.path, 0o700) }
        do { _ = try await provider.currentDirectory(); XCTFail("Denied preferences must not silently select a different source") }
        catch { XCTAssertEqual(CaptureDiagnostic.classify(error, context: .locationPreference).code, .sourcePreferenceUnreadable) }
        XCTAssertEqual(chmod(parent.path, 0o700), 0)
        let recovered = try await provider.currentDirectory()
        XCTAssertEqual(recovered, f.source.standardizedFileURL)
    }

    func testLowSpaceRefusesBeforeCopyWithoutMarkingSeenAndRecoversOnExplicitRetry() async throws {
        let f = try Fixture(); defer { f.close() }
        let url = f.source.appendingPathComponent("generated.png")
        try image(url); try mark(url)
        let original = try Data(contentsOf: url)
        let limited = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store, capacityCheck: { _, bytes in
            XCTAssertGreaterThan(bytes, 0)
            throw CaptureError.insufficientStorage
        })
        do { _ = try await importNow(limited, url); XCTFail("Capacity guard must stop new copying") }
        catch { XCTAssertEqual(error as? CaptureError, .insufficientStorage) }
        XCTAssertTrue(try f.files("media").isEmpty)
        XCTAssertTrue(try f.files("staging").isEmpty)
        XCTAssertTrue(try f.files("journal").isEmpty)
        let before = try await f.store.assets(includeUsed: true)
        XCTAssertTrue(before.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
        let normal = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        let record = try await importNow(normal, url)
        XCTAssertEqual(try Data(contentsOf: f.privateRoot.appendingPathComponent("media").appendingPathComponent(record.image.fileName)), original)
        let after = try await f.store.assets(includeUsed: true)
        XCTAssertEqual(after.count, 1)
    }

    func testExistingDurableJournalRecoveryBypassesFreshCopyCapacityGuard() async throws {
        let f = try Fixture(); defer { f.close() }
        let url = f.source.appendingPathComponent("generated.png")
        try image(url); try mark(url)
        let interrupted = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store, fault: { context in
            if context.boundary == .journalSynced { throw SimulatedImportInterruption(boundary: .journalSynced) }
        })
        do { _ = try await importNow(interrupted, url); XCTFail("Leave journal ownership before promotion") }
        catch is SimulatedImportInterruption { }
        let journal = try XCTUnwrap(f.files("journal").first)
        let limited = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store, capacityCheck: { _, _ in
            XCTFail("Recovery of already copied bytes must not require fresh-copy capacity")
            throw CaptureError.insufficientStorage
        })
        let report = try await limited.recover()
        XCTAssertEqual(report.adopted, 1)
        let record = try await importNow(limited, url)
        XCTAssertEqual(try f.files("journal"), [journal])
        XCTAssertEqual(try f.files("media").count, 1)
        XCTAssertEqual(try Data(contentsOf: f.privateRoot.appendingPathComponent("media").appendingPathComponent(record.image.fileName)),
                       try Data(contentsOf: url))
    }

    func testPNGJPEGAndTIFFPreserveExactBytesColorProfileAndEncodedDimensions() async throws {
        for type in [UTType.png, UTType.jpeg, UTType.tiff] {
            let f = try Fixture(); defer { f.close() }
            let url = f.source.appendingPathComponent("generated." + (type.preferredFilenameExtension ?? "image"))
            try image(url, type: type); try mark(url)
            let original = try Data(contentsOf: url)
            let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
            let record = try await importNow(importer, url)
            let media = f.privateRoot.appendingPathComponent("media").appendingPathComponent(record.image.fileName)
            XCTAssertEqual(try Data(contentsOf: media), original)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertEqual(record.image.pixelWidth, 40)
            XCTAssertEqual(record.image.pixelHeight, 20)
            XCTAssertEqual(record.image.mediaType, type.preferredMIMEType)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(media as CFURL, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertNotNil(decoded.colorSpace)
            let sourceImage = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let originalDecoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(sourceImage, 0, nil))
            let decodedName = decoded.colorSpace?.name.map { $0 as String }
            let originalName = originalDecoded.colorSpace?.name.map { $0 as String }
            XCTAssertEqual(decodedName, originalName)
        }
    }

    func testHEICPreservesOriginalBytesWhenSystemEncoderIsAvailable() async throws {
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard supported.contains(UTType.heic.identifier) else { throw XCTSkip("This macOS runner has no HEIC encoder; hardware format acceptance remains open") }
        let f = try Fixture(); defer { f.close() }
        let url = f.source.appendingPathComponent("generated.heic")
        try image(url, type: .heic); try mark(url)
        let original = try Data(contentsOf: url)
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        let record = try await importNow(importer, url)
        XCTAssertEqual(try Data(contentsOf: f.privateRoot.appendingPathComponent("media").appendingPathComponent(record.image.fileName)), original)
        XCTAssertEqual(record.image.pixelWidth, 40)
        XCTAssertEqual(record.image.pixelHeight, 20)
        XCTAssertEqual(record.image.mediaType, "image/heic")
    }

    func testJPEGOrientationRetainsRawIdentityAndTransformedPreview() async throws {
        let f = try Fixture(); defer { f.close() }
        let url = f.source.appendingPathComponent("rotated.jpg")
        try image(url, type: .jpeg, orientation: 6); try mark(url)
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        let record = try await importNow(importer, url)
        XCTAssertEqual(record.image.pixelWidth, 40)
        XCTAssertEqual(record.image.pixelHeight, 20)
        let media = f.privateRoot.appendingPathComponent("media").appendingPathComponent(record.image.fileName)
        XCTAssertEqual(try Data(contentsOf: media), try Data(contentsOf: url))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(media as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 6)
        let thumbnail = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 40
        ] as CFDictionary))
        XCTAssertEqual(thumbnail.width, 20)
        XCTAssertEqual(thumbnail.height, 40)
        let recovery = try await importer.recover()
        XCTAssertTrue(recovery.invalid.isEmpty)
        XCTAssertTrue(recovery.missing.isEmpty)
    }

    func testPDFAndMultiPageTIFFAreRejectedWithoutChangingOriginals() async throws {
        let f = try Fixture(); defer { f.close() }
        let pdf = f.source.appendingPathComponent("document.pdf")
        let bytes = Data("%PDF-1.7\nSynthetic unsupported screenshot document\n%%EOF".utf8)
        try bytes.write(to: pdf); try mark(pdf)
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        do { _ = try await importNow(importer, pdf); XCTFail("PDF is unsupported, not a permanently incomplete raster") }
        catch { XCTAssertEqual(error as? CaptureError, .unsupportedImage) }
        XCTAssertEqual(try Data(contentsOf: pdf), bytes)
        let single = f.source.appendingPathComponent("single.tiff")
        try image(single, type: .tiff)
        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(single as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded, 0, nil))
        let multi = f.source.appendingPathComponent("multi.tiff")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(multi as CFURL, UTType.tiff.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, cg, nil)
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try mark(multi)
        let original = try Data(contentsOf: multi)
        do { _ = try await importNow(importer, multi); XCTFail("Multiple pages cannot become one asset") }
        catch { XCTAssertEqual(error as? CaptureError, .unsupportedImage) }
        XCTAssertEqual(try Data(contentsOf: multi), original)
        let records = try await f.store.assets(includeUsed: true)
        XCTAssertTrue(records.isEmpty)
    }

    func testOversizedOrdinaryFileIsNotMislabeledAsUnsupportedScreenshot() async throws {
        let f = try Fixture(); defer { f.close() }
        let url = f.source.appendingPathComponent("ordinary.png")
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        XCTAssertEqual(ftruncate(descriptor, ValidatedImage.maximumBytes + 1), 0)
        Darwin.close(descriptor)
        try mark(url, screenshot: false)
        let importer = PrivateAssetImporter(privateRoot: f.privateRoot, store: f.store)
        do { _ = try await importNow(importer, url); XCTFail("Ordinary files never get screenshot-format diagnostics") }
        catch { XCTAssertEqual(error as? CaptureError, .notScreenshot) }
        try mark(url)
        do { _ = try await importNow(importer, url); XCTFail("A positively identified oversized screenshot is reported") }
        catch { XCTAssertEqual(error as? CaptureError, .imageTooLarge) }
        XCTAssertEqual(try FileSignature.read(at: url).size, ValidatedImage.maximumBytes + 1)
    }

    func testSourceSnapshotAndExplicitRecheckRecoverMissingFolderWithoutNewScreenshot() async throws {
        let f = try Fixture(); defer { f.close() }
        let missing = f.root.appendingPathComponent("missing", isDirectory: true)
        let log = ReleaseDiagnosticLog()
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: missing,
                                     onDiagnostic: { await log.append($0) })
        do { try await service.start(); XCTFail("Missing source cannot be active") } catch { }
        let failure = await service.statusSnapshot()
        XCTAssertFalse(failure.isRunning)
        XCTAssertFalse(failure.sourceAccessible)
        XCTAssertEqual(failure.latestDiagnostic?.code, .sourceUnavailable)
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        try await service.recheck()
        let recovered = await service.statusSnapshot()
        XCTAssertTrue(recovered.isRunning)
        XCTAssertTrue(recovered.sourceAccessible)
        XCTAssertNil(recovered.latestDiagnostic)
        XCTAssertEqual(recovered.sourceDirectory, missing.standardizedFileURL)
        let diagnostics = await log.values
        XCTAssertEqual(diagnostics.map(\.code), [.sourceUnavailable])
        await service.stop()
        let stopped = await service.statusSnapshot()
        XCTAssertFalse(stopped.isRunning)
    }

    func testDiagnosticCallbackCannotLetAnOldFailedStartStopNewCaptureGeneration() async throws {
        let f = try Fixture(); defer { f.close() }
        let reentry = DiagnosticReentry()
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot,
            sourceDirectory: f.root.appendingPathComponent("missing"),
            onDiagnostic: { _ in await reentry.recoverOnce() })
        await reentry.configure(service: service, replacement: f.source)
        do { try await service.start(); XCTFail("The old attempt still reports its original missing-directory failure") }
        catch { }
        let replacement = await service.statusSnapshot()
        XCTAssertEqual(replacement.sourceDirectory, f.source.standardizedFileURL)
        XCTAssertTrue(replacement.isRunning)
        XCTAssertTrue(replacement.sourceAccessible)
        XCTAssertNil(replacement.latestDiagnostic)
        await service.stop()
    }

    func testBindingDiagnosticCallbackCannotStopItsReplacementGeneration() async throws {
        let f = try Fixture(); defer { f.close() }
        let missing = f.root.appendingPathComponent("missing")
        let provider = DiagnosticLocationProvider(missing)
        let reentry = DiagnosticBindingReentry()
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: missing)
        let binding = CaptureSourceBinding(service: service, provider: provider,
                                           onDiagnostic: { _ in await reentry.recoverOnce() })
        await reentry.configure(binding: binding, provider: provider, replacement: f.source)
        do { try await binding.start(); XCTFail("Original binding must still throw its original failure") }
        catch { }
        let snapshot = await service.statusSnapshot()
        XCTAssertTrue(snapshot.isRunning)
        XCTAssertTrue(snapshot.sourceAccessible)
        XCTAssertEqual(snapshot.sourceDirectory, f.source.standardizedFileURL)
        XCTAssertNil(snapshot.latestDiagnostic)
        await binding.stop()
    }

    func testOldSourceRecheckCannotClearFailedNewLocationUntilSwitchActuallySucceeds() async throws {
        let f = try Fixture(); defer { f.close() }
        let missing = f.root.appendingPathComponent("next", isDirectory: true)
        let provider = DiagnosticLocationProvider(f.source)
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.source)
        let binding = CaptureSourceBinding(service: service, provider: provider)
        try await binding.start()
        await provider.setDirectory(missing)
        await binding.refresh()
        try await service.recheck()
        let oldStillActive = await service.statusSnapshot()
        XCTAssertTrue(oldStillActive.isRunning)
        XCTAssertTrue(oldStillActive.sourceAccessible)
        XCTAssertEqual(oldStillActive.sourceDirectory, f.source.standardizedFileURL)
        XCTAssertEqual(oldStillActive.latestDiagnostic?.code, .sourceUnavailable,
                       "A readable old source does not prove the requested location works")
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        await binding.refresh()
        let switched = await service.statusSnapshot()
        XCTAssertEqual(switched.sourceDirectory, missing.standardizedFileURL)
        XCTAssertTrue(switched.sourceAccessible)
        XCTAssertNil(switched.latestDiagnostic)
        await binding.stop()
    }

    func testOnlyMarkedNewUnsupportedFilesProduceFormatDiagnostic() async throws {
        let f = try Fixture(); defer { f.close() }
        let clock = ReleaseCaptureClock()
        let log = ReleaseDiagnosticLog()
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.source,
                                     onDiagnostic: { await log.append($0) }, now: { clock.read() })
        try await service.start()
        let ordinary = f.source.appendingPathComponent("ordinary.pdf")
        let screenshot = f.source.appendingPathComponent("screenshot.pdf")
        let bytes = Data("%PDF-1.7\nSynthetic unsupported document\n%%EOF".utf8)
        try bytes.write(to: ordinary); try mark(ordinary, screenshot: false)
        try await service.rescan()
        clock.advance()
        try await service.rescan()
        let ordinaryDiagnostics = await log.values
        XCTAssertTrue(ordinaryDiagnostics.isEmpty)
        try bytes.write(to: screenshot); try mark(screenshot)
        try await service.rescan()
        clock.advance()
        try await service.rescan()
        let snapshot = await service.statusSnapshot()
        XCTAssertTrue(snapshot.sourceAccessible)
        XCTAssertEqual(snapshot.latestDiagnostic?.code, .unsupportedFormat)
        let diagnostics = await log.values
        XCTAssertFalse(diagnostics.isEmpty)
        XCTAssertTrue(diagnostics.allSatisfy { $0.code == .unsupportedFormat },
                      "Real filesystem bursts may repeat the category; unrelated documents must not produce another diagnosis")
        let records = try await f.store.assets(includeUsed: true)
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: ordinary), bytes)
        XCTAssertEqual(try Data(contentsOf: screenshot), bytes)
        await service.stop()
    }
}
