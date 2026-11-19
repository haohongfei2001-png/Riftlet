"""Read the sealed G9 ordinary App trace, local native outcome and bounded QA status; only print whitelisted facts."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
from uuid import UUID

CODE_REASONS = {"fileBlobMissing","historyUnavailable","started","firstProgress","progressUnavailable"}
METRICS = ("edgeMatchedNodes","edgeNewMatchedNodes","edgeMatchedOriginalFormNodes","edgeBlobMatchedNodes","edgeFilenameMatchedNodes",
           "edgeChangedMatchedPreviews","edgeProgressNodes","edgeLoadedImageNodes","edgeErrorAttributeNodes")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(ok, message):
    if not ok:
        raise ValueError(message)


def verify(packed_path, outcome_path, reader_path):
    packed=packed_path.read_bytes()
    with gzip.open(packed_path,"rb") as source:
        raw=source.read(1024*1024+1)
    require(len(raw)<=1024*1024,"unexpected trace size")
    rows=[json.loads(line) for line in raw.splitlines()]
    require(len(rows)==347 and [r["diagnosticSequence"] for r in rows]==list(range(rows[0]["diagnosticSequence"],rows[-1]["diagnosticSequence"]+1))
            and len({r["diagnosticSessionDigest"] for r in rows})==1,"wrong or discontinuous original session")
    out=json.loads(outcome_path.read_bytes()); reader=json.loads(reader_path.read_bytes())
    image_details=[]
    for seed in (617,618):
        case, = [v for v in out["results"] if v["seed"]==seed]
        op, = case["operations"]
        op_digest=sha(str(UUID(op["id"])).encode())
        linked=[v for v in rows if v.get("operationIDDigest")==op_digest and v["event"]=="attachment_entry_result"]
        samples=[v["edgeSampleNumber"] for v in linked]
        require(samples==list(range(1,len(samples)+1)) and linked,"missing per-file samples")
        decisions=Counter(v["edgeProgressDecision"] for v in linked)
        require(set(decisions)<=CODE_REASONS,"unrecognized decision; add its bounded product enum")
        maxima={name:max(v[name] for v in linked) for name in METRICS}
        reader_row, = [v for v in reader["files"] if v["seed"]==seed]
        name_sha=sha(("riftlet-"+op["id"]+".png").encode("ascii"))
        require(reader_row["verified"] is True and reader_row["filenameSHA256"]==name_sha, "original reader File did not match operation")
        image_details.append({"seed":seed,"samples":len(samples),"firstSeq":linked[0]["diagnosticSequence"],"lastSeq":linked[-1]["diagnosticSequence"],
            "windowMilliseconds":round((linked[-1]["uptime"]-linked[0]["uptime"])*1000,3),"progressDecisions":dict(decisions),
            "allSamplesOriginalSetterEntered":all(v["setterEntered"] is True for v in linked),
            "allSamplesOriginalChangeReturned":all(v["changeReturned"] is True for v in linked),
            "allSamplesOriginalTextSelectionAndDraft":all(v.get("edgeOriginalDraftCurrent") is True and
               v.get("edgeOriginalTextUnchanged") is True and v.get("edgeOriginalSelectionUnchanged") is True for v in linked),
            "allSamplesRetainedEightBaselineNodes":all(v.get("edgeBaselineAttachmentNodes")==v.get("edgeRetainedBaselineAttachmentNodes")==8 for v in linked),
            "allSamplesNoScanLimitOrSamplingFailure":all(v.get("edgeScanLimited") is False and v.get("edgeSamplingFailed") is False for v in linked),
            "positiveStartSamples":sum(v.get("startObserved") is True for v in linked),"maxReportedNodeCounts":maxima,
            "actualSystemPNGBytes":case["original"]["bytes"],"nativeReaderIndependentlyMatchedOriginalFilenameAndFile":True})
    cmds=[v for v in rows if v["event"]=="edge_web_command"]
    starts=[i for i,v in enumerate(cmds) if v["action"]=="begin"]
    require(len(starts)==2,"two independent begins required")
    for begin,item in zip(starts,image_details):
        stop=next(i for i in range(begin+1,len(cmds)) if cmds[i]["action"] in ("commit","discard"))
        sel=[v for v in cmds[begin:stop+1] if v["action"]!="observe"]
        require([v["action"] for v in sel]==["begin"]+["chunk"]*6+["commit"] and
                all(v["succeeded"] is True and v["phase"]=="complete" for v in sel),"ordinary input commands differed")
        item["ordinarySequence"]={"begin":1,"returnedChunks":6,"commit":1}
    require(reader["reason"]=="DEADLINE" and reader["mounted"] is False and reader["restored"] is True
            and reader["newOwnerPreserved"] is False and reader["creates"]==[] and reader["candidates"]==[],"wrong reader result")
    return {"schema":1,"trace":{"rows":len(rows),"bytes":len(raw),"SHA256":sha(raw),"gzipBytes":len(packed),"gzipSHA256":sha(packed)},
            "priorOutcomeSHA256":sha(outcome_path.read_bytes()),"readerStatusSHA256":sha(reader_path.read_bytes()),
            "images":image_details,"reader":{"inputFiles":reader["diagnostics"]["inputFiles"],
                 "originalCreateJSONMatches":reader["diagnostics"]["createJSONCalls"],
                 "originalProcessingResponses":reader["diagnostics"]["processingResponses"],
                 "matchingReaders":reader["diagnostics"]["matchedReaders"],"terminalCandidates":0,
                 "reason":"DEADLINE","restored":True}}


if __name__=="__main__":
    root=Path(__file__).resolve().parent.parent
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--gzip",type=Path,default=root/"private-after/ordinary-original-trace.jsonl.gz")
    p.add_argument("--outcome",type=Path,default=root/"observations/outcome.json")
    p.add_argument("--reader",type=Path,default=root/"reader-status-1794923016898482000.json")
    p.add_argument("--expect",type=Path)
    p.add_argument("--output",type=Path)
    args=p.parse_args()
    result=verify(args.gzip,args.outcome,args.reader)
    if args.expect:
        require(json.loads(args.expect.read_bytes())==result,"sealed projection differs")
        print("PASS: 12 completed chunks, 2 commits, 145 bound observations, original reader and compressed trace")
    elif args.output:
        with args.output.open("x") as f:
            print(json.dumps(result,indent=2,sort_keys=True),file=f)
    else:
        print(json.dumps(result,indent=2,sort_keys=True))
