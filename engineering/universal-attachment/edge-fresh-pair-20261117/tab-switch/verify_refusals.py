"""Redacted independent audit of G7 adverse native input. Standard library only, local files and read-only SQLite."""
import argparse
from collections import Counter
from contextlib import closing
from datetime import datetime
import hashlib
import json
from pathlib import Path
import sqlite3
import uuid

SOURCE="62ab4b2638f78926a92dd01a0942aa98e72a7614"
OUTCOME_SHA="8c432630e0e98bb4241a671c78524caac5d014247eafc8cbb0ab839595b3389c"
STAGES=[("mouse_application_event","down",None,True),("mouse_dispatch_boundary","windowEvent","received",True),
        ("mouse_dispatch_boundary","inputDown","received",True),("mouse_dispatch_boundary","onDown","received",True),
        ("mouse_dispatch_boundary","gate","accepted",True),("selection_boundary",None,None,None),
        ("mouse_application_event","up",None,False),("mouse_dispatch_boundary","windowEvent","received",False),
        ("mouse_dispatch_boundary","inputUp","received",False),("mouse_dispatch_boundary","release","selected",False)]
ERRORS={610:"nativeSelectionChanged",611:"pageRejected(PAGE_ROUTE_UNSUPPORTED)"}


def need(s,why):
    if not s:raise ValueError(why)


def filehash(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""):h.update(b)
    return h.hexdigest()


def read(path):return json.loads(path.read_bytes())


def lines(path):return [json.loads(line) for line in path.read_bytes().splitlines() if line]


def idhash(v):return hashlib.sha256(str(uuid.UUID(v)).encode()).hexdigest()


def state(database):
    with closing(sqlite3.connect(database.resolve(strict=True).as_uri()+"?mode=ro&readonly_shm=1",uri=True,timeout=2)) as db:
        db.execute("PRAGMA query_only=ON");db.execute("BEGIN");db.row_factory=sqlite3.Row
        assets=[dict(a) for a in db.execute("SELECT id,sequence,image_json,status,visibility,active_operation_id FROM assets ORDER BY sort_at,sequence")]
        operations=[dict(a) for a in db.execute("SELECT * FROM operations ORDER BY sequence")]
        starts=[dict(a) for a in db.execute("SELECT * FROM upload_starts ORDER BY operation_id")]
    for a in assets:a["image"]=json.loads(a.pop("image_json"))
    return {"assets":assets,"operations":operations,"starts":starts}


def later_draft(saved,initial,stamp,explicit_ops):
    if not saved:return {"state":"NO_LATER_SNAPSHOT"}
    d=read(saved)
    if d.get("status")=="STOP":
        return {"state":"LATER_INSPECTION_UNAVAILABLE","snapshotSHA256":filehash(saved),
                "originalCGUnavailable":d.get("reason")=="originalCG304NotRestored"}
    need(d.get("action") in ("inspect","selection-status"),"READ_ONLY_DRAFT_SNAPSHOT_REQUIRED")
    need(datetime.fromisoformat(d["timestamp"].replace("Z","+00:00"))>=datetime.fromisoformat(stamp),"LATE_AX_SNAPSHOT_PREDATES_RUN")
    counts=Counter(d.get("operationImageNames",[]))
    checks={"sameFrontmostNativeTabWindow":d.get("frontmost") is True and all(d.get(k)==initial[k] for k in ("pid","edgeBirth","edgeWindow","nativeTabID","nativeWindowID")),
            "freshTemporaryDraftAndText":d.get("exactTemporaryDraft") is True and d.get("newNeutralText") is True and d.get("textSHA256")==initial["textSHA256"],
            "one614AndBothPriorNamedAttachments":d.get("priorImageCounts")==[1] and d.get("baselineImageCount")==1 and
                  counts==Counter(explicit_ops) and d.get("attachmentImageCount")==3 and d.get("unexpectedAttachmentCount")==0,
            "original14UTF16SelectedWords":d.get("selectedWords") is True and d.get("selectionLength")==14 and
                 d.get("selectedRangeLocation")==61 and d.get("selectedRangeLength")==14}
    return {"state":"ALL_TARGET_PROPERTIES_OBSERVED" if all(checks.values()) else "PARTIAL_TARGET_PROPERTIES_OBSERVED",
            "snapshotSHA256":filehash(saved),"timeUTC":d["timestamp"],"properties":checks}


