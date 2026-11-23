import AppKit
import ApplicationServices
import Carbon
import CryptoKit
import Foundation
@testable import RiftletAdapters

// QA diagnostics only. All browser Apple Events reachable from this executable
// are get-data calls against the enrolled process and window.
@main enum WindowInspector {
    typealias Row = [String: Any]
    static let none = NSNull()
    static func value<T>(_ v: T?) -> Any { v.map { $0 as Any } ?? none }
    static func utc() -> String { ISO8601DateFormatter().string(from: Date()) }
    static func need(_ ok: Bool, _ reason: String) throws { if !ok { throw Identity.Refusal(reason) } }
    static func read(_ f: URL) throws -> Row {
        guard let row = try JSONSerialization.jsonObject(with: Data(contentsOf: f)) as? Row else {
            throw Identity.Refusal("INVALID_SCOPE_RECORD")
        }
        return row
    }
    static func box(_ r: CGRect) -> Row { ["x":r.origin.x, "y":r.origin.y, "width":r.width, "height":r.height] }
    static func usable(_ r: CGRect) -> Bool { [r.origin.x,r.origin.y,r.width,r.height].allSatisfy(\.isFinite) && r.width > 0 && r.height > 0 }
    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        usable(a) && usable(b) && zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy { abs($0-$1) <= 1 }
    }
    static func quartz(_ cocoa: CGRect, primaryNS: CGRect, primaryCG: CGRect) -> CGRect {
        CGRect(x:primaryCG.minX + cocoa.minX - primaryNS.minX,
               y:primaryCG.minY + primaryNS.maxY - cocoa.maxY, width:cocoa.width, height:cocoa.height)
    }
    static func rect(_ row: Row) -> CGRect? {
        guard let raw = row[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: raw), usable(r) else { return nil }
        return r
    }
    static func qd(_ data: Data) -> CGRect? {
        guard data.count == 8 else { return nil }
        let v = data.withUnsafeBytes { b in (0..<4).map { Int(b.loadUnaligned(fromByteOffset:$0*2,as:Int16.self)) } }
        let r = CGRect(x:v[1],y:v[0],width:v[3]-v[1],height:v[2]-v[0])
        return usable(r) ? r : nil
    }
    static func number(_ r: Row) -> Int? { (r[kCGWindowNumber as String] as? NSNumber)?.intValue }
    static func owner(_ r: Row) -> pid_t? { (r[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value }
    static func layer(_ r: Row) -> Int? { (r[kCGWindowLayer as String] as? NSNumber)?.intValue }
    static func opacity(_ r: Row) -> Double? { (r[kCGWindowAlpha as String] as? NSNumber)?.doubleValue }
    static func cgRow(_ raw: Row, enrolled: CGRect?, onIDs: Set<Int>?) -> Row {
        let r = rect(raw), n = number(raw), flag = raw[kCGWindowIsOnscreen as String] as? Bool
        var out: Row = ["cgWindowNumber":value(n), "layer":value(layer(raw)), "quartzBounds":value(r.map(box)),
                        "alpha":value(opacity(raw)), "isOnscreenKey":value(flag),
                        "orderedOnScreenInThisAllList":flag ?? false,
                        "inSeparateOnScreenList":value(n.flatMap { id in onIDs.map{$0.contains(id)} })]
        if let r, let e = enrolled {
            out["deltaFromEnrolledBounds"] = ["x":r.minX-e.minX, "y":r.minY-e.minY, "width":r.width-e.width, "height":r.height-e.height]
            out["withinOnePointOfEnrolled"] = same(e,r)
        }
        return out
    }
    // A rectangle hit is the same conservative heuristic as the existing gate.
    // It does not reveal pixel transparency, true event hit-testing, or a Space.
    static func centerEvidence(_ on: [Row]?, pid: pid_t, r: CGRect) -> Row {
        guard let on else { return ["status":"WINDOWSERVER_LIST_UNAVAILABLE"] }
        let candidates = on.filter { owner($0)==pid && layer($0)==0 && rect($0).map { same($0,r) }==true }
        let ownIDs = candidates.compactMap(number)
        var result: Row = ["matchingEnrolledPIDLayerZeroCount":candidates.count, "matchingCGNumbers":ownIDs,
                           "centerHitOriginalCG":none, "status":"NO_COMPARABLE_CENTER_HIT"]
        let center=CGPoint(x:r.midX,y:r.midY)
        for row in on {
            if opacity(row)==0 { continue }
            guard let frame=rect(row) else { result["status"]="EARLIER_WINDOW_GEOMETRY_UNKNOWN"; return result }
            guard frame.contains(center) else { continue }
            guard let alpha=opacity(row), alpha>0, let n=number(row), let who=owner(row) else {
                result["status"]="CENTER_SURFACE_METADATA_UNKNOWN"; return result
            }
            result["topRectangleOwner"] = who==pid ? "ENROLLED_BROWSER_PROCESS" : "OTHER_PROCESS"
            result["topRectangleLayer"] = value(layer(row))
            if who==pid { result["topOwnedCGNumber"]=n }
            if candidates.count==1, ownIDs.count==1 {
                result["centerHitOriginalCG"] = n==ownIDs[0] && who==pid
                result["status"] = n==ownIDs[0] && who==pid ? "MATCHING_CG_RECTANGLE_FIRST" : "OTHER_RECTANGLE_FIRST"
            } else {
                result["status"] = candidates.isEmpty ? "NO_MATCHING_ONSCREEN_GEOMETRY" : "AMBIGUOUS_ONSCREEN_GEOMETRY"
            }
            return result
        }
        result["status"] = candidates.isEmpty ? "NO_MATCHING_ONSCREEN_GEOMETRY" : "NO_POSITIVE_ALPHA_RECTANGLE_AT_CENTER"
        return result
    }
    static func ax(_ e: AXUIElement, _ key: String) -> (AXError,CFTypeRef?) {
        var v: CFTypeRef?
        let err=AXUIElementCopyAttributeValue(e,key as CFString,&v)
        return (err,err == .success ? v : nil)
    }
    static func axWord(_ v: CFTypeRef?, _ allowed: Set<String>) -> Any {
        guard let s=v as? String else {return none}
        return allowed.contains(s) ? s : "OTHER"
    }
    static func axGeometry(_ p: CFTypeRef?, _ s: CFTypeRef?) -> CGRect? {
        guard let p,let s,CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
        var pos=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&pos), AXValueGetValue(s as! AXValue,.cgSize,&size) else{return nil}
        let r=CGRect(origin:pos,size:size);return usable(r) ? r : nil
    }
    static func axRow(_ w: AXUIElement, pid: pid_t, rawCG: [Row]?, native: CGRect?, key: SymmetricKey) -> Row {
        var confirmedPID:pid_t=0
        guard AXUIElementGetPid(w,&confirmedPID) == .success && confirmedPID==pid else {return ["status":"AX_OWNER_UNVERIFIED"]}
        let allowed=["role":kAXRoleAttribute,"subrole":kAXSubroleAttribute,"identifier":kAXIdentifierAttribute,
                     "position":kAXPositionAttribute,"size":kAXSizeAttribute,"minimized":kAXMinimizedAttribute,
                     "main":kAXMainAttribute,"focused":kAXFocusedAttribute,"modal":kAXModalAttribute] as [String:String]
        let vals=allowed.mapValues{ax(w,$0)}
        let frame=axGeometry(vals["position"]?.1,vals["size"]?.1)
        var result:Row=["status":"OWNED_AX_WINDOW","readStatus":vals.mapValues{$0.0.rawValue},
                        "role":axWord(vals["role"]?.1,["AXWindow","AXSheet","AXDialog"]),
                        "subrole":axWord(vals["subrole"]?.1,["AXStandardWindow","AXFloatingWindow","AXDialog","AXSystemDialog","AXUnknown","AXSheet"]),
                        "quartzBounds":value(frame.map(box)),"directCGWindowNumber":none,
                        "directCGWindowNumberStatus":"NO_DOCUMENTED_AX_WINDOW_NUMBER_ATTRIBUTE"]
        for k in ["minimized","main","focused","modal"] { result[k]=value(vals[k]?.1 as? Bool) }
        if let identifier=vals["identifier"]?.1 as? String, !identifier.isEmpty {
            let token=HMAC<SHA256>.authenticationCode(for:Data(identifier.utf8),using:key)
            result["identifierTokenWithinObservation"]=token.map{String(format:"%02x",$0)}.joined()
        } else {result["identifierTokenWithinObservation"]=none}
        if let frame, let cg=rawCG {
            result["sameBoundsLayerZeroCGNumbers"]=cg.filter{owner($0)==pid && layer($0)==0 && rect($0).map{same($0,frame)}==true}.compactMap(number)
        }
        if let frame,let native { result["withinOnePointOfEnrolled"]=same(frame,native) }
        return result
    }
    @MainActor static func displayEvidence(native: CGRect?) -> Row {
        let screens=NSScreen.screens, primary=CGMainDisplayID()
        func id(_ s:NSScreen)->CGDirectDisplayID? { (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        guard let ref=screens.first(where:{id($0)==primary}) else {return ["status":"PRIMARY_COCOA_REFERENCE_UNAVAILABLE"]}
        let origin=CGDisplayBounds(primary)
        let rows:[Row]=screens.map{screen in
            let cid=id(screen), ns=screen.frame, vis=screen.visibleFrame
            let q=quartz(ns,primaryNS:ref.frame,primaryCG:origin), qv=quartz(vis,primaryNS:ref.frame,primaryCG:origin)
            let display=cid.map(CGDisplayBounds)
            let consistent=display.map{same(q,$0)}
            var r:Row=["displayID":value(cid), "cocoaFrame":box(ns),"cocoaVisibleFrame":box(vis),"quartzFrameFromCocoa":box(q),
                       "quartzVisibleFrameFromCocoa":box(qv),"actualQuartzDisplayBounds":value(display.map(box)),
                       "mappingAgreesWithinOnePoint":value(consistent),"backingScale":screen.backingScaleFactor]
            if let n=native,let d=display {
                let hit=n.intersection(d)
                r["enrolledIntersectsDisplay"]=usable(hit) && !hit.isNull
                r["enrolledCenterInDisplay"]=d.contains(CGPoint(x:n.midX,y:n.midY))
                if consistent==true {
                    let vhit=n.intersection(qv)
                    r["enrolledIntersectsVisibleFrame"]=usable(vhit) && !vhit.isNull
                    r["enrolledCenterInVisibleFrame"]=qv.contains(CGPoint(x:n.midX,y:n.midY))
                }
            }
            return r
        }
        return ["status":"PER_DISPLAY_MAPPING_REPORTED","mainDisplayID":primary,"screens":rows]
    }
    struct Scope {
        let family:String, state:URL, vendor:Identity.Family, pid:pid_t, birth:String, window:String, tab:String
        init(_ path:String, _ family:String) throws {
            let s=URL(fileURLWithPath:path,isDirectory:true).standardizedFileURL.resolvingSymlinksInPath()
            guard s.lastPathComponent==family,s.deletingLastPathComponent().lastPathComponent=="signed61",
                  let v=Identity.families[family], !FileManager.default.fileExists(atPath:s.appendingPathComponent("closed.json").path)
            else {throw Identity.Refusal("OPEN_ENROLLED_BUILD61_SCOPE_REQUIRED")}
            let base=s.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let manifest=try read(base.appendingPathComponent("candidate.json"))
            try need(manifest["expectedBuild"] as? Int==61 &&
                manifest["source"] as? String=="49b9204974088c1983cda469910d9a78d8f4c43b" &&
                manifest["dmgSHA256"] as? String=="31df54cdc036dd67da3369eef9b9a4d130db67540fe5973920834b6c6a65d92e","ENROLLED_CANDIDATE_MISMATCH")
            let b=try read(s.appendingPathComponent("before.json")),c=try read(s.appendingPathComponent("creation.json"))
            let x=try read(s.appendingPathComponent("challenge.json")),n=try read(s.appendingPathComponent("site-navigation-return.json"))
            let e=try read(s.appendingPathComponent("original-entry.json"))
            guard let p=c["pid"] as? Int32, p>0, let birth=c["sessionID"] as? String,
                  let w=c["windowID"] as? String, let t=c["tabID"] as? String,
                  let wn=Int64(w), wn>0, String(wn)==w, let tn=Int64(t), tn>0, String(tn)==t,
                  let previous=b["windowIDs"] as? [String],!previous.contains(w),
                  c["family"] as? String==family,c["phase"] as? String=="qaAddressConfirmed",
                  b["pid"] as? Int32==p,b["family"] as? String==family,b["sessionID"] as? String==birth,b["dynamicSignature"] as? Bool==true,
                  x["pid"] as? Int32==p,x["family"] as? String==family,x["sessionID"] as? String==birth,
                  x["dynamicSignature"] as? Bool==true,x["windowID"] as? String==w,x["tabID"] as? String==t,
                  let d=x["doc"] as? String, UUID(uuidString:d) != nil,e["sourceDoc"] as? String==d,
                  n["sourceDoc"] as? String==d,n["navigationRequested"] as? Bool==true else {throw Identity.Refusal("INCONSISTENT_ORIGINAL_SCOPE")}
            self.family=family;self.state=s;self.vendor=v;self.pid=p;self.birth=birth;self.window=w;self.tab=t
        }
    }
    static func browserBounds(_ proc:ChromeProcessIdentity, window:NSAppleEventDescriptor) throws -> CGRect {
        let d=try Identity.get(proc,Identity.property("pbnd",window))
        guard d.descriptorType==typeQDRectangle,let r=qd(d.data) else{throw Identity.Refusal("QD_BOUNDS_UNAVAILABLE")}
        return r
    }
    static func boolProperty(_ proc:ChromeProcessIdentity,_ prop:String,_ w:NSAppleEventDescriptor) throws -> Bool {
        let result=try Identity.get(proc,Identity.property(prop,w))
        guard [typeBoolean,typeTrue,typeFalse].contains(result.descriptorType) else{throw Identity.Refusal("NON_BOOLEAN_BROWSER_REPLY")}
        return result.booleanValue
    }
    static func policy(_ p:NSApplication.ActivationPolicy)->String {
        switch p {case .regular:return "regular";case .accessory:return "accessory";case .prohibited:return "prohibited";@unknown default:return "unknown"}
    }
    static func identityActiveInOriginal(_ p:ChromeProcessIdentity,_ w:NSAppleEventDescriptor,_ sc:Scope)throws->Bool {
        let reply=try Identity.get(p,Identity.property("acTa",w))
        let tab=ChromeActiveTabDescriptor.identity(in:reply)
        return tab?.window==sc.window && tab?.tab==sc.tab
    }
    static func actions(_ sc:Scope) -> Row {
        let signed=sc.state.deletingLastPathComponent(), root=signed.deletingLastPathComponent(), base=root.deletingLastPathComponent()
        func matchesRoot(_ v:Any?) -> Bool {
            guard let path=v as? String, path.hasPrefix("/") else{return false}
            return URL(fileURLWithPath:path,isDirectory:true).standardizedFileURL.resolvingSymlinksInPath().path ==
                   root.standardizedFileURL.resolvingSymlinksInPath().path
        }
        guard let active=try? read(base.appendingPathComponent("active-scope.json")),
              active["family"] as? String==sc.family, matchesRoot(active["root"]),
              let expectedCase=active["case"] as? String,
              ["chrome","edge"].filter({FileManager.default.fileExists(atPath:signed.appendingPathComponent($0+"/creation.json").path)})==[sc.family],
              let files=try? FileManager.default.contentsOfDirectory(at:base,includingPropertiesForKeys:[.contentModificationDateKey]) else {
            return ["status":"CANNOT_ATTRIBUTE_HISTORICAL_ACTIONS_TO_ONE_ENROLLED_SCOPE"]
        }
        let bools=["alreadyReady","beforeSelected","beforeForeground","selectionRequestIssued","ownedWindowRestored","appActivationIssued",
                   "appActivationReturned","afterNSForeground","axRaiseIssued","afterAXForeground","afterAXSelectedOriginal",
                   "aeActivationIssued","aeActivationReturned","originalSelected","systemForeground","placementIssued",
                   "restoreMinimizedIssued","originalTabSelectionIssued"]
        let dispositions:Set<String>=["ACCESSIBILITY_NOT_TRUSTED","AX_WINDOWS_UNAVAILABLE","NO_AX_WINDOWS","NATIVE_BOUNDS_UNAVAILABLE",
             "AX_FRAME_MISSING","AX_FRAME_AMBIGUOUS","NATIVE_PEER_GEOMETRY_UNAVAILABLE","NATIVE_FRAME_AMBIGUOUS","NO_MATCHING_ONSCREEN_CG_WINDOW",
             "CG_FRAME_AMBIGUOUS","EXACT_NATIVE_AX_CG_FRAME","ALREADY_FOREGROUND","NO_AUTHORIZATION_WITHOUT_PROMPT","ORIGINAL_TAB_NOT_SELECTED"]
        var rows=[Row]()
        for f in files where f.lastPathComponent.range(of:"^presentation-intent-[0-9a-f]{32}\\.json$",options:.regularExpression) != nil {
            guard let i=try? read(f),matchesRoot(i["source"]),i["case"] as? String==expectedCase else{continue}
            let name=f.lastPathComponent.replacingOccurrences(of:"presentation-intent-",with:"presentation-")
            let stamp=(try? f.resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate
            var row:Row=["intentFileModifiedUTC":value(stamp.map{ISO8601DateFormatter().string(from:$0)})]
            if let result=try? read(base.appendingPathComponent(name)) {
                row["resultAvailable"]=true
                for k in bools {if let v=result[k] as? Bool {row[k]=v}}
                if let code=result["axRaiseReturnCode"] as? Int {row["axRaiseReturnCode"]=code}
                if let code=result["permissionOSStatus"] as? Int {row["aePermissionOSStatus"]=code}
                if let code=result["aeActivationOSStatus"] as? Int {row["previousHelperAEStatusField"]=code}
                if let options=result["activationOptions"] as? String {
                    row["activationOptions"]=["ordinary","alreadyForegroundWithPeerWindows","ignoreOtherApps+allWindows"].contains(options) ? options : "OTHER"
                }
                for k in ["axDisposition","aeDisposition"] {if let v=result[k] as? String {row[k]=dispositions.contains(v) ? v : "OTHER"}}
            } else {row["resultAvailable"]=false}
            rows.append(row)
        }
        return ["status":"EXACT_INTENT_ROOT_CASE_AND_SINGLE_ENROLLED_FAMILY","rows":rows.sorted{($0["intentFileModifiedUTC"] as? String ?? "")<($1["intentFileModifiedUTC"] as? String ?? "")},
                "appleEventActivationRawErrorRecordedByPreviousHelper":false]
    }
    @MainActor static func diagnose(_ sc:Scope) throws -> Row {
        let start=utc(), process=try Identity.certified(sc.vendor,expectedPID:sc.pid)
        try need(process.session==sc.birth,"ENROLLED_PROCESS_BIRTH_CHANGED")
        guard let app=NSRunningApplication(processIdentifier:sc.pid) else{throw Identity.Refusal("BROWSER_EXITED")}
        let permission=AEDeterminePermissionToAutomateTarget(NSAppleEventDescriptor(processIdentifier:sc.pid).aeDesc,typeWildCard,typeWildCard,false)
        let w=try Identity.object("cwin","ID  ",.init(string:sc.window))
        let native: CGRect?; var nativeRow:Row=["appleEventPermissionWithoutPromptOSStatus":permission,
            "browserScriptableWindowID":sc.window,"browserScriptableTabID":sc.tab,"directCGWindowNumber":none]
        if permission==noErr {
            let sole=(try? Owned.tabIDs(process,window:w)).map{$0==[sc.tab]}
            nativeRow["originalSoleTabIDsMatch"]=value(sole)
            if sole==true {
                nativeRow["originalTabSelectedInEnrolledWindow"]=value(try? identityActiveInOriginal(process,w,sc))
                native=try? browserBounds(process,window:w)
                nativeRow["visible"]=value(try? boolProperty(process,"pvis",w));nativeRow["minimized"]=value(try? boolProperty(process,"pmnd",w))
            } else {native=nil}
        } else {native=nil}
        nativeRow["topLeftBounds"]=value(native.map(box))
        let cgAll=CGWindowListCopyWindowInfo([.optionAll,.excludeDesktopElements],kCGNullWindowID) as? [Row]
        let cgOn=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [Row]
        let owned=cgAll.map{$0.filter{owner($0)==sc.pid}}, on=cgOn.map{$0.filter{owner($0)==sc.pid}}
        let onIDs=on.map{Set($0.compactMap(number))}
        let axTrusted=AXIsProcessTrusted()
        let a=AXUIElementCreateApplication(sc.pid)
        let list=axTrusted ? ax(a,kAXWindowsAttribute as String) : (.apiDisabled,nil)
        let elements=list.1 as? [AXUIElement], salt=SymmetricKey(size:.bits256)
        let cgReport:Row=["allListReadable":cgAll != nil,"onScreenListReadable":cgOn != nil,
             "allOwned":value(owned.map{$0.map{cgRow($0,enrolled:native,onIDs:onIDs)}}),
             "onScreenOwned":value(on.map{$0.map{cgRow($0,enrolled:native,onIDs:onIDs)}}),
             "centerRectangleEvidence":value(native.map{centerEvidence(cgOn,pid:sc.pid,r:$0)})]
        let axRows=elements.map{$0.map{axRow($0,pid:sc.pid,rawCG:owned,native:native,key:salt)}}
        let session=CGSessionCopyCurrentDictionary() as? Row
        var targetBSD=proc_bsdinfo()
        let n=proc_pidinfo(sc.pid,PROC_PIDTBSDINFO,0,&targetBSD,Int32(MemoryLayout<proc_bsdinfo>.size))
        let targetUID=n==MemoryLayout<proc_bsdinfo>.size && targetBSD.pbi_pid==UInt32(sc.pid) ? targetBSD.pbi_uid : nil
        let callerUID=getuid(), consoleUID=(session?[kCGSessionUserIDKey as String] as? NSNumber)?.uint32Value
        var callerAuditUser:UInt32=0, callerSession:UInt32=0, browserAuditUser:UInt32=0, browserSession:UInt32=0
        let callerErr=RiftletReadAuditSession(getpid(),&callerAuditUser,&callerSession)
        let browserErr=RiftletReadAuditSession(sc.pid,&browserAuditUser,&browserSession)
        let sameAudit:Bool? = callerErr==0 && browserErr==0 ? (callerSession==browserSession && callerAuditUser==browserAuditUser) : nil
        let visibleFront=NSWorkspace.shared.frontmostApplication
        let knownProtected=["com.apple.UserNotificationCenter","com.apple.SecurityAgent","com.apple.CoreAuthUI","com.apple.loginwindow","com.apple.ScreenSaver.Engine"]
        let display=displayEvidence(native:native)
        let stableBounds:Bool?
        if let native {
            let after=try? browserBounds(process,window:w)
            stableBounds=after.map{$0==native}
        } else {stableBounds=nil}
        let finalTab:Bool?
        if native != nil {
            let finalIDs=try? Owned.tabIDs(process,window:w)
            finalTab=finalIDs.map{$0==[sc.tab]}
        } else {finalTab=nil}
        try need(process.isCurrent() && process.session==sc.birth,"PROCESS_BIRTH_CHANGED_DURING_READ")
        return ["schemaVersion":1,"mode":"diagnose","observedFromUTC":start,"observedThroughUTC":utc(),"grantsInput":false,
            "process":["family":sc.family,"bundleID":sc.vendor.bundle,"signedTeamID":sc.vendor.team,"pid":sc.pid,
                       "kernelBirthID":sc.birth,"verifiedLiveSignatureAndBirth":true,"active":app.isActive,
                       "hidden":app.isHidden,"activationPolicy":policy(app.activationPolicy)],
            "session":["onConsole":value(session?[kCGSessionOnConsoleKey as String] as? Bool),
                       "loginDone":value(session?[kCGSessionLoginDoneKey as String] as? Bool),
                       "displayAwake":CGDisplayIsAsleep(CGMainDisplayID())==0,"callerUIDMatchesConsole":value(consoleUID.map{$0==callerUID}),
                       "browserUIDMatchesCaller":value(targetUID.map{$0==callerUID}),
                       "browserUIDMatchesConsole":value(targetUID.flatMap{uid in consoleUID.map{$0==uid}}),
                       "callerAuditQueryErrno":callerErr,"browserAuditQueryErrno":browserErr,"exactBrowserAuditSessionMatch":value(sameAudit),
                       "frontAtEndIsBrowser":value(visibleFront.map{$0.processIdentifier==sc.pid}),
                       "frontAtEndIsKnownProtected":value(visibleFront?.bundleIdentifier.map{knownProtected.contains($0)})],
            "enrolledBrowser":nativeRow,"geometryStableAcrossReads":value(stableBounds),"originalSoleTabIDsMatchAtEnd":value(finalTab),
            "accessibility":["trusted":axTrusted,"windowsAXError":list.0.rawValue,"windows":value(axRows)],
            "windowServer":cgReport,"displays":display,"recordedPresentationActions":actions(sc)]
    }
    static func controls() throws -> Row {
        let p=CGRect(x:0,y:0,width:1440,height:900), lower=CGRect(x:-800,y:-600,width:800,height:600), upper=CGRect(x:1440,y:900,width:800,height:600)
        func cg(_ pid:Int,_ n:Int,_ r:CGRect,_ l:Int=0,_ a:Double=1)->Row {
            [kCGWindowOwnerPID as String:pid,kCGWindowNumber as String:n,kCGWindowLayer as String:l,
             kCGWindowAlpha as String:a,kCGWindowBounds as String:r.dictionaryRepresentation]
        }
        let n=CGRect(x:25,y:46,width:900,height:608), own=cg(21,701,n), other=cg(54,35,n,25), peer=cg(21,702,n)
        let assertions:[(String,Bool)]=[
          ("primary top edge",quartz(CGRect(x:0,y:875,width:100,height:25),primaryNS:p,primaryCG:p).minY==0),
          ("display below and left",quartz(lower,primaryNS:p,primaryCG:p)==CGRect(x:-800,y:900,width:800,height:600)),
          ("display above and right",quartz(upper,primaryNS:p,primaryCG:p)==CGRect(x:1440,y:-600,width:800,height:600)),
          ("retina coordinates stay in points",quartz(p,primaryNS:p,primaryCG:p)==p),
          ("own surface first",centerEvidence([own,other],pid:21,r:n)["centerHitOriginalCG"] as? Bool==true),
          ("overlap is distinct from missing surface",centerEvidence([other,own],pid:21,r:n)["status"] as? String=="OTHER_RECTANGLE_FIRST"),
          ("transparent rectangle skipped",centerEvidence([cg(54,35,n,25,0),own],pid:21,r:n)["centerHitOriginalCG"] as? Bool==true),
          ("identical peer remains ambiguous",centerEvidence([own,peer],pid:21,r:n)["status"] as? String=="AMBIGUOUS_ONSCREEN_GEOMETRY"),
          ("missing match stays distinct",centerEvidence([other],pid:21,r:n)["status"] as? String=="NO_MATCHING_ONSCREEN_GEOMETRY"),
          ("read failure remains unknown",centerEvidence(nil,pid:21,r:n)["status"] as? String=="WINDOWSERVER_LIST_UNAVAILABLE"),
          ("unknown alpha held",centerEvidence([other.filter{$0.key != kCGWindowAlpha as String},own],pid:21,r:n)["status"] as? String=="CENTER_SURFACE_METADATA_UNKNOWN"),
          ("one-point tolerance only",same(n,n.offsetBy(dx:1,dy:-1)) && !same(n,n.offsetBy(dx:2,dy:0))),
          ("malformed QuickDraw descriptor",qd(Data(repeating:0,count:7))==nil),
          ("invalid rectangle rejected",!usable(.zero))]
        for (name,ok) in assertions {try need(ok,"CONTROL_FAILED: "+name)}
        return ["controls":assertions.map{$0.0},"passed":assertions.count,"realGUIOperations":0]
    }
    @MainActor static func main() {
        do {
            let a=Array(CommandLine.arguments.dropFirst()), output:Row
            if a==["controls"] {output=try controls()}
            else if a.count==3 && a[0]=="diagnose" {output=try diagnose(Scope(a[1],a[2]))}
            else if a.count==3 && a[0]=="receipt-only" {output=actions(try Scope(a[1],a[2]))}
            else{throw Identity.Refusal("USAGE: window-inspector diagnose ORIGINAL_SIGNED61_STATE chrome|edge OR controls")}
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]))
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            let reason=(error as? Identity.Refusal)?.reason ?? "UNAVAILABLE_SCOPE_OR_OS_METADATA"
            FileHandle.standardError.write(Data((reason+"\n").utf8));exit(1)
        }
    }
}
