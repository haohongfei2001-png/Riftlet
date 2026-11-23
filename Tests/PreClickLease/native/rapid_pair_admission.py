"""Read-only checks shared by a private pair sender and its post-run audit.

The native coordinator provides fresh observations from its already authorized
route. Nothing here discovers a browser, prepares a lease, or posts input.
"""
import hashlib
import math
import re

HEX = re.compile(r"[a-f0-9]{64}")
ROUTE = ("applicationID", "sessionID", "windowID", "tabID")
DRAFT = ("documentID", "composerID", "draftGeneration")


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def digest(identifier):
    return hashlib.sha256(identifier.lower().encode("utf8")).hexdigest()


def current_window(created, previous_windows, scope):
    """Call after creation. Unrelated additions/removals have no bearing on ownership."""
    observed = scope.get("currentWindowIDs")
    wid, tid = created["windowID"], created["tabID"]
    require(created["phase"] == "qaAddressConfirmed" and wid not in previous_windows
            and str(wid).isdecimal() and str(tid).isdecimal(), "unproven new QA window")
    require(all(created[k] == scope[k] for k in ("pid", "sessionID", "windowID", "tabID", "family"))
            and scope["dynamicSignature"] is True and scope["systemForeground"] is True
            and scope["exactTemporaryURL"] is True and scope["originalSelection"] is True
            and scope["originalSoleTab"] is True
            and (observed is None or observed.count(wid) == 1 and len(observed) == len(set(observed)))
            and ("selectedWindowID" not in scope or scope["selectedWindowID"] == wid)
            and ("selectedTabID" not in scope or scope["selectedTabID"] == tid)
            and ("originalTabIDs" not in scope or scope["originalTabIDs"] == [tid]),
            "original QA route or sole selected tab changed")


def admit_pair(rows, readback, trace, now):
    """readback captures the two retained targets together from one original draft.

    rows are the two frozen sender's previously pixel-checked tray row receipts,
    augmented with the SHA-256 of the decoded original pixels. Call only for the
    original private signed App and after current_window and page authorization.
    """
    require(len(rows) == 2 and len({r["assetID"] for r in rows}) == 2 and
            len({r["sha256"] for r in rows}) == 2 and len({r["pixelsSHA256"] for r in rows}) == 2,
            "expected two distinct source images")
    require(len({r[k] for r in rows for k in ("inputWindowID", "visualWindowID")}) == 4 and
            all(r["state"] == "VERIFIED_READ_ONLY" and r["sampleCount"] == 9 and
                r["maxReferenceRGBDifference"] <= 18 and r["readOnlyPacketRoundtrip"] == "VERIFIED"
                and HEX.fullmatch(r["sha256"]) and HEX.fullmatch(r["pixelsSHA256"]) for r in rows) and
            all(rows[0][k] == rows[1][k] for k in ("profile", "pid", "kernelCandidateIdentity")),
            "unverified source row identity")
    sample = readback["sampleUptime"]
    require(math.isfinite(now) and math.isfinite(sample) and 0 <= now - sample <= 1,
            "stale monotonic target sample")
    targets = readback["retainedTargets"]
    wanted = (readback["route"], readback["draft"])
    require(len(targets) == 2 and all(wanted[0].get(k) for k in ROUTE) and
            all(wanted[1].get(k) for k in DRAFT) and
            all(all(t.get(k) == wanted[j][k] for k in fields)
                for t in targets for j, fields in enumerate([ROUTE, DRAFT])),
            "both original retained targets must match the same native draft")
    bindings = []
    host_epochs = set()
    for target in targets:
        key = target["bindingDigest"]
        require(HEX.fullmatch(key) and target["unenrolled"] is True and target["originalStillValid"] is True,
                "invalid or enrolled original binding")
        lifecycle = [e for e in trace if e.get("event") == "preclick_lease" and e.get("requestIDDigest") == key]
        armed = [e for e in lifecycle if e.get("phase") == "armed"]
        require(len(armed) == 1 and all(e.get("phase") == "armed" for e in lifecycle),
                "missing unique unspent signed-App acknowledgement")
        ack = armed[0]["acknowledgedUptime"]
        require(math.isfinite(ack) and 0 <= ack <= sample and HEX.fullmatch(armed[0]["hostEpochDigest"]),
                "wrong original acknowledgement clock or epoch")
        bindings.append({"bindingDigest": key, "acknowledgedUptime": ack})
        host_epochs.add(armed[0]["hostEpochDigest"])
    require(len({b["bindingDigest"] for b in bindings}) == 2 and len(host_epochs) == 1,
            "duplicate binding or mixed host epoch")
    return {"sampleUptime":sample, "hostEpochDigest":host_epochs.pop(), "bindings":bindings,
            "route":dict(wanted[0]), "draft":dict(wanted[1]),
            "images":[{k:r[k] for k in ("assetID","sha256","pixelsSHA256","inputWindowID","visualWindowID")}
                      for r in rows]}


