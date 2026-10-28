import AppKit
import XCTest
@testable import RiftletApp

final class ScreenshotMarkupFidelityTests: XCTestCase {
    private func image(bits: Int, space: CGColorSpace) throws -> CGImage {
        let bytes = bits == 8 ? 4 : 8
        let data = Data(repeating: 0xff, count: 12 * 8 * bytes)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        return try XCTUnwrap(CGImage(width: 12, height: 8, bitsPerComponent: bits, bitsPerPixel: bytes * 8,
            bytesPerRow: 12 * bytes, space: space,
            bitmapInfo: bits == 16 ? bitmap.union(.byteOrder16Big) : bitmap,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @MainActor func testLightweightMarkupRejectsHighBitDepthAndUnknownTransferFunctions() throws {
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let extended = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        XCTAssertTrue(ScreenshotMarkupController.supportsMarkup(try image(bits: 8, space: srgb)))
        XCTAssertTrue(ScreenshotMarkupController.supportsMarkup(try image(bits: 8, space: p3)))
        XCTAssertFalse(ScreenshotMarkupController.supportsMarkup(try image(bits: 16, space: p3)))
        XCTAssertFalse(ScreenshotMarkupController.supportsMarkup(try image(bits: 8, space: extended)))
    }
}
