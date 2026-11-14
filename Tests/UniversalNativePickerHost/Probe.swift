import AppKit
import ApplicationServices
import WebKit
import CryptoKit

/// Cooperating native host fixture. The window is never ordered front and the
/// application cannot activate. Apple's open-panel callback supplies the file.
@main
private struct Run {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 3,
              let port = UInt16(CommandLine.arguments[1]), port > 0 else { exit(64) }
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard root.lastPathComponent.hasPrefix("riftlet-native-picker-") else { exit(64) }
        let app = NSApplication.shared
        if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
        guard app.activationPolicy() == .prohibited else { exit(65) }
        let probe = Probe(port: port, root: root)
        probe.begin()
        withExtendedLifetime(probe) { app.run() }
    }
}

@MainActor
private final class Probe: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    let destination: URL
    let root: URL
    let view: WKWebView
    let window: NSWindow
    let ticket = UUID().uuidString
    var next = 0
    var generation = UUID()
    var refusedReplacement = false
    var delivery: NativePickerFileDelivery?
    var navigationCount = 0
    var released = 0

    init(port: UInt16, root: URL) {
        destination = URL(string: "http://127.0.0.1:\(port)/draft")!
        self.root = root
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 360, height: 240), configuration: config)
        window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.contentView = view
        view.navigationDelegate = self
        view.uiDelegate = self
        config.userContentController.add(self, name: "fixture")
    }

    func begin() {
        view.load(URLRequest(url: destination))
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.fail("TIMEOUT") }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = webView === view && action.request.url == destination && navigationCount == 0
            && action.targetFrame?.isMainFrame == true
        decisionHandler(allowed ? .allow : .cancel)
        if allowed { navigationCount += 1; generation = UUID() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === view, webView.url == destination, navigationCount == 1 else { fail("NAVIGATION") }
        startNext()
    }

    func deliveryFor(_ file: URL) -> NativePickerFileDelivery? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return NativePickerFileDelivery(window: window, view: view, document: destination, generation: generation,
            privateDirectory: root, file: file, byteCount: Int64(data.count), sha256: hash)
    }

    func startNext() {
        guard delivery == nil, next < 2, !window.isVisible, window.contentView === view else { fail("HOST_BOUNDARY") }
        let index = next
        next += 1
        delivery = deliveryFor(root.appendingPathComponent("neutral-\(index).png"))
        guard delivery != nil else { fail("FILE_BINDING") }
        // The fixture retains exact DOM object references across both operations.
        // Only the fixture's unique native file input can request this callback.
        view.evaluateJavaScript("window.pick('\(ticket)', \(index))") { result, error in
            if error != nil || result as? Bool != true { self.fail("DRAFT_CHANGED") }
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let input = NativePickerFileDelivery.Input(view: webView, frame: frame, parameters: parameters, generation: generation)
        if next == 1 {
            // A different inode with identical content must fail at the last handoff.
            let scratch = root.appendingPathComponent("neutral-replacement.png")
            guard let bytes = try? Data(contentsOf: root.appendingPathComponent("neutral-0.png")),
                  (try? bytes.write(to: scratch, options: .withoutOverwriting)) != nil,
                  let old = deliveryFor(scratch), (try? bytes.write(to: scratch, options: .atomic)) != nil,
                  old.handOff(input) == nil else { completionHandler(nil); fail("PATH_REPLACED") }
            refusedReplacement = true
        }
        guard !window.isVisible, let capability = delivery, released + 1 == next,
              let files = capability.handOff(input),
              capability.handOff(input) == nil else {
            completionHandler(nil); fail("PICKER_CHANGED")
        }
        delivery = nil
        released += 1
        completionHandler(files)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === view, message.frameInfo.isMainFrame,
              message.frameInfo.request.url == destination, view.url == destination,
              let data = message.body as? [String: Any], data["ticket"] as? String == ticket,
              data["index"] as? Int == next - 1, data["state"] as? String == "receipt",
              data["intact"] as? Bool == true, delivery == nil, released == next else { fail("RECEIPT") }
        if next == 1 { startNext(); return }
        guard next == 2, refusedReplacement, !window.isVisible, NSApp.activationPolicy() == .prohibited else { fail("UNEXPECTED_STATE") }
        print("{\"openPanelCallbacks\":2,\"filesReleased\":2,\"duplicateHandoffsRefused\":2,\"sameBytesPathReplacementRefused\":true,\"draftAcknowledgements\":2,\"previousAttachmentsTextSelectionPreserved\":true,\"editorUnfocused\":true,\"windowNeverOrdered\":true,\"axTrustedForProbeProcess\":\(AXIsProcessTrusted())}")
        exit(0)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("CONTENT_PROCESS_EXITED") }
    func fail(_ code: String) -> Never { fputs("native-picker fixture: \(code)\n", stderr); exit(1) }
}
