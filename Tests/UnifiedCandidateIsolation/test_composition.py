"""Meaningful rejection regressions for the unified fixed-source audit.

Every fixture is an isolated temporary Git repository. No user repository,
source tree, app data, remote ref, or production upload is modified.
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


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "unified_candidate_audit", ROOT / "scripts/verify-unified-candidate-composition.py")
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class UnifiedCompositionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="riftlet-unified-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Isolated audit fixture")
        self.git("config", "user.email", "fixture@invalid.local")
        self.git("config", "core.hooksPath", os.devnull)
        self.write("Sources/Main.swift", "reviewed product code\n")
        self.write("Sources/Feedback.swift", "latest reliability fixes\n")
        self.write("website/index.html", "old website\n")
        self.history_one_path = "scripts/original-feedback-audit.py"
        self.history_two_path = "scripts/original-thin-audit.py"
        self.write(self.history_one_path, self.historical_script())
        self.history_one = self.commit("original feedback")
        self.write(self.history_two_path, self.historical_script())
        self.history_two = self.commit("original thin")

        self.git("checkout", "-q", "-b", "website-main", self.history_one)
        self.write("website/index.html", "independently pinned website\n")
        self.write("website/hero.js", "pinned website script\n")
        self.main = self.commit("website only")
        self.overlay = tuple((path, self.object(self.main, path))
                             for path in ("website/index.html", "website/hero.js"))

        self.git("checkout", "-q", "-b", "candidate", self.history_two)
        for path in AUDIT.METADATA_PATHS:
            self.write(path, "handoff and policy fixture\n")
        self.reviewed = self.commit("independently reviewed candidate")
        self.policy = AUDIT.Policy(
            histories=(
                AUDIT.HistoricalAudit("feedback", self.history_one, self.history_one_path,
                                      self.object(self.history_one, self.history_one_path)),
                AUDIT.HistoricalAudit("thin", self.history_two, self.history_two_path,
                                      self.object(self.history_two, self.history_two_path)),
            ),
            reviewed_source=self.reviewed, main_revision=self.main, main_objects=self.overlay,
        )

    def git(self, *arguments, input=None):
        result = subprocess.run(["git", "--no-replace-objects", "-C", str(self.repository), *arguments],
                                input=input, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=AUDIT.git_environment())
        if result.returncode:
            raise AssertionError(result.stderr.decode())
        return result.stdout.decode().strip()

    def write(self, path, value):
        target = self.repository / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def object(self, revision, path):
        return self.git("rev-parse", revision + ":" + path)

    @staticmethod
    def historical_script(result="PASS", reported_revision="sys.argv[1]", checks=None):
        if checks is None:
            checks = [{"id": "original-boundary", "result": result}]
        return ("import json, sys\n"
                "print(json.dumps({'result': " + repr(result) + ", 'revision': " + reported_revision
                + ", 'checks': " + repr(checks) + "}))\n")

    def check(self, revision="HEAD", policy=None, expected="FAIL"):
        report = AUDIT.audit(self.repository, revision, policy or self.policy)
        self.assertEqual(report["result"], expected, json.dumps(report, indent=2))
        return report

    def testExactReviewedCandidatePassesBothOriginalAudits(self):
        report = self.check(expected="PASS")
        self.assertEqual(report["compositionMode"], "reviewed-candidate")
        self.assertEqual(set(report["historicalAudits"]), {"feedback", "thin"})

    def testMissingReviewPinFailsClosed(self):
        report = self.check(policy=replace(self.policy, reviewed_source=None))
        self.assertIn("Missing or invalid fixed commit", report["checks"][-1]["error"])

    def testProductChangeFailsEvenUnderPreviouslyAcceptedDirectory(self):
        self.write("Sources/Main.swift", "unreviewed behavior\n")
        self.commit("unreviewed")
        self.check()

    def testFeedbackRegressionCannotBorrowThinReview(self):
        self.write("Sources/Feedback.swift", "old feedback implementation\n")
        self.commit("old branch overwrote reliability")
        self.check()

    def testNeighborAddedDeletedOrExecutablePathsFail(self):
        with self.subTest(change="addition"):
            self.write("Sources/Neighbor.swift", "unreviewed\n")
            added = self.commit("added")
            self.check(added)
        self.git("checkout", "-q", "--detach", self.reviewed)
        with self.subTest(change="deletion"):
            (self.repository / "Sources/Feedback.swift").unlink()
            deleted = self.commit("deleted")
            self.check(deleted)
        self.git("checkout", "-q", "--detach", self.reviewed)
        with self.subTest(change="mode"):
            (self.repository / "Sources/Main.swift").chmod(0o755)
            changed = self.commit("executable")
            self.check(changed)

    def testUncommittedEditsDoNotSupplyExpectedSource(self):
        self.write("Sources/Main.swift", "dirty uncommitted change\n")
        self.check(self.reviewed, expected="PASS")

    def testIdenticalTreeWithoutReviewedAncestryIsRejected(self):
        tree = self.git("rev-parse", self.reviewed + "^{tree}")
        orphan = self.git("commit-tree", tree, "-m", "same bytes without source ancestry")
        self.check(orphan)

    def testOriginalAuditMustRemainExactEvenInReviewedCheckpoint(self):
        self.write(self.history_one_path, "print('bypassed')\n")
        changed = self.commit("weakened historical gate")
        self.check(policy=replace(self.policy, reviewed_source=changed))

    def testWrongHistoricalBlobAndEmptyHistoricalListFail(self):
        altered = replace(self.policy.histories[0], blob=self.object(self.reviewed, "Sources/Main.swift"))
        self.check(policy=replace(self.policy, histories=(altered, self.policy.histories[1])))
        self.check(policy=replace(self.policy, histories=()))

    def testDuplicateHistoricalPathFails(self):
        self.check(policy=replace(self.policy, histories=(self.policy.histories[0], self.policy.histories[0])))

    def testFalseHistoricalPassWithWrongRevisionFails(self):
        self.write(self.history_two_path, self.historical_script(reported_revision="'wrong-revision'"))
        invalid = self.commit("false historical pass")
        history = replace(self.policy.histories[1], revision=invalid,
                          blob=self.object(invalid, self.history_two_path))
        self.check(policy=replace(self.policy, histories=(self.policy.histories[0], history), reviewed_source=invalid))

    def testHistoricalFailureAndEmptyChecksFail(self):
        for result, checks in (("FAIL", [{"id": "old-test", "result": "FAIL"}]), ("PASS", [])):
            with self.subTest(result=result, checks=checks):
                self.git("checkout", "-q", "--detach", self.reviewed)
                self.write(self.history_two_path, self.historical_script(result=result, checks=checks))
                invalid = self.commit("invalid historical result")
                history = replace(self.policy.histories[1], revision=invalid,
                                  blob=self.object(invalid, self.history_two_path))
                self.check(policy=replace(self.policy, histories=(self.policy.histories[0], history), reviewed_source=invalid))

    def testOnlyNamedExistingMetadataCanChange(self):
        for path in AUDIT.METADATA_PATHS:
            self.write(path, "new exact CI handoff\n")
        self.commit("handoff")
        self.check(expected="PASS")
        self.write("engineering/evidence/2026-10-29-unified-candidate/extra.py", "unreviewed executable input\n")
        self.commit("neighbor is not exempt")
        self.check()

    def testMetadataCannotBeDeletedOrSymlinkedOrExecutable(self):
        path = sorted(AUDIT.METADATA_PATHS)[0]
        for mode in ("deleted", "symlink", "executable"):
            with self.subTest(mode=mode):
                self.git("checkout", "-q", "--detach", self.reviewed)
                target = self.repository / path
                if mode == "deleted":
                    target.unlink()
                elif mode == "symlink":
                    target.unlink(); target.symlink_to("/tmp/not-an-evidence-file")
                else:
                    target.chmod(0o755)
                self.commit(mode)
                self.check()

    def testMetadataMustAlreadyExistInReviewedSource(self):
        self.check(policy=replace(self.policy, reviewed_source=self.history_two))

    def testGitEnvironmentCannotRedirectRepositoryOrObjects(self):
        with patch.dict(os.environ, {"GIT_DIR": "/nonexistent/untrusted", "GIT_WORK_TREE": "/tmp",
                                     "GIT_OBJECT_DIRECTORY": "/nonexistent/objects", "GIT_NAMESPACE": "untrusted"}):
            self.check(expected="PASS")

    def testReplacementRefsCannotReplaceReviewedObjects(self):
        self.write("Sources/Main.swift", "replacement source\n")
        replacement = self.commit("replacement")
        self.git("replace", self.reviewed, replacement)
        self.check(self.reviewed, expected="PASS")

    def make_test_merge(self, candidate_parent=None, main_parent=None, extra_parent=None):
        candidate_parent = candidate_parent or self.reviewed
        main_parent = main_parent or self.main
        self.git("checkout", "-q", "--detach", candidate_parent)
        for path, _ in self.overlay:
            self.write(path, self.git("show", self.main + ":" + path) + "\n")
        self.git("add", "-A")
        tree = self.git("write-tree")
        parents = ["-p", main_parent, "-p", candidate_parent]
        if extra_parent:
            parents += ["-p", extra_parent]
        return self.git("commit-tree", tree, *parents, "-m", "isolated GitHub test merge")

    def testExactTwoParentMainWebsiteMergePasses(self):
        merged = self.make_test_merge()
        report = self.check(merged, expected="PASS")
        self.assertEqual(report["compositionMode"], "fixed-main-test-merge")
        self.assertEqual(set(report["mainOverlayObjects"]), {path for path, _ in self.overlay})

    def testWebsiteOverlayOnOrdinaryCandidateIsRejected(self):
        self.make_test_merge()
        changed = self.commit("website without matching merge parents")
        self.check(changed)

    def testUnknownMainAndExtraMergeParentsAreRejected(self):
        merged = self.make_test_merge(main_parent=self.history_one)
        self.check(merged)
        merged = self.make_test_merge(extra_parent=self.history_one)
        self.check(merged)

    def testCandidateParentCannotHideUnreviewedChangesInTestMerge(self):
        self.write("Sources/Main.swift", "unreviewed source in parent\n")
        bad_parent = self.commit("unreviewed parent")
        self.git("checkout", "-q", "--detach", self.reviewed)
        for path, _ in self.overlay:
            self.write(path, self.git("show", self.main + ":" + path) + "\n")
        self.git("add", "-A")
        tree = self.git("write-tree")
        merged = self.git("commit-tree", tree, "-p", self.main, "-p", bad_parent, "-m", "hide parent change")
        self.check(merged)

    def testMainOverlayObjectAndNeighborChangesAreRejected(self):
        merged = self.make_test_merge()
        self.git("checkout", "-q", "--detach", merged)
        self.write("website/index.html", "unapproved website bytes\n")
        self.git("add", "-A")
        tree = self.git("write-tree")
        changed = self.git("commit-tree", tree, "-p", self.main, "-p", self.reviewed, "-m", "wrong overlay")
        self.check(changed)
        self.git("checkout", "-q", "--detach", merged)
        self.write("website/other.js", "not allowlisted\n")
        self.git("add", "-A")
        tree = self.git("write-tree")
        added = self.git("commit-tree", tree, "-p", self.main, "-p", self.reviewed, "-m", "overlay neighbor")
        self.check(added)

    def testOverlayPolicyCannotContainWrongBlobOrDuplicateOrTraversal(self):
        for overlay in (
            (("website/index.html", self.object(self.reviewed, "Sources/Main.swift")),),
            (self.overlay[0], self.overlay[0]),
            (("website/../Sources/Main.swift", self.overlay[0][1]),),
            (("website/*", self.overlay[0][1]),),
            ((AUDIT.GATE_PATH, self.overlay[0][1]),),
        ):
            with self.subTest(overlay=overlay):
                self.check(policy=replace(self.policy, main_objects=overlay))

    def testCliRejectsPinOverride(self):
        result = subprocess.run([sys.executable, "-B", str(ROOT / AUDIT.GATE_PATH),
                                 "--reviewed-source", self.reviewed],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=AUDIT.git_environment())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"unrecognized arguments", result.stderr)


if __name__ == "__main__":
    unittest.main()
