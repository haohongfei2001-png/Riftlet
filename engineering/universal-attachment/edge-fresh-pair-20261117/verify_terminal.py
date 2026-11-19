"""Reproduce the allowlisted 612/613 per-file terminal audit from the exact local HAR. Python standard library only."""
import argparse
import base64
import binascii
from datetime import datetime
import hashlib
import json
import mmap
from pathlib import Path
import re

HAR_SHA="1b0974cb48d123c0f13d2b76acaea951d02988a4693d66f63e1abed7f3596097"
HAR_SIZE=8162985
EXPECTED={
    612:("3d2559084f871deef8b65a5d8ecb5655aede8d18a2b4aff91873da7518fad8ea","18b1cb86a43bae665c757d839dabb49aeb23bf8862e0afa338ab218c4a6dc193"),
    613:("5b199daa1655b9a16ec7b31a0e65467f3f8cd85dd8c9c6ee9e84fa568ff9094d","147236ba0069d7180c302fa12068e432103be8800f70b2133e8ebc0a95547151")}
BRACKETS = re.compile(rb'["{}\[\]]')
WS = re.compile(rb'[\x20\x09\x0a\x0d]*')
PRIMITIVE = re.compile(rb'[^,\]}\s]+')
FIRST = re.compile(rb'https://chatgpt\.com/', re.I)
STAMP = re.compile(rb'[0-9T:.+Z-]{18,40}')
METHOD = re.compile(rb'POST|PUT|OPTIONS|GET')


ENUMS=re.compile(rb"(?:ok|success|succeeded|complete|completed|processed|ready|file_ready|failed|failure|error|pending|running|processing|uploaded|created|in_progress|file\.processing\.(?:started|file_ready|completed|failed)|file)")
META_ENDPOINT=re.compile(rb"https://chatgpt\.com/backend-api/(?:f/)?files/(?:status|metadata|file-[A-Za-z0-9_-]+)(?:/status|/metadata)?/?(?=[?#]|$)")
CREATE_ENDPOINT=re.compile(rb"https://chatgpt\.com/backend-api/files/?(?=[?#]|$)")
PROCESS_ENDPOINT=re.compile(rb"https://chatgpt\.com/backend-api/files/process_upload_stream/?(?=[?#]|$)")
PREPARE_ENDPOINT=re.compile(rb"https://chatgpt\.com/backend-api/(?:f/)?conversation/prepare/?(?=[?#]|$)")
CONTENT_ENDPOINT=re.compile(rb"https://chatgpt\.com/backend-api/(?:estuary/content|files/download)(?:/|[?#]|$)")


def demand(condition, label):
    if not condition:
        raise ValueError(label)

class StructuralJSON:
    def __init__(self, buf):
        self.b = buf

    def end_string(self, pos):
        b = self.b
        end = b.find(b'"', pos+1)
        while end >= 0:
            i = end - 1
            while i > pos and b[i] == 92:
                i -= 1
            if (end - 1 - i) % 2 == 0:
                return end+1
            end = b.find(b'"', end+1)
        raise ValueError("HAR_STRING_BOUNDARY")

    def skip(self, pos):
        b = self.b
        c = b[pos]
        if c == 34:
            return self.end_string(pos)
        if c not in (91, 123):
            return PRIMITIVE.match(b, pos).end()
        depth = 1
        i = pos+1
        while depth:
            m = BRACKETS.search(b, i)
            demand(m, "HAR_CONTAINER_BOUNDARY")
            k = m.start()
            if b[k] == 34:
                i = self.end_string(k)
            else:
                depth += 1 if b[k] in (91,123) else -1
                i = k+1
        return i

    def items(self, span):
        b = self.b
        pos, limit = span
        demand(b[pos] in (91,123), "HAR_OBJECT_OR_ARRAY")
        is_object = b[pos] == 123
        i = WS.match(b,pos+1,limit).end()
        while i < limit and b[i] not in (93,125):
            key = None
            if is_object:
                j = self.end_string(i)
                key = (i+1, j-1)
                i = WS.match(b,j,limit).end()
                demand(b[i] == 58, "HAR_KEY_BOUNDARY")
                i = WS.match(b,i+1,limit).end()
            j = self.skip(i)
            yield key, (i,j)
            i = WS.match(b,j,limit).end()
            if i < limit and b[i] == 44:
                i = WS.match(b,i+1,limit).end()

    def fields(self, span, *names):
        if span is None:
            return {}
        requested = {name: re.compile(name.encode("ascii")) for name in names}
        result = {}
        for key, value in self.items(span):
            for name, pattern in requested.items():
                if pattern.fullmatch(self.b, *key):
                    demand(name not in result, "HAR_DUPLICATE_ALLOWLISTED_KEY")
                    result[name] = value
                    break
        return result

    def string_matches(self, span, pattern):
        if not span:
            return None
        a, z = span
        return pattern.fullmatch(self.b,a+1,z-1) if self.b[a] == 34 else None

    def number(self, span):
        if not span:
            return None
        m = re.compile(rb'-?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?').fullmatch(self.b,*span)
        return float(m.group()) if m else None

