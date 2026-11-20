// Read-only measurement from this executable's own permission context.
// Never launch a receiver, prompt, send a page event, or inspect a browser window.
import AppKit
import Carbon
import Darwin

@main struct ReceiverProbe {
    static func birth(_ pid: pid_t) -> (UInt64, UInt64)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_pid == UInt32(pid), info.pbi_start_tvsec > 0,
              info.pbi_start_tvusec < 1_000_000 else { return nil }
        return (info.pbi_start_tvsec, info.pbi_start_tvusec)
    }

    // Only permit extra runtime checks on the disposable browser forked by the
    // same fixture runner. Never select a daily browser by its bundle ID.
    static func ownedSibling(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size &&
            info.pbi_pid == UInt32(pid) && info.pbi_ppid == UInt32(getppid())
    }

    static func checkWindowCount(_ target: NSAppleEventDescriptor) -> [String: Any] {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAECountElements),
                                           targetDescriptor: target, returnID: -1, transactionID: 0)
        event.setParam(.null(), forKeyword: AEKeyword(keyDirectObject))
        event.setParam(NSAppleEventDescriptor(typeCode: OSType(cWindow)), forKeyword: AEKeyword(keyAEObjectClass))
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
            if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
                return ["errorOSStatus": Int(error.int32Value)]
            }
            guard let count = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return ["noCountReply": true] }
            return ["windowCount": Int(count.int32Value)]
        } catch { return ["errorOSStatus": (error as NSError).code] }
    }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 2 || (args.count == 3 && Int32(args[2]) != nil) else { exit(2) }
        let ownedPID: pid_t? = args.count == 3 ? Int32(args[2]) : nil
        if let ownedPID, !ownedSibling(ownedPID) { exit(2) }
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { exit(2) }
        let receivers = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter {
            (!$0.isTerminated && (ownedPID == nil || $0.processIdentifier == ownedPID)) && $0.bundleURL?.resolvingSymlinksInPath().path == url.path
        }
        let samples: [[String: Any]] = receivers.map { app in
            let pid = app.processIdentifier
            guard let before = birth(pid) else { return ["stableKernelBirth": false] }
            let target = NSAppleEventDescriptor(processIdentifier: pid)
            let code = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
            let stable = birth(pid).map { $0 == before } ?? false
            var sample: [String: Any] = ["stableKernelBirth": stable, "nonPromptingPermissionOSStatus": Int(code)]
            if stable, ownedPID == pid && code == noErr {
                sample["ownedFixtureNativeCount"] = checkWindowCount(target)
            }
            return sample
        }
        let report: [String: Any] = ["runningReceiversForExactBundlePath": receivers.count,
                                     "probeSenderOnly": samples,
                                     "signedCandidatePermission": "NOT_RUN"]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report))
    }
}
