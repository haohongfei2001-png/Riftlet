import AppKit
import WebKit

/// This browser stays alive when the test-composed Riftlet process quits and restarts.
@MainActor final class Page: NSObject, NSApplicationDelegate, WKNavigationDelegate {
  let root: URL
  let file: URL
  var window: NSWindow!
  var web: WKWebView!
  var timer: Timer?
  var busy = false
  var started = false
  init(_ root: URL, _ file: URL) {
    self.root = root
    self.file = file
  }
  func applicationDidFinishLaunching(_ n: Notification) {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    window = NSWindow(
      contentRect: NSRect(x: 220, y: 180, width: 720, height: 450),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Riftlet controlled recovery fixture"
    window.contentView = web
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeFirstResponder(web)
    web.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(
      action.request.url?.standardizedFileURL == file.standardizedFileURL
        && action.targetFrame?.isMainFrame == true ? .allow : .cancel)
  }
  func write(_ value: Any, _ url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
      .write(to: url, options: .atomic)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard !started else { return }
    started = true
    let native: [String: Any] = [
      "applicationID": "com.google.Chrome",
      "sessionID": "owned-\(ProcessInfo.processInfo.processIdentifier)",
      "windowID": String(window.windowNumber), "tabID": "1",
    ]
    try! write(native, root.appendingPathComponent("native.json"))
    timer = .scheduledTimer(withTimeInterval: 0.012, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.tick() }
    }
  }
  func tick() async {
    guard !busy else { return }
    let queue = root.appendingPathComponent("page-in")
    guard
      let file =
        (try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil))?
        .filter({ $0.pathExtension == "json" }).sorted(by: {
          $0.lastPathComponent < $1.lastPathComponent
        }).first
    else { return }
    busy = true
    defer { busy = false }
    let claimed = root.appendingPathComponent("page-inflight").appendingPathComponent(
      file.lastPathComponent)
    guard (try? FileManager.default.moveItem(at: file, to: claimed)) != nil else { return }
    let out = root.appendingPathComponent("page-out").appendingPathComponent(file.lastPathComponent)
    do {
      let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: claimed)) as! [String: Any]
      let native =
        try JSONSerialization.jsonObject(
          with: Data(contentsOf: root.appendingPathComponent("native.json"))) as! [String: Any]
      var args: [String: Any] = [:]
      let program: String
      switch obj["action"] as? String {
      case "command":
        args = ["cmd": obj["command"]!, "native": native]
        program = "return JSON.stringify(await recoveryFixture.command(cmd,native))"
      case "snapshot": program = "return JSON.stringify(await recoveryFixture.snapshot())"
      case "setNext":
        args = ["mode": obj["mode"]!]
        program = "return JSON.stringify(recoveryFixture.setNext(mode))"
      case "transition":
        args = ["mode": obj["mode"]!, "id": obj["id"]!]
        program = "return JSON.stringify(recoveryFixture.transition(id,mode))"
      case "navigate": program = "return JSON.stringify(recoveryFixture.navigate())"
      case "focus":
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(web)
        program =
          "return JSON.stringify({focused:document.hasFocus(),original:(await recoveryFixture.snapshot()).originalDraft})"
      case "quit":
        try write(["ok": true], out)
        NSApp.terminate(nil)
        return
      default: throw CocoaError(.coderInvalidValue)
      }
      let result = try await web.callAsyncJavaScript(
        program, arguments: args, in: nil, contentWorld: .page)
      guard let string = result as? String else { throw CocoaError(.coderInvalidValue) }
      let payload = try JSONSerialization.jsonObject(
        with: Data(string.utf8), options: .fragmentsAllowed)
      try write(["ok": true, "value": payload], out)
    } catch {
      let e = error as NSError
      let msg = (e.userInfo["WKJavaScriptExceptionMessage"] as? String) ?? ""
      let code = msg.hasPrefix("Error: ") ? String(msg.dropFirst(7)) : msg
      try? write(["ok": false, "error": String(describing: error), "code": code], out)
    }
  }
}
MainActor.assumeIsolated {
  let app = NSApplication.shared
  app.setActivationPolicy(.regular)
  let page = Page(
    URL(fileURLWithPath: CommandLine.arguments[1]), URL(fileURLWithPath: CommandLine.arguments[2]))
  app.delegate = page
  app.run()
}