def payload(js,region,limit):
    fields=js.fields(region,"text","encoding") if region else {}
    if "text" not in fields: return "ABSENT_FROM_HAR",None
    a,z=fields["text"]
    if z-a==2: return "PRESENT_EMPTY",None
    if z-a>limit: return "EXCEEDS_BOUNDED_BODY",None
    if js.b[a]!=34: return "UNSUPPORTED_BODY",None
    try:
        text=json.loads(js.b[a:z])
        if "encoding" not in fields:
            return "TEXT",text.encode("utf-8")
        if js.string_matches(fields["encoding"],re.compile(rb'base64',re.I)):
            return "BASE64",base64.b64decode(text,validate=True)
    except (ValueError,TypeError,UnicodeError,binascii.Error):
        pass
    return "UNSUPPORTED_BODY",None

def classify(js,url):
    a,z=url
    for label,pattern in (("processing_stream",PROCESS_ENDPOINT),("create_upload",CREATE_ENDPOINT),
                          ("conversation_preparation",PREPARE_ENDPOINT),("preview_or_download",CONTENT_ENDPOINT),
                          ("file_metadata",META_ENDPOINT)):
        if pattern.match(js.b,a+1,z-1):return label
    return "other_first_party"

def found(js,span,token):
    if not span:return False
    return re.compile(rb"(?<![0-9A-Za-z_-])"+re.escape(token)+rb"(?![0-9A-Za-z_-])").search(js.b,*span) is not None

def base64_hit(js,span,token):
    if not span:return False
    # The inner complete 3-byte groups of each alignment can be sought without
    # decoding any unrelated entry. Exact identity is checked after a candidate hit.
    for cut in range(3):
        n=(len(token)-cut)//3*3
        if n>=12 and js.b.find(base64.b64encode(token[cut:cut+n]),*span)>=0:return True
    return False

def fields_in_body(raw,fid,route):
    allowed=("file_id","id","object","event","status","file_status","processing_status","file_processing_status","upload_status",
             "progress","file","files","result","data","payload","attachments")
    result={"matchedRecordEvents":[],"matchedFileProcessingStates":[],"genericHTTPReplyStatuses":[],"strictTerminalSignals":[]}
    def one_object(chunk):
        js=StructuralJSON(chunk)
        def text(span):
            v=js.string_matches(span,ENUMS) if span else None
            return v.group().decode("ascii") if v else None
        def visit(region,depth=0):
            if depth>5:return
            a,z=region
            if js.b[a]==91:
                i=WS.match(js.b,a+1).end()
                for _ in range(128):
                    if i>=z-1:return
                    end=js.skip(i)
                    visit((i,end),depth+1)
                    i=WS.match(js.b,end).end()
                    if i>=z or js.b[i]!=44:return
                    i=WS.match(js.b,i+1).end()
                return
            if js.b[a]!=123:return
            obj=js.fields(region,*allowed)
            match=lambda field:bool(obj.get(field) and js.string_matches(obj[field],re.compile(re.escape(fid))))
            tied=match("file_id") or (match("id") and (text(obj.get("object"))=="file" or route=="file_metadata"))
            st=text(obj.get("status"));ev=text(obj.get("event"))
            if depth==0 and st:result["genericHTTPReplyStatuses"].append(st)
            if tied:
                if ev:result["matchedRecordEvents"].append(ev)
                if ev in ("file.processing.completed","file.processing.failed"):
                    result["strictTerminalSignals"].append(ev)
                for key in ("file_processing_status","processing_status","file_status","upload_status","status"):
                    v=text(obj.get(key))
                    if v:result["matchedFileProcessingStates"].append({"field":key,"state":v})
                    if route in ("processing_stream","file_metadata") and key in ("file_processing_status","processing_status") and v in ("completed","succeeded","failed"):
                        result["strictTerminalSignals"].append("per_file_processing_"+v)
                    if route=="file_metadata" and key=="file_status" and v in ("processed","failed"):
                        result["strictTerminalSignals"].append("per_file_"+v)
            for key in ("file","files","result","data","payload","attachments"):
                if obj.get(key):visit(obj[key],depth+1)
        pos=WS.match(chunk,0).end()
        if pos<len(chunk) and chunk[pos] in (91,123):visit((pos,js.skip(pos)))
    try:
        one_object(raw)
    except (ValueError,IndexError,AttributeError):pass
    # SSE permits separate JSON frames with a data prefix. No full chat,
    # free-form messages, request headers, signed URLs or unrelated keys are emitted.
    if b"\n" in raw:
        for item in raw.splitlines()[:160]:
            if item.startswith(b"data:"):item=item[5:].lstrip()
            if item is not raw and item.startswith(b"{") and len(item)<=64*1024:
                try:one_object(item)
                except (ValueError,IndexError,AttributeError):pass
    for key in ("matchedRecordEvents","genericHTTPReplyStatuses","strictTerminalSignals"):
        result[key]=list(dict.fromkeys(result[key]))
    return result


