import AppKit
import CryptoKit
import Foundation

func validateVisibleAssetConfiguration(targets:[String], known:[String]?) throws -> Set<String> {
    try require(targets.count == 2 && Set(targets).count == 2 && targets.allSatisfy(validHash), "twoDistinctConfiguredAssetsRequired")
    let visible = known ?? targets
    try require((2...12).contains(visible.count) && Set(visible).count == visible.count
        && visible.allSatisfy(validHash) && Set(targets).isSubset(of:Set(visible)), "knownVisibleAssetsInvalid")
    return Set(visible)
}
func validateKnownVisibleMap(_ rows:[String], known:Set<String>) throws {
    try require((1...12).contains(rows.count) && Set(rows).count == rows.count
        && rows.allSatisfy(validHash) && Set(rows).isSubset(of:known), "unexpectedMapAssets")
}

private struct EventFields: Equatable {
    let type:UInt32, x:Double, y:Double, flags:UInt64
    let number:Int64, tag:Int64, source:Int64, target:Int64, window:Int64, handlingWindow:Int64
    init(_ e:CGEvent) {
        type=e.type.rawValue;x=e.location.x;y=e.location.y;flags=e.flags.rawValue
        number=e.getIntegerValueField(.mouseEventNumber);tag=e.getIntegerValueField(.eventSourceUserData)
        source=e.getIntegerValueField(.eventSourceUnixProcessID);target=e.getIntegerValueField(.eventTargetUnixProcessID)
        window=e.getIntegerValueField(.mouseEventWindowUnderMousePointer)
        handlingWindow=e.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
    }
}
func validateNativeReadbackOnCopy(_ event:CGEvent, number:Int64, tag:Int64) throws {
    try require((1...Int64(Int16.max)).contains(number) && tag > 0 && tag < (1 << 48)
        && (event.type == .leftMouseDown || event.type == .leftMouseUp), "eventNativeReadbackArgumentsInvalid")
    let original=EventFields(event)
    guard let copy=event.copy(), copy !== event else { throw Failure(code:"distinctValidationCopyUnavailable") }
    try require(copy.getIntegerValueField(.mouseEventNumber) == number && NSEvent(cgEvent:copy)?.eventNumber == Int(number)
        && copy.getIntegerValueField(.eventSourceUserData) == tag
        && NSEvent(cgEvent:copy)?.cgEvent?.getIntegerValueField(.eventSourceUserData) == tag, "eventNativeReadbackMismatch")
    try require(EventFields(event) == original, "originalEventChangedDuringCopyValidation")
}

private func integer(_ value:Any?) -> Int64? {
    guard let n=value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
          n.doubleValue == Double(n.int64Value) else{return nil}
    return n.int64Value
}
private func boolean(_ value:Any?) -> Bool? {
    guard let n=value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else{return nil}
    return n.boolValue
}
private func sequence(_ row:[String:Any]) -> Int64 { integer(row["diagnosticSequence"]) ?? -1 }

