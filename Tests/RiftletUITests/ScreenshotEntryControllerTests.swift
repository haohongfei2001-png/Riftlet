import AppKit
import XCTest
import RiftletCapture
@testable import RiftletUI

/// Direct AppKit callback/geometry checks. They do not claim physical input,
/// compositor appearance, active-draft preservation or capture exclusion.
final class ScreenshotEntryControllerTests: XCTestCase {
    @MainActor private func controller(defaultMode: ScreenshotMode = .window) throws -> ScreenshotEntryController {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first, "Native UI checks require an AppKit screen")
        let controller = ScreenshotEntryController(defaultMode: defaultMode)
        controller.configure(screen: screen)
        return controller
    }

    @MainActor private func window(_ number: Int) throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0.windowNumber == number })
    }

    @MainActor private func view(_ controller: ScreenshotEntryController,
                                 slot: ScreenshotEntrySlot) throws -> NSView {
        let control = controller.diagnosticSnapshot.controls[slot.rawValue]
        return try XCTUnwrap(try window(control.windowNumber).contentView)
    }

    @MainActor private func press(_ controller: ScreenshotEntryController,
                                  slot: ScreenshotEntrySlot) throws -> Bool {
        try view(controller, slot: slot).accessibilityPerformPress()
    }

    @MainActor private func event(_ type: NSEvent.EventType, window: NSWindow,
                                   time: TimeInterval) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type,
            location: CGPoint(x: window.frame.width / 2, y: window.frame.height / 2),
            modifierFlags: [], timestamp: time, windowNumber: window.windowNumber,
            context: nil, eventNumber: Int(time * 10), clickCount: 1, pressure: 1))
    }

    @MainActor func testEntryBeginsImmediatelyAndOnlySelectedFixedSlotBecomesCancel() throws {
        let controller = try controller(); defer { controller.close() }
        var began: [ScreenshotMode] = [], selected: [ScreenshotMode] = [], cancelled = 0
        controller.onBegin = { began.append($0) }
        controller.onMode = { selected.append($0) }
        controller.onCancel = { cancelled += 1 }
        let before = controller.diagnosticSnapshot.controls
        XCTAssertTrue(try press(controller, slot: .anchor))
        XCTAssertEqual(began, [.window])
        XCTAssertTrue(controller.isExpanded)
        XCTAssertTrue(controller.diagnosticSnapshot.controls[0].isCancel)
        // No run loop/animation wait: a newly exposed mode is already actionable.
        XCTAssertTrue(try press(controller, slot: .far))
        let switched = controller.diagnosticSnapshot
        XCTAssertEqual(selected, [.fullScreen])
        XCTAssertEqual(switched.mode, .fullScreen)
        XCTAssertFalse(switched.controls[0].isCancel)
        XCTAssertTrue(switched.controls[2].isCancel)
        XCTAssertEqual(switched.controls.map(\.mode), [.window, .region, .fullScreen, nil])
        XCTAssertEqual(switched.controls.map(\.frame), before.map(\.frame))
        XCTAssertEqual(switched.controls.map(\.windowNumber), before.map(\.windowNumber))
        XCTAssertEqual(cancelled, 0, "A switch event must not be reinterpreted as cancel")
        XCTAssertTrue(try press(controller, slot: .far))
        XCTAssertEqual(cancelled, 1)
        XCTAssertFalse(controller.isExpanded)
        XCTAssertTrue(try press(controller, slot: .anchor), "Reopening does not wait for closing animation")
        XCTAssertEqual(began, [.window, .window])
    }

    @MainActor func testSettingsAffectOnlyNextSessionAndNoSuccessModeMemoryExists() throws {
        let controller = try controller(); defer { controller.close() }
        controller.setExpanded(true, animated: false)
        let fixed = controller.diagnosticSnapshot.controls.map(\.mode)
        controller.setMode(.region)
        controller.setDefaultMode(.region)
        XCTAssertTrue(controller.isExpanded)
        XCTAssertEqual(controller.mode, .region)
        XCTAssertEqual(controller.diagnosticSnapshot.controls.map(\.mode), fixed)
        controller.setDefaultMode(.fullScreen)
        XCTAssertEqual(controller.mode, .region)
        XCTAssertEqual(controller.diagnosticSnapshot.controls.map(\.mode), fixed)
        controller.setExpanded(false, animated: false)
        controller.setExpanded(true, animated: false)
        XCTAssertEqual(controller.mode, .fullScreen)
        XCTAssertEqual(controller.diagnosticSnapshot.controls.map(\.mode), [.fullScreen, .region, .window, nil])
        controller.setMode(.window)
        controller.setExpanded(false, animated: false)
        controller.setExpanded(true, animated: false)
        XCTAssertEqual(controller.mode, .fullScreen)
        XCTAssertEqual(controller.defaultMode, .fullScreen)
    }

    @MainActor func testCaptureSuppressionPreservesEverySessionAndOpticalValue() async throws {
        let controller = try controller(); defer { controller.close() }
        controller.setExpanded(true, animated: false)
        controller.setMode(.region)
        let before = controller.diagnosticSnapshot
        controller.setCaptureSuppressed(true)
        let suppressed = controller.diagnosticSnapshot
        XCTAssertTrue(suppressed.isExpanded)
        XCTAssertEqual(suppressed.mode, before.mode)
        XCTAssertEqual(suppressed.controls.map(\.mode), before.controls.map(\.mode))
        XCTAssertEqual(suppressed.glyphAlpha, before.glyphAlpha)
        XCTAssertEqual(suppressed.surfaceAlpha, before.surfaceAlpha)
        XCTAssertEqual(suppressed.expansion, before.expansion)
        XCTAssertEqual(suppressed.cancelSlotPosition, before.cancelSlotPosition)
        XCTAssertTrue(controller.inputFrames.isEmpty)
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(try window(before.visualWindowNumber).isVisible)
        for control in before.controls { XCTAssertFalse(try window(control.windowNumber).isVisible) }
        let afterWait = controller.diagnosticSnapshot
        XCTAssertEqual(afterWait.glyphAlpha, before.glyphAlpha)
        XCTAssertEqual(afterWait.surfaceAlpha, before.surfaceAlpha)
        controller.setCaptureSuppressed(false)
        let restored = controller.diagnosticSnapshot
        XCTAssertTrue(restored.isExpanded)
        XCTAssertEqual(restored.mode, before.mode)
        XCTAssertEqual(restored.glyphAlpha, before.glyphAlpha)
        XCTAssertEqual(restored.surfaceAlpha, before.surfaceAlpha)
        XCTAssertEqual(restored.expansion, before.expansion)
        XCTAssertEqual(restored.cancelSlotPosition, before.cancelSlotPosition)
        XCTAssertEqual(restored.controls.map(\.windowNumber), before.controls.map(\.windowNumber))
        XCTAssertEqual(controller.inputFrames.count, 4)
    }

    @MainActor func testBusyKeepsExpandedCancelAvailableAndOptionsResetOnlyForNewSession() throws {
        let controller = try controller(defaultMode: .region); defer { controller.close() }
        var cancelled = 0; controller.onCancel = { cancelled += 1 }
        controller.setExpanded(true, animated: false)
        controller.setMode(.fullScreen)
        controller.setOptions(InteractiveScreenshotOptions(delay: 5, showPointer: true, editAfter: true))
        controller.setBusy(true)
        XCTAssertTrue(controller.isExpanded)
        XCTAssertEqual(controller.options.delay, 5)
        XCTAssertTrue(controller.options.editAfter)
        XCTAssertEqual(controller.diagnosticSnapshot.controls.filter(\.isEnabled).map(\.slot), [.far])
        XCTAssertFalse(try press(controller, slot: .near))
        XCTAssertFalse(try press(controller, slot: .more))
        XCTAssertTrue(try press(controller, slot: .far))
        XCTAssertEqual(cancelled, 1)
        controller.setExpanded(true, animated: false)
        XCTAssertEqual(controller.mode, .region)
        XCTAssertEqual(controller.options, InteractiveScreenshotOptions())
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor func testDecorativeRailIsTransparentAndOnlySmallNonactivatingIslandsTakeInput() throws {
        let controller = try controller(); defer { controller.close() }
        controller.setExpanded(true, animated: false)
        let snapshot = controller.diagnosticSnapshot
        let decorative = try window(snapshot.visualWindowNumber)
        XCTAssertTrue(decorative.ignoresMouseEvents)
        for control in snapshot.controls {
            let panel = try window(control.windowNumber)
            XCTAssertFalse(panel.canBecomeKey)
            XCTAssertFalse(panel.canBecomeMain)
            XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
            XCTAssertFalse(panel.ignoresMouseEvents)
            XCTAssertLessThanOrEqual(control.frame.width, 36)
            XCTAssertLessThanOrEqual(control.frame.height, 36)
        }
        let side = CGPoint(x: snapshot.controls[0].frame.minX - 1,
                           y: snapshot.controls[2].frame.midY)
        XCTAssertFalse(controller.inputFrames.contains { $0.contains(side) })
        let gap = CGPoint(x: snapshot.controls[1].frame.midX,
                          y: (snapshot.controls[1].frame.maxY + snapshot.controls[2].frame.minY) / 2)
        XCTAssertFalse(controller.inputFrames.contains { $0.contains(gap) })
        controller.setHidden(true)
        XCTAssertTrue(controller.inputFrames.isEmpty)
        XCTAssertTrue(controller.isExpanded, "Temporary hide is separate from session cancellation")
        for control in snapshot.controls { XCTAssertFalse(try window(control.windowNumber).isVisible) }
    }

    @MainActor func testReduceMotionChangeSettlesCurrentVisualTargetsWithoutChangingSessionOrCallbacks() async throws {
        let controller = try controller(); defer { controller.close() }
        var actions = 0
        controller.onBegin = { _ in actions += 1 }; controller.onMode = { _ in actions += 1 }
        controller.onCancel = { actions += 1 }; controller.onOptions = { _ in actions += 1 }
        controller.setExpanded(true)
        controller.setMode(.fullScreen)
        controller.setBusy(true)
        controller.setOptions(InteractiveScreenshotOptions(delay: 5, showPointer: true, editAfter: true))
        let original = controller.diagnosticSnapshot
        controller.applyAccessibilityDisplayOptions(reduceMotion: true)
        let settled = controller.diagnosticSnapshot
        XCTAssertEqual(settled.expansion, 1)
        XCTAssertEqual(settled.cancelSlotPosition, 2)
        XCTAssertTrue(settled.isExpanded); XCTAssertTrue(settled.isBusy)
        XCTAssertEqual(settled.mode, .fullScreen)
        XCTAssertEqual(settled.controls.map(\.frame), original.controls.map(\.frame))
        XCTAssertEqual(settled.controls.map(\.windowNumber), original.controls.map(\.windowNumber))
        XCTAssertEqual(controller.options.delay, 5)
        XCTAssertTrue(controller.options.showPointer); XCTAssertTrue(controller.options.editAfter)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.diagnosticSnapshot.expansion, 1)
        XCTAssertEqual(controller.diagnosticSnapshot.cancelSlotPosition, 2)
        XCTAssertEqual(actions, 0, "A display preference never starts, cancels or changes capture")
        let decorative = try window(controller.diagnosticSnapshot.visualWindowNumber)
        controller.close()
        let closed = controller.diagnosticSnapshot
        controller.applyAccessibilityDisplayOptions(reduceMotion: true)
        XCTAssertEqual(controller.diagnosticSnapshot.expansion, closed.expansion)
        XCTAssertTrue(controller.inputFrames.isEmpty)
        XCTAssertFalse(decorative.isVisible)
    }

    @MainActor func testGlassBorderUsesCurrentNativeBackingScale() throws {
        let controller = try controller(); defer { controller.close() }
        controller.setExpanded(true, animated: false)
        let decorative = try window(controller.diagnosticSnapshot.visualWindowNumber)
        func children(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(children) }
        let glass = try XCTUnwrap(children(try XCTUnwrap(decorative.contentView)).compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertEqual(glass.material, .popover)
        XCTAssertEqual(glass.blendingMode, .behindWindow)
        let expected: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 1 / decorative.backingScaleFactor
        XCTAssertEqual(try XCTUnwrap(glass.layer).borderWidth, expected, accuracy: 0.0001)
    }

    @MainActor func testEscapeDuringHeldControlCannotReopenOnItsLaterMouseUp() throws {
        let controller = try controller(); defer { controller.close() }
        var began = 0; controller.onBegin = { _ in began += 1 }
        controller.setExpanded(true, animated: false)
        let entry = try view(controller, slot: .anchor)
        let panel = try XCTUnwrap(entry.window)
        entry.mouseDown(with: try event(.leftMouseDown, window: panel, time: 10))
        controller.setExpanded(false, animated: false) // host's Esc path
        entry.mouseUp(with: try event(.leftMouseUp, window: panel, time: 10.1))
        XCTAssertFalse(controller.isExpanded)
        XCTAssertEqual(began, 0)
        controller.close()
        XCTAssertFalse(entry.accessibilityPerformPress(), "Retained closed views have no action authority")
    }

    @MainActor func testInitiallyDisabledEntryOwnsNoListenersAndCanBeEnabledWithoutRecreation() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let controller = ScreenshotEntryController(defaultMode: .region, isEnabled: false)
        defer { controller.close() }
        controller.configure(screen: screen)
        var began: [ScreenshotMode] = []
        controller.onBegin = { began.append($0) }
        let disabled = controller.diagnosticSnapshot
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertEqual(disabled.pointerMonitorCount, 0)
        XCTAssertFalse(disabled.hasScheduledFrame)
        XCTAssertFalse(disabled.controls.contains(where: \.isEnabled))
        XCTAssertTrue(controller.inputFrames.isEmpty)
        XCTAssertFalse(try press(controller, slot: .anchor))
        controller.setExpanded(true)
        controller.setBusy(true)
        controller.setCaptureSuppressed(true)
        XCTAssertFalse(controller.isExpanded)
        XCTAssertFalse(controller.isBusy)
        XCTAssertFalse(controller.isCaptureSuppressed)
        XCTAssertTrue(began.isEmpty)
        for control in disabled.controls { XCTAssertFalse(try window(control.windowNumber).isVisible) }

        controller.setEnabled(true)
        XCTAssertGreaterThan(controller.diagnosticSnapshot.pointerMonitorCount, 0)
        XCTAssertLessThanOrEqual(controller.diagnosticSnapshot.pointerMonitorCount, 2)
        XCTAssertEqual(controller.diagnosticSnapshot.controls.map(\.windowNumber), disabled.controls.map(\.windowNumber))
        XCTAssertFalse(controller.isExpanded, "Re-enable never resumes the earlier capture session")
        XCTAssertTrue(try press(controller, slot: .anchor))
        XCTAssertEqual(began, [.region])
        XCTAssertEqual(controller.defaultMode, .region)
    }

    @MainActor func testDisableStopsAnimationsAndLateRestoreCannotRevealTheEntry() async throws {
        let controller = try controller(); defer { controller.close() }
        var actions = 0
        controller.onBegin = { _ in actions += 1 }; controller.onCancel = { actions += 1 }
        controller.setExpanded(true)
        controller.setMode(.fullScreen)
        controller.setCaptureSuppressed(true)
        controller.setEnabled(false)
        // Exposure/permission callbacks may have been queued before the switch.
        controller.setCaptureSuppressed(false)
        controller.setExpanded(true)
        controller.setBusy(true)
        controller.configure(screen: NSScreen.screens.first)
        controller.applyAccessibilityDisplayOptions(reduceMotion: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        let disabled = controller.diagnosticSnapshot
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertFalse(disabled.isExpanded)
        XCTAssertFalse(disabled.isBusy)
        XCTAssertEqual(disabled.expansion, 0)
        XCTAssertEqual(disabled.cancelSlotPosition, 0)
        XCTAssertEqual(disabled.pointerMonitorCount, 0)
        XCTAssertFalse(disabled.hasScheduledFrame)
        XCTAssertEqual(disabled.glyphAlpha, 0)
        XCTAssertEqual(disabled.surfaceAlpha, 0)
        XCTAssertFalse(try window(disabled.visualWindowNumber).isVisible)
        for control in disabled.controls { XCTAssertFalse(try window(control.windowNumber).isVisible) }
        XCTAssertTrue(controller.inputFrames.isEmpty)
        XCTAssertEqual(actions, 0, "Disabling UI alone never starts a new capture")
    }

    @MainActor func testDisableDuringHeldControlPreventsReleaseAfterReenableFromBeginningCapture() throws {
        let controller = try controller(); defer { controller.close() }
        controller.setExpanded(true, animated: false)
        var began = 0, selected = 0
        controller.onBegin = { _ in began += 1 }; controller.onMode = { _ in selected += 1 }
        let held = try view(controller, slot: .near)
        let panel = try XCTUnwrap(held.window)
        held.mouseDown(with: try event(.leftMouseDown, window: panel, time: 20))
        controller.setEnabled(false)
        controller.setEnabled(true)
        controller.setExpanded(true, animated: false)
        held.mouseUp(with: try event(.leftMouseUp, window: panel, time: 20.1))
        XCTAssertEqual(controller.mode, .window)
        XCTAssertEqual(began, 0)
        XCTAssertEqual(selected, 0)
        XCTAssertTrue(try press(controller, slot: .near), "A fresh user action remains usable")
        XCTAssertEqual(controller.mode, .region)
        XCTAssertEqual(selected, 1)
    }

    @MainActor func testRepeatedTogglesDoNotAccumulateListenersOrOverrideIndependentHide() throws {
        let controller = try controller(); defer { controller.close() }
        let expectedMonitors = controller.diagnosticSnapshot.pointerMonitorCount
        XCTAssertGreaterThan(expectedMonitors, 0)
        controller.setDefaultMode(.fullScreen)
        for _ in 0..<12 {
            controller.setEnabled(false)
            controller.setEnabled(false)
            XCTAssertEqual(controller.diagnosticSnapshot.pointerMonitorCount, 0)
            XCTAssertFalse(controller.diagnosticSnapshot.hasScheduledFrame)
            controller.setHidden(true)
            controller.setEnabled(true)
            XCTAssertTrue(controller.isHidden)
            XCTAssertEqual(controller.diagnosticSnapshot.pointerMonitorCount, 0)
            XCTAssertTrue(controller.inputFrames.isEmpty)
            controller.setHidden(false)
            controller.setEnabled(true)
            XCTAssertEqual(controller.diagnosticSnapshot.pointerMonitorCount, expectedMonitors)
            XCTAssertEqual(controller.defaultMode, .fullScreen)
            XCTAssertFalse(controller.isExpanded)
        }
        controller.close()
        controller.setEnabled(true)
        controller.setHidden(false)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.diagnosticSnapshot.pointerMonitorCount, 0)
        XCTAssertFalse(controller.diagnosticSnapshot.hasScheduledFrame)
    }

    @MainActor func testNewGeometryAfterReleaseSupersedesDeferredHeldGeometry() async throws {
        let controller=try controller();defer{controller.close()}
        let screen=try XCTUnwrap(NSScreen.screens.first)
        let f=screen.visibleFrame
        let a=CGPoint(x:f.midX,y:f.midY),b=CGPoint(x:f.midX-80,y:f.midY),c=CGPoint(x:f.midX+80,y:f.midY)
        controller.configure(screen:screen,anchor:a)
        let input=try view(controller,slot:.anchor), panel=try XCTUnwrap(input.window)
        input.mouseDown(with:try event(.leftMouseDown,window:panel,time:10))
        let original=controller.diagnosticSnapshot.controls.map(\.frame)
        controller.configure(screen:screen,anchor:b)
        XCTAssertEqual(controller.diagnosticSnapshot.controls.map(\.frame),original)
        input.mouseUp(with:try event(.leftMouseUp,window:panel,time:10.1))
        controller.configure(screen:screen,anchor:c)
        let latest=controller.diagnosticSnapshot.controls.map(\.frame)
        XCTAssertNotEqual(latest,original)
        try await Task.sleep(nanoseconds:30_000_000)
        XCTAssertEqual(controller.diagnosticSnapshot.controls.map(\.frame),latest,"Queued release callback must not restore older B after newer C")
    }

}