def sha(value):
    return hashlib.sha256(value).hexdigest()


def file_hash(path):
    with path.open("rb") as handle:
        h=hashlib.sha256()
        for chunk in iter(lambda:handle.read(1024*1024),b""):h.update(chunk)
        return h.hexdigest()


def index_har(js):
    buf=js.b
    start=WS.match(buf,0).end()
    end=js.skip(start)
    demand(WS.match(buf,end).end()==len(buf),"HAR_ROOT_NOT_CLOSED")
    log=js.fields((start,end),"log")["log"]
    entries=js.fields(log,"entries")["entries"]
    demand(buf[entries[0]]==91 and buf[entries[1]-1]==93,"HAR_ENTRIES_NOT_CLOSED")
    out=[]
    for idx,(_,region) in enumerate(js.items(entries)):
        meta=js.fields(region,"startedDateTime","request","response")
        req=js.fields(meta["request"],"url","method","postData")
        rsp=js.fields(meta["response"],"status","content")
        date=js.string_matches(meta["startedDateTime"],STAMP)
        method=js.string_matches(req["method"],METHOD)
        a,z=req["url"]
        if not method or not date or not FIRST.match(buf,a+1,z-1):
            out.append(None)
            continue
        post=js.fields(req.get("postData"),"text","encoding")
        t=datetime.fromisoformat(date.group().decode().replace("Z","+00:00")).timestamp()
        out.append({"index":idx,"url":req["url"],"route":classify(js,req["url"]),"start":t,
                    "method":method.group().decode(),"httpStatus":int(js.number(rsp["status"])),
                    "postData":req.get("postData"),"postText":post.get("text"),"content":rsp.get("content")})
    return out


def link_creations(js,rows):
    ids={}; names={}; baselines={}; indices={}
    for row in rows:
        if not row or (row["route"],row["method"],row["httpStatus"])!=("create_upload","POST",200):continue
        _,raw=payload(js,row["postData"],64*1024)
        if not raw:continue
        src=StructuralJSON(raw); field=src.fields((0,src.skip(0)),"file_name").get("file_name")
        name=src.string_matches(field,re.compile(rb"riftlet-[A-Fa-f0-9-]{36}\.png"))
        if not name:continue
        matches=[seed for seed,(nh,_) in EXPECTED.items() if sha(name.group())==nh]
        if not matches:continue
        seed=matches[0]
        _,body=payload(js,row["content"],64*1024)
        demand(body and seed not in ids,"AMBIGUOUS_NAMED_CREATE")
        response=StructuralJSON(body)
        fid=response.string_matches(response.fields((0,response.skip(0)),"file_id").get("file_id"),re.compile(rb"file[-_][A-Za-z0-9_-]{6,128}"))
        demand(fid and sha(fid.group())==EXPECTED[seed][1],"CREATE_FILE_ID_UNBOUND")
        ids[seed],names[seed],baselines[seed],indices[seed]=fid.group(),name.group(),row["start"],row["index"]
    demand(set(ids)==set(EXPECTED) and len(set(ids.values()))==2,"TWO_DISTINCT_FILE_IDS_REQUIRED")
    return ids,names,baselines,indices


