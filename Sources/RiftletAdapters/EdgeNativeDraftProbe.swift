import AppKit
import ApplicationServices

/// Reads confined to an already identified Edge child and its unique native
/// window. Neither these AX observations nor a page reply authorizes a write.
@MainActor
struct EdgeNativeDraftProbe {
    enum Unavailable: String, Error {
        case permission, process, window, document, editor, selection, budget, address
    }

    struct Snapshot: Equatable {
        let process: KernelProcessBirth
        let window: MacAXElement
        let document: MacAXElement
        let editor: MacAXElement
        let entry: MacAXElement?
        let prior: MacAXElement?
        let text: String
        let selection: CFRange

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.process == rhs.process && lhs.window == rhs.window && lhs.document == rhs.document
                && lhs.editor == rhs.editor && lhs.entry == rhs.entry && lhs.prior == rhs.prior && lhs.text == rhs.text
                && lhs.selection.location == rhs.selection.location && lhs.selection.length == rhs.selection.length
        }
    }

    // AXWebConstants.h spells this public attribute "AXDOMIdentifier". Older
    // SDKs omit the symbol; receivers without the attribute still refuse.
    private static let domIdentifierAttribute = "AXDOMIdentifier"
    private let driver: any MacAXDriver
    init(driver: any MacAXDriver) { self.driver = driver }

    /// Read-only transport precondition accessible to the packaged App. An
    /// absent baseline for prior attachments or an unproved chooser keeps all
    /// commercial file delivery unavailable, even when this inspection succeeds.
    func freeze(_ host: EdgeApplicationHost) throws -> EdgeDraft {
        let target = try host.freeze()
        guard let url = URL(string: target.address), ConversationSurfaceAdapter(url: url)?.service == .chatGPT
        else { throw Unavailable.address }
        let snapshot = try read(process: target.process, address: url, editorID: "prompt-textarea")
        try host.revalidate(target)
        return EdgeDraft(target: target, snapshot: snapshot)
    }

    struct EdgeDraft {
        fileprivate let target: EdgeWindowTab
        fileprivate let snapshot: Snapshot
    }

    func revalidate(_ draft: EdgeDraft, host: EdgeApplicationHost) throws {
        try host.revalidate(draft.target)
        guard let url = URL(string: draft.target.address),
              try read(process: draft.target.process, address: url, editorID: "prompt-textarea") == draft.snapshot
        else { throw Unavailable.editor }
        try host.revalidate(draft.target)
    }

    /// Exposes a reason only; content and AX identities never leave this call.
    /// App builds can only call this overload for a disposable loopback draft.
    func inspectNeutral(pid: pid_t, expectedBirth: String, address: URL) -> String {
        guard let parts = URLComponents(url: address, resolvingAgainstBaseURL: false),
              parts.scheme == "http", parts.host == "127.0.0.1", parts.port != nil, parts.user == nil,
              parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.range(of: #"^/RiftletNeutral[a-f0-9]{32}$"#, options: .regularExpression) != nil,
              let process = KernelProcessBirth.read(pid: pid),
              expectedBirth == "\(process.seconds):\(process.microseconds)" else { return Unavailable.address.rawValue }
        do {
            let first = try read(process: process, address: address, editorID: "riftlet-neutral-editor")
            guard try read(process: process, address: address, editorID: "riftlet-neutral-editor") == first,
                  first.text == "Neutral unsent draft", first.selection.location == 2, first.selection.length == 5
            else { return Unavailable.selection.rawValue }
            return "ORIGINAL_AX_DOCUMENT_EDITOR_TEXT_RANGE"
        } catch let error as Unavailable { return error.rawValue }
        catch { return "AX_ATTRIBUTES_UNAVAILABLE" }
    }

    func read(process: KernelProcessBirth, address: URL, editorID: String,
              controlledChooser: Bool = false) throws -> Snapshot {
        guard driver.isTrusted() else { throw Unavailable.permission }
        func exactWindow() throws -> MacAXElement {
            guard let current = NSWorkspace.shared.frontmostApplication, !current.isTerminated,
                  current.processIdentifier == process.pid, current.bundleIdentifier == "com.microsoft.edgemac",
                  KernelProcessBirth.read(pid: process.pid) == process else { throw Unavailable.process }
            let app = try driver.applicationElement(processID: process.pid)
            guard let focused = try driver.elementAttribute(kAXFocusedWindowAttribute, of: app),
                  try driver.elementsAttribute(kAXWindowsAttribute, of: app, maximumCount: 64).contains(focused),
                  try driver.processID(of: focused) == process.pid,
                  try driver.stringAttribute(kAXRoleAttribute, of: focused) == kAXWindowRole,
                  try driver.boolAttribute(kAXMinimizedAttribute, of: focused) == false else { throw Unavailable.window }
            return focused
        }
        let window = try exactWindow()
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        var visited: [MacAXElement] = []
        var documents: [MacAXElement] = []
        var editors: [MacAXElement] = []
        var entries: [MacAXElement] = []
        var images: [MacAXElement] = []
        func scan(_ node: MacAXElement, inDocument: Bool) throws {
            guard visited.count < 768, ProcessInfo.processInfo.systemUptime < deadline else { throw Unavailable.budget }
            guard !visited.contains(node) else { return }
            visited.append(node)
            guard try driver.processID(of: node) == process.pid else { throw Unavailable.process }
            let role = try driver.stringAttribute(kAXRoleAttribute, of: node)
            var inside = inDocument
            if role == "AXWebArea" {
                // Never match an editor in a nested frame.
                guard !inside else { return }
                var raw: CFTypeRef?
                guard AXUIElementCopyAttributeValue(node.rawValue, kAXURLAttribute as CFString, &raw) == .success,
                      let raw, CFGetTypeID(raw) == CFURLGetTypeID(), let url = raw as? URL,
                      url.absoluteString == address.absoluteString else { throw Unavailable.document }
                documents.append(node)
                inside = true
            }
            if inside && role == kAXTextAreaRole,
               try driver.stringAttribute(Self.domIdentifierAttribute, of: node) == editorID {
                editors.append(node)
            }
            if inside && controlledChooser && role == kAXButtonRole,
               try driver.stringAttribute(Self.domIdentifierAttribute, of: node) == "riftlet-neutral-attachment" {
                entries.append(node)
            }
            if inside && controlledChooser && role == kAXImageRole { images.append(node) }
            for child in try driver.elementsAttribute(kAXChildrenAttribute, of: node, maximumCount: 128) {
                try scan(child, inDocument: inside)
            }
        }
        try scan(window, inDocument: false)
        guard documents.count == 1 else { throw Unavailable.document }
        guard editors.count == 1, let editor = editors.first,
              try driver.elementAttribute(kAXWindowAttribute, of: editor) == window,
              let text = try driver.stringAttribute(kAXValueAttribute, of: editor) else { throw Unavailable.editor }
        var raw: CFTypeRef?
        var range = CFRange()
        guard AXUIElementCopyAttributeValue(editor.rawValue, kAXSelectedTextRangeAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID(),
              AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count, range.length <= text.utf16.count - range.location
        else { throw Unavailable.selection }
        if controlledChooser {
            guard entries.count == 1, images.count == 1,
                  try driver.stringAttribute(Self.domIdentifierAttribute, of: images[0]) == "riftlet-neutral-prior",
                  try driver.elementAttribute(kAXWindowAttribute, of: entries[0]) == window,
                  try driver.elementAttribute(kAXWindowAttribute, of: images[0]) == window
            else { throw Unavailable.document }
        }
        guard try exactWindow() == window else { throw Unavailable.window }
        return Snapshot(process: process, window: window, document: documents[0], editor: editor, entry: entries.first, prior: images.first, text: text, selection: range)
    }
}
