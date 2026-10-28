import XCTest
import Foundation
import CoreGraphics
import Darwin
@testable import RiftletCapture

/// Synthetic plist/desktop fixtures. Passing tests are not real Screenshot.app,
/// physical display, source-position or Retina acceptance.
final class ScreenshotSourceGeometryTests: XCTestCase {
    private let primary = ScreenshotDisplayGeometry(id: 1,
        quartzBounds: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        appKitFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900), backingScale: 2)

    private func plist(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private func decode(_ rectangle: Any, kind: Any = "selection") throws
        -> Result<ScreenshotSourceMetadata, ScreenshotSourceFailure> {
        ScreenshotSourceMetadataReader.decode(rectangleData: try plist(rectangle), captureKindData: try plist(kind))
    }

    private func metadata(_ rect: CGRect, kind: ScreenshotCaptureKind = .selection) -> ScreenshotSourceMetadata {
        ScreenshotSourceMetadata(captureKind: kind, quartzRect: rect)
    }

    func testFourNumberPlistAndExactKnownCaptureKinds() throws {
        for kind in [ScreenshotCaptureKind.selection, .window, .display] {
            let parsed = try decode([12.5, 24.5, 200.0, 100.0], kind: kind.rawValue).get()
            XCTAssertEqual(parsed.quartzRect, CGRect(x: 12.5, y: 24.5, width: 200, height: 100))
            XCTAssertEqual(parsed.captureKind, kind)
        }
    }

    func testRejectsLegacyIncompleteRectStringsBooleansAndWrongShapes() throws {
        let malformed: [Any] = [[12], [12, 24, 200], [12, 24, 200, 100, 99],
                                [true, false, true, true], ["12", "24", "200", "100"],
                                "{{12, 24}, {200, 100}}", ["x": 12, "y": 24, "width": 200, "height": 100]]
        for value in malformed {
            XCTAssertEqual(try decode(value), .failure(.malformedRectangle))
        }
        XCTAssertEqual(ScreenshotSourceMetadataReader.decode(rectangleData: nil, captureKindData: try plist("selection")),
                       .failure(.missingRectangle))
        XCTAssertEqual(ScreenshotSourceMetadataReader.decode(rectangleData: Data(repeating: 0, count: 4_097),
                                                              captureKindData: try plist("selection")),
                       .failure(.malformedRectangle))
    }

    func testRejectsNonfiniteEmptyAndNegativeGeometry() throws {
        for values in [[0.0, 0, 0, 100], [0, 0, -10, 100], [0, 0, 100, -10],
                       [Double.nan, 0, 100, 100], [0, Double.infinity, 100, 100],
                       [0, 0, Double.infinity, 100], [0, 0, 100, -Double.infinity]] {
            XCTAssertEqual(try decode(values), .failure(.malformedRectangle))
        }
    }

    func testMissingOrUnrecognizedCaptureTypeNeverGuesses() throws {
        XCTAssertEqual(ScreenshotSourceMetadataReader.decode(rectangleData: try plist([0, 0, 100, 100]),
                                                              captureKindData: nil), .failure(.missingCaptureKind))
        let unsupported: [Any] = ["Selection", "selection\n", "fullscreen", "", 1, ["window"]]
        for kind in unsupported {
            XCTAssertEqual(try decode([0, 0, 100, 100], kind: kind), .failure(.unsupportedCaptureKind))
        }
    }

    func testRetinaPointsConvertToAppKitWithoutScalingTheOrigin() throws {
        let result = try ScreenshotSourceGeometryResolver.resolve(
            metadata(CGRect(x: 100, y: 120, width: 200, height: 100)), pixelWidth: 400, pixelHeight: 200,
            displays: [primary], targetDisplayID: 1).get()
        XCTAssertEqual(result.appKitRect, CGRect(x: 100, y: 680, width: 200, height: 100))
        XCTAssertEqual(result.displayID, 1)
        XCTAssertEqual(result.backingScale, 2)
    }

    func testNegativeOriginSecondaryDisplayAndDifferentScale() throws {
        let left = ScreenshotDisplayGeometry(id: 2,
            quartzBounds: CGRect(x: -1_920, y: 100, width: 1_920, height: 1_080),
            appKitFrame: CGRect(x: -1_920, y: -280, width: 1_920, height: 1_080), backingScale: 1)
        let result = try ScreenshotSourceGeometryResolver.resolve(
            metadata(CGRect(x: -1_800, y: 200, width: 400, height: 300)), pixelWidth: 400, pixelHeight: 300,
            displays: [primary, left], targetDisplayID: 2).get()
        XCTAssertEqual(result.appKitRect, CGRect(x: -1_800, y: 400, width: 400, height: 300))
        XCTAssertEqual(result.backingScale, 1)
    }

    func testDisplaysAboveAndBelowPrimaryUseTheirOwnFrames() throws {
        let above = ScreenshotDisplayGeometry(id: 2,
            quartzBounds: CGRect(x: 0, y: -1_080, width: 1_920, height: 1_080),
            appKitFrame: CGRect(x: 0, y: 900, width: 1_920, height: 1_080), backingScale: 1)
        let below = ScreenshotDisplayGeometry(id: 3,
            quartzBounds: CGRect(x: 0, y: 900, width: 1_920, height: 1_080),
            appKitFrame: CGRect(x: 0, y: -1_080, width: 1_920, height: 1_080), backingScale: 1)
        let top = try ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 80, y: -1_000, width: 200, height: 100)),
            pixelWidth: 200, pixelHeight: 100, displays: [primary, above, below], targetDisplayID: 2).get()
        let bottom = try ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 80, y: 1_000, width: 200, height: 100)),
            pixelWidth: 200, pixelHeight: 100, displays: [primary, above, below], targetDisplayID: 3).get()
        XCTAssertEqual(top.appKitRect.minY, 1_800)
        XCTAssertEqual(bottom.appKitRect.minY, -200)
    }

    func testRetinaFilePixelsAreNotReinterpretedAsLogicalPoints() {
        let result = ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 100, y: 120, width: 400, height: 200)),
            pixelWidth: 400, pixelHeight: 200, displays: [primary], targetDisplayID: 1)
        XCTAssertEqual(result, .failure(.pixelScaleMismatch))
    }

    func testWindowPaddingMismatchAndWrongPixelSizeFallBack() {
        for kind in [ScreenshotCaptureKind.selection, .window] {
            XCTAssertEqual(ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 100, y: 100, width: 200, height: 100), kind: kind),
                pixelWidth: 440, pixelHeight: 240, displays: [primary], targetDisplayID: 1), .failure(.pixelScaleMismatch))
        }
    }

    func testCrossDisplayDestinationAndSpanningRectangleFallBack() {
        let second = ScreenshotDisplayGeometry(id: 2,
            quartzBounds: CGRect(x: 1_440, y: 0, width: 1_440, height: 900),
            appKitFrame: CGRect(x: 1_440, y: 0, width: 1_440, height: 900), backingScale: 2)
        XCTAssertEqual(ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 100, y: 100, width: 200, height: 100)),
            pixelWidth: 400, pixelHeight: 200, displays: [primary, second], targetDisplayID: 2), .failure(.crossDisplay))
        XCTAssertEqual(ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 1_400, y: 100, width: 200, height: 100)),
            pixelWidth: 400, pixelHeight: 200, displays: [primary, second], targetDisplayID: 1), .failure(.outsideDisplay))
    }

    func testMirrorAndAmbiguousOverlapAreRejected() {
        let rect = metadata(CGRect(x: 100, y: 100, width: 200, height: 100))
        let mirror = ScreenshotDisplayGeometry(id: 2, quartzBounds: primary.quartzBounds,
            appKitFrame: primary.appKitFrame, backingScale: 2, isMirrored: true)
        XCTAssertEqual(ScreenshotSourceGeometryResolver.resolve(rect, pixelWidth: 400, pixelHeight: 200,
            displays: [mirror], targetDisplayID: 2), .failure(.mirroredDisplay))
        XCTAssertEqual(ScreenshotSourceGeometryResolver.resolve(rect, pixelWidth: 400, pixelHeight: 200,
            displays: [primary, mirror], targetDisplayID: 1), .failure(.ambiguousDisplay))
    }

    func testInvalidDisplayScaleOrMismatchedLogicalBoundsFallBack() {
        for scale in [0.0, Double.nan, Double.infinity, 5.0] {
            let bad = ScreenshotDisplayGeometry(id: 1, quartzBounds: primary.quartzBounds,
                appKitFrame: primary.appKitFrame, backingScale: scale)
            XCTAssertEqual(ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 100, y: 100, width: 200, height: 100)),
                pixelWidth: 400, pixelHeight: 200, displays: [bad], targetDisplayID: 1), .failure(.invalidDisplayGeometry))
        }
        let bad = ScreenshotDisplayGeometry(id: 1, quartzBounds: primary.quartzBounds,
            appKitFrame: CGRect(x: 0, y: 0, width: 2_880, height: 1_800), backingScale: 2)
        XCTAssertEqual(ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 100, y: 100, width: 200, height: 100)),
            pixelWidth: 400, pixelHeight: 200, displays: [bad], targetDisplayID: 1), .failure(.invalidDisplayGeometry))
    }

    func testFullscreenMustMatchTheDisplayAndItsPixelScale() throws {
        let full = try ScreenshotSourceGeometryResolver.resolve(metadata(primary.quartzBounds, kind: .display),
            pixelWidth: 2_880, pixelHeight: 1_800, displays: [primary], targetDisplayID: 1).get()
        XCTAssertEqual(full.appKitRect, primary.appKitFrame)
        XCTAssertEqual(ScreenshotSourceGeometryResolver.resolve(metadata(CGRect(x: 100, y: 100, width: 200, height: 100), kind: .display),
            pixelWidth: 400, pixelHeight: 200, displays: [primary], targetDisplayID: 1), .failure(.displayCaptureMismatch))
    }

    private func writeAttribute(_ value: Any, name: String, at url: URL) throws {
        let bytes = try plist(value)
        XCTAssertEqual(bytes.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, $0.count, 0, 0) }, 0)
    }

    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-source-geometry-" + UUID().uuidString)
        try Data("synthetic geometry metadata fixture".utf8).write(to: url)
        try writeAttribute(true, name: CaptureSource.metadataName, at: url)
        try writeAttribute([100, 100, 200, 100], name: ScreenshotSourceMetadataReader.rectangleAttribute, at: url)
        try writeAttribute("selection", name: ScreenshotSourceMetadataReader.kindAttribute, at: url)
        return url
    }

    func testObservationReadsOriginalMetadataWithoutChangingFileBytes() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let before = try Data(contentsOf: url)
        let signature = try FileSignature.read(at: url)
        let id = UUID()
        let observation = ScreenshotSourceObservation(url: url, signature: signature, assetID: id, readyUptime: 100)
        let result = try observation.readMetadata().get()
        XCTAssertEqual(result.quartzRect, CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertEqual(observation.assetID, id)
        XCTAssertEqual(observation.readyUptime, 100)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileSignature.read(at: url), signature)
    }

    func testObservationRejectsSameInodeContentMutationAfterImport() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let signature = try FileSignature.read(at: url)
        let observation = ScreenshotSourceObservation(url: url, signature: signature, assetID: UUID())
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        let changed = try FileSignature.read(at: url)
        XCTAssertEqual(changed.sourceKey, signature.sourceKey, "This tests an in-place edit, not only inode replacement")
        XCTAssertEqual(observation.readMetadata(), .failure(.sourceChanged))
    }

    func testObservationRejectsReplacementAndSymlink() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let observation = ScreenshotSourceObservation(url: url, signature: try FileSignature.read(at: url), assetID: UUID())
        try FileManager.default.removeItem(at: url)
        try Data("different inode".utf8).write(to: url)
        XCTAssertEqual(observation.readMetadata(), .failure(.sourceChanged))
        let link = url.appendingPathExtension("symlink")
        defer { try? FileManager.default.removeItem(at: link) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        let linked = ScreenshotSourceObservation(url: link, signature: try FileSignature.read(at: url), assetID: UUID())
        XCTAssertEqual(linked.readMetadata(), .failure(.unreadableSource))
    }

    func testMissingMetadataOrFalseScreenshotMarkerNeverInventsPosition() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(removexattr(url.path, ScreenshotSourceMetadataReader.rectangleAttribute, 0), 0)
        let noRect = ScreenshotSourceObservation(url: url, signature: try FileSignature.read(at: url), assetID: UUID())
        XCTAssertEqual(noRect.readMetadata(), .failure(.missingRectangle))
        try writeAttribute(false, name: CaptureSource.metadataName, at: url)
        let ordinary = ScreenshotSourceObservation(url: url, signature: try FileSignature.read(at: url), assetID: UUID())
        XCTAssertEqual(ordinary.readMetadata(), .failure(.notScreenshot))
    }
}
