import Foundation
import RiftletAdapters
import RiftletCore

enum FixtureMailbox {
  static let root = URL(
    fileURLWithPath: ProcessInfo.processInfo.environment["RIFTLET_OWNED_RECOVERY_FIXTURE"]!)
  static func object(_ url: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  }
  static var native: [String: Any] {
    (try? object(root.appendingPathComponent("native.json"))) ?? [:]
  }
  static var privateSupport: URL { root.appendingPathComponent("app-support") }
  static func log(_ fields: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
    else { return }
    let url = root.appendingPathComponent(
      "transport-\(ProcessInfo.processInfo.systemUptime)-\(UUID().uuidString).json")
    try? data.write(to: url, options: .atomic)
  }
  static func send(_ object: [String: Any]) async throws -> Data {
    let name = UUID().uuidString + ".json"
    let request = root.appendingPathComponent("page-in").appendingPathComponent(name)
    let reply = root.appendingPathComponent("page-out").appendingPathComponent(name)
    try JSONSerialization.data(withJSONObject: object).write(to: request, options: .atomic)
    let deadline = ProcessInfo.processInfo.systemUptime + 8
    while !FileManager.default.fileExists(atPath: reply.path)
      && ProcessInfo.processInfo.systemUptime < deadline
    {
      try await Task.sleep(nanoseconds: 6_000_000)
    }
    let envelope = try Self.object(reply)
    guard envelope["ok"] as? Bool == true, let value = envelope["value"] else {
      if let code = envelope["code"] as? String, let rejection = WebPageRejection(rawValue: code) {
        throw WebAdapterError.pageRejected(rejection)
      }
      throw WebAdapterError.invalidReply
    }
    return try JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
  }
}
@MainActor final class FixtureExecutor: WebClickTargetPinning {
  private var ticket: TargetLease?
  var preparedBinding: String? { ticket?.clickBindingID?.uuidString }
  private var epoch = UUID()
  private var task: Task<Void, Never>?
  private var stopped = false
  private let owner: PreClickPreparationOwner
  init(owner: PreClickPreparationOwner) { self.owner = owner }
  nonisolated func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws
    -> Data
  {
    let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command))
    return try await FixtureMailbox.send(["action": "command", "command": payload])
  }
  func requestPreparation(program: WebPageProgram, invalidate: Bool, maintain: Bool) {
    guard !stopped else { return }
    if invalidate { retirePreparation(program: program) }
    guard task == nil, ticket == nil else { return }
    let generation = epoch
    task = Task { @MainActor in
      defer { if generation == self.epoch { self.task = nil } }
      let witness = UUID().uuidString
      do {
        let document = try await FixtureMailbox.send(["action": "snapshot"])
        guard let state = try JSONSerialization.jsonObject(with: document) as? [String: Any],
          let original = state["originalDraft"] as? Bool
        else { throw WebAdapterError.invalidTarget }
        let address =
          original
          ? "https://chatgpt.com/" : "https://chatgpt.com/c/11111111-1111-4111-8111-111111111111"
        let raw = try await FixtureMailbox.send([
          "action": "command",
          "command": ["action": "pinTarget", "clickWitnessID": witness, "address": address],
        ])
        let bound = try JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed)
        let ownership = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self.owner))
        let result = try await FixtureMailbox.send([
          "action": "command",
          "command": [
            "action": "captureTarget", "clickWitnessID": witness, "preparationOwner": ownership,
          ],
        ])
        guard bound as? String == "bound" else { throw WebAdapterError.invalidTarget }
        let t = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let target = try JSONDecoder().decode(
          TargetLease.self, from: JSONSerialization.data(withJSONObject: t))
        guard generation == self.epoch, target.clickBindingID != nil else { return }
        self.ticket = target
        FixtureMailbox.log([
          "event": "ownedPrepared", "witness": witness, "pin": bound, "target": t,
        ])
      } catch {
        FixtureMailbox.log([
          "event": "ownedPrepareRejected", "error": String(describing: error), "witness": witness,
        ])
      }
    }
  }
  func retirePreparation(program: WebPageProgram) {
    epoch = UUID()
    task?.cancel()
    task = nil
    if let ticket { abandonFrozenTarget(ticket, program: program) }
    ticket = nil
  }
  func stopPreparingForExit(program: WebPageProgram) {
    stopped = true
    retirePreparation(program: program)
  }
  func finishRetirementForExit() async {}
  func abandonFrozenTarget(_ target: TargetLease, program: WebPageProgram) {
    Task {
      let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target))
      _ = try await FixtureMailbox.send([
        "action": "command", "command": ["action": "releasePreparedTarget", "target": value],
      ])
    }
  }
  func targetForClick(eventUptime: TimeInterval) throws -> TargetLease {
    guard let ticket else { throw WebAdapterError.invalidTarget }
    self.ticket = nil
    FixtureMailbox.log([
      "event": "ownedConsumedByAppKit", "uptime": eventUptime,
      "binding": ticket.clickBindingID!.uuidString,
    ])
    return ticket
  }
  func focusOriginal(_ operation: TransferOperation) async -> Bool {
    guard operation.target.sessionID == FixtureMailbox.native["sessionID"] as? String,
      let f = try? await FixtureMailbox.send(["action": "focus"]),
      let reply = try? JSONSerialization.jsonObject(with: f) as? [String: Any]
    else { return false }
    return reply["original"] as? Bool == true && reply["focused"] as? Bool == true
  }
}
