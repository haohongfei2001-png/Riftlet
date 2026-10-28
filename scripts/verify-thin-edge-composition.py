#!/usr/bin/env python3
"""Read-only composition gate for the independently reviewed Thin Edge candidate.

The three historical audits execute their original, pinned Git blobs against
their exact historical commits. They are not weakened to accept a sibling's
changes. The second layer pins the complete reviewed composition tree: every
path, blob, type and mode must match, except this source-review policy file and
the two explicitly named post-CI handoff records. Those three paths must already
exist in the reviewed source tree and remain regular, non-executable files.
There are no directory exceptions, branch-name switches, CLI pin overrides,
working-tree inputs, checkout/index writes or automatic history fetches.

The integration owner must set REVIEWED_SOURCE after non-author review and a
source commit. Until then the executable fails closed. Updating this gate is a
new review decision; the gate cannot cryptographically approve its own edits.
"""

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Optional


GATE_PATH = "scripts/verify-thin-edge-composition.py"
METADATA_PATHS = frozenset((
    GATE_PATH,
    "engineering/evidence/2026-10-29-thin-edge-native/README.md",
    "engineering/evidence/2026-10-29-thin-edge-native/results.json",
))
REVIEWED_SOURCE = "4fd4ac2da062bb26dc3cdc600b224f2e8dfe094b"  # Non-author source review + scoped native evidence.


@dataclass(frozen=True)
class HistoricalAudit:
    name: str
    revision: str
    path: str
    blob: str


@dataclass(frozen=True)
class Policy:
    baseline: str
    histories: tuple
    reviewed_source: Optional[str]


POLICY = Policy(
    baseline="1920e0562db893a3292af89a89270a26ddb46a5f",
    histories=(
        HistoricalAudit("internal-beta", "1920e0562db893a3292af89a89270a26ddb46a5f",
                        "scripts/verify-internal-beta-integration.py",
                        "94b09b58f412a7778c2e63ec46c23291b4c3bc99"),
        HistoricalAudit("capture-entry", "5d6a683652d255af8c1d3e0d9533587fcc27a24d",
                        "scripts/verify-capture-entry-integration.py",
                        "e4e9280b4b7c168f3cd5ddac01d33de448d761ea"),
        HistoricalAudit("arrival", "d552a7388af3890bf693bb3fb24f4b8fc5bc12e7",
                        "scripts/verify-arrival-integration.py",
                        "3a90bed49e5abe2b4b35d88167c8662a6e05f140"),
    ),
    reviewed_source=REVIEWED_SOURCE,
)


class AuditError(Exception):
    pass


def git_environment():
    # -C alone does not defeat GIT_DIR, alternate objects, namespaces or grafts.
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = os.devnull
    return environment


