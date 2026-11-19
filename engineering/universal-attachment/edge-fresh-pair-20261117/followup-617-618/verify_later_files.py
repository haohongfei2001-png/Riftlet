"""Read fixed DevTools exports offline, link three original creates, and project per-file response evidence."""
import argparse
import base64
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

H68="1b0974cb48d123c0f13d2b76acaea951d02988a4693d66f63e1abed7f3596097"
H191="b9c6fdff2ee7610124304e28061f93fcaa2a3aa4bedc69f3fa0342693097a00f"
TRUSTED={
    612:("3d2559084f871deef8b65a5d8ecb5655aede8d18a2b4aff91873da7518fad8ea","18b1cb86a43bae665c757d839dabb49aeb23bf8862e0afa338ab218c4a6dc193"),
    613:("5b199daa1655b9a16ec7b31a0e65467f3f8cd85dd8c9c6ee9e84fa568ff9094d","147236ba0069d7180c302fa12068e432103be8800f70b2133e8ebc0a95547151"),
    615:("946a263454eed9e29aac766e0d719bdd91dd572fc7d40352782bc346d53994b3","b7d05c9ad165ed79acc876c4abf0fb01ed03a00f1980c15ae57eb3abedd2eb48")}
STATES={"ok","success","succeeded","complete","completed","processed","ready","file_ready","failed","failure","error","pending","running","processing","uploaded","created","in_progress"}
EVENTS={"file.processing.started","file.processing.file_ready","file.processing.completed","file.processing.failed"}
FINAL={"complete","completed","succeeded","processed","failed","failure"}
STRONG_KEYS=("file_status","file_processing_status","processing_status","upload_status","status")
AUX_KEYS=("_webSocketMessages","_eventSourceMessages","_eventSourceEvents")


def require(ok,why):
    if not ok: raise ValueError(why)


def digest(data):
    if isinstance(data,str): data=data.encode()
    return hashlib.sha256(data).hexdigest()


def load(path,expected,count=None):
    require(re.fullmatch("[0-9a-f]{64}",expected) and path.is_file() and not path.is_symlink(),"HAR_SOURCE_NOT_VERIFIED")
    before=path.stat()
    require(0<before.st_size<400*1024**2,"HAR_SIZE_LIMIT")
    raw=path.read_bytes()
    require(digest(raw)==expected,"HAR_DIGEST_MISMATCH")
    rows=json.loads(raw)["log"]["entries"]
    after=path.stat()
    require(isinstance(rows,list) and (count is None or len(rows)==count) and
            (before.st_ino,before.st_size,before.st_mtime_ns)==(after.st_ino,after.st_size,after.st_mtime_ns),"HAR_CHANGED_OR_BAD_COUNT")
    return rows,{"sha256":expected,"bytes":len(raw),"completeEntries":len(rows),"outerDocumentClosed":True}


def first(url):
    u=urlsplit(url)
    return u.scheme.lower() in ("https","wss") and u.hostname=="chatgpt.com" and u.port in (None,443) and not u.username and not u.password


def category(url):
    path=unquote(urlsplit(url).path).rstrip("/")
    if path=="/backend-api/files":return "create_upload"
    if path=="/backend-api/files/process_upload_stream":return "processing_stream"
    if re.fullmatch(r"/backend-api/(?:f/)?conversation/prepare",path):return "conversation_preparation"
    if re.match(r"/backend-api/(?:estuary/content|files/download)(?:/|$)",path):return "preview_or_download"
    if re.fullmatch(r"/backend-api/(?:f/)?files/(?:status|metadata|file[-_][A-Za-z0-9_-]+)(?:/status|/metadata)?",path):return "file_metadata"
    return "other_first_party"


def content(o):
    if "text" not in o: return "ABSENT_FROM_HAR",""
    text=o.get("text")
    if not isinstance(text,str):return "UNSUPPORTED",""
    if not text:return "PRESENT_EMPTY",""
    if o.get("encoding")=="base64":
        try: return "BASE64",base64.b64decode(text,validate=True).decode("utf-8")
        except (ValueError,UnicodeError):return "NON_UTF8_OR_NON_TEXT",""
    if o.get("encoding") is not None:return "UNSUPPORTED",""
    return "TEXT",text


def stamp(entry):
    return datetime.fromisoformat(entry["startedDateTime"].replace("Z","+00:00")).timestamp()


