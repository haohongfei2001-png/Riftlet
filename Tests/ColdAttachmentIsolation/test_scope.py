"""Adversarial exact-source checks in disposable Git repositories only."""

from dataclasses import replace
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("cold_scope", ROOT / "scripts/verify-cold-attachment-scope.py")
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class ColdAttachmentScopeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="riftlet-cold-scope-test-")
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Isolated technical audit")
        self.git("config", "user.email", "fixture@invalid.local")
        self.git("config", "core.hooksPath", os.devnull)
        self.old_gate = "scripts/formal.py"
        self.workflow = ".github/workflows/native.yml"
        self.write(self.old_gate, self.history())
        self.write("Sources/Transport.swift", "original receipt reader\n")
        self.write("Sources/Admission.swift", "ordinary uploads disabled\n")
        self.write("evidence/old-unknown.json", "immutable historical evidence\n")
        self.write(self.workflow, "name: Formal\njobs:\n  macos:\n    run: original-full-tests\n")
        self.base = self.commit("formal checkpoint")
        self.base_gate_blob = self.oid(self.base, self.old_gate)
        self.write("Sources/Transport.swift", "reviewed receipt repair\n")
        self.write(self.workflow, "name: Technical\njobs:\n  macos:\n    run: original-full-tests\n")
        gate = (ROOT / AUDIT.GATE_PATH).read_text()
        gate = re.sub(r'^REVIEWED_SOURCE = .+$', "REVIEWED_SOURCE = None", gate, flags=re.MULTILINE)
        gate = re.sub(r'^REVIEWED_TREE = .+$', "REVIEWED_TREE = None", gate, flags=re.MULTILINE)
        self.write(AUDIT.GATE_PATH, gate)
        self.source = self.commit("reviewed technical source")
        self.policy = AUDIT.Policy(
            self.base, self.old_gate, self.base_gate_blob,
            self.source, self.git("rev-parse", self.source + "^{tree}"),
            frozenset(("Sources/Transport.swift", self.workflow, AUDIT.GATE_PATH)),
            ((self.workflow, b"  macos:\n"),))
        self.head = self.pin(self.policy)

    def git(self, *args):
        result = subprocess.run(["git", "--no-replace-objects", "-C", str(self.repository), *args],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=AUDIT.git_environment())
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout.decode().strip()

    def write(self, path, value):
        target = self.repository / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def oid(self, revision, path):
        return self.git("rev-parse", revision + ":" + path)

    @staticmethod
    def history(result="PASS", revision="sys.argv[1]", checks=None):
        checks = [{"id": "original-gate", "result": result}] if checks is None else checks
        return ("import json, sys\nprint(json.dumps({'result': " + repr(result)
                + ", 'revision': " + revision + ", 'checks': " + repr(checks) + "}))\n")

    def pin(self, policy):
        self.git("checkout", "-q", "--detach", policy.reviewed_source)
        source = (self.repository / AUDIT.GATE_PATH).read_bytes()
        (self.repository / AUDIT.GATE_PATH).write_bytes(AUDIT.pinned_gate(source, policy))
        return self.commit("only two exact pin literals")

    def changed_source(self, edit, policy=None):
        policy = policy or self.policy
        self.git("checkout", "-q", "--detach", self.source)
        edit()
        source = self.commit("different reviewed source fixture")
        policy = replace(policy, reviewed_source=source, reviewed_tree=self.git("rev-parse", source + "^{tree}"))
        return self.pin(policy), policy

    def check(self, revision="HEAD", policy=None, expected="FAIL"):
        report = AUDIT.audit(self.repository, revision, policy or self.policy)
        self.assertEqual(report["result"], expected, json.dumps(report, indent=2))
        return report

    def testExactReviewedChildAndPreservedJobsPass(self):
        report = self.check(expected="PASS")
        self.assertEqual(report["technicalHead"], self.head)
        self.assertEqual(set(report["sourceDelta"]), set(self.policy.edited_paths))

    def testReviewSourceAndTreePinsAreRequired(self):
        for field, value in (("reviewed_source", None), ("reviewed_tree", None),
                             ("reviewed_source", "HEAD"), ("reviewed_tree", self.base)):
            with self.subTest(field=field, value=value):
                self.check(policy=replace(self.policy, **{field: value}))

    def testUnpinnedSourceIsNotAnApprovedCandidate(self):
        self.check(self.source)

    def testProductOrAdmissionCannotChangeAfterReview(self):
        for path in ("Sources/Transport.swift", "Sources/Admission.swift", "evidence/old-unknown.json"):
            with self.subTest(path=path):
                self.git("checkout", "-q", "--detach", self.source)
                raw = (self.repository / AUDIT.GATE_PATH).read_bytes()
                (self.repository / AUDIT.GATE_PATH).write_bytes(AUDIT.pinned_gate(raw, self.policy))
                self.write(path, "unreviewed change\n")
                self.commit("not just pin literals")
                self.check()

    def testExtraDocumentationAlsoNeedsReview(self):
        self.write("docs/extra.md", "not a metadata exception\n")
        self.commit("extra document")
        self.check()

    def testPinPolicyChangesCannotHideBehindItsOwnPath(self):
        self.git("checkout", "-q", "--detach", self.source)
        gate = (self.repository / AUDIT.GATE_PATH)
        gate.write_bytes(AUDIT.pinned_gate(gate.read_bytes(), self.policy) + b"# unreviewed policy\n")
        self.commit("policy edited while pinning")
        self.check()

    def testWholeTreeOutsideNamedDeltaMustEqualFormalBaseline(self):
        for path in ("Sources/Admission.swift", "Sources/Neighbor.swift", "evidence/old-unknown.json"):
            with self.subTest(path=path):
                head, policy = self.changed_source(lambda: self.write(path, "unauthorized delta\n"))
                self.check(head, policy)

    def testDeltaDeletionSymlinkAndExecutableAreRejected(self):
        for change in ("delete", "symlink", "execute"):
            with self.subTest(change=change):
                def edit():
                    path = self.repository / "Sources/Transport.swift"
                    if change == "delete":
                        path.unlink()
                    elif change == "symlink":
                        path.unlink()
                        path.symlink_to("Admission.swift")
                    else:
                        path.chmod(0o755)
                head, policy = self.changed_source(edit)
                self.check(head, policy)

    def testNoBaselineObjectsCanBeDeleted(self):
        head, policy = self.changed_source(lambda: (self.repository / "Sources/Admission.swift").unlink())
        self.check(head, policy)

    def testOriginalFormalGateMustRemainExact(self):
        head, policy = self.changed_source(lambda: self.write(self.old_gate, "print('bypassed')\n"),
            replace(self.policy, edited_paths=self.policy.edited_paths | {self.old_gate}))
        self.check(head, policy)

    def testUnchangedOriginalMacOSJobIsMandatoryEvenInReviewedSource(self):
        head, policy = self.changed_source(lambda: self.write(self.workflow,
            "name: Technical\njobs:\n  macos:\n    run: weaker-tests\n"))
        self.check(head, policy)

    def testOriginalAuditFailureWrongRevisionAndEmptyChecksFail(self):
        for script in (self.history(result="FAIL"), self.history(revision="'wrong'"),
                       self.history(checks=[]), "print('[]')\n", self.history() + "sys.exit(1)\n"):
            with self.subTest(script=script):
                self.write("original-fixture.py", script)
                blob = self.git("hash-object", "-w", "original-fixture.py")
                good, _ = AUDIT.baseline_audit(self.repository,
                    replace(self.policy, baseline_gate_blob=blob))
                self.assertFalse(good)

    def testSameTreeWithoutSourceAncestryCannotPass(self):
        tree = self.git("rev-parse", self.head + "^{tree}")
        orphan = self.git("commit-tree", tree, "-m", "orphan")
        self.check(orphan)

    def testNoExtraPostReviewCommitEvenWithIdenticalBytes(self):
        tree = self.git("rev-parse", self.head + "^{tree}")
        extra = self.git("commit-tree", tree, "-p", self.head, "-m", "extra parent")
        self.check(extra)

    def merge(self, first=None, second=None, tree=None, third=None):
        args = ["commit-tree", tree or self.git("rev-parse", self.head + "^{tree}"),
                "-p", first or self.base, "-p", second or self.head]
        if third:
            args.extend(("-p", third))
        return self.git(*args, "-m", "test merge")

    def testExactPRMergeIntoUnchangedFormalBasePasses(self):
        report = self.check(self.merge(), expected="PASS")
        self.assertEqual(report["compositionMode"], "exact-baseline-pr-test-merge")

    def testChangedBaseWrongParentsAndMergedTreeFail(self):
        self.check(self.merge(first=self.source))
        self.check(self.merge(first=self.head, second=self.base))
        self.check(self.merge(third=self.source))
        self.check(self.merge(tree=self.git("rev-parse", self.source + "^{tree}")))

    def testGitEnvironmentAndReplacementRefsCannotRedirectEvidence(self):
        self.git("replace", self.source, self.base)
        with patch.dict(os.environ, {"GIT_DIR": "/invalid", "GIT_WORK_TREE": "/invalid",
                                     "GIT_OBJECT_DIRECTORY": "/invalid", "GIT_NAMESPACE": "untrusted"}):
            self.check(self.head, expected="PASS")

    def testCliCannotOverrideReviewPins(self):
        result = subprocess.run([sys.executable, "-B", str(ROOT / AUDIT.GATE_PATH),
                                 "--reviewed-source", self.source], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"unrecognized arguments", result.stderr)


if __name__ == "__main__":
    unittest.main()