def confirm_pair(evidence, operations, positive, trace):
    require(len(positive) == len(operations) == 2, "missing pair operations")
    acks = {b["bindingDigest"]:b["acknowledgedUptime"] for b in evidence["bindings"]}
    require({r["requestDigest"] for r in positive} == set(acks), "pre-press bindings changed")
    first = positive[0]["downUptime"]
    require(evidence["sampleUptime"] <= first and max(acks.values()) < first, "late pair proof")
    require(positive[1]["downUptime"] > first, "non-increasing press clock")
    for k in ("operationID","invocationID","evidenceID","cardID","eventNumber"):
        require(positive[0][k] != positive[1][k], "duplicate original operation evidence")
    for image, receipt, op in zip(evidence["images"], positive, operations):
        key = receipt["requestDigest"]
        require(op["id"] == receipt["operationID"] and op["assetID"] == image["assetID"]
                and op["invocationID"] == receipt["invocationID"] and op["startMatchesOriginal"] is True
                and op["startSignal"] == "attachmentAccepted" and op["startCount"] == 1
                and op["uniqueStartEvidence"] == receipt["evidenceID"] and op["currentAttachmentID"] == receipt["cardID"]
                and image["sha256"] == receipt["sha256"] and acks[key] == receipt["ackUptime"]
                and tuple(op[k] for k in ("originalDocumentID","originalComposerID","originalDraftGeneration"))
                    == tuple(evidence["draft"][k] for k in DRAFT), "wrong original input, draft or START")
        lifecycle = [e for e in trace if e.get("event") == "preclick_lease" and e.get("requestIDDigest") == key]
        frozen = [e for e in lifecycle if e.get("phase") == "frozen"]
        consumed = [e for e in lifecycle if e.get("phase") == "consumed"]
        require(len(frozen) == len(consumed) == 1 and frozen[0]["hostEpochDigest"] == evidence["hostEpochDigest"]
                and frozen[0]["originalEventUptime"] == receipt["downUptime"]
                and frozen[0]["acknowledgedUptime"] == acks[key]
                and consumed[0]["operationIDDigest"] == digest(op["id"])
                and digest(op["clickBindingID"]) == key,
                "binding and original operation evidence do not join")
    elapsed = (positive[1]["downUptime"] - first) * 1000
    return {"originalMouseDownDeltaMS":elapsed, "strictlyUnderTwoSeconds":elapsed < 2000}


