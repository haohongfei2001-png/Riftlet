"""Real Git-object checks; no network, account credentials or product data."""
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "scripts/verify-feedback-isolation.sh"

class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Synthetic Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.write("Sources/RiftletCore/value", "old\n")
        self.commit("common")
        self.old = self.git("rev-parse", "HEAD")
        self.git("checkout", "-qb", "feedback")
        self.write("Sources/RiftletFeedback/value", "feedback\n")
        self.commit("feature")
        self.feature = self.git("rev-parse", "HEAD")
        self.git("checkout", "-qb", "engineering", self.old)
        self.write("Sources/RiftletCore/value", "new\n")
        self.commit("target advances")
        self.base = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/origin/codex/engineering-foundation-20261027", self.base)
        self.git("merge", "--no-ff", "feedback", "-m", "synthetic PR merge")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL).strip()

    def write(self, name, text):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "-qm", message)

    def run_audit(self, base=None, head=None):
        env = dict(os.environ, FEEDBACK_BASE_SHA=base or self.old, FEEDBACK_HEAD_SHA=head or self.feature)
        return subprocess.run(["bash", str(SCRIPT)], cwd=self.root, env=env, capture_output=True, text=True)

    def test_stale_event_uses_actual_target_parent(self):
        result = self.run_audit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        record = (self.root / "feedback-results/composition.txt").read_text()
        self.assertIn("event_base=" + self.old, record)
        self.assertIn("\nbase=" + self.base, record)

    def test_mutated_protected_blob_is_rejected(self):
        self.write("Sources/RiftletCore/value", "tampered\n")
        self.git("add", ".")
        self.git("commit", "--amend", "--no-edit", "-q")
        self.assertNotEqual(self.run_audit().returncode, 0)

    def test_mutated_feedback_blob_is_rejected(self):
        self.write("Sources/RiftletFeedback/value", "tampered\n")
        self.git("add", ".")
        self.git("commit", "--amend", "--no-edit", "-q")
        self.assertNotEqual(self.run_audit().returncode, 0)

    def test_wrong_head_or_wrong_target_ref_is_rejected(self):
        self.assertNotEqual(self.run_audit(head=self.base).returncode, 0)
        self.git("update-ref", "refs/remotes/origin/codex/engineering-foundation-20261027", self.old)
        self.assertNotEqual(self.run_audit().returncode, 0)

if __name__ == "__main__":
    unittest.main()