def audit(har,preserved=None,custody=None):
    st=har.stat()
    demand(st.st_size==HAR_SIZE,"HAR_SIZE_MISMATCH")
    with har.open("rb") as f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as buf:
        demand(sha(buf)==HAR_SHA,"HAR_DIGEST_MISMATCH")
        js=StructuralJSON(buf);rows=index_har(js)
        demand(len(rows)==68,"ENTRY_COUNT_MISMATCH")
        ids,names,baselines,created=link_creations(js,rows)
        results={seed:[] for seed in ids}
        for row in rows:
            if not row or row["route"]=="create_upload":continue
            content=row["content"];info=js.fields(content,"text","mimeType","encoding")
            mime=bool(js.string_matches(info.get("mimeType"),re.compile(rb"(?:application/(?:[a-z0-9.+-]*\+)?json|(?:text|application)/event-stream|text/plain)(?:;[^\r\n\x22]*)?",re.I)))
            encoded=bool(js.string_matches(info.get("encoding"),re.compile(b"base64",re.I)))
            for seed,fid in ids.items():
                if row["start"]<baselines[seed]:continue
                file_name=names[seed]
                request_id=found(js,row["url"],fid) or found(js,row["postText"],fid)
                request_name=found(js,row["postText"],file_name)
                response_id=found(js,info.get("text"),fid)
                response_name=found(js,info.get("text"),file_name)
                possible_encoded=mime and encoded and any(base64_hit(js,info.get("text"),s) for s in (fid,file_name))
                if not any((request_id,request_name,response_id,response_name,possible_encoded)):continue
                state="ABSENT_FROM_HAR" if "text" not in info else "NON_TEXT"
                facts={"genericHTTPReplyStatuses":[],"matchedRecordEvents":[],"matchedFileProcessingStates":[],"strictTerminalSignals":[]}
                if mime:
                    state,body=payload(js,content,256*1024)
                    if body:
                        response_id,response_name=fid in body,file_name in body
                        if not any((request_id,request_name,response_id,response_name)):continue
                        facts=fields_in_body(body,fid,row["route"])
                results[seed].append({"entry":row["index"],"route":row["route"],"method":row["method"],"httpStatus":row["httpStatus"],
                    "requestMatchedFileID":request_id,"requestMatchedOperationFilename":request_name,
                    "responseMatchedFileID":response_id,"responseMatchedOperationFilename":response_name,"bodyAvailability":state,**facts})
    now=har.stat()
    demand((st.st_ino,st.st_size,st.st_mtime_ns)==(now.st_ino,now.st_size,now.st_mtime_ns),"HAR_CHANGED_DURING_AUDIT")
    result={"schema":1,"entryIndexBase":0,"originalHARSHA256":HAR_SHA,"originalHARBytes":HAR_SIZE,
            "coverage":{"completeEntries":68,"entriesArrayClosed":True,"outerDocumentClosed":True},
            "files":{str(s):{"creationEntry":created[s],"operationFilenameSHA256":EXPECTED[s][0],"serviceFileIDSHA256":EXPECTED[s][1],
                    "laterFirstPartyEntries":rs,"explicitPerFileTerminalSignals":list(dict.fromkeys(x for r in rs for x in r["strictTerminalSignals"])),
                    "terminalObservation":"PRESENT" if any(r["strictTerminalSignals"] for r in rs) else "UNKNOWN"} for s,rs in results.items()}}
    if preserved:
        demand(preserved.stat().st_size==HAR_SIZE and file_hash(preserved)==HAR_SHA,"PRESERVED_COPY_MISMATCH")
        result["preservedCopySHA256"]=HAR_SHA
    if custody:
        stamp=custody.read_bytes()
        demand(sha(stamp)=="b039a62ca6e755fddf3e1efdd8da3b35ea0c6f2822debe9e5940c67456cd903a","CUSTODY_RECORD_MISMATCH")
        c=StructuralJSON(stamp)
        fields=c.fields((0,c.skip(0)),"kind","bytes","sha256","savePathBasis")
        demand(c.string_matches(fields["kind"],re.compile(b"REGULAR_DEVTOOLS_HAR")) and c.number(fields["bytes"])==HAR_SIZE and
               c.string_matches(fields["sha256"],re.compile(HAR_SHA.encode())) and
               c.string_matches(fields["savePathBasis"],re.compile(b"operatorObservedExactTicketNamePlusDevToolsSuffixAndDigest")),
               "CUSTODY_DOES_NOT_BIND_HAR")
        result["custodyRecordSHA256"]=sha(stamp)
    return result


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--har",type=Path,required=True)
    p.add_argument("--preserved",type=Path)
    p.add_argument("--custody",type=Path)
    args=p.parse_args()
    try:print(json.dumps(audit(args.har,args.preserved,args.custody),indent=2,sort_keys=True,allow_nan=False))
    except (OSError,KeyError,ValueError,TypeError,IndexError,AttributeError) as e:
        reason=str(e)
        print(json.dumps({"status":"INPUT_NOT_VERIFIED","reason":reason if re.fullmatch("[A-Z_]{1,70}",reason) else type(e).__name__}))
        raise SystemExit(2)
