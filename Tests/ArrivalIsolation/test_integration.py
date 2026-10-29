"""Exact-scope arrival audit exercised against independent temporary Git histories.

No network, user's queue/media, repository refs or real screenshot is touched.
The fixture historical audit is intentionally small and independent of the
production path allowlist; the production baseline's real audit also runs in CI.
"""

from dataclasses import replace
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/verify-arrival-integration.py"
SPEC = importlib.util.spec_from_file_location("arrival_integration", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)

HISTORICAL_AUDIT = '''import argparse, json, subprocess, sys
p = argparse.ArgumentParser()
p.add_argument("revision")
p.add_argument("--repository")
a = p.parse_args()
value = subprocess.check_output(["git", "--no-replace-objects", "-C", a.repository,
    "show", a.revision + ":Sources/RiftletCore/protected.swift"])
passed = value == b"reviewed core\\n"
result = "PASS" if passed else "FAIL"
print(json.dumps({"revision": a.revision, "result": result,
                  "checks": [{"id": "fixture:original-core", "result": result}]}))
sys.exit(0 if passed else 1)
'''


class ArrivalIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="riftlet-arrival-isolation-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Synthetic Arrival Audit")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.filemode", "true")
        self.write("Sources/RiftletCore/protected.swift", "reviewed core\n")
        self.write("Sources/RiftletAdapters/protected.swift", "reviewed adapter\n")
        self.write("Sources/RiftletUI/Panel.swift", "reviewed old panel\n")
        self.write("Sources/RiftletUI/Neighbor.swift", "reviewed unchanged neighbor\n")
        self.write("engineering/evidence/old/evidence.json", '{"original":true}\n')
        self.write(".github/workflows/feedback-v01.yml", "name: old feedback\n")
        self.write(".github/workflows/native-foundation.yml", "name: old native\n")
        self.write("scripts/verify-internal-beta-integration.py", HISTORICAL_AUDIT)
        self.record("fixed baseline")
        self.baseline = self.git("rev-parse", "HEAD")
        self.baseline_blob = self.git("rev-parse", "HEAD:scripts/verify-internal-beta-integration.py")

        self.write("Sources/RiftletUI/Panel.swift", "reviewed new panel\n")
        self.write("Sources/RiftletUI/Magnet.swift", "reviewed magnet\n")
        self.write("Tests/ArrivalTests.swift", "reviewed independent test\n")
        self.write("docs/arrival.md", "reviewed handoff\n")
        self.write(".github/workflows/feedback-v01.yml", "name: reviewed feedback\n")
        self.write(".github/workflows/native-foundation.yml", "name: reviewed native\n")
        self.write("scripts/arrival-source-probe.swift", "// reviewed bounded read-only probe\n")
        self.record("reviewed arrival source")
        self.source = self.git("rev-parse", "HEAD")
        # Independent fixture values, not derived from the production allowlist.
        self.policy = AUDIT.Policy(
            baseline=self.baseline, baseline_audit_blob=self.baseline_blob,
            changes=(("M", "Sources/RiftletUI/Panel.swift"),
                     ("A", "Sources/RiftletUI/Magnet.swift"),
                     ("A", "Tests/ArrivalTests.swift"),
                     ("M", ".github/workflows/feedback-v01.yml"),
                     ("M", ".github/workflows/native-foundation.yml"),
                     ("A", "scripts/arrival-source-probe.swift"),
                     ("A", "docs/arrival.md")),
            reviewed_source=self.source,
        )

    def git(self, *arguments):
        return subprocess.check_output(["git", *arguments], cwd=self.root,
                                       stderr=subprocess.DEVNULL, text=True).strip()

    def write(self, path, content):
        destination = self.root / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content)

    def record(self, message):
        self.git("add", ".")
        self.git("commit", "-qm", message)

    def inspect(self, revision="HEAD", policy=None):
        return AUDIT.audit(self.root, revision, policy or self.policy)

    def failures(self, result):
        self.assertEqual(result["result"], "FAIL", result)
        return {entry["id"] for entry in result["checks"] if entry["result"] == "FAIL"}

    def test_correct_exact_delta_retains_original_audit_and_ignores_working_files(self):
        self.write("Sources/RiftletCore/protected.swift", "uncommitted change\n")
        self.write("Sources/RiftletUI/Untracked.swift", "untracked change\n")
        # A malicious dirty historical script must never be executed.
        self.write("scripts/verify-internal-beta-integration.py", "raise RuntimeError('dirty script')\n")
        result = self.inspect()
        self.assertEqual(result["result"], "PASS", result)
        self.assertEqual(result["baselineAudit"]["revision"], self.baseline)
        self.assertEqual(result["baselineAudit"]["result"], "PASS")
        self.assertEqual(result["revision"], self.source)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.source)
        self.assertIn("uncommitted", (self.root / "Sources/RiftletCore/protected.swift").read_text())

    def test_core_adapter_and_neighbor_mutations_fail_even_in_allowed_parent_directories(self):
        for path in ("Sources/RiftletCore/protected.swift", "Sources/RiftletAdapters/protected.swift",
                     "Sources/RiftletUI/Neighbor.swift"):
            self.write(path, "unreviewed mutation\n")
        self.record("outside scope")
        failed = self.failures(self.inspect())
        self.assertIn("delta:exact-paths", failed)
        self.assertIn("baseline:all-other-objects", failed)

    def test_unknown_addition_is_not_authorized_by_neighboring_new_file(self):
        self.write("Sources/RiftletUI/Unreviewed.swift", "unknown new source\n")
        self.record("unexpected addition")
        result = self.inspect()
        self.assertIn("delta:exact-paths", self.failures(result))
        check = next(entry for entry in result["checks"] if entry["id"] == "delta:exact-paths")
        self.assertEqual(check["unexpectedChanges"], ["Sources/RiftletUI/Unreviewed.swift"])

    def test_deletion_of_approved_modified_file_fails(self):
        (self.root / "Sources/RiftletUI/Panel.swift").unlink()
        self.record("lost panel")
        failed = self.failures(self.inspect())
        self.assertIn("delta:exact-paths", failed)
        self.assertIn("delta:regular-file:Sources/RiftletUI/Panel.swift", failed)

    def test_deletion_of_archived_evidence_fails(self):
        (self.root / "engineering/evidence/old/evidence.json").unlink()
        self.record("lost old evidence")
        failed = self.failures(self.inspect())
        self.assertIn("delta:exact-paths", failed)
        self.assertIn("baseline:all-other-objects", failed)

    def test_changed_file_cannot_become_executable_or_symlink(self):
        (self.root / "Sources/RiftletUI/Panel.swift").chmod(0o755)
        self.record("unexpected executable")
        self.assertIn("delta:regular-file:Sources/RiftletUI/Panel.swift", self.failures(self.inspect()))
        (self.root / "Sources/RiftletUI/Magnet.swift").unlink()
        (self.root / "Sources/RiftletUI/Magnet.swift").symlink_to("../RiftletCore/protected.swift")
        self.record("unexpected symlink")
        self.assertIn("delta:regular-file:Sources/RiftletUI/Magnet.swift", self.failures(self.inspect()))

    def test_historical_audit_cannot_be_changed_or_whitelisted(self):
        self.write("scripts/verify-internal-beta-integration.py", "print('PASS')\n")
        self.record("weaken old audit")
        broadened = replace(self.policy, changes=self.policy.changes + (
            ("M", "scripts/verify-internal-beta-integration.py"),))
        result = self.inspect(policy=broadened)
        self.assertIn("baseline:audit-unchanged", self.failures(result))
        self.assertEqual(result["baselineAudit"]["result"], "PASS",
                         "Original immutable audit must still execute against its baseline")

    def test_allowed_source_modification_after_review_requires_a_new_pin(self):
        self.write("Sources/RiftletUI/Magnet.swift", "unreviewed later source\n")
        self.record("mutate allowed source after review")
        self.assertIn("reviewed-source:Sources/RiftletUI/Magnet.swift", self.failures(self.inspect()))

    def test_documentation_successor_preserves_exact_reviewed_source(self):
        self.write("docs/arrival.md", "updated accurate evidence\n")
        self.record("documentation successor")
        self.assertEqual(self.inspect()["result"], "PASS")

    def test_allowed_ci_and_probe_modifications_after_review_require_a_new_pin(self):
        paths = (".github/workflows/feedback-v01.yml", ".github/workflows/native-foundation.yml",
                 "scripts/arrival-source-probe.swift")
        for path in paths:
            self.write(path, "unreviewed CI or probe change\n")
        self.record("mutate verification and probe after review")
        failures = self.failures(self.inspect())
        for path in paths:
            self.assertIn("reviewed-source:" + path, failures)

    def test_identical_tree_without_baseline_or_review_ancestry_fails(self):
        tree = self.git("rev-parse", "HEAD^{tree}")
        detached = self.git("commit-tree", tree, "-m", "flattened copy")
        failed = self.failures(self.inspect(detached))
        self.assertIn("ancestor:baseline", failed)
        self.assertIn("ancestor:reviewed-source", failed)

    def test_wrong_pinned_historical_blob_fails_closed(self):
        wrong = self.git("rev-parse", "HEAD:Sources/RiftletUI/Magnet.swift")
        self.assertIn("audit:git-inputs", self.failures(
            self.inspect(policy=replace(self.policy, baseline_audit_blob=wrong))))

    def test_invalid_policy_and_git_replacement_refs_cannot_expand_scope(self):
        bad = replace(self.policy, changes=self.policy.changes + (("A", "Sources/RiftletUI/*"),))
        self.assertIn("audit:git-inputs", self.failures(self.inspect(policy=bad)))
        self.write("Sources/RiftletCore/protected.swift", "bad core\n")
        self.record("bad replacement")
        changed = self.git("rev-parse", "HEAD")
        # Replacement refs cannot cause the explicit reviewed revision to become
        # the later corrupt commit when read by either audit layer.
        self.git("replace", self.source, changed)
        self.assertEqual(self.inspect(self.source)["result"], "PASS")

    def test_cli_has_no_pin_overrides_or_branch_based_authorization(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--repository", str(self.root)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertEqual(report["policy"]["baseline"], "1920e0562db893a3292af89a89270a26ddb46a5f")
        self.assertIn("audit:git-inputs", self.failures(report))
        self.assertIn("ARRIVAL_INTEGRATION_FAIL", result.stderr)
        override = subprocess.run([sys.executable, str(SCRIPT), "--baseline", self.baseline],
                                  capture_output=True, text=True)
        self.assertEqual(override.returncode, 2)
        self.assertIn("unrecognized arguments", override.stderr)


if __name__ == "__main__":
    unittest.main()
