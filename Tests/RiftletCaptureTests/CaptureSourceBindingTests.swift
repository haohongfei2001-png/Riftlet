import XCTest
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Darwin
@testable import RiftletCapture
import RiftletCore

private final class SourceTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date = Date()) { self.value = value }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ interval: TimeInterval = 1) { lock.lock(); value.addTimeInterval(interval); lock.unlock() }
}

private actor TestLocationProvider: CaptureLocationProviding {
    var directory: URL
    private var handler: (@Sendable () async -> Void)?
    private var retiredHandler: (@Sendable () async -> Void)?
    init(_ directory: URL) { self.directory = directory }
    func currentDirectory() -> URL { directory }
    func start(onChange: @escaping @Sendable () async -> Void) { handler = onChange }
    func stop() { retiredHandler = handler; handler = nil }
    func change(to directory: URL) async { self.directory = directory; await handler?() }
    func lateChange(to directory: URL) async { self.directory = directory; await retiredHandler?() }
}

final class CaptureSourceBindingTests: XCTestCase {
    private struct Fixture: Sendable {
        let root: URL
        let first: URL
        let second: URL
        let privateRoot: URL
        let store: QueueStore
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-source-" + UUID().uuidString)
            first = root.appendingPathComponent("first", isDirectory: true)
            second = root.appendingPathComponent("second", isDirectory: true)
            privateRoot = root.appendingPathComponent("private", isDirectory: true)
            for directory in [first, second, privateRoot] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            store = try QueueStore(databaseURL: privateRoot.appendingPathComponent("queue.sqlite"))
        }
        func close() { try? FileManager.default.removeItem(at: root) }
    }

    private func png() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 12, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func mark(_ url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = data.withUnsafeBytes { setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }
        XCTAssertEqual(result, 0)
    }

    private func preference(_ url: URL, location: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["location": location], format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
    }

    func testInjectedLocationChangeKeepsEarlyArrivalAndIgnoresExistingHistory() async throws {
        let f = try Fixture(); defer { f.close() }
        let historical = f.second.appendingPathComponent("historical.png")
        try png().write(to: historical); try mark(historical)
        let clock = SourceTestClock()
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.first,
                                     now: { clock.read() })
        let provider = TestLocationProvider(f.first)
        let binding = CaptureSourceBinding(service: service, provider: provider)
        try await binding.start()
        // The screenshot reaches the new destination before its change event is delivered.
        let arriving = f.second.appendingPathComponent("early.png")
        try png().write(to: arriving); try mark(arriving)
        clock.advance(10)
        await provider.change(to: f.second)
        clock.advance()
        try await service.rescan()
        await provider.change(to: f.second)
        try await service.rescan()
        let records = try await f.store.assets()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.image.sourceKey, try FileSignature.read(at: arriving).sourceKey)
        let current = await service.currentSourceDirectory()
        XCTAssertEqual(current, f.second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: historical.path))
        await binding.stop()
    }

    func testSameDestinationDoesNotRestartStabilityObservation() async throws {
        let f = try Fixture(); defer { f.close() }
        let clock = SourceTestClock()
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.first,
                                     now: { clock.read() })
        try await service.start()
        let image = f.first.appendingPathComponent("new.png")
        try png().write(to: image); try mark(image)
        try await service.rescan()
        try await service.setSourceDirectory(f.first)
        clock.advance()
        try await service.rescan()
        let records = try await f.store.assets()
        XCTAssertEqual(records.count, 1)
        await service.stop()
    }

    func testIncompleteOldSourceSurvivesSwitchAndProcessRestart() async throws {
        let f = try Fixture(); defer { f.close() }
        let clock = SourceTestClock()
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.first,
                                     now: { clock.read() })
        try await service.start()
        let oldSource = f.first.appendingPathComponent("unfinished.png")
        let bytes = try png()
        try bytes.prefix(bytes.count / 2).write(to: oldSource); try mark(oldSource)
        let sourceKey = try FileSignature.read(at: oldSource).sourceKey
        try await service.rescan()
        try await service.setSourceDirectory(f.second)
        clock.advance()
        try await service.rescan()
        let incomplete = try await f.store.assets()
        XCTAssertTrue(incomplete.isEmpty)
        await service.stop()

        // Finish the same inode after the old watcher has been released.
        let handle = try FileHandle(forWritingTo: oldSource)
        try handle.truncate(atOffset: 0); try handle.write(contentsOf: bytes); try handle.close()
        let restarted = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.second,
                                       now: { clock.read() })
        try await restarted.start()
        clock.advance()
        try await restarted.rescan()
        let recovered = try await f.store.assets()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.image.sourceKey, sourceKey)
        XCTAssertEqual(try Data(contentsOf: oldSource), bytes)
        await restarted.stop()
    }

    func testFailedSwitchPreservesLastWorkingSource() async throws {
        let f = try Fixture(); defer { f.close() }
        let clock = SourceTestClock()
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.first,
                                     now: { clock.read() })
        let provider = TestLocationProvider(f.first)
        let binding = CaptureSourceBinding(service: service, provider: provider)
        try await binding.start()
        await provider.change(to: f.root.appendingPathComponent("absent"))
        let current = await service.currentSourceDirectory()
        XCTAssertEqual(current, f.first)
        let image = f.first.appendingPathComponent("after-failure.png")
        try png().write(to: image); try mark(image)
        try await service.rescan()
        clock.advance()
        try await service.rescan()
        let records = try await f.store.assets()
        XCTAssertEqual(records.count, 1)
        await binding.stop()
    }

    func testLateProviderCallbackCannotRestartStoppedCollector() async throws {
        let f = try Fixture(); defer { f.close() }
        let provider = TestLocationProvider(f.first)
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.first)
        let binding = CaptureSourceBinding(service: service, provider: provider)
        try await binding.start()
        await binding.stop()
        await provider.lateChange(to: f.second)
        let current = await service.currentSourceDirectory()
        XCTAssertEqual(current, f.first)
        let image = f.first.appendingPathComponent("while-stopped.png")
        try png().write(to: image); try mark(image)
        try await service.rescan()
        let records = try await f.store.assets()
        XCTAssertTrue(records.isEmpty)
    }

    func testRestartAtNewDestinationKeepsScreenshotsMadeWhileStopped() async throws {
        let f = try Fixture(); defer { f.close() }
        let service = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.first)
        try await service.start(); await service.stop()
        let image = f.second.appendingPathComponent("offline-new-destination.png")
        try png().write(to: image); try mark(image)
        let clock = SourceTestClock()
        let restarted = CaptureService(store: f.store, privateRoot: f.privateRoot, sourceDirectory: f.second,
                                       now: { clock.read() })
        try await restarted.start()
        clock.advance()
        try await restarted.rescan()
        let records = try await f.store.assets()
        XCTAssertEqual(records.count, 1)
        await restarted.stop()
    }

    func testNativePreferenceReplacementRebindsWithoutManualRefresh() async throws {
        let f = try Fixture(); defer { f.close() }
        let prefs = f.root.appendingPathComponent("preferences.plist")
        try preference(prefs, location: f.first.path)
        let imported = expectation(description: "New-source synthetic screenshot imported after preference file event")
        imported.assertForOverFulfill = false
        let store = f.store
        let service = CaptureService(store: store, privateRoot: f.privateRoot, sourceDirectory: f.first,
            onChange: { if (try? await store.assets().count) == 1 { imported.fulfill() } })
        let provider = SystemCaptureLocationProvider(preferencesFile: prefs, fallbackDirectory: f.first)
        let binding = CaptureSourceBinding(service: service, provider: provider)
        try await binding.start()
        let image = f.second.appendingPathComponent("arrived-before-notification.png")
        try png().write(to: image); try mark(image)
        try preference(prefs, location: f.second.path)
        await fulfillment(of: [imported], timeout: 4)
        let current = await service.currentSourceDirectory()
        XCTAssertEqual(current, f.second)
        await binding.stop()
    }

    func testPreferenceReaderRejectsMalformedOrRelativeLocation() async throws {
        let f = try Fixture(); defer { f.close() }
        let prefs = f.root.appendingPathComponent("preferences.plist")
        let provider = SystemCaptureLocationProvider(preferencesFile: prefs, fallbackDirectory: f.first)
        let fallback = try await provider.currentDirectory()
        XCTAssertEqual(fallback, f.first)
        try preference(prefs, location: "relative/path")
        do { _ = try await provider.currentDirectory(); XCTFail("Relative location must not redirect collection") }
        catch { XCTAssertEqual(error as? CaptureError, .invalidLocationPreference) }
        try Data("incomplete plist".utf8).write(to: prefs)
        do { _ = try await provider.currentDirectory(); XCTFail("Malformed plist must not silently fall back") }
        catch { XCTAssertEqual(error as? CaptureError, .invalidLocationPreference) }
        try preference(prefs, location: f.second.path)
        let restored = try await provider.currentDirectory()
        XCTAssertEqual(restored, f.second)
    }

    func testUnrelatedPreferenceChangeDoesNotNotify() async throws {
        let f = try Fixture(); defer { f.close() }
        let prefs = f.root.appendingPathComponent("preferences.plist")
        try preference(prefs, location: f.first.path)
        let irrelevant = expectation(description: "No callback for a different preference domain")
        irrelevant.isInverted = true
        let provider = SystemCaptureLocationProvider(preferencesFile: prefs, fallbackDirectory: f.first)
        try await provider.start { irrelevant.fulfill() }
        try Data("unrelated".utf8).write(to: f.root.appendingPathComponent("another-domain.plist"), options: .atomic)
        await fulfillment(of: [irrelevant], timeout: 0.25)
        await provider.stop()
    }

    func testPreferenceParentReplacementAndSubsequentCreationRemainObserved() async throws {
        let f = try Fixture(); defer { f.close() }
        let directory = f.root.appendingPathComponent("preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let prefs = directory.appendingPathComponent("screens.plist")
        try preference(prefs, location: f.first.path)
        let changed = expectation(description: "Replacement parent preference observed")
        let removed = expectation(description: "Removed preference observed")
        let recreated = expectation(description: "New preference observed after removal")
        for value in [changed, removed, recreated] { value.assertForOverFulfill = false }
        let fallback = f.root.appendingPathComponent("fallback")
        let provider = SystemCaptureLocationProvider(preferencesFile: prefs, fallbackDirectory: fallback)
        try await provider.start {
            guard let current = try? await provider.currentDirectory() else { return }
            if current == f.second { changed.fulfill() }
            if current == fallback { removed.fulfill() }
            if current == f.privateRoot { recreated.fulfill() }
        }
        try FileManager.default.moveItem(at: directory, to: f.root.appendingPathComponent("old-preferences"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try preference(prefs, location: f.second.path)
        await fulfillment(of: [changed], timeout: 3)
        try FileManager.default.removeItem(at: prefs)
        await fulfillment(of: [removed], timeout: 3)
        try preference(prefs, location: f.privateRoot.path)
        await fulfillment(of: [recreated], timeout: 3)
        await provider.stop()
    }
}