/// Pure parser: positive native receipt and an original execution observation
/// are separate facts. Never classifies commercial upload success or retry.
func originalMouseReceipt(_ sent:[String:Any], records:[[String:Any]]) -> [String:Any] {
    var result:[String:Any]=["status":"PENDING_ORIGINAL_RECEIPT","nativeReceiptComplete":false,
        "uploadStartOrCompletionClaimed":false,"retryPermitted":false,"terminalObservationAvailable":false]
    guard let asset=sent["assetIDDigest"] as? String,validHash(asset),
          let session=sent["diagnosticSessionDigest"] as? String,validHash(session),
          let window=integer(sent["windowNumber"]),window>0,
          let tag=integer(sent["mouseProbeTag"]),tag>0,tag<(1<<48),
          let number=integer(sent["eventNumber"]),(1...Int64(Int16.max)).contains(number),
          let start=integer(sent["afterDiagnosticSequence"]),start>=0 else {
        result["status"]="UNKNOWN_DO_NOT_REPOST";result["reason"]="sentIdentityInvalid";return result
    }
    let rows=records.filter { $0["diagnosticSessionDigest"] as? String == session && sequence($0)>start }
    result["originalSessionRowsObserved"]=rows.count
    guard Set(rows.map(sequence)).count == rows.count,
          zip(rows.map(sequence),rows.map(sequence).dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
        result["status"]="UNKNOWN_DO_NOT_REPOST";result["reason"]="traceSequenceInvalid";return result
    }
    let tagged=rows.filter { integer($0["mouseProbeTag"]) == tag }
    result["taggedRowsObserved"]=tagged.count
    guard tagged.allSatisfy({ integer($0["eventNumber"]) == number && integer($0["windowNumber"]) == window
        && integer($0["clickCount"]) == 1 }) else {
        result["status"]="UNKNOWN_DO_NOT_REPOST";result["reason"]="taggedIdentityMismatch";return result
    }
    let native=tagged.filter { $0["event"] as? String == "mouse_dispatch_boundary" }
    let applications=tagged.filter { $0["event"] as? String == "mouse_application_event" }
    let selections=tagged.filter { $0["event"] as? String == "selection_boundary" }
    guard native.allSatisfy({ $0["assetIDDigest"] as? String == asset }) else {
        result["status"]="UNKNOWN_DO_NOT_REPOST";result["reason"]="nativeAssetMismatch";return result
    }
    let expected:[(String,String,Bool)]=[("windowEvent","received",true),("inputDown","received",true),
        ("onDown","received",true),("gate","accepted",true),("windowEvent","received",false),
        ("inputUp","received",false),("release","selected",false)]
    let matched=expected.map { phase,status,down in native.filter { $0["phase"] as? String == phase
        && $0["status"] as? String == status && boolean($0["mouseDown"]) == down } }
    result["nativeStageCounts"]=Dictionary(uniqueKeysWithValues:zip(expected,matched).map {
        ("\($0.0.0):\($0.0.1):\($0.0.2 ? "down":"up")",$0.1.count) })
    result["applicationEvents"]=applications.count;result["selections"]=selections.count
    let appDown=applications.filter { $0["phase"] as? String == "down" && boolean($0["mouseDown"]) == true }
    let appUp=applications.filter { $0["phase"] as? String == "up" && boolean($0["mouseDown"]) == false }
    guard tagged.count == 10,native.count == 7,matched.allSatisfy({$0.count==1}),
          appDown.count==1,appUp.count==1,selections.count==1,
          selections[0]["assetIDDigest"] as? String == asset,selections[0]["source"] as? String == "mouse",
          boolean(selections[0]["targetRequested"]) == true else{return result}
    let ordered=[sequence(appDown[0]),sequence(matched[0][0]),sequence(matched[1][0]),sequence(matched[2][0]),
        sequence(matched[3][0]),sequence(selections[0]),sequence(appUp[0]),sequence(matched[4][0]),
        sequence(matched[5][0]),sequence(matched[6][0])]
    guard zip(ordered,ordered.dropFirst()).allSatisfy({$0.0 < $0.1}) else {
        result["status"]="UNKNOWN_DO_NOT_REPOST";result["reason"]="nativeOrderMismatch";return result
    }
    result["nativeReceiptComplete"]=true
    let selected=sequence(selections[0]),released=ordered.last!
    let original=rows.filter { $0["assetIDDigest"] as? String == asset && sequence($0)>selected }
    guard !original.contains(where:{$0["event"] as? String == "selection_boundary"}) else {
        result["status"]="UNKNOWN_DO_NOT_REPOST";result["reason"]="sameAssetSelectionReplaced";return result
    }
    let submissions=original.filter { $0["event"] as? String == "selection_submission_started" && sequence($0)>released }
    guard submissions.count==1 else{return result}
    let submitted=sequence(submissions[0])
    let resolved=original.filter { $0["event"] as? String == "click_target_resolved" && sequence($0)>submitted }
    let refusals=original.filter { $0["event"] as? String == "click_input_refused" && sequence($0)>submitted
        && boolean($0["critical"]) == true && ["resolveSelection","submitSelection"].contains($0["phase"] as? String ?? "") }
    let entries=original.filter { ["attachment_entry_result","input_resource_refused"].contains($0["event"] as? String ?? "")
        && sequence($0)>submitted && validHash($0["operationIDDigest"] as? String ?? "") }
    guard refusals.count<=1,resolved.count<=1,
          Set(entries.compactMap{$0["operationIDDigest"] as? String}).count<=1 else {
        result["status"]="UNKNOWN_DO_NOT_REPOST";result["reason"]="originalExecutionAmbiguous";return result
    }
    if let refusal=refusals.first {
        result["status"]="NATIVE_AND_ORIGINAL_REFUSAL_OBSERVED"
        result["terminalObservationAvailable"]=true;result["terminalEvent"]="click_input_refused"
        result["terminalSequence"]=sequence(refusal);result["terminalPhase"]=refusal["phase"]
        result["explicitPreInputRefusal"]=refusal["phase"] as? String == "resolveSelection" && resolved.isEmpty && entries.isEmpty
        return result
    }
    if let resolution=resolved.first,let entry=entries.first,sequence(entry)>sequence(resolution),
       let phase=entry["phase"] as? String,phase.range(of:"^[a-zA-Z][a-zA-Z0-9]{0,63}$",options:.regularExpression) != nil {
        result["status"]=phase == "unknown" ? "UNKNOWN_DO_NOT_REPOST":"NATIVE_AND_ORIGINAL_ENTRY_OBSERVED"
        result["terminalObservationAvailable"]=true;result["terminalEvent"]=entry["event"]
        result["terminalSequence"]=sequence(entry);result["terminalPhase"]=phase;result["operationIDDigest"]=entry["operationIDDigest"]
        if phase == "unknown" { result["reason"]="originalEntryUnknown" }
    }
    return result
}

func observeOriginalMouseReceipt(_ sent:[String:Any], traceURL:URL) -> [String:Any] {
    let started=ProcessInfo.processInfo.systemUptime,deadline=started+5
    var last:[String:Any]=["status":"PENDING_ORIGINAL_RECEIPT","nativeReceiptComplete":false]
    var reads=0,readFailures=0
    while ProcessInfo.processInfo.systemUptime < deadline {
        do {
            let bytes=try ownedData(traceURL.path,limit:1_048_576)
            let records=try bytes.split(separator:10).map { line -> [String:Any] in
                guard let row=try JSONSerialization.jsonObject(with:Data(line)) as? [String:Any] else {throw Failure(code:"traceRecordInvalid")}
                return row
            }
            reads+=1;last=originalMouseReceipt(sent,records:records)
            last["traceSHA256"]=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
            if last["status"] as? String != "PENDING_ORIGINAL_RECEIPT" {break}
        } catch {readFailures+=1}
        // This services observations only. It never posts or activates anything.
        _=RunLoop.current.run(mode:.default,before:Date(timeIntervalSinceNow:0.025))
    }
    if last["status"] as? String == "PENDING_ORIGINAL_RECEIPT" {
        last["status"]="UNKNOWN_DO_NOT_REPOST";last["reason"]="originalReceiptObservationDeadline"
    }
    last["observationSeconds"]=ProcessInfo.processInfo.systemUptime-started
    last["traceReads"]=reads;last["traceReadFailures"]=readFailures
    last["retryPermitted"]=false;last["uploadStartOrCompletionClaimed"]=false
    return last
}
