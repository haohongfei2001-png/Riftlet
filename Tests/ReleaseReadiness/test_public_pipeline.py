import importlib.util
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("riftlet_public_pipeline", Path(__file__).resolve().parents[2] / "scripts/release-macos.py")
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class PublicReleasePipelineTests(unittest.TestCase):
    def test_identity_discovery_requires_a_unique_valid_developer_id(self):
        output = ('  1) ' + 'A'*40 + ' "Apple Development: Example (A234567890)"\n'
                  '  2) ' + 'B'*40 + ' "Developer ID Application: First (B234567890)"\n'
                  '  3) ' + 'C'*40 + ' "Developer ID Application: Second (C234567890)"\n')
        with patch.object(P.R, "run", return_value=SimpleNamespace(stdout=output.encode())):
            with self.assertRaisesRegex(P.R.ReleaseError, "select_one_developer_id_identity"):
                P.select_signer(None, None)
            self.assertEqual(P.select_signer(None, "B234567890"), ("B"*40, "B234567890"))
            with self.assertRaisesRegex(P.R.ReleaseError, "developer_id_identity_unavailable"):
                P.select_signer("A"*40, None)

    def test_unacknowledged_dmg_query_stays_pending_without_binding_or_resubmitting(self):
        queried = []
        def query():
            queried.append(True)
            return {"stage": "SUBMISSION_UNKNOWN", "queryStatus": "In Progress", "queriedSubmissionID": "original"}
        result = P.wait_for_notary(query, 0)
        self.assertEqual(result, {"status": "PENDING_NOTARIZATION", "submissionID": "original"})
        self.assertEqual(queried, [True])

    def test_lost_app_submission_never_calls_submit_again(self):
        with patch.object(P.R, "notary_submit", side_effect=AssertionError("replayed submission")), \
             patch.object(P.R, "load_package_for_resume", return_value={}), \
             patch.object(P.R, "notary_status", return_value={"status":"NOTARY_IN_PROGRESS", "submissionID":"original"}) as lookup:
            result = P.prepare_app(Path("/unused"), Path("/unused/package"), "NOTARY_SUBMISSION_UNKNOWN",
                                   None, "A234567890", "profile", "original", 0)
            self.assertEqual(result, {"status":"PENDING_NOTARIZATION","submissionID":"original"})
            self.assertEqual(lookup.call_args.args[0].submission_id, "original")

    def test_staple_retry_reuses_accepted_app(self):
        with patch.object(P.R, "verify_package", return_value={}), patch.object(P.R, "verify_accepted_app_log"), \
             patch.object(P.R, "load_package_for_resume", return_value={"signature":{"teamID":"A234567890"}}), \
             patch.object(P.R, "notary_submit", side_effect=AssertionError("resubmitted")), \
             patch.object(P.R, "staple_candidate") as staple:
            self.assertIsNone(P.prepare_app(Path("/unused"), Path("/unused/package"), "STAPLE_FAILED", None,
                                            "A234567890", None, None, 0))
            staple.assert_called_once()

    def test_preparation_is_bound_to_requested_source_and_version_on_resume(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp).resolve()
            opts = SimpleNamespace(source="a"*40, version="0.3.2", build="5", label="Release Candidate", arch=None)
            record = {"stage":"PREPARED","build":{"source":{"commit":"a"*40},"version":"0.3.2","build":"5",
                      "versionLabel":"Release Candidate","architectures":["arm64","x86_64"]}}
            with patch.object(P.R, "load_package_for_resume", return_value=record), \
                 patch.object(P.R, "build_candidate", side_effect=AssertionError("overwrote workspace")):
                self.assertEqual(P.prepared_package(opts, workspace)[1], record)
                opts.build = "6"
                with self.assertRaisesRegex(P.R.ReleaseError, "workspace_belongs_to_another_release"):
                    P.prepared_package(opts, workspace)

    @unittest.skipUnless(sys.platform == "darwin", "requires the actual macOS codesign tool")
    def test_reads_the_public_leaf_from_a_real_signed_binary(self):
        with tempfile.TemporaryDirectory() as tmp:
            fp = P.signer_fingerprint(Path("/usr/bin/codesign"), Path(tmp).resolve())
            self.assertRegex(fp, r"^[0-9A-F]{40}$")

    def test_app_job_can_be_reconciled_before_another_signing_key_is_available(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp).resolve()
            args = SimpleNamespace(workspace=workspace, wait_seconds=0, prepare_only=False, team=None,
                                   identity=None, profile="fixture", app_submission_id="original", dmg_submission_id=None)
            value = {"stage":"NOTARY_SUBMISSION_UNKNOWN","signature":{"teamID":"A234567890"}}
            with patch.object(P, "prepared_package", return_value=(workspace / "package", value)), \
                 patch.object(P, "select_signer", side_effect=AssertionError("unnecessary private key")), \
                 patch.object(P.R, "run", return_value=SimpleNamespace(stdout=b"{}")), \
                 patch.object(P.R, "load_package_for_resume", return_value=value), \
                 patch.object(P.R, "notary_submit", side_effect=AssertionError("duplicate submission")), \
                 patch.object(P.R, "notary_status", return_value={"status":"NOTARY_IN_PROGRESS","submissionID":"original"}):
                self.assertEqual(P.release(args), {"status":"PENDING_NOTARIZATION","submissionID":"original","component":"App"})

    def test_finished_dmg_rechecks_artifact_without_signing_or_notary_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp).resolve()
            package = workspace / "Riftlet-Release"
            folder = workspace / "formal-dmg"
            package.mkdir(); folder.mkdir()
            (package / P.R.MANIFEST).write_bytes(b"pinned fixture")
            image = folder / "Riftlet-0.3.2-5-universal.dmg"
            image.write_bytes(b"controlled verified payload")
            P.R.write_json(folder / "state.json", {"stage":"PUBLISHING"})
            options = SimpleNamespace(workspace=workspace, prepare_only=False, identity=None, team=None, profile=None,
                app_submission_id=None, dmg_submission_id=None, wait_seconds=0, source="a"*40, version="0.3.2", build="5")
            manifest = {"stage":"STAPLED","signature":{"teamID":"A234567890"}}
            receipt = {"stage":"VERIFIED_STAPLED_DMG","archive":image.name,"sha256":P.R.digest(image),
                "architectures":["arm64","x86_64"],"submissionID":"dmg-id","appSubmissionID":"app-id"}
            with patch.object(P, "prepared_package", return_value=(package, manifest)), \
                 patch.object(P, "prepare_app", return_value=None), \
                 patch.object(P, "select_signer", side_effect=AssertionError("unnecessary private key")), \
                 patch.object(P.R, "run", side_effect=AssertionError("no account call needed")), \
                 patch.object(P, "signer_fingerprint", return_value="B"*40), \
                 patch.object(P, "dmg_step", return_value=receipt) as finish:
                result = P.release(options)
                self.assertEqual([c.args[0] for c in finish.call_args_list], ["finish"])
                self.assertEqual(result["artifact"], str(image))
                self.assertFalse(result["published"])
                image.write_bytes(b"substituted bytes")
                with self.assertRaisesRegex(P.R.ReleaseError, "final_dmg_identity_mismatch"):
                    P.release(options)

    def test_workspace_lock_excludes_another_publisher(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp).resolve() / "version"
            with P.release_lock(path), self.assertRaisesRegex(P.R.ReleaseError, "release_workspace_busy"):
                with P.release_lock(path):
                    self.fail("second publisher entered")


if __name__ == "__main__":
    unittest.main()