def git(repository, *arguments, ancestor=False):
    process = subprocess.run(
        ["git", "--no-replace-objects", "-C", str(repository), *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=git_environment(),
    )
    if ancestor and process.returncode in (0, 1):
        return process.returncode == 0
    if process.returncode != 0:
        raise AuditError("git " + arguments[0] + " failed: " + process.stderr.decode("utf-8", errors="replace").strip())
    return process.stdout


def commit(repository, revision):
    return git(repository, "rev-parse", "--verify", "--end-of-options",
               revision + "^{commit}").decode("ascii").strip()


def fixed_commit(repository, revision, name):
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise AuditError("Missing or invalid fixed commit: " + name)
    if commit(repository, revision) != revision:
        raise AuditError("Commit does not resolve to its exact pin: " + name)


def objects(repository, revision):
    result = {}
    for item in git(repository, "ls-tree", "-r", "-z", revision).split(b"\0"):
        if not item:
            continue
        metadata, raw_path = item.split(b"\t", 1)
        mode, kind, oid = metadata.decode("ascii").split()
        result[raw_path.decode("utf-8")] = {"mode": mode, "type": kind, "oid": oid}
    return result


def valid_path(path):
    return (isinstance(path, str) and bool(path) and not path.startswith("/")
            and all(part not in ("", ".", "..") for part in path.split("/"))
            and not any(symbol in path for symbol in ("*", "?", "[", "\\")))


def run_historical(repository, history):
    """Execute the exact old command-line program, never checkout script bytes.

    capture-entry's unchanged loader derives the repository from __file__. Its
    original logical filename is retained while executable bytes come only from
    the pinned blob. Original arguments and all original checks remain intact.
    """
    repository = Path(repository).resolve()
    source = git(repository, "cat-file", "blob", history.blob)
    with tempfile.TemporaryDirectory(prefix="riftlet-thin-edge-audit-") as directory:
        payload = Path(directory) / "historical.py"
        payload.write_bytes(source)
        logical_path = str(repository / history.path)
        wrapper = (
            "import pathlib, sys\n"
            "payload, logical, revision, repository = sys.argv[1:]\n"
            "sys.argv = [logical, revision, '--repository', repository]\n"
            "namespace = {'__name__': '__main__', '__file__': logical}\n"
            "exec(compile(pathlib.Path(payload).read_bytes(), logical, 'exec'), namespace)\n"
        )
        process = subprocess.run(
            [sys.executable, "-B", "-c", wrapper, str(payload), logical_path,
             history.revision, str(repository)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=git_environment(), timeout=90,
        )
    try:
        report = json.loads(process.stdout)
    except (ValueError, UnicodeError) as error:
        raise AuditError(history.name + " historical audit emitted no structured result") from error
    if not isinstance(report, dict):
        raise AuditError(history.name + " historical audit emitted a non-object result")
    checks = report.get("checks", [])
    passed = (process.returncode == 0 and report.get("result") == "PASS"
              and report.get("revision") == history.revision and bool(checks)
              and all(isinstance(item, dict) and item.get("result") == "PASS" for item in checks))
    return passed, report


def audit(repository, revision="HEAD", policy=POLICY):
    """Alternate policies are solely for independent temporary Git fixtures."""
    report = {"schemaVersion": 1, "result": "FAIL", "revisionRequested": revision,
              "baseline": policy.baseline, "reviewedSource": policy.reviewed_source,
              "metadataExceptions": sorted(METADATA_PATHS), "checks": [], "historicalAudits": {}}
    checks = report["checks"]

    def check(identifier, passed, **details):
        checks.append({"id": identifier, "result": "PASS" if passed else "FAIL", **details})

    try:
        resolved = commit(repository, revision)
        report["revision"] = resolved
        report["tree"] = git(repository, "rev-parse", resolved + "^{tree}").decode("ascii").strip()
        fixed_commit(repository, policy.baseline, "baseline")
        check("ancestor:baseline", git(repository, "merge-base", "--is-ancestor",
                                      policy.baseline, resolved, ancestor=True))
        actual = objects(repository, resolved)
        seen = set()
        if not policy.histories:
            raise AuditError("Historical audit list must not be empty")
        for history in policy.histories:
            if (not valid_path(history.path) or history.path == GATE_PATH or history.path in seen
                    or not re.fullmatch(r"[0-9a-f]{40}", history.blob)):
                raise AuditError("Invalid historical audit policy")
            seen.add(history.path)
            fixed_commit(repository, history.revision, history.name)
            expected = {"mode": "100644", "type": "blob", "oid": history.blob}
            pinned = objects(repository, history.revision).get(history.path)
            if pinned != expected:
                raise AuditError("Historical audit pin does not match its original tree: " + history.name)
            passed, historical_report = run_historical(repository, history)
            report["historicalAudits"][history.name] = historical_report
            check("historical:" + history.name, passed,
                  originalRevision=history.revision, originalAudit=expected)
            check("historical-gate-unchanged:" + history.name,
                  actual.get(history.path) == expected, expected=expected, actual=actual.get(history.path))

        fixed_commit(repository, policy.reviewed_source, "reviewed composition source")
        check("ancestor:reviewed-source", git(repository, "merge-base", "--is-ancestor",
                                             policy.reviewed_source, resolved, ancestor=True))
        check("ancestor:reviewed-source-baseline", git(repository, "merge-base", "--is-ancestor",
                                                      policy.baseline, policy.reviewed_source, ancestor=True))
        approved = objects(repository, policy.reviewed_source)
        protected = set(approved) - METADATA_PATHS
        candidate = set(actual) - METADATA_PATHS
        check("composition:exact-paths", protected == candidate,
              unexpected=sorted(candidate - protected), missing=sorted(protected - candidate))
        different = {path: {"expected": approved[path], "actual": actual.get(path)}
                     for path in sorted(protected) if actual.get(path) != approved[path]}
        check("composition:exact-objects", not different, protectedFileCount=len(protected), differences=different)
        for name, tree in (("reviewed", approved), ("candidate", actual)):
            for path in sorted(METADATA_PATHS):
                obj = tree.get(path)
                check("composition:regular-metadata:" + name + ":" + path,
                      bool(obj) and obj["mode"] == "100644" and obj["type"] == "blob")
        report["protectedObjects"] = {path: approved[path] for path in sorted(protected)}
    except (AuditError, OSError, UnicodeError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        check("audit:inputs", False, error=str(error))
    report["result"] = "PASS" if checks and all(item["result"] == "PASS" for item in checks) else "FAIL"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD", help="committed revision to inspect")
    parser.add_argument("--repository", type=Path, default=Path("."), help="Git repository/worktree")
    arguments = parser.parse_args()
    report = audit(arguments.repository, arguments.revision)
    print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
    print("THIN_EDGE_COMPOSITION_" + report["result"], file=sys.stderr)
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
