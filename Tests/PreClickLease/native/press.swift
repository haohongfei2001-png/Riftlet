import AppKit

private final class QAPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
private final class MouseTarget: NSView {
  var down: NSEvent?
  var handledAt: Double?
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {
    handledAt = ProcessInfo.processInfo.systemUptime
    down = event
  }
}
enum Press {
  @MainActor static func measure(ack: Double, browserPID: pid_t) throws -> [String: Any] {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let panel = QAPanel(
      contentRect: NSRect(x: 80, y: 80, width: 54, height: 32),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    defer {
      panel.orderOut(nil)
      panel.close()
    }
    guard let screen = NSScreen.main else { throw Identity.Refusal("NO_SCREEN") }
    panel.setFrameOrigin(
      NSPoint(x: screen.visibleFrame.maxX - 70, y: screen.visibleFrame.minY + 20))
    panel.level = .floating
    let view = MouseTarget(frame: NSRect(x: 0, y: 0, width: 54, height: 32))
    panel.contentView = view
    panel.orderFrontRegardless()
    let windowNumber = panel.windowNumber
    guard windowNumber > 0, NSWorkspace.shared.frontmostApplication?.processIdentifier == browserPID
    else { throw Identity.Refusal("QA_BROWSER_NOT_FOREGROUND_AT_POST") }
    let tag = Int.random(in: 1000...1_000_000)
    func post(_ type: NSEvent.EventType) throws -> Double {
      let at = ProcessInfo.processInfo.systemUptime
      guard
        let event = NSEvent.mouseEvent(
          with: type, location: NSPoint(x: 20, y: 15), modifierFlags: [], timestamp: at,
          windowNumber: windowNumber, context: nil, eventNumber: tag, clickCount: 1,
          pressure: type == .leftMouseDown ? 1 : 0),
        let cg = event.cgEvent
      else { throw Identity.Refusal("NATIVE_EVENT_UNAVAILABLE") }
      cg.setIntegerValueField(.eventSourceUserData, value: Int64(tag))
      cg.postToPid(getpid())  // An event addressed only to this own harness, never the browser or current global focus.
      return at
    }
    let posted = try post(.leftMouseDown)
    let deadline = Date(timeIntervalSinceNow: 1)
    while view.down == nil && Date() < deadline {
      if let next = app.nextEvent(
        matching: .any, until: Date(timeIntervalSinceNow: 0.02), inMode: .default, dequeue: true)
      {
        app.sendEvent(next)
      }
    }
    _ = try post(.leftMouseUp)
    guard let observed = view.handledAt, let down = view.down, down.windowNumber == windowNumber,
      down.cgEvent?.getIntegerValueField(.eventSourceUserData) == Int64(tag),
      down.timestamp >= ack, observed >= down.timestamp,
      NSWorkspace.shared.frontmostApplication?.processIdentifier == browserPID
    else { throw Identity.Refusal("TARGETED_NATIVE_DOWN_NOT_CONFIRMED") }
    return [
      "origin": "CGEvent delivered exclusively to the harness PID; received by its AppKit QA view",
      "humanPhysicalMouse": "NOT_RUN", "nativeACKUptime": ack, "postedUptime": posted,
      "eventDownUptime": down.timestamp,
      "viewHandledUptime": observed, "ackBeforeMouseDown": true,
      "ackToNativeMouseDownMS": (down.timestamp - ack) * 1000,
      "appKitWindowMatched": true, "nativeEventMarkerMatched": true,
    ]
  }
}
