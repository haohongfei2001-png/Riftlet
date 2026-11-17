import AppKit
import Carbon

protocol EdgeWebExecutionDriver: Sendable {
    func freeze(deadline: TimeInterval) throws -> EdgeWindowTab
    func recheckClickSelection(_ target: EdgeWindowTab, deadline: TimeInterval) throws
    func revalidate(_ target: EdgeWindowTab, deadline: TimeInterval,
                    descriptorFailure: (EdgeDescriptorFailure) -> Void) throws
    func isCurrent(_ target: EdgeWindowTab) -> Bool
    func recover(session: String, window: String, tab: String) -> EdgeWindowTab?
    func evaluate(_ source: String, target: EdgeWindowTab, budget: MainWorldReceiptReadBudget) throws -> String
    func bootstrap(_ source: String, target: EdgeWindowTab) throws
}

extension EdgeWebExecutionDriver {
    func revalidate(_ target: EdgeWindowTab, deadline: TimeInterval) throws {
        try revalidate(target, deadline: deadline, descriptorFailure: { _ in })
    }
}

/// Independently uses Edge's scripting.sdef: CrSu/ExJa/JvSc, CrTb in cwin,
/// and the writable tab URL property. No osascript recipient lookup, activation,
/// remote debugging, private API, extension, chooser or network API is involved.
struct NativeEdgeWebExecutionDriver: EdgeWebExecutionDriver {
    func freeze(deadline: TimeInterval) throws -> EdgeWindowTab {
        do { return try EdgeApplicationHost(deadlineUptime: deadline).freeze() } catch { throw Self.mapped(error) }
    }
    func revalidate(_ target: EdgeWindowTab, deadline: TimeInterval,
                    descriptorFailure: (EdgeDescriptorFailure) -> Void) throws {
        do { try EdgeApplicationHost(deadlineUptime: deadline).revalidate(target) }
        catch {
            if case let EdgeHostError.unsupportedDescriptor(failure) = error { descriptorFailure(failure) }
            throw Self.mapped(error)
        }
    }
    func recheckClickSelection(_ target: EdgeWindowTab, deadline: TimeInterval) throws {
        do { try EdgeApplicationHost(deadlineUptime: deadline).recheckClickSelection(target) }
        catch { throw Self.mapped(error) }
    }
    func isCurrent(_ target: EdgeWindowTab) -> Bool {
        EdgeProcessIdentity.read(pid: target.process.pid)?.birth == target.process
    }
    func recover(session: String, window: String, tab: String) -> EdgeWindowTab? {
        guard let process = EdgeProcessIdentity.recover(session), Self.identifier(window), Self.identifier(tab) else { return nil }
        // Observation addresses only the stored tab. It never asks which tab is
        // now selected and never uses a URL to discover a replacement receiver.
        return EdgeWindowTab(process: process.birth, windowID: window, tabID: tab, address: "")
    }

    private static func identifier(_ text: String) -> Bool {
        guard let number = Int64(text), number > 0 else { return false }
        return String(number) == text
    }

    func evaluate(_ source: String, target: EdgeWindowTab, budget: MainWorldReceiptReadBudget) throws -> String {
        let result = try send(suite: "CrSu", action: "ExJa", target: target, source: source,
                              budget: budget)
        guard let value = result?.stringValue else { throw WebAdapterError.nativeExecutionFailed }
        return value
    }

