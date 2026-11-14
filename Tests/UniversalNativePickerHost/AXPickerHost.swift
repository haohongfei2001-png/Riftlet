import AppKit
import ApplicationServices
import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// File choices in this cooperating fixture have a declared accessibility
/// identifier derived from their exact private URL and bytes. A generic radio
/// button's AXURL can be omitted by AppKit, despite setAccessibilityURL().
private func fileChoiceID(_ url: URL, nonce: String) throws -> String {
    var hash = SHA256()
    hash.update(data: Data(url.standardizedFileURL.path.utf8))
    hash.update(data: Data([0]))
    hash.update(data: try Data(contentsOf: url))
    return "file-" + nonce + "-" + hash.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Two processes on a disposable CI console. The receiver creates a real
/// NSOpenPanel sheet; the observer can only act within the spawned fixture PID.
@main
private struct RunAX {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 3, ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              let uuid = UUID(uuidString: args[2]), args[2] == uuid.uuidString else { exit(64) }
        if args[1] == "--observe", args.count == 5, let pid = Int32(args[3]) {
            let app = NSApplication.shared
            if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
            guard app.activationPolicy() == .prohibited else { print("OBSERVER_NOT_BACKGROUND_ONLY"); return }
            let observer = try Observer(pid: pid, nonce: args[2], root: URL(fileURLWithPath: args[4]))
            do { print(try observer.run()) }
            catch NativeMacAXError.accessibility(let code) { print("AX_ERROR_\(code)") }
            catch { print("AX_ATTRIBUTE_OR_BINDING_UNAVAILABLE") }
            return
        }
        guard args[1] == "--receive", args.count == 4,
              Bundle.main.bundleIdentifier == "org.riftlet.axpicker.\(args[2])" else { exit(64) }
        let app = NSApplication.shared
        let receiver = Receiver(nonce: args[2], root: URL(fileURLWithPath: args[3]))
        app.setActivationPolicy(.regular)
        app.delegate = receiver
        withExtendedLifetime(receiver) { app.run() }
    }
}

