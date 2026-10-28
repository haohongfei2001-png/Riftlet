import AppKit
import RiftletFeedback
import RiftletFeedbackUI

@MainActor
final class DemoDelegate: NSObject,NSApplicationDelegate {
    private var controller:FeedbackWindowController?
    func applicationDidFinishLaunching(_ notification:Notification){
        Task {
            do {
                let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!.appendingPathComponent("Riftlet-Feedback-Demo")
                let store=try await Task.detached{try FeedbackStore(directory:root)}.value
                let engine=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:DemoFeedbackTransport())
                let diagnostics=FeedbackDiagnostics();diagnostics.record(.queueUnknown);diagnostics.record(.visibilitySwallowed);diagnostics.record(.phaseUnknown)
                controller=FeedbackWindowController(engine:engine,diagnostics:diagnostics,appVersion:"0.1.0",demo:true)
                controller?.show()
            } catch {fputs("Feedback demo store unavailable; no network or screenshot access.\n",stderr);NSApp.terminate(nil)}
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
let app=NSApplication.shared
let delegate=DemoDelegate()
app.delegate=delegate;app.setActivationPolicy(.regular)
withExtendedLifetime(delegate){app.run()}