    func bootstrap(_ source: String, target: EdgeWindowTab) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let escaped = ("void(" + source + ")").addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw WebAdapterError.invalidRequest
        }
        _ = try send(suite: "core", action: "setd", target: target, value: "javascript:" + escaped)
    }

    private func send(suite: String, action: String, target: EdgeWindowTab, source: String? = nil,
                      value: String? = nil, budget: MainWorldReceiptReadBudget? = nil) throws -> NSAppleEventDescriptor? {
        guard isCurrent(target), Self.identifier(target.windowID), Self.identifier(target.tabID) else {
            throw WebAdapterError.invalidTarget
        }
        let code = EdgeReadEvents.code
        let receiver = NSAppleEventDescriptor(processIdentifier: target.process.pid)
        // The App's explicit consent controller owns prompting. Input, polling,
        // restart and background checks must never create an Automation prompt.
        let permission = AEDeterminePermissionToAutomateTarget(receiver.aeDesc, code(suite), code(action), false)
        guard permission == noErr else { throw WebAdapterError.nativeEventFailed(permission) }
        let tab = try EdgeReadEvents.tab(window: target.windowID, id: target.tabID)
        let direct: NSAppleEventDescriptor
        if value != nil {
            let property = NSAppleEventDescriptor.record()
            property.setDescriptor(.init(typeCode: code("prop")), forKeyword: code("want"))
            property.setDescriptor(.init(enumCode: code("prop")), forKeyword: code("form"))
            property.setDescriptor(.init(typeCode: code("URL ")), forKeyword: code("seld"))
            property.setDescriptor(tab, forKeyword: code("from"))
            guard let object = property.coerce(toDescriptorType: code("obj ")) else {
                throw WebAdapterError.nativeExecutionFailed
            }
            direct = object
        } else { direct = tab }
        let request = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(action),
            targetDescriptor: receiver, returnID: -1, transactionID: 0)
        request.setParam(direct, forKeyword: code("----"))
        if let source { request.setParam(.init(string: source), forKeyword: code("JvSc")) }
        if let value { request.setParam(.init(string: value), forKeyword: code("data")) }
        let timeout = try budget?.timeout(at: ProcessInfo.processInfo.systemUptime) ?? 5
        let reply: NSAppleEventDescriptor
        do { reply = try request.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout) }
        catch { throw Self.mapped(error) }
        if let budget, ProcessInfo.processInfo.systemUptime >= budget.deadlineUptime {
            throw WebAdapterError.nativeEventFailed(-1712)
        }
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            throw WebAdapterError.nativeEventFailed(error.int32Value)
        }
        guard isCurrent(target) else { throw WebAdapterError.invalidTarget }
        return reply.paramDescriptor(forKeyword: code("----"))
    }

    static func mapped(_ error: Error) -> WebAdapterError {
        if let error = error as? WebAdapterError { return error }
        if let error = error as? EdgeHostError {
            switch error {
            case .notFrontmost: return .browserNotFrontmost
            case .changed: return .nativeSelectionChanged
            case .unsupportedDescriptor: return .invalidTarget
            case .automation(let status): return .nativeEventFailed(status)
            }
        }
        let native = error as NSError
        guard native.domain == NSOSStatusErrorDomain, let status = Int32(exactly: native.code) else {
            return .nativeExecutionFailed
        }
        return .nativeEventFailed(status)
    }
}

/// A per-click execution capability check. Edge's dictionary does not specify
/// worlds: the execute realm must retain an original-document private closure,
/// while a javascript: bootstrap must NOT see that realm's own global property.
/// This checks actual runtime behavior, not a browser-family assumption. It is
/// not an authenticated service receipt; native identity, editor witness and
/// the shared attachment observer remain independently mandatory.
struct EdgeExecutionWorldWitness: Sendable {
    private let id = UUID().uuidString.lowercased()
    private let secret = UUID().uuidString.lowercased()
    private var key: String { "__riftletEdgeExecution_" + id }
    private var attribute: String { "data-riftlet-edge-execution-" + id }

    /// Both original-document capabilities are created in one execute event on
    /// the frozen tab. This saves a native round trip inside the unchanged
    /// 150 ms click budget; neither check nor the final native recheck is omitted.
    func prepareAndBind(_ witness: ChromeClickDocumentWitness, address: String,
                        program: WebPageProgram) throws -> String {
        let binding = try witness.bindScript(address: address, program: program)
        return """
        /* edge-click-prepare-and-pin */
        (()=>{if((\(prepare))!=='prepared')return 'refused';return (\(binding));})()
        """
    }

    var prepare: String {
        """
        /* edge-world-prepare */
        (()=>{const key='\(key)',secret='\(secret)',root=document.documentElement,
          entry=globalThis.navigation?.currentEntry,address=location.href;
        if(top!==self||!root||!entry||Object.prototype.hasOwnProperty.call(globalThis,key))return 'refused';
        const current=()=>document.documentElement===root&&location.href===address&&navigation.currentEntry?.id===entry.id;
        let verified=false;
        const capability=Object.freeze({confirm:()=>{if(current()&&root.getAttribute('\(attribute)')===secret){
          root.removeAttribute('\(attribute)');verified=true;}return verified&&current();},current:()=>verified&&current()});
        Object.defineProperty(globalThis,key,{value:capability,configurable:true});
        setTimeout(()=>{delete globalThis[key];root.removeAttribute('\(attribute)');},60000);
        return 'prepared';})()
        """
    }
    var bootstrap: String {
        """
        /* edge-world-bootstrap */
        (()=>{if(!Object.prototype.hasOwnProperty.call(globalThis,'\(key)'))
          document.documentElement.setAttribute('\(attribute)','\(secret)');})()
        """
    }
    var confirm: String {
        "/* edge-world-confirm */ (()=>globalThis['\(key)']?.confirm()===true?'verified':'refused')()"
    }
    var validate: String {
        "/* edge-world-validate */ (()=>globalThis['\(key)']?.current()===true?'verified':'refused')()"
    }
}