@MainActor
private final class Receiver: NSObject, NSApplicationDelegate, NSOpenSavePanelDelegate {
    let nonce: String
    let root: URL
    let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 400, height: 240), styleMask: [.titled],
                          backing: .buffered, defer: false)
    let editor = NSTextView(frame: NSRect(x: 10, y: 12, width: 380, height: 120))
    lazy var panel = NSOpenPanel()
    let chooser = NSBox()
    var selected: URL?
    var choices: [NSButton] = []
    var files: [URL] = []
    let accept = AXPickerActionButton()
    let selectionLabel = NSTextField(labelWithString: "No file selected")
    let prior = NSImageView(frame: NSRect(x: 230, y: 160, width: 32, height: 32))
    var priorImage: NSImage?
    var completed = false
    var announced = false
    var usesNativeFileList: Bool { root.lastPathComponent == "appkit-file-list" }
    var presses = 0
    init(nonce: String, root: URL) { self.nonce = nonce; self.root = root }
    var file: URL { root.appendingPathComponent("images/neutral.png") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        editor.string = "Neutral existing draft."
        editor.setSelectedRange(NSRange(location: 1, length: 4))
        editor.setAccessibilityIdentifier("editor-" + nonce)
        let old = NSImage(contentsOf: root.appendingPathComponent("prior.png"))
        guard let old else { exit(1) }
        priorImage = old
        prior.setAccessibilityElement(true)
        prior.setAccessibilityIdentifier("prior-" + nonce)
        prior.image = old
        window.contentView?.addSubview(prior)
        let entry = NSButton(title: "Attach", target: self, action: #selector(attach))
        entry.frame = NSRect(x: 10, y: 160, width: 100, height: 36)
        entry.setAccessibilityIdentifier("entry-" + nonce)
        window.contentView?.addSubview(editor)
        window.contentView?.addSubview(entry)
        window.initialFirstResponder = entry
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        publishWhenActive(deadline: ProcessInfo.processInfo.systemUptime + 6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) {
            if !self.usesNativeFileList { self.panel.cancel(nil) }
            NSApp.terminate(nil)
        }
    }
    private func publishWhenActive(deadline: TimeInterval) {
        guard !announced else { return }
        let native = NSRunningApplication.current
        let front = NSWorkspace.shared.frontmostApplication
        let sameFront = front?.processIdentifier == getpid() && front?.bundleIdentifier == Bundle.main.bundleIdentifier
        if sameFront && native.launchDate != nil && window.isKeyWindow && window.isVisible && NSApp.isActive {
            announced = true
            do { try Data(String(getpid()).utf8).write(to: root.appendingPathComponent("ready"), options: .atomic) }
            catch { exit(1) }
            return
        }
        if ProcessInfo.processInfo.systemUptime >= deadline {
            let facts = "front=\(sameFront) launch=\(native.launchDate != nil) key=\(window.isKeyWindow) visible=\(window.isVisible) active=\(NSApp.isActive)"
            try? Data(facts.utf8).write(to: root.appendingPathComponent("startup-status"), options: .atomic)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.publishWhenActive(deadline: deadline) }
    }
    @objc func attach() {
        presses += 1
        guard presses == 1 else { exit(1) }
        if usesNativeFileList { showFileList(); return }
        // Return from the AXPress handler before AppKit connects its remote
        // open/save panel service. The original observer only reads thereafter.
        DispatchQueue.main.async { self.showSystemPanel() }
    }
    private func showSystemPanel() {
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png]
        panel.directoryURL = file.deletingLastPathComponent()
        panel.nameFieldStringValue = file.lastPathComponent
        panel.delegate = self
        panel.beginSheetModal(for: window) { result in
            guard result == .OK else { return }
            guard self.panel.urls == [self.file] else { exit(1) }
            self.deliver(self.file)
        }
    }
    func showFileList() {
        // Explicit in-window chooser, independent from the system NSOpenPanel.
        chooser.frame = NSRect(x: 5, y: 5, width: 388, height: 145)
        chooser.title = "Fixture file chooser"
        chooser.setAccessibilityElement(true)
        chooser.setAccessibilityRole(.group)
        chooser.setAccessibilityIdentifier("chooser-" + nonce)
        for (index, name) in ["decoy.png", "neutral.png"].enumerated() {
            let url = file.deletingLastPathComponent().appendingPathComponent(name)
            guard let identifier = try? fileChoiceID(url, nonce: nonce) else { exit(1) }
            let choice = AXPickerActionButton()
            choice.title = name; choice.target = self; choice.action = #selector(choose(_:))
            choice.setButtonType(.radio)
            choice.setAccessibilityElement(true)
            choice.setAccessibilityRole(.radioButton)
            choice.tag = index
            files.append(url)
            choice.frame = NSRect(x: 8, y: CGFloat(78 - 29 * index), width: 170, height: 26)
            choice.setAccessibilityIdentifier(identifier)
            choice.setAccessibilityURL(file.deletingLastPathComponent().appendingPathComponent(name))
            chooser.contentView?.addSubview(choice)
            choices.append(choice)
        }
        accept.setAccessibilityElement(true)
        accept.setAccessibilityRole(.button)
        accept.title = "Attach to this draft"
        accept.target = self; accept.action = #selector(commitChoice)
        accept.frame = NSRect(x: 195, y: 15, width: 165, height: 36)
        accept.isEnabled = false
        accept.setAccessibilityIdentifier("submit-" + nonce)
        chooser.contentView?.addSubview(accept)
        selectionLabel.frame = NSRect(x: 4, y: 8, width: 180, height: 24)
        selectionLabel.setAccessibilityElement(true)
        selectionLabel.setAccessibilityIdentifier("unselected-" + nonce)
        chooser.contentView?.addSubview(selectionLabel)
        chooser.setAccessibilityChildren(choices + [accept, selectionLabel])
        window.contentView?.addSubview(chooser)
    }
    @objc func choose(_ button: NSButton) {
        guard selected == nil, let index = choices.firstIndex(of: button), files.indices.contains(index),
              button.state == .on else { exit(1) }
        selected = files[index]
        guard let selected, let id = try? fileChoiceID(selected, nonce: nonce) else { exit(1) }
        selectionLabel.stringValue = selected.lastPathComponent
        selectionLabel.setAccessibilityIdentifier("selected-" + id)
        accept.isEnabled = true
    }
    @objc func commitChoice() {
        guard let selected, selected == file, choices.filter({ $0.state == .on }).count == 1 else { exit(1) }
        chooser.removeFromSuperview()
        deliver(selected)
    }
    func intact() -> Bool {
        editor.string == "Neutral existing draft." && editor.selectedRange() == NSRange(location: 1, length: 4)
            && editor.window === window && prior.window === window && prior.image === priorImage && priorImage != nil
    }
    func deliver(_ selected: URL) {
        guard !completed, presses == 1, intact(), selected == file,
              let data = try? Data(contentsOf: selected),
              let text = try? String(contentsOf: root.appendingPathComponent("port"), encoding: .utf8),
              let port = UInt16(text), let destination = URL(string: "http://127.0.0.1:\(port)/receive/\(nonce)") else { exit(1) }
        completed = true
        var request = URLRequest(url: destination)
        request.httpMethod = "POST"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        let session = URLSession(configuration: .ephemeral)
        session.uploadTask(with: request, from: data) { reply, response, error in
            DispatchQueue.main.async {
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 201,
                      reply == Data("accepted-\(self.nonce)".utf8), self.intact(), self.completed,
                      let image = NSImage(data: data) else { exit(1) }
                let card = NSImageView(frame: NSRect(x: 280, y: 160, width: 32, height: 32))
                card.image = image
                self.window.contentView?.addSubview(card)
                guard card.window === self.window, self.intact() else { exit(1) }
                do { try data.write(to: self.root.appendingPathComponent("received"), options: .withoutOverwriting) }
                catch { exit(1) }
                session.finishTasksAndInvalidate()
                NSApp.terminate(nil)
            }
        }.resume()
    }
    func panel(_ sender: Any, validate url: URL) throws {
        if url != file { throw CocoaError(.fileReadNoPermission) }
    }
}

