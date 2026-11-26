#!/usr/bin/env python3
"""Check cross-record agreement for a downloaded hosted-macOS Sparkle receipt.
This does not mount a DMG, test a website, or approve a release.
"""
import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path


def need(ok, message):
    if not ok:
        raise ValueError(message)


def verify(args):
    signed, formal, summary = [json.loads(p.read_text()) for p in
                               (args.signed, args.formal, args.summary)]
    with zipfile.ZipFile(args.artifact) as z:
        names = [x for x in z.infolist() if x.filename == "public-sparkle.json"]
        need(len(names) == 1 and names[0].file_size <= 65536,
             "expected exactly one small public-sparkle.json")
        raw = z.read(names[0])
    r = json.loads(raw)
    old, new = r["startingApp"], r["retainedLibrary"]["installed"]
    arch = signed["architectures"]
    expected_build = str(signed["build"])
    checks = (
        (hashlib.sha256(raw).hexdigest() == summary["receiptSHA256"], "artifact byte hash"),
        (r["status"] == "PRIVATE_LOOPBACK_IN_APP_UPGRADE_PASS" and r["mode"] == "private-upgrade", "exact hosted upgrade outcome"),
        (r["qaSource"] == summary["qaSource"] and summary["run"].rstrip("/").endswith("/actions/runs/" + str(r["workflow"])), "workflow and QA source identity"),
        (signed["source"] == formal["signedProductSource"] == summary["source"], "candidate source commit"),
        (signed["sourceTree"] == formal["signedProductTree"] and signed["manifestSHA256"] == formal["signedPackageManifestSHA256"], "candidate tree and manifest"),
        (r["privateFeed"]["enclosureSHA256"] == signed["sha256"] == summary["packageSHA256"] and bool(re.fullmatch(r"[0-9a-f]{64}", signed["sha256"])), "DMG SHA-256"),
        (new["build"] == r["privateFeed"]["build"] == summary["newBuild"] == expected_build == str(formal["build"]) and new["version"] == signed["version"] == formal["version"], "installed release/build"),
        (old["build"] == summary["oldBuild"], "starting build"),
        (set(arch) == {"x86_64", "arm64"} and arch == summary["codeDirectories"] == new["codeDirectories"] and signed["binarySHA256"] == summary["appBinarySHA256"] == new["binarySHA256"], "binary SHA-256 and both CodeDirectory hashes"),
        (new["appTicket"] == signed["appTicket"] == signed["dmgTicket"] == "VALID" and new["gatekeeper"] == signed["appGatekeeperExecute"] == signed["dmgGatekeeperOpen"] == "ACCEPTED", "notarization and Gatekeeper"),
        (r["retainedLibrary"]["oldRowsAndMediaExact"] is True and r["retainedLibrary"]["preferencesUnchanged"] is True and r["oldLibrary"]["sqliteSnapshotSHA256"] == r["retainedLibrary"]["sqliteSnapshotSHA256"] and r["oldLibrary"]["syntheticHistoricOperation"] == r["retainedLibrary"]["retainedHistoricOperation"] and r["oldLibrary"]["oldPID"] != r["retainedLibrary"]["newPID"], "SQLite, originals, preferences, historic operation and relaunch"),
        (r["privateFeed"]["oldPublicKeyVerifiedFeedAndEnclosure"] is True and r["loopback"]["onlyLocal"] is True and r["loopback"]["serverStopped"] is True and r["loopback"]["persistentFeedOverride"] is False and summary["publicStableChanged"] is False, "private, signed, nonpersistent upgrade"),
        (summary["status"] == signed["status"] == formal["formalOutcome"] == "PASS", "receipt provenance statuses"),
    )
    for ok, name in checks:
        need(ok, f"mismatch: {name}")
    print(json.dumps({"status":"PASS", "scope":"cross-record evidence only; no fresh install or website acceptance", "workflow":r["workflow"], "macOS":r["system"], "fromBuild":old["build"], "toBuild":new["build"], "candidateSource":signed["source"], "mergeCandidate":formal["mergeCommit"], "dmgSHA256":signed["sha256"], "artifactReceiptSHA256":summary["receiptSHA256"], "checks":len(checks)}, indent=2))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for argument in ("artifact", "signed", "formal", "summary"):
        p.add_argument("--" + argument, required=True, type=Path)
    try:
        verify(p.parse_args())
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as exc:
        sys.exit(f"FAIL: {exc}")


if __name__ == "__main__":
    main()
