#!/usr/bin/env python3
"""Audit the explicitly reviewed capture-entry increment over the fixed Beta.

The historical Beta audit still runs against its unchanged accepted commit.
This audit then checks ancestry, the complete changed-path set, and exact Git
objects for the newly reviewed runtime, tests, workflows and visual reference.
No event metadata, environment variable or CLI option can replace those pins.
Documentation and this review gate are the only non-source metadata exceptions;
changing the gate or its pins requires a new source review.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import types

BASELINE = "1920e0562db893a3292af89a89270a26ddb46a5f"


def git_environment():
    # -C does not override GIT_DIR. Do not allow a CI/job environment to redirect
    # object lookup to a different repository, alternate object store or namespace.
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = os.devnull
    return environment


# Load the unchanged historical implementation from its accepted Git object,
# never a possibly edited working-tree Python module.
_historical = subprocess.check_output(
    ["git", "--no-replace-objects", "-C", str(Path(__file__).resolve().parents[1]),
     "show", BASELINE + ":scripts/verify-internal-beta-integration.py"], env=git_environment())
beta = types.ModuleType("internal_beta_audit")
sys.modules[beta.__name__] = beta
exec(compile(_historical, "git:" + BASELINE + ":verify-internal-beta-integration.py", "exec"), beta.__dict__)


def git(repository, *arguments, allow_not_ancestor=False):
    process = subprocess.run(["git", "--no-replace-objects", "-C", str(repository), *arguments],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=git_environment())
    if allow_not_ancestor and process.returncode in (0, 1):
        return process.returncode == 0
    if process.returncode != 0:
        raise beta.AuditError("git " + arguments[0] + " failed: " + process.stderr.decode("utf-8", errors="replace").strip())
    return process.stdout


# Keep the historical audit's checks and pins intact; only constrain its Git
# subprocess environment as well as the incremental checks' environment.
beta.git = git

# BEGIN REVIEWED OBJECTS
REVIEWED_OBJECTS = {
    ".github/workflows/feedback-v01.yml": "2d615808f3be8ef7a51ecb55eb40e76887a16dd7",
    ".github/workflows/native-foundation.yml": "6a2331f7e04025efdbd47ac34a838281f4b6b1b7",
    "Package.swift": "78f9b0289738d1f11f6acc825c8c27785548458b",
    "Resources/Info.plist": "ffd087594dc2c3c5b849beaed2f301fda091047b",
    "Sources/RiftletApp/RiftletMain.swift": "5f185bd9a51ce35620f37e4962b230a7e777b3c3",
    "Sources/RiftletApp/ScreenshotEntryHost.swift": "3b7745c85ab2afdaa7801124c57527fcb978766b",
    "Sources/RiftletApp/ScreenshotEntryPreferences.swift": "99f3c16cfd052f3790bebec65443e31cbdb7202a",
    "Sources/RiftletApp/ScreenshotMarkupController.swift": "f17b7d3d6819b65e5739e5f43cd21dc66db6064a",
    "Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift": "4002dc4bc85cc72dfaf6c25ef6ae0c442c6eda96",
    "Sources/RiftletCapture/CompletedScreenshotImporter.swift": "63e73e4fad3b93faa512b4efc8d07c36aa58b120",
    "Sources/RiftletCapture/InteractiveScreenshotController.swift": "6f5863790fed57d908f8dd9b6c2697f83b1e391b",
    "Sources/RiftletCapture/InteractiveScreenshotSystemCapture.swift": "67cf903985a93fc12e9b7ff24b4f03e417dd780f",
    "Sources/RiftletCapture/InteractiveScreenshotTypes.swift": "b757a21a50086f807d73e5965ef6507a6b271133",
    "Sources/RiftletCapture/StorageUsage.swift": "3a35ec428f286fe2adcf42c55662efebfa088741",
    "Sources/RiftletCore/Models.swift": "169ceefef82da5b50f52e681cf5652acafc8feb7",
    "Sources/RiftletCore/ReceiptPolicy.swift": "9e874c0995c3731123c9d9e44d0b16f8126b8335",
    "Sources/RiftletUI/RiftPanelController.swift": "033af73abae013ad118a6f316735133804d53bcb",
    "Sources/RiftletUI/ScreenshotEntryController.swift": "6de7330ed6a69f82fa16d2191f2c0ef8525be13f",
    "Sources/RiftletUI/ScreenshotEntryModel.swift": "67b72caa18fb151ead4d36b1369a0a6900ca4b2f",
    "Tests/CaptureEntryIsolation/test_integration.py": "dd29553591641c2818857bf7870c8824230aa563",
    "Tests/RiftletAppTests/ScreenshotEntryIntegrationTests.swift": "89bb42a028ea8e195cf3a394d86db8c667ad8348",
    "Tests/RiftletCaptureTests/CompletedScreenshotImporterTests.swift": "749e7e1ab5024037f0e5f3f5aa267df7c9b44bc9",
    "Tests/RiftletCaptureTests/InteractiveScreenshotTests.swift": "dbb17e110d712a2b3cb0b21cd61ef9351b1bf65a",
    "Tests/RiftletUITests/RiftCapturePresentationTests.swift": "e5b2a796949657b9e5c440a1d2b87319d3293928",
    "Tests/RiftletUITests/ScreenshotEntryControllerTests.swift": "b5eb3e7e369d5d476dfc21e877503c223d095dcc",
    "Tests/RiftletUITests/ScreenshotEntryModelTests.swift": "6c4b32735783711b9f481b55eb5f799a5e4536ab",
    "design/capture-entry/README.md": "f8297fa77e5ea28f9cefa6a5a2bdbf375408cf1d",
    "design/capture-entry/Riftlet-Capture-Entry.html": "e227da1cda6bfb13e0246c939b439b4518272d86",
    "design/capture-entry/THIRD_PARTY_NOTICES.md": "d2d7bcca83b96615d8ce4c59788a634f0940be34",
    "design/capture-entry/build.py": "4480e71d637a6cee165b63d460a6e16b887c5416",
    "design/capture-entry/source.html": "c9998c6db3f3c9d5216178b3860dd81892bb9167",
    "design/capture-entry/verify.cjs": "09a350bb9cadada8a2871f9741b694a43a339cdd"
}
# END REVIEWED OBJECTS

# These files contain the review policy and prose. They
# cannot authorize any source path beyond the exact reviewed object list above.
REVIEW_METADATA = frozenset({
    "scripts/verify-capture-entry-integration.py",
    "docs/CAPTURE_ENTRY_2026-10-28.md",
    "docs/EXECUTION_BOARD.md",
    "docs/DECISIONS.md",
})


def audit(repository, revision="HEAD", *, baseline=BASELINE,
          expected=None, metadata=REVIEW_METADATA, baseline_audit=None):
    """Explicit alternate policies are only for disposable Git test fixtures."""
    if expected is None:
        expected = REVIEWED_OBJECTS
    if baseline_audit is None:
        baseline_audit = beta.audit
    report = {"schemaVersion": 1, "result": "FAIL", "baseline": baseline,
              "revisionRequested": revision, "checks": []}
    checks = report["checks"]

    def check(identifier, passed, **details):
        checks.append({"id": identifier, "result": "PASS" if passed else "FAIL", **details})

    try:
        resolved = beta.commit(repository, revision)
        report["revision"] = resolved
        historical = baseline_audit(repository, baseline)
        check("historical-beta-composition", historical.get("result") == "PASS", report=historical)
        check("baseline-ancestor", beta.git(repository, "merge-base", "--is-ancestor", baseline, resolved,
                                           allow_not_ancestor=True))
        original = beta.objects(repository, baseline, (".",), recursive=True)
        actual = beta.objects(repository, resolved, (".",), recursive=True)
        changed = {path for path in set(original) | set(actual) if original.get(path) != actual.get(path)}
        allowed = set(expected) | set(metadata)
        check("complete-changed-path-set", bool(expected) and changed == allowed,
              unexpected=sorted(changed - allowed), missing=sorted(allowed - changed))
        for path, oid in sorted(expected.items()):
            wanted = {"mode": "100644", "type": "blob", "oid": oid}
            check("reviewed:" + path, actual.get(path) == wanted, expected=wanted, actual=actual.get(path))
        for path in sorted(metadata):
            obj = actual.get(path)
            check("review-metadata:" + path, bool(obj) and obj["type"] == "blob" and obj["mode"] == "100644")
    except (beta.AuditError, OSError, ValueError, UnicodeError) as error:
        check("audit:git-inputs", False, error=str(error))
    report["result"] = "PASS" if checks and all(c["result"] == "PASS" for c in checks) else "FAIL"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD")
    parser.add_argument("--repository", type=Path, default=Path("."))
    arguments = parser.parse_args()
    report = audit(arguments.repository, arguments.revision)
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    print("CAPTURE_ENTRY_INTEGRATION_" + report["result"], file=sys.stderr)
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