def run_pair(batch, output, read_witness, scoped_sender, settle, load_trace, uptime, save, wait):
    """Execute one already authorized pair through the existing sender and no-replay journal.

    read_witness receives no browser selector. The caller captures the current
    original route, retained bindings and native sample uptime together.
    scoped_sender retains its per-press native route, SHA, pixel and hit checks.
    settle returns the two original operations and original verified receipts.
    """
    import json
    require(len(batch) == 2 and batch[1][0] == batch[0][0] + 1, "expected two adjacent indices")
    rows = []
    for index, sha in batch:
        row = json.loads((output / f"row-{index}.json").read_bytes())
        pixels = json.loads((output / f"source-pixels-{index}.json").read_bytes())
        require(row["sha256"] == pixels["sha256"] == sha and pixels["uniqueAgainstPriorSources"] is True,
                "wrong original source image")
        rows.append({**row, "pixelsSHA256": pixels["rgbaSHA256"]})
    preparation_started = uptime()
    until = preparation_started + 8
    while True:
        state = read_witness()
        current_window(state["creation"], state["previousWindows"], state["scope"])
        # Only a positive, currently scoped observation of fewer than two
        # retained bindings can wait for the already-running product preparation.
        # A missing receipt or target change is an immediate terminal refusal.
        scope = state["scope"]
        require(scope["sessionID"] == state["route"]["sessionID"] and scope["windowID"] == state["route"]["windowID"]
                and scope["tabID"] == state["route"]["tabID"] and scope["bundle"] == state["route"]["applicationID"],
                "different observed native route")
        if len(state["retainedTargets"]) >= 2 or uptime() >= until:
            break
        wait(.05)
    admission = admit_pair(rows, state, load_trace(), uptime())
    admission["sourceReceiptSHA256"] = state.get("sourceReceiptSHA256")
    admission["verifierPreparationStartedUptime"] = preparation_started
    admission["verifierPreparationFinishedUptime"] = uptime()
    admission["rowVerifiedUptimes"] = [r["sampleUptime"] for r in rows]
    save(f"preclick-pair-{batch[0][0]}.json", admission)
    sender_started = uptime()
    try:
        scoped_sender(batch)
    finally:
        save(f"sender-elapsed-{batch[0][0]}.json", {"enteredUptime":sender_started, "returnedUptime":uptime()})
    operations, positive = settle(batch)
    result = confirm_pair(admission, operations, positive, load_trace())
    save(f"confirmed-pair-{batch[0][0]}.json", result)
    return result

def observation(envelope, created, before, expected_route):
    """Decode privately supplied readback bytes; procuring this receipt belongs to the caller."""
    import base64
    import json
    data = base64.b64decode(envelope["payloadBase64"], validate=True)
    require(hashlib.sha256(data).hexdigest() == envelope["sha256"] and
            json.loads(data) == envelope["payload"], "invalid original observer receipt")
    payload = envelope["payload"]
    current_window(created, before["windowIDs"], payload)
    require(before["sessionID"] == created["sessionID"] and before["pid"] == created["pid"] and
            before["dynamicSignature"] is True and before["bundle"] == payload["bundle"],
            "original browser identity changed")
    route = {"applicationID":payload["bundle"], **{k:payload[k] for k in ROUTE[1:]}}
    require(route == expected_route, "native observer and candidate route differ")
    page = payload["page"]
    require(all(page.get(k) is True for k in ("editor", "uploadEntry", "signedIn")), "original authenticated composer unavailable")
    pins = page["preparedBindingSHA256"]
    require(isinstance(pins,list) and all(isinstance(k,str) and HEX.fullmatch(k) for k in pins)
            and len(set(pins)) == len(pins), "duplicate or invalid prepared binding")
    draft = {"documentID":page.get("documentID"), "composerID":page.get("composerID"),
             "draftGeneration":page.get("draftEpoch")}
    if pins:
        require(all(isinstance(v,str) and v for v in draft.values()), "missing retained original draft identity")
    # These booleans are the definition of the observer's filtered set:
    # only currently retained, original, unenrolled page bindings are reported.
    targets = [dict(route, **draft, bindingDigest=k, unenrolled=True, originalStillValid=True) for k in pins]
    return {"scope":payload, "creation":created, "previousWindows":before["windowIDs"],
            "sampleUptime":payload["systemUptime"], "retainedTargets":targets,
            "draft":draft, "route":route, "sourceReceiptSHA256":envelope["sha256"]}
