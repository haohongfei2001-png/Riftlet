import AppKit
import XCTest

/// Synthetic input stays within the test process. Trackpad and mechanical
/// wheel events use their separate native AppKit representations.
@MainActor
enum TimelineWheelFixture {
    static func event(in window: NSWindow, units: CGScrollEventUnit,
                      delta: Int32, phase: CGScrollPhase? = nil) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: units,
                                      wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let display = try XCTUnwrap(NSScreen.screens.first)
        cg.location = CGPoint(x: center.x, y: display.frame.maxY - center.y)
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                                value: Int64(window.windowNumber))
        if let phase { cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue)) }
        let event = try XCTUnwrap(NSEvent(cgEvent: cg))
        XCTAssertEqual(event.hasPreciseScrollingDeltas, units == .pixel)
        XCTAssertEqual(event.scrollingDeltaY, CGFloat(delta))
        return event
    }

    /// AppKit may update its clip view on a later display tick. Collect the
    /// intermediate visible cells instead of assuming the display refresh rate.
    @discardableResult
    static func wait(until condition: () -> Bool, sampling: () -> Void = {}) -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            sampling()
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.004))
        } while ProcessInfo.processInfo.systemUptime < end
        sampling()
        return condition()
    }
}
