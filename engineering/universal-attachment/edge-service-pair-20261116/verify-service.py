"""Offline, source-pinned projections of two neutral upload transactions.

Only structural offsets are traversed for unrelated HAR fields. No general HAR
JSON deserialization, URL/query parser, cookie/header dump or PUT body access.
"""
import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import json
import mmap
from pathlib import Path
import re

SOURCE = "4fddbe800991bb3f68ef632b08085f7175344d0aaca47e8d8bda2e37a0a99372"
# Operation and exact neutral request filename allowlists, in SHA-256 form.
FIXTURES = {
    605: ("42757826432694954c594df4941870ee7737caf43dcf93e030a12189309a4cc6", "be9886a61741143825d31d55431f8206a67c50c1a4f6d71bc10adfdf6f356e8b"),
    606: ("680c6903664ca8baf633f71f51d69e74c016232a0e067d0e7c822801c713909f", "4d22b2c926148a54fa6a78edf63d0b1a988e2ce2f3a03265eda541ecc2d30ca9"),
}
BRACKETS = re.compile(rb'["{}\[\]]')
WS = re.compile(rb'[\x20\x09\x0a\x0d]*')
PRIMITIVE = re.compile(rb'[^,\]}\s]+')
LOCATOR = re.compile(rb'[A-Za-z0-9:/.%_~+!$&()=,@-]+')
ID_BYTES = rb'file[-_][A-Za-z0-9_-]{6,128}'


def sha(data):
    return hashlib.sha256(data).hexdigest()


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


def time_iso(value):
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00","Z")


def near_fixture(start):
    if start.year != 2026 or start.month != 11 or start.day != 16 or start.hour != 13:
        return None
    if 7 <= start.minute <= 9:
        return 605
    if 14 <= start.minute <= 16:
        return 606
    return None


def only(pattern, buf, span):
    """Find one allowlisted capture inside an eligible neutral text field."""
    if not span:
        return None
    matches = list(pattern.finditer(buf,*span))
    if len(matches) > 1:
        raise ValueError("NON_UNIQUE_ALLOWED_FIELD")
    return matches[0].group(1) if matches else None


def body_field_pattern(key, value, quoted=True):
    left = rb'(?<=[{,])\s*\\"' + key + rb'\\"\s*:\s*'
    return re.compile(left + (rb'\\"(' + value + rb')\\"' if quoted else rb'(' + value + rb')(?=[\s,}])'))


def storage_locator(buf, low, high):
    # Only the returned locator's HTTPS DNS authority/path may be materialized.
    if not re.compile(rb'https://[a-z0-9.-]+(?::\d{1,5})?/', re.I).match(buf,low,high):
        return None
    m = LOCATOR.match(buf,low,high)
    if not m:
        return None
    boundary = m.end()
    if boundary > low + 1200 or buf[boundary:boundary+1] not in (b"?", b'"', b"\\"):
        return None
    return m.group()


def route(js, url):
    # Compare only known endpoint prefixes. No other URL's path or query is projected.
    a, z = url
    prefix = b'"https://chatgpt.com/backend-api/files'
    if not re.compile(re.escape(prefix)).match(js.b,a,z):
        return None
    off = a+len(prefix)
    for suffix, kind in ((b"/process_upload_stream","PROCESS"), (b"","CREATE")):
        if re.compile(re.escape(suffix)).match(js.b,off,z) and js.b[off+len(suffix):off+len(suffix)+1] in (b"?",b'"'):
            return kind
    return "OTHER_FILE_ENDPOINT"


def header(js, headers, wanted, want_digits=False):
    matches = []
    name_check = re.compile(wanted,re.I)
    for _, record in js.items(headers):
        projected = js.fields(record,"name","value")
        if not js.string_matches(projected.get("name"), name_check):
            continue
        val = projected.get("value")
        if want_digits:
            digits = js.string_matches(val, re.compile(rb'\d{1,12}'))
            matches.append(int(digits.group()) if digits else None)
        else:
            matches.append(bool(val and val[1]-val[0] > 2))
    demand(len(matches) <= 1, "DUPLICATE_ALLOWED_HEADER")
    return matches[0] if matches else None


def body(js, obj):
    return js.fields(obj,"text").get("text")


