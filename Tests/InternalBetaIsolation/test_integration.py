"""Read-only audit exercised against real temporary Git histories and objects.

The fixture's official source advances after Feedback branched, matching the
integration risk. No network, product data, credentials or host repo mutation.
"""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/verify-internal-beta-integration.py"
SPEC = importlib.util.spec_from_file_location("internal_beta_integration", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class InternalBetaIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Synthetic Integration Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        # Independent fixture paths, not inferred from the audit's path lists.
        for path in (
            "Sources/RiftletCore/value.swift", "Sources/RiftletCapture/value.swift",
            "Sources/RiftletUI/value.swift", "Sources/RiftletAdapters/value.swift",
            "Sources/RiftletGUIAcceptance/value.swift", "Sources/CSQLite/shim.h",
            "Resources/Info.plist", "ThirdPartyNotices/example/LICENSE",
            "Tests/RiftletCoreTests/value.swift", "Tests/RiftletCaptureTests/value.swift",
            "Tests/RiftletUITests/value.swift", "Tests/RiftletAdaptersTests/value.swift",
            "Tests/RiftletAppTests/value.swift", "Tests/WebPageProgram/value.cjs",
            "Sources/RiftletApp/ApplicationMode.swift",
            "Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift",
            "Package.swift",
        ):
            self.write(path, "old baseline\n")
        self.write("Sources/RiftletApp/RiftletMain.swift", "old main\n")
        self.record("old common baseline")
        self.old = self.git("rev-parse", "HEAD")

        self.git("checkout", "-qb", "feedback")
        for path in (
            "Sources/RiftletFeedback/FeedbackEngine.swift",
            "Sources/RiftletFeedbackUI/FeedbackWindowController.swift",
            "Sources/RiftletFeedbackDemo/FeedbackDemoMain.swift",
            "Sources/RiftletApp/FeedbackHost.swift",
            "Tests/RiftletFeedbackTests/value.swift",
            "Tests/RiftletFeedbackUITests/value.swift",
            "Tests/FeedbackIsolation/test_isolation.py",
            "services/feedback/receiver.mjs", "scripts/build-feedback-demo.sh",
            "scripts/verify-feedback-isolation.sh", "Package.swift",
        ):
            self.write(path, "delivered feedback\n")
        self.write("Sources/RiftletApp/RiftletMain.swift", "old main\nfeedback hook\n")
        self.record("feedback delivery from the older baseline")
        self.feedback = self.git("rev-parse", "HEAD")

        self.git("checkout", "-qb", "engineering", self.old)
        self.write("Sources/RiftletCore/value.swift", "new official screenshot logic\n")
        self.write("Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift", "restricted prospective admission\n")
        self.write("Sources/RiftletApp/RiftletMain.swift", "new screenshot main\n")
        self.record("official screenshot admission")
        self.official = self.git("rev-parse", "HEAD")
        for name in ("README.md", "result.json", "timeline.json", "review.md",
                     "data-preservation.json", "private-evidence-sha256.json", "verification.json"):
            self.write("engineering/evidence/2026-10-28-system-screenshot-swallow/" + name,
                       "archived synthetic evidence for " + name + "\n")
        self.record("evidence-only child")
        self.acceptance = self.git("rev-parse", "HEAD")
        # Preserve both parents, resolving only the intentionally shared Main.
        merged = subprocess.run(["git", "merge", "--no-ff", "--no-commit", "feedback"],
                                cwd=self.root, capture_output=True, text=True)
        self.assertEqual(merged.returncode, 1, merged.stdout + merged.stderr)
        self.assertEqual(self.git("diff", "--name-only", "--diff-filter=U"),
                         "Sources/RiftletApp/RiftletMain.swift")
        self.write("Sources/RiftletApp/RiftletMain.swift", "new screenshot main\nfeedback hook\n")
        self.record("reviewed three-way composition")
        self.combined = self.git("rev-parse", "HEAD")
        self.policy = AUDIT.Policy(self.official, self.acceptance, self.feedback,
                                   self.git("rev-parse", "HEAD:Sources/RiftletApp/RiftletMain.swift"))

    def git(self, *arguments):
        return subprocess.check_output(["git", *arguments], cwd=self.root,
                                       stderr=subprocess.DEVNULL, text=True).strip()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def record(self, message):
        self.git("add", ".")
        self.git("commit", "-qm", message)

    def inspect(self, revision="HEAD"):
        return AUDIT.audit(self.root, revision, self.policy)

    def failures(self, report):
        self.assertEqual(report["result"], "FAIL", report)
        return {item["id"] for item in report["checks"] if item["result"] == "FAIL"}

    def test_correct_composition_checks_commits_not_dirty_or_untracked_files(self):
        self.write("Sources/RiftletCore/value.swift", "uncommitted accidental edit\n")
        self.write("Sources/RiftletApp/Untracked.swift", "not part of this revision\n")
        report = self.inspect()
        self.assertEqual(report["result"], "PASS", report)
        self.assertEqual(report["revision"], self.combined)
        self.assertEqual(report["parents"], [self.acceptance, self.feedback])
        self.assertEqual(self.git("rev-parse", "HEAD"), self.combined)
        self.assertIn("uncommitted", (self.root / "Sources/RiftletCore/value.swift").read_text())

    def test_feedback_branch_old_screenshot_logic_cannot_replace_official(self):
        self.write("Sources/RiftletCore/value.swift", "old baseline\n")
        self.record("incorrectly restore old screenshot source")
        self.assertIn("screenshot:Sources/RiftletCore", self.failures(self.inspect()))
        # Explicitly checking the earlier committed composition still succeeds.
        self.assertEqual(self.inspect(self.combined)["result"], "PASS")

    def test_feedback_delivery_mutation_is_rejected(self):
        self.write("Sources/RiftletFeedback/FeedbackEngine.swift", "silently changed delivery\n")
        self.record("feedback changed")
        self.assertIn("feedback:Sources/RiftletFeedback", self.failures(self.inspect()))

    def test_lost_acceptance_file_is_rejected_despite_retained_ancestors(self):
        (self.root / "engineering/evidence/2026-10-28-system-screenshot-swallow/review.md").unlink()
        self.record("lost archived evidence")
        failed = self.failures(self.inspect())
        self.assertIn("acceptance:engineering/evidence/2026-10-28-system-screenshot-swallow", failed)
        self.assertFalse(any(name.startswith("ancestor:") for name in failed))

    def test_identical_tree_without_delivery_ancestry_is_rejected(self):
        tree = self.git("rev-parse", "HEAD^{tree}")
        flattened = self.git("commit-tree", tree, "-p", self.official, "-m", "incorrect flattened delivery")
        failed = self.failures(self.inspect(flattened))
        self.assertEqual(failed, {"ancestor:acceptance", "ancestor:feedback"})

    def test_shared_main_and_other_app_files_need_exact_reviewed_objects(self):
        self.write("Sources/RiftletApp/RiftletMain.swift", "old main\nfeedback hook\n")
        self.write("Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift", "old baseline\n")
        self.write("Sources/RiftletApp/Unexpected.swift", "unreviewed wiring\n")
        self.record("incorrect app composition")
        failed = self.failures(self.inspect())
        self.assertIn("app:reviewed-main", failed)
        self.assertIn("app:original-files", failed)

    def test_cli_has_no_fixture_pin_override_and_emits_structured_failure(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--repository", str(self.root)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertEqual(report["policy"]["official"], "e421e6687651c2fac1441410c1af2bd5b8151e55")
        self.assertIn("audit:git-inputs", self.failures(report))
        self.assertIn("INTERNAL_BETA_INTEGRATION_FAIL", result.stderr)


if __name__ == "__main__":
    unittest.main()
