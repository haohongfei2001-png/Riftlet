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
    feedback_updates: tuple[tuple[str, str], ...] = ()


# Changing any pin requires a new integration review, not a runtime override.
POLICY = Policy(
    official="e421e6687651c2fac1441410c1af2bd5b8151e55",
    acceptance="c177174e400064d8ec8bb79685c33d01c4e93b89",
    feedback="f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9",
    beta="b4bcfa41e8e237723b975d2a9a0059e955fa0c1f",
    experience="fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3",
    experience_evidence="8e1a1688e75db8c18965e073ae357010e7397a3a",
    main_blob="05fe28ec734ba0d8c040810c737b26715a33d5de",
    # 2026-10-29 independently reviewed Feedback reliability/privacy repairs.
    # All other Feedback files remain pinned to the original f195beb delivery.
    feedback_updates=(
        ("Sources/RiftletFeedback/FeedbackEngine.swift", "364bf1ad9f47ea820a82522ad7af3ab8a8ef7a91"),
        ("Sources/RiftletFeedback/FeedbackStore.swift", "e00e5722d09b38257777aa105828ced889d36ff2"),
        ("Sources/RiftletFeedbackUI/FeedbackWindowController.swift", "b9f2bb1418112f6dae35a2d4a33a9ef28ff7e39e"),
        ("Tests/RiftletFeedbackTests/FeedbackAutomaticRetryTests.swift", "3cacdac27aac9e8bd6ef9396f5f5c3e72ed352f3"),
        ("Tests/RiftletFeedbackTests/FeedbackPrivacyCleanupTests.swift", "2ec47c6f7c984194e89f9bcadc26cc1ce4eef059"),
        ("Tests/RiftletFeedbackTests/FeedbackTests.swift", "507fe2ff7485078ab3b6d4dd11b12448c70559ca"),
        ("Tests/RiftletFeedbackUITests/FeedbackCloseTests.swift", "657d62ff9fde0863064a959326324d0938abc971"),
        ("Tests/RiftletFeedbackUITests/FeedbackWindowTests.swift", "437712acf5eeca9c4aaa4961ed1b35ed275e5333"),
        ("services/feedback/delivery.mjs", "11c853d9a72cc8d9e2ee63be7efaf0e42a476d6c"),
        ("services/feedback/feedback.test.mjs", "4ff61e5f3d0125c03feda989a9559ca4c42209af"),
        ("services/feedback/wrangler.delivery.jsonc", "6fdd3bba7a3a1ca04149428bf420df222385ffd7"),
        ("services/feedback/README.md", "bf1fad3c7343ec931a5da8fe2e37ff4cbfc697ec"),
    ),
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
                   "mainBlob": policy.main_blob,
                   "feedbackUpdates": dict(policy.feedback_updates)},
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
        feedback_updates = dict(policy.feedback_updates)
        if len(feedback_updates) != len(policy.feedback_updates):
            raise AuditError("Duplicate fixed Feedback update path")
        for path, oid in feedback_updates.items():
            if (not any(path == root or path.startswith(root + "/") for root in FEEDBACK_PATHS)
                    or any(part in ("", ".", "..") for part in path.split("/"))
                    or not re.fullmatch(r"[0-9a-f]{40}", oid)
                    or git(repository, "cat-file", "-t", oid).strip() != b"blob"):
                raise AuditError("Invalid fixed Feedback update: " + path)

        for group, expected_revision, paths in (
            ("screenshot", policy.official, SCREENSHOT_PATHS),
            ("experience", policy.experience, EXPERIENCE_PATHS),
            ("feedback", policy.feedback, FEEDBACK_PATHS),
            ("acceptance", policy.acceptance, (EVIDENCE_PATH,)),
            ("experience-evidence", policy.experience_evidence, (EXPERIENCE_EVIDENCE_PATH,)),
        ):
            if group == "feedback" and feedback_updates:
                # Preserve every original object; approve only the reviewed
                # text-file blobs, including explicit additions. A neighbouring
                # mutation/addition/deletion still fails this exact comparison.
                for root in paths:
                    expected = objects(repository, expected_revision, (root,), recursive=True)
                    original_exists = bool(expected)
                    actual = objects(repository, resolved, (root,), recursive=True)
                    for path, oid in feedback_updates.items():
                        if path == root or path.startswith(root + "/"):
                            expected[path] = {"mode": "100644", "type": "blob", "oid": oid}
                    missing = sorted(set(expected) - set(actual))
                    added = sorted(set(actual) - set(expected))
                    changed = sorted(path for path in set(expected) & set(actual)
                                     if expected[path] != actual[path])
                    check(group + ":" + root, original_exists and not (missing or added or changed),
                          expectedFileCount=len(expected), actualFileCount=len(actual),
                          missing=missing, added=added, changed=changed)
                continue
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
