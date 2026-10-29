import AppKit
import QuartzCore
import XCTest
@testable import RiftletUI

/// Software AppKit/WindowServer checks only. These do not certify physical
/// click-through, another application's focus, screenshot exclusion or taste.
final class MagnetFlightPresenterTests: XCTestCase {
    @MainActor private func fixture(short: Bool = false) throws -> (MagnetMotionPlan, CGImage, CGFloat) {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first(where: { $0.frame.width > 800 && $0.frame.height > 500 }),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("Needs a WindowServer display with motion permitted; physical acceptance remains NOT_RUN")
        }
        let frame = screen.frame
        let source = CGRect(x: frame.minX + 80, y: frame.minY + 80, width: 400, height: 280)
        let destination = CGRect(x: frame.maxX - 62, y: frame.minY + 320, width: 72, height: 56)
        var parameters = MagnetMotionParameters()
        if short {
            parameters.formationDuration = 0.01
            parameters.chargeDuration = 0.01
            parameters.attractionDuration = 0.02
            parameters.settleDuration = 0.01
        }
        let plan = try XCTUnwrap(MagnetMotionPlan(sourceRect: source, targetImageFrame: destination,
            clippingEdgeX: frame.maxX - 8, screenFrame: frame, parameters: parameters))
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 312, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 312))
        return (plan, try XCTUnwrap(context.makeImage()), screen.backingScaleFactor)
    }

    @MainActor func testDecorationOwnsOneMouseTransparentNonactivatingWindowAndReleasesSynchronously() throws {
        let (plan, image, scale) = try fixture()
        let presenter = MagnetFlightPresenter()
        defer { presenter.close() }
        let id = UUID()
        var completions: [MagnetFlightCompletion] = []
        XCTAssertTrue(presenter.start(assetID: id, image: image, plan: plan, backingScale: scale) { value in
            XCTAssertEqual(presenter.activePanelCount, 0)
            XCTAssertEqual(presenter.diagnostics.retainedImageCount, 0)
            completions.append(value)
        })
        let diagnostics = presenter.diagnostics
        XCTAssertEqual(diagnostics.assetID, id)
        XCTAssertEqual(diagnostics.activePanelCount, 1)
        XCTAssertEqual(diagnostics.retainedImageCount, 1)
        XCTAssertTrue(diagnostics.ignoresMouseEvents)
        XCTAssertFalse(diagnostics.canBecomeKey)
        XCTAssertFalse(diagnostics.canBecomeMain)
        let window = try XCTUnwrap(NSApp.windows.first(where: { $0.windowNumber == diagnostics.windowNumber }))
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(window.collectionBehavior.contains(.transient))
        XCTAssertFalse(window.collectionBehavior.contains(.stationary))
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.contentView?.isAccessibilityHidden() ?? false)
        presenter.cancel(assetID: id, reason: .clicked)
        XCTAssertEqual(completions.map(\.reason), [.clicked])
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(window.contentView)
        XCTAssertNil(presenter.currentAssetID)
        presenter.cancel(assetID: id)
        XCTAssertEqual(completions.count, 1)
    }

    @MainActor func testTwelveCaptureBurstKeepsOneSpriteAndNoStaleCancelOwnsTheReplacement() async throws {
        let (plan, image, scale) = try fixture()
        let presenter = MagnetFlightPresenter()
        defer { presenter.close() }
        var completions: [MagnetFlightCompletion] = []
        var ids: [UUID] = []
        for _ in 0..<12 {
            let id = UUID(); ids.append(id)
            XCTAssertTrue(presenter.start(assetID: id, image: image, plan: plan, backingScale: scale) {
                completions.append($0)
            })
            XCTAssertEqual(presenter.currentAssetID, id)
            XCTAssertEqual(presenter.activePanelCount, 1)
            XCTAssertEqual(presenter.diagnostics.retainedImageCount, 1)
        }
        XCTAssertEqual(completions.map(\.assetID), Array(ids.dropLast()))
        XCTAssertTrue(completions.allSatisfy { $0.reason == .superseded })
        presenter.cancel(assetID: ids[0], reason: .clicked)
        XCTAssertEqual(presenter.currentAssetID, ids.last)
        presenter.cancel(reason: .captureObserved)
        XCTAssertEqual(completions.count, 12)
        XCTAssertEqual(completions.last?.reason, .captureObserved)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(presenter.activePanelCount, 0)
        XCTAssertEqual(completions.count, 12, "Old animation and watchdog callbacks are harmless")
        XCTAssertEqual(Set(completions.map(\.generation)).count, 12)
    }

    @MainActor func testVisibleHostRetainsReadyClockAndNaturallyFinishesTheNormalPlan() async throws {
        let (plan, image, scale) = try fixture()
        let presenter = MagnetFlightPresenter()
        defer { presenter.close() }
        let elapsed: TimeInterval = 0.080
        var completions: [MagnetFlightCompletion] = []
        var observations: [MagnetAnimationObservation] = []
        let before = CACurrentMediaTime()
        XCTAssertTrue(presenter.start(assetID: UUID(), image: image, plan: plan, backingScale: scale,
            elapsedSinceAssetReady: elapsed, onAnimationObservation: { observations.append($0) }) {
                completions.append($0)
            })
        let after = CACurrentMediaTime()
        let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == presenter.diagnostics.windowNumber })
        XCTAssertTrue(window.isVisible)
        func findImage(_ layer: CALayer) -> CALayer? {
            if layer.name == "rift.magnet.image" { return layer }
            return layer.sublayers?.compactMap { findImage($0) }.first
        }
        let root = try XCTUnwrap(window.contentView?.layer)
        let imageLayer = try XCTUnwrap(findImage(root))
        let animation = try XCTUnwrap(imageLayer.animation(forKey: "riftlet.magnet.flight"))
        let globalBegin = imageLayer.convertTime(animation.beginTime, to: nil)
        XCTAssertGreaterThanOrEqual(globalBegin, before - elapsed - 0.000001)
        XCTAssertLessThanOrEqual(globalBegin, after - elapsed + 0.000001)
        XCTAssertLessThan(globalBegin, before)
        XCTAssertEqual(animation.duration, plan.totalDuration)
        XCTAssertEqual(animation.fillMode, .backwards)
        XCTAssertTrue(animation.isRemovedOnCompletion)
        XCTAssertEqual(animation.speed, 1)
        XCTAssertEqual(animation.timeOffset, 0)
        XCTAssertTrue(observations.contains { $0.phase == .submitted })
        for _ in 0..<90 where completions.isEmpty {
            CATransaction.flush()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(completions.map(\.reason), [.finished])
        XCTAssertTrue(observations.contains { $0.phase == .stopped && $0.finished == true })
        XCTAssertEqual(presenter.activePanelCount, 0)
        XCTAssertEqual(presenter.diagnostics.retainedImageCount, 0)
    }

    @MainActor func testNaturalFinishAndExplicitCloseReleaseWithoutReplayingCompletion() async throws {
        let (plan, image, scale) = try fixture(short: true)
        let presenter = MagnetFlightPresenter()
        var completions: [MagnetFlightCompletion] = []
        XCTAssertTrue(presenter.start(assetID: UUID(), image: image, plan: plan, backingScale: scale) {
            completions.append($0)
        })
        try await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertEqual(completions.count, 1)
        XCTAssertTrue([.finished, .timedOut].contains(completions[0].reason))
        XCTAssertEqual(presenter.activePanelCount, 0)
        XCTAssertEqual(presenter.diagnostics.retainedImageCount, 0)
        presenter.close()
        presenter.close()
        XCTAssertFalse(presenter.start(assetID: UUID(), image: image, plan: plan, backingScale: scale) { _ in
            XCTFail("Closed presenter cannot begin or complete a new decoration")
        })
        XCTAssertEqual(completions.count, 1)
    }

    @MainActor func testScreenChangeCancelsAndNoOtherAssetsAreRepresentedOrMutated() async throws {
        let (plan, image, scale) = try fixture()
        let presenter = MagnetFlightPresenter()
        defer { presenter.close() }
        let id = UUID()
        var ended: MagnetFlightCompletion?
        XCTAssertTrue(presenter.start(assetID: id, image: image, plan: plan, backingScale: scale) { ended = $0 })
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(ended?.assetID, id)
        XCTAssertEqual(ended?.reason, .geometryChanged)
        XCTAssertEqual(presenter.activePanelCount, 0)
    }

    @MainActor func testInvalidScaleAndStaleScreenNeverAllocateWindow() throws {
        let (plan, image, _) = try fixture()
        let presenter = MagnetFlightPresenter()
        defer { presenter.close() }
        for scale in [CGFloat(0), .nan, .infinity, 8] {
            XCTAssertFalse(presenter.start(assetID: UUID(), image: image, plan: plan, backingScale: scale) { _ in
                XCTFail("Invalid start does not manufacture a completed flight")
            })
            XCTAssertEqual(presenter.activePanelCount, 0)
        }
        let stale = try XCTUnwrap(MagnetMotionPlan(sourceRect: plan.sourceRect.offsetBy(dx: 10_000, dy: 0),
            targetImageFrame: plan.finalFrame.offsetBy(dx: 10_000, dy: 0),
            clippingEdgeX: plan.clippingEdgeX + 10_000, screenFrame: plan.screenFrame.offsetBy(dx: 10_000, dy: 0)))
        XCTAssertFalse(presenter.start(assetID: UUID(), image: image, plan: stale, backingScale: 2) { _ in
            XCTFail("A disconnected or changed screen must fall back")
        })
        XCTAssertEqual(presenter.activePanelCount, 0)
    }

    @MainActor func testExpiredOrInvalidReadyClockDoesNotReplayDecoration() throws {
        let (plan, image, scale) = try fixture()
        let presenter = MagnetFlightPresenter()
        defer { presenter.close() }
        for elapsed in [Double.nan, .infinity, -0.01, plan.totalDuration, plan.totalDuration + 1] {
            XCTAssertFalse(presenter.start(assetID: UUID(), image: image, plan: plan,
                backingScale: scale, elapsedSinceAssetReady: elapsed) { _ in
                    XCTFail("An expired asset-ready decoration never manufactures completion")
                })
            XCTAssertEqual(presenter.activePanelCount, 0)
        }
    }

    @MainActor func testReentrantCompletionCannotOrphanANewerWindow() throws {
        let (plan, image, scale) = try fixture()
        let presenter = MagnetFlightPresenter()
        defer { presenter.close() }
        let first = UUID(), nested = UUID(), attempted = UUID()
        var ended: [UUID] = []
        XCTAssertTrue(presenter.start(assetID: first, image: image, plan: plan, backingScale: scale) {
            ended.append($0.assetID)
            XCTAssertTrue(presenter.start(assetID: nested, image: image, plan: plan, backingScale: scale) {
                ended.append($0.assetID)
            })
        })
        XCTAssertFalse(presenter.start(assetID: attempted, image: image, plan: plan, backingScale: scale) { _ in
            XCTFail("A start superseded during its own callback never owns a window")
        })
        XCTAssertEqual(presenter.currentAssetID, nested)
        XCTAssertEqual(presenter.activePanelCount, 1)
        XCTAssertEqual(ended, [first])
        presenter.cancel(reason: .clicked)
        XCTAssertEqual(ended, [first, nested])
    }

    @MainActor func testDroppedPresenterHasNoWindowOrImageLeftBehind() async throws {
        let (plan, image, scale) = try fixture()
        var presenter: MagnetFlightPresenter? = MagnetFlightPresenter()
        weak var weakPresenter = presenter
        XCTAssertTrue(presenter!.start(assetID: UUID(), image: image, plan: plan, backingScale: scale) { _ in })
        let number = try XCTUnwrap(presenter?.diagnostics.windowNumber)
        let window = try XCTUnwrap(NSApp.windows.first(where: { $0.windowNumber == number }))
        presenter = nil
        XCTAssertNil(weakPresenter, "Animation and watchdog must not retain their owner")
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(window.contentView)
    }
}
