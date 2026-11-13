import AppKit
import WebKit

/// Development prototype for a cooperating native WebKit host. The host owns the
/// page and the open-panel delegate. A callback in an unrelated app cannot be
/// intercepted with this API. There is no App registration or positive receipt.
@MainActor
final class NativePickerFileDelivery: AttachmentTransport {
    struct Input {
        let view: WKWebView
        let frame: WKFrameInfo
        let parameters: WKOpenPanelParameters
        let generation: UUID
    }
    private weak var window: NSWindow?
    private weak var view: WKWebView?
    private let document: URL
    private let generation: UUID
    private let file: URL
    private let pinned: NativeMacVerifiedFile
    private var consumed = false

    /// The caller creates this capability once at the click boundary, for its
    /// original private file. The isolated fixture exercises only a local draft.
    init?(window: NSWindow, view: WKWebView, document: URL, generation: UUID,
          privateDirectory: URL, file: URL, byteCount: Int64, sha256: String) {
        guard view.window === window, !view.configuration.websiteDataStore.isPersistent,
              view.url == document, document.scheme == "http", document.host == "127.0.0.1",
              document.port != nil, document.user == nil, document.password == nil,
              document.path == "/draft", document.query == nil, document.fragment == nil,
              privateDirectory.isFileURL, file.isFileURL, file.pathExtension == "png",
              file.deletingLastPathComponent().standardizedFileURL == privateDirectory.standardizedFileURL,
              file.resolvingSymlinksInPath().path == file.standardizedFileURL.path else { return nil }
        guard let verified = try? NativeMacVerifiedFile(fileURL: file, mediaDirectory: privateDirectory.standardizedFileURL,
            name: file.lastPathComponent, byteCount: byteCount, sha256: sha256) else { return nil }
        pinned = verified
        self.window = window
        self.view = view
        self.document = document
        self.generation = generation
        self.file = file
    }

    /// Even a refused callback burns this capability. No action searches another
    /// view, chooses a new target or concludes an upload started. The host owns
    /// `input.generation` and must rotate it on navigation and draft replacement.
    func handOff(_ input: Input) -> [URL]? {
        let current = input.view
        let frame = input.frame
        let parameters = input.parameters
        guard !consumed else { return nil }
        consumed = true
        guard let window, let original = view, current === original, current.window === window,
              current.url == document, input.generation == generation,
              frame.webView === original, frame.isMainFrame, frame.request.url == document,
              frame.securityOrigin.protocol == "http", frame.securityOrigin.host == "127.0.0.1",
              frame.securityOrigin.port == document.port,
              !parameters.allowsMultipleSelection, !parameters.allowsDirectories else { return nil }
        do { try pinned.verifyBytes() } catch { return nil }
        return [file]
    }
}
