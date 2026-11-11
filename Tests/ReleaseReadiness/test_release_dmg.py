"""Outer DMG tests. Apple credentials and service replies are simulated, never obtained."""
import argparse
from contextlib import ExitStack
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/release-dmg.py"
SPEC = importlib.util.spec_from_file_location("riftlet_dmg_test", SCRIPT)
D = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(D)
R = D.R
TEAM = "TESTTEAM01"
APP_JOB = "cc20ed50-4ec3-4da0-8eb3-008352c8c224"
DMG_JOB = "ac37f4bf-786e-457a-818e-5a8f44f939ad"


class OuterImageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ws = Path(self.temp.name).resolve()
        self.package = self.ws / R.PAYLOAD
        (self.package / R.APP).mkdir(parents=True)
        self.folder = self.ws / "formal-dmg"
        self.pin = "a" * 64
        self.manifest = {"stage": "STAPLED", "signature": {"teamID": TEAM},
                         "notarization": {"submissionID": APP_JOB},
                         "build": {"source": {"commit": "b" * 40}, "version": "0.3.1", "build": "4", "architectures": ["arm64"]}}
        logfile = self.ws / "notary-query-app" / (APP_JOB + ".notary-log.json")
        loghash = "2" * 64
        logfile.parent.mkdir()
        R.write_json(logfile, {"jobId": APP_JOB, "status": "Accepted", "sha256": loghash})
        self.manifest["notarization"].update(status="Accepted", uploadSHA256=loghash,
            logPath=str(logfile.relative_to(self.ws)), logSHA256=R.digest(logfile))
        self.calls = []
        self.inspections = []
        self.uncertain = False
        self.notary_status = "Accepted"
        self.wrong_log = False
        self.submitted_sha = None
        self.external_check = None
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        def mock(owner, name, value):
            self.stack.enter_context(patch.object(owner, name, value))
        def verified_package(path, pin, team):
            self.assertEqual((path, pin, team), (self.package, self.pin, TEAM))
            return self.manifest
        mock(R, "verify_package", verified_package)
        mock(R.platform, "system", lambda: "Darwin")
        mock(R, "identity_available", lambda fp, team: None)
        def build(app, manifest, image, attempt):
            self.assertEqual(app, self.package / R.APP)
            image.write_bytes(b"controlled synthetic image")
        mock(D, "build_image", build)
        mock(D, "inspect_image", lambda image, manifest, attempt: self.inspections.append(R.digest(image)))
        mock(R, "run", self.native)

    def native(self, args, **kwargs):
        self.calls.append(tuple(str(v) for v in args))
        stdout = stderr = b""
        if args[0] == "/usr/bin/codesign" and "-d" in args:
            stderr = (f"Identifier={D.DMG_ID}\nAuthority=Developer ID Application: Fixture ({TEAM})\n"
                      f"TeamIdentifier={TEAM}\nTimestamp=fixture-time\nCDHash={'1' * 40}\n").encode()
        elif args[:3] == ["xcrun", "notarytool", "submit"]:
            upload = Path(args[3])
            self.submitted_sha = R.digest(upload)
            self.assertEqual(upload.stat().st_mode & 0o777, 0o400)
            if self.uncertain: raise subprocess.TimeoutExpired(args, 180)
            stdout = json.dumps({"id": DMG_JOB}).encode()
        elif args[:3] == ["xcrun", "notarytool", "info"]:
            stdout = json.dumps({"id": args[3], "status": self.notary_status}).encode()
        elif args[:3] == ["xcrun", "notarytool", "log"]:
            R.write_json(Path(args[-1]), {"jobId": args[3], "status": self.notary_status,
                                         "sha256": "0" * 64 if self.wrong_log else self.submitted_sha})
        elif args[:3] == ["xcrun", "stapler", "staple"]:
            image = Path(args[-1]); image.write_bytes(image.read_bytes() + b"-simulated-ticket")
        elif args[0] == "/usr/sbin/spctl":
            if "--status" in args: stdout = b"assessments enabled\n"
            else:
                if self.external_check: self.external_check(args)
                stdout = plistlib.dumps({"assessment:verdict": True})
        elif args[0] not in ("/usr/bin/codesign", "/usr/sbin/spctl") and args[:3] != ["xcrun", "stapler", "validate"]:
            raise AssertionError(args)
        return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr=stderr)

    def op(self, name, **kwargs):
        args = dict(command=name, workspace=self.ws, manifest_sha256=self.pin, team=TEAM, execute=True,
                    allow_network=True, identity="f" * 40, profile="offline-fixture", submission_id=None)
        return D.operate(argparse.Namespace(**(args | kwargs)))

    def refuse(self, code, fn, *args, **kwargs):
        with self.assertRaises(R.ReleaseError) as fail:
            fn(*args, **kwargs)
        self.assertEqual(fail.exception.code, code)

    def accepted(self):
        self.op("create"); self.op("submit"); self.op("status")

    def test_requires_explicit_execution_and_stapled_app(self):
        self.refuse("explicit_execution_and_network_flags_required", self.op, "create", execute=False)
        self.manifest["stage"] = "PREPARED"
        self.refuse("formal_dmg_requires_stapled_app", self.op, "create")
        self.assertFalse(self.folder.exists())

    def test_direct_dmg_rejects_replaced_retained_app_log_before_signing(self):
        log = self.ws / self.manifest["notarization"]["logPath"]
        log.write_text("substituted log")
        self.refuse("accepted_app_log_digest_mismatch", self.op, "create")
        self.assertFalse(self.folder.exists())
        self.assertEqual(self.calls, [])

    def test_full_two_identities_and_repeat_finish_without_submission(self):
        self.accepted()
        a = self.op("finish")
        self.assertEqual(self.op("finish"), a)
        self.assertEqual((a["submissionID"], a["appSubmissionID"]), (DMG_JOB, APP_JOB))
        self.assertEqual(a["stage"], "VERIFIED_STAPLED_DMG")
        self.assertEqual(a["archive"], "Riftlet-0.3.1-4-arm64.dmg")
        self.assertEqual(a["sha256"], R.digest(self.folder / a["archive"]))
        self.assertNotEqual(a["signedSHA256"], a["sha256"])
        self.assertEqual(a["signedSHA256"], self.submitted_sha)
        self.assertEqual(sum(c[:3] == ("xcrun", "notarytool", "submit") for c in self.calls), 1)
        self.assertTrue(any("--timestamp" in c and "--identifier" in c for c in self.calls))
        self.assertTrue(any("context:primary-signature" in c for c in self.calls))
        self.assertEqual(R.read_json(self.folder / "state.json")["stage"], "VERIFIED_STAPLED_DMG")

    def test_unknown_only_reconciles_original_dmg_hash_never_app_job_or_second_submit(self):
        self.op("create"); self.uncertain = True
        self.refuse("dmg_submission_uncertain_query_original_job", self.op, "submit")
        self.refuse("dmg_submit_requires_signed_once", self.op, "submit")
        self.refuse("original_dmg_submission_id_required", self.op, "status")
        self.refuse("dmg_wrong_notary_job", self.op, "status", submission_id=APP_JOB)
        self.wrong_log = True
        self.refuse("dmg_notary_log_artifact_mismatch", self.op, "status", submission_id=DMG_JOB)
        self.notary_status = "In Progress"
        self.assertIsNone(self.op("status", submission_id=DMG_JOB)["submissionID"])
        self.notary_status = "Accepted"; self.wrong_log = False
        self.assertEqual(self.op("status", submission_id=DMG_JOB)["stage"], "ACCEPTED")
        self.assertEqual(sum(c[:3] == ("xcrun", "notarytool", "submit") for c in self.calls), 1)

    def test_rejected_dmg_never_staples_despite_app_stapled(self):
        self.op("create"); self.op("submit"); self.notary_status = "Invalid"
        self.assertEqual(self.op("status")["stage"], "REJECTED")
        self.refuse("dmg_finish_requires_accepted_job", self.op, "finish")
        self.assertFalse((self.folder / "dmg-receipt.json").exists())

    def test_changed_uploaded_dmg_or_terminal_log_cannot_be_finished(self):
        self.accepted()
        state = R.read_json(self.folder / "state.json")
        signed = self.folder / state["signedImage"]; original = signed.read_bytes()
        signed.write_bytes(b"different dmg")
        self.refuse("dmg_bytes_mismatch", self.op, "finish")
        signed.write_bytes(original)
        (self.folder / state["notaryLog"]).write_bytes(b"other log")
        self.refuse("dmg_bytes_mismatch", self.op, "finish")

    def test_gatekeeper_failure_leaves_no_release_receipt(self):
        self.accepted()
        def reject(args):
            self.assertIn("open", args)
            raise R.ReleaseError("gatekeeper_rejected_fixture")
        self.external_check = reject
        self.refuse("gatekeeper_rejected_fixture", self.op, "finish")
        self.assertFalse((self.folder / "dmg-receipt.json").exists())

    def test_receipt_link_interruption_resumes_exact_partial_candidate(self):
        self.accepted()
        real = os.link
        def crash(source, dest, **kwargs):
            if Path(dest).name == "dmg-receipt.json": raise OSError("injected interruption after DMG published")
            real(source, dest, **kwargs)
        with patch.object(D.os, "link", side_effect=crash), self.assertRaisesRegex(OSError, "injected"):
            self.op("finish")
        state = R.read_json(self.folder / "state.json")
        self.assertEqual(state["stage"], "PUBLISHING")
        final = self.folder / state["name"]
        self.assertEqual(R.digest(final), state["finalSHA256"])
        self.assertFalse((self.folder / "dmg-receipt.json").exists())
        done = self.op("finish")
        self.assertEqual(done["sha256"], state["finalSHA256"])
        self.assertEqual(sum(c[:3] == ("xcrun", "stapler", "staple") for c in self.calls), 1)

    def test_conflicting_existing_file_is_never_overwritten(self):
        self.accepted()
        final = self.folder / "Riftlet-0.3.1-4-arm64.dmg"
        final.write_bytes(b"unrelated")
        self.refuse("conflicting_final_dmg", self.op, "finish")
        self.assertEqual(final.read_bytes(), b"unrelated")
        self.assertFalse((self.folder / "dmg-receipt.json").exists())

    def test_modified_completed_dmg_is_rejected_on_repeat(self):
        self.accepted(); receipt = self.op("finish")
        (self.folder / receipt["archive"]).write_bytes(b"modified")
        self.refuse("dmg_bytes_mismatch", self.op, "finish")

    def test_repeat_verification_never_recreates_missing_completed_outputs(self):
        self.accepted(); receipt = self.op("finish")
        (self.folder / receipt["archive"]).unlink()
        self.refuse("completed_dmg_outputs_missing", self.op, "finish")
        self.assertFalse((self.folder / receipt["archive"]).exists())

    def test_disabled_assessment_or_false_verdict_is_not_acceptance(self):
        for enabled, verdict, expected in [(False, True, "gatekeeper_assessment_disabled"),
                                            (True, False, "gatekeeper_verdict_not_accepted")]:
            with self.subTest(enabled=enabled, verdict=verdict):
                def spctl(args, **kwargs):
                    out = (b"assessments enabled" if enabled else b"assessments disabled") if "--status" in args else plistlib.dumps({"assessment:verdict": verdict})
                    return subprocess.CompletedProcess(args, 0, out, b"")
                with patch.object(R, "run", side_effect=spctl):
                    self.refuse(expected, D.assess, self.ws / "fixture.dmg", "open", self.ws)

    def test_private_operation_lock_blocks_concurrent_submission(self):
        self.op("create")
        with (self.folder / ".operation-lock").open("rb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.refuse("dmg_operation_already_running", self.op, "submit")
        self.assertFalse(any(c[:3] == ("xcrun", "notarytool", "submit") for c in self.calls))


class NativeImageTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin", "native hdiutil/ditto require macOS")
    def test_real_readonly_image_checks_app_and_link_and_detaches_without_launch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            package = root / "pkg"; app = package / R.APP
            (app / "Contents/Resources/empty").mkdir(parents=True)
            item = app / "Contents/Resources/fixture"; item.write_bytes(b"synthetic only")
            app.chmod(0o700)
            old_manifest = {"files": R.inventory(package)}
            with self.assertRaises(R.ReleaseError) as blocked:
                D.verify_app_tree(app, old_manifest)
            self.assertIn("distribution_app_mode_mismatch", blocked.exception.code)
            R.normalize_staged_app(package)
            manifest = {"files": R.inventory(package), "signature": {"teamID": TEAM}, "build": {"architectures": ["arm64"]}}
            image = root / "unsigned-fixture.dmg"
            D.build_image(app, manifest, image, root)
            self.assertEqual(root.stat().st_mode & 0o777, 0o700)
            self.assertEqual((root / "image-source").stat().st_mode & 0o777, 0o755)
            raw = R.run; calls = []
            def run(args, **kwargs):
                calls.append(tuple(str(v) for v in args))
                if args[0] == "/usr/sbin/spctl":
                    out = b"assessments enabled" if "--status" in args else plistlib.dumps({"assessment:verdict": True})
                    return subprocess.CompletedProcess(args, 0, out, b"")
                if args[:3] == ["xcrun", "stapler", "validate"]:
                    return subprocess.CompletedProcess(args, 0, b"", b"")
                return raw(args, **kwargs)
            with patch.object(R, "run", side_effect=run), patch.object(R, "verify_signature", return_value=manifest["signature"]):
                D.inspect_image(image, manifest, root)
                manifest["files"][R.APP + "/Contents/Resources/fixture"]["sha256"] = "0" * 64
                with self.assertRaises(R.ReleaseError) as failed: D.inspect_image(image, manifest, root)
            self.assertEqual(failed.exception.code, "dmg_app_inventory_mismatch")
            self.assertFalse(any(os.path.ismount(m) for m in root.glob("mount-*")))
            self.assertEqual(sum(c[:2] == ("/usr/bin/hdiutil", "detach") for c in calls), 2)
            self.assertTrue(any("--type" in c and "execute" in c for c in calls))


if __name__ == "__main__":
    unittest.main()
