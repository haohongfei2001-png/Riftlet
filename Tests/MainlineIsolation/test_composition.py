"""Source-admission regressions in disposable Git repositories, never user data."""

from dataclasses import replace
import hashlib
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
SPEC = importlib.util.spec_from_file_location("mainline_audit", ROOT / "scripts/verify-mainline-composition.py")
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class MainlineCompositionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="riftlet-mainline-fixture-")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Isolated fixture")
        self.git("config", "user.email", "fixture@invalid.local")
        self.git("config", "core.hooksPath", os.devnull)
        self.write("index.html", "approved website\n")
        self.write("CNAME", "fixture.invalid\n")
        self.website = self.commit("website")
        self.write("Sources/Main.swift", "reviewed product\n")
        self.write("Tests/Product.swift", "reviewed regression\n")
        self.write(".github/workflows/native.yml", "reviewed workflow\n")
        self.write("engineering/evidence/original.json", '{"historical":"FAIL remains FAIL"}\n')
        self.write("research/fixture.txt", "immutable original evidence\n")
        self.write(AUDIT.LEGACY_GATE_PATH, "import json,sys\nprint(json.dumps({'result':'PASS','revision':sys.argv[1],'checks':[{'result':'PASS'}]}))\n")
        self.legacy = self.commit("original approved product")
        self.foundation = self.merge(self.website, self.legacy)
        self.policy = AUDIT.Policy(
            foundation=self.foundation, foundation_tree=self.tree(self.foundation),
            foundation_parents=(self.website, self.legacy), legacy_source=self.legacy,
            legacy_gate_blob=self.git("rev-parse", self.legacy + ":" + AUDIT.LEGACY_GATE_PATH),
            website_source=self.website, website_paths=("index.html", "CNAME"),
            historical_gates=(AUDIT.LEGACY_GATE_PATH,),
            historical_prefixes=("engineering/evidence/", "research/"),
        )
        self.git("checkout", "-q", "--detach", self.foundation)
        self.write("scripts/verify-mainline-composition.py", "reviewed successor policy\n")
        self.write(AUDIT.ADMISSION_PATH, "{}\n")
        self.source = self.commit("source independently reviewed after commit")
        self.record = self.review_record(self.source, self.foundation)
        self.head = self.admit(self.source, self.record)

    def git(self, *args):
        result = subprocess.run(["git", "--no-replace-objects", "-C", str(self.repo), *args],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=AUDIT.git_environment())
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout.decode().strip()

    def write(self, path, content):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def tree(self, revision):
        return self.git("rev-parse", revision + "^{tree}")

    def merge(self, base, head, extra=(), tree=None):
        args = ["commit-tree", tree or self.tree(head), "-p", base, "-p", head]
        for parent in extra:
            args.extend(("-p", parent))
        return self.git(*args, "-m", "standard merge fixture")

    def review_record(self, source, base):
        tree = self.tree(source)
        report = json.dumps({"result": "PASS", "reviewedSource": source, "reviewedTree": tree,
                             "reviewer": "independent-fixture-reviewer", "scope": "synthetic test review only"})
        return {"schemaVersion": 1, "reviewedBase": base, "reviewedSource": source, "reviewedTree": tree,
                "authorRole": "fixture-author", "productionAdmission": dict(AUDIT.PRODUCTION_BOUNDARY),
                "reviews": [{"reviewer": "independent-fixture-reviewer", "source": source, "tree": tree,
                             "result": "PASS", "sha256": hashlib.sha256(report.encode()).hexdigest(), "report": report}]}

    def admit(self, source, record):
        self.git("checkout", "-q", "--detach", source)
        self.write(AUDIT.ADMISSION_PATH, json.dumps(record, indent=2) + "\n")
        return self.commit("record independent exact source review")

    def check(self, revision=None, expected="FAIL", context=None, policy=None):
        report = AUDIT.audit(self.repo, revision or "HEAD", policy=policy or self.policy, context=context)
        self.assertEqual(report["result"], expected, json.dumps(report, indent=2))
        return report

    def pr_context(self, merge, base=None, head=None):
        return {"name": "pull_request", "sha": merge, "ref": "refs/pull/25/merge",
                "repository": "haohongfei2001-png/Riftlet", "event": {"number": 25,
                "pull_request": {"base": {"ref": "main", "sha": base or self.foundation},
                                 "head": {"sha": head or self.head}}}}

    def push_context(self, merge, base=None):
        return {"name": "push", "sha": merge, "ref": "refs/heads/main",
                "repository": "haohongfei2001-png/Riftlet", "event": {"before": base or self.foundation,
                "after": merge, "ref": "refs/heads/main", "forced": False, "deleted": False}}

    def testReviewedCandidatePasses(self):
        report = self.check(expected="PASS")
        self.assertEqual(report["compositionMode"], "reviewed-candidate")
        self.assertEqual(set(report["legacyAudits"]), {"pr1", "main-foundation"})

    def testActualPRMergeAndMainPushPassWithSameTree(self):
        merged = self.merge(self.foundation, self.head)
        self.git("checkout", "-q", "--detach", merged)
        self.check(expected="PASS", context=self.pr_context(merged))
        self.check(expected="PASS", context=self.push_context(merged))

    def testNextReviewedPRUsesNewMainBaseWithoutRepinningFoundation(self):
        base = self.merge(self.foundation, self.head)
        self.git("checkout", "-q", "--detach", base)
        self.write("Sources/Main.swift", "next explicitly reviewed product\n")
        source = self.commit("next source checkpoint")
        head = self.admit(source, self.review_record(source, base))
        merged = self.merge(base, head)
        self.git("checkout", "-q", "--detach", merged)
        self.check(expected="PASS", context=self.pr_context(merged, base, head))
        self.check(expected="PASS", context=self.push_context(merged, base))

    def testProductTestWorkflowAndPolicyEditsCannotBorrowOldReview(self):
        for path in ("Sources/Main.swift", "Tests/Product.swift", ".github/workflows/native.yml",
                     "scripts/verify-mainline-composition.py"):
            with self.subTest(path=path):
                self.git("checkout", "-q", "--detach", self.head)
                self.write(path, "unreviewed change\n")
                self.commit("unreviewed")
                report = self.check()
                self.assertTrue(any(c["id"] == "checkout:exact-objects" and c["result"] == "FAIL" for c in report["checks"]))

    def testUnreviewedNeighborAdditionDeletionAndModeFail(self):
        for change in ("add", "delete", "mode"):
            with self.subTest(change=change):
                self.git("checkout", "-q", "--detach", self.head)
                if change == "add":
                    self.write("engineering/mainline/neighbor.json", "{}")
                elif change == "delete":
                    (self.repo / "Sources/Main.swift").unlink()
                else:
                    (self.repo / "Sources/Main.swift").chmod(0o755)
                self.commit(change)
                self.check()

    def testMissingOrWrongSourceAndBasePinsFail(self):
        for key, value in (("reviewedSource", None), ("reviewedSource", self.legacy),
                           ("reviewedBase", None), ("reviewedBase", self.website),
                           ("reviewedTree", "0" * 40)):
            with self.subTest(key=key, value=value):
                changed = json.loads(json.dumps(self.record)); changed[key] = value
                self.admit(self.source, changed)
                self.check()

    def testAbsentSelfApprovalHashMismatchAndMismatchedEmbeddedReportFail(self):
        for mutation in ("empty", "self", "hash", "embedded", "duplicate-reviewer"):
            with self.subTest(mutation=mutation):
                changed = json.loads(json.dumps(self.record))
                if mutation == "empty":
                    changed["reviews"] = []
                elif mutation == "self":
                    changed["authorRole"] = changed["reviews"][0]["reviewer"]
                elif mutation == "hash":
                    changed["reviews"][0]["sha256"] = "0" * 64
                elif mutation == "embedded":
                    changed["reviews"][0]["report"] = '{}'
                    changed["reviews"][0]["sha256"] = hashlib.sha256(b'{}').hexdigest()
                else:
                    changed["reviews"] *= 2
                self.admit(self.source, changed)
                self.check()

    def testDuplicateUnknownAndOversizedJSONFieldsFail(self):
        for content in (json.dumps(self.record)[:-1] + ',"schemaVersion":1}',
                        json.dumps({**self.record, "automaticallyTrustHead": True}),
                        " " * (AUDIT.MAX_RECORD_BYTES + 1)):
            self.git("checkout", "-q", "--detach", self.source)
            self.write(AUDIT.ADMISSION_PATH, content)
            self.commit("malformed record")
            self.check()

    def testEveryProductionBoundaryRemainsClosed(self):
        for key in AUDIT.PRODUCTION_BOUNDARY:
            with self.subTest(key=key):
                changed = json.loads(json.dumps(self.record))
                changed["productionAdmission"][key] = True
                self.admit(self.source, changed)
                self.check()

    def testAdmissionMissingExecutableAndSymlinkFail(self):
        for kind in ("missing", "executable", "symlink"):
            with self.subTest(kind=kind):
                self.git("checkout", "-q", "--detach", self.head)
                path = self.repo / AUDIT.ADMISSION_PATH
                if kind == "executable":
                    path.chmod(0o755)
                else:
                    path.unlink()
                    if kind == "symlink":
                        path.symlink_to("../evidence/original.json")
                self.commit(kind)
                self.check()

    def testProductionFalseCannotBeReplacedByNumber(self):
        changed = json.loads(json.dumps(self.record))
        changed["productionAdmission"]["ordinaryInput"] = 0
        self.admit(self.source, changed)
        self.check()

    def testAdmissionMustAlreadyExistInReviewedSource(self):
        self.git("checkout", "-q", "--detach", self.foundation)
        self.write("Sources/Main.swift", "new source lacking review record\n")
        source = self.commit("missing admission source")
        self.admit(source, self.review_record(source, self.foundation))
        self.check()

    def testSourceMustDescendExactFoundationAndBase(self):
        orphan = self.git("commit-tree", self.tree(self.source), "-m", "same bytes no ancestry")
        self.admit(orphan, self.review_record(orphan, self.foundation))
        self.check()

    def testImmutableEvidenceAndHistoricalGatesCannotBeRepinnedAsNewSource(self):
        for path in ("engineering/evidence/original.json", "research/fixture.txt", AUDIT.LEGACY_GATE_PATH):
            with self.subTest(path=path):
                self.git("checkout", "-q", "--detach", self.head)
                self.write(path, "rewritten history\n")
                source = self.commit("attempted new approval of history rewrite")
                self.admit(source, self.review_record(source, self.foundation))
                report = self.check()
                self.assertTrue(any(c["id"] == "reviewed:immutable-history" and c["result"] == "FAIL" for c in report["checks"]))

    def testWebsiteChangeCannotBeRepinnedAsNewSource(self):
        self.write("index.html", "changed website\n")
        source = self.commit("attempted website rewrite")
        self.admit(source, self.review_record(source, self.foundation))
        report = self.check()
        self.assertTrue(any(c["id"] == "website:index.html" and c["result"] == "FAIL" for c in report["checks"]))

    def testEvidenceAddedByEarlierMainPRBecomesImmutable(self):
        self.write("engineering/evidence/new-acceptance.json", '{"result":"NOT_RUN"}\n')
        source = self.commit("explicitly reviewed new evidence")
        head = self.admit(source, self.review_record(source, self.foundation))
        base = self.merge(self.foundation, head)
        self.git("checkout", "-q", "--detach", base)
        self.check(expected="PASS", context=self.push_context(base))
        for change in ("rewrite", "delete", "mode"):
            with self.subTest(change=change):
                self.git("checkout", "-q", "--detach", base)
                path = self.repo / "engineering/evidence/new-acceptance.json"
                if change == "rewrite":
                    path.write_text('{"result":"PASS"}\n')
                elif change == "delete":
                    path.unlink()
                else:
                    path.chmod(0o755)
                newer_source = self.commit("attempt to rewrite previously admitted evidence")
                newer_head = self.admit(newer_source, self.review_record(newer_source, base))
                merged = self.merge(base, newer_head)
                self.git("checkout", "-q", "--detach", merged)
                self.check(context=self.pr_context(merged, base, newer_head))

    def testSymlinkOrSubmoduleCannotBeAdmittedEvenAtReviewedCheckpoint(self):
        (self.repo / "Sources/link.swift").symlink_to("Main.swift")
        source = self.commit("linked source")
        self.admit(source, self.review_record(source, self.foundation))
        self.check()

    def testSingleParentDirectMainPushFails(self):
        self.check(context=self.push_context(self.head))

    def testReversedExtraOrWrongMergeParentsFail(self):
        revisions = (self.merge(self.head, self.foundation, tree=self.tree(self.head)),
                     self.merge(self.foundation, self.head, extra=(self.website,)),
                     self.merge(self.website, self.head))
        for revision in revisions:
            with self.subTest(revision=revision):
                self.git("checkout", "-q", "--detach", revision)
                self.check(context=self.pr_context(revision))

    def testMergeCannotHideUnreviewedCandidateBytes(self):
        self.write("Sources/Main.swift", "hidden unreviewed candidate\n")
        bad_head = self.commit("bad candidate")
        merged = self.merge(self.foundation, bad_head, tree=self.tree(self.head))
        self.git("checkout", "-q", "--detach", merged)
        self.check(context=self.pr_context(merged, head=bad_head))

    def testMergeAdmissionMustBeByteIdenticalToCandidate(self):
        self.write(AUDIT.ADMISSION_PATH, json.dumps(self.record, separators=(",", ":")))
        changed = self.commit("same JSON different bytes")
        merged = self.merge(self.foundation, self.head, tree=self.tree(changed))
        self.git("checkout", "-q", "--detach", merged)
        report = self.check(context=self.pr_context(merged))
        self.assertTrue(any(c["id"] == "merge:exact-admission-blob" and c["result"] == "FAIL" for c in report["checks"]))

    def testPRSHAHeadBaseRefAndRepositoryMismatchFail(self):
        merged = self.merge(self.foundation, self.head)
        self.git("checkout", "-q", "--detach", merged)
        for key in ("sha", "head", "base", "base-ref", "ref", "repository"):
            with self.subTest(key=key):
                context = self.pr_context(merged)
                if key in ("head", "base"):
                    context["event"]["pull_request"][key]["sha"] = self.legacy
                elif key == "base-ref":
                    context["event"]["pull_request"]["base"]["ref"] = "other"
                else:
                    context[key] = "wrong"
                self.check(context=context)

    def testPushBeforeAfterRefForcedAndDeletedMismatchFail(self):
        merged = self.merge(self.foundation, self.head)
        self.git("checkout", "-q", "--detach", merged)
        for key in ("before", "after", "ref", "forced", "deleted"):
            context = self.push_context(merged)
            context["event"][key] = True if key in ("forced", "deleted") else "wrong"
            self.check(context=context)

    def testMovedBaseNeedsFreshReviewEvenIfMergeTreeUnchanged(self):
        newer = self.merge(self.foundation, self.head)
        merged = self.merge(newer, self.head)
        self.git("checkout", "-q", "--detach", merged)
        self.check(context=self.pr_context(merged, base=newer))

    def testDirtyTrackedCheckoutFailsFormalEvent(self):
        merged = self.merge(self.foundation, self.head)
        self.git("checkout", "-q", "--detach", merged)
        self.write("Sources/Main.swift", "dirty source\n")
        self.check(context=self.pr_context(merged))
        self.check(merged, expected="PASS")  # Read-only historical object inspection remains exact.

    def testGitEnvironmentAndReplaceRefsCannotRedirectApprovedObjects(self):
        self.write("Sources/Main.swift", "unreviewed\n")
        changed = self.commit("unreviewed replacement")
        self.git("replace", self.source, changed)
        with patch.dict(os.environ, {"GIT_DIR": "/missing", "GIT_WORK_TREE": "/missing"}):
            self.check(self.head, expected="PASS")
            self.check(changed)

    def testIndexFlagsCannotHideChangedActualSource(self):
        merged = self.merge(self.foundation, self.head)
        self.git("checkout", "-q", "--detach", merged)
        for flag, clear in (("--assume-unchanged", "--no-assume-unchanged"),
                            ("--skip-worktree", "--no-skip-worktree")):
            with self.subTest(flag=flag):
                self.git("update-index", flag, "Sources/Main.swift")
                self.write("Sources/Main.swift", "hidden dirty compiler input\n")
                self.assertEqual(self.git("diff", "HEAD"), "")
                self.check(context=self.pr_context(merged))
                self.git("update-index", clear, "Sources/Main.swift")
                self.git("checkout", "HEAD", "--", "Sources/Main.swift")

    def testIgnoredOrUntrackedCompilerInputFailsButCIReportsDoNot(self):
        merged = self.merge(self.foundation, self.head)
        self.git("checkout", "-q", "--detach", merged)
        self.write("test-results/fixture.log", "source admission output\n")
        self.write("feedback-results/fixture.log", "source admission output\n")
        self.check(expected="PASS", context=self.pr_context(merged))
        self.write("Sources/Injected.swift", "untracked compiler input\n")
        self.check(context=self.pr_context(merged))
        self.write(".git/info/exclude", "Sources/Injected.swift\n")
        self.assertNotIn("Injected.swift", self.git("ls-files", "--others", "--exclude-standard"))
        self.check(context=self.pr_context(merged))

    def testSwiftPMConfigurationIsNotAnExemptOutput(self):
        merged = self.merge(self.foundation, self.head)
        self.git("checkout", "-q", "--detach", merged)
        self.write(".swiftpm/configuration/mirrors.json", '{"unreviewed":"configuration"}\n')
        self.check(context=self.pr_context(merged))

    def testBadFoundationOrEmptyPreservationPolicyFails(self):
        for policy in (replace(self.policy, foundation_tree="0" * 40),
                       replace(self.policy, foundation_parents=tuple(reversed(self.policy.foundation_parents))),
                       replace(self.policy, historical_gates=()),
                       replace(self.policy, historical_prefixes=()),
                       replace(self.policy, website_paths=())):
            self.check(policy=policy)

    def testFailingHistoricalAuditCannotBeIgnored(self):
        def fail(*args):
            return False, {"result": "FAIL", "checks": [{"result": "FAIL"}]}
        with patch.object(AUDIT, "legacy_audit", side_effect=fail):
            self.check()

    def testMissingFormalEventAndCLIApprovalOverrideFail(self):
        script = str(ROOT / "scripts/verify-mainline-composition.py")
        env = {k: v for k, v in os.environ.items() if not k.startswith("GITHUB_")}
        for args in (("--github-event",), ("--reviewed-source", self.head)):
            process = subprocess.run([sys.executable, "-B", script, *args], cwd=self.repo,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
            self.assertNotEqual(process.returncode, 0)


class WorkflowContractTests(unittest.TestCase):
    def testFormalMainEventsAreUnfilteredAndTokenRemainsReadOnly(self):
        for name in ("native-foundation.yml", "feedback-v01.yml"):
            text = (ROOT / ".github/workflows" / name).read_text()
            triggers = text.split("permissions:", 1)[0]
            self.assertIn("      - main\n", triggers)
            self.assertIn("  pull_request:\n    branches: [main]\n", triggers)
            self.assertNotIn("paths:", triggers)
            self.assertNotIn("paths-ignore:", triggers)
            self.assertNotIn("pull_request_target", text)
            self.assertIn("permissions:\n  contents: read\n", text)
            self.assertIn("persist-credentials: false", text)
            self.assertIn("verify-mainline-composition.py --github-event", text)

    def testRequiredNamesArchitecturesAndFullExecutionArePreserved(self):
        native = (ROOT / ".github/workflows/native-foundation.yml").read_text()
        feedback = (ROOT / ".github/workflows/feedback-v01.yml").read_text()
        for name in ("Native source admission", "Native ARM64", "Native Intel"):
            self.assertIn(name, native)
            self.assertNotIn(name, feedback)
        for name in ("Feedback source admission", "Feedback native and service"):
            self.assertIn(name, feedback)
            self.assertNotIn(name, native)
        for marker in ("runner: macos-15\n", "runner: macos-15-intel\n", "swift test --parallel",
                       "scripts/build-macos.sh", "scripts/package-internal-beta.sh", "capture-quiet-edge-r2-evidence.py"):
            self.assertIn(marker, native)
        for marker in ("services/feedback/feedback.test.mjs", "services/feedback/retention.test.mjs",
                       "RiftletFeedbackTests|RiftletFeedbackUITests", "FeedbackCloseTests", "build-feedback-demo.sh"):
            self.assertIn(marker, feedback)
        self.assertNotIn("continue-on-error:", native + feedback)


if __name__ == "__main__":
    unittest.main()