@MainActor
private final class Observer {
    let driver: NativeMacAXDriver
    let pid: Int32
    let nonce: String
    let root: URL
    init(pid: Int32, nonce: String, root: URL) throws {
        driver = try NativeMacAXDriver(messagingTimeout: 0.5)
        self.pid = pid; self.nonce = nonce; self.root = root
    }

    func descendants(_ start: MacAXElement) throws -> [MacAXElement] {
        var items = [start]
        var cursor = 0
        while cursor < items.count {
            let children = try driver.elementsAttribute(kAXChildrenAttribute, of: items[cursor], maximumCount: 128)
            for child in children where !items.contains(child) {
                guard try driver.processID(of: child) == pid, items.count < 384 else { throw NativeMacAXError.boundsExceeded }
                items.append(child)
            }
            cursor += 1
        }
        return items
    }
    func unique(_ matches: [MacAXElement]) -> MacAXElement? { matches.count == 1 ? matches[0] : nil }
    func exactFile(_ row: MacAXElement, url: URL) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(row.rawValue, kAXURLAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == CFURLGetTypeID(), let value = raw as? URL else { return false }
        guard value.isFileURL, url.isFileURL, let parts = URLComponents(url: value, resolvingAgainstBaseURL: false),
              [nil, "", "localhost"].contains(parts.host?.lowercased()), parts.user == nil, parts.password == nil,
              parts.port == nil, parts.query == nil, parts.fragment == nil else { return false }
        return value.standardizedFileURL.path == url.standardizedFileURL.path
    }
    func fileListControls(expected: URL, binding: AXPickerInspection, originalDraft: @escaping () throws -> Bool) throws -> EdgeConversationPicker.Controls? {
        func identifier(_ node: MacAXElement, _ id: String) throws -> Bool {
            try driver.stringAttribute(kAXIdentifierAttribute, of: node) == id + "-" + nonce
        }
        func findChooser() throws -> MacAXElement? {
            guard try binding.originalDraftIsCurrent(originalDraft) else { return nil }
            return try unique(descendants(binding.window).filter { try identifier($0, "chooser") })
        }
        let until = ProcessInfo.processInfo.systemUptime + 2
        var chooser: MacAXElement?
        while chooser == nil && ProcessInfo.processInfo.systemUptime < until {
            chooser = try findChooser()
            if chooser == nil { Thread.sleep(forTimeInterval: 0.10) }
        }
        guard let chooser else { return nil }
        let expectedID = try fileChoiceID(expected, nonce: nonce)
        let decoy = expected.deletingLastPathComponent().appendingPathComponent("decoy.png")
        let decoyID = try fileChoiceID(decoy, nonce: nonce)
        var choices: [MacAXElement] = []
        var choice: MacAXElement?
        var submit: MacAXElement?
        var decoyFound = false
        let ready = ProcessInfo.processInfo.systemUptime + 3
        repeat {
            do {
                guard try findChooser() == chooser else { return nil }
                let nodes = try descendants(chooser)
                choices = try nodes.filter { try driver.stringAttribute(kAXRoleAttribute, of: $0) == kAXRadioButtonRole }
                let pairs = try choices.map { ($0, try driver.stringAttribute(kAXIdentifierAttribute, of: $0)) }
                choice = unique(pairs.filter { $0.1 == expectedID }.map(\.0))
                decoyFound = pairs.filter { $0.1 == decoyID }.count == 1
                submit = try unique(nodes.filter { try identifier($0, "submit") })
                if choices.count == 2 && choice != nil && decoyFound && submit != nil { break }
            } catch NativeMacAXError.accessibility(let code) where code == AXError.cannotComplete.rawValue {
                // Read-only AX replies can lag a newly mounted AppKit view.
            }
            Thread.sleep(forTimeInterval: 0.08)
        } while ProcessInfo.processInfo.systemUptime < ready
        guard choices.count == 2, let choice, decoyFound, let submit else { return nil }
        func confirms() throws -> Bool {
            guard try findChooser() == chooser else { return false }
            let list = try descendants(chooser)
            let radios = try list.filter { try driver.stringAttribute(kAXRoleAttribute, of: $0) == kAXRadioButtonRole }
            guard radios.count == 2, radios.contains(choice), let other = radios.first(where: { $0 != choice }),
                  try driver.stringAttribute(kAXIdentifierAttribute, of: other) == decoyID else { return false }
            func radioState(_ node: MacAXElement) -> Int? {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(node.rawValue, kAXValueAttribute as CFString, &value) == .success,
                      let number = value as? NSNumber, number == 0 || number == 1 else { return nil }
                return number.intValue
            }
            let wanted = radioState(choice), unwanted = radioState(other)
            guard wanted == 1, unwanted == 0 else {
                return false
            }
            let receipts = try list.filter { try driver.stringAttribute(kAXIdentifierAttribute, of: $0) == "selected-" + expectedID }
            guard receipts.count == 1 else { return false }
            guard try driver.boolAttribute(kAXEnabledAttribute, of: submit) == true else { return false }
            return true
        }
        return EdgeConversationPicker.Controls(choice: choice, submit: submit, matchesFile: { stage in
            guard try findChooser() == chooser else { return false }
            let current = try self.descendants(chooser)
            let radios = try current.filter { try self.driver.stringAttribute(kAXRoleAttribute, of: $0) == kAXRadioButtonRole }
            guard radios.count == choices.count, choices.allSatisfy(radios.contains), current.contains(submit),
                  try self.driver.stringAttribute(kAXIdentifierAttribute, of: choice) == expectedID,
                  try fileChoiceID(expected, nonce: self.nonce) == expectedID else { return false }
            if stage == .beforeSelection { return true }
            return try confirms()
        }, selectionSettled: {
            let until = ProcessInfo.processInfo.systemUptime + 2
            repeat {
                guard try binding.originalDraftIsCurrent(originalDraft) else { return false }
                if try confirms() { return true }
                Thread.sleep(forTimeInterval: 0.035)
            } while ProcessInfo.processInfo.systemUptime < until
            return false
        })
    }
    private struct DraftState: Equatable {
        let text: String
        let location: Int
        let length: Int
        let prior: MacAXElement
    }

