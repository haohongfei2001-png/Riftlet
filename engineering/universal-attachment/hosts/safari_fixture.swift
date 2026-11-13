import AppKit
import Carbon
import Foundation

func main() -> Int32 {
    let env = ProcessInfo.processInfo.environment
    guard env["GITHUB_ACTIONS"] == "true", env["RUNNER_ENVIRONMENT"] == "github-hosted" else {
        print("NOT_RUN_HOSTED_CONSOLE_REQUIRED"); return 77
    }
    guard CommandLine.arguments.count == 3, let url = URLComponents(string: CommandLine.arguments[2]),
          url.scheme == "http", url.host == "127.0.0.1", let port = url.port, (1...65535).contains(port),
          url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
          url.path.range(of: #"^/draft/[0-9a-f]{32}$"#, options: .regularExpression) != nil else { return 64 }
    let id = "com.apple.Safari"
    func running() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
    }
    guard running().isEmpty, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
        print("NOT_RUN_NO_EXCLUSIVE_SAFARI_LAUNCH"); return 77
    }
    // LaunchServices starts one ordinary Safari on a disposable hosted console.
    // Per-process Automation preflight occurs before any AppleScript event.
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    var app: NSRunningApplication?
    var finished = false
    NSWorkspace.shared.openApplication(at: appURL, configuration: config) { result, _ in app = result; finished = true }
    let until = ProcessInfo.processInfo.systemUptime + 7
    while !finished && ProcessInfo.processInfo.systemUptime < until {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    guard let original = app, original.bundleIdentifier == id else { print("NOT_RUN_SAFARI_LAUNCH_UNAVAILABLE"); return 77 }
    defer { _ = original.terminate() }
    func sameProcess() -> Bool {
        !original.isTerminated && running().count == 1 && running().first?.processIdentifier == original.processIdentifier
    }
    guard sameProcess() else { print("NOT_RUN_SAFARI_PROCESS_CHANGED"); return 77 }
    let receiver = NSAppleEventDescriptor(processIdentifier: original.processIdentifier)
    let permission = AEDeterminePermissionToAutomateTarget(receiver.aeDesc, typeWildCard, typeWildCard, false)
    guard permission == noErr else { print("NOT_RUN_SAFARI_AUTOMATION_OSSTATUS_\(permission)"); return 77 }
    guard let src = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8),
          let script = NSAppleScript(source: src) else { return 1 }
    let command = NSAppleEventDescriptor(eventClass: UInt32(kASAppleScriptSuite), eventID: UInt32(kASSubroutineEvent),
                                         targetDescriptor: nil, returnID: -1, transactionID: 0)
    command.setParam(.init(string: "exercise"), forKeyword: UInt32(keyASSubroutineName))
    let args = NSAppleEventDescriptor.list()
    args.insert(.init(string: CommandLine.arguments[2]), at: 1)
    command.setParam(args, forKeyword: UInt32(keyDirectObject))
    var failure: NSDictionary?
    let result = script.executeAppleEvent(command, error: &failure)
    if let failure {
        let code = failure[NSAppleScript.errorNumber] as? Int ?? -1
        print("SAFARI_SCRIPT_OSSTATUS_\(code)")
        return [Int(errAEEventNotPermitted), Int(errAEEventWouldRequireUserConsent), -1712].contains(code) ? 77 : 1
    }
    guard sameProcess() else { print("SAFARI_PROCESS_CHANGED"); return 1 }
    if let result = result.stringValue, result.hasPrefix("javascript-unavailable:"),
       let code = Int(result.dropFirst("javascript-unavailable:".count)) {
        print("NOT_RUN_SAFARI_JAVASCRIPT_EVENTS_DISABLED_OSSTATUS_\(code)"); return 77
    }
    guard result.stringValue == "verified-neutral-documents" else { print("SAFARI_IDENTITY_UNVERIFIED"); return 1 }
    print("SAFARI_TWO_TABS_TWO_WINDOWS_AND_SHIFT_VERIFIED")
    return 0
}
exit(main())
