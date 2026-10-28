#!/usr/bin/env python3
"""Read-only, exact-path audit of the native two-mode arrival increment.

The former internal-Beta audit is retained byte-for-byte and executed from its
pinned committed blob against the pinned Beta baseline. This second layer checks
the entire new committed tree: only individually reviewed additions/modifications
are allowed; no directory is exempted. Branch names, environment variables,
working-tree bytes and PR metadata cannot supply the expected policy.

The executable exposes no source-pin overrides. Tests inject independent Git
fixtures through the Python API. Missing Git history fails closed; no fetch,
checkout, index change or other repository mutation occurs here.
"""

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Optional


BASELINE_AUDIT_PATH = "scripts/verify-internal-beta-integration.py"
REVIEWED_TOOL_PATHS = frozenset((
    ".github/workflows/feedback-v01.yml",
    ".github/workflows/native-foundation.yml",
    "scripts/arrival-source-probe.swift",
))


@dataclass(frozen=True)
class Policy:
    baseline: str
    baseline_audit_blob: str
    # Exact paths and exact delta kinds. Renames/deletions are never authorized.
    changes: tuple
    # Set to the reviewed source-only commit after that commit is created.
    # The audit itself/evidence documentation can then be committed separately.
    reviewed_source: Optional[str] = None


POLICY = Policy(
    baseline="1920e0562db893a3292af89a89270a26ddb46a5f",
    baseline_audit_blob="94b09b58f412a7778c2e63ec46c23291b4c3bc99",
    changes=(
        ("M", ".github/workflows/feedback-v01.yml"),
        ("M", ".github/workflows/native-foundation.yml"),
        ("M", "Sources/RiftletApp/RiftletMain.swift"),
        ("M", "Sources/RiftletCapture/CaptureService.swift"),
        ("M", "Sources/RiftletUI/RiftPanelController.swift"),
        ("M", "Sources/RiftletUI/ThumbnailCache.swift"),
        ("M", "Tests/RiftletUITests/RiftLifecycleTests.swift"),
        ("M", "Tests/RiftletUITests/RiftInputIslandTests.swift"),
        ("M", "Tests/RiftletUITests/PresentationBoundaryTests.swift"),
        ("A", "Sources/RiftletApp/ArrivalMotionPreferences.swift"),
        ("A", "Sources/RiftletApp/ArrivalCaptureBridge.swift"),
        ("A", "Sources/RiftletCapture/ScreenshotSourceGeometry.swift"),
        ("A", "Sources/RiftletUI/ArrivalMotionMode.swift"),
        ("A", "Sources/RiftletUI/ArrivalMotionSettingsController.swift"),
        ("A", "Sources/RiftletUI/MagnetMotionPlan.swift"),
        ("A", "Sources/RiftletUI/MagnetFlightPresenter.swift"),
        ("A", "Tests/RiftletCaptureTests/ScreenshotSourceGeometryTests.swift"),
        ("A", "Tests/RiftletCaptureTests/CaptureArrivalObservationTests.swift"),
        ("A", "Tests/RiftletAppTests/ArrivalMotionPreferencesTests.swift"),
        ("A", "Tests/RiftletUITests/ArrivalModesTests.swift"),
        ("A", "Tests/RiftletUITests/MagnetMotionPlanTests.swift"),
        ("A", "Tests/RiftletUITests/MagnetFlightPresenterTests.swift"),
        ("A", "Tests/ArrivalIsolation/test_integration.py"),
        ("A", "docs/ARRIVAL_NATIVE_LOCAL_ACCEPTANCE.md"),
        ("A", "docs/ARRIVAL_NATIVE_IMPLEMENTATION.md"),
        ("A", "docs/ARRIVAL_SOURCE_GEOMETRY.md"),
        ("A", "engineering/evidence/2026-10-28-arrival-native/branch-heads-start.json"),
        ("A", "engineering/evidence/2026-10-28-arrival-native/validation.json"),
        ("A", "engineering/evidence/2026-10-28-arrival-native/README.md"),
        ("A", "scripts/arrival-source-probe.swift"),
        ("A", "scripts/verify-arrival-integration.py"),
    ),
)


class AuditError(Exception):
    pass


