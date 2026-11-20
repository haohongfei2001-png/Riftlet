import Foundation
import AppKit
import Carbon

@main struct Probe {
 static func main() {
    var model=[CChar](repeating:0,count:128), size=128
    guard sysctlbyname("hw.model",&model,&size,nil,0)==0, String(cString:model)=="VirtualMac2,1",
      CommandLine.arguments.count==2 else {exit(2)}
    let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
    let instances=NSRunningApplication.runningApplications(withBundleIdentifier:"com.brave.Browser")
    guard folder.deletingLastPathComponent().path=="/private/tmp", folder.lastPathComponent.hasPrefix("riftlet-120-"),
      instances.count==1, let app=instances.first, app.bundleURL?.path==folder.appendingPathComponent("Brave Browser.app").path else {exit(2)}
    let target=NSAppleEventDescriptor(processIdentifier:app.processIdentifier)
    let first=AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,false)
    let status=first == errAEEventWouldRequireUserConsent ? AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,true) : first
    var r:[String:Any]=["initialNonpromptingStatus":Int(first),"probeSenderAutomationStatus":Int(status),"signedCandidatePermission":"NOT_RUN"]
    if status==0 {
      let fixture=folder.appendingPathComponent("RiftletHostFixture.html").absoluteString
      var e:NSDictionary?
      let v=NSAppleScript(source:"""
      tell application id "com.brave.Browser"
        if (count windows) is not 1 then error number -2700
        set t to active tab of front window
        if URL of t is not "\(fixture)" then error number -2700
        return {id of front window, id of t}
      end tell
      """)!.executeAndReturnError(&e)
      r["nativeNumericWindowAndTabIDs"] = e == nil && v.numberOfItems==2 && (v.atIndex(1)?.int32Value ?? 0)>0 && (v.atIndex(2)?.int32Value ?? 0)>0
      if e==nil {
        let js=NSAppleScript(source:"""
        tell application id "com.brave.Browser"
          set t to active tab of front window
          if URL of t is not "\(fixture)" then error number -2700
          return execute t javascript "typeof window.riftletFixtureSentinel"
        end tell
        """)!.executeAndReturnError(&e)
        r["defaultJavaScriptRead"]=e==nil ? (js.stringValue=="string" ? "READ_PAGE_SENTINEL" : "OTHER_RESPONSE") : "ERROR"
      }
      if let e {r["readError"]=e[NSAppleScript.errorNumber] as? Int ?? -1}
    }
    try? JSONSerialization.data(withJSONObject:r,options:.sortedKeys).write(to:folder.appendingPathComponent("brave.json"))
 }
}
