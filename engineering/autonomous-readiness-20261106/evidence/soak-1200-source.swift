import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import RiftletCapture
import RiftletCore

/// Real temporary files, ImageIO and SQLite; never the user's data or browser.
/// Metrics are storage/collector timings, not UI presentation or remote upload.
final class ReadinessSoak {
    private func png() throws -> Data {
        let context = try unwrap(CGContext(data: nil, width: 64, height: 40,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.65, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        let bytes = NSMutableData()
        let destination = try unwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try unwrap(context.makeImage()), nil)
        try ensure(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func writeScreenshot(_ bytes: Data, to url: URL) throws {
        try bytes.write(to: url)
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        try equal(marker.withUnsafeBytes { setxattr(url.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }, 0)
    }

    private func metrics(_ name: String, _ samples: [Double], count: Int) throws {
        let sorted = samples.sorted()
        let result: [String: Any] = ["name": name, "scope": "isolated native storage; no UI or network",
            "count": count, "samples": samples.count, "unit": "ms",
            "p50": sorted[sorted.count / 2], "p95": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
            "max": sorted.last!, "total": sorted.reduce(0,+)]
        print("READINESS_METRIC " + String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }

    func testRepeatedImportChurnReopenPreservesEveryOriginalAndUnknown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-readiness-soak-" + UUID().uuidString)
        let source = root.appendingPathComponent("source"), storage = root.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = storage.appendingPathComponent("queue.sqlite")
        var store = try QueueStore(databaseURL: database)
        var importer = PrivateAssetImporter(privateRoot: storage, store: store)
        let bytes = try png()
        let requested = Int(ProcessInfo.processInfo.environment["RIFTLET_SOAK_CAPTURES"] ?? "160") ?? 160
        let count = min(10000, max(160, requested))
        let interval = min(1000, max(0, Int(ProcessInfo.processInfo.environment["RIFTLET_SOAK_INTERVAL_MS"] ?? "0") ?? 0))
        var importMS: [Double] = [], queueMS: [Double] = [], historyMS: [Double] = [], ids: [UUID] = []
        var unknownID: UUID?, unknownOperation: UUID?
        let runStart = monotonicStart()
        let monotonic = { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }
        for index in 0..<count {
            let original = source.appendingPathComponent("generated-\(index).png")
            try writeScreenshot(bytes, to: original)
            let signature = try FileSignature.read(at: original)
            let start = monotonic()
            let asset = try await importer.importStableFile(at: original, signature: signature, firstSeenAt: Date())
            importMS.append(monotonic() - start)
            let duplicate = try await importer.importStableFile(at: original, signature: signature, firstSeenAt: Date())
            try equal(asset.id, duplicate.id)
            ids.append(asset.id)
            if index == 0 {
                let target = TargetLease(adapterID: "readiness", surface: .webChat, applicationID: "fixture.browser",
                    sessionID: "session", windowID: "window", tabID: "tab", documentID: "doc", composerID: "composer", draftGeneration: "draft")
                let op = try await store.prepare(assetID: asset.id, target: target)
                try await store.markDispatchIntent(op.id)
                try await store.markUnknown(op.id, reason: "isolated interruption fixture")
                unknownID = asset.id; unknownOperation = op.id
            }
            let queueStart = monotonic()
            let visible = try await store.assets()
            queueMS.append(monotonic() - queueStart)
            try lessOrEqual(visible.count, 9)
            if index % 8 == 7 { _ = try await store.clearVisibleQueue() }
            if index % 40 == 39 {
                try resourceSample(captures: index + 1, start: runStart)
                let historyStart = monotonic()
                let page = try await store.historySnapshot(limit: 40)
                historyMS.append(monotonic() - historyStart)
                try equal(page.count, 40)
                store = try QueueStore(databaseURL: database)
                importer = PrivateAssetImporter(privateRoot: storage, store: store)
                try await store.recoverInterruptedOperations()
                let recovery = try await importer.recover()
                try equal(recovery.adopted, 0)
                let old = try await store.asset(id: unwrap(unknownID))
                try equal(old?.status, .unknown)
                try equal(old?.activeOperationID, unknownOperation)
            }
            if interval > 0 { try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000) }
        }
        _ = try await store.clearVisibleQueue()
        let all = try await store.assets(includeUsed: true)
        try equal(all.count, count)
        try equal(Set(all.map(\.id)), Set(ids))
        try equal(try FileManager.default.contentsOfDirectory(atPath: source.path).count, count)
        try equal(try FileManager.default.contentsOfDirectory(atPath: storage.appendingPathComponent("media").path).count, count)
        for record in all {
            try equal(try Data(contentsOf: storage.appendingPathComponent("media").appendingPathComponent(record.image.fileName)), bytes)
        }
        for index in 0..<count { try equal(try Data(contentsOf: source.appendingPathComponent("generated-\(index).png")), bytes) }
        let oldOperation = try await store.operation(id: unwrap(unknownOperation))
        try equal(oldOperation?.phase, .unknown)
        try metrics("stable_file_to_durable_asset", importMS, count: count)
        try metrics("visible_queue_after_history_growth", queueMS, count: count)
        try metrics("history_page_40", historyMS, count: count)
    }

    func testCollectorBurstsAndRestartDoNotDuplicateOrLoseStoppedArrivals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-readiness-collector-" + UUID().uuidString)
        let source = root.appendingPathComponent("source"), storage = root.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: storage.appendingPathComponent("queue.sqlite"))
        let service = CaptureService(store: store, privateRoot: storage, sourceDirectory: source)
        let bytes = try png()
        try await service.start()
        for batch in 0..<4 {
            if batch > 0 { await service.stop() }
            for item in 0..<40 { try writeScreenshot(bytes, to: source.appendingPathComponent("\(batch)-\(item).png")) }
            if batch > 0 { try await service.start() }
            let start = DispatchTime.now().uptimeNanoseconds
            var observed = 0
            for _ in 0..<100 {
                try await service.rescan()
                observed = try await store.assets(includeUsed: true).count
                if observed == (batch + 1) * 40 { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            try equal(observed, (batch + 1) * 40)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            try metrics("burst_40_to_collected_batch_\(batch)", [elapsed], count: observed)
            _ = try await store.clearVisibleQueue()
        }
        await service.stop()
        let all = try await store.assets(includeUsed: true)
        try equal(all.count, 160)
        try equal(Set(all.map(\.image.sourceKey)).count, 160)
        try equal(try FileManager.default.contentsOfDirectory(atPath: source.path).count, 160)
    }
}

private enum ProbeFailure: Error { case mismatch(String), missingValue }
private func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw ProbeFailure.missingValue }; return value }
private func equal<T: Equatable>(_ a: T, _ b: T, file: String = #fileID, line: Int = #line) throws {
    guard a == b else { throw ProbeFailure.mismatch("\(file):\(line): unequal values") }
}
private func ensure(_ value: Bool, file: String = #fileID, line: Int = #line) throws {
    guard value else { throw ProbeFailure.mismatch("\(file):\(line): condition failed") }
}
private func lessOrEqual<T: Comparable>(_ a: T, _ b: T, file: String = #fileID, line: Int = #line) throws {
    guard a <= b else { throw ProbeFailure.mismatch("\(file):\(line): bound exceeded") }
}
@main struct ReadinessRunner {
    static func main() async throws {
        let probe = ReadinessSoak()
        try await probe.testCollectorBurstsAndRestartDoNotDuplicateOrLoseStoppedArrivals()
        try await probe.testRepeatedImportChurnReopenPreservesEveryOriginalAndUnknown()
        print("READINESS_SOAK_PASS: real temporary files/ImageIO/SQLite; no UI/browser/production mutation")
    }
}

private func monotonicStart() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
private func resourceSample(captures: Int, start: UInt64) throws {
    var info = mach_task_basic_info()
    var size = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &size)
        }
    }
    guard status == KERN_SUCCESS else { throw ProbeFailure.mismatch("task_info failed") }
    var usage = rusage(); guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw ProbeFailure.mismatch("getrusage failed") }
    let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    let row: [String: Any] = ["captures": captures, "elapsedSeconds": Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000,
        "residentBytes": info.resident_size, "peakResidentBytes": usage.ru_maxrss, "cpuSeconds": cpu,
        "scope": "isolated collector/store probe; excludes UI and browser"]
    print("READINESS_RESOURCE " + String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))
}
