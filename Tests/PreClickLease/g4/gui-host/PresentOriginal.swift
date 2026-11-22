import AppKit
import Carbon
import Foundation
@testable import RiftletAdapters

// A bounded presentation action for a previously created dedicated Temporary Chat.
// Only its window descriptor is mutated. The app is activated only after that
// window's original tab is confirmed selected in the application.
@main enum PresentOriginal {
    typealias Row = [String:Any]
    static func need(_ b:Bool,_ why:String)throws{if !b{throw Identity.Refusal(why)}}
    static func read(_ u:URL)throws->Row{guard let r=try JSONSerialization.jsonObject(with:Data(contentsOf:u)) as? Row else{throw Identity.Refusal("UNREADABLE_RECEIPT")};return r}
    @MainActor static func run()throws->Row{
        let args=CommandLine.arguments
        try need(args.count==3,"PREVIOUSLY_ENROLLED_SCOPE_REQUIRED")
        let state=URL(fileURLWithPath:args[1],isDirectory:true),fam=args[2]
        let c=try read(state.appendingPathComponent("creation.json")),b=try read(state.appendingPathComponent("before.json")),n=try read(state.appendingPathComponent("original-entry.json")),local=try read(state.appendingPathComponent("challenge.json"))
        guard let p=c["pid"] as? Int32,let v=Identity.families[fam],let wid=c["windowID"] as? String,let tid=c["tabID"] as? String,let birth=c["sessionID"] as? String,let doc=local["doc"] as? String,let previous=b["windowIDs"] as? [String],
              c["family"] as? String==fam,b["sessionID"] as? String==birth,b["dynamicSignature"] as? Bool==true,c["phase"] as? String=="qaAddressConfirmed",!previous.contains(wid),
              local["windowID"] as? String==wid,local["tabID"] as? String==tid,local["sessionID"] as? String==birth,local["dynamicSignature"] as? Bool==true,n["sourceDoc"] as? String==doc,UUID(uuidString:doc) != nil else{throw Identity.Refusal("ORIGINAL_CREATE_AND_NAVIGATION_REQUIRED")}
        let proc=try Identity.certified(v,expectedPID:p)
        let w=try Identity.object("cwin","ID  ",.init(string:wid)),t=try Identity.object("CrTb","ID  ",.init(string:tid),w)
        func original()throws{
            try need(proc.isCurrent() && proc.session==birth,"BIRTH_CHANGED")
            try need(try Owned.tabIDs(proc,window:w)==[tid] && Identity.get(proc,Identity.property("URL ",t)).stringValue==QAOriginalBrowserTab.temporaryChat,"ORIGINAL_TAB_CHANGED")
            let r=try Owned.request(proc,"CrSu","ExJa",["----":t,"JvSc":.init(string:"JSON.stringify([navigation.currentEntry.id,performance.timeOrigin])")])
            guard let s=r.stringValue, let j=try JSONSerialization.jsonObject(with:Data(s.utf8)) as? [Any], j.count==2,j[0] as? String==n["entryID"] as? String,j[1] as? Double==n["timeOrigin"] as? Double else{throw Identity.Refusal("ORIGINAL_DOCUMENT_CHANGED")}
        }
        let f=try Identity.object("cwin","indx",.init(int32:1))
        func selected()throws->Bool{let x=ChromeActiveTabDescriptor.identity(in:try Identity.get(proc,Identity.property("acTa",f)));return x?.window==wid && x?.tab==tid}
        let front=NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let guards=["com.apple.UserNotificationCenter","com.apple.SecurityAgent","com.apple.CoreAuthUI","com.apple.loginwindow","com.apple.ScreenSaver.Engine"]
        try need(front != nil && !guards.contains(front!),"PROTECTED_FOREGROUND")
        let sess=CGSessionCopyCurrentDictionary() as? Row
        try need(sess?[kCGSessionOnConsoleKey as String] as? Bool==true && sess?[kCGSessionLoginDoneKey as String] as? Bool==true && sess?["CGSSessionScreenIsLocked"] as? Bool != true && CGDisplayIsAsleep(CGMainDisplayID())==0,"DESKTOP_UNAVAILABLE")
        try original();let before=try selected()
        var r:Row=["beforeSelected":before,"beforeForeground":NSWorkspace.shared.frontmostApplication?.processIdentifier==p,"selectionRequestIssued":false,"ownedWindowRestored":false,"appActivationIssued":false]
        if !before {
            _=try Owned.request(proc,"core","setd",["----":Identity.property("pidx",w),"data":.init(int32:1)])
            r["selectionRequestIssued"]=true
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.24))
        }
        if try !selected() {
            try original()
            _=try Owned.request(proc,"core","setd",["----":Identity.property("pmnd",w),"data":.init(boolean:true)])
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.25));try original()
            _=try Owned.request(proc,"core","setd",["----":Identity.property("pmnd",w),"data":.init(boolean:false)])
            _=try Owned.request(proc,"core","setd",["----":Identity.property("pidx",w),"data":.init(int32:1)])
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.45));r["ownedWindowRestored"]=true
        }
        try original();let own=try selected();r["originalSelected"]=own
        if own && NSWorkspace.shared.frontmostApplication?.processIdentifier != p,let app=NSRunningApplication(processIdentifier:p){
            r["appActivationIssued"]=true;r["appActivationReturned"]=app.activate(options:[])
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.4))
        }
        try original();r["originalSelected"]=try selected();r["systemForeground"]=NSWorkspace.shared.frontmostApplication?.processIdentifier==p
        return r
    }
    @MainActor static func main(){do{FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:run(),options:.sortedKeys))}catch{FileHandle.standardError.write(Data(((error as? Identity.Refusal)?.reason ?? "RESTORE_UNAVAILABLE").utf8));exit(1)}}
}
