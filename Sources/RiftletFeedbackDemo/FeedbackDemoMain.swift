import AppKit
import RiftletFeedback
import RiftletFeedbackUI

/// Not a network credential: deterministic only for the offline demonstration,
/// allowing its own local reports to remain viewable after a demo restart.
private struct OfflineDemoSecrets: FeedbackSecretStorage {
    func secret(for id: String, create: Bool) throws -> String {
        let compact = id.replacingOccurrences(of: "-", with: "").lowercased()
        guard compact.count == 32 else { throw FeedbackFailure.secretUnavailable }
        return compact + compact
    }
}

@MainActor
private final class DemoDelegate: NSObject, NSApplicationDelegate {
    private var controller: FeedbackWindowController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Riftlet-Feedback-Demo")
                let store = try await Task.detached { try FeedbackStore(directory: root) }.value
                let engine = FeedbackEngine(store: store, secrets: OfflineDemoSecrets(), transport: DemoFeedbackTransport())
                let diagnostics = FeedbackDiagnostics()
                diagnostics.record(.queueUnknown); diagnostics.record(.visibilitySwallowed); diagnostics.record(.phaseUnknown)
                controller = FeedbackWindowController(engine: engine, diagnostics: diagnostics, appVersion: "0.1.0", demo: true)
                controller?.show()
            } catch {
                fputs("Feedback demo store unavailable; no network or screenshot access.\n", stderr)
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller?.show() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        Task {
            let saved = await controller.saveBeforeClosing()
            if !saved { controller.show() }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}

@main
private enum FeedbackDemoMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = DemoDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
