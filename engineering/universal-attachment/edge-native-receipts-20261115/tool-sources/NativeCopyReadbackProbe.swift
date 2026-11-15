import AppKit
import ApplicationServices
import CryptoKit
import Darwin
import Foundation

// Standalone neutral transport diagnostic. Never opens a browser, reads a
// product database, chooses a screenshot, or changes permission/settings.
let allowedRoot = "<USER_HOME>/Documents/GitHub/Riftlet/build/pr69-mouse-delivery-review"
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
func sha(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
func birth(_ pid: pid_t) -> String? {
    var record = proc_bsdinfo()
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &record, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
          record.pbi_pid == UInt32(pid), record.pbi_start_tvsec > 0 else { return nil }
    return "\(record.pbi_start_tvsec):\(record.pbi_start_tvusec)"
}
enum ProbeError: Error { case stopped(String) }
func require(_ value: Bool, _ reason: String) throws { if !value { throw ProbeError.stopped(reason) } }
func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]) + Data([10]) }
func writeNew(_ object: Any, to url: URL) throws {
    let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    try require(fd >= 0, "evidenceAlreadyExistsOrUnavailable")
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? file.close() }
    try file.write(contentsOf: json(object)); try require(fsync(fd) == 0, "evidenceSyncFailed")
}
func readOwned(_ url: URL) throws -> [String: Any] {
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    try require(fd >= 0, "ownedFileUnavailable")
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? file.close() }
    var statbuf = stat()
    try require(fstat(fd, &statbuf) == 0 && statbuf.st_uid == getuid()
        && statbuf.st_mode & S_IFMT == S_IFREG && statbuf.st_mode & 0o777 == 0o600
        && statbuf.st_size > 0 && statbuf.st_size < 65536, "ownedFileInvalid")
    guard let data = try file.readToEnd(), data.count == statbuf.st_size,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProbeError.stopped("ownedFileUnreadable") }
    return object
}
func ownedRun(_ url: URL) throws {
    try require(url.path == url.resolvingSymlinksInPath().path
        && url.deletingLastPathComponent().path == allowedRoot, "runPathOutsideScope")
    var st = stat()
    try require(lstat(url.path, &st) == 0 && st.st_uid == getuid()
        && st.st_mode & S_IFMT == S_IFDIR && st.st_mode & 0o777 == 0o700, "runDirectoryInvalid")
}
func ownWindow(_ pid: pid_t, _ window: Int, _ point: CGPoint) -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]],
          let row = rows.first(where: { ($0[kCGWindowNumber as String] as? Int) == window }),
          row[kCGWindowOwnerPID as String] as? pid_t == pid,
          let raw = row[kCGWindowBounds as String] as? NSDictionary,
          let frame = CGRect(dictionaryRepresentation: raw), frame.contains(point) else { return false }
    let cocoa = CGPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    return NSWindow.windowNumber(at: cocoa, belowWindowWithWindowNumber: 0) == window
}