def bindings(first_rows,second_rows):
    result={}
    for rows,expected in ((first_rows,{612,613}),(second_rows,{615})):
        for i,e in enumerate(rows):
            q=e["request"];resp=e["response"]
            if q["method"]!="POST" or resp["status"]!=200 or not first(q["url"]) or category(q["url"])!="create_upload":continue
            try: name=json.loads(content(q.get("postData",{}))[1])["file_name"]
            except (KeyError,ValueError,TypeError): continue
            for seed in expected:
                if digest(name)!=TRUSTED[seed][0]: continue
                fid=json.loads(content(resp["content"])[1])["file_id"]
                require(seed not in result and isinstance(fid,str) and re.fullmatch(r"file[-_][A-Za-z0-9_-]{6,128}",fid) and
                        digest(fid)==TRUSTED[seed][1],"ORIGINAL_ID_OR_FILENAME_MISMATCH")
                result[seed]=(fid,name,stamp(e),i)
    require(set(result)==set(TRUSTED) and len(set(v[0] for v in result.values()))==3,"ORIGINAL_CREATIONS_INCOMPLETE")
    return result


def objects(data):
    if not data:return []
    try:return [json.loads(data)]
    except (ValueError,RecursionError): pass
    vals=[]
    for line in data.splitlines():
        line=line.strip()
        if line.startswith("data:"):line=line[5:].lstrip()
        if not line.startswith(("{","[")):continue
        try: vals.append(json.loads(line))
        except (ValueError,RecursionError):pass
    return vals


def nodes(doc):
    stack=[doc]
    while stack:
        o=stack.pop()
        if isinstance(o,dict):
            yield o
            stack.extend(o.values())
        elif isinstance(o,list):stack.extend(o)


def record_facts(docs,fid,name,route,secure_metadata=False):
    states=[];events=[];signals=[];generic=[]
    for doc in docs:
        if isinstance(doc,dict) and isinstance(doc.get("status"),str) and doc["status"] in STATES:generic.append(doc["status"])
        for o in nodes(doc):
            tied=(o.get("file_id")==fid or (o.get("id")==fid and (o.get("object")=="file" or route=="file_metadata")))
            if not tied:
                # A response scoped to /files/<exact service id> also binds its top-level metadata.
                tied=bool(secure_metadata and o is doc and "file_id" not in o and "id" not in o)
            if not tied or any(isinstance(o.get(k),str) and o[k]!=name for k in ("file_name","filename")):continue
            for field in ("event","type"):
                ev=o.get(field)
                if isinstance(ev,str) and ev in EVENTS:
                    events.append(ev)
                    if ev in ("file.processing.completed","file.processing.failed"):signals.append(ev)
            for field in STRONG_KEYS:
                state=o.get(field)
                if not isinstance(state,str):continue
                v=state.lower()
                if v not in STATES:continue
                states.append((field,v))
                if field in ("file_status","file_processing_status","processing_status") and v in FINAL:
                    signals.append(field+"="+v)
    return {"fileStates":[{"field":k,"state":v} for k,v in sorted(set(states))],
            "matchedEvents":sorted(set(events)),"explicitTerminalSignals":sorted(set(signals)),
            "genericStatuses":sorted(set(generic))}


def match_token(token,*values):
    rx=re.compile(r"(?<![A-Za-z0-9_-])"+re.escape(token)+r"(?![A-Za-z0-9_-])")
    return any(rx.search(v) for v in values if isinstance(v,str))


def texts_in_docs(docs):
    # JSON-escape normalization for exact token matching, including nested objects and lists.
    for doc in docs:
        stack=[doc]
        while stack:
            v=stack.pop()
            if isinstance(v,str):yield v
            elif isinstance(v,dict):stack.extend(v.values())
            elif isinstance(v,list):stack.extend(v)


