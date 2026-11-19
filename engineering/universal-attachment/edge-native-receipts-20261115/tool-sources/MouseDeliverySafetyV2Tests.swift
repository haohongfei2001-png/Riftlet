import AppKit
import Foundation

private var passed=0
private func check(_ okay:Bool,_ reason:String) throws { if !okay {throw Failure(code:reason)} }
private func test(_ name:String,_ body:() throws -> Void) throws {try body();passed+=1;print("PASS \(name)")}
private func reject(_ code:String,_ body:() throws -> Void) throws {
    do {try body();throw Failure(code:"expectedRejection_"+code)} catch let error as Failure {try check(error.code==code,"wrongRejection_"+error.code)}
}
private func hash(_ n:Int) -> String {String(format:"%064x",n)}
private let first=hash(1),second=hash(2),oldFirst=hash(3),oldSecond=hash(4),session=hash(10),op=hash(20)
private let sent:[String:Any]=["assetIDDigest":first,"diagnosticSessionDigest":session,"afterDiagnosticSequence":40,
    "windowNumber":99,"mouseProbeTag":51000000000001 as Int64,"eventNumber":23001]
private func fixture(_ terminal:String?=nil) -> [[String:Any]] {
    var rows:[[String:Any]]=[]
    func add(_ body:[String:Any],tagged:Bool=false) {
        var row=body;row["diagnosticSessionDigest"]=session;row["diagnosticSequence"]=41+rows.count
        if tagged {row["windowNumber"]=99;row["mouseProbeTag"]=51000000000001 as Int64;row["eventNumber"]=23001;row["clickCount"]=1}
        rows.append(row)
    }
    func native(_ phase:String,_ status:String,_ down:Bool) {
        add(["event":"mouse_dispatch_boundary","phase":phase,"status":status,"mouseDown":down,"assetIDDigest":first],tagged:true)
    }
    add(["event":"mouse_application_event","phase":"down","mouseDown":true],tagged:true)
    native("windowEvent","received",true);native("inputDown","received",true);native("onDown","received",true);native("gate","accepted",true)
    add(["event":"selection_boundary","source":"mouse","targetRequested":true,"assetIDDigest":first],tagged:true)
    add(["event":"mouse_application_event","phase":"up","mouseDown":false],tagged:true)
    native("windowEvent","received",false);native("inputUp","received",false);native("release","selected",false)
    add(["event":"selection_submission_started","assetIDDigest":first])
    if terminal == "refusal" {add(["event":"click_input_refused","assetIDDigest":first,"critical":true,"phase":"resolveSelection"])}
    else if let terminal {
        add(["event":"click_target_resolved","assetIDDigest":first])
        add(["event":"attachment_entry_result","assetIDDigest":first,"operationIDDigest":op,"phase":terminal])
    }
    return rows
}
private func status(_ rows:[[String:Any]],_ identity:[String:Any]=sent) -> String { originalMouseReceipt(identity,records:rows)["status"] as? String ?? "missing" }

