import AppKit
import WebKit

enum CheckError: Error { case failed(Int) }

func check<T: Equatable>(_ value: T, _ expected: T, line: Int = #line) throws {
    guard value == expected else { throw CheckError.failed(line) }
}

func unwrap<T>(_ value: T?, line: Int = #line) throws -> T {
    guard let value else { throw CheckError.failed(line) }
    return value
}

@MainActor
final class SurfaceScenarios {
    let source: String
    let chromeProgram: String
    init(source: String, chromeProgram: String) { self.source = source; self.chromeProgram = chromeProgram }

    private struct Example {
        let url: URL
        let html: String

        init(_ url: String, _ body: String) {
            self.url = URL(string: url)!
            self.html = """
            <!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
            <style>body,main,form,fieldset,input-area,rich-textarea {display:block} textarea,[contenteditable]{min-width:280px;min-height:40px}</style>
            <main>\(body)</main><aside><textarea>Unrelated note</textarea><input type="file"></aside>
            """
        }
    }
    private let chatGPT = Example("https://chatgpt.com/c/sample",
        "<form><div id='prompt-textarea' contenteditable>Sample draft</div><button type='button' data-testid='composer-plus-btn'>Attach</button><span data-testid='attachment-preview'>Prior file</span></form>")
    private let claude = Example("https://claude.ai/new",
        "<fieldset><div class='ProseMirror' contenteditable>Sample draft</div><button type='button' data-testid='add-attachment'>Add files</button><span data-testid='file-thumbnail'>Prior file</span></fieldset>")
    private let gemini = Example("https://gemini.google.com/app",
        "<input-area><rich-textarea><div contenteditable>Sample draft</div></rich-textarea><button type='button' class='upload-card-button'>Upload</button><file-preview>Prior file</file-preview></input-area>")
    private let perplexity = Example("https://www.perplexity.ai/search/sample",
        "<form><div id='ask-input' contenteditable>Sample draft</div><button type='button' data-testid='attach-file'>Attach</button><span data-testid='file-pill'>Prior file</span></form>")
    private let poe = Example("https://poe.com/chat/sample",
        "<div class='ChatMessageInputContainer_inputContainer_sample'><textarea data-testid='chat-input'>Sample draft</textarea><button type='button' aria-label='Add attachment'>Add</button><span class='AttachmentPill_sample'>Prior file</span></div>")

    /// A fresh offscreen WebKit view. The bytes for the entire navigation come
    /// from the fixture, including pages whose simulated URL uses a service host.
    @MainActor
    private final class Fixture: NSObject, WKNavigationDelegate {
        let view: WKWebView
        let world = WKContentWorld.world(name: "RiftletSurfaceInspection")
        private(set) var loaded = false
        let source: String
        private let url: URL
        private(set) var loadError: Error?

        init(_ example: Example, source: String) {
            self.source = source
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            view = WKWebView(frame: .init(x: 0, y: 0, width: 640, height: 480), configuration: config)
            url = example.url
            super.init()
            view.navigationDelegate = self
            view.loadSimulatedRequest(URLRequest(url: example.url), responseHTML: example.html)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) { loadError = error; loaded = true }

        func eval(_ expression: String, in world: WKContentWorld? = nil) async throws -> Any? {
            try await view.evaluateJavaScript(expression, in: nil, contentWorld: world ?? .page)
        }

        func inspect(_ action: ConversationSurfaceAction, _ id: UUID) async throws -> ConversationSurfaceInspection {
            let adapter = try unwrap(ConversationSurfaceAdapter(url: url))
            let result = try await eval(adapter.script(for: action, bindingID: id, program: source), in: world)
            let json = try unwrap(result as? String)
            return try JSONDecoder().decode(ConversationSurfaceInspection.self, from: Data(json.utf8))
        }
    }

    private func open(_ example: Example) async throws -> Fixture {
        let fixture = Fixture(example, source: source)
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while !fixture.loaded && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        try check(fixture.loaded, true)
        if let error = fixture.loadError { throw error }
        return fixture
    }

    private func requireNavigationIdentity(_ fixture: Fixture) async throws {
        let available = try await fixture.eval("!!window.navigation?.currentEntry")
        guard (available as? Bool) == true else {
            let response = try await fixture.inspect(.bind, UUID())
            try check(response.status, .unavailable)
            throw SurfaceHostError.navigationAPIUnavailable
        }
    }

