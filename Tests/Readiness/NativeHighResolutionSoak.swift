import AppKit
import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import RiftletCore
@testable import RiftletCapture
@testable import RiftletUI

private enum SoakFailure: Error { case failed(String) }
private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw SoakFailure.failed(message) }
}
private func value<T>(_ optional: T?, _ message: String) throws -> T {
    guard let optional else { throw SoakFailure.failed(message) }
    return optional
}
private func uptime() -> Double { ProcessInfo.processInfo.systemUptime }
private func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

/// Only this probe's collector callback writes here. No UI or browser is present.
private final class ImportObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var starts: [String: Double] = [:]
    private var imported: [UUID: Double] = [:]
    private var samples: [Double] = []
    private var issues: [String] = []
    func expect(key: String, start: Double) { lock.lock(); starts[key] = start; lock.unlock() }
    func receive(_ record: AssetRecord, _ observation: ScreenshotSourceObservation) {
        lock.lock(); defer { lock.unlock() }
        if imported[record.id] == nil, let start = starts[record.image.sourceKey] {
            samples.append((observation.readyUptime - start) * 1_000)
        }
        imported[record.id] = observation.readyUptime
    }
    func issue(_ message: String) { lock.lock(); issues.append(message); lock.unlock() }
    func snapshot() -> (count: Int, samples: [Double], issues: [String]) {
        lock.lock(); defer { lock.unlock() }; return (imported.count, samples, issues)
    }
}

@MainActor private final class CallbackResult<T> {
    private var continuation: CheckedContinuation<T, Error>?
    private var deadline: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<T, Error>, timeout: Double, label: String) {
        self.continuation = continuation
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish(.failure(SoakFailure.failed(label + " timed out")))
        }
    }
    func finish(_ result: Result<T, Error>) {
        guard let continuation else { return }
        self.continuation = nil; deadline?.cancel(); deadline = nil
        continuation.resume(with: result)
    }
}

private struct Fixture {
    let name: String, width: Int, height: Int, data: Data, sha256: String
}

@MainActor private final class HighResolutionSoak {
    private let root: URL
    private let source: URL
    private let storage: URL
    private let captures: Int
    private let seconds: Double
    private let interval: Double
    private let observations = ImportObservations()
    private let began = uptime()
    private var metrics: [String: [Double]] = [:]
    private var resources: [[String: Any]] = []
    private var cases: [[String: Any]] = []
    private var previews: [[String: Any]] = []
    private var originals: [String: (URL, Fixture)] = [:]
    private var fixtures: [Fixture] = []
    private var store: QueueStore!
    private var collector: CaptureService!
    private var unknown: AssetRecord?
    private var unknownOperation: TransferOperation?
    private var unknownReason: String?
    private var fileIndex = 0
    private var reservedOriginalBytes: UInt64 = 0
    private var maintenanceSeconds: Double = 0
    private let dataBudget: UInt64 = 2 * 1_024 * 1_024 * 1_024

