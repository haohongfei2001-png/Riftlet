#!/usr/bin/env python3
"""Project an existing fixed local native QA run. Reads fixed files only, never runs the probe."""

import argparse
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
from uuid import UUID

import verify


HERE = Path(__file__).resolve().parent
FIXTURE = Path("Tests/PreClickLease/g4/main-world-bootstrap/fixture.html")
FROZEN = "49b9204974088c1983cda469910d9a78d8f4c43b"
TRANSPORT = "00b1f7b637aad2ce00cc9b766c923ad5c4f25c3d0d08e8cf7306983ddb386140"
STEPS = ("install", "read", "clear", "retire")
STAGES = ("creation-intent", "window-created", "ready", "installed", "isolated", "main-read",
          "clear", "final-independent-read", "retired", "close-intent", "closed", "run",
          "preparation-stop", "environment", "cleanup-after-stop",
          "last-while-waiting-ready", "last-while-waiting-installed", "last-while-waiting-read",
          "last-while-waiting-cleared")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def token(*fields):
    return sha(json.dumps(fields, separators=(",", ":"), ensure_ascii=True).encode())


def raw(path, limit):
    if path.resolve() != path:
        raise ValueError("noncanonical input")
    info = path.stat()
    if (not stat.S_ISREG(info.st_mode) or info.st_size > limit or info.st_nlink != 1
            or info.st_uid != os.getuid()):
        raise ValueError("unexpected input metadata")
    return path.read_bytes()


def uuid_string(value):
    try:
        return isinstance(value, str) and str(UUID(value)) == value.lower()
    except ValueError:
        return False


def count(value):
    return type(value) is int and value >= 0


