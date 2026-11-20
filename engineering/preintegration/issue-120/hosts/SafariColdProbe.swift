// Run only on a disposable macOS guest. Its initially empty Safari session
// must already display the single local fixture created by safari-guest.sh.
import AppKit
import Carbon

struct ProbeError: Error { let number: Int }

func runScript(_ source: String) throws -> NSAppleEventDescriptor {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)!.executeAndReturnError(&error)
    if let error { throw ProbeError(number: error[NSAppleScript.errorNumber] as? Int ?? -1) }
    return result
}

@main struct SafariColdProbe {
    static func main() throws {
        let args = CommandLine.arguments
        let requestOnGuest = args.count == 4 && args[2] == "--request-on-disposable-vm"
        guard (args.count == 2 || requestOnGuest),
              let fixture = URL(string: CommandLine.arguments[1]),
              fixture.isFileURL, fixture.lastPathComponent == "RiftletHostFixture.html",
              fixture.deletingLastPathComponent().lastPathComponent.hasPrefix("riftlet-120-"),
              !fixture.absoluteString.contains("\""),
              let receiver = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").only else { exit(2) }
        let pidTarget = NSAppleEventDescriptor(processIdentifier: receiver.processIdentifier)
        if requestOnGuest {
            var model = [CChar](repeating: 0, count: 128), size = 128
            guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0, String(cString: model) == "VirtualMac2,1",
                  URL(fileURLWithPath: args[3]).deletingLastPathComponent() == fixture.deletingLastPathComponent()
            else { exit(2) }
        }
        let before = AEDeterminePermissionToAutomateTarget(pidTarget.aeDesc, typeWildCard, typeWildCard, false)
        let status = requestOnGuest && before == errAEEventWouldRequireUserConsent
            ? AEDeterminePermissionToAutomateTarget(pidTarget.aeDesc, typeWildCard, typeWildCard, true) : before
        var result: [String: Any] = ["initialNonpromptingStatus": Int(before), "requestedInDisposableVM": requestOnGuest, "automationStatusForProbeSender": Int(status), "signedCandidatePermission": "NOT_RUN",
                                     "lateSlotBinding": "NOT_RUN", "pageJavaScriptFromAppleEvents": "NOT_RUN"]
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                if requestOnGuest { try? data.write(to: URL(fileURLWithPath: args[3]), options: .atomic) }
                else { FileHandle.standardOutput.write(data) }
            }
        }
        guard status == noErr else { return }
        do {
            let descriptor = try runScript("""
                tell application id "com.apple.Safari"
                    if (count windows) is not 1 then error number -2700
                    if (count tabs of front window) is not 1 then error number -2700
                    if URL of current tab of front window is not "\(fixture.absoluteString)" then error number -2700
                    return current tab of front window
                end tell
                """)
            let fields: NSAppleEventDescriptor? = descriptor.coerce(toDescriptorType: DescType(typeAERecord))
            let form: NSAppleEventDescriptor? = fields?.forKeyword(AEKeyword(keyAEKeyForm))
            let key: OSType? = form?.enumCodeValue
            result["tabSpecifierKeyForm"] = key.map { String(format: "%08x", $0) } ?? "UNREADABLE"
            do {
                let js = try runScript("""
                    tell application id "com.apple.Safari"
                        if URL of current tab of front window is not "\(fixture.absoluteString)" then error number -2700
                        return do JavaScript "typeof window.riftletFixtureSentinel" in current tab of front window
                    end tell
                    """)
                result["pageJavaScriptFromAppleEvents"] = js.stringValue == "string" ? "READ_PAGE_SENTINEL" : "SENTINEL_NOT_VISIBLE"
            } catch let error as ProbeError { result["pageJavaScriptFromAppleEvents"] = ["error": error.number] }
            let moved = try runScript("""
                tell application id "com.apple.Safari"
                    set w to front window
                    if (count tabs of w) is not 1 then error number -2700
                    set originalTab to current tab of w
                    if URL of originalTab is not "\(fixture.absoluteString)" then error number -2700
                    set firstTitle to name of originalTab
                    if firstTitle does not start with "RiftletHostFixture-" then error number -2700
                    set otherTab to make new tab at end of tabs of w with properties {URL:"\(fixture.absoluteString)"}
                    repeat 60 times
                        if name of otherTab starts with "RiftletHostFixture-" then exit repeat
                        delay 0.1
                    end repeat
                    set secondTitle to name of otherTab
                    if secondTitle does not start with "RiftletHostFixture-" or secondTitle = firstTitle then error number -2700
                    if URL of otherTab is not "\(fixture.absoluteString)" then error number -2700
                    close originalTab
                    try
                        if URL of originalTab = "\(fixture.absoluteString)" and name of originalTab = secondTitle then return "ORIGINAL_SPECIFIER_NOW_RESOLVES_TO_OTHER_DOCUMENT"
                    on error
                        return "ORIGINAL_SPECIFIER_INVALIDATED"
                    end try
                    return "INCONCLUSIVE"
                end tell
                """)
            result["lateSlotBinding"] = moved.stringValue ?? "INCONCLUSIVE"
        } catch let error as ProbeError { result["nativeReadError"] = error.number }
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
