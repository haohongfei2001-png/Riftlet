import XCTest
import RiftletCapture
@testable import RiftletUI

final class ScreenshotEntryModelTests: XCTestCase {
    func testEveryDefaultOwnsAnchorForOneSessionAndSelectingNeverExchangesModes() {
        let expected: [(ScreenshotMode, [ScreenshotMode])] = [
            (.window, [.window, .region, .fullScreen]),
            (.region, [.region, .window, .fullScreen]),
            (.fullScreen, [.fullScreen, .region, .window])
        ]
        for (defaultMode, slots) in expected {
            var state = ScreenshotEntrySession(defaultMode: defaultMode)
            XCTAssertEqual(state.action(for: .anchor), .begin(defaultMode))
            XCTAssertNil(state.action(for: .near))
            state.setExpanded(true)
            XCTAssertEqual(state.modes, slots)
            XCTAssertEqual(state.action(for: .anchor), .cancel)
            for slot in [ScreenshotEntrySlot.near, .far, .anchor] {
                let mode = slots[slot.rawValue]
                XCTAssertEqual(state.action(for: slot), .select(mode))
                state.setMode(mode)
                XCTAssertEqual(state.modes, slots, "A mode may change role but never physical slot")
                XCTAssertEqual(state.activeSlot, slot)
                XCTAssertEqual(state.action(for: slot), .cancel)
                XCTAssertEqual(state.action(for: .more), .options)
            }
        }
    }

    func testChangingDefaultToCurrentModeDoesNotCancelOrReassignCurrentSession() {
        var state = ScreenshotEntrySession()
        state.setExpanded(true); state.setMode(.region)
        let slots = state.modes
        state.setDefaultMode(.region)
        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(state.mode, .region)
        XCTAssertEqual(state.modes, slots)
        state.setDefaultMode(.fullScreen)
        XCTAssertEqual(state.mode, .region)
        XCTAssertEqual(state.modes, slots)
        state.setExpanded(false); state.setExpanded(true)
        XCTAssertEqual(state.mode, .fullScreen)
        XCTAssertEqual(state.modes, [.fullScreen, .region, .window])
        state.setMode(.window)
        state.setExpanded(false); state.setExpanded(true)
        XCTAssertEqual(state.mode, .fullScreen, "Finishing another mode must not overwrite the preference")
    }

    func testLayoutKeepsExactAnchorAndFixedUpwardGeometryAcrossDisplayOrigins() throws {
        for origin in [CGPoint.zero, CGPoint(x: -1_440, y: -250), CGPoint(x: 1_440, y: 300)] {
            let screen = CGRect(origin: origin, size: CGSize(width: 1_440, height: 900))
            let layout = try XCTUnwrap(ScreenshotEntryLayout.make(screenFrame: screen,
                                                                  visibleFrame: screen))
            XCTAssertEqual(layout.anchor, CGPoint(x: screen.maxX - 32, y: screen.maxY - 246))
            XCTAssertEqual(layout.entryFrame.size, CGSize(width: 36, height: 36))
            XCTAssertEqual(layout.railFrame.size, CGSize(width: 36, height: 132))
            XCTAssertEqual(layout.entryFrame.midX, layout.anchor.x)
            XCTAssertEqual(layout.entryFrame.midY, layout.anchor.y)
            XCTAssertTrue(screen.contains(layout.railFrame))
            for slot in ScreenshotEntrySlot.allCases {
                let frame = layout.controlFrames[slot.rawValue]
                XCTAssertEqual(frame.midX, layout.anchor.x)
                XCTAssertEqual(frame.midY, layout.anchor.y + CGFloat(slot.rawValue) * 32)
            }
        }
    }

