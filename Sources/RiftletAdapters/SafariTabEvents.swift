import AppKit
import Carbon
import RiftletCore

/// Safari.sdef exposes tab positions but no tab ID. Pair a position in one
/// numeric window with a capability held by that exact live Document.
struct SafariTabAddress: Equatable {
    let position: Int32
    let document: UUID

    init(position: Int32, document: UUID) {
        self.position = position
        self.document = document
    }

    init?(serialized: String) {
        let parts = serialized.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "safari", let position = Int32(parts[1]), position > 0,
              String(position) == String(parts[1]), let document = UUID(uuidString: String(parts[2])),
              document.uuidString.lowercased() == String(parts[2]) else { return nil }
        self.init(position: position, document: document)
    }

    var serialized: String { "safari:\(position):\(document.uuidString.lowercased())" }
}

/// Safari's documented "do JavaScript in tab" is the only script transport.
/// An indexed specifier can resolve to a replacement tab. Put the identity
/// check and the operation in the same evaluation so a changed slot never
/// runs the operation, including a chunk, relay installation or receipt read.
enum SafariDocumentBinding {
    static let mismatch = "riftlet-safari-original-document-changed"

    private static let read = """
    const root=document.documentElement,key=Symbol.for('com.riftlet.safari.document.v1');
    const entry=root&&Object.getOwnPropertyDescriptor(root,key)?.value;
    const current=top===self&&entry&&entry.document===document&&entry.root===root?entry.id:null;
    """

    static let readSelected = "(()=>{\(read)return document.visibilityState==='visible'&&current||'';})()"

    static func prepare(url: String, token: UUID) throws -> String {
        let address = String(decoding: try JSONEncoder().encode(url), as: UTF8.self)
        let id = token.uuidString.lowercased()
        return """
        (()=>{\(read)
        if(top!==self||!root||document.visibilityState!=='visible'||!document.hasFocus()||location.href!==\(address))return '';
        if(current)return current;
        if(entry)return '';
        Object.defineProperty(root,key,{value:Object.freeze({document,root,id:'\(id)'})});
        return '\(id)';})()
        """
    }

    static func guarded(_ expression: String, document: UUID) -> String {
        "(()=>{\(read)if(current!=='\(document.uuidString.lowercased())')return '\(mismatch)';return (\(expression));})()"
    }
}

struct SafariTabEvents: BrowserTabEvents {
    let pid: pid_t
    var clickDeadline: ChromeClickDeadline? = nil

    private struct Slot: Equatable {
        let window: Int32
        let position: Int32
    }

    private func window(_ id: Int32) throws -> NSAppleEventDescriptor {
        try object("cwin", form: "ID  ", key: .init(int32: id))
    }

    private func frontWindowID() throws -> Int32 {
        let front = try object("cwin", form: "indx", key: .init(int32: 1))
        return try positiveInteger(get(property("ID  ", of: front)))
    }

    private func positiveInteger(_ value: NSAppleEventDescriptor) throws -> Int32 {
        guard [DescType(typeSInt16), DescType(typeSInt32), DescType(typeSInt64)].contains(value.descriptorType),
              let text = value.stringValue, let result = Int32(text), result > 0 else {
            throw WebAdapterError.invalidTarget
        }
        return result
    }

    private func selectedPosition(in id: Int32) throws -> Int32 {
        let current = try property("cTab", of: window(id))
        return try positiveInteger(get(property("pidx", of: current)))
    }

    private func selection() throws -> Slot {
        let owner = try frontWindowID()
        return try Slot(window: owner, position: selectedPosition(in: owner))
    }

    private func tab(_ slot: Slot) throws -> NSAppleEventDescriptor {
        try object("bTab", form: "indx", key: .init(int32: slot.position), container: window(slot.window))
    }

    private func slot(window: String, tabID: String) throws -> (Slot, UUID) {
        guard let owner = Int32(window), owner > 0, String(owner) == window,
              let address = SafariTabAddress(serialized: tabID) else { throw WebAdapterError.invalidTarget }
        return (Slot(window: owner, position: address.position), address.document)
    }

