import AppKit
import ApplicationServices
import Carbon
import Foundation
@testable import RiftletAdapters

// This helper has no AX actions or event posting. It never asks for notification,
// window, or document titles, descriptions, values, or child control contents.
@main enum WindowEvidence {
    typealias Row = [String: Any]

    static func require(_ ok: Bool, _ message: String) throws {
        if !ok { throw Identity.Refusal(message) }
    }
    static func read(_ path: URL) throws -> Row {
        guard let row = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? Row else {
            throw Identity.Refusal("INVALID_RECEIPT")
        }
        return row
    }
    static func ax(_ object: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(object, name as CFString, &value) == .success ? value : nil
    }
    static func frame(_ object: AXUIElement) -> CGRect? {
        guard let p = ax(object,kAXPositionAttribute as String), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = ax(object,kAXSizeAttribute as String), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var start = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&start),
              AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
        return CGRect(origin:start,size:size)
    }
    static func cgFrame(_ value: Row) -> CGRect? {
        guard let bounds = value[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }
    static func coords(_ r: CGRect) -> Row {
        ["x":r.origin.x,"y":r.origin.y,"width":r.size.width,"height":r.size.height]
    }
    static func same(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        zip([lhs.minX,lhs.minY,lhs.width,lhs.height],[rhs.minX,rhs.minY,rhs.width,rhs.height]).allSatisfy { abs($0-$1)<=1.0 }
    }
    // CG bounds can include transparent or non-interactive portions of an overlay.
    // Ask the system which window would receive input at distinct interior points.
    // No input is posted. Only fetch a window attribute after the hit PID matches.
    static func accessibleHits(in rect: CGRect, original: AXUIElement, pid: pid_t,
                               protectedPIDs: Set<pid_t>, captureRects: [CGRect],
                               protectedForeground: Bool) -> Row {
        let system = AXUIElementCreateSystemWide()
        let samples = [(0.50, 0.50), (0.25, 0.30), (0.75, 0.30), (0.25, 0.70), (0.75, 0.70)]
        var unresolvedOnCapture = false
        let classifications: [String] = samples.map { x, y in
            let point = CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
            var hit: AXUIElement?, hitPID: pid_t = -1
            let code = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
            guard code == .success, let hit, AXUIElementGetPid(hit, &hitPID) == .success else {
                if captureRects.contains(where: { $0.contains(point) }) { unresolvedOnCapture = true }
                return "UNAVAILABLE"
            }
            if protectedPIDs.contains(hitPID) { return "KNOWN_PROTECTED" }
            guard hitPID == pid else { return "OTHER" }
            if CFEqual(hit, original) { return "ORIGINAL" }
            guard let window = ax(hit, kAXWindowAttribute as String), CFGetTypeID(window) == AXUIElementGetTypeID() else {
                if captureRects.contains(where: { $0.contains(point) }) { unresolvedOnCapture = true }
                return "UNAVAILABLE"
            }
            return CFEqual(window, original) ? "ORIGINAL" : "OTHER"
        }
        let hits = classifications.map { $0 == "ORIGINAL" }
        let blocked = protectedForeground || unresolvedOnCapture || classifications.contains("KNOWN_PROTECTED")
        return ["center": hits[0], "quadrants": Array(hits.dropFirst()), "classifications": classifications,
                "blockedByProtectedSurface": blocked, "unresolvedOnCaptureRectangle": unresolvedOnCapture,
                "quorum": !blocked && hits.dropFirst().filter { $0 }.count >= 3]
    }
    static func aePermission(_ app:NSRunningApplication) -> String {
        // This API is queried with askUserIfNeeded=false and sends no event.
        guard let id=app.bundleIdentifier else{return "TARGET_UNAVAILABLE"}
        let target=NSAppleEventDescriptor(bundleIdentifier:id)
        let code=AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,false)
        switch code {
        case noErr: return "ALLOWED"
        case -1743:return "DENIED"
        case -1744:return "CONSENT_REQUIRED"
        case -600:return "TARGET_NOT_RUNNING"
        default:return "UNKNOWN_OS_STATUS"
        }
    }
    static func ownWindows(_ pid: pid_t) -> [AXUIElement]? {
        ax(AXUIElementCreateApplication(pid),kAXWindowsAttribute as String) as? [AXUIElement]
    }
    static func meta(_ w: AXUIElement) -> Row {
        var row:Row=["role":ax(w,kAXRoleAttribute as String) as? String ?? "unavailable",
                     "subrole":ax(w,kAXSubroleAttribute as String) as? String ?? "unavailable",
                     "modal":ax(w,kAXModalAttribute as String) as? Bool ?? false]
        if let b=frame(w) { row["bounds"]=coords(b) }
        return row
    }
    @MainActor static func run(_ a:[String]) throws -> Row {
        try require((a.count==2 && a[1]=="environment") || (a.count==4 && a[1]=="original"),"TYPED_MODE_REQUIRED")
        let session=CGSessionCopyCurrentDictionary() as? Row ?? [:]
        let all=CGWindowListCopyWindowInfo([.optionAll,.excludeDesktopElements],kCGNullWindowID) as? [Row] ?? []
        let on=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [Row] ?? []
        let front=NSWorkspace.shared.frontmostApplication
        func owned(_ rows:[Row],_ p:pid_t)->[Row] { rows.filter{($0[kCGWindowOwnerPID as String] as? Int32)==p} }
        func regular(_ rows:[Row])->[Row] { rows.filter{($0[kCGWindowLayer as String] as? Int)==0} }
        let fro=front.map{ownWindows($0.processIdentifier) ?? []} ?? []
        let protected=["com.apple.UserNotificationCenter","com.apple.SecurityAgent","com.apple.CoreAuthUI","com.apple.loginwindow","com.apple.ScreenSaver.Engine"]
        let knownSystem = protected.flatMap{NSRunningApplication.runningApplications(withBundleIdentifier:$0)}
        let surfaces=knownSystem.compactMap{app->Row? in
            let visible=owned(on,app.processIdentifier)
            guard !visible.isEmpty else{return nil}
            let win=(ownWindows(app.processIdentifier) ?? []).map(meta)
            return ["bundle":app.bundleIdentifier ?? "","pid":app.processIdentifier,"ax":win,"cg":visible.map{
                row in ["layer":row[kCGWindowLayer as String] ?? -1,"bounds":cgFrame(row).map(coords) ?? [:]] as Row
            }]
        }
        // Loginwindow occasionally owns the background desktop. Only a displayed
        // system dialog, modal, or a protected foreground counts as an input blocker.
        let protectedFront=front?.bundleIdentifier.map{protected.contains($0) || $0.lowercased()=="com.apple.screencaptureui"} ?? true
        let dialog=surfaces.contains{row in
            (row["ax"] as? [Row] ?? []).contains{($0["modal"] as? Bool)==true || $0["subrole"] as? String=="AXSystemDialog"}
        }
        let console=session[kCGSessionOnConsoleKey as String] as? Bool
        let login=session[kCGSessionLoginDoneKey as String] as? Bool
        let awake=CGDisplayIsAsleep(CGMainDisplayID())==0
        let locked=session["CGSSessionScreenIsLocked"] as? Bool ?? false
        let frontModal=fro.contains{ax($0,kAXModalAttribute as String) as? Bool==true}
        var browsers=[String:Row]()
        for (family,vendor) in Identity.families {
            let matches=NSRunningApplication.runningApplications(withBundleIdentifier:vendor.bundle).filter{
                $0.executableURL?.resolvingSymlinksInPath().path==vendor.executable
            }
            if matches.count==1 {
                let app=matches[0],wins=ownWindows(app.processIdentifier)
                browsers[family]=["queryWithoutPrompt":true,"aePermission":aePermission(app),"axWindowAttributeReadable":wins != nil,"pid":app.processIdentifier,"running":true,"regular":app.activationPolicy == .regular,"hidden":app.isHidden,"active":app.isActive,
                                  "axWindowCount":wins?.count ?? -1,"cgBaseWindowCount":regular(owned(all,app.processIdentifier)).count,"cgOnScreenCount":regular(owned(on,app.processIdentifier)).count]
            } else {browsers[family]=["running":false,"matchingProcessCount":matches.count]}
        }
        var total:Row=["frontBundle":front?.bundleIdentifier ?? "","frontPID":front?.processIdentifier ?? -1,"frontAX":fro.map(meta),"protectedSystemSurfaces":surfaces,"protectedForeground":protectedFront,"systemDialogOnScreen":dialog,"frontHasModal":frontModal,"displayAwake":awake,"screenLocked":locked,"onConsole":console as Any? ?? NSNull(),"loginDone":login as Any? ?? NSNull(),"consoleUIDMatches":(session[kCGSessionUserIDKey as String] as? Int)==Int(getuid()),"axTrusted":AXIsProcessTrusted(),"displays":NSScreen.screens.map{coords($0.frame)},"browsers":browsers]
        total["eligibleForPreparation"]=console==true && login==true && awake && !locked && !protectedFront && !dialog && !frontModal && AXIsProcessTrusted()
        if a[1]=="environment" {return total}
        let state=URL(fileURLWithPath:a[2],isDirectory:true),family=a[3]
        let before=try read(state.appendingPathComponent("before.json")),creation=try read(state.appendingPathComponent("creation.json"))
        let challenge=try read(state.appendingPathComponent("challenge.json")),nav=try read(state.appendingPathComponent("site-navigation-return.json")),entry=try read(state.appendingPathComponent("original-entry.json"))
        guard let vendor=Identity.families[family],let pid=creation["pid"] as? Int32,let wid=creation["windowID"] as? String,let tid=creation["tabID"] as? String,
              let birth=creation["sessionID"] as? String,let prior=before["windowIDs"] as? [String],let doc=challenge["doc"] as? String,
              UUID(uuidString:doc) != nil, !prior.contains(wid), before["pid"] as? Int32==pid, before["sessionID"] as? String==birth,
              before["dynamicSignature"] as? Bool==true,creation["phase"] as? String=="qaAddressConfirmed",creation["family"] as? String==family,
              challenge["windowID"] as? String==wid,challenge["tabID"] as? String==tid,challenge["sessionID"] as? String==birth,
              challenge["dynamicSignature"] as? Bool==true,nav["sourceDoc"] as? String==doc,nav["navigationRequested"] as? Bool==true,
              entry["sourceDoc"] as? String==doc else {throw Identity.Refusal("ORIGINAL_SCOPE_REQUIRED")}
        try require(browsers[family]?["aePermission"] as? String=="ALLOWED","AE_PERMISSION_NOT_ESTABLISHED_WITHOUT_PROMPT")
        let proc=try Identity.certified(vendor,expectedPID:pid)
        try require(proc.session==birth,"BROWSER_BIRTH_CHANGED")
        let w=try Identity.object("cwin","ID  ",.init(string:wid)),t=try Identity.object("CrTb","ID  ",.init(string:tid),w)
        func selected() throws -> Bool {
            let first=try Identity.object("cwin","indx",.init(int32:1))
            let s=ChromeActiveTabDescriptor.identity(in:try Identity.get(proc,Identity.property("acTa",first)))
            return s?.window==wid && s?.tab==tid
        }
        func exact()throws{
            try require(proc.isCurrent() && proc.session==birth,"BROWSER_RESTARTED")
            try require(try Owned.tabIDs(proc,window:w)==[tid] && Identity.get(proc,Identity.property("URL ",t)).stringValue==QAOriginalBrowserTab.temporaryChat,"ORIGINAL_SOLE_TEMPORARY_TAB_REQUIRED")
        }
        try exact();let firstSelected=try selected(),firstForeground=front?.processIdentifier==pid
        let nativeVisible=try Identity.get(proc,Identity.property("pvis",w)).booleanValue
        let isMini=try Identity.get(proc,Identity.property("pmnd",w)).booleanValue
        let bounds=try Identity.get(proc,Identity.property("pbnd",w))
        let bytes=bounds.data
        guard bounds.descriptorType==typeQDRectangle,bytes.count==8 else{throw Identity.Refusal("NATIVE_WINDOW_BOUNDS_REQUIRED")}
        let edges=bytes.withUnsafeBytes{raw in (0..<4).map{Int(raw.loadUnaligned(fromByteOffset:$0*2,as:Int16.self))}}
        let nframe=CGRect(x:edges[1],y:edges[0],width:edges[3]-edges[1],height:edges[2]-edges[0])
        try require(nframe.width>10 && nframe.height>10,"INVALID_NATIVE_WINDOW_FRAME")
        let nativeCG=regular(owned(on,pid)).filter{row in cgFrame(row).map{same($0,nframe)}==true}
        let candidates=(ownWindows(pid) ?? []).filter{object in
            ax(object,kAXRoleAttribute as String) as? String=="AXWindow" && ax(object,kAXSubroleAttribute as String) as? String=="AXStandardWindow" && frame(object).map{same($0,nframe)}==true
        }
        let originalAX=candidates.count==1 && ax(candidates[0],kAXMainAttribute as String) as? Bool==true
        let cgID=nativeCG.count==1 ? nativeCG[0][kCGWindowNumber as String] as? Int:nil
        let cgOpaque = nativeCG.count == 1 && (nativeCG[0][kCGWindowAlpha as String] as? Double ?? 0) > 0
        var pointEvidence: Row = ["center": false, "quadrants": [false, false, false, false],
                                  "blockedByProtectedSurface": true, "quorum": false]
        if originalAX && cgOpaque && firstForeground && firstSelected && nativeVisible && !isMini {
            let captureApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier?.lowercased() == "com.apple.screencaptureui" }
            let capturePIDs = Set(captureApps.map(\.processIdentifier))
            let captureRects = on.filter { capturePIDs.contains($0[kCGWindowOwnerPID as String] as? Int32 ?? -1) &&
                                           ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }.compactMap(cgFrame)
            let protectedPIDs = capturePIDs.union(knownSystem.map(\.processIdentifier))
            pointEvidence = accessibleHits(in: nframe, original: candidates[0], pid: pid, protectedPIDs: protectedPIDs,
                                          captureRects: captureRects, protectedForeground: protectedFront)
        }
        let center=CGPoint(x:nframe.midX,y:nframe.midY)
        let hit=on.first{r in (r[kCGWindowAlpha as String] as? Double ?? 1)>0 && cgFrame(r)?.contains(center)==true}
        let sameHit=cgID != nil && hit?[kCGWindowNumber as String] as? Int==cgID
        try exact()
        let finalSelected=try selected(); let stable=firstSelected && finalSelected
        let actualForeground=firstForeground && NSWorkspace.shared.frontmostApplication?.processIdentifier==pid
        total["original"]=["pid":pid,"birth":birth,"nativeWindowID":wid,"nativeTabID":tid,"knownOriginalProcess":true,"selected":stable,"nativeVisible":nativeVisible && !isMini,"systemForeground":actualForeground,"singleTab":true,"nativeBounds":coords(nframe),"matchingAXStandard":candidates.count,"uniqueMainAX":originalAX,"matchingCGOnScreen":nativeCG.count,"cgWindowNumber":cgID as Any? ?? NSNull(),"centerHitOriginalCG":sameHit,"originalAXHits":pointEvidence,"originalAXHitQuorum":pointEvidence["quorum"] as? Bool == true,"cgWindowOnScreen":cgID != nil && cgOpaque,"axOriginalWindow":originalAX]
        return total
    }
    @MainActor static func main(){do{
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:run(CommandLine.arguments),options:.sortedKeys))
    }catch{
        FileHandle.standardError.write(Data(((error as? Identity.Refusal)?.reason ?? "NATIVE_METADATA_UNAVAILABLE").utf8));exit(1)
    }}
}