def git(repository, *arguments, ancestor=False):
    process = subprocess.run(
        ["git", "--no-replace-objects", "-C", str(repository), *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if ancestor and process.returncode in (0, 1):
        return process.returncode == 0
    if process.returncode != 0:
        raise AuditError("git " + arguments[0] + " failed: "
                         + process.stderr.decode("utf-8", errors="replace").strip())
    return process.stdout


def commit(repository, revision):
    return git(repository, "rev-parse", "--verify", "--end-of-options",
               revision + "^{commit}").decode("ascii").strip()


def objects(repository, revision):
    result = {}
    for item in git(repository, "ls-tree", "-r", "-z", revision).split(b"\0"):
        if not item:
            continue
        metadata, raw_path = item.split(b"\t", 1)
        mode, kind, oid = metadata.decode("ascii").split()
        result[raw_path.decode("utf-8")] = {"mode": mode, "type": kind, "oid": oid}
    return result


def fixed_commit(repository, value, name):
    if not re.fullmatch(r"[0-9a-f]{40}", value) or commit(repository, value) != value:
        raise AuditError("Invalid pinned commit: " + name)


def run_baseline_audit(repository, policy, expected_object):
    if not re.fullmatch(r"[0-9a-f]{40}", policy.baseline_audit_blob):
        raise AuditError("Invalid baseline audit blob identity")
    if expected_object != {"mode": "100644", "type": "blob", "oid": policy.baseline_audit_blob}:
        raise AuditError("Pinned baseline audit object does not match baseline")
    # Read the immutable Git object, not the candidate checkout's executable.
    source = git(repository, "cat-file", "blob", policy.baseline_audit_blob)
    with tempfile.TemporaryDirectory(prefix="riftlet-arrival-baseline-audit-") as directory:
        executable = Path(directory) / "baseline-audit.py"
        executable.write_bytes(source)
        process = subprocess.run(
            [sys.executable, str(executable), policy.baseline,
             "--repository", str(Path(repository).resolve())],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    try:
        report = json.loads(process.stdout)
    except (ValueError, UnicodeError) as error:
        raise AuditError("Baseline audit emitted no structured result") from error
    checks = report.get("checks", [])
    passed = (process.returncode == 0 and report.get("result") == "PASS"
              and report.get("revision") == policy.baseline and checks
              and all(item.get("result") == "PASS" for item in checks))
    return passed, report


def audit(repository, revision="HEAD", policy=POLICY):
    """Audit committed objects. The optional policy argument is for Git fixtures."""
    report = {
        "schemaVersion": 1, "result": "FAIL", "revisionRequested": revision,
        "policy": {"baseline": policy.baseline,
                   "baselineAuditBlob": policy.baseline_audit_blob,
                   "reviewedSource": policy.reviewed_source,
                   "changes": [{"kind": kind, "path": path} for kind, path in policy.changes]},
        "checks": [],
    }
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
        before, after = objects(repository, policy.baseline), objects(repository, resolved)
        passed, baseline_report = run_baseline_audit(repository, policy,
                                                    before.get(BASELINE_AUDIT_PATH))
        report["baselineAudit"] = baseline_report
        check("baseline:original-audit", passed,
              baselineCheckCount=len(baseline_report.get("checks", [])))

        allowlist = {}
        for kind, path in policy.changes:
            if (kind not in ("A", "M") or not path or path.startswith("/")
                    or ".." in path.split("/") or path in allowlist
                    or any(symbol in path for symbol in ("*", "?", "[", "\\"))):
                raise AuditError("Invalid exact-path delta policy")
            allowlist[path] = kind
        # The historical audit cannot be substituted, even by an allowlist edit.
        check("baseline:audit-unchanged", after.get(BASELINE_AUDIT_PATH) == before.get(BASELINE_AUDIT_PATH)
              and BASELINE_AUDIT_PATH not in allowlist)
        delta = {}
        for path in set(before) | set(after):
            if before.get(path) == after.get(path):
                continue
            delta[path] = "A" if path not in before else "D" if path not in after else "M"
        report["actualChanges"] = [{"kind": delta[path], "path": path} for path in sorted(delta)]
        missing = sorted(set(allowlist) - set(delta))
        unexpected = sorted(set(delta) - set(allowlist))
        wrong_kind = sorted(path for path in set(delta) & set(allowlist)
                            if delta[path] != allowlist[path])
        check("delta:exact-paths", not (missing or unexpected or wrong_kind),
              missingExpectedChanges=missing, unexpectedChanges=unexpected, wrongDeltaKind=wrong_kind)
        for path, kind in sorted(allowlist.items()):
            actual = after.get(path)
            expected_mode = before[path]["mode"] if kind == "M" and path in before else "100644"
            safe = (actual is not None and actual["type"] == "blob" and actual["mode"] == expected_mode
                    and expected_mode in ("100644", "100755")
                    and (path in before) == (kind == "M"))
            check("delta:regular-file:" + path, safe, actual=actual)

        # All existing source, test, evidence, config and scripts outside this
        # closed list are exact baseline Git objects, including type and mode.
        protected = sorted(set(before) - set(allowlist))
        different = [path for path in protected if before[path] != after.get(path)]
        check("baseline:all-other-objects", not different,
              protectedFileCount=len(protected), changedOrMissing=different)

        if policy.reviewed_source is not None:
            fixed_commit(repository, policy.reviewed_source, "reviewed source")
            check("ancestor:reviewed-source", git(repository, "merge-base", "--is-ancestor",
                                                  policy.reviewed_source, resolved, ancestor=True))
            approved = objects(repository, policy.reviewed_source)
            for path in sorted(allowlist):
                if path.startswith(("Sources/", "Tests/")) or path in REVIEWED_TOOL_PATHS:
                    check("reviewed-source:" + path,
                          path in approved and after.get(path) == approved[path],
                          expected=approved.get(path), actual=after.get(path))
    except (AuditError, OSError, UnicodeError, ValueError, KeyError, TypeError) as error:
        check("audit:git-inputs", False, error=str(error))

    report["result"] = "PASS" if checks and all(item["result"] == "PASS" for item in checks) else "FAIL"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD", help="committed revision to inspect")
    parser.add_argument("--repository", type=Path, default=Path("."), help="Git repository/worktree")
    arguments = parser.parse_args()
    report = audit(arguments.repository, arguments.revision)
    print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
    print("ARRIVAL_INTEGRATION_" + report["result"], file=sys.stderr)
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
