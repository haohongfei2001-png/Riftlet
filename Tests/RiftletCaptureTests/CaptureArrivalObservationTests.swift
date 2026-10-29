import XCTest
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Darwin
import CSQLite
import RiftletCore
@testable import RiftletCapture

private final class ArrivalObservationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance() { lock.lock(); value.addTimeInterval(1); lock.unlock() }
}

private struct ImportedObservationCheck: Sendable {
    let record: AssetRecord
    let observation: ScreenshotSourceObservation
    let committedInSeparateConnection: Bool
    let privateBytesPresent: Bool
}

private final class ArrivalObservationChecks: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ImportedObservationCheck] = []
    func append(_ item: ImportedObservationCheck) { lock.lock(); items.append(item); lock.unlock() }
    func read() -> [ImportedObservationCheck] { lock.lock(); defer { lock.unlock() }; return items }
}

/// A separate read-only SQLite connection checks visibility DURING the synchronous
/// callback. An async read scheduled later would not prove commit preceded callback.
private func committedAssetIsVisible(databaseURL: URL, id: UUID) -> Bool {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        if let database { sqlite3_close(database) }
        return false
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "SELECT id,status,visibility FROM assets", -1, &statement, nil) == SQLITE_OK else { return false }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW,
          let assetID = sqlite3_column_text(statement, 0),
          let status = sqlite3_column_text(statement, 1),
          let visibility = sqlite3_column_text(statement, 2) else { return false }
    return String(cString: assetID) == id.uuidString && String(cString: status) == "pending"
        && String(cString: visibility) == "visible"
}

final class CaptureArrivalObservationTests: XCTestCase {
    func testOptionalArrivalObservationFollowsDurableImportAndDoesNotWaitForGeometry() async throws {
        let fixture = try CaptureTests.Fixture()
        defer { fixture.close() }
        let clock = ArrivalObservationClock(), checks = ArrivalObservationChecks()
        let database = fixture.privateRoot.appendingPathComponent("queue.sqlite")
        let media = fixture.privateRoot.appendingPathComponent("media")
        let source = fixture.source.appendingPathComponent("generated-no-source-rectangle.png")
        let service = CaptureService(store: fixture.store, privateRoot: fixture.privateRoot, sourceDirectory: fixture.source,
            onImported: { record, observation in
                // Deliberately do NOT read or resolve optional geometry here.
                // The imported record must already be usable through independent DB/file reads.
                let committed = committedAssetIsVisible(databaseURL: database, id: record.id)
                let copy = try? Data(contentsOf: media.appendingPathComponent(record.image.fileName))
                let original = try? Data(contentsOf: source)
                checks.append(ImportedObservationCheck(record: record, observation: observation,
                    committedInSeparateConnection: committed, privateBytesPresent: copy != nil && copy == original))
            }, recordSourceTiming: true, now: { clock.read() })
        do {
            try await service.start()
            let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
            let image = try XCTUnwrap(context.makeImage())
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            XCTAssertEqual(marker.withUnsafeBytes { setxattr(source.path, CaptureSource.metadataName, $0.baseAddress, $0.count, 0, 0) }, 0)
            try await service.rescan()
            clock.advance()
            try await service.rescan()
            let observations = checks.read()
            XCTAssertEqual(observations.count, 1)
            let observed = try XCTUnwrap(observations.first)
            XCTAssertTrue(observed.committedInSeparateConnection)
            XCTAssertTrue(observed.privateBytesPresent)
            XCTAssertEqual(observed.observation.assetID, observed.record.id)
            XCTAssertLessThanOrEqual(observed.observation.readyUptime, ProcessInfo.processInfo.systemUptime)
            let timing = try XCTUnwrap(observed.observation.sourceTiming)
            let firstObserved = try XCTUnwrap(timing.firstObservedUptime)
            XCTAssertGreaterThan(firstObserved, 0)
            XCTAssertLessThanOrEqual(firstObserved, timing.validatedCopyUptime)
            XCTAssertLessThanOrEqual(timing.validatedCopyUptime, timing.durableCommitUptime)
            XCTAssertLessThanOrEqual(timing.durableCommitUptime, observed.observation.readyUptime)
            XCTAssertNil(observed.record.image.capturedAt, "Diagnostic observations do not invent system capture completion")
            XCTAssertEqual(observed.observation.readMetadata(), .failure(.missingRectangle))
            let durable = try await fixture.store.asset(id: observed.record.id)
            XCTAssertEqual(durable, observed.record)
            try await service.rescan()
            XCTAssertEqual(checks.read().count, 1, "Repeated directory events do not replay an arrival")
            await service.stop()
        } catch {
            await service.stop()
            throw error
        }
    }
}
