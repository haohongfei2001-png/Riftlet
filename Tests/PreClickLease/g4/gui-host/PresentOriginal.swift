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
    static func ax(_ obj:AXUIElement,_ name:String)->CFTypeRef?{
        var value:CFTypeRef?
        return AXUIElementCopyAttributeValue(obj,name as CFString,&value) == .success ? value:nil
    }
    static func axFrame(_ obj:AXUIElement)->CGRect?{
        guard let p=ax(obj,kAXPositionAttribute as String),CFGetTypeID(p)==AXValueGetTypeID(),
              let s=ax(obj,kAXSizeAttribute as String),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
        var pos=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&pos),AXValueGetValue(s as! AXValue,.cgSize,&size) else{return nil}
        return CGRect(origin:pos,size:size)
    }
    static func same(_ a:CGRect,_ b:CGRect)->Bool{
        zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<=1}
    }
    @MainActor static func run()throws->Row{
        let args=CommandLine.arguments
        try need(args.count==3,"PREVIOUSLY_ENROLLED_SCOPE_REQUIRED")
        let state=URL(fileURLWithPath:args[1],isDirectory:true),fam=args[2]
        let c=try read(state.appendingPathComponent("creation.json")),b=try read(state.appendingPathComponent("before.json")),n=try read(state.appendingPathComponent("original-entry.json")),local=try read(state.appendingPathComponent("challenge.json"))
        guard let p=c["pid"] as? Int32,let v=Identity.families[fam],let wid=c["windowID"] as? String,let tid=c["tabID"] as? String,let birth=c["sessionID"] as? String,let doc=local["doc"] as? String,let previous=b["windowIDs"] as? [String],
              c["family"] as? String==fam,b["sessionID"] as? String==birth,b["dynamicSignature"] as? Bool==true,c["phase"] as? String=="qaAddressConfirmed",!previous.contains(wid),
              local["windowID"] as? String==wid,local["tabID"] as? String==tid,local["sessionID"] as? String==birth,local["dynamicSignature"] as? Bool==true,n["sourceDoc"] as? String==doc,UUID(uuidString:doc) != nil else{throw Identity.Refusal("ORIGINAL_CREATE_AND_NAVIGATION_REQUIRED")}
        let originalTarget=NSAppleEventDescriptor(bundleIdentifier:v.bundle)
        try need(AEDeterminePermissionToAutomateTarget(originalTarget.aeDesc,typeWildCard,typeWildCard,false)==noErr,"AE_PERMISSION_NOT_ESTABLISHED_WITHOUT_PROMPT")
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
        func available()throws{
        let front=NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let guards=["com.apple.UserNotificationCenter","com.apple.SecurityAgent","com.apple.CoreAuthUI","com.apple.loginwindow","com.apple.ScreenSaver.Engine"]
        try need(front != nil && !guards.contains(front!),"PROTECTED_FOREGROUND")
        let sess=CGSessionCopyCurrentDictionary() as? Row
        try need(sess?[kCGSessionOnConsoleKey as String] as? Bool==true && sess?[kCGSessionLoginDoneKey as String] as? Bool==true && sess?["CGSSessionScreenIsLocked"] as? Bool != true && CGDisplayIsAsleep(CGMainDisplayID())==0,"DESKTOP_UNAVAILABLE")
        guard let active=NSWorkspace.shared.frontmostApplication else{throw Identity.Refusal("UNKNOWN_FOREGROUND")}
        try need(AXIsProcessTrusted(),"AX_NOT_TRUSTED")
        let on=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [Row] ?? []
        let seen=Set(on.compactMap{$0[kCGWindowOwnerPID as String] as? Int32})
        for bundle in guards {
            for process in NSRunningApplication.runningApplications(withBundleIdentifier:bundle) where seen.contains(process.processIdentifier) {
                if let wins=ax(AXUIElementCreateApplication(process.processIdentifier),kAXWindowsAttribute as String) as? [AXUIElement]{
                    try need(!wins.contains{ax($0,kAXSubroleAttribute as String) as? String=="AXSystemDialog" || ax($0,kAXModalAttribute as String) as? Bool==true},"SYSTEM_DIALOG_ONSCREEN")
                }
            }
        }
        let app=AXUIElementCreateApplication(active.processIdentifier)
        if let wins=ax(app,kAXWindowsAttribute as String) as? [AXUIElement] {
            try need(!wins.contains{ax($0,kAXModalAttribute as String) as? Bool==true},"FOREGROUND_MODAL")
        }
        }
        func authenticated()throws{try available();try original()}
        func axCandidate()throws->(AXUIElement?,String){
            if !AXIsProcessTrusted(){return(nil,"ACCESSIBILITY_NOT_TRUSTED")}
            let app=AXUIElementCreateApplication(p)
            guard let wins=ax(app,kAXWindowsAttribute as String) as? [AXUIElement] else{return(nil,"AX_WINDOWS_UNAVAILABLE")}
            if wins.isEmpty{return(nil,"NO_AX_WINDOWS")}
            let descriptor=try Identity.get(proc,Identity.property("pbnd",w))
            guard descriptor.descriptorType==typeQDRectangle && descriptor.data.count==8 else{return(nil,"NATIVE_BOUNDS_UNAVAILABLE")}
            let corners=descriptor.data.withUnsafeBytes{b in (0..<4).map{Int(b.loadUnaligned(fromByteOffset:$0*2,as:Int16.self))}}
            let frame=CGRect(x:corners[1],y:corners[0],width:corners[3]-corners[1],height:corners[2]-corners[0])
            let matches=wins.filter{win in ax(win,kAXRoleAttribute as String) as? String=="AXWindow" && ax(win,kAXSubroleAttribute as String) as? String=="AXStandardWindow" && axFrame(win).map{same($0,frame)}==true}
            guard matches.count==1 else{return(nil,matches.isEmpty ? "AX_FRAME_MISSING":"AX_FRAME_AMBIGUOUS")}
            // Two regular native windows can share bounds. Compare every current browser
            // window's geometry only; never inspect other tabs, URLs or titles.
            let ids=try Identity.windows(proc)
            var count=0
            for other in ids {
                let candidate=try Identity.object("cwin","ID  ",.init(string:other))
                let bounds=try Identity.get(proc,Identity.property("pbnd",candidate))
                guard bounds.descriptorType==typeQDRectangle && bounds.data.count==8 else{return(nil,"NATIVE_PEER_GEOMETRY_UNAVAILABLE")}
                let v=bounds.data.withUnsafeBytes{b in (0..<4).map{Int(b.loadUnaligned(fromByteOffset:$0*2,as:Int16.self))}}
                let rect=CGRect(x:v[1],y:v[0],width:v[3]-v[1],height:v[2]-v[0])
                if same(rect,frame){count+=1}
            }
            guard count==1 else{return(nil,"NATIVE_FRAME_AMBIGUOUS")}
            let cg=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [Row] ?? []
            let visible=cg.filter{row in
                guard row[kCGWindowOwnerPID as String] as? Int32==p, row[kCGWindowLayer as String] as? Int==0,
                      let d=row[kCGWindowBounds as String] as? NSDictionary,let r=CGRect(dictionaryRepresentation:d) else{return false}
                return same(r,frame)
            }
            guard visible.count==1 else{return(nil,visible.isEmpty ? "NO_MATCHING_ONSCREEN_CG_WINDOW":"CG_FRAME_AMBIGUOUS")}
            return(matches[0],"EXACT_NATIVE_AX_CG_FRAME")
        }
        try authenticated();let before=try selected()
        var r:Row=["beforeSelected":before,"beforeForeground":NSWorkspace.shared.frontmostApplication?.processIdentifier==p,"selectionRequestIssued":false,"ownedWindowRestored":false,"appActivationIssued":false,"axRaiseIssued":false,"aeActivationIssued":false]
        if !before {
            try authenticated();_=try Owned.request(proc,"core","setd",["----":Identity.property("pidx",w),"data":.init(int32:1)])
            r["selectionRequestIssued"]=true
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.24))
        }
        if try !selected() {
            try authenticated()
            _=try Owned.request(proc,"core","setd",["----":Identity.property("pmnd",w),"data":.init(boolean:true)])
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.25));try authenticated()
            _=try Owned.request(proc,"core","setd",["----":Identity.property("pmnd",w),"data":.init(boolean:false)])
            _=try Owned.request(proc,"core","setd",["----":Identity.property("pidx",w),"data":.init(int32:1)])
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.45));r["ownedWindowRestored"]=true
        }
        try original();let own=try selected();r["originalSelected"]=own
        if own && NSWorkspace.shared.frontmostApplication?.processIdentifier != p,let app=NSRunningApplication(processIdentifier:p){
            try authenticated();r["appActivationIssued"]=true;r["appActivationReturned"]=app.activate(options:[])
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.4))
        }
        let afterNS=NSWorkspace.shared.frontmostApplication?.processIdentifier==p
        r["afterNSForeground"]=afterNS
        if !afterNS {
            try authenticated()
            let (target,why)=try axCandidate()
            r["axDisposition"]=why
            if let target {
                try authenticated()
                let (fresh,latest)=try axCandidate()
                guard let fresh, latest=="EXACT_NATIVE_AX_CG_FRAME",CFEqual(fresh,target) else{throw Identity.Refusal("AX_TARGET_CHANGED_BEFORE_RAISE")}
                let code=AXUIElementPerformAction(fresh,kAXRaiseAction as CFString)
                r["axRaiseIssued"]=true;r["axRaiseReturnCode"]=code.rawValue
                RunLoop.current.run(until:Date(timeIntervalSinceNow:0.3))
            }
        } else {r["axDisposition"]="ALREADY_FOREGROUND"}
        try original();let afterAX=NSWorkspace.shared.frontmostApplication?.processIdentifier==p
        r["afterAXForeground"]=afterAX
        let afterAXSelection=try selected()
        r["afterAXSelectedOriginal"]=afterAXSelection
        if !afterAX && afterAXSelection {
            try authenticated()
            let target=NSAppleEventDescriptor(bundleIdentifier:v.bundle)
            let permission=AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,false)
            if permission==noErr {
                r["aeActivationIssued"]=true
                do{_=try Owned.request(proc,"misc","actv",[:]);r["aeActivationReturned"]=true}
                catch{r["aeActivationReturned"]=false}
                RunLoop.current.run(until:Date(timeIntervalSinceNow:0.4))
            }else{r["aeDisposition"]="NO_AUTHORIZATION_WITHOUT_PROMPT"}
        }else{r["aeDisposition"]=afterAX ? "ALREADY_FOREGROUND":"ORIGINAL_TAB_NOT_SELECTED"}
        try original();r["originalSelected"]=try selected();r["systemForeground"]=NSWorkspace.shared.frontmostApplication?.processIdentifier==p
        return r
    }
    @MainActor static func main(){do{FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:run(),options:.sortedKeys))}catch{FileHandle.standardError.write(Data(((error as? Identity.Refusal)?.reason ?? "RESTORE_UNAVAILABLE").utf8));exit(1)}}
}