def walk_projection(js):
    log = js.fields((0,len(js.b)),"log")["log"]
    entries = js.fields(log,"entries")["entries"]
    collected, count = [], 0
    for idx, (_, item) in enumerate(js.items(entries)):
        count += 1
        meta = js.fields(item,"startedDateTime","time","timings","request","response")
        iso = js.string_matches(meta["startedDateTime"],re.compile(rb'[0-9T:.+Z-]{18,40}'))
        demand(iso,"HAR_UTC_TIMESTAMP")
        start = datetime.fromisoformat(iso.group().decode("ascii").replace("Z","+00:00")).astimezone(timezone.utc)
        seed = near_fixture(start)
        if seed is None:
            continue
        req = js.fields(meta["request"], "method","url")
        verb = js.string_matches(req["method"],re.compile(rb'POST|PUT|OPTIONS'))
        if not verb:
            continue
        method = verb.group().decode("ascii")
        kind = route(js,req["url"]) if method in ("POST","OPTIONS") else None
        if method == "POST" and kind not in ("CREATE","PROCESS"):
            continue
        collected.append((idx,seed,start,method,kind,req,meta))
    demand(count == 498,"HAR_ENTRY_COUNT")
    return collected, count


def one(items, label):
    items = list(items)
    demand(len(items) == 1, label)
    return items[0]


def key_count(buf, span, key):
    return len(list(re.compile(rb'(?<=[{,])\s*\\"' + key + rb'\\"\s*:').finditer(buf,*span)))


def matches_locator(js, span, locator):
    a,z = span
    match = re.compile(re.escape(locator)).match(js.b,a+1,z-1)
    return bool(match and js.b[match.end():match.end()+1] in (b'?',b'"'))


def request_record(js, row):
    index, _, start, verb, _, _, meta = row
    status = js.number(js.fields(meta["response"],"status").get("status"))
    length = js.number(meta["time"])
    demand(status is not None and length is not None and length >= 0,"MISSING_HAR_RESPONSE_OR_DURATION")
    end = start + timedelta(milliseconds=length)
    return dict(harEntryIndexZeroBased=index, method=verb, httpStatus=int(status),
                startUTC=time_iso(start), endUTC=time_iso(end), durationMS=round(length,3)), end


def projected_name(js, row, name_hash):
    req = js.fields(row[6]["request"], "postData")
    text = body(js,req.get("postData"))
    shape = rb'riftlet-[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}\.png'
    if text:
        for match in body_field_pattern(b"file_name",shape).finditer(js.b,*text):
            if sha(memoryview(js.b)[match.start(1):match.end(1)]) == name_hash:
                demand(key_count(js.b,text,b"file_name") == 1,"AMBIGUOUS_NEUTRAL_FILE_NAME")
                return text, match.group(1)
    return None


def linked_creation(js, rows, name_hash):
    row, (post,name) = one(((r,p) for r in rows if r[3:5] == ("POST","CREATE") and
                            (p := projected_name(js,r,name_hash))), "NEUTRAL_CREATE_COUNT")
    size = only(body_field_pattern(b"file_size",rb'\d{1,12}',False),js.b,post)
    response = body(js,js.fields(row[6]["response"],"content").get("content"))
    demand(size and response,"CREATE_SIZE_OR_RESPONSE_MISSING")
    file_id = only(body_field_pattern(b"file_id",ID_BYTES),js.b,response)
    field = one(re.compile(rb'(?<=[{,])\s*\\"upload_url\\"\s*:\s*\\"').finditer(js.b,*response), "CREATE_STORAGE_FIELD")
    locator = storage_locator(js.b,field.end(),response[1])
    demand(file_id and locator, "CREATE_ID_OR_QUERY_FREE_LOCATOR_MISSING")
    record, _ = request_record(js,row)
    record.update(requestFileNameSHA256=sha(name), requestFileNameMatchesOriginalOperation=True,
                  requestedFileSizeBytes=int(size), responseFileIDSHA256=sha(file_id), queryFreeStorageLocatorSHA256=sha(locator))
    return record, file_id, locator, name


def linked_put(js, rows, locator, size):
    related = [r for r in rows if r[3] in ("PUT","OPTIONS") and matches_locator(js,r[5]["url"],locator)]
    row = one((r for r in related if r[3] == "PUT"),"MATCHED_STORAGE_PUT_COUNT")
    record, finish = request_record(js,row)
    meta = row[6]
    length = header(js,js.fields(meta["request"],"headers")["headers"],rb'content-length',True)
    etag = header(js,js.fields(meta["response"],"headers")["headers"],rb'etag')
    demand(length == size and record["httpStatus"] == 201 and etag is True,"STORAGE_TRANSFER_NOT_SUBSTANTIATED")
    times = {k: js.number(v) for k,v in js.fields(meta["timings"],"blocked","dns","connect","send","wait","receive").items()}
    demand(all(k in times and times[k] is not None for k in ("blocked","dns","connect","send","wait","receive")),"HAR_SEND_PHASES_MISSING")
    before_send = sum(max(times[k],0) for k in ("blocked","dns","connect"))
    send_start = row[2]+timedelta(milliseconds=before_send)
    send_end = send_start+timedelta(milliseconds=times["send"])
    demand(times["send"] > 0 and times["blocked"] >= 0 and send_end <= finish,"HAR_SEND_INTERVAL_INVALID")
    accounted = before_send+times["send"]+times["wait"]+times["receive"]
    demand(abs(accounted-record["durationMS"]) < .5,"HAR_TIMING_SUM_DISAGREES")
    record.update(requestContentLengthBytes=length,responseETagPresent=True,
                  requestFileSizeEqualsContentLength=True, queryFreeStorageLocatorSHA256=sha(locator),
                  matchingOPTIONSExcluded=sum(r[3]=="OPTIONS" for r in related),
                  localHARPhaseMS={k:round(v,3) if v>=0 else None for k,v in times.items()},
                  harSendStartUTC=time_iso(send_start),harSendEndUTC=time_iso(send_end),
                  storageResult="HTTP_201_WITH_ETAG")
    return record, (row[2],finish,send_start,send_end)


