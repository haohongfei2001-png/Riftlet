"""Recover a build 59 pair's timing from hash-pinned, read-only acceptance receipts.

Usage: python3 rapid_timing.py <published-series.json> <private-series-dir> <second-index>
Host times are relative to the first AppKit event. Browser times use the same
original document's performance.now() and are deliberately kept on that clock.
"""
import argparse
import hashlib
import json
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def one(records, **fields):
    matches = [r for r in records if all(r.get(k) == v for k, v in fields.items())]
    require(len(matches) == 1, f"Expected one {tuple(fields)} match, got {len(matches)}")
    return matches[0]


def digest(identifier):
    return hashlib.sha256(identifier.lower().encode("ascii")).hexdigest()


def analyze(manifest, directory, last_index):
    def raw(filename):
        local_name = "candidate.stderr" if filename == "signed-app.stderr" else filename
        data = (directory / local_name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == manifest["originalRawSHA256"][filename],
                f"Receipt digest mismatch for {filename}")
        return data

    def read(filename):
        return json.loads(raw(filename))

    child = read("child.json")
    require(child["candidate"]["sha256"] == manifest["dmgSHA256"] and
            child["candidate"]["source"] == manifest["productCommit"], "Wrong candidate")
    trace = [json.loads(line) for line in raw("signed-app.stderr").splitlines()
             if line.startswith(b"{")]
    pair = read(f"positive-{last_index}.json")
    require([item["index"] for item in pair] == [last_index - 1, last_index], "Expected a full pair")
    page = read(f"page-after-{last_index}.json")
    require(page["originalDocument"] and page["originalEditor"] and page["rememberedCards"] > 0 and
            page["allRememberedCardsPresent"] and page["previousQAImagesPresent"] and
            page["counts"]["sendButtonClicks"] == page["counts"]["formSubmit"] == 0,
            "Missing original draft or existing attachments, or unexpected send")
    baseline = pair[0]["downUptime"]

    def ms(uptime):
        return round((uptime - baseline) * 1000, 3)

    operations = read(f"db-{last_index}.json")["operations"]
    events = []
    draft = None
    for key in ("sha256", "operationID", "invocationID", "evidenceID", "cardID", "eventNumber"):
        require(pair[0][key] != pair[1][key], f"Reused {key}")
    for item in pair:
        index = item["index"]
        row = read(f"row-{index}.json")
        click = read(f"click-{index}.json")
        op = one(operations, id=item["operationID"], invocationID=item["invocationID"],
                 assetID=row["assetID"], uniqueStartEvidence=item["evidenceID"],
                 startMatchesOriginal=True, startSignal="attachmentAccepted", startCount=1,
                 currentAttachmentID=item["cardID"])
        current_draft = tuple(op[k] for k in ("originalDocumentID", "originalComposerID", "originalDraftGeneration"))
        require(all(current_draft) and (draft is None or current_draft == draft), "Changed original draft")
        draft = current_draft
        require(click["profile"] == row["profile"] and click["pid"] == row["pid"] and
                click["kernelCandidateIdentity"] == row["kernelCandidateIdentity"] and
                click["eventNumber"] == item["eventNumber"] and click["eventUptime"] == item["downUptime"],
                "Candidate process or AppKit receipt changed")
        require(row["state"] == "VERIFIED_READ_ONLY" and row["eventsPosted"] == 0 and
                row["sampleCount"] == 9 and row["maxReferenceRGBDifference"] <= 18 and
                row["readOnlyPacketRoundtrip"] == "VERIFIED" and row["sha256"] == item["sha256"] and
                row["profile"] == child["profile"] and row["pid"] == child["pid"] and
                click["assetID"] == row["assetID"] and click["delivery"] == "MOUSE_DOWN_ACKNOWLEDGED",
                "Missing original tray row or press")
        aid, oid = digest(row["assetID"]), digest(op["id"])
        mouse = one(trace, event="selection_boundary", source="mouse", assetIDDigest=aid,
                    eventNumber=item["eventNumber"], eventUptime=item["downUptime"])
        host_start = one(trace, event="attachment_entry_result", operationIDDigest=oid,
                         phase="uploadStarted", startObserved=True)["uptime"]
        handed_off = one(trace, event="attachment_entry_result", operationIDDigest=oid,
                         phase="inputTriggered", setterEntered=True, changeReturned=True)["uptime"]
        consumed = one(trace, event="preclick_lease", phase="consumed", operationIDDigest=oid,
                       requestIDDigest=item["requestDigest"])["uptime"]
        # The native commit is serialized. A lost reply, competing commit, or
        # observation-only action cannot supply an exact renderer setter time.
        commits = [e for e in trace if e.get("event") == "native_bridge" and
                   e.get("action") == "commit" and e.get("transportSucceeded") and
                   consumed <= e["startedUptime"] <= e["endedUptime"] <= handed_off]
        require(len(commits) == 1, "Ambiguous native commit interval")
        commit = commits[0]
        inputs = [r for r in page["observedInputReceipts"]
                  if r["knownQAFileName"].lower() == item["inputName"].lower()]
        require([r["event"] for r in inputs] == ["input", "change"] and
                all(r["sha256"] == item["sha256"] and r["sameInputAsOriginal"] for r in inputs),
                "Missing exact original input/change")
        animation = [one(trace, event="presentation_boundary", phase=phase,
                         assetIDDigest=aid, operationIDDigest=oid)["uptime"]
                     for phase in ("swallowActualStart", "swallowClose")]
        events.append({
            "index": index, "operationID": op["id"], "priorVerifiedRowMS": ms(row["sampleUptime"]),
            "preclickAcknowledgedMS": ms(item["ackUptime"]), "mouseDownMS": ms(mouse["eventUptime"]),
            "appKitCallbackMS": ms(mouse["callbackUptime"]), "leaseConsumedMS": ms(consumed),
            "nativeCommitCallIntervalMS": [ms(commit[k]) for k in ("startedUptime", "endedUptime")],
            "setterEnteredAndChangeReturnedHostReceiptMS": ms(handed_off),
            "browserInputMS": inputs[0]["atMS"], "browserChangeMS": inputs[1]["atMS"],
            "attachmentAcceptedHostReceiptMS": ms(host_start),
            "swallowStartMS": ms(animation[0]), "swallowCloseMS": ms(animation[1]),
            "qaLastPreDispatchRowSampleMS": (ms(click["sampleUptime"])
                if click.get("transport") == "two-process-window-local-v1" else None),
            "qaFinalCheckElapsedMS": (round(click["finalCheckMS"], 3)
                if "finalCheckMS" in click else None)
        })
    delta_ms = (pair[1]["downUptime"] - baseline) * 1000
    return {"family": manifest["family"], "dmgSHA256": manifest["dmgSHA256"],
            "oldCardsPreserved": page["rememberedCards"], "events": events,
            "downDeltaMS": round(delta_ms, 3), "strictlyUnderTwoSeconds": 0 < delta_ms < 2000}


if __name__ == "__main__":
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("manifest", type=Path)
    args.add_argument("receipts", type=Path)
    args.add_argument("last_index", type=int)
    parsed = args.parse_args()
    print(json.dumps(analyze(json.loads(parsed.manifest.read_bytes()), parsed.receipts, parsed.last_index),
                     indent=2, allow_nan=False))
