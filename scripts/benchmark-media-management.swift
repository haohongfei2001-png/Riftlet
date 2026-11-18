// Link this isolated probe against the candidate's RiftletCore and RiftletCapture products.
// swiftc -O -parse-as-library -I "$products" -I Sources/CSQLite scripts/benchmark-media-management.swift "$products/RiftletCore.o" "$products/RiftletCapture.o" -lsqlite3 -o "$probe"
// Run the binary without arguments. It creates and removes its own synthetic profile.
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import RiftletCapture
import RiftletCore
import UniformTypeIdentifiers

private func fixture() throws -> Data {
    // A screenshot-sized textured canvas. Every PNG has independent on-disk
    // source and managed file identities; repeated content makes sizes comparable.
    let width = 1024, height = 768
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    var seed: UInt32 = 71
    for y in 0..<height {
        for x in 0..<width {
            seed = seed &* 1664525 &+ 1013904223
            let offset = (y * width + x) * 4
            bytes[offset] = UInt8(truncatingIfNeeded: x / 5)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: y / 4)
            bytes[offset + 2] = y < 180 ? UInt8(truncatingIfNeeded: seed >> 24) : 128
            bytes[offset + 3] = 255
        }
    }
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

private func elapsed(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private func stats(_ values: [Double]) -> [String: Double] {
    let sorted = values.sorted()
    func p(_ fraction: Double) -> Double { sorted[Int(ceil(Double(sorted.count) * fraction)) - 1] }
    return ["n": Double(sorted.count), "p50": p(0.5), "p95": p(0.95), "max": sorted.last!]
}

private func resources() throws -> rusage_info_v4 {
    var result = rusage_info_v4()
    let code = withUnsafeMutablePointer(to: &result) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
        }
    }
    guard code == 0 else { throw POSIXError(.EIO) }
    return result
}

private func treeSize(_ url: URL) throws -> (files: Int, logicalBytes: Int64) {
    var count = 0, total: Int64 = 0
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
    let entries = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))!
    for case let url as URL in entries {
        let values = try url.resourceValues(forKeys: keys)
        if values.isRegularFile == true { count += 1; total += Int64(values.fileSize ?? 0) }
    }
    return (count, total)
}

@main private struct Probe {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-media-benchmark-" + UUID().uuidString)
        let originals = root.appendingPathComponent("originals"), profile = root.appendingPathComponent("profile")
        defer { try? FileManager.default.removeItem(at: root) }
        for dir in [originals, profile] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let store = try QueueStore(databaseURL: profile.appendingPathComponent("queue.sqlite"))
        let importer = PrivateAssetImporter(privateRoot: profile, store: store)
        try await importer.initializeRetention(newProfile: true)
        let bytes = try fixture()
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        @Sendable func ingest(_ n: Int) async throws -> AssetRecord {
            let src = originals.appendingPathComponent("\(n).png")
            try bytes.write(to: src)
            let tagged = marker.withUnsafeBytes { setxattr(src.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, marker.count, 0, 0) }
            guard tagged == 0 else { throw POSIXError(.EIO) }
            return try await importer.importCompletedScreenshot(at: src, origin: .systemScreenshot)
        }
        for n in 0..<1000 {
            let row = try await ingest(n)
            try await store.removeFromQueue(row.id)
        }
        let beforeFiles = try treeSize(root), before = try resources()
        let first = DispatchTime.now().uptimeNanoseconds
        let initial = try await importer.cleanupSummary()
        let firstSummaryMS = elapsed(first)
        precondition(initial.count == 1000)
        let verifyStart = DispatchTime.now().uptimeNanoseconds
        async let verified = importer.cleanupItems()
        var collectionMS = [Double](), snapshotMS = [Double]()
        for n in 1000..<1020 {
            let begin = DispatchTime.now().uptimeNanoseconds
            _ = try await ingest(n)
            collectionMS.append(elapsed(begin))
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try await importer.cleanupSummary()
            _ = try await store.history(limit: 50)
            try await importer.setRetention(days: n % 2 == 0 ? 30 : 90, includeExisting: true)
            snapshotMS.append(elapsed(start))
        }
        let batch = try await verified
        let combinedMS = elapsed(verifyStart)
        precondition(batch.count == 1000 && batch.allSatisfy(\.verifiedOriginal))
        let after = try resources(), afterFiles = try treeSize(root)
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        func cpuMS(_ ticks: UInt64) -> Double {
            Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
        }
        let report: [String: Any] = [
            "syntheticImageBytes": bytes.count, "imageSize": "1024x768", "initialCopies": initial.count,
            "initialProfileAndOriginalFiles": beforeFiles.files, "initialLogicalBytes": beforeFiles.logicalBytes,
            "initialSummaryMS": firstSummaryMS, "concurrentCollectionMS": stats(collectionMS),
            "summaryHistoryAndRuleMS": stats(snapshotMS), "verifyAndConcurrentWorkMS": combinedMS,
            "verifiedCopies": batch.count, "extraImports": 20,
            "fileGrowth": afterFiles.files - beforeFiles.files, "logicalGrowthBytes": afterFiles.logicalBytes - beforeFiles.logicalBytes,
            "cpuUserMS": cpuMS(after.ri_user_time - before.ri_user_time),
            "cpuSystemMS": cpuMS(after.ri_system_time - before.ri_system_time),
            "physicalDiskReadBytes": after.ri_diskio_bytesread - before.ri_diskio_bytesread,
            "physicalDiskWriteBytes": after.ri_diskio_byteswritten - before.ri_diskio_byteswritten,
            "finalRSSBytes": after.ri_resident_size, "initialRSSBytes": before.ri_resident_size
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