    private func verify(_ example: Example) async throws {
        let fixture = try await open(example)
        let inspectionID = UUID()
        try await requireNavigationIdentity(fixture)
        let snapshot = """
            (() => { const e=document.querySelector('main textarea,[contenteditable]'), s=document.getSelection();
            return JSON.stringify([document.activeElement.tagName, e.value || e.textContent,
              e.selectionStart ?? s.anchorOffset,e.selectionEnd ?? s.focusOffset,document.querySelector('main').innerHTML]); })()
            """
        _ = try await fixture.eval("""
            (() => { const editor=document.querySelector('main textarea,[contenteditable]');
            if (editor.tagName==='TEXTAREA') editor.setSelectionRange(2,6);
            else document.getSelection().setBaseAndExtent(editor.firstChild,2,editor.firstChild,6); })()
            """)
        let before = try await fixture.eval(snapshot) as? String
        let bound = try await fixture.inspect(.bind, inspectionID)
        try check(bound.status, .bound)
        try check(bound.entry, .button)
        try check(bound.attachmentCount, 1)
        let unchanged = try await fixture.inspect(.revalidate, inspectionID)
        try check(unchanged.status, .unchanged)
        let after = try await fixture.eval(snapshot) as? String
        try check(before, after)
        let released = try await fixture.inspect(.release, inspectionID)
        try check(released.status, .released)
        let expired = try await fixture.inspect(.revalidate, inspectionID)
        try check(expired.status, .expired)
    }

    func testChatGPTSurface() async throws { try await verify(chatGPT) }
    func testClaudeSurface() async throws { try await verify(claude) }
    func testGeminiSurface() async throws { try await verify(gemini) }
    func testPerplexitySurface() async throws { try await verify(perplexity) }
    func testPoeSurface() async throws { try await verify(poe) }

    func testUnfocusedEditorAndAmbiguousSurfaces() async throws {
        let fixture = try await open(chatGPT)
        try await requireNavigationIdentity(fixture)
        _ = try await fixture.eval("document.querySelector('aside textarea').focus()")
        let id = UUID()
        let bound = try await fixture.inspect(.bind, id)
        try check(bound.status, .bound)
        let focused = try await fixture.eval("document.activeElement === document.querySelector('aside textarea')")
        try check(focused as? Bool, true)
        _ = try await fixture.eval("document.querySelector('main').append(document.querySelector('form').cloneNode(true))")
        let old = try await fixture.inspect(.revalidate, id)
        let new = try await fixture.inspect(.bind, UUID())
        try check(old.status, .changed)
        try check(new.status, .ambiguous)
    }

    func testNewDraftNavigationAndRetainedEditorAfterRoundTrip() async throws {
        let fixture = try await open(claude)
        try await requireNavigationIdentity(fixture)
        let id = UUID()
        let bound = try await fixture.inspect(.bind, id)
        try check(bound.status, .bound)
        _ = try await fixture.eval("history.pushState(null,'','/chat/other'); history.pushState(null,'','/new');")
        let result = try await fixture.inspect(.revalidate, id)
        try check(result.status, .changed)
        _ = try await fixture.eval("history.pushState(null,'','/chat/other')")
        let staleHostAddress = try await fixture.inspect(.bind, UUID())
        try check(staleHostAddress.status, .unsupportedRoute)
    }

    func testChangedSelectionTextAttachmentOrReinsertedEditor() async throws {
        let fixture = try await open(chatGPT)
        try await requireNavigationIdentity(fixture)
        for mutation in [
            "const e=document.querySelector('[contenteditable]'); document.getSelection().setBaseAndExtent(e.firstChild,1,e.firstChild,4)",
            "document.querySelector('[contenteditable]').firstChild.data='Revised sample'",
            "const e=document.querySelector('[data-testid=attachment-preview]'); e.replaceWith(e.cloneNode(true))",
            "const e=document.querySelector('[contenteditable]'), p=e.parentNode; e.remove(); p.prepend(e)"
        ] {
            let id = UUID()
            let bound = try await fixture.inspect(.bind, id)
            try check(bound.status, .bound)
            _ = try await fixture.eval("(() => {\(mutation)})()")
            let changed = try await fixture.inspect(.revalidate, id)
            try check(changed.status, .changed)
            _ = try await fixture.inspect(.release, id)
        }
    }