func sender(_ configURL: URL) throws {
    let app = NSApplication.shared; _ = app.setActivationPolicy(.prohibited)
    try require(app.activationPolicy() == .prohibited, "senderActivationPolicyUnavailable")
    try ownedRun(configURL.deletingLastPathComponent())
    let c = try readOwned(configURL)
    guard let runID = c["runID"] as? String, let trialID = c["trialID"] as? Int,
          let pid = c["receiverPID"] as? pid_t, let expectedBirth = c["receiverBirth"] as? String,
          let window = c["window"] as? Int, let x = c["x"] as? Double, let y = c["y"] as? Double,
          let number = c["eventNumber"] as? Int64, let tag = c["tag"] as? Int64,
          let expectedExecutable = c["executableSHA256"] as? String,
          let wait = c["waitForReceipt"] as? Bool else { throw ProbeError.stopped("senderConfigInvalid") }
    try require((trialID == 1 && !wait) || (trialID == 2 && wait), "senderModeInvalid")
    try require(birth(pid) == expectedBirth && sha(try Data(contentsOf: URL(fileURLWithPath: executable))) == expectedExecutable,
                "receiverIdentityChanged")
    try require(CGPreflightPostEventAccess(), "postPermissionUnavailable")
    try require(CGEventSource.flagsState(.combinedSessionState).intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty
        && !CGEventSource.buttonState(.combinedSessionState, button: .left), "otherInputActive")
    let point = CGPoint(x: x, y: y)
    try require(ownWindow(pid, window, point), "originalFixtureNotFirstReceiver")
    guard let source = CGEventSource(stateID: .privateState),
          let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        throw ProbeError.stopped("eventCreationFailed")
    }
    // Compare full native validation on a separate CGEvent copy while posting
    // the untouched original. No delay, retry, or routing field is added.
    func eventFields(_ event: CGEvent) -> [String: Any] {
        ["type":event.type.rawValue,"timestamp":event.timestamp,"flags":event.flags.rawValue,
         "x":event.location.x,"y":event.location.y,
         "eventNumber":event.getIntegerValueField(.mouseEventNumber),
         "tag":event.getIntegerValueField(.eventSourceUserData),
         "sourcePID":event.getIntegerValueField(.eventSourceUnixProcessID),
         "targetPID":event.getIntegerValueField(.eventTargetUnixProcessID),
         "targetProcessSerialNumber":event.getIntegerValueField(.eventTargetProcessSerialNumber),
         "sourceStateID":event.getIntegerValueField(.eventSourceStateID),
         "windowUnderPointer":event.getIntegerValueField(.mouseEventWindowUnderMousePointer),
         "windowThatCanHandle":event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)]
    }
    var readbackSnapshots: [[String: Any]] = []
    for event in [down, up] {
        event.flags = []; event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.mouseEventNumber, value: number)
        event.setIntegerValueField(.eventSourceUserData, value: tag)
        let beforeReadback = eventFields(event)
        guard let validationEvent = event.copy(), validationEvent !== event else {
            throw ProbeError.stopped("distinctValidationCopyUnavailable")
        }
        let copyBeforeReadback = eventFields(validationEvent)
        try require(validationEvent.getIntegerValueField(.mouseEventNumber) == number && NSEvent(cgEvent: validationEvent)?.eventNumber == Int(number)
            && validationEvent.getIntegerValueField(.eventSourceUserData) == tag
            && NSEvent(cgEvent: validationEvent)?.cgEvent?.getIntegerValueField(.eventSourceUserData) == tag, "eventNativeReadbackMismatch")
        readbackSnapshots.append(["before":beforeReadback,"after":eventFields(event),
            "copyBefore":copyBeforeReadback,"copyAfter":eventFields(validationEvent),"validatedDistinctCopy":true])
    }
    let run = configURL.deletingLastPathComponent()
    let before = ProcessInfo.processInfo.systemUptime
    try writeNew(["runID":runID, "trialID":trialID, "senderPID":getpid(), "sourcePID":down.getIntegerValueField(.eventSourceUnixProcessID),
                  "tag":tag, "eventNumber":number, "beforePostUptime":before, "window":window, "x":x, "y":y,
                  "variant":"fullNativeReadbackOnSeparateCGCopy", "readbackSnapshots":readbackSnapshots],
                 to: run.appendingPathComponent("trial-\(trialID)-reserved.json"))
    try require(birth(pid) == expectedBirth && ownWindow(pid, window, point), "originalFixtureChangedBeforePost")
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    // A returned void API is not an event-delivery acknowledgment.
    var result: [String: Any] = ["status":"onePairPosted", "trialID":trialID, "senderPID":getpid(),
        "returnedPostUptime":ProcessInfo.processInfo.systemUptime, "waitForReceipt":wait, "fixtureAcknowledgment":false,
        "variant":"fullNativeReadbackOnSeparateCGCopy", "readbackSnapshots":readbackSnapshots]
    if wait {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        let ackURL = run.appendingPathComponent("trial-\(trialID)-ack.json")
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let ack = try? readOwned(ackURL), ack["runID"] as? String == runID,
               ack["trialID"] as? Int == trialID, ack["receiverPID"] as? pid_t == pid,
               ack["window"] as? Int == window, ack["senderPID"] as? pid_t == getpid(),
               ack["inputDown"] as? Int == 1, ack["inputUp"] as? Int == 1 {
                result["fixtureAcknowledgment"] = true; break
            }
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow:0.01))
        }
    }
    result["senderExitUptime"] = ProcessInfo.processInfo.systemUptime
    try FileHandle.standardOutput.write(contentsOf: json(result))
}