def number(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def yes(row, *keys):
    return all(row.get(k) is True for k in keys)


def no(row, *keys):
    return all(row.get(k) is False for k in keys)


def known_stop(value):
    if value is None:
        return None
    fixed = {"FIXTURE_CHANGED", "FIXTURE_NOT_READY", "NEW_WINDOW_NOT_VERIFIED", "SOLE_NEW_TAB_NOT_VERIFIED",
             "NEW_TAB_NOT_BLANK", "LOCAL_FILE_DID_NOT_LOAD", "ORIGINAL_LOCAL_TARGET_CHANGED", "STALE_DOCUMENT",
             "ORIGINAL_TAB_NO_LONGER_SELECTED", "CLOSURE_OWNERSHIP_UNPROVEN", "RETIREMENT_MISMATCH",
             "WINDOW_CLOSE_UNCONFIRMED", "RECEIPT_RETIREMENT_UNCONFIRMED", "LOCAL_INSTALL_CHALLENGE_OR_KEYS_MISSING"}
    if isinstance(value, str) and (value in fixed or re.fullmatch(
            r"(?:APPLE_EVENT_|EXISTING_AUTOMATION_PERMISSION_REQUIRED_|LOCAL_AUDIT_ERROR_)-?[0-9]{1,8}"
            r"|PAGE_RECEIPT_MISSING_(?:READY|INSTALLED|READ|CLEARED)", value)):
        return value
    return "OTHER_RECORDED_STOP"


def local_policy(fixture):
    text = fixture.decode()
    policies = re.findall(r'<meta http-equiv="Content-Security-Policy" content="([^"]+)">', text)
    scripts = re.findall(r"<script>(.*?)</script>", text, re.S)
    if len(policies) != 1 or len(scripts) != 1:
        return False
    encoded = base64.b64encode(hashlib.sha256(scripts[0].encode()).digest()).decode()
    directives = [line.strip().split() for line in policies[0].split(";")]
    denied = ("default-src connect-src child-src frame-src worker-src form-action img-src object-src "
              "base-uri style-src font-src media-src manifest-src").split()
    return (len(directives) == len(denied) + 1 and all([name, "'none'"] in directives for name in denied)
            and ["script-src", "'sha256-" + encoded + "'"] in directives)


def build_verified(scratch, family, manifest):
    fixture = raw(scratch / family / FIXTURE, 128_000)
    native = raw(HERE / "NativeCheck.swift", 128_000)
    builder = raw(HERE / "build_local.py", 64_000)
    compiled = raw(scratch / "package/Sources/RiftletAdapters/ChromeAppleEventsExecutor.swift", 512_000)
    config = ('\nenum PinnedLocalBootstrapFixture {\n    static let work = ' + json.dumps(str(scratch)) +
              '\n    static let sha = ' + json.dumps(sha(fixture)) + '\n}\n').encode()
    suffix = config + native
    return (compiled.endswith(suffix) and sha(compiled[:-len(suffix)]) == TRANSPORT
            and fixture == raw(HERE / "fixture.html", 128_000) and local_policy(fixture)
            and manifest == {"frozenCommit": FROZEN, "transportPrefixSHA256": TRANSPORT,
                             "compiledSourceSHA256": sha(compiled), "executableSHA256":
                             sha(raw(scratch / "local-bootstrap-audit", 128_000_000)),
                             "fixtureSHA256": sha(fixture), "runnerSHA256": sha(native),
                             "builderSHA256": sha(builder)})


def project(scratch, family):
    if (family not in ("chrome", "edge") or scratch != scratch.resolve()
            or scratch.parent != Path("/private/tmp") or not scratch.name.startswith("riftlet61-owned-native-")
            or scratch.stat().st_uid != os.getuid() or scratch.stat().st_mode & 0o077):
        raise ValueError("expected owned private scratch")
    records, digests = {}, {}
    for name in (*STAGES, "build-manifest"):
        folder = scratch if name == "build-manifest" else scratch / family
        path = folder / (name + ".json")
        if not path.exists():
            continue
        data = raw(path, verify.LIMIT)
        row = verify.read(data)
        if type(row) is not dict:
            raise ValueError("invalid stage object")
        records[name], digests[name] = row, sha(data)
    def row(name):
        return records.get(name, {})
    def page(name):
        result = row(name).get("page", {})
        return result if type(result) is dict else {}

    manifest = row("build-manifest")
    source_ok = bool(manifest) and build_verified(scratch, family, manifest)
    report, creation, baseline = row("run"), row("window-created"), row("creation-intent")
    closed, close_intent = row("closed"), row("close-intent")
    env = row("environment")
    reason = []
    # Empty input or an interrupted invocation must not be mistaken for a confirmed stop.
    terminal_before_set = (row("preparation-stop").get("family") == family
                           and bool(row("preparation-stop").get("preparationStop")) and not report)
    environment_stop = env.get("admitted") is False and not report and not creation
    owned = (type(creation.get("pid")) is int and creation["pid"] > 0 and
             isinstance(creation.get("birth"), str) and bool(creation["birth"]) and
             all(isinstance(creation.get(k), str) and re.fullmatch(r"[1-9][0-9]*", creation[k])
                 for k in ("window", "tab")) and creation.get("blankVerified") is True and
             type(creation.get("beforeWindowIDs")) is list and creation["window"] not in creation["beforeWindowIDs"]
             and baseline.get("originalWindowIDs") == creation["beforeWindowIDs"]
             and all(baseline.get(k) == creation[k] for k in ("pid", "birth")))
    route = (token(family, creation["pid"], creation["birth"], creation["window"], creation["tab"])
             if owned else None)
    close_ok = bool(owned and yes(closed, "ownedWindowGone", "allOriginalIDsRestored")
                    and all(close_intent.get(k) == creation[k] for k in ("pid", "birth", "window", "tab")))
    source_file = (scratch / family / FIXTURE).as_uri()
    origin, entry, doc_nonce = (row("ready").get("timeOrigin"), row("ready").get("entryID"),
                                page("ready").get("documentNonce"))
    def original(name, phase):
        s, p = row(name), page(name)
        return bool(owned and number(origin) and uuid_string(entry) and uuid_string(doc_nonce)
                    and s.get("originalFile") == source_file and s.get("entryID") == entry
                    and s.get("timeOrigin") == p.get("timeOrigin") == origin
                    and p.get("documentNonce") == doc_nonce and p.get("phase") == phase
                    and type(p.get("schema")) is int and p["schema"] == 1
                    and yes(s, "hidden", "textEmpty") and yes(p, "documentMatches", "methodsUnchanged"))
    doc = token(route, source_file, origin, entry, doc_nonce) if original("ready", "ready") else None
    events = report.get("events", [])
    events_ok = (type(events) is list and len(events) <= 24 and report.get("family") == family
                 and all(isinstance(e, dict) and isinstance(e.get("detail"), dict)
                         and number(e.get("uptime")) for e in events))
    if events_ok:
        events_ok = all(e.get("event") in ("owned-file-loaded", "native-submit-intent", "native-submit-return",
                                           "cleanup-read-unavailable") for e in events)
    if events_ok:
        times = [e["uptime"] for e in events]
        events_ok = times == sorted(times)
    native = [e for e in events if e["event"] in ("native-submit-intent", "native-submit-return")] if events_ok else []
    native_steps = [(e["event"], e["detail"].get("step")) for e in native]
    loaded_once = (events_ok and len(events) > 0 and events[0]["event"] == "owned-file-loaded"
                   and sum(e["event"] == "owned-file-loaded" for e in events) == 1)
    def returned(step):
        for i, (kind, tag) in enumerate(native_steps):
            if tag == step and kind == "native-submit-intent":
                return (native_steps.count((kind, step)) == native_steps.count(("native-submit-return", step)) == 1
                        and i+1 < len(native) and native_steps[i+1] == ("native-submit-return", step)
                        and type(native[i+1]["detail"].get("nativeStatus")) is int
                        and native[i+1]["detail"]["nativeStatus"] == 0)
        return False
    expected = [(event, step) for step in STEPS for event in ("native-submit-intent", "native-submit-return")]
    full_order = loaded_once and native_steps == expected and all(returned(step) for step in STEPS)
    challenge = report.get("challenge")
    chash = token(challenge) if uuid_string(challenge) else None
    attempted = bool(native) or any(name in records for name in ("installed", "isolated", "main-read"))
    no_set = (not attempted and (terminal_before_set or environment_stop
              or (events_ok and report.get("measurementStop") and not native)))
    stage_names = sorted(set(records) - {"build-manifest"})
    summary = {"sourceAndManifestVerified": source_ok, "sourceArtifactSHA256": digests,
               "observedStages": stage_names, "stageCount": len(stage_names), "ownedWindowVerified": owned,
               "ownedWindowClosureVerified": close_ok, "exactNativeOrder": full_order,
               "nativeIntents": {step: native_steps.count(("native-submit-intent", step)) for step in STEPS},
               "nativeSuccessfulReplies": {step: returned(step) for step in STEPS},
               "preparationStop": known_stop(row("preparation-stop").get("preparationStop")),
               "measurementStop": known_stop(report.get("measurementStop")),
               "closureStop": known_stop(report.get("closureStop")), "environmentAdmitted": env.get("admitted")
               if isinstance(env.get("admitted"), bool) else None, "blockers": reason}
    frame = {"schema": 1, "browser": family, "scope": "owned-local", "entry": "none" if no_set else "native-set",
             "run": None}
    if no_set or not attempted:
        reason.append("NATIVE_INSTALL_NOT_ENTERED" if no_set else "NO_TERMINAL_PROOF_OF_NATIVE_INSTALL")
        return {"projection": frame, "verdict": verify.evaluate(frame), "summary": summary}

    marks = page("installed")
    keys = (marks.get("globalMarkerKey"), marks.get("prototypeMarkerKey"))
    keys_ok = (isinstance(keys[0], str) and re.fullmatch(r"__riftlet_fixture_global_[0-9a-f]{32}", keys[0])
               and isinstance(keys[1], str) and re.fullmatch(r"__riftlet_fixture_xhr_[0-9a-f]{32}", keys[1]))
    def marked(name, phase):
        p = page(name)
        return bool(original(name, phase) and keys_ok and chash and p.get("nativeChallenge") == challenge
                    and (p.get("globalMarkerKey"), p.get("prototypeMarkerKey")) == keys
                    and yes(p, "ok", "globalMatches", "prototypeMatches", "globalMarkerIdentityMatches",
                            "prototypeMarkerIdentityMatches", "nonEnumerable", "sharedMarkerMatches",
                            "globalMarkerPresent", "prototypeMarkerPresent")
                    and row(name).get("temporaryNodePresent") is True)
    install = bool(loaded_once and native_steps[:2] == expected[:2] and marked("installed", "installed")
                   and returned("install"))
    isolated = install and marked("isolated", "installed") and row("isolated").get("ownedFunctionVisible") is False
    main = bool(install and marked("main-read", "read") and returned("read"))
    baseline_ok = (original("ready", "ready") and yes(page("ready"), "ok", "descriptorRestored", "noTemporaryNodes")
                   and no(page("ready"), "globalMarkerPresent", "prototypeMarkerPresent")
                   and page("ready").get("nativeChallenge") is None and row("ready").get("temporaryNodePresent") is False)
    retired = row("retired")
    retirement = (yes(retired, "staticNodePresent", "hidden", "textEmpty", "noReceiptOrPolicyData",
                      "temporaryNodeAbsent", "globalAbsent", "prototypeAbsent")
                  and retired.get("entryID") == entry and retired.get("timeOrigin") == origin)
    cleanup = (main and full_order and retirement and all(
        original(name, "cleared") and yes(page(name), "ok", "globalMatches", "prototypeMatches", "cleanupVerified",
                                          "noTemporaryNodes", "descriptorRestored")
        and no(page(name), "globalMarkerPresent", "prototypeMarkerPresent") and
        no(row(name), "temporaryNodePresent", "globalVisible", "xhrVisible")
        for name in ("clear", "final-independent-read")))
    seq = (("ready", "ready"), ("installed", "installed"), ("isolated", "installed"), ("main-read", "read"),
           ("clear", "cleared"), ("final-independent-read", "cleared"))
    def counters(name, phase):
        p, s = page(name), row(name)
        return (original(name, phase) and yes(p, "cspObservationAvailable", "resourceEntriesAvailable")
                and all(count(p.get(k)) for k in ("cspViolations", "resourceEntries", "resourceBufferFullEvents"))
                and p.get("cspListenerActive") is (phase != "cleared")
                and p.get("resourceBufferListenerActive") is (phase != "cleared")
                and s.get("cspCount") == str(p["cspViolations"])
                and s.get("bufferFull") == str(p["resourceBufferFullEvents"])
                and count(s.get("resourceEntries")) and s["resourceEntries"] == p["resourceEntries"])
    continuous = bool(source_ok and all(counters(name, phase) for name, phase in seq))
    if continuous:
        values = {k: [page(n)[k] for n, _ in seq] for k in ("cspViolations", "resourceEntries", "resourceBufferFullEvents")}
        continuous = all(v == sorted(v) for v in values.values())
    end = row("final-independent-read") if continuous else {}
    last = row("last-while-waiting-installed")
    summary["sameOriginalStillReadyAfterSet"] = bool(returned("install") and original("last-while-waiting-installed", "ready"))
    summary["lastWhileWaitingCspCount"] = int(last["cspCount"]) if isinstance(last.get("cspCount"), str) and re.fullmatch(r"[0-9]{1,7}", last["cspCount"]) else None
    directive = last.get("cspDirective")
    summary["lastWhileWaitingCspDirective"] = directive if directive in ("script-src", "script-src-elem", "script-src-attr", "default-src") else None
    summary["fixtureCallsOnly"] = 0 if source_ok and all(
        page(n).get("networkCountScope") == "fixtureSourceCalls" and type(page(n).get("networkCalls")) is int
        and page(n)["networkCalls"] == 0 for n in ("ready",)) and original("ready", "ready") else None
    if not source_ok:
        reason.append("SOURCE_MANIFEST_OR_FIXED_FIXTURE_UNVERIFIED")
    if env.get("admitted") is not True:
        reason.append("LOCAL_ENVIRONMENT_ADMISSION_NOT_PROVEN")
    if not install:
        reason.append("NATIVE_PAGE_INSTALL_NOT_OBSERVED")
    if not isolated or not main:
        reason.append("WORLD_READBACK_INCOMPLETE")
    if not cleanup:
        reason.append("ORIGINAL_MARKER_CLEANUP_OR_RETIREMENT_UNVERIFIED")
    if not close_ok:
        reason.append("ORIGINAL_WINDOW_CLOSURE_UNVERIFIED")
    if not continuous:
        reason.append("PAGE_COUNTER_COVERAGE_INCOMPLETE")
    trace = {"before": "ready", "set": "run", "effect": "installed", "isolated": "isolated",
             "main": "main-read", "cleanup": "clear", "after": "retired", "network": "final-independent-read"}
    refs = {key: digests[name] for key, name in trace.items() if name in digests and source_ok}
    native_status = 0 if returned("install") else None
    # A thrown install happens between its intent and its return. Do not attribute
    # an error from a later original-document read to the native setter.
    if (native_steps == [("native-submit-intent", "install")] and
            isinstance(report.get("measurementStop"), str)):
        status_error = re.fullmatch(r"APPLE_EVENT_(-[0-9]{1,8})", report["measurementStop"])
        if status_error:
            native_status = int(status_error.group(1))
    net = {"coverage": "unmeasured", "requests": None, "uploads": None}
    if "ready" in records:
        net = {"coverage": "page-resource-timing", "requests": None, "uploads": None,
               "resourceEntries": end.get("resourceEntries"), "cspViolations": int(end["cspCount"]) if end else None,
               "localPage": {"fileScheme": bool(doc), "fixedFixtureSHA256": manifest.get("fixtureSHA256") if source_ok else None,
                             "fixtureHashMatched": source_ok, "policyActiveFromPreparationThroughCleanup": True if continuous else None,
                             "connectionAndWorkerSourcesDenied": True if source_ok else None,
                             "remoteSubresourcesAndFormDenied": True if source_ok else None,
                             "continuousCountersOnOriginalDocument": True if continuous else None,
                             "counterOverflowOrLoss": int(end["bufferFull"]) > 0 if end else None}}
    frame["evidenceSHA256"] = refs
    frame["run"] = {
        "challenge": chash,
        "before": {"route": route, "document": doc, "markerAbsent": baseline_ok} if "ready" in records else None,
        "set": {"route": route, "osStatus": native_status, "challenge": chash},
        "effect": {"document": doc, "challenge": chash, "via": "native-set"} if install else None,
        "isolated": {"document": doc, "sharedChallenge": chash, "globalVisible": row("isolated").get("globalVisible"),
                     "xhrVisible": row("isolated").get("xhrVisible"), "contextVerified": isolated} if install and "isolated" in records else None,
        "main": {"document": doc, "globalChallenge": chash, "xhrChallenge": chash,
                 "unopened": page("main-read").get("unopenedXHRMatches"), "contextVerified": main} if main else None,
        "cleanup": {"document": doc, "globalAbsent": cleanup, "xhrAbsent": cleanup, "sharedMarkerAbsent": cleanup,
                    "mainContextVerified": cleanup} if "clear" in records else None,
        "after": {"route": route, "document": doc} if (cleanup and close_ok and env.get("admitted") is True
                                                      and not report.get("measurementStop")
                                                      and not report.get("closureStop")) else None,
        "network": net,
    }
    return {"projection": frame, "verdict": verify.evaluate(frame), "summary": summary}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scratch", type=Path)
    parser.add_argument("family", choices=("chrome", "edge"))
    args = parser.parse_args()
    try:
        output = project(args.scratch, args.family)
    except (OSError, ValueError, KeyError, TypeError, OverflowError):
        parser.exit(2, "Invalid, incomplete or unreadable fixed QA source or evidence schema.\n")
    print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
