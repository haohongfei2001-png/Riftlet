import AppKit

/// Target discovery and event delivery are confined to windows of this test process.
/// All control actions beyond opening the product menu travel through NSApplication's normal event queue.
@MainActor final class FixtureUI {
  static let shared = FixtureUI()
  private var timer: Timer?
  private var monitor: Any?
  private var history: (() -> Void)?
  private var approach: (() -> Void)?
  private var binding: (() -> String?)?
  func start(
    binding: @escaping () -> String?, approach: @escaping () -> Void, history: @escaping () -> Void
  ) {
    self.binding = binding
    self.approach = approach
    self.history = history
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
      FixtureMailbox.log([
        "event": "appkitDelivered", "type": Int(event.type.rawValue), "window": event.windowNumber,
        "uptime": event.timestamp,
      ])
      return event
    }
    timer = .scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    FixtureMailbox.log([
      "event": "productUIReady", "pid": ProcessInfo.processInfo.processIdentifier,
    ])
  }
  func flatten(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(flatten) }
  func tick() {
    let root = FixtureMailbox.root
    let dir = root.appendingPathComponent("ui-in")
    guard
      let f =
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
        .first(where: { $0.pathExtension == "json" })
    else { return }
    let dest = root.appendingPathComponent("ui-inflight").appendingPathComponent(
      f.lastPathComponent)
    guard (try? FileManager.default.moveItem(at: f, to: dest)) != nil else { return }
    var reply: [String: Any] = ["ok": false]
    defer {
      try? JSONSerialization.data(withJSONObject: reply, options: .sortedKeys).write(
        to: root.appendingPathComponent("ui-out").appendingPathComponent(f.lastPathComponent),
        options: .atomic)
    }
    guard let req = try? FixtureMailbox.object(dest), let action = req["action"] as? String else {
      return
    }
    let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
    let views = windows.flatMap { flatten($0.contentView!) }.filter {
      !$0.isHiddenOrHasHiddenAncestor
    }
    let buttons = views.compactMap { $0 as? NSButton }
    let rows = windows.filter {
      String(describing: type(of: $0.contentView!)) == "RiftInputView" && !$0.ignoresMouseEvents
    }.sorted { $0.frame.width > $1.frame.width }
    let tables = views.compactMap { $0 as? NSTableView }.filter { $0.numberOfRows > 0 }
    let labels = views.compactMap { $0 as? NSTextField }.map(\.stringValue)
    if action == "read" {
      reply = [
        "ok": true, "binding": binding?() ?? "",
        "buttons": buttons.map {
          ["id": $0.identifier?.rawValue ?? "", "title": $0.title, "enabled": $0.isEnabled]
        }, "tables": tables.map(\.numberOfRows), "rows": rows.map(\.windowNumber), "text": labels,
        "sheets": windows.filter { $0.sheetParent != nil }.count,
      ]
      return
    }
    if action == "approach" {
      approach?()
      reply = ["ok": true]
      return
    }
    if action == "history" {
      history?()
      reply = ["ok": true]
      return
    }
    if action == "quit" {
      reply = ["ok": true]
      DispatchQueue.main.async { NSApp.terminate(nil) }
      return
    }
    var view: NSView?
    var point: NSPoint?
    switch action {
    case "tray":
      // A fresh case has one captured asset. Reject ambiguous image windows.
      guard let first = rows.first, rows.count <= 2,
        rows.count == 1 || first.frame.width > rows[1].frame.width
      else { break }
      view = first.contentView
    case "table":
      guard tables.count == 1, tables[0].numberOfRows == 1 else { break }
      view = tables[0]
      let r = tables[0].rect(ofRow: 0)
      point = NSPoint(x: r.midX, y: r.midY)
    case "button":
      let found = buttons.filter {
        $0.isEnabled
          && ($0.identifier?.rawValue == req["key"] as? String || $0.title == req["key"] as? String)
      }
      guard found.count == 1 else { break }
      view = found[0]
    default: break
    }
    guard let view, let window = view.window else {
      reply["error"] = "no unique enabled control"
      return
    }
    let center = point ?? NSPoint(x: view.bounds.midX, y: view.bounds.midY)
    if !view.visibleRect.contains(center) {
      _ = view.scrollToVisible(view.bounds)
      window.contentView?.layoutSubtreeIfNeeded()
    }
    let local = view.convert(center, to: nil)
    let hit = window.contentView?.hitTest(
      window.contentView!.superview?.convert(local, from: nil) ?? local)
    guard let hit, hit === view || hit.isDescendant(of: view) else {
      reply["error"] = "own target not hit"
      reply["target"] = String(describing: type(of: view))
      reply["local"] = NSStringFromPoint(local)
      reply["visible"] = NSStringFromRect(view.visibleRect)
      reply["hit"] = hit.map { String(describing: type(of: $0)) } ?? "nil"
      return
    }
    let ts = ProcessInfo.processInfo.systemUptime
    guard
      let down = NSEvent.mouseEvent(
        with: .leftMouseDown, location: local, modifierFlags: [], timestamp: ts,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
      let up = NSEvent.mouseEvent(
        with: .leftMouseUp, location: local, modifierFlags: [], timestamp: ts + 0.006,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
    else { return }
    NSApp.postEvent(down, atStart: false)
    NSApp.postEvent(up, atStart: false)
    reply = [
      "ok": true, "action": action, "window": window.windowNumber, "uptime": ts,
      "target": String(describing: type(of: view)),
    ]
  }
}
