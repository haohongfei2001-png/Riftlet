import Foundation
import XCTest
@testable import RiftletCapture

final class CapturePreferenceObservationTests: XCTestCase {
    private func signatures() throws -> (FileSignature, FileSignature) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-preference-observation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.plist"), second = root.appendingPathComponent("b.plist")
        try Data("first preference".utf8).write(to: first)
        try Data("second preference".utf8).write(to: second)
        return (try FileSignature.read(at: first), try FileSignature.read(at: second))
    }

    func testDeletionAfterConsumerReadsReplacementCannotDisappearIntoAnAbsentEventBaseline() throws {
        let (first, replacement) = try signatures()
        var observation = CapturePreferenceObservation(signature: first)
        // Parent replacement is first sampled in the brief absent interval.
        XCTAssertTrue(observation.beginNotification(signature: nil, force: false))
        // Before the awaited consumer reads, a different preference is created.
        observation.didRead(signature: replacement)
        // Its immediate deletion is coalesced with creation. Both event samples
        // are nil, but the consumer must be told to leave the replacement path.
        XCTAssertTrue(observation.beginNotification(signature: nil, force: false))
        observation.didRead(signature: nil)
        XCTAssertFalse(observation.beginNotification(signature: nil, force: false))
    }

    func testReadObservationCannotSwallowAnOrdinaryChangeOrNotifyForUnrelatedWrites() throws {
        let (first, replacement) = try signatures()
        var observation = CapturePreferenceObservation(signature: first)
        observation.didRead(signature: first)
        XCTAssertFalse(observation.beginNotification(signature: first, force: false))
        // An independent read before the file event must not consume that event.
        observation.didRead(signature: replacement)
        XCTAssertTrue(observation.beginNotification(signature: replacement, force: false))
        observation.didRead(signature: replacement)
        XCTAssertFalse(observation.beginNotification(signature: replacement, force: false))
        XCTAssertTrue(observation.beginNotification(signature: replacement, force: true))
        XCTAssertFalse(observation.beginNotification(signature: replacement, force: false))
    }
}
