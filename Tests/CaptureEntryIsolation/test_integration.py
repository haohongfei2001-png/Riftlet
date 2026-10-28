"""Disposable Git fixtures; never inspect a user's image or browser."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("capture_entry_audit", ROOT / "scripts/verify-capture-entry-integration.py")
audit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = audit
SPEC.loader.exec_module(audit)


class CaptureEntryIsolationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.write("Sources/protected.swift", "preserved\n")
        self.write("Sources/entry.swift", "old\n")
        self.base = self.commit()
        self.write("Sources/entry.swift", "reviewed\n")
        self.write("Sources/new.swift", "new capture\n")
        self.write("docs/review.md", "review metadata\n")
        self.reviewed = self.commit()
        objects = audit.beta.objects(self.repo, self.reviewed, ("Sources",), recursive=True)
        self.expected = {p: objects[p]["oid"] for p in ("Sources/entry.swift", "Sources/new.swift")}
        self.metadata = {"docs/review.md"}

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], stderr=subprocess.STDOUT).decode().strip()

    def write(self, path, data):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(data)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def run_audit(self, historical="PASS"):
        return audit.audit(self.repo, baseline=self.base, expected=self.expected, metadata=self.metadata,
                           baseline_audit=lambda *_: {"result": historical})

    def test_exact_reviewed_increment_passes(self):
        self.assertEqual(self.run_audit()["result"], "PASS")

    def test_protected_adapter_equivalent_mutation_is_rejected(self):
        self.write("Sources/protected.swift", "changed\n"); self.commit()
        self.assertEqual(self.run_audit()["result"], "FAIL")

    def test_same_path_unreviewed_code_is_rejected(self):
        self.write("Sources/entry.swift", "different runtime\n"); self.commit()
        self.assertEqual(self.run_audit()["result"], "FAIL")

    def test_additional_source_is_rejected(self):
        self.write("Sources/surprise.swift", "unreviewed\n"); self.commit()
        self.assertEqual(self.run_audit()["result"], "FAIL")

    def test_missing_source_is_rejected(self):
        (self.repo / "Sources/new.swift").unlink(); self.commit()
        self.assertEqual(self.run_audit()["result"], "FAIL")

    def test_executable_mode_change_is_rejected(self):
        (self.repo / "Sources/entry.swift").chmod(0o755); self.commit()
        self.assertEqual(self.run_audit()["result"], "FAIL")

    def test_historical_beta_failure_cannot_be_overridden_by_new_source(self):
        self.assertEqual(self.run_audit(historical="FAIL")["result"], "FAIL")

    def test_working_tree_source_does_not_supply_expected_or_actual_git_objects(self):
        self.write("Sources/entry.swift", "uncommitted\n")
        self.assertEqual(self.run_audit()["result"], "PASS")

    def test_review_note_may_change_without_authorizing_runtime_changes(self):
        self.write("docs/review.md", "additional actual CI result\n"); self.commit()
        self.assertEqual(self.run_audit()["result"], "PASS")

    def test_git_directory_environment_cannot_substitute_an_approved_repository(self):
        alternate = self.repo.parent / (self.repo.name + "-alternate.git")
        self.addCleanup(lambda: __import__("shutil").rmtree(alternate, ignore_errors=True))
        subprocess.check_call(["git", "clone", "--bare", "-q", str(self.repo), str(alternate)])
        self.write("Sources/protected.swift", "unreviewed mutation\n"); self.commit()
        with patch.dict(os.environ, {"GIT_DIR": str(alternate)}):
            report = self.run_audit()
        self.assertEqual(report["result"], "FAIL")
        self.assertEqual(report["revision"], self.git("rev-parse", "HEAD"))

    def test_git_config_and_object_environment_are_not_inherited(self):
        with patch.dict(os.environ, {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.bare",
                                     "GIT_CONFIG_VALUE_0": "true", "GIT_NAMESPACE": "another",
                                     "GIT_OBJECT_DIRECTORY": "/does-not-exist"}):
            self.assertEqual(self.run_audit()["result"], "PASS")


if __name__ == "__main__":
    unittest.main()