def audit(rows,spec,orig):
    found={s:[] for s in orig};coverage=Counter();stamps=[]
    for i,e in enumerate(rows):
        ts=stamp(e);stamps.append(e["startedDateTime"])
        q=e["request"];r=e["response"];url=q["url"]
        if not first(url):continue
        coverage["firstPartyEntries"]+=1
        route=category(url)
        request_text=content(q.get("postData",{}))[1]
        status,body=content(r.get("content",{}));coverage["responses_"+status]+=1
        mime=str(r.get("content",{}).get("mimeType","")).lower()
        may_parse=(("json" in mime or "event-stream" in mime or mime.startswith("text/plain")) or body.lstrip().startswith(("{","[","data:")))
        docs=objects(body) if may_parse else []
        if may_parse and body:coverage["structuredResponsesParsed" if docs else "structuredResponsesWithoutJSON"]+=1
        dat=tuple(texts_in_docs(docs));request_data=tuple(texts_in_docs(objects(request_text)))
        frames=[]
        for k in AUX_KEYS:
            values=e.get(k,[])
            if isinstance(values,list):
                coverage["capturedAuxiliaryFrames"]+=len(values)
                for v in values:
                    if isinstance(v,dict) and v.get("type")!="send":
                        text=v.get("data")
                        if isinstance(text,str):frames.append(text)
        frame_docs=[doc for f in frames for doc in objects(f)]
        frame_text=tuple(texts_in_docs(frame_docs))
        for seed,(fid,name,created,_) in orig.items():
            if ts<created:continue
            req=[match_token(t,unquote(url),request_text,*request_data) for t in (fid,name)]
            res=[match_token(t,body,*dat) for t in (fid,name)]
            aux=[match_token(t,*frames,*frame_text) for t in (fid,name)]
            if not any(req+res+aux):continue
            secure=route=="file_metadata" and fid in unquote(urlsplit(url).path).split("/")
            facts=record_facts(docs+frame_docs,fid,name,route,secure)
            found[seed].append({"index":i,"category":route,"method":q["method"],"httpStatus":r["status"],
                       "body":status,"requestExactFileID":req[0],"requestExactFilename":req[1],
                       "responseExactFileID":res[0],"responseExactFilename":res[1],"auxFrameMatched":any(aux),**facts})
    spec=dict(spec,coverage=dict(sorted(coverage.items())),earliestRequest=min(stamps,key=lambda x:datetime.fromisoformat(x.replace("Z","+00:00"))),
              latestRequest=max(stamps,key=lambda x:datetime.fromisoformat(x.replace("Z","+00:00"))))
    spec["files"]={str(s):{"identityBearingEntryCount":len(x),"matchedIndices":[v["index"] for v in x],
                "explicitFileStatusEntryCount":sum(any(st["field"]=="file_status" for st in v["fileStates"]) for v in x),
                "explicitTerminalEntryCount":sum(bool(v["explicitTerminalSignals"]) for v in x),
                "serverFileTerminal":"EVIDENCED" if any(v["explicitTerminalSignals"] for v in x) else "UNKNOWN","entries":x} for s,x in found.items()}
    return spec


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--private-build", type=Path, required=True, help="Directory containing the two preserved original private exports")
    p.add_argument("--new-har",type=Path);p.add_argument("--sha");p.add_argument("--output",type=Path);p.add_argument("--expect",type=Path)
    a=p.parse_args()
    require(bool(a.new_har)==bool(a.sha),"NEW_EXPORT_AND_EXPECTED_SHA_REQUIRED_TOGETHER")
    base=a.private_build/"pr69-adverse-20261117/g7-private-export"/("preserved-"+H68+".har")
    later=a.private_build/"pr69-har-615-20261117"/("preserved-"+H191+".har")
    r68,i68=load(base,H68,68);r191,i191=load(later,H191,191)
    orig=bindings(r68,r191)
    packet={"schema":1,"entryIndexBase":0,"sources":{"612_613":audit(r68,i68,orig),"615_616":audit(r191,i191,orig)},
            "authenticatedOriginals":{str(s):{"operationFilenameSHA256":v[0],"serviceFileIDSHA256":v[1]} for s,v in TRUSTED.items()}}
    if a.new_har:
        rnew,info=load(a.new_har,a.sha)
        packet["sources"]["617_618"]=audit(rnew,info,orig)
    printed=(json.dumps(packet,indent=2,sort_keys=True)+"\n").encode()
    if a.output:
        with a.output.open("xb") as f:f.write(printed)
    elif a.expect:require(a.expect.read_bytes()==printed,"PROJECTION_MISMATCH")
    else:print(printed.decode(),end="")
    if a.output or a.expect:
        print(json.dumps({"projectionSHA256":digest(printed),"captures":{k:{"entries":v["completeEntries"],
            "firstParty":v["coverage"]["firstPartyEntries"],"identityMatches":{s:info["identityBearingEntryCount"] for s,info in v["files"].items()},
            "terminalEntries":{s:info["explicitTerminalEntryCount"] for s,info in v["files"].items()}} for k,v in packet["sources"].items()}},sort_keys=True))


if __name__=="__main__":main()
