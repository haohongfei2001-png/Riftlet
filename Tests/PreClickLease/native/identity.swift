import AppKit
import Carbon
import CryptoKit
import Security

@testable import RiftletAdapters

// Only this process's vendor-authenticated standard browser may answer. Existing
// windows contribute IDs only; the only URL/title read is in a newly added window.
@main enum Identity {
  struct Refusal: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
  }
  struct Family {
    let bundle, team, name: String
    var path: String { "/Applications/" + name + ".app" }
    var executable: String { path + "/Contents/MacOS/" + name }
    var requirement: String {
      "anchor apple generic and identifier \"\(bundle)\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(team)\""
    }
  }
  static let families = [
    "chrome": Family(bundle: "com.google.Chrome", team: "EQHXZ8M8AV", name: "Google Chrome"),
    "edge": Family(bundle: "com.microsoft.edgemac", team: "UBF8T346G9", name: "Microsoft Edge"),
  ]
  static func verify(_ value: OSStatus, _ stage: String) throws {
    if value != errSecSuccess { throw Refusal(stage + "_" + String(value)) }
  }
  static func pidPath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(validatingUTF8: buffer)
  }
  static func certified(_ family: Family, expectedPID: pid_t?) throws -> ChromeProcessIdentity {
    let matches = NSRunningApplication.runningApplications(withBundleIdentifier: family.bundle)
      .filter {
        (expectedPID == nil || $0.processIdentifier == expectedPID)
          && $0.bundleURL?.resolvingSymlinksInPath().path == family.path
          && $0.executableURL?.resolvingSymlinksInPath().path == family.executable
      }
    guard matches.count == 1, let pid = matches.first?.processIdentifier,
      pidPath(pid) == family.executable,
      let frozen = ChromeProcessIdentity.read(pid: pid, applicationID: family.bundle)
    else { throw Refusal("UNIQUE_SIGNED_PROCESS_REQUIRED") }
    var signed: SecCode?
    var requirement: SecRequirement?
    var disk: SecStaticCode?
    var actualURL: CFURL?
    let none = SecCSFlags()
    try verify(
      SecRequirementCreateWithString(family.requirement as CFString, none, &requirement),
      "REQUIREMENT")
    try verify(
      SecCodeCopyGuestWithAttributes(
        nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, none, &signed),
      "GUEST")
    guard let signed, let requirement else { throw Refusal("MISSING_GUEST") }
    try verify(SecCodeCheckValidity(signed, none, requirement), "LIVE_SIGNATURE")
    try verify(SecCodeCopyStaticCode(signed, none, &disk), "STATIC_CODE")
    guard let disk else { throw Refusal("MISSING_STATIC_CODE") }
    try verify(SecCodeCopyPath(disk, none, &actualURL), "SIGNATURE_PATH")
    guard let actualURL, (actualURL as URL).resolvingSymlinksInPath().path == family.path,
      frozen.isCurrent(), pidPath(pid) == family.executable
    else { throw Refusal("SIGNATURE_PATH_OR_BIRTH") }
    return frozen
  }
  static func code(_ value: String) -> UInt32 { value.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
  static func object(
    _ kind: String, _ form: String, _ selector: NSAppleEventDescriptor,
    _ parent: NSAppleEventDescriptor = .null()
  ) throws -> NSAppleEventDescriptor {
    let record = NSAppleEventDescriptor.record()
    for (key, item) in [
      ("want", NSAppleEventDescriptor(typeCode: code(kind))), ("form", .init(enumCode: code(form))),
      ("seld", selector), ("from", parent),
    ] { record.setDescriptor(item, forKeyword: code(key)) }
    guard let result = record.coerce(toDescriptorType: code("obj ")) else {
      throw Refusal("INVALID_SPECIFIER")
    }
    return result
  }
  static func get(_ identity: ChromeProcessIdentity, _ obj: NSAppleEventDescriptor) throws
    -> NSAppleEventDescriptor
  {
    guard identity.isCurrent() else { throw Refusal("PROCESS_CHANGED") }
    let event = NSAppleEventDescriptor(
      eventClass: code("core"), eventID: code("getd"),
      targetDescriptor: .init(processIdentifier: identity.pid), returnID: -1, transactionID: 0)
    event.setParam(obj, forKeyword: keyDirectObject)
    let rep = try event.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: 1)
    try verify(rep.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0, "READ")
    guard identity.isCurrent(), let item = rep.paramDescriptor(forKeyword: keyDirectObject) else {
      throw Refusal("READ_MISSING")
    }
    return item
  }
  static func property(_ id: String, _ receiver: NSAppleEventDescriptor) throws
    -> NSAppleEventDescriptor
  {
    try object("prop", "prop", .init(typeCode: code(id)), receiver)
  }
  static func windows(_ identity: ChromeProcessIdentity) throws -> Set<String> {
    let all = try object("cwin", "indx", ChromeHistoryTabSelection.allTabsOrdinal())
    let ids = try get(identity, property("ID  ", all))
    guard ids.descriptorType == typeAEList else { throw Refusal("WINDOW_LIST_UNAVAILABLE") }
    var keys = Set<String>()
    for i in 0..<ids.numberOfItems {
      guard let s = ids.atIndex(i + 1)?.stringValue, let id = Int64(s), id > 0, String(id) == s,
        keys.insert(s).inserted
      else { throw Refusal("INVALID_WINDOW_IDENTITIES") }
    }
    return keys
  }
  @MainActor static func execute(_ initial: [String]) throws -> [String: Any] {
    var args = initial
    var expectedPID: pid_t?
    if args.first == "--pid" {
      guard args.count >= 4, let pid = Int32(args[1]), pid > 0 else {
        throw Refusal("INVALID_EXPECTED_PID")
      }
      expectedPID = pid
      args.removeFirst(2)
    }
    guard args.count >= 2, let family = families[args[1]] else { throw Refusal("USAGE") }
    if args[0] == "availability" {
      let rows = NSRunningApplication.runningApplications(withBundleIdentifier: family.bundle)
      return [
        "family": args[1], "registered": rows.count,
        "standard": rows.filter { $0.bundleURL?.resolvingSymlinksInPath().path == family.path }.map
        {
          [
            "pid": $0.processIdentifier,
            "expectedExecutable": $0.executableURL?.resolvingSymlinksInPath().path
              == family.executable,
            "kernelPathMatches": pidPath($0.processIdentifier) == family.executable,
            "currentProductClassifies": ChromeProcessIdentity.read(
              pid: $0.processIdentifier, applicationID: family.bundle) != nil,
          ] as [String: Any]
        },
      ]
    }
    let identity = try certified(family, expectedPID: expectedPID)
    if args[0] == "create" { return try Owned.create(identity, args) }
    if args[0] == "close" || args[0] == "close-temporary" { return try Owned.close(identity, args) }
    var facts: [String: Any] = [
      "family": args[1], "bundle": family.bundle, "bundlePath": family.path,
      "executable": family.executable,
      "teamID": family.team, "developerIDRequirement": family.requirement, "dynamicSignature": true,
      "pid": identity.pid, "sessionID": identity.session,
    ]
    if args[0] == "process", args.count == 2 { return facts }
    let current = try windows(identity)
    if args[0] == "snapshot", args.count == 2 {
      facts["windowIDs"] = current.sorted()
      return facts
    }
    guard
      ["verify", "inspect", "observe", "activate-qa", "temporary-route", "press", "series"]
        .contains(args[0]), args.count == 7,
      let before = try JSONSerialization.jsonObject(
        with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as? [String: Any],
      before["sessionID"] as? String == identity.session,
      let old = before["windowIDs"] as? [String],
      current.subtracting(old) == Set([args[3]]), Set(old).isSubset(of: current),
      let tab = Int64(args[4]), tab > 0, String(tab) == args[4],
      let url = URLComponents(string: args[5]), url.scheme == "http", url.host == "127.0.0.1",
      url.port != nil, url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil,
      url.path.range(of: "^/[a-f0-9]{48}/$", options: .regularExpression) != nil,
      let docID = UUID(uuidString: args[6])
    else { throw Refusal("NEW_OWN_WINDOW_OR_CHALLENGE_REQUIRED") }
    let window = try object("cwin", "ID  ", .init(string: args[3]))
    let target = try object("CrTb", "ID  ", .init(string: args[4]), window)
    func isFront() throws -> Bool {
      let first = try object("cwin", "indx", .init(int32: 1))
      guard
        let active = ChromeActiveTabDescriptor.identity(
          in: try get(identity, property("acTa", first)))
      else { return false }
      return active.window == args[3] && active.tab == args[4]
    }
    facts["windowID"] = args[3]
    facts["tabID"] = args[4]
    if args[0] == "temporary-route" {
      guard try isFront(), try Owned.tabIDs(identity, window: window) == [args[4]] else {
        throw Refusal("ORIGINAL_NATIVE_WINDOW_OR_TAB_CHANGED")
      }
      let value = try get(identity, property("URL ", target)).stringValue ?? ""
      facts["exactTemporaryURL"] = value == "https://chatgpt.com/?temporary-chat=true"
      facts["systemForeground"] =
        NSWorkspace.shared.frontmostApplication?.processIdentifier == identity.pid
      return facts
    }
    if args[0] == "inspect" || args[0] == "observe" || args[0] == "activate-qa" {
      let front = try isFront()
      guard try Owned.tabIDs(identity, window: window) == [args[4]],
        try get(identity, property("URL ", target)).stringValue == args[5]
      else { throw Refusal("OWNED_EXACT_URL_MISSING") }
      let title = try get(identity, property("pnam", target)).stringValue ?? ""
      if args[0] == "observe" || args[0] == "activate-qa" {
        let address = try String(decoding: JSONEncoder().encode(args[5]), as: UTF8.self)
        let doc = try String(
          decoding: JSONEncoder().encode(docID.uuidString.lowercased()), as: UTF8.self)
        let query =
          "JSON.stringify({sameDocument:location.href===" + address
          + "&&document.querySelector('#doc')?.textContent===" + doc
          + ",focused:document.hasFocus(),retired:document.title==='Retired QA receiver',grants:[...document.querySelectorAll('#grants output')].filter(e=>e.textContent.length>0).length})"
        let reply =
          try Owned.request(
            identity, "CrSu", "ExJa", ["----": target, "JvSc": .init(string: query)]
          ).stringValue ?? ""
        guard
          let row = (try? JSONSerialization.jsonObject(with: Data(reply.utf8))) as? [String: Any],
          row["sameDocument"] as? Bool == true
        else {
          throw Refusal(
            reply.localizedCaseInsensitiveContains("turned off")
              ? "BROWSER_APPLE_EVENT_JAVASCRIPT_DISABLED" : "NATIVE_RENDERER_NO_RECEIPT")
        }
        if args[0] == "activate-qa" {
          guard front, current == Set([args[3]]),
            let app = NSRunningApplication(processIdentifier: identity.pid)
          else { throw Refusal("EXCLUSIVE_OWNED_WINDOW_REQUIRED") }
          if !app.isActive {
            guard app.activate(options: []) else { throw Refusal("EXCLUSIVE_WINDOW_NOT_ACTIVATED") }
          }
          let deadline = Date(timeIntervalSinceNow: 1)
          while !app.isActive && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
          }
          guard try isFront(),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == identity.pid
          else { throw Refusal("OWNED_WINDOW_NOT_FOREGROUND") }
          facts["activatedOwnedWindowOnly"] = true
        }
        facts["doc"] = docID.uuidString.lowercased()
        facts["renderer"] = row
        return facts
      }
      facts["expectedTitle"] = title == "Riftlet QA " + docID.uuidString.lowercased()
      facts["retired"] = title == "Retired QA receiver"
      facts["preparing"] = title == "Preparing Riftlet QA"
      facts["ownWindowSelected"] = front
      facts["systemForeground"] =
        NSWorkspace.shared.frontmostApplication?.processIdentifier == identity.pid
      return facts
    }
    guard try isFront(), try get(identity, property("URL ", target)).stringValue == args[5],
      try get(identity, property("pnam", target)).stringValue == "Riftlet QA "
        + docID.uuidString.lowercased(),
      try isFront()
    else { throw Refusal("NATIVE_WINDOW_TAB_RENDERER_CHALLENGE_CHANGED") }
    if args[0] != "verify"
      && NSWorkspace.shared.frontmostApplication?.processIdentifier != identity.pid
    {
      // Only this system-verified new window can be raised. The challenge and receiver
      // are re-read after activation; an earlier grant can never be reinstated here.
      guard let app = NSRunningApplication(processIdentifier: identity.pid),
        app.activate(options: [])
      else { throw Refusal("VERIFIED_WINDOW_NOT_ACTIVE") }
      let until = Date(timeIntervalSinceNow: 1)
      while !app.isActive && Date() < until {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
      }
    }
    if args[0] != "verify" {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == identity.pid,
        try isFront(),
        try get(identity, property("URL ", target)).stringValue == args[5],
        try get(identity, property("pnam", target)).stringValue == "Riftlet QA "
          + docID.uuidString.lowercased()
      else { throw Refusal("ORIGINAL_FOREGROUND_RECEIVER_UNAVAILABLE") }
    }
    let ack = ProcessInfo.processInfo.systemUptime
    let uptime = DispatchTime.now().uptimeNanoseconds
    if args[0] == "press" {
      facts["press"] = try Press.measure(ack: ack, browserPID: identity.pid)
      guard try isFront(),
        try get(identity, property("pnam", target)).stringValue == "Riftlet QA "
          + docID.uuidString.lowercased()
      else { throw Refusal("ORIGINAL_RENDERER_NOT_CURRENT_AFTER_DOWN") }
    }
    if args[0] == "series" {
      var ids = Set<String>()
      var samples = [[String: Any]]()
      for slot in 0..<4 {
        guard try isFront(), try get(identity, property("URL ", target)).stringValue == args[5],
          try get(identity, property("pnam", target)).stringValue == "Riftlet QA "
            + docID.uuidString.lowercased()
        else { throw Refusal("ORIGINAL_LOST_BETWEEN_EVENTS") }
        let grant = try Owned.grant(identity, tab: target, slot)
        guard ids.insert(grant).inserted else { throw Refusal("DUPLICATE_GRANT") }
        let ack = ProcessInfo.processInfo.systemUptime
        var sample = try Press.measure(ack: ack, browserPID: identity.pid)
        sample["slot"] = slot
        sample["grant"] = grant
        guard try isFront(),
          try get(identity, property("pnam", target)).stringValue == "Riftlet QA "
            + docID.uuidString.lowercased()
        else { throw Refusal("ORIGINAL_LOST_AFTER_PRESS") }
        samples.append(sample)
      }
      facts["samples"] = samples
    }
    facts["windowID"] = args[3]
    facts["tabID"] = args[4]
    facts["doc"] = args[6]
    facts["challengeSHA256"] = SHA256.hash(data: Data(args[5].utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    facts["systemForeground"] =
      NSWorkspace.shared.frontmostApplication?.processIdentifier == identity.pid
    facts["ackUptimeNS"] = String(uptime)
    return facts
  }
  @MainActor static func main() {
    do {
      let value = try execute(Array(CommandLine.arguments.dropFirst()))
      FileHandle.standardOutput.write(
        try JSONSerialization.data(
          withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
      FileHandle.standardOutput.write(Data([10]))
    } catch {
      let status = (error as? Refusal)?.reason ?? "NATIVE_ERROR_" + String((error as NSError).code)
      FileHandle.standardError.write(Data((status + "\n").utf8))
      exit(1)
    }
  }
}