    // sfri/dojs takes the JavaScript as its direct parameter and the absolute
    // tab under 'dcnm'. Leaving the latter out would execute in the active tab.
    private func script(_ source: String, in slot: Slot, returnID: Int16 = -1) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: code("sfri"), eventID: code("dojs"),
            targetDescriptor: .init(processIdentifier: pid), returnID: returnID, transactionID: 0)
        event.setParam(.init(string: source), forKeyword: keyDirectObject)
        event.setParam(try tab(slot), forKeyword: code("dcnm"))
        return event
    }

    /// Safari returns 8 for its own "Allow JavaScript from Apple Events" setting.
    /// Apply that meaning exclusively to sfri/dojs. Standard window events and
    /// macOS Automation consent errors retain their original OSStatus.
    static func javaScriptEvent<T>(_ read: () throws -> T) throws -> T {
        do { return try read() }
        catch WebAdapterError.nativeEventFailed(8) { throw WebAdapterError.javaScriptDisabled }
    }

    private func evaluate(_ source: String, in slot: Slot, budget: MainWorldReceiptReadBudget? = nil) throws -> String {
        let event = try script(source, in: slot)
        let reply = try Self.javaScriptEvent { try send(event, receiptBudget: budget) }
        guard let text = reply.stringValue else { throw WebAdapterError.invalidReply }
        guard text != SafariDocumentBinding.mismatch else { throw WebAdapterError.nativeSelectionChanged }
        return text
    }

    func clickRoute(deadline: ChromeClickDeadline) throws -> ChromeClickRoute {
        let original = try selection()
        // Read only the selected slot's URL before granting any script access.
        guard let url = try get(property("pURL", of: tab(original))).stringValue,
              ConversationProvider.matching(url: url) != nil else { throw WebAdapterError.pageRejected(.pageRouteUnsupported) }
        let source = try SafariDocumentBinding.prepare(url: url, token: UUID())
        let returned = try evaluate(source, in: original)
        guard let token = UUID(uuidString: returned), returned == token.uuidString.lowercased(),
              try selection() == original else { throw WebAdapterError.nativeSelectionChanged }
        try deadline.checkReturn()
        return try .conversation(window: String(original.window),
            tab: SafariTabAddress(position: original.position, document: token).serialized, url: url)
    }

    func activeIdentity(check: String) throws -> (window: String, tab: String) {
        let selected = try selection()
        guard let url = try get(property("pURL", of: tab(selected))).stringValue,
              ConversationProvider.matching(url: url) != nil else { throw WebAdapterError.pageRejected(.pageRouteUnsupported) }
        let token = try selectedDocument(in: selected)
        return (String(selected.window), SafariTabAddress(position: selected.position, document: token).serialized)
    }

    func requireSelection(window: String, tab: String, check: String) throws {
        let (expected, document) = try slot(window: window, tabID: tab)
        // In particular, QA must not probe an unrelated front tab for a marker.
        guard try selection() == expected, try selectedDocument(in: expected) == document else {
            throw WebAdapterError.nativeSelectionChanged
        }
    }

    private func selectedDocument(in original: Slot) throws -> UUID {
        let returned = try evaluate(SafariDocumentBinding.readSelected, in: original)
        guard let token = UUID(uuidString: returned), token.uuidString.lowercased() == returned,
              try selection() == original else { throw WebAdapterError.nativeSelectionChanged }
        return token
    }

    func url(window: String, tab: String) throws -> String {
        try execute("location.href", window: window, tab: tab)
    }

    func selectForHistory(window: String, tab: String) throws {
        let (original, _) = try slot(window: window, tabID: tab)
        // Safari cannot atomically select a tab by a stable native ID. A user
        // can raise its window when the attested tab is already selected there.
        guard try selectedPosition(in: original.window) == original.position,
              try execute("'original'", window: window, tab: tab) == "original" else {
            throw WebAdapterError.nativeSelectionChanged
        }
        _ = try send("core", "setd", direct: property("pidx", of: self.window(original.window)), integer: 1)
        try requireSelection(window: window, tab: tab, check: "history_focus")
    }

    func connectionProbe(stillCurrent: () -> Bool) throws -> String {
        let original = try selection()
        guard stillCurrent() else { throw WebAdapterError.invalidTarget }
        let result = try evaluate("'Riftlet'", in: original, budget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 3))
        guard try selection() == original else { throw WebAdapterError.nativeSelectionChanged }
        return result
    }

    func enqueueWitness(_ source: String, route: ChromeClickRoute, deadline: ChromeClickDeadline) throws -> ChromeClickSnapshot.WitnessReply {
        let (original, token) = try slot(window: route.window, tabID: route.tab)
        let event = try script(SafariDocumentBinding.guarded(source, document: token), in: original, returnID: 3)
        return try Self.javaScriptEvent { try ChromeClickSnapshot.enqueueWitness(event, before: deadline) }
    }

    func confirmWitness(_ reply: ChromeClickSnapshot.WitnessReply, before deadline: ChromeClickDeadline) throws -> Bool {
        try Self.javaScriptEvent { try reply.boundWithinClick(before: deadline) }
    }

    func execute(_ source: String, window: String, tab: String, receiptBudget: MainWorldReceiptReadBudget?) throws -> String {
        let (original, token) = try slot(window: window, tabID: tab)
        return try evaluate(SafariDocumentBinding.guarded(source, document: token), in: original, budget: receiptBudget)
    }

    func dispatchMainWorld(_ source: String, window: String, tab: String) throws {
        guard try execute(source, window: window, tab: tab) == "submitted" else { throw WebAdapterError.invalidReply }
    }

    func submitMainWorld(_ source: String, window: String, tab: String) throws {
        try dispatchMainWorld(source, window: window, tab: tab)
    }
}
