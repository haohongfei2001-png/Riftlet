#!/usr/bin/env python3
"""One-shot fingerprint-guarded wiring on the isolated implementation branch.
The resulting Swift/Package files are committed for review; never a runtime hook.
"""
import pathlib, subprocess
root=pathlib.Path(__file__).resolve().parents[1]
branch=subprocess.check_output(['git','branch','--show-current'],cwd=root,text=True).strip()
if branch != 'codex/feedback-v01-20261028':
    raise SystemExit('Refuse host wiring outside the isolated feedback branch')
p=root/'Sources/RiftletApp/RiftletMain.swift'
s=p.read_text()
if 'private lazy var feedback = FeedbackHost' in s:
    raise SystemExit(0)
expected={'Sources/RiftletApp/RiftletMain.swift':'98562d4494c241fbcc167e3c92416f8351f692f6','Package.swift':'5903d370088c75c20e1c3bc6d9cf2606fc9183fa'}
for path,sha in expected.items():
    actual=subprocess.check_output(['git','hash-object',path],cwd=root,text=True).strip()
    if actual!=sha:raise SystemExit('Shared source changed; no overwrite: '+path)
def replace(old,new):
    global s
    if s.count(old)!=1:raise SystemExit('Nonunique host boundary: '+old[:70])
    s=s.replace(old,new)
replace('import RiftletAdapters\n','import RiftletAdapters\nimport RiftletFeedback\n')
replace('    private var statusItem: NSStatusItem?', '    private lazy var feedback = FeedbackHost(modeDirectory: mode.directoryName)\n    private var statusItem: NSStatusItem?')
replace('        installMenu()\n        installSetup()', '        installMenu()\n        _ = feedback // Independent sidecar initializes off the screenshot path.\n        installSetup()')
replace('                setupIssue = .initializationFailed', '                feedback.diagnostics.record(.initializationIssue)\n                setupIssue = .initializationFailed')
replace('    func applicationWillTerminate(_ notification: Notification) {', '''    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        feedback.prepareTermination { accepted in sender.reply(toApplicationShouldTerminate: accepted) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {''')
replace('        captureDiagnostic = value\n        switch value.code {','        feedback.capture(value)\n        captureDiagnostic = value\n        switch value.code {')
replace('    @objc private func showSetup()', '    @objc private func showFeedback() { feedback.open() }\n\n    @objc private func showSetup()')
replace('        add(menu, "开始使用与运行状态…", #selector(showSetup))','        add(menu, "开始使用与运行状态…", #selector(showSetup))\n        add(menu, "反馈与建议…", #selector(showFeedback))')
replace('                rift?.render(snapshot)', '''                rift?.render(snapshot)
                feedback.assets(snapshot) // Sampled local counts, not operation-level statistics.
                feedback.operations(successful + unresolved)
                if interactionFence.snapshot().blocked { feedback.diagnostics.record(.uiProjectionDeferred) }''')
replace('            } catch { showIssue("Queue read failed; durable data is preserved.") }','            } catch { feedback.diagnostics.record(.queueReadIssue); showIssue("Queue read failed; durable data is preserved.") }')
replace('                    self.cancelOriginalSelection(originalSelection, reason: "selectionRejected")','                    self.feedback.diagnostics.record(.selectionRejected)\n                    self.cancelOriginalSelection(originalSelection, reason: "selectionRejected")')
replace('            let originalSelection = accepted','            if accepted != nil { self.feedback.diagnostics.record(.selectionAccepted) }\n            let originalSelection = accepted')
replace('        automationPermission = state\n        guard mode.usesWebAdapter','        automationPermission = state\n        if mode.usesWebAdapter, state != .granted { feedback.diagnostics.record(.permissionUnavailable) }\n        guard mode.usesWebAdapter')
p.write_text(s)
p=root/'Package.swift';s=p.read_text()
s=s.replace('.executable(name: "RiftletGUIAcceptance", targets: ["RiftletGUIAcceptance"])','.executable(name: "RiftletFeedbackDemo", targets: ["RiftletFeedbackDemo"]),\n        .executable(name: "RiftletGUIAcceptance", targets: ["RiftletGUIAcceptance"])')
s=s.replace('        .target(name: "RiftletCore",', '        .target(name: "RiftletFeedback", dependencies: ["CSQLite"]),\n        .target(name: "RiftletFeedbackUI", dependencies: ["RiftletFeedback"]),\n        .executableTarget(name: "RiftletFeedbackDemo", dependencies: ["RiftletFeedback", "RiftletFeedbackUI"]),\n        .testTarget(name: "RiftletFeedbackTests", dependencies: ["RiftletFeedback", "CSQLite"]),\n        .testTarget(name: "RiftletFeedbackUITests", dependencies: ["RiftletFeedbackUI", "RiftletFeedback"]),\n        .target(name: "RiftletCore",')
s=s.replace('.executableTarget(name: "RiftletApp", dependencies: ["RiftletCore", "RiftletCapture", "RiftletUI", "RiftletAdapters"])', '.executableTarget(name: "RiftletApp", dependencies: ["RiftletCore", "RiftletCapture", "RiftletUI", "RiftletAdapters", "RiftletFeedback", "RiftletFeedbackUI"])')
p.write_text(s)
print('Applied isolated feedback menu, typed observations, termination flush and Package targets.')
