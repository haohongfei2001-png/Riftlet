"""Composition-gate faults in disposable, independent Git repositories only.

These cases prove source/evidence isolation, not AppKit or upload behavior.
The production historical audits are separately executed against their real pins.
"""

from dataclasses import replace
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/verify-thin-edge-composition.py"
SPEC = importlib.util.spec_from_file_location("thin_edge_composition", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)

HISTORICAL = '''import argparse, json, subprocess, sys
p = argparse.ArgumentParser()
p.add_argument("revision")
p.add_argument("--repository")
a = p.parse_args()
value = subprocess.check_output(["git", "--no-replace-objects", "-C", a.repository,
    "show", a.revision + ":Sources/Core.swift"])
passed = value == b"original reviewed core\\n"
result = "PASS" if passed else "FAIL"
print(json.dumps({"revision": a.revision, "result": result,
                  "checks": [{"id": "fixture:original-core", "result": result}]}))
sys.exit(0 if passed else 1)
'''


class ThinEdgeCompositionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="riftlet-thin-edge-fixture-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Synthetic Composition Review")
        self.git("config", "user.email", "review@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.filemode", "true")
        self.write("Sources/Core.swift", "original reviewed core\n")
        self.write("Sources/UI.swift", "old interface\n")
        self.write("Sources/Neighbor.swift", "unchanged source\n")
        self.write("engineering/evidence/original.json", '{"preserved":true}\n')
        self.write(".github/workflows/native.yml", "name: reviewed tests\n")
        self.history_paths = ["scripts/beta.py", "scripts/capture.py", "scripts/arrival.py"]
        for path in self.history_paths:
            self.write(path, HISTORICAL)
        self.record("fixed original source")
        self.baseline = self.git("rev-parse", "HEAD")
        histories = tuple(AUDIT.HistoricalAudit(name, self.baseline, path,
                          self.git("rev-parse", self.baseline + ":" + path))
                          for name, path in zip(("beta", "capture", "arrival"), self.history_paths))
        self.write("Sources/UI.swift", "reviewed composed interface\n")
        self.write("Sources/Motion.swift", "reviewed composed motion\n")
        self.write("Tests/UI.swift", "reviewed regression\n")
        for path in AUDIT.METADATA_PATHS:
            self.write(path, "reviewed policy or public handoff placeholder\n")
        self.record("reviewed composed source")
        self.source = self.git("rev-parse", "HEAD")
        self.policy = AUDIT.Policy(self.baseline, histories, self.source)

    def git(self, *arguments):
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(self.root), *arguments],
                                       env=AUDIT.git_environment(), stderr=subprocess.PIPE).decode().strip()

    def write(self, path, content):
        destination = self.root / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content)

    def record(self, message):
        self.git("add", ".")
        self.git("commit", "-qm", message)

    def result(self, *, policy=None, revision="HEAD"):
        return AUDIT.audit(self.root, revision, policy or self.policy)

    def assertFails(self, report, identifier):
        self.assertEqual(report["result"], "FAIL")
        self.assertTrue(any(item["id"] == identifier and item["result"] == "FAIL"
                            for item in report["checks"]), json.dumps(report["checks"], indent=2))

    def test_exact_source_and_only_named_metadata_followup_pass(self):
        self.assertEqual(self.result()["result"], "PASS")
        for path in AUDIT.METADATA_PATHS:
            self.write(path, "explicitly reviewed policy or actual CI result\n")
        self.record("pin source and record post-CI handoff")
        report = self.result()
        self.assertEqual(report["result"], "PASS")
        self.assertIn("Sources/Core.swift", report["protectedObjects"])
        self.assertIn("engineering/evidence/original.json", report["protectedObjects"])
        self.assertEqual(report["metadataExceptions"], sorted(AUDIT.METADATA_PATHS))

    def test_unreviewed_adjacent_source_is_rejected(self):
        self.write("Sources/Neighbor.swift", "unreviewed change\n")
        self.record("unreviewed neighboring source")
        self.assertFails(self.result(), "composition:exact-objects")

    def test_new_path_even_documentation_is_rejected(self):
        self.write("docs/unreviewed.md", "new unreviewed document\n")
        self.record("new path")
        self.assertFails(self.result(), "composition:exact-paths")

    def test_adjacent_handoff_file_is_not_a_directory_exception(self):
        self.write("engineering/evidence/2026-10-29-thin-edge-native/unreviewed.py", "unreviewed source\n")
        self.record("unreviewed sibling under metadata directory")
        self.assertFails(self.result(), "composition:exact-paths")

    def test_named_handoff_record_cannot_disappear(self):
        path = "engineering/evidence/2026-10-29-thin-edge-native/results.json"
        (self.root / path).unlink()
        self.record("missing handoff record")
        self.assertFails(self.result(), "composition:regular-metadata:candidate:" + path)

    def test_named_handoff_record_cannot_be_executable(self):
        path = "engineering/evidence/2026-10-29-thin-edge-native/README.md"
        (self.root / path).chmod(0o755)
        self.record("executable handoff record")
        self.assertFails(self.result(), "composition:regular-metadata:candidate:" + path)

    def test_removal_of_original_evidence_is_rejected(self):
        (self.root / "engineering/evidence/original.json").unlink()
        self.record("lost evidence")
        self.assertFails(self.result(), "composition:exact-objects")

    def test_mode_change_is_rejected(self):
        (self.root / "Sources/UI.swift").chmod(0o755)
        self.record("unexpected executable source")
        self.assertFails(self.result(), "composition:exact-objects")

    def test_symlink_substitution_is_rejected(self):
        (self.root / "Sources/UI.swift").unlink()
        (self.root / "Sources/UI.swift").symlink_to("Neighbor.swift")
        self.record("symlink source")
        self.assertFails(self.result(), "composition:exact-objects")

    def test_policy_path_cannot_be_symlink(self):
        (self.root / AUDIT.GATE_PATH).unlink()
        (self.root / AUDIT.GATE_PATH).symlink_to("beta.py")
        self.record("symlink gate")
        self.assertFails(self.result(), "composition:regular-metadata:candidate:" + AUDIT.GATE_PATH)

    def test_old_gate_is_protected_even_by_a_new_composition_pin(self):
        self.write("scripts/capture.py", "print('weakened gate')\n")
        self.record("changed old gate")
        revised = replace(self.policy, reviewed_source=self.git("rev-parse", "HEAD"))
        self.assertFails(self.result(policy=revised), "historical-gate-unchanged:capture")

    def test_working_tree_scripts_cannot_replace_pinned_audits(self):
        for path in self.history_paths:
            self.write(path, "raise RuntimeError('must never execute working tree')\n")
        self.write("Sources/Core.swift", "uncommitted bytes do not impersonate committed source\n")
        self.assertEqual(self.result()["result"], "PASS")

    def test_git_environment_cannot_redirect_to_other_repository(self):
        with patch.dict(os.environ, {"GIT_DIR": "/nonexistent-git-directory",
                                     "GIT_WORK_TREE": "/nonexistent-worktree",
                                     "GIT_ALTERNATE_OBJECT_DIRECTORIES": "/nonexistent-alternate",
                                     "GIT_NAMESPACE": "untrusted"}):
            self.assertEqual(self.result()["result"], "PASS")

    def test_git_replace_cannot_change_historical_objects(self):
        self.git("replace", self.baseline, self.source)
        self.assertEqual(self.result()["result"], "PASS")

    def test_missing_review_pin_fails_closed(self):
        self.assertFails(self.result(policy=replace(self.policy, reviewed_source=None)), "audit:inputs")

    def test_missing_history_fails_closed(self):
        absent = replace(self.policy.histories[0], revision="0" * 40)
        self.assertFails(self.result(policy=replace(self.policy, histories=(absent,))), "audit:inputs")

    def test_mismatched_historical_blob_is_not_executed(self):
        wrong = replace(self.policy.histories[0], blob=self.git("rev-parse", "HEAD:Sources/UI.swift"))
        self.assertFails(self.result(policy=replace(self.policy, histories=(wrong,))), "audit:inputs")

    def test_same_source_tree_without_reviewed_ancestry_is_rejected(self):
        tree = self.git("rev-parse", self.source + "^{tree}")
        sibling = self.git("commit-tree", tree, "-p", self.baseline, "-m", "unreviewed sibling")
        self.assertFails(self.result(revision=sibling), "ancestor:reviewed-source")

    def test_historical_false_pass_or_wrong_revision_does_not_count(self):
        for suffix, replacement in (("child-check", '"checks": [{"result": "FAIL"}]'),
                                    ("wrong-revision", '"revision": "0" * 40')):
            with self.subTest(suffix=suffix):
                path = "scripts/" + suffix + ".py"
                source = '''import argparse, json
p=argparse.ArgumentParser(); p.add_argument("revision"); p.add_argument("--repository")
a=p.parse_args()
r={"result":"PASS", "revision":a.revision, "checks":[{"result":"PASS"}]}
r.update({''' + replacement + '''})
print(json.dumps(r))
'''
                self.write(path, source)
                self.record(suffix)
                revision = self.git("rev-parse", "HEAD")
                history = AUDIT.HistoricalAudit(suffix, revision, path, self.git("rev-parse", revision + ":" + path))
                policy = replace(self.policy, histories=(history,), reviewed_source=revision)
                self.assertFails(self.result(policy=policy), "historical:" + suffix)

    def test_non_object_historical_result_fails_closed(self):
        path = "scripts/malformed.py"
        self.write(path, 'print("[]")\n')
        self.record("malformed historical result")
        revision = self.git("rev-parse", "HEAD")
        history = AUDIT.HistoricalAudit("malformed", revision, path,
                                       self.git("rev-parse", revision + ":" + path))
        policy = replace(self.policy, histories=(history,), reviewed_source=revision)
        self.assertFails(self.result(policy=policy), "audit:inputs")

    def test_cli_has_no_policy_override(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--reviewed-source", self.source],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
