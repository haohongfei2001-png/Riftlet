// Read-only control-channel diagnosis, never a Riftlet target or input grant.
// No activation, prompt, file input, capture or upload. Only the existing MAIN nonce receipt is written.
import AppKit
import Carbon
import ApplicationServices

private func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
private func object(_ kind: String, form: String, key: NSAppleEventDescriptor,
                    container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
    let r = NSAppleEventDescriptor.record()
    r.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
    r.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
    r.setDescriptor(key, forKeyword: code("seld"))
    r.setDescriptor(container, forKeyword: code("from"))
    guard let result = r.coerce(toDescriptorType: code("obj ")) else { throw ProbeError.shape }
    return result
}
private func property(_ name: String, of parent: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
    try object("prop", form: "prop", key: .init(typeCode: code(name)), container: parent)
}
private enum ProbeError: Error { case shape, processChanged, permission(Int32), native(Int32) }
private func failure(_ error: Error) -> [String: Any] {
    switch error {
    case ProbeError.shape: return ["result": "FAIL", "kind": "descriptorShape"]
    case ProbeError.processChanged: return ["result": "FAIL", "kind": "processChanged"]
    case let ProbeError.permission(status): return ["result": "NOT_RUN", "kind": "permission", "status": status]
    case let ProbeError.native(status): return ["result": "FAIL", "kind": "appleEvent", "status": status]
    default: return ["result": "FAIL", "kind": "native", "status": (error as NSError).code]
    }
}

private struct Receiver {
    let pid: pid_t
    let launch: Date
    func stable() -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated && app.bundleIdentifier == "com.google.Chrome" && app.launchDate == launch
    }
    func permission() -> Int32 {
        let address = NSAppleEventDescriptor(processIdentifier: pid)
        return AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, false)
    }
    func send(_ suite: String, _ event: String, direct: NSAppleEventDescriptor,
              javascript: String? = nil, value: String? = nil, receiptBudget: MainWorldReceiptReadBudget? = nil) throws -> NSAppleEventDescriptor {
        guard stable() else { throw ProbeError.processChanged }
        let consent = permission()
        guard consent == noErr else { throw ProbeError.permission(consent) }
        let request = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(event),
            targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        request.setParam(direct, forKeyword: code("----"))
        if let javascript { request.setParam(.init(string: javascript), forKeyword: code("JvSc")) }
        if let value { request.setParam(.init(string: value), forKeyword: code("data")) }
        let timeout = try receiptBudget?.timeout(at: ProcessInfo.processInfo.systemUptime) ?? 0.5
        let reply = try request.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
        guard stable() else { throw ProbeError.processChanged }
        if let err = reply.paramDescriptor(forKeyword: code("errn")), err.int32Value != 0 {
            throw ProbeError.native(err.int32Value)
        }
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else { if value != nil { return .null() }; throw ProbeError.shape }
        return result
    }
    func get(_ value: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send("core", "getd", direct: value)
    }
}

// Standalone diagnostic harness links the unmodified production envelope file.
// These declarations supply only its error/payload type dependencies.
enum ObservationDecoder { static let maximumPayloadBytes = 64 * 1024 }
enum WebAdapterError: Error, Equatable { case invalidReply, pageRejected(WebPageRejection), nativeEventFailed(Int32) }
@main private struct Run {
 @MainActor private static var stage = "request"
 @MainActor static func main() {
  do { try run() } catch {
   var report=failure(error);report["stage"]=stage;report["uptime"]=ProcessInfo.processInfo.systemUptime
   print(String(decoding:(try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys)) ?? Data(),as:UTF8.self));exit(1)
  }
 }
 @MainActor static func run() throws {
  guard CommandLine.arguments.count == 3 else { throw ProbeError.shape }
  let raw=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]));guard raw.count<16384,
   let command=try JSONSerialization.jsonObject(with:raw) as? [String:Any],let identity=command["identity"] as? [String:Any],
   let target=identity["target"] as? [String:Any],let session=target["sessionID"] as? String,
   let pidText=session.split(separator:":").first,let pid=Int32(pidText),
   let app=NSRunningApplication(processIdentifier:pid),let launch=app.launchDate,
   session=="\(pid):\(launch.timeIntervalSince1970)",target["applicationID"] as? String=="com.google.Chrome",
   let window=target["windowID"] as? String,let tab=target["tabID"] as? String,
   let logical=target["logicalDraftIdentity"] as? [String:Any],let chat=logical["id"] as? String else{throw ProbeError.processChanged}
  let receiver=Receiver(pid:pid,launch:launch)
  let w=try object("cwin",form:"ID  ",key:.init(string:window));let t=try object("CrTb",form:"ID  ",key:.init(string:tab),container:w)
  stage="original-route-read"
  guard try receiver.get(property("URL ",of:t)).stringValue=="https://chatgpt.com/c/"+chat else {throw ProbeError.shape}
  let function=try String(contentsOfFile:CommandLine.arguments[2],encoding:.utf8)
  guard !function.isEmpty,function.utf8.count<=128*1024 else{throw ProbeError.shape}
  let native=["applicationID":"com.google.Chrome","sessionID":session,"windowID":window,"tabID":tab]
  let context=String(decoding:try JSONSerialization.data(withJSONObject:native),as:UTF8.self)
  let envelope=MainWorldCommandEnvelope(function:function,commandJSON:String(decoding:raw,as:UTF8.self),contextJSON:context)
  let allowed=CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
  guard let encoded=("void("+envelope.source+")").addingPercentEncoding(withAllowedCharacters:allowed) else{throw ProbeError.shape}
  let before=ProcessInfo.processInfo.systemUptime
  // Exactly one MAIN submission; retries below only read this original nonce.
  stage="main-submit"
  _ = try receiver.send("core","setd",direct:property("URL ",of:t),value:"javascript:"+encoded)
  stage="original-receipt-read"
  let receipt=try MainWorldReceiptReader.read(envelope){budget in
   try receiver.send("CrSu","ExJa",direct:t,javascript:envelope.reader,receiptBudget:budget).stringValue ?? ""
  }
  let report:[String:Any] = ["world":"MAIN","submittedUptime":before,"receivedUptime":receipt.receivedUptime,
    "snapshot":try JSONSerialization.jsonObject(with:Data(receipt.text.utf8)),"physical":false]
  print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:.sortedKeys),as:UTF8.self))
 }
}