    func testMissingAndAmbiguousAttachmentEntryStayDiagnostic() async throws {
        let fixture = try await open(gemini)
        try await requireNavigationIdentity(fixture)
        _ = try await fixture.eval("document.querySelector('input-area').append(document.querySelector('button').cloneNode(true))")
        let duplicate = try await fixture.inspect(.bind, UUID())
        try check(duplicate.status, .bound)
        try check(duplicate.entry, .ambiguous)
        _ = try await fixture.eval("document.querySelectorAll('button').forEach(b=>b.remove())")
        let missing = try await fixture.inspect(.bind, UUID())
        try check(missing.status, .bound)
        try check(missing.entry, .missing)
    }

    func testClickWitnessCrossesContentWorldsOnlyOnOriginalElements() async throws {
        let fixture = try await open(chatGPT)
        try await requireNavigationIdentity(fixture)
        let id = UUID().uuidString
        let pin = "(\(chromeProgram))({action:'pinTarget',clickWitnessID:'\(id)',address:'https://chatgpt.com/c/sample'},{})"
        let bound = try await fixture.eval(pin, in: fixture.world) as? String
        try check(bound, "bound")
        let capture = "(\(chromeProgram))({action:'captureTarget',clickWitnessID:'\(id)'},{applicationID:'com.google.Chrome',sessionID:'test',windowID:'1',tabID:'2'})"
        let target = try await fixture.eval(capture) as? [String: Any]
        try check(target?["clickBindingID"] as? String, id)
        let second = try await open(chatGPT)
        let checked = "(()=>{try{\(capture);return 'retargeted';}catch(e){return e.message;}})()"
        let missing = try await second.eval(checked) as? String
        try check(missing, "CLICK_PIN_REFUSED")
    }

    func testOtherDocumentCannotRevalidateOriginalClick() async throws {
        let first = try await open(chatGPT)
        let second = try await open(chatGPT)
        try await requireNavigationIdentity(first)
        let id = UUID()
        let before = try await first.inspect(.bind, id)
        try check(before.status, .bound)
        let other = try await second.inspect(.revalidate, id)
        try check(other.status, .expired)
        let original = try await first.inspect(.revalidate, id)
        try check(original.status, .unchanged)
    }

}


enum SurfaceHostError: Error { case navigationAPIUnavailable }

@main
struct ConversationSurfaceHost {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 3,
              let source = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8),
              let chromeProgram = try? String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8) else {
            print("Expected the bundled surface and Chrome JS source paths")
            exit(1)
        }
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let scenarios = SurfaceScenarios(source: source, chromeProgram: chromeProgram)
        let tests: [(String, () async throws -> Void)] = [
            ("ChatGPT", scenarios.testChatGPTSurface), ("Claude", scenarios.testClaudeSurface),
            ("Gemini", scenarios.testGeminiSurface), ("Perplexity", scenarios.testPerplexitySurface),
            ("Poe", scenarios.testPoeSurface), ("unfocused and ambiguous drafts", scenarios.testUnfocusedEditorAndAmbiguousSurfaces),
            ("same-page navigation round trip", scenarios.testNewDraftNavigationAndRetainedEditorAfterRoundTrip),
            ("selection, text, attachment and editor changes", scenarios.testChangedSelectionTextAttachmentOrReinsertedEditor),
            ("missing and duplicate attachment buttons", scenarios.testMissingAndAmbiguousAttachmentEntryStayDiagnostic),
            ("same route in another document", scenarios.testOtherDocumentCannotRevalidateOriginalClick),
            ("Chrome click witness across isolated and page content worlds", scenarios.testClickWitnessCrossesContentWorldsOnlyOnOriginalElements)
        ]
        for (name, run) in tests {
            do { try await run(); print("PASS [simulated WebKit DOM] \(name)") }
            catch SurfaceHostError.navigationAPIUnavailable {
                print("NOT_RUN [WebKit Navigation API unavailable; refusal verified] \(name)")
                exit(77)
            }
            catch let CheckError.failed(line) {
                print("FAIL [simulated WebKit DOM] \(name) assertion line \(line)")
                exit(1)
            }
            catch {
                let err = error as NSError
                print("FAIL [simulated WebKit DOM] \(name) \(err.domain) \(err.code)")
                exit(1)
            }
        }
    }
}
