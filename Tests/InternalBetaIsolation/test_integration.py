"""Read-only audit exercised against real temporary Git histories and objects.

The fixture's official source advances after Feedback branched, and a later UX
delivery branches before Feedback integration. No network, product data,
credentials or host repo mutation.
"""

import importlib.util
from dataclasses import replace
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
            "Sources/RiftletApp/ProductStatus.swift",
            "Sources/RiftletApp/SelectionSubmissionQueue.swift",
            "Sources/RiftletGUIAcceptance/AcceptanceMain.swift",
            "Sources/RiftletUI/RiftPanelController.swift",
            "Tests/RiftletAppTests/SelectionSubmissionQueueTests.swift",
            "Tests/RiftletUITests/PresentationBoundaryTests.swift",
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
        self.beta = self.git("rev-parse", "HEAD")

        self.git("checkout", "-qb", "experience", self.official)
        for path in (
            "Sources/RiftletApp/ProductStatus.swift",
            "Sources/RiftletApp/SelectionSubmissionQueue.swift",
            "Sources/RiftletGUIAcceptance/AcceptanceMain.swift",
            "Sources/RiftletUI/RiftPanelController.swift",
            "Tests/RiftletAppTests/ProductStatusTests.swift",
            "Tests/RiftletAppTests/SelectionSubmissionQueueTests.swift",
            "Tests/RiftletUITests/PresentationBoundaryTests.swift",
        ):
            self.write(path, "reviewed UX for " + path + "\n")
        self.write("Sources/RiftletApp/RiftletMain.swift", "new screenshot main\nowner revision feedback\n")
        self.record("bounded UX delivery from before Feedback integration")
        self.experience = self.git("rev-parse", "HEAD")
        for name in ("README.md", "combined-beta.md", "data-preservation.json",
                     "human-gui.md", "latency.md", "private-evidence-index.json",
                     "review-and-integration.md", "verification.json"):
            self.write("engineering/evidence/2026-10-28-beta-ux/" + name,
                       "bounded synthetic UX evidence for " + name + "\n")
        self.record("UX evidence-only child")
        self.experience_evidence = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "engineering")
        merged = subprocess.run(["git", "merge", "--no-ff", "--no-commit", "experience"],
                                cwd=self.root, capture_output=True, text=True)
        self.assertEqual(merged.returncode, 1, merged.stdout + merged.stderr)
        self.assertEqual(self.git("diff", "--name-only", "--diff-filter=U"),
                         "Sources/RiftletApp/RiftletMain.swift")
        self.write("Sources/RiftletApp/RiftletMain.swift",
                   "new screenshot main\nowner revision feedback\nfeedback hook\n")
        self.record("reviewed UX and Feedback composition")
        self.combined = self.git("rev-parse", "HEAD")
        self.policy = AUDIT.Policy(
            official=self.official, acceptance=self.acceptance, feedback=self.feedback,
            beta=self.beta, experience=self.experience,
            experience_evidence=self.experience_evidence,
            main_blob=self.git("rev-parse", "HEAD:Sources/RiftletApp/RiftletMain.swift"),
        )

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
        self.assertEqual(report["parents"], [self.beta, self.experience_evidence])
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

    def approve_feedback_repairs(self):
        repairs = {
            "Sources/RiftletFeedback/FeedbackEngine.swift": "reviewed timer repair\n",
            "Tests/RiftletFeedbackTests/FeedbackAutomaticRetryTests.swift": "new timer regression\n",
        }
        for path, content in repairs.items():
            self.write(path, content)
        self.record("independently reviewed exact Feedback repairs")
        updates = tuple((path, self.git("rev-parse", "HEAD:" + path)) for path in repairs)
        self.policy = replace(self.policy, feedback_updates=updates)

    def test_exact_feedback_repairs_and_added_test_are_accepted(self):
        self.approve_feedback_repairs()
        self.assertEqual(self.inspect()["result"], "PASS")
        # Approval is not a wildcard: changing the repaired object still fails.
        self.write("Sources/RiftletFeedback/FeedbackEngine.swift", "different repair\n")
        self.record("alter approved repair")
        self.assertIn("feedback:Sources/RiftletFeedback", self.failures(self.inspect()))

    def test_feedback_repairs_do_not_allow_neighbor_mutation_or_addition(self):
        self.approve_feedback_repairs()
        self.write("Sources/RiftletFeedback/Unexpected.swift", "unreviewed neighbor\n")
        self.write("Tests/RiftletFeedbackTests/value.swift", "unreviewed old test change\n")
        self.write("Sources/RiftletApp/FeedbackHost.swift", "unreviewed endpoint\n")
        self.record("unreviewed neighboring changes")
        self.assertEqual(self.failures(self.inspect()), {
            "feedback:Sources/RiftletFeedback", "feedback:Tests/RiftletFeedbackTests",
            "feedback:Sources/RiftletApp/FeedbackHost.swift",
        })

    def test_missing_added_feedback_regression_is_rejected(self):
        self.approve_feedback_repairs()
        (self.root / "Tests/RiftletFeedbackTests/FeedbackAutomaticRetryTests.swift").unlink()
        self.record("drop required new regression")
        self.assertEqual(self.failures(self.inspect()), {"feedback:Tests/RiftletFeedbackTests"})

    def test_feedback_repair_policy_rejects_non_feedback_and_non_blob_pins(self):
        self.approve_feedback_repairs()
        oid = self.policy.feedback_updates[0][1]
        valid = self.policy
        for updates in (
            (("Sources/RiftletCore/value.swift", oid),),
            (("Sources/RiftletFeedback/../RiftletCore/value.swift", oid),),
            (("Sources/RiftletFeedback/FeedbackEngine.swift", self.combined),),
            (valid.feedback_updates[0], valid.feedback_updates[0]),
        ):
            self.policy = replace(valid, feedback_updates=updates)
            self.assertEqual(self.failures(self.inspect()), {"audit:git-inputs"})

    def test_every_approved_ux_file_requires_its_exact_delivered_object(self):
        # Independent list includes an added test absent from the old baseline.
        paths = (
            "Sources/RiftletApp/ProductStatus.swift",
            "Sources/RiftletApp/SelectionSubmissionQueue.swift",
            "Sources/RiftletGUIAcceptance/AcceptanceMain.swift",
            "Sources/RiftletUI/RiftPanelController.swift",
            "Tests/RiftletAppTests/ProductStatusTests.swift",
            "Tests/RiftletAppTests/SelectionSubmissionQueueTests.swift",
            "Tests/RiftletUITests/PresentationBoundaryTests.swift",
        )
        for path in paths:
            self.write(path, "old baseline\n")
        self.record("incorrectly overwrite approved UX with the old Beta")
        failed = self.failures(self.inspect())
        self.assertEqual(failed, {"experience:" + path for path in paths})

    def test_approved_ux_does_not_allow_other_changes_in_the_same_directories(self):
        paths = (
            "Sources/RiftletUI/value.swift",
            "Sources/RiftletGUIAcceptance/value.swift",
            "Tests/RiftletUITests/value.swift",
            "Tests/RiftletAppTests/value.swift",
        )
        for path in paths:
            self.write(path, "unreviewed neighboring change\n")
        self.write("Sources/RiftletUI/Unreviewed.swift", "unreviewed addition\n")
        self.record("incorrect directory-wide UX exception")
        failed = self.failures(self.inspect())
        self.assertEqual(failed, {"experience:unmodified:" + str(Path(path).parent)
                                  for path in paths})

    def test_lost_acceptance_file_is_rejected_despite_retained_ancestors(self):
        (self.root / "engineering/evidence/2026-10-28-system-screenshot-swallow/review.md").unlink()
        (self.root / "engineering/evidence/2026-10-28-beta-ux/review-and-integration.md").unlink()
        self.record("lost archived evidence")
        failed = self.failures(self.inspect())
        self.assertIn("acceptance:engineering/evidence/2026-10-28-system-screenshot-swallow", failed)
        self.assertIn("experience-evidence:engineering/evidence/2026-10-28-beta-ux", failed)
        self.assertFalse(any(name.startswith("ancestor:") for name in failed))

    def test_identical_tree_without_delivery_ancestry_is_rejected(self):
        tree = self.git("rev-parse", "HEAD^{tree}")
        flattened = self.git("commit-tree", tree, "-p", self.official, "-m", "incorrect flattened delivery")
        failed = self.failures(self.inspect(flattened))
        self.assertEqual(failed, {"ancestor:acceptance", "ancestor:feedback", "ancestor:beta",
                                  "ancestor:experience", "ancestor:experience_evidence"})

    def test_ux_delivery_must_be_merged_not_copied_on_top_of_existing_beta(self):
        tree = self.git("rev-parse", "HEAD^{tree}")
        copied = self.git("commit-tree", tree, "-p", self.beta, "-m", "copied UX without ancestry")
        self.assertEqual(self.failures(self.inspect(copied)),
                         {"ancestor:experience", "ancestor:experience_evidence"})

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
        self.assertEqual(report["policy"]["beta"], "b4bcfa41e8e237723b975d2a9a0059e955fa0c1f")
        self.assertEqual(report["policy"]["experience"], "fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3")
        self.assertIn("audit:git-inputs", self.failures(report))
        self.assertIn("INTERNAL_BETA_INTEGRATION_FAIL", result.stderr)
        override = subprocess.run([sys.executable, str(SCRIPT), "--official", self.official],
                                  capture_output=True, text=True)
        self.assertEqual(override.returncode, 2)
        self.assertIn("unrecognized arguments", override.stderr)


if __name__ == "__main__":
    unittest.main()