    func testHostAnchorClampsAsAWholeRailAndInvalidScreenProducesNoInputGeometry() throws {
        let screen = CGRect(x: -500, y: 70, width: 500, height: 400)
        let layout = try XCTUnwrap(ScreenshotEntryLayout.make(screenFrame: screen,
            visibleFrame: screen, anchor: CGPoint(x: 1_000, y: 2_000)))
        XCTAssertTrue(screen.contains(layout.railFrame))
        XCTAssertTrue(layout.controlFrames.allSatisfy { screen.contains($0) })
        XCTAssertNil(ScreenshotEntryLayout.make(screenFrame: .zero, visibleFrame: .zero))
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 100)
        XCTAssertNil(ScreenshotEntryLayout.make(screenFrame: tiny, visibleFrame: tiny))
        var invalid = ScreenshotEntryConfiguration(); invalid.slotPitch = .nan
        XCTAssertEqual(invalid.validated, ScreenshotEntryConfiguration())
    }

    private let screen = CGRect(x: 0, y: 0, width: 1_000, height: 900)
    private let anchor = CGPoint(x: 968, y: 654)

    private func initialTarget(distance: CGFloat) -> ScreenshotEntryAlphas {
        var optics = ScreenshotEntryOptics()
        optics.observe(point: CGPoint(x: anchor.x - distance, y: anchor.y), at: 1,
                       anchor: anchor, screenFrame: screen)
        return optics.target(at: 1, anchor: anchor, screenWidth: screen.width,
                             queueFrames: [], expanded: false, pressed: false, configuration: .init())
    }

    func testGlyphAndMaterialUseIndependentSpatialEnvelopes() {
        XCTAssertEqual(initialTarget(distance: 600), ScreenshotEntryAlphas())
        let early = initialTarget(distance: 460)
        XCTAssertGreaterThan(early.glyph, 0)
        XCTAssertEqual(early.surface, 0)
        let glyphFull = initialTarget(distance: 350)
        XCTAssertEqual(glyphFull.glyph, 1)
        XCTAssertGreaterThan(glyphFull.surface, 0)
        XCTAssertLessThan(glyphFull.surface, 1)
        XCTAssertEqual(initialTarget(distance: 80), ScreenshotEntryAlphas(glyph: 1, surface: 1))
    }

    func testPredictionRespondsToApproachOutsideSpatialEntryButNotDeparture() {
        var approach = ScreenshotEntryOptics(), departure = ScreenshotEntryOptics()
        approach.observe(point: CGPoint(x: 100, y: anchor.y), at: 1, anchor: anchor, screenFrame: screen)
        approach.observe(point: CGPoint(x: 200, y: anchor.y), at: 1.016, anchor: anchor, screenFrame: screen)
        departure.observe(point: CGPoint(x: 200, y: anchor.y), at: 1, anchor: anchor, screenFrame: screen)
        departure.observe(point: CGPoint(x: 100, y: anchor.y), at: 1.016, anchor: anchor, screenFrame: screen)
        let a = approach.target(at: 1.016, anchor: anchor, screenWidth: screen.width,
                                queueFrames: [], expanded: false, pressed: false, configuration: .init())
        let d = departure.target(at: 1.016, anchor: anchor, screenWidth: screen.width,
                                 queueFrames: [], expanded: false, pressed: false, configuration: .init())
        XCTAssertGreaterThan(a.glyph, 0.2)
        XCTAssertGreaterThan(a.surface, 0)
        XCTAssertLessThan(a.surface, a.glyph)
        XCTAssertEqual(d, ScreenshotEntryAlphas())
    }

    func testHysteresisRetainsStationaryVisibilityOnlyUntilWiderExitBoundary() {
        var optics = ScreenshotEntryOptics()
        optics.observe(point: anchor, at: 1, anchor: anchor, screenFrame: screen)
        _ = optics.target(at: 1, anchor: anchor, screenWidth: screen.width,
                          queueFrames: [], expanded: false, pressed: false, configuration: .init())
        optics.observe(point: CGPoint(x: anchor.x - 700, y: anchor.y), at: 2,
                       anchor: anchor, screenFrame: screen)
        let retreat = optics.target(at: 2, anchor: anchor, screenWidth: screen.width,
                                    queueFrames: [], expanded: false, pressed: false, configuration: .init())
        XCTAssertGreaterThan(retreat.glyph, 0)
        XCTAssertEqual(initialTarget(distance: 700).glyph, 0)
        XCTAssertEqual(optics.target(at: 20, anchor: anchor, screenWidth: screen.width,
                                      queueFrames: [], expanded: false, pressed: false, configuration: .init()), retreat)
        optics.observe(point: CGPoint(x: anchor.x - 901, y: anchor.y), at: 21,
                       anchor: anchor, screenFrame: screen)
        XCTAssertEqual(optics.target(at: 21, anchor: anchor, screenWidth: screen.width,
                                      queueFrames: [], expanded: false, pressed: false, configuration: .init()),
                       ScreenshotEntryAlphas())
    }

    func testCancelPreservesDisplayedAlphasWhileQueueSuppressesTheNextTarget() {
        var optics = ScreenshotEntryOptics()
        optics.observe(point: anchor, at: 1, anchor: anchor, screenFrame: screen)
        for frame in 0...90 {
            optics.advance(at: 1 + Double(frame) / 60, anchor: anchor, screenWidth: screen.width,
                           queueFrames: [], expanded: true)
        }
        let before = optics.alphas
        optics.resume(anchor: anchor, screenWidth: screen.width,
                      configuration: .init(), afterCancel: true)
        XCTAssertEqual(optics.alphas, before, "Cancel must not flash by resetting alpha to zero or one")
        let thumb = CGRect(x: anchor.x - 20, y: anchor.y - 20, width: 40, height: 40)
        XCTAssertEqual(optics.target(at: 3, anchor: anchor, screenWidth: screen.width,
                                     queueFrames: [thumb], expanded: false, pressed: false, configuration: .init()),
                       ScreenshotEntryAlphas())
        optics.advance(at: 3, anchor: anchor, screenWidth: screen.width,
                       queueFrames: [thumb], expanded: false)
        XCTAssertLessThan(optics.alphas.glyph, before.glyph)
        XCTAssertLessThan(optics.alphas.surface, before.surface)
    }

    func testOpticalRiseIsIndependentAndDraggingOrAnotherScreenCannotRevealIdleEntry() {
        var optics = ScreenshotEntryOptics()
        optics.observe(point: anchor, at: 1, anchor: anchor, screenFrame: screen)
        optics.advance(at: 1, anchor: anchor, screenWidth: screen.width, queueFrames: [], expanded: false)
        XCTAssertGreaterThan(optics.alphas.glyph, optics.alphas.surface)
        XCTAssertEqual(optics.alphas.glyph, 0.26, accuracy: 0.00001)
        XCTAssertEqual(optics.alphas.surface, 0.065, accuracy: 0.00001)
        optics.observe(point: anchor, at: 2, anchor: anchor, screenFrame: screen, pointerIsDown: true)
        XCTAssertEqual(optics.target(at: 2, anchor: anchor, screenWidth: screen.width,
                                    queueFrames: [], expanded: false, pressed: false, configuration: .init()),
                       ScreenshotEntryAlphas())
        optics.observe(point: CGPoint(x: 1_100, y: 654), at: 3, anchor: anchor, screenFrame: screen)
        XCTAssertNil(optics.point)
        XCTAssertEqual(optics.target(at: 3, anchor: anchor, screenWidth: screen.width,
                                    queueFrames: [], expanded: false, pressed: false, configuration: .init()),
                       ScreenshotEntryAlphas())
    }

    func testRapidReverseAndCaptureSuppressionKeepOneContinuousRail() {
        var rail = ScreenshotEntryRailMotion()
        rail.setExpanded(true, at: 1, duration: 0.18, animated: true)
        rail.advance(at: 1.06)
        let opening = rail.value
        XCTAssertGreaterThan(opening, 0); XCTAssertLessThan(opening, 1)
        rail.setExpanded(false, at: 1.06, duration: 0.18, animated: true)
        XCTAssertEqual(rail.value, opening)
        rail.advance(at: 1.07)
        let closing = rail.value
        rail.setExpanded(true, at: 1.07, duration: 0.18, animated: true)
        XCTAssertEqual(rail.value, closing)
        rail.shiftClock(by: 10)
        rail.advance(at: 11.07)
        XCTAssertEqual(rail.value, closing, accuracy: 0.000001)
        rail.advance(at: 12)
        XCTAssertEqual(rail.value, 1)
        XCTAssertTrue(rail.isSettled)
        rail.setExpanded(false, at: 12, duration: 0.18, animated: false)
        XCTAssertEqual(rail.value, 0)
    }

    func testCancelCoverCanBeInterruptedWhileModeActionIsAlreadyAtDestination() {
        var session = ScreenshotEntrySession()
        var cover = ScreenshotEntryCancelMotion()
        session.setExpanded(true)
        session.setMode(.fullScreen)
        cover.move(to: session.activeSlot, at: 1, animated: true)
        XCTAssertEqual(cover.value, 0)
        XCTAssertEqual(session.action(for: .far), .cancel)
        XCTAssertEqual(session.action(for: .anchor), .select(.window))
        cover.advance(at: 1.05)
        XCTAssertEqual(cover.value, 1, accuracy: 0.000001)
        session.setMode(.region)
        cover.move(to: session.activeSlot, at: 1.05, animated: true)
        XCTAssertEqual(cover.value, 1, accuracy: 0.000001)
        XCTAssertEqual(session.action(for: .near), .cancel)
        XCTAssertEqual(session.modes, [.window, .region, .fullScreen])
        cover.advance(at: 1.2)
        XCTAssertEqual(cover.value, 1)
    }
}
