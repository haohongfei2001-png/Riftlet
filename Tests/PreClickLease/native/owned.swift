import AppKit
import Carbon

@testable import RiftletAdapters

// Suite-local commands for an independently authenticated Chromium process.
// The new-window reply and its sole tab are verified before the only URL write.
// There are no global keys, OS-coordinate clicks or arbitrary script inputs.
enum Owned {
  typealias E = NSAppleEventDescriptor
  static func request(
    _ proc: ChromeProcessIdentity, _ cls: String, _ event: String, _ params: [String: E]
  ) throws -> E {
    guard proc.isCurrent() else { throw Identity.Refusal("PROCESS_CHANGED") }
    let a = E(
      eventClass: Identity.code(cls), eventID: Identity.code(event),
      targetDescriptor: .init(processIdentifier: proc.pid), returnID: -1, transactionID: 0)
    for (k, v) in params { a.setParam(v, forKeyword: Identity.code(k)) }
    let r = try a.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: 2)
    try Identity.verify(
      r.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0, "OWNED_" + event)
    guard proc.isCurrent() else { throw Identity.Refusal("PROCESS_CHANGED") }
    return r.paramDescriptor(forKeyword: keyDirectObject) ?? .null()
  }
  static func valid(_ text: String) -> Bool {
    guard let u = URLComponents(string: text), u.scheme == "http", u.host == "127.0.0.1",
      u.port != nil, u.query == nil, u.fragment == nil, u.user == nil, u.password == nil
    else { return false }
    return u.path.range(of: "^/[0-9a-f]{48}/$", options: .regularExpression) != nil
  }
  static func tabIDs(_ proc: ChromeProcessIdentity, window: E) throws -> [String] {
    let all = try Identity.object(
      "CrTb", "indx", ChromeHistoryTabSelection.allTabsOrdinal(), window)
    let ids = try Identity.get(proc, Identity.property("ID  ", all))
    guard ids.descriptorType == typeAEList else { throw Identity.Refusal("TAB_LIST_UNAVAILABLE") }
    return try (0..<ids.numberOfItems).map { i in
      guard let s = ids.atIndex(i + 1)?.stringValue, let n = Int64(s), n > 0, String(n) == s else {
        throw Identity.Refusal("TAB_LIST_INVALID")
      }
      return s
    }
  }
  static func write(_ value: [String: Any], to file: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
      to: file, options: .atomic)
  }
  @MainActor static func create(_ proc: ChromeProcessIdentity, _ args: [String]) throws -> [String:
    Any]
  {
    guard args.count == 5, valid(args[3]),
      let before = try JSONSerialization.jsonObject(
        with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as? [String: Any],
      before["sessionID"] as? String == proc.session, let ids = before["windowIDs"] as? [String],
      try Identity.windows(proc) == Set(ids)
    else { throw Identity.Refusal("IDENTITY_CHANGED_BEFORE_CREATION") }
    let output = URL(fileURLWithPath: args[4])
    guard !FileManager.default.fileExists(atPath: output.path) else {
      throw Identity.Refusal("CREATION_ALREADY_REQUESTED")
    }
    var result: [String: Any] = [
      "family": args[1], "pid": proc.pid, "sessionID": proc.session, "phase": "creationRequested",
    ]
    try write(result, to: output)
    let w = try request(proc, "core", "crel", ["kocl": .init(typeCode: Identity.code("cwin"))])
    guard w.descriptorType == typeObjectSpecifier,
      w.forKeyword(Identity.code("want"))?.typeCodeValue == Identity.code("cwin"),
      w.forKeyword(Identity.code("form"))?.enumCodeValue == Identity.code("ID  "),
      let wid = w.forKeyword(Identity.code("seld"))?.stringValue, let n = Int64(wid), n > 0,
      String(n) == wid,
      try Identity.windows(proc).subtracting(ids) == Set([wid])
    else { throw Identity.Refusal("NEW_WINDOW_RECEIPT_UNPROVEN") }
    result["windowID"] = wid
    result["phase"] = "windowConfirmed"
    try write(result, to: output)
    let window = try Identity.object("cwin", "ID  ", .init(string: wid))
    let tabs = try tabIDs(proc, window: window)
    guard tabs.count == 1 else { throw Identity.Refusal("NEW_WINDOW_NOT_SINGLE_TAB") }
    let tid = tabs[0]
    let tab = try Identity.object("CrTb", "ID  ", .init(string: tid), window)
    let beforeURL = try Identity.get(proc, Identity.property("URL ", tab)).stringValue
    guard ["about:blank", "chrome://newtab/", "edge://newtab/"].contains(beforeURL ?? "") else {
      throw Identity.Refusal("NEW_WINDOW_NOT_BLANK")
    }
    result["tabID"] = tid
    result["phase"] = "blankConfirmed"
    try write(result, to: output)
    _ = try request(
      proc, "core", "setd",
      ["----": Identity.property("URL ", tab), "data": .init(string: args[3])])
    let deadline = Date(timeIntervalSinceNow: 2)
    while try Identity.get(proc, Identity.property("URL ", tab)).stringValue != args[3] {
      if Date() >= deadline { throw Identity.Refusal("QA_ADDRESS_UNCONFIRMED") }
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    guard try tabIDs(proc, window: window) == [tid] else {
      throw Identity.Refusal("OWN_WINDOW_CHANGED")
    }
    let active = try Identity.get(
      proc, Identity.property("acTa", Identity.object("cwin", "indx", .init(int32: 1))))
    guard let ids = ChromeActiveTabDescriptor.identity(in: active), ids.window == wid,
      ids.tab == tid
    else { throw Identity.Refusal("OWN_WINDOW_NOT_SELECTED") }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != proc.pid {
      guard NSRunningApplication(processIdentifier: proc.pid)?.activate(options: []) == true else {
        throw Identity.Refusal("OWN_WINDOW_NOT_FRONT")
      }
    }
    result["phase"] = "qaAddressConfirmed"
    try write(result, to: output)
    return result
  }
  static func close(_ proc: ChromeProcessIdentity, _ args: [String]) throws -> [String: Any] {
    guard args.count == 4,
      args[0] == "close-temporary"
        ? args[3] == "https://chatgpt.com/?temporary-chat=true" : valid(args[3]),
      let receipt = try JSONSerialization.jsonObject(
        with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as? [String: Any],
      receipt["phase"] as? String == "qaAddressConfirmed",
      receipt["sessionID"] as? String == proc.session, let w = receipt["windowID"] as? String,
      let t = receipt["tabID"] as? String
    else { throw Identity.Refusal("OWN_WINDOW_RECEIPT_MISSING") }
    let window = try Identity.object("cwin", "ID  ", .init(string: w))
    let tab = try Identity.object("CrTb", "ID  ", .init(string: t), window)
    guard try tabIDs(proc, window: window) == [t],
      try Identity.get(proc, Identity.property("URL ", tab)).stringValue == args[3]
    else { throw Identity.Refusal("CLOSE_REFUSED") }
    var updated = receipt
    let receiptURL = URL(fileURLWithPath: args[2])
    updated["phase"] = "closeRequested"
    try write(updated, to: receiptURL)
    _ = try request(proc, "core", "clos", ["----": window])
    let until = Date(timeIntervalSinceNow: 2)
    while try Identity.windows(proc).contains(w) {
      if Date() >= until { throw Identity.Refusal("CLOSE_UNCONFIRMED") }
      Thread.sleep(forTimeInterval: 0.02)
    }
    updated["phase"] = "closed"
    try write(updated, to: receiptURL)
    return ["windowClosed": true, "closeRequests": 1, "sessionID": proc.session]
  }
  static func grant(_ proc: ChromeProcessIdentity, tab: E, _ slot: Int) throws -> String {
    guard (0..<4).contains(slot) else { throw Identity.Refusal("UNKNOWN_GRANT") }
    let script = "document.querySelector('#g" + String(slot) + "')?.textContent || ''"
    guard
      let s = try request(proc, "CrSu", "ExJa", ["----": tab, "JvSc": .init(string: script)])
        .stringValue,
      UUID(uuidString: s) != nil
    else { throw Identity.Refusal("ORIGINAL_RENDERER_GRANT_UNAVAILABLE") }
    return s
  }
}
