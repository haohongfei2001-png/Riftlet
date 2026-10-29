#!/usr/bin/env python3
"""Offline native-first-click evidence join; never controls an app or authorizes input.

Usage: python3 timeline.py /private/path/manifest.json > /private/path/summary.json

Minimal manifest (use real collector values, never these example placeholders):
  {"version":1,"runID":"run-1","bootID":"boot-from-sysctl",
   "clock":"hostSystemUptime",
   "traces":[{"path":"app.log","sha256":"<64 hex>","runID":"run-1",
              "bootID":"boot-from-sysctl","clock":"hostSystemUptime"}],
   "trials":[{"id":"N1","scenario":"existing-chat","source":"CGEvent",
       "assetID":"<new asset UUID>","priorOperationCount":0,
       "sourceEvidence":{"token":123},
       "captureCompletion":{"kind":"unobserved"}},
     {"id":"N2","scenario":"physical","source":"physical",
       "notRunReason":"No human hardware input available"}]}

The collector must bind each immutable log to one actual process run and boot;
the manifest is an attestation of that collection, not proof generated here.
App records carry runID/clock; legacy native bridge records are bound by their
log sidecar and exact invocation IDs. T0 may be exact, interval, or unobserved;
file birthtime, copied PNG validation and ordered panels never fill missing T0.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics


CLOCK = "hostSystemUptime"
SOURCES = ("physical", "CGEvent", "AXPress", "browserSynthetic")
UNSCOPED_NATIVE = {"capture_ack", "native_bridge", "active_identity"}


class EvidenceError(ValueError):
    pass


def number(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value >= 0)


def required_text(value):
    return isinstance(value, str) and bool(value.strip())


def identity(row, request, attempt, epoch, digest=None):
    return (row.get("captureRequestID") == request
            and row.get("armAttemptID") == attempt and row.get("hostEpoch") == epoch
            and (digest is None or row.get("targetDigest") == digest))


def one(rows):
    return rows[0] if len(rows) == 1 else None


def stamp(row, field):
    value = row.get(field) if row else None
    return value if number(value) else None


def delta(later, earlier):
    return round((later - earlier) * 1000, 6) if later is not None and earlier is not None else None


def validate_session(manifest, rows):
    if (manifest.get("version") != 1 or manifest.get("clock") != CLOCK
            or not required_text(manifest.get("runID"))
            or not required_text(manifest.get("bootID"))):
        raise EvidenceError("invalid_session_manifest")
    for row in rows:
        if row.get("runID") is None and row.get("event") in UNSCOPED_NATIVE:
            if row.get("clock", CLOCK) != CLOCK:
                raise EvidenceError("mixed_or_unbound_run_clock")
            # Same-process immutable log sidecar; still joined by invocation identity.
        elif row.get("runID") != manifest["runID"] or row.get("clock") != CLOCK:
            raise EvidenceError("mixed_or_unbound_run_clock")
        if row.get("bootID", manifest["bootID"]) != manifest["bootID"]:
            raise EvidenceError("mixed_boot")


def load(manifest_path):
    manifest_path = Path(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    traces = manifest.get("traces")
    if (not isinstance(traces, list)
            or not traces and not all(t.get("notRunReason") for t in manifest.get("trials", []))):
        raise EvidenceError("missing_immutable_trace_files")
    rows = []
    hashes = []
    for trace in traces:
        if any(trace.get(key) != manifest.get(key) for key in ("runID", "bootID", "clock")):
            raise EvidenceError("trace_sidecar_session_mismatch")
        path = manifest_path.parent / trace["path"]
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != trace.get("sha256") or digest in hashes:
            raise EvidenceError("trace_hash_mismatch_or_duplicate")
        hashes.append(digest)
        for line in data.decode("utf-8").splitlines():
            if line.startswith("RIFTLET_ARRIVAL_TRACE "):
                line = line.removeprefix("RIFTLET_ARRIVAL_TRACE ")
            if not line.startswith("{"):
                continue
            row = json.loads(line)
            if isinstance(row, dict) and isinstance(row.get("event"), str):
                rows.append(row)
    validate_session(manifest, rows)
    return manifest, rows, hashes


def provenance(trial, selection, receipts, receipt_only=False):
    """No inferred hardware source from NSEvent.source == mouse."""
    source = trial["source"]
    if source == "AXPress" and not receipt_only:
        return (selection.get("source") == "accessibility", "native_accessibility_invocation")
    if source not in ("physical", "CGEvent") or (not receipt_only and selection.get("source") != "mouse"):
        return False, "not_a_native_mouse_boundary"
    if len(receipts) != 1:
        return False, "multiple_or_missing_native_presses_for_sample"
    matching = [r for r in receipts if r.get("eventUptime") == selection.get("eventUptime")
                and r.get("eventNumber") == selection.get("eventNumber")
                and r.get("windowNumber") == selection.get("windowNumber")]
    receipt = one(matching)
    if (receipt is None or receipt.get("gateAccepted") is not (not receipt_only)
            or not isinstance(selection.get("eventNumber"), int)
            or isinstance(selection.get("eventNumber"), bool)
            or not isinstance(selection.get("windowNumber"), int)
            or isinstance(selection.get("windowNumber"), bool)):
        return False, "missing_or_ambiguous_original_mouse_receipt"
    evidence = trial.get("sourceEvidence", {})
    if source == "CGEvent":
        token = evidence.get("token")
        valid = (isinstance(token, int) and not isinstance(token, bool) and token != 0
                 and selection.get("eventSourceUserData") == token
                 and receipt.get("eventSourceUserData") == token)
        return valid, "declared_CGEvent_token_join" if valid else "software_token_mismatch"
    valid = (evidence.get("method") == "humanObservedHardware"
             and required_text(evidence.get("observationReceipt"))
             and evidence.get("eventUptime") == selection.get("eventUptime")
             and selection.get("eventSourceUserData", 0) in (None, 0)
             and receipt.get("eventSourceUserData", 0) in (None, 0))
    return valid, "human_attestation_not_machine_hardware_proof" if valid else "missing_human_observation"


def ack_proof(selection, rows):
    request, attempt, epoch, digest = (selection.get(k) for k in
        ("effectiveCaptureRequestID", "effectiveArmAttemptID", "hostEpoch", "targetDigest"))
    result = {"status": "NOT_PROVEN", "missing": [], "ackMarginMS": None}
    if not all(required_text(x) for x in (request, attempt, epoch, digest)):
        result["missing"].append("click_effective_ack_identity")
        return result, {}
    joined = [r for r in rows if identity(r, request, attempt, epoch, digest)]
    publish = one([r for r in joined if r.get("event") == "arm_completion"
                   and r.get("publicationResult") == "publishedNewTarget"])
    native = one([r for r in joined if r.get("event") == "capture_ack"
                  and r.get("phase") == "native_validated"])
    bridge = one([r for r in rows if identity(r, request, attempt, epoch)
                  and r.get("event") == "native_bridge" and r.get("action") == "captureTarget"
                  and r.get("phase") == "complete"])
    start = one([r for r in rows if identity(r, request, attempt, epoch)
                 and r.get("event") == "arm_attempt_started"])
    if publish is None:
        result["missing"].append("unique_original_app_publication")
    if native is None:
        result["missing"].append("unique_original_native_validation")
    if bridge is None:
        result["missing"].append("unique_original_capture_bridge")
    if start is None:
        result["missing"].append("unique_original_prebind_start")
    if result["missing"]:
        return result, {}
    times = {"prebindStarted": stamp(start, "uptime"),
             "bridgeQueued": stamp(bridge, "queuedUptime"),
             "bridgeStarted": stamp(bridge, "startedUptime"),
             "pageReceiptAtNative": stamp(native, "nativeReceivedUptime"),
             "nativeValidated": stamp(native, "nativeValidatedUptime"),
             "bridgeReturned": stamp(bridge, "endedUptime"),
             "adapterValidated": stamp(publish, "adapterValidatedUptime"),
             "effectiveAppACK": stamp(publish, "effectiveAckUptime"),
             "appPublicationObserved": stamp(publish, "mainPublishedUptime")}
    click = stamp(selection, "originalEventUptime")
    result["ackMarginMS"] = delta(click, times["effectiveAppACK"])
    guards = (native.get("accepted") is True and native.get("requestID") == request
              and bridge.get("requestID") == request and bridge.get("transportSucceeded") is True
              and publish.get("armed") is True
              and publish.get("epochAccepted") is True and publish.get("captureAttempted") is True
              and publish.get("error") == "none" and publish.get("reusedExistingArmedTarget") is False
              and publish.get("effectiveCaptureRequestID") == request
              and publish.get("effectiveArmAttemptID") == attempt
              and selection.get("frozen") is True and selection.get("freezeResult") == "accepted"
              and selection.get("hostEpochMatches") is True and selection.get("foregroundSessionMatches") is True)
    ordered = (all(t is not None for t in times.values()) and click is not None
               and list(times.values()) == sorted(times.values())
               and times["prebindStarted"] == stamp(publish, "startedUptime")
               and times["effectiveAppACK"] == stamp(selection, "ackUptime")
               and times["effectiveAppACK"] < click
               and selection.get("eventUptime") == click
               and stamp(selection, "callbackUptime") is not None
               and click <= selection["callbackUptime"])
    if not guards:
        result["missing"].append("original_publication_or_click_guard")
    if not ordered:
        result["missing"].append("original_finite_causal_timestamps")
    result["status"] = "PASS" if guards and ordered else "NOT_PROVEN"
    result["publicationObservationBeforeClick"] = (
        times["appPublicationObserved"] < click
        if times["appPublicationObserved"] is not None and click is not None else None)
    result["scope"] = "original effective ACK; publication observation is separately timed"
    return result, times


def pending_observation(selection, rows):
    """Explain an in-flight capture; it can NEVER become click authorization."""
    req, attempt, epoch = (selection.get(k) for k in
        ("inFlightCaptureRequestID", "inFlightArmAttemptID", "hostEpoch"))
    if not all(required_text(v) for v in (req, attempt, epoch)):
        return None
    joined = [r for r in rows if identity(r, req, attempt, epoch)]
    native = one([r for r in joined if r.get("event") == "capture_ack"
                  and r.get("phase") == "native_validated" and r.get("accepted") is True])
    publish = one([r for r in joined if r.get("event") == "arm_completion"
                   and r.get("publicationResult") == "publishedNewTarget"])
    start = one([r for r in joined if r.get("event") == "arm_attempt_started"])
    click = stamp(selection, "originalEventUptime")
    consistent = not (native and publish) or native.get("targetDigest") == publish.get("targetDigest")
    return {"authorizesOriginalClick": False, "targetDigestConsistent": consistent,
            "prebindStartedOffsetMS": delta(stamp(start, "uptime"), click),
            "nativeReceiptOffsetMS": delta(stamp(native, "nativeReceivedUptime"), click),
            "nativeValidationOffsetMS": delta(stamp(native, "nativeValidatedUptime"), click),
            "appACKOffsetMS": delta(stamp(publish, "effectiveAckUptime"), click) if consistent else None}


def capture_completion(trial):
    item = trial.get("captureCompletion", {"kind": "unobserved"})
    kind = item.get("kind")
    if kind == "exact" and number(item.get("uptime")) and required_text(item.get("evidence")):
        return {"status": "EXACT_ATTESTED", "uptime": item["uptime"], "notDerivedFromFile": True}
    if (kind == "interval" and number(item.get("lowerUptime")) and number(item.get("upperUptime"))
            and item["lowerUptime"] <= item["upperUptime"] and required_text(item.get("evidence"))):
        return {"status": "INTERVAL_ATTESTED", "lowerUptime": item["lowerUptime"],
                "upperUptime": item["upperUptime"], "notAnExactT0": True}
    return {"status": "NOT_MEASURED"}


def capture_chain(times, completion):
    """Validate observed partial orders independently of target/ACK authority.

    The importer stamps *after* awaiting the database insert, while another Main
    refresh can already read that asset and render it. Therefore importer-return
    and Main-delivery stamps have no guaranteed order against window observation.
    The original NSEvent timestamp is independent: it may precede the post-order
    observation or a CGEvent may have been created before it was posted. Never
    turn those signed offsets into capture latency or an inconsistent capture.
    """
    importer = ["firstCandidateObserved", "sourceValidatedCopyUpperBound", "durableCommit",
                "importObserverReady", "mainCaptureCallback"]
    presentation = ["sourceValidatedCopyUpperBound", "inputWindowsOrdered", "imageDelivered"]
    invalid = set()
    for branch in (importer, presentation):
        known = [key for key in branch if times.get(key) is not None]
        for earlier, later in zip(known, known[1:]):
            if times[earlier] > times[later]:
                invalid.add((earlier, later))
    copy = times.get("sourceValidatedCopyUpperBound")
    kind = completion["status"]
    if kind == "NOT_MEASURED":
        completion["temporalCheck"] = "NOT_CHECKED_UNOBSERVED_T0"
    elif copy is None:
        completion["temporalCheck"] = "NOT_CHECKED_NO_VALIDATED_COPY"
    elif kind == "EXACT_ATTESTED":
        if completion["uptime"] > copy:
            invalid.add(("exactSystemCaptureCompletion", "sourceValidatedCopyUpperBound"))
            completion["temporalCheck"] = "CONTRADICTS_VALIDATED_COPY"
        else:
            completion["temporalCheck"] = "PRECEDES_VALIDATED_COPY"
    elif completion["lowerUptime"] > copy:
        invalid.add(("systemCaptureCompletionLowerBound", "sourceValidatedCopyUpperBound"))
        completion["temporalCheck"] = "CONTRADICTS_VALIDATED_COPY"
    elif completion["upperUptime"] > copy:
        # The interval may contain a valid T0. Do not invent a narrower interval.
        completion["temporalCheck"] = "OVERLAPS_VALIDATED_COPY_BOUND"
    else:
        completion["temporalCheck"] = "BOUNDS_PRECEDE_VALIDATED_COPY"
    # Either endpoint of an inversion may be wrong. Exclude any metric using
    # those stages or crossing them, rather than guessing which timestamp to fix.
    suspect = {key for pair in invalid for key in pair}
    metrics = {"sourceValidatedToWindowObservation": presentation[:2],
               "sourceValidatedToImageDelivery": presentation,
               "importReadyToMainCallback": ["importObserverReady", "mainCaptureCallback"]}
    durations = {name: (None if suspect.intersection(stages) else
                       delta(times.get(stages[-1]), times.get(stages[0])))
                 for name, stages in metrics.items()}
    complete = (all(times.get(key) is not None for key in importer + presentation + ["originalClick"])
                and kind == "EXACT_ATTESTED")
    status = "INCONSISTENT" if invalid else "CONSISTENT_OBSERVATIONS" if complete else "PARTIAL"
    return status, [f"{earlier}>{later}" for earlier, later in sorted(invalid)], durations


def trial_summary(trial, rows):
    result = {"id": trial["id"], "scenario": trial["scenario"], "source": trial["source"],
              "attachmentSuccess": "NOT_VERIFIED", "hardwareDeviceProvenByTrace": False}
    if trial.get("notRunReason"):
        return result | {"status": "NOT_RUN", "reason": trial["notRunReason"]}
    if (not required_text(trial.get("assetID")) or type(trial.get("priorOperationCount")) is not int
            or trial["priorOperationCount"] != 0):
        return result | {"status": "NOT_EVALUABLE", "reason": "new_independent_sample_not_attested"}
    selected = [r for r in rows if r.get("event") == "selection_boundary"
                and r.get("assetID") == trial["assetID"]]
    asset_rows = [r for r in rows if r.get("assetID") == trial["assetID"]]
    receipts = [r for r in asset_rows if r.get("event") == "native_input_receipt"]
    receipt = one(receipts)
    receipt_only = not selected and receipt is not None and receipt.get("gateAccepted") is False
    selection = one(selected) if not receipt_only else receipt
    if selection is None:
        return result | {"status": "NOT_EVALUABLE", "reason": "missing_or_multiple_original_selections",
                         "selectionCount": len(selected)}
    source_ok, source_reason = provenance(trial, selection, receipts, receipt_only)
    result["sourceEvidence"] = {"qualified": source_ok, "basis": source_reason}
    ack, times = ack_proof(selection, rows)
    times["originalClick"] = stamp(selection, "eventUptime" if receipt_only else "originalEventUptime")
    result["clickBoundaryKind"] = "native_gate_refusal_only" if receipt_only else "selection_boundary"
    source = one([r for r in asset_rows if r.get("event") == "capture_source_verified"])
    durable = one([r for r in asset_rows if r.get("event") == "capture_durable_delivery"])
    times.update({"firstCandidateObserved": stamp(source, "firstObservedUptime"),
                  "sourceValidatedCopyUpperBound": stamp(source, "validatedCopyUptime"),
                  "durableCommit": stamp(source, "durableCommitUptime"),
                  "importObserverReady": stamp(durable, "readyUptime"),
                  "mainCaptureCallback": stamp(durable, "callbackUptime")})
    result["appKitWindowObservations"] = {}
    for phase, key in (("initialOrder", "inputWindowsOrdered"), ("imageDelivery", "imageDelivered")):
        observation = one([r for r in asset_rows if r.get("event") == "input_windows_observed"
                           and r.get("phase") == phase])
        times[key] = stamp(observation, "uptime")
        if observation:
            result["appKitWindowObservations"][phase] = {key: observation.get(key) for key in
                ("windowsVisible", "ignoresMouseEvents", "selectionStateEligible", "imageDecoded")}
            result["appKitWindowObservations"][phase]["selectedWindowMatchesInputPair"] = (
                selection.get("windowNumber") in (observation.get("imageWindow"), observation.get("numberWindow"))
                if selection.get("windowNumber") is not None else None)
    result["captureCompletion"] = capture_completion(trial)
    result["ackEvidence"] = ack
    result["pendingCaptureDiagnostic"] = pending_observation(selection, rows)
    result["refusalReason"] = ("nativeGateRefused" if receipt_only else
                                selection.get("refusalReason") if selection.get("frozen") is not True else None)
    result["times"] = times
    result["captureChainStatus"], result["invalidStages"], result["latencyMS"] = capture_chain(
        times, result["captureCompletion"])
    offset_baselines = {"fromSourceValidatedCopy": "sourceValidatedCopyUpperBound",
                        "fromInputWindowObservation": "inputWindowsOrdered"}
    result["originalEventOffsetsMS"] = {name: delta(times["originalClick"], times.get(key))
                                         for name, key in offset_baselines.items()}
    suspect = {key for pair in result["invalidStages"] for key in pair.split(">")}
    result["invalidEventOffsetBaselines"] = [name for name, key in offset_baselines.items() if key in suspect]
    result["originalEventOffsetsAreLatencies"] = False
    result["missingStages"] = [key for key, value in times.items() if value is None]
    if result["captureCompletion"]["status"] != "EXACT_ATTESTED":
        result["missingStages"].append("exactSystemCaptureCompletion")
    result["missingStages"].extend(["firstWindowServerHitAvailability", "firstPixelPresentation"])
    result["status"] = ("NOT_EVALUABLE" if not source_ok else
                        "ACK_BEFORE_CLICK_PROVEN" if ack["status"] == "PASS" else
                        "REFUSED" if receipt_only or selection.get("frozen") is False and selection.get("freezeResult") == "refused"
                        else "ACK_NOT_PROVEN")
    return result


def analyze(manifest, rows):
    validate_session(manifest, rows)
    trials = manifest.get("trials")
    if not isinstance(trials, list):
        raise EvidenceError("missing_trials")
    ids, assets = set(), set()
    for trial in trials:
        if (not required_text(trial.get("id")) or trial["id"] in ids
                or not required_text(trial.get("scenario")) or trial.get("source") not in SOURCES):
            raise EvidenceError("invalid_or_duplicate_trial")
        ids.add(trial["id"])
        if not trial.get("notRunReason"):
            if trial.get("assetID") in assets:
                raise EvidenceError("reused_trial_asset")
            assets.add(trial.get("assetID"))
    results = [trial_summary(trial, rows) for trial in trials]
    groups = {}
    for source in SOURCES:
        group = [r for r in results if r["source"] == source]
        attempted = [r for r in group if r["status"] not in ("NOT_RUN", "NOT_EVALUABLE")]
        passed = [r for r in attempted if r["status"] == "ACK_BEFORE_CLICK_PROVEN"]
        margins = [r["ackEvidence"]["ackMarginMS"] for r in passed]
        durations = {}
        for name in ("sourceValidatedToWindowObservation", "sourceValidatedToImageDelivery", "importReadyToMainCallback"):
            values = [r["latencyMS"][name] for r in attempted if r["latencyMS"][name] is not None]
            durations[name] = {"count": len(values), "min": min(values), "median": statistics.median(values),
                               "max": max(values)} if values else None
        offsets = {}
        for name in ("fromSourceValidatedCopy", "fromInputWindowObservation"):
            values = [r["originalEventOffsetsMS"][name] for r in attempted
                      if r["originalEventOffsetsMS"][name] is not None
                      and name not in r["invalidEventOffsetBaselines"]]
            offsets[name] = {"count": len(values), "min": min(values), "median": statistics.median(values),
                             "max": max(values)} if values else None
        groups[source] = {"qualifiedNativeTrials": len(attempted), "preClickACKProven": len(passed),
            "preClickACKRate": len(passed) / len(attempted) if attempted else None,
            "status": "OBSERVED_LIMITED_SAMPLE" if attempted else "NOT_RUN",
            "excludedUnqualified": sum(r["status"] == "NOT_EVALUABLE" for r in group),
            "ackMarginMS": {"min": min(margins), "median": statistics.median(margins),
                            "max": max(margins)} if margins else None,
            "latencyDistributionMS": durations,
            "originalEventOffsetDistributionMS": offsets,
            "attachmentSuccessRate": None}
    return {"version": 1, "scope": "native timing evidence only; no input or upload admission",
            "clock": CLOCK, "traceRecordCount": len(rows), "trials": results, "bySource": groups,
            "timeSemantics": {"durableCommit": "post-await import return observation, not transaction commit instant",
                "inputWindowsOrdered": "post-order AppKit observation, not first WindowServer hit availability",
                "originalEventOffsetsMS": "signed original-event timestamp offsets; not capture or upload latency"},
            "completeNaturalPhysicalAcceptance": "NOT_ESTABLISHED"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest")
    args = parser.parse_args()
    try:
        manifest, rows, hashes = load(args.manifest)
        output = analyze(manifest, rows)
        output["traceSHA256"] = hashes
        print(json.dumps(output, indent=2, sort_keys=True, allow_nan=False))
    except (EvidenceError, OSError, ValueError, KeyError, TypeError) as error:
        # Avoid printing local paths or arbitrary malformed private log content.
        code = str(error) if isinstance(error, EvidenceError) else type(error).__name__
        print(json.dumps({"status": "INVALID_EVIDENCE", "reason": code}))
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
