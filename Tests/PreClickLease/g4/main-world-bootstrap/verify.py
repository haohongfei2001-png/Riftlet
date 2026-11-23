#!/usr/bin/env python3
"""Check a redacted native-bootstrap receipt offline. No browser or network access."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys


STAGES = {
    "before": {"route": "hash", "document": "hash", "markerAbsent": "bool"},
    "set": {"route": "hash", "osStatus": "os-status", "challenge": "hash"},
    "effect": {"document": "hash", "challenge": "hash", "via": "effect-source"},
    "isolated": {"document": "hash", "sharedChallenge": "hash", "globalVisible": "bool",
                 "xhrVisible": "bool", "contextVerified": "bool"},
    "main": {"document": "hash", "globalChallenge": "hash", "xhrChallenge": "hash",
             "unopened": "bool", "contextVerified": "bool"},
    "cleanup": {"document": "hash", "globalAbsent": "bool", "xhrAbsent": "bool",
                "sharedMarkerAbsent": "bool", "mainContextVerified": "bool"},
    "after": {"route": "hash", "document": "hash"},
}
STAGE_NAMES = {*STAGES, "network"}
HASH = re.compile(r"[0-9a-f]{64}")
LIMIT = 32768
LOCAL_PAGE = {
    "fileScheme": "bool", "fixedFixtureSHA256": "hash", "fixtureHashMatched": "bool",
    "policyActiveFromPreparationThroughCleanup": "bool", "connectionAndWorkerSourcesDenied": "bool",
    "remoteSubresourcesAndFormDenied": "bool", "continuousCountersOnOriginalDocument": "bool",
    "counterOverflowOrLoss": "bool",
}


class InvalidReceipt(ValueError):
    """Messages describe schema paths and never echo untrusted values."""


def fields(value, required, path, optional=()):
    if type(value) is not dict or not set(required) <= value.keys():
        raise InvalidReceipt(f"{path}: missing required fields or invalid object")
    if value.keys() - set(required) - set(optional):
        raise InvalidReceipt(f"{path}: unexpected field")


def valid_scalar(value, kind):
    if kind == "hash":
        return type(value) is str and HASH.fullmatch(value) is not None
    if kind == "bool":
        return type(value) is bool
    if kind == "os-status":
        return type(value) is int and -(2**31) <= value < 2**31
    if kind == "effect-source":
        return value in ("native-set", "page-link", "unattributed")
    if kind == "count":
        return type(value) is int and value >= 0
    raise AssertionError("Unknown scalar type")


def validate_network(net):
    if net is None:
        return
    required = {"coverage", "requests", "uploads"}
    if type(net) is dict and net.get("coverage") == "page-resource-timing":
        required.update(("resourceEntries", "cspViolations"))
    page_timing = type(net) is dict and net.get("coverage") == "page-resource-timing"
    fields(net, required, "run.network", {"localPage"} if page_timing else ())
    local = net.get("localPage")
    if local is not None:
        fields(local, LOCAL_PAGE, "run.network.localPage")
        for key, kind in LOCAL_PAGE.items():
            if local[key] is not None and not valid_scalar(local[key], kind):
                raise InvalidReceipt(f"run.network.localPage.{key}: invalid value")
    coverage = net["coverage"]
    if coverage not in ("unmeasured", "page-resource-timing", "whole-attempt"):
        raise InvalidReceipt("run.network.coverage: invalid category")
    for key, value in net.items():
        if key not in ("coverage", "localPage") and value is not None and not valid_scalar(value, "count"):
            raise InvalidReceipt(f"run.network.{key}: invalid count")
    requests, uploads = net["requests"], net["uploads"]
    if coverage != "whole-attempt" and (requests is not None or uploads is not None):
        raise InvalidReceipt("run.network: whole-attempt counts require whole-attempt coverage")
    if requests is not None and uploads is not None and uploads > requests:
        raise InvalidReceipt("run.network: uploads exceed requests")


def validate(data):
    fields(data, {"schema", "browser", "scope", "entry", "run"}, "receipt", {"evidenceSHA256"})
    if type(data["schema"]) is not int or data["schema"] != 1:
        raise InvalidReceipt("schema: unsupported")
    for key, options in (("browser", ("chrome", "edge")),
                         ("scope", ("owned-local", "enrolled-temporary")),
                         ("entry", ("none", "native-set", "page-link"))):
        if data[key] not in options:
            raise InvalidReceipt(f"{key}: invalid category")
    refs = data.get("evidenceSHA256", {})
    fields(refs, (), "evidenceSHA256", STAGE_NAMES)
    if any(not valid_scalar(ref, "hash") for ref in refs.values()):
        raise InvalidReceipt("evidenceSHA256: expected a SHA-256 digest")
    run = data["run"]
    if run is None:
        if refs:
            raise InvalidReceipt("evidenceSHA256: no run to reference")
        return
    if data["entry"] == "none":
        raise InvalidReceipt("entry: run present without an entry")
    fields(run, STAGE_NAMES | {"challenge"}, "run")
    if run["challenge"] is not None and not valid_scalar(run["challenge"], "hash"):
        raise InvalidReceipt("run.challenge: invalid digest")
    for stage, specification in STAGES.items():
        observation = run[stage]
        if observation is None:
            continue
        fields(observation, specification, f"run.{stage}")
        for name, kind in specification.items():
            value = observation[name]
            if value is not None and not valid_scalar(value, kind):
                raise InvalidReceipt(f"run.{stage}.{name}: invalid value")
    validate_network(run["network"])


def same(first, *observations):
    return first is not None and all(observation == first for observation in observations)


def evaluate(data):
    """A digest is a locator for independent review, never an authenticity assertion."""
    validate(data)
    run = data["run"] or {}
    def value(stage, name):
        return (run.get(stage) or {}).get(name)

    route, doc = value("before", "route"), value("before", "document")
    nonce = run.get("challenge")
    after_original = same(route, value("after", "route")) and same(doc, value("after", "document"))
    native_entry = data["entry"] == "native-set"
    checks = {
        "baselineMarkerAbsent": value("before", "markerAbsent") is True,
        "nativeSetReplySucceeded": native_entry and value("set", "osStatus") == 0,
        "nativeSetBoundToOriginalRouteAndChallenge": (
            native_entry and same(route, value("set", "route"))
            and same(nonce, value("set", "challenge"))),
        "nativeSetEffectInOriginalDocument": (
            native_entry and value("effect", "via") == "native-set"
            and same(doc, value("effect", "document"))
            and same(nonce, value("effect", "challenge"))),
        "originalIsolatedSeesSharedMarkerOnly": (
            value("isolated", "contextVerified") is True
            and same(doc, value("isolated", "document"))
            and same(nonce, value("isolated", "sharedChallenge"))
            and value("isolated", "globalVisible") is False
            and value("isolated", "xhrVisible") is False),
        "originalMainSeesOwnUnopenedXHRAndGlobal": (
            value("main", "contextVerified") is True
            and same(doc, value("main", "document"))
            and same(nonce, value("main", "globalChallenge"), value("main", "xhrChallenge"))
            and value("main", "unopened") is True),
        "afterOriginalRouteAndDocument": after_original,
    }
    refs = data.get("evidenceSHA256", {})
    world_stages = {"before", "set", "effect", "isolated", "main", "after"}
    checks["worldEvidenceReferenced"] = world_stages <= refs.keys()
    world = all(checks.values())
    cleanup = (same(doc, value("cleanup", "document"))
               and all(value("cleanup", field) is True for field in (
                   "globalAbsent", "xhrAbsent", "sharedMarkerAbsent", "mainContextVerified")))
    checks["cleanedInOriginalMain"] = cleanup
    network = run.get("network") or {}
    coverage = network.get("coverage", "unmeasured")
    whole_zero = (coverage == "whole-attempt"
                  and network.get("requests") == 0 and network.get("uploads") == 0)
    checks["measuredZeroWholeAttemptRequestsAndUploads"] = whole_zero
    local = network.get("localPage") or {}
    original_page_covered = (
        data["scope"] == "owned-local" and coverage == "page-resource-timing"
        and local.get("fixedFixtureSHA256") is not None
        and all(local.get(key) is True for key, kind in LOCAL_PAGE.items()
                if kind == "bool" and key != "counterOverflowOrLoss")
        and local.get("counterOverflowOrLoss") is False
        and after_original and same(doc, value("cleanup", "document"))
        and {"before", "after", "cleanup", "network"} <= refs.keys())
    page_zero = (original_page_covered and network.get("resourceEntries") == 0
                 and network.get("cspViolations") == 0)
    checks["fixedLocalPageContinuouslyCovered"] = original_page_covered
    checks["allStagesReferenced"] = STAGE_NAMES <= refs.keys()
    if data["entry"] == "none":
        verdict = "NOT_RUN"
    elif data["entry"] == "page-link":
        verdict = "CONTROL_ONLY"
    elif world and cleanup and (whole_zero or page_zero) and checks["allStagesReferenced"]:
        verdict = "PASS"
    else:
        verdict = "INCONCLUSIVE"
    return {"schema": 1, "browser": data["browser"], "scope": data["scope"], "entry": data["entry"],
            "overall": verdict,
            "overallScope": ("owned-local-original-document" if data["scope"] == "owned-local"
                             else "enrolled-temporary-original-document"),
            "worldVerified": world,
            "localExecutionWorld": ("PASS" if data["scope"] == "owned-local" and world
                                    else "NOT_VERIFIED"),
            "originalDocumentResourcesNoHTTP": True if page_zero else None,
            "wholeNetworkObserved": (coverage == "whole-attempt" and "network" in refs
                                     and network.get("requests") is not None
                                     and network.get("uploads") is not None),
            "checks": checks,
            "effectSource": value("effect", "via"), "observedOSStatus": value("set", "osStatus"),
            "network": network or {"coverage": coverage, "requests": None, "uploads": None},
            "missingStageReferences": sorted(STAGE_NAMES - refs.keys())}


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InvalidReceipt("receipt: duplicate key")
        result[key] = value
    return result


def reject_nonfinite(_):
    raise InvalidReceipt("receipt: invalid number")


def read(raw):
    if len(raw) > LIMIT:
        raise InvalidReceipt("receipt: too large")
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicates,
                          parse_constant=reject_nonfinite)
    except InvalidReceipt:
        raise
    except (ValueError, RecursionError) as error:
        raise InvalidReceipt("receipt: invalid JSON") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", help="fixed-schema JSON file, or - for stdin")
    parser.add_argument("--require-pass", action="store_true", help="exit 1 for valid non-PASS results")
    args = parser.parse_args()
    try:
        if args.receipt == "-":
            raw = sys.stdin.buffer.read(LIMIT + 1)
        else:
            with Path(args.receipt).open("rb") as stream:
                raw = stream.read(LIMIT + 1)
        result = evaluate(read(raw))
        result["projectionSHA256"] = hashlib.sha256(raw).hexdigest()
    except OSError:
        print(json.dumps({"overall": "INVALID_RECEIPT", "reason": "receipt: read failed"}))
        return 2
    except InvalidReceipt as error:
        print(json.dumps({"overall": "INVALID_RECEIPT", "reason": str(error)}))
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return int(args.require_pass and result["overall"] != "PASS")


if __name__ == "__main__":
    sys.exit(main())
