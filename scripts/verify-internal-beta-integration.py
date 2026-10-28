#!/usr/bin/env python3
"""Read-only audit of the reviewed internal Beta's committed Git composition.

No branch/event metadata, working-tree file, environment override or merge-parent
order supplies the expected source. The CLI pins the accepted source/evidence
commits, the seven approved UX files, and the separately reviewed Main blob.
A shallow checkout must fetch history
before this audit; missing objects fail closed. No fetch or repository write is
performed here.
"""

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
import sys


@dataclass(frozen=True)
class Policy:
    official: str
    acceptance: str
    feedback: str
    beta: str
    experience: str
    experience_evidence: str
    main_blob: str


# Changing any pin requires a new integration review, not a runtime override.
POLICY = Policy(
    official="e421e6687651c2fac1441410c1af2bd5b8151e55",
    acceptance="c177174e400064d8ec8bb79685c33d01c4e93b89",
    feedback="f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9",
    beta="b4bcfa41e8e237723b975d2a9a0059e955fa0c1f",
    experience="fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3",
    experience_evidence="8e1a1688e75db8c18965e073ae357010e7397a3a",
    main_blob="05fe28ec734ba0d8c040810c737b26715a33d5de",
)

SCREENSHOT_PATHS = (
    "Sources/RiftletCore", "Sources/RiftletCapture",
    "Sources/RiftletAdapters", "Sources/CSQLite",
    "Resources", "ThirdPartyNotices", "Tests/RiftletCoreTests",
    "Tests/RiftletCaptureTests", "Tests/RiftletAdaptersTests", "Tests/WebPageProgram",
)
# Only these individual UX objects move to fa74f3c. Every other object in their
# original directories remains pinned to e421e668; these are not directory-wide
# exceptions. Main is checked separately against the reviewed combined blob.
EXPERIENCE_PATHS = (
    "Sources/RiftletApp/ProductStatus.swift",
    "Sources/RiftletApp/SelectionSubmissionQueue.swift",
    "Sources/RiftletGUIAcceptance/AcceptanceMain.swift",
    "Sources/RiftletUI/RiftPanelController.swift",
    "Tests/RiftletAppTests/ProductStatusTests.swift",
    "Tests/RiftletAppTests/SelectionSubmissionQueueTests.swift",
    "Tests/RiftletUITests/PresentationBoundaryTests.swift",
)
EXPERIENCE_ROOTS = (
    "Sources/RiftletUI", "Sources/RiftletGUIAcceptance",
    "Tests/RiftletUITests", "Tests/RiftletAppTests",
)
FEEDBACK_PATHS = (
    "Sources/RiftletFeedback", "Sources/RiftletFeedbackUI", "Sources/RiftletFeedbackDemo",
    "Sources/RiftletApp/FeedbackHost.swift", "Tests/RiftletFeedbackTests",
    "Tests/RiftletFeedbackUITests", "Tests/FeedbackIsolation", "services/feedback",
    "Package.swift", "scripts/build-feedback-demo.sh", "scripts/verify-feedback-isolation.sh",
)
EVIDENCE_PATH = "engineering/evidence/2026-10-28-system-screenshot-swallow"
EXPERIENCE_EVIDENCE_PATH = "engineering/evidence/2026-10-28-beta-ux"
APP_PATH = "Sources/RiftletApp"
MAIN_PATH = APP_PATH + "/RiftletMain.swift"
HOST_PATH = APP_PATH + "/FeedbackHost.swift"


class AuditError(Exception):
    pass