    init(root: URL, captures: Int, seconds: Double, interval: Double) throws {
        self.root = root; source = root.appendingPathComponent("source")
        storage = root.appendingPathComponent("private")
        self.captures = captures; self.seconds = seconds; self.interval = interval
        let prefix = "riftlet-hires-"
        try require(root.isFileURL && root.lastPathComponent.hasPrefix(prefix) &&
            UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
            "Evidence root must be a fresh riftlet-hires-UUID directory")
        let parent = root.deletingLastPathComponent()
        try require(parent.standardizedFileURL == parent.resolvingSymlinksInPath(), "Symlink parent rejected")
        try require(Darwin.mkdir(root.path, 0o700) == 0, "Evidence root already exists or cannot be created")
        for name in ["source", "private", "fixtures"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        try writeJSON(["schema": 1, "kind": "synthetic-high-resolution-readiness", "uuid": String(root.lastPathComponent.dropFirst(prefix.count)),
                       "createdUTC": ISO8601DateFormatter().string(from: Date()), "productionDataAccess": false], "root-marker.json")
    }

    func run() async throws {
        do {
            try sampleResources("before-fixture-generation")
            for (name, width, height) in [("landscape-4k", 3840, 2160), ("portrait-4k", 2160, 3840),
                                          ("ultrawide", 5120, 1440), ("landscape-8k", 7680, 4320)] {
                let start = uptime()
                let data = try autoreleasepool { try makePattern(width: width, height: height) }
                try require(data.count <= 32 * 1_024 * 1_024, "Synthetic PNG unexpectedly large")
                let fixture = Fixture(name: name, width: width, height: height, data: data, sha256: digest(data))
                fixtures.append(fixture)
                try data.write(to: root.appendingPathComponent("fixtures/" + name + ".png"))
                add("fixture_generation", (uptime() - start) * 1_000)
                try sampleResources("generated-" + name)
            }
            store = try QueueStore(databaseURL: storage.appendingPathComponent("queue.sqlite"))
            collector = makeCollector(store: store)
            try await collector.start()
            for offset in stride(from: 0, to: captures, by: 10) {
                if offset > 0 { _ = try await store.clearVisibleQueue() }
                try await importBatch(count: min(10, captures - offset))
                if offset == 0 { try await makeUnknown() }
                try require(try await store.assets().count <= 10, "Visible queue exceeded this test's ten-item fixture")
            }
            try await establishTenVisible()
            try require(try await store.assets(includeUsed: true).count == captures, "Initial history count mismatch")
            let historyStart = uptime()
            var pageIDs = [UUID]()
            for offset in stride(from: 0, to: captures, by: 40) {
                pageIDs += try await store.historySnapshot(limit: 40, offset: offset).map { $0.record.id }
            }
            add("history_all_pages_40", (uptime() - historyStart) * 1_000)
            try require(Set(pageIDs).count == captures && pageIDs.count == captures, "History pagination lost or duplicated an ID")
            pass("initial-history-and-ten-visible", ["historyCount": captures, "visibleCount": 10])
            try await verifyDedupe()
            try await benchmarkImages()
            try await reopenPreservingUnknown()
            try await stoppedArrivalRecovery()
            try await establishTenVisible()
            try await unavailablePrivateFileRoundTrip()
            try await maintenance()
            await collector.stop()
            try await verifyIntegrity()
            try sampleResources("finished")
            try saveReport(result: "PASS_SCOPED_HIGH_RESOLUTION_READINESS", failure: nil)
        } catch {
            if let collector { await collector.stop() }
            try? sampleResources("failed")
            try? saveReport(result: "FAIL_SCOPED_HIGH_RESOLUTION_READINESS", failure: String(describing: error))
            throw error
        }
    }

    private func makeCollector(store: QueueStore) -> CaptureService {
        let log = observations
        return CaptureService(store: store, privateRoot: storage, sourceDirectory: source,
            onImported: { log.receive($0, $1) }, onIssue: { log.issue($0) })
    }

    private func makePattern(width: Int, height: Int) throws -> Data {
        let context = try value(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), "Cannot create pattern context")
        context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for row in 0..<64 {
            let y = row * height / 64
            let color = CGFloat((row * 17) % 90) / 100
            context.setFillColor(CGColor(red: 0.08 + color / 3, green: 0.3 + color / 3, blue: 0.4 + color / 4, alpha: 1))
            context.fill(CGRect(x: width / 24, y: y, width: width * (12 + row % 9) / 24, height: max(2, height / 240)))
        }
        for column in 0..<16 {
            context.setStrokeColor(CGColor(red: 0.1, green: 0.6, blue: 0.5, alpha: 1))
            context.setLineWidth(CGFloat(max(1, width / 1920)))
            context.stroke(CGRect(x: column * width / 16, y: height / 3, width: width / 20, height: height / 4))
        }
        let bytes = NSMutableData()
        let destination = try value(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil), "Cannot encode fixture")
        CGImageDestinationAddImage(destination, try value(context.makeImage(), "Cannot make fixture image"), nil)
        try require(CGImageDestinationFinalize(destination), "PNG encode failed")
        return bytes as Data
    }

    private func writeNext() throws {
        let fixture = fixtures[fileIndex % fixtures.count]
        // Reserve enough logical bytes for original + durable private copy.
        let current = try dataBytes()
        let fixtureBytes = fixtures.reduce(UInt64(0)) { $0 + UInt64($1.data.count) }
        let projected = fixtureBytes + (reservedOriginalBytes + UInt64(fixture.data.count)) * 2 + 64 * 1_024 * 1_024
        try require(current < dataBudget && projected < dataBudget, "2 GiB synthetic data budget reached")
        let url = source.appendingPathComponent(String(format: "synthetic-%04d.png", fileIndex))
        let start = uptime()
        try fixture.data.write(to: url, options: .withoutOverwriting)
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = marker.withUnsafeBytes { setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }
        try require(result == 0, "Cannot mark synthetic screenshot fixture")
        let signature = try FileSignature.read(at: url)
        observations.expect(key: signature.sourceKey, start: start)
        originals[signature.sourceKey] = (url, fixture)
        reservedOriginalBytes += UInt64(fixture.data.count)
        fileIndex += 1
    }

    private func importBatch(count: Int) async throws {
        let expected = fileIndex + count
        let start = uptime()
        for _ in 0..<count { try writeNext() }
        try await awaitImported(expected: expected)
        add("batch_first_write_to_durable_callbacks", (uptime() - start) * 1_000)
    }

    private func awaitImported(expected: Int) async throws {
        let deadline = uptime() + 45
        while uptime() < deadline {
            let count = try await store.assets(includeUsed: true).count
            if count == expected && observations.snapshot().count == expected { return }
            try require(count <= expected, "Unexpected duplicate asset")
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw SoakFailure.failed("Collector did not durably import the expected synthetic batch within 45 s")
    }

    private func makeUnknown() async throws {
        let record = try value(try await store.assets().first, "Missing first synthetic asset")
        let target = TargetLease(adapterID: "high-resolution-readiness", surface: .webChat,
            applicationID: "isolated.synthetic", sessionID: "session", windowID: "window", tabID: "tab",
            documentID: "doc", composerID: "composer", draftGeneration: "draft")
        let operation = try await store.prepare(assetID: record.id, target: target)
        try await store.markDispatchIntent(operation.id)
        try await store.markUnknown(operation.id, reason: "Isolated high-resolution recovery fixture; no external input occurred")
        _ = try await store.clearVisibleQueue()
        unknown = try await store.asset(id: record.id)
        unknownOperation = try await store.operation(id: operation.id)
        unknownReason = try await store.operationReason(for: operation.id)
        try require(unknown?.status == .unknown && unknownOperation?.phase == .unknown, "UNKNOWN fixture not created")
    }

    private func establishTenVisible() async throws {
        let all = try await store.assets(includeUsed: true)
        let desired = Set(all.filter { $0.status == .pending }.suffix(10).map(\.id))
        try require(desired.count == 10, "Insufficient pending synthetic records for queue")
        for record in all where record.visibility == .visible && !desired.contains(record.id) {
            try await store.removeFromQueue(record.id)
        }
        for record in all where desired.contains(record.id) && record.visibility != .visible {
            try await store.restoreToQueue(record.id)
        }
        let start = uptime()
        let visible = try await store.assets()
        add("queue_read_ten", (uptime() - start) * 1_000)
        try require(Set(visible.map(\.id)) == desired, "Visible queue did not preserve exact requested IDs")
    }

    private func verifyDedupe() async throws {
        let before = try await store.assets(includeUsed: true)
        for record in before {
            let original = try value(originals[record.image.sourceKey], "Missing original mapping")
            let start = uptime()
            let duplicate = try await collector.importer.importStableFile(at: original.0,
                signature: FileSignature.read(at: original.0), firstSeenAt: record.image.firstSeenAt)
            add("same_source_dedupe", (uptime() - start) * 1_000)
            try require(duplicate.id == record.id, "Importer duplicated a known source")
        }
        try require(try await store.assets(includeUsed: true) == before, "Dedupe mutated existing records")
        pass("real-importer-deduplication", ["records": before.count])
    }

    private func thumbnail(_ cache: ThumbnailCache, _ asset: ImportedAsset) async throws -> (CGImage, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            let reply = CallbackResult<(CGImage, Bool)>(continuation, timeout: 15, label: "ThumbnailCache")
            var returned = false
            cache.image(for: asset, maxPixelSize: 128) { image in
                if let image { reply.finish(.success((image, !returned))) }
                else { reply.finish(.failure(SoakFailure.failed("ThumbnailCache returned no pixels"))) }
            }
            returned = true
        }
    }

    private func preview(_ loader: HistoryPreviewLoader, _ asset: ImportedAsset,
                         viewport: CGSize, backing: CGFloat) async throws -> HistoryPreviewImage {
        let owner = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let reply = CallbackResult<HistoryPreviewImage>(continuation, timeout: 30, label: "HistoryPreviewLoader")
            loader.request(owner: owner, request: .init(asset: asset,
                directory: storage.appendingPathComponent("media"), viewport: viewport, backing: backing),
                invalidated: { reply.finish(.failure(SoakFailure.failed("Unexpected preview owner invalidation"))) },
                completion: { reply.finish($0) })
        }
    }

    private func benchmarkImages() async throws {
        let visible = try await store.assets()
        let cache = ThumbnailCache(directory: storage.appendingPathComponent("media"))
        var immediateWarmHits = 0
        for record in visible {
            let coldStart = uptime(); let cold = try await thumbnail(cache, record.image)
            add("thumbnail_app_cache_cold_128px", (uptime() - coldStart) * 1_000)
            try require(max(cold.0.width, cold.0.height) <= 128, "Thumbnail exceeds requested display dimensions")
            let warmStart = uptime(); let warm = try await thumbnail(cache, record.image)
            add("thumbnail_app_cache_warm_128px", (uptime() - warmStart) * 1_000)
            if warm.1 && cold.0 === warm.0 { immediateWarmHits += 1 }
        }
        pass("actual-thumbnail-cache", ["coldRequests": visible.count, "warmRequests": visible.count,
            "synchronousSameImageWarmHits": immediateWarmHits, "OSFileCacheControlled": false])
        let all = try await store.assets(includeUsed: true)
        let loader = HistoryPreviewLoader()
        for fixture in fixtures {
            let asset = try value(all.first { $0.image.pixelWidth == fixture.width && $0.image.pixelHeight == fixture.height }?.image,
                                  "Missing representative high-resolution asset")
            for (label, viewport, backing) in [("fit-retina", CGSize(width: 960, height: 684), CGFloat(2)),
                                                ("large-viewport-budget", CGSize(width: 10_000, height: 10_000), CGFloat(2))] {
                let start = uptime(); let loaded = try await preview(loader, asset, viewport: viewport, backing: backing)
                let elapsed = (uptime() - start) * 1_000
                add("history_preview_" + label, elapsed)
                let decodedBytes = loaded.image.bytesPerRow * loaded.image.height
                try require(HistoryPreviewPlan.accepts(loaded.image), "Actual preview violates pixel/byte budget")
                try require(loaded.identity.matches(loaded.url), "Actual preview identity is stale")
                previews.append(["fixture": fixture.name, "request": label, "elapsedMS": elapsed,
                    "sourceWidth": fixture.width, "sourceHeight": fixture.height,
                    "decodedWidth": loaded.image.width, "decodedHeight": loaded.image.height,
                    "decodedBytes": decodedBytes, "maximumDecodedBytes": HistoryPreviewPlan.maximumBytes,
                    "maximumDecodedPixels": HistoryPreviewPlan.maximumPixels])
                try sampleResources("decoded-" + fixture.name + "-" + label)
            }
        }
        pass("actual-history-preview-budget", ["requests": previews.count])
    }

    private func reopenPreservingUnknown() async throws {
        let before = try await store.assets(includeUsed: true)
        await collector.stop(); collector = nil; store = nil
        let start = uptime()
        store = try QueueStore(databaseURL: storage.appendingPathComponent("queue.sqlite"))
        try await store.recoverInterruptedOperations()
        collector = makeCollector(store: store)
        try await collector.start()
        add("store_and_collector_reopen", (uptime() - start) * 1_000)
        try require(try await store.assets(includeUsed: true) == before, "Reopening changed prior full asset records")
        try await checkUnknown()
        pass("store-reopen-full-records-and-unknown", ["records": before.count, "processRestart": false])
    }

    private func checkUnknown() async throws {
        let old = try value(unknown, "Missing UNKNOWN baseline")
        let operation = try value(unknownOperation, "Missing UNKNOWN operation baseline")
        try require(try await store.asset(id: old.id) == old, "UNKNOWN asset row changed")
        try require(try await store.operation(id: operation.id) == operation, "UNKNOWN operation row changed")
        try require(try await store.operationReason(for: operation.id) == unknownReason, "UNKNOWN reason changed")
        try require(try await store.uploadStartReceipt(for: operation.id) == nil, "Synthetic test invented upload START")
    }

    private func stoppedArrivalRecovery() async throws {
        await collector.stop()
        let before = try await store.assets(includeUsed: true).count
        for _ in 0..<4 { try writeNext() }
        // This is an explicit fixed negative observation, not proof of every possible delay.
        let start = uptime(); try await Task.sleep(nanoseconds: 400_000_000)
        try require(try await store.assets(includeUsed: true).count == before, "Stopped collector imported a new fixture")
        let observationSeconds = uptime() - start
        try await collector.start(); try await awaitImported(expected: fileIndex)
        try await checkUnknown()
        pass("stopped-arrivals-recovered", ["negativeObservationSeconds": observationSeconds, "newFixtures": 4])
    }

    private func unavailablePrivateFileRoundTrip() async throws {
        await collector.stop()
        let record = try value(try await store.assets().first, "No availability fixture")
        let original = storage.appendingPathComponent("media/" + record.image.fileName)
        let held = root.appendingPathComponent("temporarily-unavailable.png")
        try FileManager.default.moveItem(at: original, to: held)
        do {
            let loader = HistoryPreviewLoader()
            do {
                _ = try await preview(loader, record.image, viewport: CGSize(width: 640, height: 480), backing: 2)
                throw SoakFailure.failed("Missing private file unexpectedly decoded")
            } catch HistoryPreviewFailure.invalidFile {
                // A missing file must fail its identity check, not return other pixels.
            }
            try FileManager.default.moveItem(at: held, to: original)
            _ = try await preview(loader, record.image, viewport: CGSize(width: 640, height: 480), backing: 2)
        } catch {
            if FileManager.default.fileExists(atPath: held.path) { try FileManager.default.moveItem(at: held, to: original) }
            throw error
        }
        try await collector.start()
        pass("temporary-private-file-unavailability", ["originalBytesRestored": true, "scope": "Only owned synthetic media; collector stopped during reversible rename"])
    }

    private func maintenance() async throws {
        let start = uptime(), end = start + seconds
        var nextCapture = start + interval, nextResource = start
        var cycles = 0
        while uptime() < end {
            let now = uptime()
            if now >= nextCapture {
                _ = try await store.clearVisibleQueue()
                try await importBatch(count: 4)
                try await establishTenVisible()
                let historyStart = uptime()
                let page = try await store.historySnapshot(limit: 40)
                add("history_page_40_during_soak", (uptime() - historyStart) * 1_000)
                try require(page.count == min(40, fileIndex), "History page size changed")
                if cycles % 5 == 4 {
                    try await benchmarkImages()
                    try await reopenPreservingUnknown()
                }
                cycles += 1; nextCapture += interval
            }
            if now >= nextResource { try sampleResources("maintenance"); nextResource += 30 }
            let left = min(1, max(0, end - uptime()))
            if left > 0 { try await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
        }
        maintenanceSeconds = uptime() - start
        try require(maintenanceSeconds >= seconds, "Duration shortened")
        pass("bounded-maintenance-duration", ["requestedSeconds": seconds, "actualSeconds": maintenanceSeconds,
            "cycles": cycles, "cycleIntervalSeconds": interval, "scope": "Live collector, periodic high-resolution files, native store/cache/decode; no App windows or browser"])
    }

    private func verifyIntegrity() async throws {
        let all = try await store.assets(includeUsed: true)
        try require(all.count == fileIndex && Set(all.map(\.image.sourceKey)).count == fileIndex, "Final assets/source-key count mismatch")
        try await checkUnknown()
        for record in all {
            let original = try value(originals[record.image.sourceKey], "Missing source mapping")
            let sourceBytes = try Data(contentsOf: original.0)
            let mediaBytes = try Data(contentsOf: storage.appendingPathComponent("media/" + record.image.fileName))
            try require(digest(sourceBytes) == original.1.sha256 && digest(mediaBytes) == original.1.sha256, "Original/private pixels changed")
            try require(record.image.byteCount == mediaBytes.count && record.image.pixelWidth == original.1.width &&
                        record.image.pixelHeight == original.1.height, "Durable metadata differs from original fixture")
        }
        try require(observations.snapshot().issues.isEmpty, "CaptureService reported an unexpected issue")
        let usage = try PrivateStorageUsage.measure(privateRoot: storage)
        try require(usage.isComplete, "Private storage accounting incomplete")
        try require(try dataBytes() < dataBudget, "Synthetic data exceeded 2 GiB")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(all).write(to: root.appendingPathComponent("final-assets.json"))
        try encoder.encode(unknownOperation).write(to: root.appendingPathComponent("unknown-operation.json"))
        try encoder.encode(usage).write(to: root.appendingPathComponent("storage-usage.json"))
        pass("all-originals-media-and-unknown-preserved", ["assets": all.count, "mediaVerified": all.count,
            "syntheticUnknownOperations": 1, "uploadStarts": 0, "syntheticDataLogicalBytes": try dataBytes()])
    }

    private func dataBytes() throws -> UInt64 {
        var total: UInt64 = 0
        for directory in [source, storage, root.appendingPathComponent("fixtures")] {
            let iterator = try value(FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), "Cannot account synthetic files")
            for case let url as URL in iterator {
                let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                try require(properties.isSymbolicLink != true, "Unexpected symlink in owned fixture tree")
                if properties.isRegularFile == true { total += UInt64(properties.fileSize ?? 0) }
            }
        }
        return total
    }

    private func sampleResources(_ phase: String) throws {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        var usage = rusage()
        try require(status == KERN_SUCCESS && getrusage(RUSAGE_SELF, &usage) == 0, "Cannot read own process resources")
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let sample: [String: Any] = ["phase": phase, "elapsedSeconds": uptime() - began,
            "processCPUSeconds": cpu, "residentBytes": info.resident_size, "peakResidentBytes": usage.ru_maxrss,
            "syntheticDataLogicalBytes": try dataBytes(), "capturesWritten": fileIndex]
        resources.append(sample)
        let data = try JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys])
        let url = root.appendingPathComponent("resources.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10]))
        print("HIRES_RESOURCE " + String(decoding: data, as: UTF8.self))
        fflush(stdout)
    }

    private func add(_ name: String, _ milliseconds: Double) { metrics[name, default: []].append(milliseconds) }
    private func pass(_ name: String, _ details: [String: Any]) { cases.append(["name": name, "result": "PASS", "details": details]) }
    private func writeJSON(_ object: Any, _ name: String) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent(name), options: .atomic)
    }
    private func saveReport(result: String, failure: String?) throws {
        metrics["file_write_to_durable_import_callback"] = observations.snapshot().samples
        let summaries = metrics.mapValues { values -> [String: Any] in
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return ["samples": 0, "unit": "ms"] }
            return ["samples": sorted.count, "unit": "ms", "p50": sorted[sorted.count / 2],
                "p95": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], "maximum": sorted.last!, "values": values]
        }
        let firstCPU = resources.first?["processCPUSeconds"] as? Double ?? 0
        let finalCPU = resources.last?["processCPUSeconds"] as? Double ?? firstCPU
        let elapsed = uptime() - began
        try writeJSON(["schema": 1, "result": result, "completed": result.hasPrefix("PASS"),
            "pid": ProcessInfo.processInfo.processIdentifier,
            "failure": failure as Any? ?? NSNull(), "startedUptime": began, "actualRunSeconds": elapsed,
            "requestedMaintenanceSeconds": seconds, "actualMaintenanceSeconds": maintenanceSeconds,
            "initialHistoryCount": captures, "finalCaptureCount": fileIndex,
            "processCPUSecondsDelta": finalCPU - firstCPU,
            "cpuPercentOneCoreOverRun": (finalCPU - firstCPU) / max(0.001, elapsed) * 100,
            "fixtures": fixtures.map { ["name": $0.name, "width": $0.width, "height": $0.height, "encodedBytes": $0.data.count, "sha256": $0.sha256] as [String: Any] },
            "cases": cases, "metrics": summaries, "previewDecodes": previews, "resources": resources,
            "captureIssues": observations.snapshot().issues,
            "scope": ["syntheticFixtures": true, "realCollectorImporterSQLiteImageIO": true,
                "appWindowsCreated": false, "browserOrNetwork": false, "productionDataAccess": false,
                "OSFileCacheControlled": false, "UIVisibleLatencyMeasured": false,
                "processRestartMeasured": false, "sleepWakeMeasured": false,
                "noClaim": "These are native data/cache/decode timings, not rendered UI, physical screenshot or upload timings. Database reopen is not process restart. Sources are bounded patterns, not adversarial image noise."]], "report.json")
    }
}