def audit(args):
    root=args.run;folder=root/"trial"; orig=read(folder/"outcome.json")
    need(filehash(folder/"outcome.json")==OUTCOME_SHA,"RUN_OUTCOME_DIGEST_MISMATCH")
    p=read(folder/"prepared.json"); start=read(root/"queue-before.json"); after=state(args.database)
    raw=lines(folder/"raw-events.jsonl");control=lines(folder/"actions.jsonl");rest=read(folder/"restored.json")
    seq=[r["diagnosticSequence"] for r in raw]
    identity=p["identity"];session=p["nativePreflights"][0]["diagnosticSessionDigest"]
    need(seq==list(range(157,188)) and all(r["diagnosticSessionDigest"]==session for r in raw),"ORIGINAL_SESSION_NOT_CONTIGUOUS")
    need(identity["attemptID"]=="g7-adverse-fresh-tab-610-611-20261117" and orig["retries"]==0,"WRONG_ATTEMPT")
    by_uid={a["id"]:a for a in after["assets"]};olds={a["id"] for a in start["assets"]};media={}
    for a in after["assets"]:
        uid=a["id"];filename=str(uuid.UUID(uid))+".png"
        need(a["image"]["fileName"]==filename,"PRIVATE_FILE_ID_MISMATCH")
        media[uid]=filehash(args.media_dir/filename)
        need(media[uid]==a["image"]["sha256"],"PRIVATE_MEDIA_CHANGED")
    same_assets=all(by_uid.get(a["id"])==a for a in start["assets"])
    checks={"allPriorAssetRowsUnchanged":same_assets,"allPriorMediaBytesUnchanged":all(media[i]==h for i,h in start["media"].items()),
            "allOperationsExactlyUnchanged":after["operations"]==start["operations"],"allStartReceiptsExactlyUnchanged":after["starts"]==start["starts"]}
    need(all(checks.values()),"PREVIOUS_STORE_CHANGED")
    scan=[];times={};targets=[]
    for i,seed in enumerate((610,611),1):
        sent=read(folder/f"sender-{i}.json");key=sent["assetIDDigest"];target=p["targets"][key];uid=target["uuid"]
        cap=read(root/f"capture-{seed}.json");intent=read(folder/f"intent-{i}.json")
        need(sent["status"]=="singlePairPostedReceiptNotYetConfirmed" and sent["attemptID"]==identity["attemptID"]
             and sent["configurationSHA256"]==p["configSHA256"] and sent["diagnosticSessionDigest"]==session
             and sent["productBinarySHA256"]==identity["productBinarySHA256"] and intent["assetIDDigest"]==key
             and target["seed"]==seed and idhash(uid)==key and cap["systemScreenshotMetadata"] is True
             and media[uid]==cap["sha256"]==target["sha256"]==filehash(root/cap["fileName"]),"NEW_ORIGINAL_OR_SENDER_NOT_BOUND")
        tagged=[r for r in raw if r.get("mouseProbeTag")==sent["mouseProbeTag"] and r["diagnosticSequence"]>sent["afterDiagnosticSequence"]]
        need([(r["event"],r.get("phase"),r.get("status"),r.get("mouseDown")) for r in tagged]==STAGES,"TEN_NATIVE_STAGES_NOT_PROVEN")
        need(all(r.get("eventNumber")==sent["eventNumber"] and r.get("clickCount")==1 and r.get("windowNumber")==sent["windowNumber"]
                 for r in tagged) and all(r.get("assetIDDigest")==key for r in tagged if r["event"]!="mouse_application_event"),
             "TAG_EVENT_WINDOW_ASSET_MISMATCH")
        selected=tagged[5];need(selected.get("source")=="mouse" and selected.get("targetRequested") is True,"NO_MOUSE_SELECTION")
        scoped=[r for r in raw if r.get("assetIDDigest")==key]
        request=[r for r in scoped if r["event"]=="selection_submission_started"]
        refusal=[r for r in scoped if r["event"]=="click_input_refused"]
        need(len(request)==len(refusal)==1 and request[0]["diagnosticSequence"]<refusal[0]["diagnosticSequence"]
             and refusal[0].get("critical") is True and refusal[0]["phase"]=="resolveSelection" and refusal[0]["error"]==ERRORS[seed],
             "SCOPED_PRE_INPUT_REFUSAL_ABSENT")
        has_entry=any(r["event"] in ("click_target_resolved","attachment_entry_result","presentation_boundary") for r in scoped)
        need(not has_entry and not any(o["asset_id"]==uid for o in after["operations"]),"UNEXPECTED_RECEIVER_SIDE_EFFECT")
        need(by_uid[uid]["status"]=="pending" and by_uid[uid]["visibility"]=="visible" and by_uid[uid]["active_operation_id"] is None,
             "ASSET_NOT_RETAINED_PENDING_VISIBLE")
        scan.append({"seed":seed,"nativeTaggedStages":10,"distinctPhysicalUserClickProved":False,"softwareNativeClickReceipt":True,
                     "onePositiveMouseSelection":True,"exactCallbackSequence":selected["diagnosticSequence"],
                     "refusalAtSequence":refusal[0]["diagnosticSequence"],"refusal":ERRORS[seed],"refusalPhase":"resolveSelection",
                     "newOperations":0,"newStarts":0,"scopedSetterOrSwallowTrace":False,"pendingVisible":True})
        times[seed]=(tagged[2]["eventUptime"],selected["callbackUptime"],refusal[0]["uptime"])
        targets.append(uid)
    need(set(by_uid)==olds|set(targets) and not (olds&set(targets)),"UNEXPECTED_ADDED_ASSET")
    tick=lambda t:round(1000*t,3)
    armed=control[0];switch=control[1]["switchReceipt"];blank=control[2]["611BlankGuard"];ending=control[3]["611BlankAfterObservation"]
    need(armed["status"]=="originalArmed" and switch["status"]=="neutralSelected" and blank["status"]==ending["status"]=="boundOwnBlankStillSelected"
         and armed["originalTabID"]==rest["originalTabID"] and len({v["neutralTabID"] for v in (armed,switch,blank,ending)})==1
         and armed["originalTabID"]!=armed["neutralTabID"] and rest["status"]=="originalRestored","TAB_SWITCH_OR_RESTORE_UNBOUND")
    need(times[610][0]<=times[610][1]<=switch["requestedUptime"]<=times[610][2]<=switch["confirmedUptime"]<=blank["uptime"]
         <=times[611][0]<=times[611][1]<=times[611][2]<=ending["uptime"]<=rest["seconds"],"TRIAL_TIMING_ORIGINAL_MISMATCH")
    base=p["baselineDraft"];names=base["operationImageNames"]
    need(len(set(names))==len(names)==2 and base["baselineImageCount"]==1 and base["attachmentImageCount"]==3
            and base["selectedWords"] is True and base["selectionLength"]==14 and base.get("selectedRangeLocation")==61,
            "THREE_IMAGE_INITIAL_GUARD_MISSING")
    return {"schema":1,"source":SOURCE,"executableSHA256":identity["productBinarySHA256"],"diagnosticSequenceRange":[157,187],
        "sourceSHA256":{n:filehash(folder/n) for n in ("raw-events.jsonl","actions.jsonl","prepared.json","outcome.json","projection.json","restored.json","sender-1.json","sender-2.json")},
        "operationalResult":{"inputs":scan,"retryCount":0,"originalTabRestoreReceipt":True,"sameBoundBlankAt611Down":True,
            "firstDownToSwitchRequestMS":tick(switch["requestedUptime"]-times[610][0]),"firstCallbackToSwitchRequestMS":tick(switch["requestedUptime"]-times[610][1]),
            "switchRequestToConfirmedMS":tick(switch["confirmedUptime"]-switch["requestedUptime"]),
            "firstRejectionRelativeToConfirmationMS":tick(times[610][2]-switch["confirmedUptime"]),
            "blankGuardBeforeSecondDownMS":tick(times[611][0]-blank["uptime"]),"actualNativeDownIntervalMS":tick(times[611][0]-times[610][0])},
        "priorStore":{"assets":len(start["assets"]),"operations":len(start["operations"]),"starts":len(start["starts"]),"preservedMedia":len(start["media"]),**checks},
        "afterStore":{"assets":len(after["assets"]),"operations":len(after["operations"]),"starts":len(after["starts"])},
        "initialDraft":{"baseline614":1,"expectedPriorOperationFilenamesOnceEach":len(names),"totalAttachments":3,"originalSelectedUTF16Range":[61,14]},
        "originalRun":{"exitCode":3,"afterDraftProbe":"boundFreshComposerChanged","afterDraftFieldsIndividuallyUnavailable":True,"compositeProof":False},
        "laterReadOnlyDraft":later_draft(args.draft,base,orig["at"],names),
        "G7AETimeout1712Observed":any("-1712" in str(r.get("error","")) for r in raw)}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for key in ("run","database","media-dir"):p.add_argument("--"+key,type=Path,required=True)
    p.add_argument("--draft",type=Path)
    try:print(json.dumps(audit(p.parse_args()),indent=2,sort_keys=True))
    except (OSError,ValueError,KeyError,IndexError,TypeError,sqlite3.Error) as e:
        print(json.dumps({"status":"INPUT_NOT_VERIFIED","reason":str(e) if str(e).replace("_","").isalpha() else type(e).__name__}));raise SystemExit(2)