def processing_events(js, response_content, file_id):
    projected = js.fields(response_content,"text","encoding")
    text = projected.get("text")
    if not text:
        return "ABSENT_FROM_HAR", [], "UNKNOWN"
    a,z = text
    if z-a == 2:
        return "PRESENT_EMPTY", [], "UNKNOWN"
    if projected.get("encoding"):
        return "ENCODED_BODY_NOT_INSPECTED", [], "UNKNOWN"
    # Frames are newline-delimited JSON. Discard frames' other fields as opaque offsets.
    records = []
    event_pattern = body_field_pattern(b"event",rb'file\.processing\.(?:started|file_ready|completed|failed)')
    ends = [(m.start(),m.end()) for m in re.compile(re.escape(b'\\n')).finditer(js.b,a+1,z-1)] + [(z-1,z-1)]
    start = a+1
    for end, following in ends:
        if start != end:
            span = (start,end)
            event = only(event_pattern,js.b,span)
            fid = only(body_field_pattern(b"file_id",ID_BYTES),js.b,span)
            progress = only(body_field_pattern(b"progress",rb'\d+(?:\.\d+)?',False),js.b,span)
            demand(fid == file_id and event and key_count(js.b,span,b"event") == key_count(js.b,span,b"file_id") == 1,
                   "UNMATCHED_OR_AMBIGUOUS_FILE_PROCESSING_FRAME")
            records.append({"event":event.decode("ascii"),"sameFileID":True,"progressPercent":float(progress) if progress else None})
        start = following
    kinds = [r["event"] for r in records]
    expected = ["file.processing.started","file.processing.file_ready","file.processing.completed"]
    result = "COMPLETED_FOR_MATCHED_FILE" if kinds == expected and records[-1]["progressPercent"] == 100 else "UNKNOWN"
    return "PRESENT_NEWLINE_DELIMITED_JSON", records, result


def linked_processing(js, rows, name, file_id):
    row, (post,process_name) = one(((r,p) for r in rows if r[3:5] == ("POST","PROCESS") and
                                    (p := projected_name(js,r,sha(name)))),"NEUTRAL_PROCESS_COUNT")
    demand(process_name == name and key_count(js.b,post,b"file_id") == 1 and only(body_field_pattern(b"file_id",ID_BYTES),js.b,post) == file_id,
           "PROCESS_FILE_ID_DIFFERS_FROM_CREATE")
    record, _ = request_record(js,row)
    state, events, result = processing_events(js,js.fields(row[6]["response"],"content").get("content"),file_id)
    record.update(requestFileIDSHA256=sha(file_id),requestFileNameSHA256=sha(name),
                  originalFileIDAndNameMatch=True,bodyState=state,matchedFileEvents=events,fileTerminalResult=result)
    return record


def clock_anchor(app_folder):
    with (app_folder/"rapid-outcome.json").open("rb") as f, mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as buf:
        js = StructuralJSON(buf)
        calls = js.fields((0,len(buf)),"dispatches")["dispatches"]
        call = js.fields(next(js.items(calls))[1],"at","monotonic")
        wall = js.string_matches(call["at"],re.compile(rb'[0-9T:.+Z-]{18,40}'))
        return datetime.fromisoformat(wall.group().decode("ascii")),js.number(call["monotonic"])