@main private struct HighResolutionRunner {
    private static func verifyRestart(_ root: URL) async throws {
        let prefix = "riftlet-hires-"
        try require(root.lastPathComponent.hasPrefix(prefix) &&
            UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil &&
            root.standardizedFileURL == root.resolvingSymlinksInPath(), "Restart root is not an owned fixture directory")
        let marker = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("root-marker.json"))) as? [String: Any]
        try require(marker?["kind"] as? String == "synthetic-high-resolution-readiness" &&
            marker?["uuid"] as? String == String(root.lastPathComponent.dropFirst(prefix.count)), "Restart marker mismatch")
        let output = root.appendingPathComponent("restart-report.json")
        try require(!FileManager.default.fileExists(atPath: output.path), "Never overwrite restart evidence")
        let before = try JSONDecoder().decode([AssetRecord].self, from: Data(contentsOf: root.appendingPathComponent("final-assets.json")))
        let oldOperation = try JSONDecoder().decode(TransferOperation.self, from: Data(contentsOf: root.appendingPathComponent("unknown-operation.json")))
        let storage = root.appendingPathComponent("private")
        let store = try QueueStore(databaseURL: storage.appendingPathComponent("queue.sqlite"))
        let started = uptime()
        try await store.recoverInterruptedOperations()
        let importer = PrivateAssetImporter(privateRoot: storage, store: store)
        let recovery = try await importer.recover()
        try require(recovery.adopted == 0 && recovery.missing.isEmpty && recovery.invalid.isEmpty, "Restart unexpectedly recovered missing/invalid data")
        let after = try await store.assets(includeUsed: true)
        try require(before == after, "New process changed prior full asset records")
        try require(try await store.operation(id: oldOperation.id) == oldOperation, "New process changed full UNKNOWN operation")
        try require(try await store.uploadStartReceipt(for: oldOperation.id) == nil, "New process invented START")
        for record in after {
            let url = storage.appendingPathComponent("media/" + record.image.fileName)
            try require(digest(Data(contentsOf: url)) == record.image.sha256, "New process found media mismatch")
        }
        let report: [String: Any] = ["schema": 1, "result": "PASS_SCOPED_FRESH_PROCESS_RECOVERY", "completed": true,
            "pid": ProcessInfo.processInfo.processIdentifier, "assetCount": after.count,
            "allPriorFullAssetRecordsEqual": true, "unknownFullOperationEqual": true,
            "mediaVerified": after.count, "uploadStarts": 0, "recoveryElapsedSeconds": uptime() - started,
            "productionDataAccess": false, "scope": "Same native probe binary in a new process; real QueueStore/importer recovery. Not an installed App restart or system login."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output, options: .withoutOverwriting)
        print("HIGH_RESOLUTION_RESTART_PASS")
    }

    @MainActor static func main() async {
        do {
            let arguments = CommandLine.arguments
            if arguments.count == 3 && arguments[1] == "--verify-restart" {
                try await verifyRestart(URL(fileURLWithPath: arguments[2]).standardizedFileURL)
                return
            }
            guard arguments.count == 5, let captures = Int(arguments[2]), (12...200).contains(captures),
                  let seconds = Double(arguments[3]), seconds.isFinite, (0...7_200).contains(seconds),
                  let interval = Double(arguments[4]), interval.isFinite, (1...300).contains(interval) else {
                fputs("usage: high-resolution-soak NEW-ROOT/riftlet-hires-UUID INITIAL-CAPTURES MAINTENANCE-SECONDS INTERVAL-SECONDS\n", stderr)
                exit(64)
            }
            let probe = try HighResolutionSoak(root: URL(fileURLWithPath: arguments[1]).standardizedFileURL,
                captures: captures, seconds: seconds, interval: interval)
            try await probe.run()
            print("HIGH_RESOLUTION_SOAK_PASS: retained isolated high-resolution files; no windows/browser/production access")
        } catch {
            fputs("HIGH_RESOLUTION_SOAK_FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
