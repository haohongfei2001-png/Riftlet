#!/usr/bin/env python3
"""Verify the reviewed unified candidate without weakening its source audits.

Run the exact historical Feedback and Thin Edge audit blobs at their original
commits, then compare every current object with a non-author-reviewed source
checkpoint. Existing audit scripts stay fixed. Only this policy and two named,
already-existing plain-text handoff records can change after that checkpoint.

A GitHub PR test merge may additionally contain exactly fifteen individually
pinned website objects from a fixed main commit. That allowance requires the
actual two merge parents and checks the candidate parent independently; it is
not selected by an event, branch name, environment variable or directory prefix.
The CLI cannot override any source pin. Missing review pins fail closed.
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


GATE_PATH = "scripts/verify-final-product-composition.py"
METADATA_PATHS = frozenset((
    GATE_PATH,
    "engineering/evidence/2026-10-29-final-product/README.md",
    "engineering/evidence/2026-10-29-final-product/results.json",
))
# Set only after a committed source checkpoint has non-author review. This
# script cannot approve changes to its own policy; that remains a review gate.
REVIEWED_SOURCE = "ee538eb7e3aedc459cbccffbeb0337918fa13b6b"  # Non-author source review; runtime acceptance remains separate.


@dataclass(frozen=True)
class HistoricalAudit:
    name: str
    revision: str
    path: str
    blob: str


@dataclass(frozen=True)
class Policy:
    histories: tuple
    reviewed_source: Optional[str]
    main_revision: str
    main_objects: tuple


POLICY = Policy(
    histories=(
        HistoricalAudit("feedback-reliability", "0e7ea8be148e1124b387e799fd886a7830e96559",
                        "scripts/verify-internal-beta-integration.py",
                        "d02efe1b8655b22a2aae2a347bba3c4d1c9d20f8"),
        HistoricalAudit("thin-edge", "443d21da1a55c0061eafced823b5406879b96024",
                        "scripts/verify-thin-edge-composition.py",
                        "eff1187ef5a46797266cd6aa69e383dfdf4e3a60"),
        HistoricalAudit("unified-thin-edge", "2c8cd0371de5e07fd7794f76335381a40403030d",
                        "scripts/verify-unified-candidate-composition.py",
                        "a9470427c62625db2935e187f340616682aaa30d"),
        HistoricalAudit("builtin-capture", "6b60f67f6d35272eecff901c507bd75a77874ed6",
                        "scripts/verify-builtin-capture-composition.py",
                        "1b9d9ad4c43026647fd4f656962b639bab877965"),
    ),
    reviewed_source=REVIEWED_SOURCE,
    main_revision="eba1a4fc77648a665e1d5c1f2609df1314c3b079",
    main_objects=(
        ("favicon.svg", "0b3bd76e4db66be4eaff53c3274121c6da866b82"),
        ("index.html", "d6edc73d994af4f32b15e828ba53172b2fc09a9e"),
        ("site.webmanifest", "1e967c66fe1b30209b94176ee7a7d70fd3aeb5ef"),
        ("website-hero.css", "5349abef4838f4590e8d6421069816cc99bec460"),
        ("website-hero.js", "dad41af6d6d2d421afc7a07042eeb7b8cc301d9e"),
        ("website-locale.js", "451ab3500e55129f4ccedf4de7ec3d818d09ea85"),
        ("website-product.css", "89db114f288ef3d2dd9e66a67072fae2aad1da77"),
        ("website-product.js", "7d8510923fe7d959f483610486bcac1ca5a12a9a"),
        ("website/HERO_REVISION_2026-10-27.md", "3fd19dca32f5d1758bb24491e1d566d33e5a3359"),
        ("website/README.md", "8e21d20e48e9904221fa4e214922ed3204134d90"),
        ("website/RESTORE_ART_DIRECTION_2026-10-27.md", "c4b404a16baf599e3365fb486b534eed768a0f81"),
        ("website/test-hero-layout.py", "99d162db1247a6a4578a87ac82992a23e0cc8914"),
        ("website/test-hero-motion.py", "da33a99adc0099efce9b2eeec4ec8afcb36f6196"),
        ("website/test-hero.py", "8d48acc7c765af2c58a5eb692b2a9df3a34abe9c"),
        ("website/test-product.cjs", "b1ca496f318e11a709561de15d3f8299e720d2bf"),
    ),
)


class AuditError(Exception):
    pass


def git_environment():
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


def regular_blob(oid):
    if not isinstance(oid, str) or not re.fullmatch(r"[0-9a-f]{40}", oid):
        raise AuditError("Invalid fixed blob identity")
    return {"mode": "100644", "type": "blob", "oid": oid}


def run_historical(repository, history):
    """Execute pinned bytes with the historical CLI; do not import live scripts."""
    repository = Path(repository).resolve()
    source = git(repository, "cat-file", "blob", history.blob)
    with tempfile.TemporaryDirectory(prefix="riftlet-unified-audit-") as directory:
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
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=git_environment(), timeout=180,
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
    """Custom policies are only an in-process seam for isolated Git fixtures."""
    report = {"schemaVersion": 1, "result": "FAIL", "revisionRequested": revision,
              "reviewedSource": policy.reviewed_source, "mainRevision": policy.main_revision,
              "metadataExceptions": sorted(METADATA_PATHS), "checks": [], "historicalAudits": {}}
    checks = report["checks"]

    def check(identifier, passed, **details):
        checks.append({"id": identifier, "result": "PASS" if passed else "FAIL", **details})

    def compare(identifier, expected, actual):
        protected = set(expected) - METADATA_PATHS
        candidate = set(actual) - METADATA_PATHS
        check(identifier + ":exact-paths", protected == candidate,
              unexpected=sorted(candidate - protected), missing=sorted(protected - candidate))
        different = {path: {"expected": expected[path], "actual": actual.get(path)}
                     for path in sorted(protected) if actual.get(path) != expected[path]}
        check(identifier + ":exact-objects", not different,
              protectedFileCount=len(protected), differences=different)

    def metadata(identifier, tree):
        for path in sorted(METADATA_PATHS):
            obj = tree.get(path)
            check(identifier + ":regular-metadata:" + path,
                  bool(obj) and obj["mode"] == "100644" and obj["type"] == "blob")

    try:
        resolved = commit(repository, revision)
        report["revision"] = resolved
        report["tree"] = git(repository, "rev-parse", resolved + "^{tree}").decode("ascii").strip()
        actual = objects(repository, resolved)
        if not policy.histories:
            raise AuditError("Historical audit list must not be empty")
        seen_paths, seen_names = set(), set()
        for history in policy.histories:
            if (not valid_path(history.path) or history.path in METADATA_PATHS
                    or history.path in seen_paths or history.name in seen_names):
                raise AuditError("Invalid historical audit policy")
            seen_paths.add(history.path); seen_names.add(history.name)
            fixed_commit(repository, history.revision, history.name)
            expected_gate = regular_blob(history.blob)
            if objects(repository, history.revision).get(history.path) != expected_gate:
                raise AuditError("Historical audit pin does not match original tree: " + history.name)
            passed, historical_report = run_historical(repository, history)
            report["historicalAudits"][history.name] = historical_report
            check("historical:" + history.name, passed,
                  originalRevision=history.revision, originalAudit=expected_gate)
            check("historical-gate-unchanged:" + history.name,
                  actual.get(history.path) == expected_gate,
                  expected=expected_gate, actual=actual.get(history.path))
            check("ancestor:" + history.name, git(repository, "merge-base", "--is-ancestor",
                                                   history.revision, resolved, ancestor=True))

        fixed_commit(repository, policy.reviewed_source, "reviewed composition source")
        check("ancestor:reviewed-source", git(repository, "merge-base", "--is-ancestor",
                                             policy.reviewed_source, resolved, ancestor=True))
        approved = objects(repository, policy.reviewed_source)
        for history in policy.histories:
            check("reviewed-source-ancestor:" + history.name,
                  git(repository, "merge-base", "--is-ancestor", history.revision,
                      policy.reviewed_source, ancestor=True))
        metadata("reviewed", approved); metadata("candidate", actual)

        fixed_commit(repository, policy.main_revision, "main website source")
        overlay = {}
        main_tree = objects(repository, policy.main_revision)
        for path, oid in policy.main_objects:
            if (not valid_path(path) or path in METADATA_PATHS or path in seen_paths or path in overlay):
                raise AuditError("Invalid or duplicate main overlay path")
            overlay[path] = regular_blob(oid)
            if main_tree.get(path) != overlay[path]:
                raise AuditError("Main overlay pin does not match original tree: " + path)
        parents = git(repository, "show", "-s", "--format=%P", resolved).decode("ascii").strip().split()
        report["parents"] = parents
        expected = dict(approved)
        if policy.main_revision in parents:
            check("ci-merge:two-parents", len(parents) == 2 and len(set(parents)) == 2)
            if len(parents) != 2 or len(set(parents)) != 2:
                raise AuditError("The main overlay requires exactly two distinct parents")
            candidate_parent = next(parent for parent in parents if parent != policy.main_revision)
            check("ci-merge:reviewed-candidate-parent",
                  git(repository, "merge-base", "--is-ancestor", policy.reviewed_source,
                      candidate_parent, ancestor=True), candidateParent=candidate_parent)
            parent_tree = objects(repository, candidate_parent)
            metadata("ci-parent", parent_tree)
            compare("ci-parent", approved, parent_tree)
            expected.update(overlay)
            report["compositionMode"] = "fixed-main-test-merge"
            report["mainOverlayObjects"] = overlay
        else:
            report["compositionMode"] = "reviewed-candidate"
        compare("composition", expected, actual)
        report["protectedObjects"] = {path: expected[path] for path in sorted(expected) if path not in METADATA_PATHS}
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
    print("FINAL_PRODUCT_COMPOSITION_" + report["result"], file=sys.stderr)
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