def git(repository, *arguments, allow_not_ancestor=False):
    # Replacement refs must not substitute different objects for the fixed pins.
    process = subprocess.run(
        ["git", "--no-replace-objects", "-C", str(repository), *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if allow_not_ancestor and process.returncode in (0, 1):
        return process.returncode == 0
    if process.returncode != 0:
        detail = process.stderr.decode("utf-8", errors="replace").strip()
        raise AuditError("git " + arguments[0] + " failed: " + detail)
    return process.stdout


def commit(repository, revision):
    # --end-of-options ensures a caller's revision cannot inject Git options.
    return git(repository, "rev-parse", "--verify", "--end-of-options",
               revision + "^{commit}").decode("ascii").strip()


def objects(repository, revision, paths, recursive=False):
    arguments = ["ls-tree", "-z"]
    if recursive:
        arguments.append("-r")
    raw = git(repository, *arguments, revision, "--", *paths)
    result = {}
    for item in raw.split(b"\0"):
        if not item:
            continue
        metadata, path = item.split(b"\t", 1)
        mode, kind, oid = metadata.decode("ascii").split()
        result[path.decode("utf-8")] = {"mode": mode, "type": kind, "oid": oid}
    return result


def audit(repository, revision="HEAD", policy=POLICY):
    """Inspect committed objects; the explicit policy argument is for Git fixtures.

    The executable CLI always uses POLICY above and exposes no pin overrides.
    """
    report = {
        "schemaVersion": 2,
        "result": "FAIL",
        "revisionRequested": revision,
        "policy": {"official": policy.official, "acceptance": policy.acceptance,
                   "feedback": policy.feedback, "beta": policy.beta,
                   "experience": policy.experience,
                   "experienceEvidence": policy.experience_evidence,
                   "mainBlob": policy.main_blob},
        "checks": [],
    }
    checks = report["checks"]

    def check(identifier, passed, **details):
        checks.append({"id": identifier, "result": "PASS" if passed else "FAIL", **details})

    try:
        resolved = commit(repository, revision)
        report["revision"] = resolved
        report["tree"] = git(repository, "rev-parse", resolved + "^{tree}").decode("ascii").strip()
        report["parents"] = git(repository, "show", "-s", "--format=%P", resolved).decode("ascii").strip().split()
        for name in ("official", "acceptance", "feedback", "beta",
                     "experience", "experience_evidence"):
            anchor = getattr(policy, name)
            if not re.fullmatch(r"[0-9a-f]{40}", anchor) or commit(repository, anchor) != anchor:
                raise AuditError("Invalid fixed commit identity: " + name)
            is_ancestor = git(repository, "merge-base", "--is-ancestor", anchor, resolved,
                              allow_not_ancestor=True)
            check("ancestor:" + name, is_ancestor, expected=anchor)
        if not re.fullmatch(r"[0-9a-f]{40}", policy.main_blob):
            raise AuditError("Invalid fixed Main blob identity")

        for group, expected_revision, paths in (
            ("screenshot", policy.official, SCREENSHOT_PATHS),
            ("experience", policy.experience, EXPERIENCE_PATHS),
            ("feedback", policy.feedback, FEEDBACK_PATHS),
            ("acceptance", policy.acceptance, (EVIDENCE_PATH,)),
            ("experience-evidence", policy.experience_evidence, (EXPERIENCE_EVIDENCE_PATH,)),
        ):
            expected = objects(repository, expected_revision, paths)
            actual = objects(repository, resolved, paths)
            for path in paths:
                # Both missing is a failure, rather than a vacuous equality.
                check(group + ":" + path,
                      path in expected and actual.get(path) == expected[path],
                      expected=expected.get(path), actual=actual.get(path))

        def check_unmodified_files(identifier, root, exclusions):
            expected = objects(repository, policy.official, (root,), recursive=True)
            actual = objects(repository, resolved, (root,), recursive=True)
            # A directory containing only an approved file may become empty
            # after exclusions; its original object must nevertheless exist.
            original_exists = bool(expected)
            for entries in (expected, actual):
                for path in exclusions:
                    entries.pop(path, None)
            missing = sorted(set(expected) - set(actual))
            added = sorted(set(actual) - set(expected))
            changed = sorted(path for path in set(expected) & set(actual)
                             if expected[path] != actual[path])
            check(identifier, original_exists and not (missing or added or changed),
                  expectedFileCount=len(expected), actualFileCount=len(actual),
                  missing=missing, added=added, changed=changed)

        for root in EXPERIENCE_ROOTS:
            check_unmodified_files("experience:unmodified:" + root, root, EXPERIENCE_PATHS)
        check_unmodified_files("app:original-files", APP_PATH,
                               (*EXPERIENCE_PATHS, MAIN_PATH, HOST_PATH))

        actual_main = objects(repository, resolved, (MAIN_PATH,)).get(MAIN_PATH)
        expected_main = {"mode": "100644", "type": "blob", "oid": policy.main_blob}
        check("app:reviewed-main", actual_main == expected_main,
              expected=expected_main, actual=actual_main)
    except (AuditError, OSError, UnicodeError, ValueError) as error:
        check("audit:git-inputs", False, error=str(error))

    report["result"] = "PASS" if checks and all(item["result"] == "PASS" for item in checks) else "FAIL"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD", help="committed revision to inspect (default: HEAD)")
    parser.add_argument("--repository", type=Path, default=Path("."), help="Git repository/worktree (default: current directory)")
    arguments = parser.parse_args()
    report = audit(arguments.repository, arguments.revision)
    print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
    print("INTERNAL_BETA_INTEGRATION_" + report["result"], file=sys.stderr)
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