def progress_alignment(app_folder, app_audit, seed, times, anchor):
    op = FIXTURES[seed][0]
    case = one((c for c in app_audit["images"] if c["seed"] == seed),"APP_CASE")
    demand(case["operationDigest"] == op,"APP_OPERATION_ID_MISMATCH")
    relative = "raw-events.jsonl" if seed == 605 else "606-separate/raw-events.jsonl"
    data = (app_folder/relative).read_bytes()
    demand(sha(data) == app_audit["sourceSHA256"]["pr69-network-20261116/"+relative],"APP_TRACE_HASH_MISMATCH")
    rows = [r for line in data.splitlines() if (r := json.loads(line)).get("event") == "attachment_entry_result"
            and r.get("operationIDDigest") == op and r.get("assetIDDigest") == case["assetDigest"] and r.get("attempt") == 1]
    positive = [r for r in rows if r["edgeProgressValueKnown"] and 0 < r["edgeProgressPercentMinimum"] <= r["edgeProgressPercentMaximum"] < 100]
    demand(positive and all(r["edgeProgressNodes"] == 1 and r["edgeClickBound"] and r["edgeOriginalDraftCurrent"]
           and r["edgeMatchedOriginalFormNodes"] > 0 and r["edgeNewMatchedNodes"] > 0 for r in positive),"APP_PROGRESS_OR_SCOPE")
    wall,mono = anchor
    stamps = [wall+timedelta(seconds=r["uptime"]-mono) for r in positive]
    put_start,put_end,send_start,send_end = times
    def ms(a,b):
        return round((a-b).total_seconds()*1000,3)
    def point(i):
        r = positive[i]
        return dict(originalSample=r["edgeSampleNumber"],appUTCApprox=time_iso(stamps[i]),percent=r["edgeProgressPercentMaximum"],
                    sincePutStartMS=ms(stamps[i],put_start),sinceHARSendStartMS=ms(stamps[i],send_start))
    increasing = next((i for i in range(1,len(positive)) if positive[i]["edgeProgressPercentMinimum"] >
                       positive[i-1]["edgeProgressPercentMaximum"]),None)
    return {"operationDigest":op,"originalPNGBytes":app_audit["durableState"]["images"][str(seed)]["bytes"],
            "initialSamples":len(rows),"knownPositiveIntermediateSamples":len(positive),
            "withinWholePUT":sum(put_start <= s <= put_end for s in stamps),
            "withinHARSendPhase":sum(send_start <= s <= send_end for s in stamps),
            "distinctPositivePercentValues":sorted({r["edgeProgressPercentMaximum"] for r in positive}),
            "firstPositive":point(0),"firstAdjacentStrictIncrease":point(increasing) if increasing is not None else None,
            "lastPositiveInRetainedWindow":point(-1),"remainingHARSendAtLastPositiveMS":ms(send_end,stamps[-1]),
            "positiveProductSTARTRows":sum(r["startObserved"] for r in rows)}


def audit(har, app_folder, app_path):
    app_audit = json.loads(app_path.read_bytes())
    anchor = clock_anchor(app_folder)
    results = []
    with har.open("rb") as f, mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as buf:
        demand(sha(buf) == SOURCE,"HAR_SHA256_MISMATCH")
        js = StructuralJSON(buf)
        rows,n = walk_projection(js)
        for seed,(operation_hash,name_hash) in FIXTURES.items():
            subset = [r for r in rows if r[1] == seed]
            create,file_id,locator,name = linked_creation(js,subset,name_hash)
            demand(sha(name[8:-4].lower()) == operation_hash,"NEUTRAL_NAME_OPERATION_MISMATCH")
            put,times = linked_put(js,subset,locator,create["requestedFileSizeBytes"])
            process = linked_processing(js,subset,name,file_id)
            demand(create["httpStatus"] == process["httpStatus"] == 200 and
                   create["harEntryIndexZeroBased"] < put["harEntryIndexZeroBased"] < process["harEntryIndexZeroBased"], "REQUEST_CHAIN")
            alignment = progress_alignment(app_folder,app_audit,seed,times,anchor)
            results.append({"fixture":seed,"operationIDDigest":alignment["operationDigest"],"create":create,
                            "put":put,"process":process,"alignment":alignment,
                            "originalPNGMinusRequestSizeBytes":alignment["originalPNGBytes"]-create["requestedFileSizeBytes"]})
    demand(len({r["create"]["responseFileIDSHA256"] for r in results}) == 2 and
           len({r["put"]["queryFreeStorageLocatorSHA256"] for r in results}) == 2,"TWO_INDEPENDENT_DESTINATIONS")
    return {"harSHA256":SOURCE,"harEntries":n,"appAuditSHA256":sha(app_path.read_bytes()),
            "appUTCMapping":"SAME_HOST_LAUNCHER_WALL_MONOTONIC_APPROXIMATION",
            "clockBasis":"APP_SAMPLE_UPTIME_AND_HAR_UTC","bodySizeBasis":"PUT_REQUEST_CONTENT_LENGTH",
            "operations":results}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("har",type=Path)
    parser.add_argument("app_evidence",type=Path)
    parser.add_argument("--app-audit",type=Path,default=Path(__file__).with_name("pair-audit.json"))
    args = parser.parse_args()
    print(json.dumps(audit(args.har,args.app_evidence,args.app_audit),indent=2))
