#!/usr/bin/env python3
"""Verify only the independently reviewed attachment-reliability increment.

The formal PR #15 checker is immutable and runs at its exact 73251d0 checkpoint.
This separate checker does not grant attachment admission or claim real-device
acceptance. Every other object must equal that checkpoint or the exact reviewed
technical source. Its pin child changes only the two review literals below.
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


GATE_PATH = "scripts/verify-cold-attachment-scope.py"
BASELINE = "73251d034c8da8f486d09083b048a35cdee39bc0"
BASELINE_GATE_PATH = "scripts/verify-final-product-composition.py"
BASELINE_GATE_BLOB = "6e9b3a8383cc6c780acc48e299b0bc289dcfcd0e"
REVIEWED_SOURCE = "6d9649c46a2f6655fd5b91afe6c306a075a2f5b2"
REVIEWED_TREE = "8467441078096d7da972170750c49c508e2997b2"

EDITED_PATHS = frozenset((
    ".github/workflows/native-foundation.yml",
    ".github/workflows/feedback-v01.yml",
    "Sources/RiftletAdapters/MainWorldCommandEnvelope.swift",
    "Sources/RiftletAdapters/ChromeAppleEventsExecutor.swift",
    "Sources/RiftletApp/SelectionSubmissionQueue.swift",
    "Tests/RiftletAdaptersTests/MainWorldCommandEnvelopeTests.swift",
    "Tests/RiftletAdaptersTests/MainWorldReceiptReaderTests.swift",
    "Tests/RiftletAppTests/SelectionSubmissionQueueTests.swift",
    "Tests/WebPageProgram/acceptance-program.test.cjs",
    "Tests/ColdAttachmentIsolation/test_scope.py",
    GATE_PATH,
))
PRESERVED_JOBS = (
    (".github/workflows/native-foundation.yml", b"  macos:\n"),
    (".github/workflows/feedback-v01.yml", b"  feedback:\n"),
)


@dataclass(frozen=True)
class Policy:
    baseline: str
    baseline_gate_path: str
    baseline_gate_blob: str
    reviewed_source: str | None
    reviewed_tree: str | None
    edited_paths: frozenset
    preserved_jobs: tuple


POLICY = Policy(BASELINE, BASELINE_GATE_PATH, BASELINE_GATE_BLOB,
                REVIEWED_SOURCE, REVIEWED_TREE, EDITED_PATHS, PRESERVED_JOBS)


class AuditError(Exception):
    pass


def git_environment():
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    return env


def git(repository, *arguments, ancestor=False):
    result = subprocess.run(["git", "--no-replace-objects", "-C", str(repository), *arguments],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=git_environment())
    if ancestor and result.returncode in (0, 1):
        return result.returncode == 0
    if result.returncode:
        raise AuditError("Git object query failed: " + arguments[0])
    return result.stdout


def resolve(repository, revision):
    return git(repository, "rev-parse", "--verify", "--end-of-options",
               revision + "^{commit}").decode().strip()


def fixed_oid(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}", value):
        raise AuditError("Missing or invalid exact review/baseline identity")


def objects(repository, revision):
    result = {}
    for entry in git(repository, "ls-tree", "-r", "-z", revision).split(b"\0"):
        if entry:
            header, path = entry.split(b"\t", 1)
            mode, kind, oid = header.decode().split()
            result[path.decode()] = {"mode": mode, "type": kind, "oid": oid}
    return result


def parents(repository, revision):
    return git(repository, "show", "-s", "--format=%P", revision).decode().split()


def difference(before, after):
    return {path: {"before": before.get(path), "after": after.get(path)}
            for path in sorted(set(before) | set(after)) if before.get(path) != after.get(path)}


def pinned_gate(source, policy):
    for name, value in (("REVIEWED_SOURCE", policy.reviewed_source),
                        ("REVIEWED_TREE", policy.reviewed_tree)):
        old = (name + " = None\n").encode()
        if source.count(old) != 1:
            raise AuditError("Source policy must contain exactly one empty " + name)
        source = source.replace(old, (name + ' = "' + value + '"\n').encode())
    return source


def baseline_audit(repository, policy):
    """Execute the original fixed blob, not a mutable working-tree import."""
    payload = git(repository, "cat-file", "blob", policy.baseline_gate_blob)
    with tempfile.TemporaryDirectory(prefix="riftlet-cold-baseline-") as directory:
        temporary = Path(directory) / "baseline.py"
        temporary.write_bytes(payload)
        wrapper = (
            "import pathlib, sys\n"
            "payload, logical, revision, repository = sys.argv[1:]\n"
            "sys.argv = [logical, revision, '--repository', repository]\n"
            "namespace = {'__name__': '__main__', '__file__': logical}\n"
            "exec(compile(pathlib.Path(payload).read_bytes(), logical, 'exec'), namespace)\n"
        )
        process = subprocess.run(
            [sys.executable, "-B", "-c", wrapper, str(temporary),
             str(Path(repository).resolve() / policy.baseline_gate_path),
             policy.baseline, str(Path(repository).resolve())],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=git_environment(), timeout=240)
    report = json.loads(process.stdout)
    checks = report.get("checks", []) if isinstance(report, dict) else []
    good = (isinstance(report, dict) and process.returncode == 0 and report.get("result") == "PASS"
            and report.get("revision") == policy.baseline and bool(checks)
            and all(isinstance(item, dict) and item.get("result") == "PASS" for item in checks))
    return good, report


def audit(repository, revision="HEAD", policy=POLICY):
    """A custom policy is an in-process seam for isolated Git rejection tests."""
    report = {"schemaVersion": 1, "result": "FAIL", "baseline": policy.baseline,
              "reviewedSource": policy.reviewed_source, "reviewedTree": policy.reviewed_tree,
              "scope": "technical-delta-only-no-upload-admission", "checks": []}

    def check(name, ok, **details):
        report["checks"].append({"id": name, "result": "PASS" if ok else "FAIL", **details})

    try:
        for oid in (policy.baseline, policy.baseline_gate_blob,
                    policy.reviewed_source, policy.reviewed_tree):
            fixed_oid(oid)
        for revision_pin in (policy.baseline, policy.reviewed_source):
            if resolve(repository, revision_pin) != revision_pin:
                raise AuditError("Revision does not resolve to its exact commit")
        actual = resolve(repository, revision)
        report["revision"] = actual
        report["tree"] = git(repository, "rev-parse", actual + "^{tree}").decode().strip()
        base = objects(repository, policy.baseline)
        source = objects(repository, policy.reviewed_source)
        expected_gate = {"mode": "100644", "type": "blob", "oid": policy.baseline_gate_blob}
        check("original-final-gate-immutable", base.get(policy.baseline_gate_path) == expected_gate
              and source.get(policy.baseline_gate_path) == expected_gate)
        if not report["checks"][-1]["result"] == "PASS":
            raise AuditError("Original formal checker changed")
        passed, historical = baseline_audit(repository, policy)
        check("original-formal-baseline-admission", passed)
        report["formalBaselineAudit"] = historical
        check("reviewed-source-ancestry", git(repository, "merge-base", "--is-ancestor",
              policy.baseline, policy.reviewed_source, ancestor=True))
        check("reviewed-source-exact-tree", git(repository, "rev-parse",
              policy.reviewed_source + "^{tree}").decode().strip() == policy.reviewed_tree)
        delta = difference(base, source)
        check("reviewed-source-exact-path-set", set(delta) == set(policy.edited_paths), differences=delta)
        check("reviewed-delta-only-regular-files", all(
            source.get(path, {}).get("mode") == "100644"
            and source.get(path, {}).get("type") == "blob" for path in policy.edited_paths))
        for path, marker in policy.preserved_jobs:
            old = git(repository, "show", policy.baseline + ":" + path)
            new = git(repository, "show", policy.reviewed_source + ":" + path)
            check("unchanged-verification-job:" + path, old.count(marker) == new.count(marker) == 1
                  and old.split(marker, 1)[1] == new.split(marker, 1)[1])

        actual_parents = parents(repository, actual)
        candidate = actual
        if len(actual_parents) == 2:
            # A PR targeting the unchanged formal line is the only test merge.
            if actual_parents[0] != policy.baseline or actual_parents[0] == actual_parents[1]:
                raise AuditError("Unreviewed integration base or merge topology")
            candidate = actual_parents[1]
            check("pr-merge-equals-technical-head", objects(repository, actual) == objects(repository, candidate))
            report["compositionMode"] = "exact-baseline-pr-test-merge"
        else:
            report["compositionMode"] = "technical-pin-child"
        check("only-reviewed-source-parent", parents(repository, candidate) == [policy.reviewed_source])
        expected = dict(source)
        raw_gate = git(repository, "show", policy.reviewed_source + ":" + GATE_PATH)
        pinned = pinned_gate(raw_gate, policy)
        # Hash without writing Git objects. The two pin literals are the entire
        # allowed post-review difference, including this policy's own bytes.
        import hashlib
        oid = hashlib.sha1(b"blob " + str(len(pinned)).encode() + b"\0" + pinned).hexdigest()
        expected[GATE_PATH] = {"mode": "100644", "type": "blob", "oid": oid}
        candidate_objects = objects(repository, candidate)
        remaining = difference(expected, candidate_objects)
        check("pin-child-exact-objects", not remaining, differences=remaining,
              protectedObjectCount=len(expected), expectedGateBlob=oid)
        report["technicalHead"] = candidate
        report["sourceDelta"] = delta
    except (AuditError, OSError, ValueError, KeyError, TypeError, UnicodeError, subprocess.TimeoutExpired) as error:
        check("audit-inputs", False, error=str(error))
    if report["checks"] and all(item["result"] == "PASS" for item in report["checks"]):
        report["result"] = "PASS"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD")
    parser.add_argument("--repository", type=Path, default=Path("."))
    args = parser.parse_args()
    report = audit(args.repository, args.revision)
    print(json.dumps(report, indent=2, sort_keys=True))
    print("COLD_ATTACHMENT_SCOPE_" + report["result"], file=sys.stderr)
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
