@preconcurrency import AppKit
import XCTest

/// Synthetic input stays within the test process. Trackpad and mechanical
/// wheel events use their separate native AppKit representations.
@MainActor
enum TimelineWheelFixture {
    static func event(in window: NSWindow, units: CGScrollEventUnit,
                      delta: Int32, phase: CGScrollPhase? = nil) throws -> NSEvent {
        let basis = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: units,
                                         wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        // A Quartz wheel by itself has no NSEvent.windowNumber, even when its
        // under-pointer fields name a window. Preserve AppKit's window binding.
        let point = window.convertPoint(fromScreen: CGPoint(x: window.frame.midX, y: window.frame.midY))
        let bound = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0)?.cgEvent)
        bound.type = .scrollWheel
        for field in [CGEventField.scrollWheelEventIsContinuous, .scrollWheelEventDeltaAxis1] {
            bound.setIntegerValueField(field, value: basis.getIntegerValueField(field))
        }
        bound.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1,
                                  value: basis.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        bound.setIntegerValueField(.scrollWheelEventPointDeltaAxis1,
                                   value: basis.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        if let phase { bound.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue)) }
        let event = try XCTUnwrap(NSEvent(cgEvent: bound))
        XCTAssertTrue(event.window === window)
        XCTAssertEqual(event.windowNumber, window.windowNumber)
        XCTAssertEqual(event.type, .scrollWheel)
        XCTAssertEqual(event.hasPreciseScrollingDeltas, units == .pixel)
        XCTAssertEqual(event.scrollingDeltaY, CGFloat(delta))
        return event
    }

    static func trackpad(in window: NSWindow, delta: Int32,
                         deliver: (NSEvent) -> Void) throws {
        let begin = try event(in: window, units: .pixel, delta: 0, phase: .began)
        let change = try event(in: window, units: .pixel, delta: delta, phase: .changed)
        let end = try event(in: window, units: .pixel, delta: 0, phase: .ended)
        XCTAssertEqual([begin.phase, change.phase, end.phase], [.began, .changed, .ended])
        // NSScrollView may track inside scrollWheel(with:). The rest of the
        // gesture must be available independently while AppKit owns that loop.
        let app = NSApplication.shared
        let sent = DispatchGroup()
        sent.enter()
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.03)
            app.postEvent(change, atStart: false)
            Thread.sleep(forTimeInterval: 0.03)
            app.postEvent(end, atStart: false)
            sent.leave()
        }
        deliver(begin)
        // Some AppKit versions return before the later phases. Consume only
        // the remaining events for this original test window in normal order.
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if let next = app.nextEvent(matching: .scrollWheel,
               until: Date().addingTimeInterval(0.012), inMode: .default, dequeue: true) {
                guard next.window === window else {
                    app.postEvent(next, atStart: true)
                    XCTFail("Another window received the test gesture")
                    return
                }
                deliver(next)
                if next.phase == .ended { break }
            } else if sent.wait(timeout: .now()) == .success { break }
        }
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