final class ProbeWindow: NSWindow {
    var observe: ((NSEvent, String) -> Void)?
    override func sendEvent(_ event: NSEvent) { observe?(event, "window"); super.sendEvent(event) }
}
final class ProbeView: NSView {
    var observe: ((NSEvent, String) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { observe?(event, "input") }
    override func mouseUp(with event: NSEvent) { observe?(event, "input") }
    override func draw(_ rect: NSRect) {
        NSColor(calibratedRed:0.12, green:0.18, blue:0.22, alpha:1).setFill(); bounds.fill()
        let style: [NSAttributedString.Key: Any] = [.foregroundColor:NSColor.white, .font:NSFont.systemFont(ofSize:17)]
        ("Neutral native mouse diagnostic" as NSString).draw(at:CGPoint(x:24,y:165), withAttributes:style)
        ("1. immediate exit" as NSString).draw(at:CGPoint(x:24,y:90), withAttributes:style)
        ("2. receipt wait" as NSString).draw(at:CGPoint(x:242,y:90), withAttributes:style)
        ("No browser, screenshot, or product operation" as NSString).draw(at:CGPoint(x:24,y:30),
            withAttributes:[.foregroundColor:NSColor.white,.font:NSFont.systemFont(ofSize:12)])
    }
}
final class TapContext {
    unowned let owner: ProbeController; let name: String
    init(_ owner: ProbeController, _ name: String) { self.owner=owner; self.name=name }
}
func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, user: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let user {
        let context=Unmanaged<TapContext>.fromOpaque(user).takeUnretainedValue()
        context.owner.receiveCG(event,type:type,stage:context.name)
    }
    return Unmanaged.passUnretained(event)
}
final class Trial {
    let id: Int, point: CGPoint, number: Int64, tag: Int64, wait: Bool
    var process: Process?, senderPID: pid_t = 0, started = 0.0, ended: Double?, exit: Int32?
    var rows: [[String:Any]] = [], uncorrelated: [[String:Any]] = [], inputDown = 0, inputUp = 0, acknowledged = false
    init(_ id: Int, point: CGPoint, number: Int64, tag: Int64) { self.id=id; self.point=point; self.number=number; self.tag=tag; wait=id == 2 }
}
final class ProbeController: NSObject, NSWindowDelegate {
    let run: URL, runID=UUID().uuidString, receiverPID=getpid()
    let window=ProbeWindow(contentRect:NSRect(x:0,y:0,width:440,height:220), styleMask:[.titled,.closable], backing:.buffered,defer:false)
    var contexts:[TapContext]=[], taps:[(String,CFMachPort)]=[], timer:Timer?, trials:[Trial]=[], active:Int?=nil
    var stageFacts:[[String:Any]]=[], activationDeadline=0.0, finishing=false
    var nativeMouseCounts:[String:Int]=[:]
    init(_ run: URL) { self.run=run; super.init() }
    func begin() throws {
        try ownedRun(run)
        let main=CGDisplayBounds(CGMainDisplayID())
        try require(main.origin == .zero && main.width >= 600 && main.height >= 500, "unsupportedDisplayGeometry")
        // Record the listen preflight separately: it is not a reason to request
        // new authorization if the mouse-only taps can actually be created.
        stageFacts.append(["stage":"preflight","listen":CGPreflightListenEventAccess(),
            "post":CGPreflightPostEventAccess(),"AXTrusted":AXIsProcessTrusted()])
        try require(CGPreflightPostEventAccess(), "existingPostPermissionUnavailable")
        let view=ProbeView(frame:NSRect(x:0,y:0,width:440,height:220)); window.contentView=view
        window.title="Riftlet neutral mouse delivery diagnostic"; window.delegate=self; window.isReleasedWhenClosed=false
        window.setFrameOrigin(CGPoint(x:(main.width-440)/2,y:(main.height-250)/2))
        window.observe={ [weak self] event,stage in self?.receiveNative(event,stage:stage) }
        view.observe={ [weak self] event,stage in self?.receiveNative(event,stage:stage) }
        for (name, location, placement) in [("hidHead", CGEventTapLocation.cghidEventTap,CGEventTapPlacement.headInsertEventTap),
            ("hidTail",.cghidEventTap,.tailAppendEventTap),("annotatedTail",.cgAnnotatedSessionEventTap,.tailAppendEventTap)] {
            let context=TapContext(self,name);contexts.append(context)
            guard let tap=CGEvent.tapCreate(tap:location,place:placement,options:.listenOnly,
                eventsOfInterest:(1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue),
                callback:eventCallback,userInfo:Unmanaged.passUnretained(context).toOpaque()),
                let source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0) else { throw ProbeError.stopped("passiveTapUnavailable_"+name) }
            taps.append((name,tap));CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
        }
        facts("created");try require(taps.allSatisfy { CGEvent.tapIsEnabled(tap:$0.1) }, "passiveTapNotEnabled")
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        for id in [1,2] {
            let cocoa=window.convertPoint(toScreen:CGPoint(x:id == 1 ? 110 : 330,y:110))
            trials.append(Trial(id,point:CGPoint(x:cocoa.x,y:main.height-cocoa.y),number:Int64(23000+id),tag:Int64(51000000000000+id)))
        }
        activationDeadline=ProcessInfo.processInfo.systemUptime+2
        timer=Timer.scheduledTimer(withTimeInterval:0.01,repeats:true) { [weak self] _ in self?.tick() }
    }
    func facts(_ stage: String) {
        stageFacts.append(["stage":stage,"uptime":ProcessInfo.processInfo.systemUptime,
            "taps":Dictionary(uniqueKeysWithValues:taps.map {($0.0,CGEvent.tapIsEnabled(tap:$0.1))}),
            "frontmostReceiver":NSWorkspace.shared.frontmostApplication?.processIdentifier == receiverPID])
    }
    func tick() {
        guard !finishing else { return }
        let now=ProcessInfo.processInfo.systemUptime
        do {
            if active == nil {
                if ownWindow(receiverPID,window.windowNumber,trials[0].point) { try launch(0) }
                else if now >= activationDeadline { finish("STOP_originalFixtureNotFirstReceiver") }
                return
            }
            let index=active!, trial=trials[index]
            guard let process=trial.process else { finish("STOP_senderMissing");return }
            if !process.isRunning && trial.exit == nil {
                trial.exit=process.terminationStatus;trial.ended=now;facts("trial\(trial.id)_senderExited")
            }
            if trial.exit != nil && (trial.acknowledged || now-trial.started >= 2.5) {
                if trial.exit != 0 { finish("STOP_senderPreflightOrExecutionFailed");return }
                if index == 0 { try launch(1) } else { finish("OBSERVED_TWO_DISTINCT_NEUTRAL_TRIALS") }
            } else if now-trial.started > 5 { finish("STOP_senderDidNotFinish");return }
        } catch { finish("STOP_\(error)") }
    }
    func launch(_ index: Int) throws {
        let trial=trials[index]
        try require(ownWindow(receiverPID,window.windowNumber,trial.point) && birth(receiverPID) != nil,
                    "fixtureIdentityChanged")
        try require(taps.allSatisfy { CGEvent.tapIsEnabled(tap:$0.1) }, "passiveTapDisabled")
        let config:[String:Any]=["runID":runID,"trialID":trial.id,"receiverPID":receiverPID,"receiverBirth":birth(receiverPID)!,
            "window":window.windowNumber,"x":trial.point.x,"y":trial.point.y,"eventNumber":trial.number,"tag":trial.tag,
            "waitForReceipt":trial.wait,"executableSHA256":sha(try Data(contentsOf:URL(fileURLWithPath:executable)))]
        let url=run.appendingPathComponent("trial-\(trial.id)-config.json");try writeNew(config,to:url)
        let process=Process();process.executableURL=URL(fileURLWithPath:executable);process.arguments=["--sender",url.path]
        for (suffix, isError) in [("stdout",false),("stderr",true)] {
            let path=run.appendingPathComponent("trial-\(trial.id)-\(suffix).txt").path
            let fd=open(path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600);try require(fd>=0,"senderLogUnavailable")
            let file=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
            if isError { process.standardError=file } else { process.standardOutput=file }
        }
        active=index;trial.process=process;trial.started=ProcessInfo.processInfo.systemUptime
        try process.run();trial.senderPID=process.processIdentifier;facts("trial\(trial.id)_senderStarted")
    }
    func matching(_ event: CGEvent, type: CGEventType) -> Trial? {
        guard type == .leftMouseDown || type == .leftMouseUp else { return nil }
        return trials.first { trial in
            guard trial.senderPID > 0 else { return false }
            let byPID=event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(trial.senderPID)
            let byPoint=event.getIntegerValueField(.mouseEventNumber) == trial.number
                && abs(event.location.x-trial.point.x)<0.5 && abs(event.location.y-trial.point.y)<0.5
            return byPID || byPoint
        }
    }
    func receiveCG(_ event: CGEvent,type:CGEventType,stage:String) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stageFacts.append(["stage":stage,"tapDisabledType":type.rawValue,"uptime":ProcessInfo.processInfo.systemUptime]);return
        }
        guard type == .leftMouseDown || type == .leftMouseUp else{return}
        let row:[String:Any] = ["stage":stage,"type":type.rawValue,"tag":event.getIntegerValueField(.eventSourceUserData),
            "eventNumber":event.getIntegerValueField(.mouseEventNumber),"sourcePID":event.getIntegerValueField(.eventSourceUnixProcessID),
            "targetPID":event.getIntegerValueField(.eventTargetUnixProcessID),"x":event.location.x,"y":event.location.y,
            "uptime":ProcessInfo.processInfo.systemUptime,"eventTimestamp":event.timestamp]
        if let trial=matching(event,type:type), trial.rows.count<32 { trial.rows.append(row);return }
        // This catches rewritten identity fields without granting an ACK. The
        // observed point must still belong to this neutral fixture's actual
        // first window; no unrelated mouse or keyboard event is retained.
        guard let index=active, ownWindow(receiverPID,window.windowNumber,event.location) else{return}
        let pointTrial=trials.first { $0.senderPID > 0 && abs(event.location.x-$0.point.x)<0.5 && abs(event.location.y-$0.point.y)<0.5 }
        guard pointTrial != nil || event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(receiverPID) else{return}
        let trial=pointTrial ?? trials[index]
        if trial.uncorrelated.count<16 { var candidate=row;candidate["identityCorrelation"]=false;trial.uncorrelated.append(candidate) }
    }
    func receiveNative(_ event:NSEvent,stage:String) {
        guard event.type == .leftMouseDown || event.type == .leftMouseUp, event.windowNumber == window.windowNumber,
              let index=active else{return}
        let countKey=stage + (event.type == .leftMouseDown ? "Down" : "Up")
        nativeMouseCounts[countKey]=min(64,(nativeMouseCounts[countKey] ?? 0)+1)
        guard let cg=event.cgEvent,let trial=matching(cg,type:cg.type),trial.rows.count<32 else {
            let trial=trials[index]
            if trial.uncorrelated.count<16 {
                trial.uncorrelated.append(["stage":stage,"type":event.type == .leftMouseDown ? 1 : 2,
                    "tag":event.cgEvent?.getIntegerValueField(.eventSourceUserData) as Any? ?? NSNull(),
                    "sourcePID":event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) as Any? ?? NSNull(),
                    "eventNumber":event.eventNumber,"window":event.windowNumber,"identityCorrelation":false,
                    "windowLocalX":event.locationInWindow.x,"windowLocalY":event.locationInWindow.y,
                    "uptime":ProcessInfo.processInfo.systemUptime])
            }
            return
        }
        trial.rows.append(["stage":stage,"type":event.type == .leftMouseDown ? 1 : 2,"tag":cg.getIntegerValueField(.eventSourceUserData),
            "eventNumber":event.eventNumber,"sourcePID":cg.getIntegerValueField(.eventSourceUnixProcessID),"window":event.windowNumber,
            "uptime":ProcessInfo.processInfo.systemUptime,"eventTimestamp":event.timestamp])
        if stage == "input" {
            if event.type == .leftMouseDown { trial.inputDown+=1 } else { trial.inputUp+=1 }
            if trial.inputDown==1 && trial.inputUp==1 && !trial.acknowledged {
                do {
                    try writeNew(["runID":runID,"trialID":trial.id,"receiverPID":receiverPID,"window":window.windowNumber,
                        "senderPID":trial.senderPID,"inputDown":trial.inputDown,"inputUp":trial.inputUp,
                        "scope":"neutralFixtureOnly_noProductOrCommercialClaim"],to:run.appendingPathComponent("trial-\(trial.id)-ack.json"))
                    trial.acknowledged=true
                } catch { finish("STOP_ackWriteFailed") }
            }
        }
    }
    func windowWillClose(_ notification:Notification) { if !finishing { finish("STOP_fixtureClosed") } }
    func finish(_ status:String) {
        guard !finishing else{return};finishing=true;timer?.invalidate();facts("finish")
        for (_,tap) in taps { CGEvent.tapEnable(tap:tap,enable:false) }
        let report:[String:Any]=["status":status,"runID":runID,"receiverPID":receiverPID,"window":window.windowNumber,
            "scope":"Two independent neutral AppKit events; no product screenshot/browser/session/permission mutation; not commercial acceptance",
            "executableSHA256":(try? Data(contentsOf:URL(fileURLWithPath:executable))).map(sha) ?? "unavailable",
            "stageFacts":stageFacts,"ownedWindowNativeMouseCounts":nativeMouseCounts,"trials":trials.map { t -> [String:Any] in
                ["trialID":t.id,"waitForReceipt":t.wait,"senderPID":t.senderPID,"expectedTag":t.tag,"expectedEventNumber":t.number,
                 "senderStartedUptime":t.started,"senderEndedUptime":t.ended as Any? ?? NSNull(),"senderExit":t.exit as Any? ?? NSNull(),
                 "inputDown":t.inputDown,"inputUp":t.inputUp,"acknowledged":t.acknowledged,"observations":t.rows,
                 "uncorrelatedOwnedFixtureObservations":t.uncorrelated]
            }]
        do { try writeNew(report,to:run.appendingPathComponent("report.json"));try FileHandle.standardOutput.write(contentsOf:json(report)) }
        catch { fputs("REPORT_WRITE_FAILED\n",stderr) }
        // Do not terminate another process or force a child after timeout.
        window.orderOut(nil);NSApp.stop(nil)
        NSApp.postEvent(NSEvent.otherEvent(with:.applicationDefined,location:.zero,modifierFlags:[],timestamp:0,
            windowNumber:0,context:nil,subtype:0,data1:0,data2:0)!,atStart:false)
    }
}

do {
    let args=CommandLine.arguments
    if args.count == 3 && args[1] == "--sender" { try sender(URL(fileURLWithPath:args[2])) }
    else if args.count == 3 && args[1] == "--run" {
        let run=URL(fileURLWithPath:args[2]).standardizedFileURL
        try require(run.deletingLastPathComponent().path == allowedRoot && run.path == run.resolvingSymlinksInPath().path,
                    "runPathOutsideScope")
        try require(mkdir(run.path,0o700)==0,"freshRunDirectoryRequired")
        let app=NSApplication.shared;_ = app.setActivationPolicy(.regular)
        let controller=ProbeController(run)
        do { try controller.begin();app.run() } catch { controller.finish("STOP_\(error)") }
        withExtendedLifetime(controller) {}
    } else { throw ProbeError.stopped("usageRunFreshDirectory") }
} catch {
    print("STOP \(error)");exit(1)
}