@main struct MouseDeliverySafetyV2Tests {
    static func main() throws {
        let targets=[first,second],known=[first,second,oldFirst,oldSecond]
        try test("legacyTwoTargetConfiguration") {try check(validateVisibleAssetConfiguration(targets:targets,known:nil)==Set(targets),"legacy")}
        try test("fourKnownRowsWithOnlyTwoTargets") {
            let result=try validateVisibleAssetConfiguration(targets:targets,known:known)
            try validateKnownVisibleMap(known,known:result);try check(result==Set(known),"known")
        }
        try test("maximumTwelveKnownRows") {let ids=(1...12).map(hash);let set=try validateVisibleAssetConfiguration(targets:targets,known:ids);try validateKnownVisibleMap(ids,known:set)}
        try test("singleCurrentVisibleTarget") {try validateKnownVisibleMap([second],known:Set(known))}
        for (name,list) in [("duplicateTargets",[first,first]),("threeTargets",known.prefix(3).map{$0}),("oneTarget",[first]),("malformedTarget",[first,"bad"])] {
            try test(name) {try reject("twoDistinctConfiguredAssetsRequired") {_=try validateVisibleAssetConfiguration(targets:list,known:known)}}
        }
        for (name,list) in [("emptyKnown",[String]()),("duplicateKnown",[first,second,second]),("missingTarget",[first,oldFirst]),
            ("malformedKnown",[first,second,"bad"]),("thirteenKnown",(1...13).map(hash))] {
            try test(name) {try reject("knownVisibleAssetsInvalid") {_=try validateVisibleAssetConfiguration(targets:targets,known:list)}}
        }
        for (name,list) in [("unrecognizedMapAsset",[hash(50)]),("duplicateMapAsset",[first,first]),("emptyMap",[String]()),("thirteenMapRows",(1...13).map(hash))] {
            try test(name) {try reject("unexpectedMapAssets") {try validateKnownVisibleMap(list,known:Set(known))}}
        }
        for kind in [CGEventType.leftMouseDown,.leftMouseUp] {
            try test("copyValidationNoPost_\(kind.rawValue)") {
                guard let source=CGEventSource(stateID:.privateState),let event=CGEvent(mouseEventSource:source,mouseType:kind,
                    mouseCursorPosition:CGPoint(x:31,y:47),mouseButton:.left) else {throw Failure(code:"eventConstruction")}
                event.setIntegerValueField(.mouseEventNumber,value:23001);event.setIntegerValueField(.eventSourceUserData,value:51000000000001)
                let sourcePID=event.getIntegerValueField(.eventSourceUnixProcessID),targetPID=event.getIntegerValueField(.eventTargetUnixProcessID)
                try validateNativeReadbackOnCopy(event,number:23001,tag:51000000000001)
                try check(event.location==CGPoint(x:31,y:47) && event.type==kind && event.getIntegerValueField(.eventSourceUnixProcessID)==sourcePID
                    && event.getIntegerValueField(.eventTargetUnixProcessID)==targetPID,"originalFieldsChanged")
                try reject("eventNativeReadbackMismatch") {try validateNativeReadbackOnCopy(event,number:23002,tag:51000000000001)}
                try reject("eventNativeReadbackMismatch") {try validateNativeReadbackOnCopy(event,number:23001,tag:51000000000002)}
                try reject("eventNativeReadbackArgumentsInvalid") {try validateNativeReadbackOnCopy(event,number:0,tag:51000000000001)}
            }
        }
        try test("nativeReceiptAloneDoesNotEndObservation") {let r=originalMouseReceipt(sent,records:fixture());try check(r["nativeReceiptComplete"] as? Bool==true && status(fixture())=="PENDING_ORIGINAL_RECEIPT","nativeOnly")}
        try test("explicitOriginalResolveRefusal") {let r=originalMouseReceipt(sent,records:fixture("refusal"));try check(r["status"] as? String=="NATIVE_AND_ORIGINAL_REFUSAL_OBSERVED" && r["explicitPreInputRefusal"] as? Bool==true,"refusal")}
        try test("originalEntryObservationNotCommercialCompletion") {let r=originalMouseReceipt(sent,records:fixture("inputTriggered"));try check(r["status"] as? String=="NATIVE_AND_ORIGINAL_ENTRY_OBSERVED" && r["uploadStartOrCompletionClaimed"] as? Bool==false && r["retryPermitted"] as? Bool==false,"entry")}
        try test("originalUnknownNeverRetries") {try check(status(fixture("unknown"))=="UNKNOWN_DO_NOT_REPOST","unknown")}
        try test("noMouseReceipt") {try check(status([])=="PENDING_ORIGINAL_RECEIPT","empty")}
        try test("wrongSessionCannotBorrowReceipt") {var s=sent;s["diagnosticSessionDigest"]=hash(30);try check(status(fixture("refusal"),s)=="PENDING_ORIGINAL_RECEIPT","session")}
        try test("wrongAssetCannotBorrowReceipt") {var s=sent;s["assetIDDigest"]=second;try check(status(fixture("refusal"),s)=="UNKNOWN_DO_NOT_REPOST","asset")}
        try test("wrongWindowCannotBorrowReceipt") {var s=sent;s["windowNumber"]=100;try check(status(fixture("refusal"),s)=="UNKNOWN_DO_NOT_REPOST","window")}
        try test("wrongNumberCannotBorrowReceipt") {var s=sent;s["eventNumber"]=23002;try check(status(fixture("refusal"),s)=="UNKNOWN_DO_NOT_REPOST","number")}
        try test("booleanNumberCannotMatch") {var r=fixture("refusal");r[0]["eventNumber"]=true;try check(status(r)=="UNKNOWN_DO_NOT_REPOST","boolean")}
        try test("duplicateSequenceRefused") {var r=fixture("refusal");r[1]["diagnosticSequence"]=41;try check(status(r)=="UNKNOWN_DO_NOT_REPOST","sequence")}
        try test("missingNativeBoundaryNotEnough") {var r=fixture("refusal");r.remove(at:2);try check(status(r)=="PENDING_ORIGINAL_RECEIPT","missing")}
        try test("wrongOrderNotEnough") {var r=fixture("refusal");r[1]["phase"]="inputDown";r[2]["phase"]="windowEvent";try check(status(r)=="UNKNOWN_DO_NOT_REPOST","order")}
        try test("assetlessTransportFinishNotEnough") {var r=fixture();r.append(["event":"input_transport_finished","diagnosticSessionDigest":session,"diagnosticSequence":52]);try check(status(r)=="PENDING_ORIGINAL_RECEIPT","global")}
        try test("refusalMustBeCritical") {var r=fixture("refusal");r[r.count-1]["critical"]=false;try check(status(r)=="PENDING_ORIGINAL_RECEIPT","critical")}
        try test("wrongAssetEntryNotEnough") {var r=fixture("inputTriggered");r[r.count-1]["assetIDDigest"]=second;try check(status(r)=="PENDING_ORIGINAL_RECEIPT","entryasset")}
        try test("entryMustFollowTargetResolution") {var r=fixture("inputTriggered");r.remove(at:r.count-2);try check(status(r)=="PENDING_ORIGINAL_RECEIPT","resolve")}
        try test("multipleOperationEntriesUnknown") {var r=fixture("inputTriggered");var extra=r.last!;extra["operationIDDigest"]=hash(21);extra["diagnosticSequence"]=54;r.append(extra);try check(status(r)=="UNKNOWN_DO_NOT_REPOST","operations")}
        try test("laterSameAssetSelectionInvalidatesAssociation") {var r=fixture("refusal");r.append(["event":"selection_boundary","assetIDDigest":first,"diagnosticSessionDigest":session,"diagnosticSequence":60]);try check(status(r)=="UNKNOWN_DO_NOT_REPOST","newselection")}
        try test("observedReadyStillDoesNotClaimUploadAcceptance") {let r=originalMouseReceipt(sent,records:fixture("ready"));try check(r["uploadStartOrCompletionClaimed"] as? Bool==false && r["retryPermitted"] as? Bool==false,"ready")}
        print("TOTAL \(passed) PASS; no GUI, event post, browser or product data write")
    }
}