    private func fixtureDraft(editor: MacAXElement, prior: MacAXElement) throws -> DraftState? {
        var value: CFTypeRef?
        var range = CFRange()
        guard let text = try driver.stringAttribute(kAXValueAttribute, of: editor),
              AXUIElementCopyAttributeValue(editor.rawValue, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cfRange, &range), range.location == 1, range.length == 4,
              text == "Neutral existing draft." else { return nil }
        return DraftState(text: text, location: range.location, length: range.length, prior: prior)
    }

    func run() throws -> String {
        guard driver.isTrusted() else { return "NOT_RUN_NO_EXISTING_AX_TRUST" }
        guard let actual = NSRunningApplication(processIdentifier: pid) else { return "RECEIVER_PROCESS_MISSING" }
        guard actual.bundleIdentifier == "org.riftlet.axpicker." + nonce else { return "RECEIVER_BUNDLE_CHANGED" }
        guard actual.launchDate != nil else { return "RECEIVER_LAUNCH_DATE_UNAVAILABLE" }
        guard let identity = try driver.applicationIdentity(processID: pid) else { return "RECEIVER_VERSION_OR_IDENTITY_UNAVAILABLE" }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return "FOREGROUND_CHANGED_AFTER_READY" }
        guard try driver.frontmostApplication() == identity else { return "FOREGROUND_LAUNCH_MISMATCH" }
        let app = try driver.applicationElement(processID: pid)
        guard let window = try driver.elementAttribute(kAXFocusedWindowAttribute, of: app) else { return "NO_FROZEN_WINDOW" }
        let children = try descendants(window)
        func matches(_ node: MacAXElement, _ id: String) throws -> Bool {
            try driver.stringAttribute(kAXIdentifierAttribute, of: node) == id + "-" + nonce
        }
        guard let entry = try unique(children.filter { try matches($0, "entry") }) else { return "NO_UNIQUE_ATTACH_BUTTON" }
        guard let editor = try unique(children.filter { try matches($0, "editor") }) else { return "NO_UNIQUE_DRAFT_EDITOR" }
        let binding = AXPickerInspection(driver: driver, process: identity, window: window, editor: editor, entry: entry)
        let prior = try unique(children.filter { try matches($0, "prior") })
        let draftMatches = {
            let current = try self.descendants(window)
            return try self.unique(current.filter { try matches($0, "editor") }) == editor
                && self.unique(current.filter { try matches($0, "entry") }) == entry
        }
        guard try binding.originalDraftIsCurrent(draftMatches),
              try binding.attachedSheet(draftMatches) == nil else { return "DRAFT_NOT_AVAILABLE" }
        // A known fixture opens precisely one sheet and owns a cancellation timer.
        // Never open an arbitrary app's panel to discover whether it can be controlled.
        let systemPanel = root.lastPathComponent == "system-open-panel"
        if !systemPanel {
            guard let prior, let fixtureID = UUID(uuidString: nonce),
                  let baseline = try fixtureDraft(editor: editor, prior: prior) else { return "NO_NATIVE_DRAFT_STATE" }
            let snapshotUnchanged = {
                guard try draftMatches(),
                      try self.unique(self.descendants(window).filter { try matches($0, "prior") }) == prior
                else { return false }
                return try self.fixtureDraft(editor: editor, prior: prior) == baseline
            }
            let file = root.appendingPathComponent("images/neutral.png")
            let bytes = try Data(contentsOf: file)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let picker = try EdgeConversationPicker.controlled(fixtureID: fixtureID, binding: binding,
                originalDraft: snapshotUnchanged, directory: file.deletingLastPathComponent(), file: file,
                bytes: Int64(bytes.count), sha256: hash)
            let input = EdgeConversationPicker.Input(chooserIsAbsent: {
                try binding.attachedSheet(snapshotUnchanged) == nil &&
                    !self.descendants(window).contains(where: { try matches($0, "chooser") })
            }, findOpenedControls: { file in
                try self.fileListControls(expected: file, binding: binding, originalDraft: snapshotUnchanged).map(EdgeConversationPicker.OpenedChooser.fileList)
            })
            let result = try picker.handOff(input)
            guard try picker.handOff(input) == .alreadyAttempted else { return "RIFTLET_PICKER_DUPLICATE_NOT_REFUSED" }
            return result == .inputAttempted ? "EXACT_FILE_SUBMIT_ATTEMPTED" : "RIFTLET_PICKER_\(result)"
        }
        do { try driver.press(entry) }
        catch NativeMacAXError.accessibility(let code) where systemPanel && code == AXError.cannotComplete.rawValue {
            // The original press may have opened the panel. Never reissue it.
            // Discover only its own parent's sheet until the bounded deadline.
        }
        let until = ProcessInfo.processInfo.systemUptime + 3
        var sheet: MacAXElement?
        while sheet == nil && ProcessInfo.processInfo.systemUptime < until {
            do { sheet = try binding.attachedSheet(draftMatches) }
            catch NativeMacAXError.accessibility(let code) where code == AXError.cannotComplete.rawValue {
                // System open-panel XPC may temporarily block the host AX server.
            }
            if sheet == nil { Thread.sleep(forTimeInterval: 0.08) }
        }
        guard let sheet else { return "ENTRY_PRESSED_OWNED_SHEET_UNPROVEN" }
        let file = root.appendingPathComponent("images/neutral.png")
        let nodes: [MacAXElement]
        do { nodes = try descendants(sheet) }
        catch NativeMacAXError.accessibility(let code) where code == AXError.cannotComplete.rawValue {
            return "SHEET_OWNED_FILE_ROW_UNPROVEN"
        }
        guard let table = try unique(nodes.filter { node in
            let role = try driver.stringAttribute(kAXRoleAttribute, of: node)
            return [kAXTableRole, kAXOutlineRole].contains(role) &&
                (try? driver.elementsAttribute(kAXRowsAttribute, of: node, maximumCount: 128))?.contains(where: { exactFile($0, url: file) }) == true
        }), let row = try unique(driver.elementsAttribute(kAXRowsAttribute, of: table, maximumCount: 128).filter { exactFile($0, url: file) }),
              try binding.attachedSheet(draftMatches) == sheet,
              try driver.elementAttribute(kAXTopLevelUIElementAttribute, of: table) == sheet else { return "SHEET_OWNED_FILE_ROW_UNPROVEN" }
        let rows = [row.rawValue] as CFArray
        guard AXUIElementSetAttributeValue(table.rawValue, kAXSelectedRowsAttribute as CFString, rows) == .success,
              try driver.elementsAttribute(kAXSelectedRowsAttribute, of: table, maximumCount: 4) == [row],
              exactFile(row, url: file), try binding.attachedSheet(draftMatches) == sheet,
              let submit = try driver.elementAttribute(kAXDefaultButtonAttribute, of: sheet),
              try driver.processID(of: submit) == pid,
              try driver.elementAttribute(kAXTopLevelUIElementAttribute, of: submit) == sheet,
              try driver.stringAttribute(kAXRoleAttribute, of: submit) == kAXButtonRole,
              try driver.boolAttribute(kAXEnabledAttribute, of: submit) == true,
              try driver.actionNames(of: submit).contains(kAXPressAction) else { return "EXACT_SELECTION_UNPROVEN" }
        try driver.press(submit)
        return "EXACT_FILE_SUBMIT_ATTEMPTED"
    }
}
