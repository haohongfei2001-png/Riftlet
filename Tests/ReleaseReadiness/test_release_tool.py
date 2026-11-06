"""Offline release identity/state tests. All Apple signing/network calls are mocked."""
import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_tool", ROOT / "scripts/release-tool.py")
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
TEAM = "ABCDE12345"
IDENTITY = "A" * 40
JOB = "11111111-2222-4333-8444-555555555555"


def thin(arch="arm64"):
    cpu = {v: k for k, v in R.ARCHES.items()}[arch]
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 0, 0, 0, 0)


def fat():
    return (struct.pack(">2I", 0xCAFEBABE, 2)
            + struct.pack(">5I", 0x01000007, 0, 64, 32, 4)
            + struct.pack(">5I", 0x0100000C, 0, 96, 32, 4)
            + b"\0" * 16 + thin("x86_64") + thin("arm64"))


def signature(arches=("arm64",)):
    return {"teamID": TEAM, "hardenedRuntime": True, "entitlements": dict(R.ENTITLEMENTS),
            "architectures": {arch: {"cdhash": "b" * 40, "timestamp": "Nov 6, 2026 at 08:00:00"} for arch in arches}}


def result(out=b"", err=b"", code=0):
    return subprocess.CompletedProcess([], code, out, err)


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="riftlet-release-test-")
        self.root = Path(self.temporary.name).resolve()
        self.workspace = self.root / "workspace"; self.workspace.mkdir()
        self.package = self.workspace / R.PAYLOAD; self.package.mkdir()
        self.app = self.package / R.APP
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/Resources").mkdir()
        binary = self.app / "Contents/MacOS/Riftlet"
        binary.write_bytes(thin()); binary.chmod(0o755)
        info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        info.update(CFBundleShortVersionString="0.2.0", CFBundleVersion="2", RiftletVersionLabel="Beta 2", RiftletBuildChannel="release-candidate")
        del info["RiftletDeveloperIDSigned"]; del info["RiftletNotarized"]
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        resources = self.app / "Contents/Resources/Riftlet_RiftletAdapters.bundle"
        resources.mkdir()
        for name in R.BUNDLE.RESOURCE_NAMES:
            (resources / name).write_text("/* synthetic fixture only */\n")
        for name in R.BUNDLE.NOTICE_NAMES:
            path = self.app / "Contents/Resources/ThirdPartyNotices" / name
            path.parent.mkdir(parents=True, exist_ok=True); path.write_text("fixture notice\n")
        shutil.copy2(ROOT / "packaging/release/INSTALL-zh-CN.txt", self.package / "INSTALL-zh-CN.txt")
        self.receipt = {"schemaVersion": 1, "source": {"commit": "a" * 40, "tree": "c" * 40,
                        "inputs": {key: "d" * 40 for key in R.BUILD_INPUTS}}, "version": "0.2.0", "build": "2",
                        "bundleIdentifier": "com.riftlet.app", "minimumMacOS": "13.0", "architectures": ["arm64"],
                        "ordinaryBuildInfo": {"internalAcceptance": False, "mode": "capture", "dataDirectory": "Riftlet",
                           "input": True, "start": True, "completion": True, "builtInUpload": True,
                           "safeRetry": False, "continuation": True}, "buildInfoExecutedOn": "arm64",
                        "infoPlistSHA256": R.digest(self.app / "Contents/Info.plist"), "dataCompatibility": "NOT_ASSERTED",
                        "preparationInputs": {key: R.digest(ROOT / key) for key in R.PREPARATION_INPUTS},
                        "swiftVersion": "synthetic fixture; no compiler invoked"}
        R.write_json(self.app / R.RECEIPT, self.receipt)
        self.manifest = {"schemaVersion": 1, "kind": R.KIND, "stage": "PREPARED", "build": self.receipt,
                         "sourceAdmission": "INDEPENDENT_REVIEW_REQUIRED", "signature": None, "notarization": None}
        self.save()

    def tearDown(self):
        self.temporary.cleanup()

    def save(self):
        R.save_manifest(self.package, self.manifest)

    def error(self, code, fn, *args, **kwargs):
        with self.assertRaises(R.ReleaseError) as caught:
            fn(*args, **kwargs)
        self.assertEqual(caught.exception.code, code)
        return caught.exception

    def stage(self, stage):
        self.manifest["stage"] = stage
        if stage not in {"PREPARED", "SIGN_FAILED"}:
            self.manifest["signature"] = signature()
        if stage.startswith("NOTARY") or stage in {"NOTARIZED", "STAPLED", "STAPLE_FAILED"}:
            unknown = stage in {"NOTARY_SUBMITTING", "NOTARY_SUBMISSION_UNKNOWN"}
            self.manifest["notarization"] = {"status": "SubmissionUnknown" if unknown else "In Progress" if stage == "NOTARY_IN_PROGRESS" else "Invalid" if stage == "NOTARY_REJECTED" else "Accepted",
                "submissionID": None if unknown else JOB, "uploadSHA256": R.sha(b"upload"), "stapled": stage == "STAPLED"}
            if stage in {"NOTARY_REJECTED", "NOTARIZED", "STAPLED", "STAPLE_FAILED"}:
                self.manifest["notarization"]["logSHA256"] = "e" * 64
        self.save()

    def args(self, **kwargs):
        base = {"workspace": self.workspace, "execute": True, "allow_network": True,
                "identity": IDENTITY, "team": TEAM, "profile": "offline-test-profile", "submission_id": None}
        return argparse.Namespace(**(base | kwargs))

    def archive(self, additions=(), mutate=None):
        archive = self.root / "candidate.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as out:
            for path in sorted(self.package.rglob("*")):
                name = R.PAYLOAD + "/" + path.relative_to(self.package).as_posix() + ("/" if path.is_dir() else "")
                info = zipfile.ZipInfo(name); info.create_system = 3
                info.external_attr = path.stat().st_mode << 16
                data = b"" if path.is_dir() else path.read_bytes()
                if mutate:
                    info, data = mutate(info, data)
                out.writestr(info, data)
            for info, data in additions:
                out.writestr(info, data)
        return archive

    def test_prepared_full_inventory_and_pin_match(self):
        self.assertEqual(R.verify_package(self.package, R.digest(self.package / R.MANIFEST))["stage"], "PREPARED")

    def test_actual_binary_architecture_disagrees_with_receipt(self):
        (self.app / "Contents/MacOS/Riftlet").write_bytes(thin("x86_64")); self.save()
        self.error("binary_arch_mismatch", R.verify_package, self.package)

    def test_macho_universal_reads_both_actual_slices(self):
        self.assertEqual(R.macho_arches(fat()), ["arm64", "x86_64"])
        self.assertEqual(R.macho_arches(thin("x86_64")), ["x86_64"])

    def test_macho_rejects_overlapping_and_mismatched_slices(self):
        data = bytearray(fat()); struct.pack_into(">I", data, 36, 64)
        self.error("overlapping_fat_slices", R.macho_arches, data)
        data = bytearray(fat()); data[96:128] = thin("x86_64")
        self.error("fat_slice_arch_mismatch", R.macho_arches, data)

    def test_macho_rejects_truncation_and_non_executable(self):
        self.error("truncated_macho", R.macho_arches, thin()[:16])
        data = bytearray(thin()); struct.pack_into("<I", data, 12, 6)
        self.error("macho_not_executable", R.macho_arches, data)

    def test_payload_tampered_notice_and_mode_are_detected(self):
        notice = self.app / "Contents/Resources/ThirdPartyNotices/Screenshoss/LICENSE"
        notice.write_text("changed")
        self.error("payload_inventory_mismatch", R.verify_package, self.package)
        self.save(); notice.chmod(0o777)
        self.error("payload_inventory_mismatch", R.verify_package, self.package)

    def test_stable_xattrs_are_checked_and_download_quarantine_is_not_removed(self):
        path = self.package / "INSTALL-zh-CN.txt"
        def write(key, value):
            if hasattr(os, "setxattr"): os.setxattr(path, key, value.encode())
            elif Path("/usr/bin/xattr").exists():
                subprocess.run(["/usr/bin/xattr", "-w", key, value, str(path)], check=True, capture_output=True)
            else: self.skipTest("filesystem has no xattr API")
        try:
            write("com.riftlet.release-fixture", "first")
            write("com.apple.quarantine", "synthetic offline fixture")
        except (OSError, subprocess.CalledProcessError):
            self.skipTest("filesystem does not support macOS user xattrs")
        self.save(); R.verify_package(self.package)
        if hasattr(os, "getxattr"):
            quarantine = os.getxattr(path, "com.apple.quarantine")
        else:
            quarantine = subprocess.run(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(path)], check=True, capture_output=True).stdout.rstrip(b"\n")
        self.assertEqual(quarantine, b"synthetic offline fixture")
        self.assertNotIn("com.apple.quarantine", self.manifest["files"]["INSTALL-zh-CN.txt"]["xattrs"])
        write("com.riftlet.release-fixture", "different")
        self.error("payload_inventory_mismatch", R.verify_package, self.package)

    def test_extra_payload_and_symlink_are_rejected(self):
        (self.package / "unexpected.txt").write_text("extra")
        self.error("invalid_payload_layout", R.verify_package, self.package)
        (self.package / "unexpected.txt").unlink()
        (self.app / "Contents/Resources/link").symlink_to(self.root)
        self.error("unsafe_payload_entry", R.verify_package, self.package)

    def test_hardlink_and_linked_parent_are_rejected(self):
        os.link(self.package / "INSTALL-zh-CN.txt", self.app / "Contents/Resources/linked.txt")
        self.error("hard_linked_payload_entry", R.inventory, self.package)
        shortcut = self.root / "shortcut"; shortcut.symlink_to(self.workspace, target_is_directory=True)
        self.error("linked_path", R.verify_package, shortcut / R.PAYLOAD)

    def test_manifest_pin_and_duplicate_json_keys_rejected(self):
        self.error("manifest_pin_mismatch", R.verify_package, self.package, "0" * 64)
        self.error("duplicate_json_key", R.decode_json, b'{"stage":"SIGNED","stage":"STAPLED"}')

    def test_linked_manifest_is_rejected_before_reading_its_target_hash(self):
        outside = self.root / "unrelated.txt"; outside.write_text("unrelated private fixture")
        manifest = self.package / R.MANIFEST; manifest.unlink(); manifest.symlink_to(outside)
        with patch.object(R, "digest", side_effect=AssertionError("must not read linked target")):
            self.error("missing_or_linked_json", R.verify_package, self.package, "0" * 64)

    def test_boolean_schema_and_unadmitted_source_claim_rejected(self):
        self.manifest["schemaVersion"] = True; self.save()
        self.error("invalid_manifest", R.verify_package, self.package)
        self.manifest["schemaVersion"] = 1; self.manifest["sourceAdmission"] = "PASS"; self.save()
        self.error("manifest_cannot_admit_source", R.verify_package, self.package)

    def test_recorded_stapled_stage_requires_real_receipt_fields(self):
        self.manifest["stage"] = "STAPLED"; self.save()
        self.error("invalid_signature_receipt", R.verify_package, self.package)
        self.stage("STAPLED"); self.manifest["notarization"]["stapled"] = False; self.save()
        self.error("staple_stage_mismatch", R.verify_package, self.package)

    def test_receipt_and_plist_cannot_drift_together_unnoticed(self):
        info_path = self.app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes()); info["NSAppleEventsUsageDescription"] = "Different purpose text for receipt mismatch"
        info_path.write_bytes(plistlib.dumps(info)); self.save()
        self.error("plist_receipt_mismatch", R.verify_package, self.package)

    def test_full_source_sha_and_positive_build_are_required(self):
        self.error("full_source_sha_required", R.full_sha, "HEAD")
        for build in ("0", "-1", "01", 2):
            with self.subTest(build=build): self.error("invalid_build", R.version_values, "0.2.0", build)

    def test_staging_explicit_version_label_preserves_source_identity_and_other_keys(self):
        original = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        info = dict(original)
        source = R.stage_version(info, "0.3.0", "3", "Beta 3")
        self.assertEqual(source, {key: original[key] for key in
                                  ("CFBundleShortVersionString", "CFBundleVersion", "RiftletVersionLabel")})
        self.assertEqual(info["RiftletVersionLabel"], "Beta 3")
        self.assertEqual(info["CFBundleShortVersionString"], "0.3.0")
        self.assertEqual(info["CFBundleVersion"], "3")
        changed = {"CFBundleShortVersionString", "CFBundleVersion", "RiftletVersionLabel", "RiftletBuildChannel"}
        self.assertEqual({k: v for k, v in info.items() if k not in changed},
                         {k: v for k, v in original.items() if k not in changed})

    def test_label_is_explicit_and_rejects_empty_control_or_padded_text(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            R.parser().parse_args(["build", "--source", "a" * 40, "--version", "0.3.0", "--build", "3",
                                   "--arch", "arm64", "--workspace", str(self.root / "not-created")])
        for label in (None, "", " ", "Beta 3\n", "Beta\t3", "x" * 65):
            with self.subTest(label=repr(label)):
                self.error("invalid_version_label", R.version_label, label)

    def test_new_receipt_binds_label_and_both_version_provenances(self):
        self.receipt.update(versionLabel="Beta 2", sourceVersion={"CFBundleShortVersionString": "0.1.0",
                            "CFBundleVersion": "1", "RiftletVersionLabel": "Beta 1"})
        R.write_json(self.app / R.RECEIPT, self.receipt); self.save()
        R.verify_package(self.package)
        info_path = self.app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes()); info["RiftletVersionLabel"] = "stale label"
        info_path.write_bytes(plistlib.dumps(info)); self.receipt["infoPlistSHA256"] = R.digest(info_path)
        R.write_json(self.app / R.RECEIPT, self.receipt); self.save()
        self.error("invalid_release_RiftletVersionLabel", R.verify_package, self.package)
        del self.receipt["sourceVersion"]
        self.error("invalid_source_version", R.validate_receipt, self.receipt)

    def review_native(self, *, corrupt_mount=False, fail_detach=False, change_source=False):
        calls = []
        def native(args, **kwargs):
            calls.append([str(x) for x in args])
            if args[0] == "/usr/bin/ditto":
                if "-c" in args: shutil.copyfile(self.archive(), args[-1])
                else: shutil.copytree(args[-2], args[-1])
                return result()
            self.assertEqual(args[0], "/usr/bin/hdiutil")
            if args[1] == "create": Path(args[-1]).write_bytes(b"synthetic DMG, no Apple service")
            elif args[1] == "attach":
                self.assertTrue(all(flag in args for flag in ("-readonly", "-nobrowse", "-noautoopen")))
                mount = Path(args[args.index("-mountpoint") + 1])
                shutil.copytree(self.workspace / "review-image-source", mount, dirs_exist_ok=True)
                if corrupt_mount: (mount / R.PAYLOAD / "INSTALL-zh-CN.txt").write_text("tampered")
                if change_source: (self.package / "INSTALL-zh-CN.txt").write_text("changed while packaging")
                return result(plistlib.dumps({"system-entities": [{"mount-point": str(mount)}]}))
            elif args[1] == "detach":
                if fail_detach: raise R.ReleaseError("synthetic_detach_failure")
                self.mock_mounted = False
            else: self.assertEqual(args[1], "verify")
            return result()
        self.mock_mounted = True
        return calls, native

    def review_args(self):
        return self.args(manifest_sha256=R.digest(self.package / R.MANIFEST))

    def test_review_container_checks_both_formats_without_promoting_candidate(self):
        before = (self.package / R.MANIFEST).read_bytes(); calls, native = self.review_native()
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native), \
                patch.object(R.os.path, "ismount", side_effect=lambda _: self.mock_mounted):
            answer = R.package_review(self.review_args())
        self.assertEqual(answer["status"], "REVIEW_ONLY")
        self.assertEqual(answer["notarization"], "NOT_NOTARIZED")
        self.assertEqual(answer["installation"], "NOT_RUN")
        self.assertEqual(answer["gatekeeper"], "NOT_RUN")
        self.assertEqual(set(answer["artifacts"]), {"zip", "dmg"})
        self.assertEqual(before, (self.package / R.MANIFEST).read_bytes())
        self.assertTrue(all(c[0] in {"/usr/bin/ditto", "/usr/bin/hdiutil"} for c in calls))
        self.assertEqual(sum(c[1] == "detach" for c in calls), 1)
        self.assertTrue((self.workspace / "review-distribution/review-artifacts.json").is_file())

    def test_review_refuses_wrong_pin_before_native_tool_or_output(self):
        with patch.object(R.platform, "system", return_value="Darwin"), \
                patch.object(R, "run", side_effect=AssertionError("pin fails before subprocess")):
            self.error("manifest_pin_mismatch", R.package_review, self.args(manifest_sha256="0" * 64))
        self.assertFalse((self.workspace / "review-distribution").exists())

    def test_review_never_relabels_signed_or_failed_candidate_and_formal_gate_stays_closed(self):
        with patch.object(R.platform, "system", return_value="Darwin"), \
                patch.object(R, "run", side_effect=AssertionError("no tools for wrong stage")):
            self.error("distribution_requires_stapled_candidate", R.package_candidate, self.args())
            for stage in ("SIGNED", "SIGN_FAILED", "NOTARIZED", "STAPLED"):
                self.manifest.update(signature=None, notarization=None)
                self.stage(stage)
                self.error("review_package_requires_prepared_candidate", R.package_review, self.review_args())
        self.assertFalse((self.workspace / "review-distribution").exists())

    def test_review_mount_tamper_detaches_and_never_publishes_success_receipt(self):
        calls, native = self.review_native(corrupt_mount=True)
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native), \
                patch.object(R.os.path, "ismount", side_effect=lambda _: self.mock_mounted):
            self.error("payload_inventory_mismatch", R.package_review, self.review_args())
        self.assertTrue(any(c[1] == "detach" for c in calls))
        self.assertFalse((self.workspace / "review-distribution/review-artifacts.json").exists())

    def test_review_detach_failure_preserves_evidence_and_prevents_success(self):
        calls, native = self.review_native(fail_detach=True)
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native), \
                patch.object(R.os.path, "ismount", side_effect=lambda _: self.mock_mounted):
            self.error("synthetic_detach_failure", R.package_review, self.review_args())
        self.assertTrue(any(p.suffix == ".dmg" for p in (self.workspace / "review-distribution").iterdir()))
        self.assertFalse((self.workspace / "review-distribution/review-artifacts.json").exists())

    def test_review_rechecks_original_source_and_preserves_existing_output(self):
        calls, native = self.review_native(change_source=True)
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native), \
                patch.object(R.os.path, "ismount", side_effect=lambda _: self.mock_mounted):
            self.error("payload_inventory_mismatch", R.package_review, self.review_args())
        self.assertFalse((self.workspace / "review-distribution/review-artifacts.json").exists())
        (self.package / "INSTALL-zh-CN.txt").write_bytes((ROOT / "packaging/release/INSTALL-zh-CN.txt").read_bytes())
        with patch.object(R.platform, "system", return_value="Darwin"), \
                patch.object(R, "run", side_effect=AssertionError("must preserve previous attempt")):
            self.error("review_distribution_already_exists", R.package_review, self.review_args())

    def test_archive_pin_verifies_without_extracting_or_executing(self):
        archive = self.archive(); before = sorted(p.relative_to(self.root).as_posix() for p in self.root.rglob("*"))
        with patch.object(R, "run", side_effect=AssertionError("no subprocess for archive verification")):
            answer = R.verify_archive(archive, R.digest(archive))
        self.assertEqual(answer["status"], "OFFLINE_ARCHIVE_IDENTITY_MATCH")
        self.assertEqual(answer["nativeSignatureCheck"], "NOT_RUN")
        self.assertEqual(before, sorted(p.relative_to(self.root).as_posix() for p in self.root.rglob("*")))

    def test_archive_requires_external_pin(self):
        archive = self.archive()
        self.error("trusted_archive_pin_required", R.verify_archive, archive, None)
        self.error("archive_pin_mismatch", R.verify_archive, archive, "0" * 64)

    @unittest.skipUnless(Path("/usr/bin/ditto").exists(), "native macOS ditto only")
    def test_native_ditto_archive_matches_read_only_verifier(self):
        archive = self.root / "native-ditto.zip"
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(self.package), str(archive)], check=True, capture_output=True)
        with patch.object(R, "run", side_effect=AssertionError("read only verification")):
            self.assertEqual(R.verify_archive(archive, R.digest(archive))["status"], "OFFLINE_ARCHIVE_IDENTITY_MATCH")

    def test_archive_rejects_path_aliases_and_traversal(self):
        for name in ("../outside", "/Riftlet-Release/outside", "Riftlet-Release/a/../b", "Riftlet-Release//alias", "Riftlet-Release/./alias", "Riftlet-Release\\alias"):
            with self.subTest(name=name):
                archive = self.archive([(zipfile.ZipInfo(name), b"bad")])
                self.error("unsafe_archive_path", R.verify_archive, archive, R.digest(archive))

    def test_archive_rejects_symlink_and_case_duplicate(self):
        linked = zipfile.ZipInfo(R.PAYLOAD + "/link"); linked.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive = self.archive([(linked, b"/Applications/Riftlet.app")])
        self.error("unsafe_archive_entry", R.verify_archive, archive, R.digest(archive))
        archive = self.archive([(zipfile.ZipInfo(R.PAYLOAD + "/install-zh-cn.txt"), b"different")])
        self.error("duplicate_archive_path", R.verify_archive, archive, R.digest(archive))

    def test_archive_hash_and_mode_changes_are_detected(self):
        def change_bytes(info, data):
            return info, b"corrupt" if info.filename.endswith("INSTALL-zh-CN.txt") else data
        archive = self.archive(mutate=change_bytes)
        self.error("archive_file_mismatch", R.verify_archive, archive, R.digest(archive))
        def change_mode(info, data):
            if info.filename.endswith("/MacOS/Riftlet"): info.external_attr = (stat.S_IFREG | 0o644) << 16
            return info, data
        archive = self.archive(mutate=change_mode)
        self.error("archive_mode_mismatch", R.verify_archive, archive, R.digest(archive))

    def test_missing_credentials_never_call_tools_or_mutate(self):
        before = R.inventory(self.package)
        with patch.object(R, "run", side_effect=AssertionError("must not call native tools")):
            error = self.error("developer_team_required", R.sign_candidate, self.args(team=None))
            self.assertEqual(error.status, "BLOCKED_CREDENTIALS")
            self.error("notary_keychain_profile_required", R.notary_submit, self.args(profile=None))
            self.error("developer_team_required", R.preflight, self.args(team=None))
        self.assertEqual(before, R.inventory(self.package))

    def test_signing_requires_two_explicit_execution_flags(self):
        with patch.object(R, "run", side_effect=AssertionError("must not call native tools")):
            error = self.error("explicit_execution_and_network_flags_required", R.sign_candidate, self.args(execute=False))
            self.assertEqual(error.status, "PLAN_ONLY")
            self.error("explicit_execution_and_network_flags_required", R.sign_candidate, self.args(allow_network=False))

    def test_unavailable_configured_identity_remains_credential_block(self):
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", return_value=result(b"0 valid identities found\n")):
            error = self.error("configured_developer_id_identity_unavailable", R.sign_candidate, self.args())
        self.assertEqual(error.status, "BLOCKED_CREDENTIALS")
        self.assertEqual(R.read_json(self.package / R.MANIFEST)["stage"], "PREPARED")

    def test_signing_uses_hardened_timestamp_and_refreshes_changed_inventory(self):
        calls = []
        def native(args, **kwargs):
            calls.append(args)
            if args[0] == "security": return result((IDENTITY + ' "Developer ID Application: Test (' + TEAM + ')"\n').encode())
            if "--sign" in args:
                (self.app / "Contents/_CodeSignature").mkdir()
                (self.app / "Contents/_CodeSignature/CodeResources").write_bytes(b"synthetic signature seal")
                return result()
            raise AssertionError(args)
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native), patch.object(R, "verify_signature", return_value=signature()):
            self.assertEqual(R.sign_candidate(self.args())["status"], "SIGNED")
        self.assertIn("--timestamp", calls[1]); self.assertIn("runtime", calls[1]); self.assertNotIn("--deep", calls[1])
        self.assertEqual(R.verify_package(self.package)["stage"], "SIGNED")
        self.assertIn(R.APP + "/Contents/_CodeSignature/CodeResources", R.read_json(self.package / R.MANIFEST)["files"])

    def test_signing_failure_preserves_partial_files_and_stops_resign(self):
        def native(args, **kwargs):
            if args[0] == "security": return result((IDENTITY + ' "Developer ID Application: Test (' + TEAM + ')"\n').encode())
            (self.app / "Contents/Resources/partial-signature-fixture").write_bytes(b"failure evidence")
            raise R.ReleaseError("sign_fixture_failure")
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native):
            self.error("sign_fixture_failure", R.sign_candidate, self.args())
            self.error("sign_requires_prepared_workspace", R.sign_candidate, self.args())
        self.assertEqual(R.verify_package(self.package)["stage"], "SIGN_FAILED")
        self.assertEqual((self.app / "Contents/Resources/partial-signature-fixture").read_bytes(), b"failure evidence")

    def test_signature_checks_each_arch_and_no_debug_exemptions(self):
        commands = []
        def native(args, **kwargs):
            commands.append(args)
            if "--entitlements" in args: return result(plistlib.dumps(R.ENTITLEMENTS))
            if "-d" in args:
                return result(err=("Identifier=com.riftlet.app\nTeamIdentifier=" + TEAM + "\nAuthority=Developer ID Application: Test (" + TEAM + ")\n"
                              "CodeDirectory v=20500 size=123 flags=0x10000(runtime)\nTimestamp=Nov 6, 2026 at 08:00:00\nCDHash=" + "b" * 40 + "\n").encode())
            return result()
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native):
            value = R.verify_signature(self.app, TEAM, ["arm64", "x86_64"])
        self.assertEqual(set(value["architectures"]), {"arm64", "x86_64"})
        self.assertEqual(len(commands), 5); self.assertIn("--all-architectures", commands[0])
        self.assertIn("certificate leaf[subject.OU]", commands[0][5])
        for entitlements in ({**R.ENTITLEMENTS, "com.apple.security.get-task-allow": True}, {"com.apple.security.automation.apple-events": 1}):
            def unsafe(args, **kwargs):
                return result(plistlib.dumps(entitlements)) if "--entitlements" in args else native(args, **kwargs)
            with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=unsafe):
                self.error("unexpected_entitlements", R.verify_signature, self.app, TEAM, ["arm64"])

    def test_signature_rejects_wrong_team_adhoc_no_runtime_or_timestamp(self):
        good = "Identifier=com.riftlet.app\nTeamIdentifier=" + TEAM + "\nAuthority=Developer ID Application: Test\nflags=0x10000(runtime)\nTimestamp=recorded\nCDHash=" + "b" * 40 + "\n"
        cases = [(good.replace(TEAM, "OTHER12345"), "wrong_signature_identity"),
                 (good.replace("Authority=Developer ID Application: Test", "Signature=adhoc"), "not_developer_id_application"),
                 (good.replace("0x10000(runtime)", "0x0(none)"), "hardened_runtime_missing"),
                 (good.replace("Timestamp=recorded", "Timestamp=none"), "secure_timestamp_missing")]
        for detail, expected in cases:
            with self.subTest(expected=expected), patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", return_value=result(err=detail.encode())):
                self.error(expected, R.verify_signature, self.app, TEAM, ["arm64"])

    def test_uncertain_notary_submit_is_once_and_keeps_archive_identity(self):
        self.stage("SIGNED"); calls = []
        def native(args, **kwargs):
            calls.append(args)
            if args[0] == "/usr/bin/ditto": Path(args[-1]).write_bytes(b"upload"); return result()
            if "submit" in args: raise subprocess.TimeoutExpired(args, 180, output=b"response lost")
            raise AssertionError(args)
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "verify_signature", return_value=signature()), patch.object(R, "run", side_effect=native):
            self.error("submission_uncertain_query_original_job_do_not_resubmit", R.notary_submit, self.args())
            self.error("submit_requires_signed_once", R.notary_submit, self.args())
        self.assertEqual(sum("submit" in c for c in calls), 1)
        value = R.verify_package(self.package)
        self.assertEqual(value["stage"], "NOTARY_SUBMISSION_UNKNOWN")
        self.assertEqual(value["notarization"]["uploadSHA256"], R.sha(b"upload"))

    def test_unknown_submission_requires_original_id_without_any_network(self):
        self.stage("NOTARY_SUBMISSION_UNKNOWN")
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=AssertionError("no guessed job")):
            error = self.error("original_submission_id_required_no_resubmit", R.notary_status, self.args())
        self.assertEqual(error.status, "BLOCKED_RECONCILIATION")

    def test_accepted_notary_status_binds_job_and_original_upload_hash(self):
        self.stage("NOTARY_IN_PROGRESS"); calls = []
        def native(args, **kwargs):
            calls.append(args)
            if "info" in args: return result(R.encoded({"id": JOB, "status": "Accepted"}))
            if "log" in args:
                R.write_json(args[-1], {"jobId": JOB, "status": "Accepted", "sha256": R.sha(b"upload")}); return result()
            raise AssertionError(args)
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native):
            self.assertEqual(R.notary_status(self.args())["status"], "NOTARIZED")
        self.assertTrue(all("submit" not in c for c in calls))
        self.assertFalse(R.verify_package(self.package)["notarization"]["stapled"])

    def test_other_artifact_log_never_marks_accepted(self):
        self.stage("NOTARY_IN_PROGRESS")
        def native(args, **kwargs):
            if "info" in args: return result(R.encoded({"id": JOB, "status": "Accepted"}))
            R.write_json(args[-1], {"jobId": JOB, "status": "Accepted", "sha256": "0" * 64}); return result()
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=native):
            self.error("notary_log_artifact_mismatch", R.notary_status, self.args())
            self.error("cannot_switch_notary_job", R.notary_status, self.args(submission_id="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"))
        self.assertEqual(R.verify_package(self.package)["stage"], "NOTARY_IN_PROGRESS")

    def test_staple_requires_accepted_and_failure_is_preserved(self):
        self.stage("SIGNED")
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "run", side_effect=AssertionError("not accepted")):
            self.error("staple_requires_accepted_job", R.staple_candidate, self.args())
        self.stage("NOTARIZED")
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "verify_signature", return_value=signature()), patch.object(R, "run", side_effect=R.ReleaseError("simulated_stapler_failure")):
            self.error("simulated_stapler_failure", R.staple_candidate, self.args())
        self.assertEqual(R.verify_package(self.package)["stage"], "STAPLE_FAILED")

    def test_staple_success_retains_code_identity_and_updates_manifest(self):
        self.stage("NOTARIZED")
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "verify_signature", return_value=signature()), patch.object(R, "run", return_value=result()):
            self.assertEqual(R.staple_candidate(self.args())["status"], "STAPLED")
        self.assertTrue(R.verify_package(self.package)["notarization"]["stapled"])

    def test_distribution_pins_final_archive_and_refuses_overwrite(self):
        self.stage("STAPLED")
        fixture_zip = self.archive()
        def native(args, **kwargs):
            self.assertEqual(args[0], "/usr/bin/ditto")
            shutil.copyfile(fixture_zip, args[-1]); return result()
        with patch.object(R.platform, "system", return_value="Darwin"), patch.object(R, "verify_signature", return_value=signature()), patch.object(R, "run", side_effect=native):
            value = R.package_candidate(self.args())
            self.error("distribution_already_exists", R.package_candidate, self.args())
        artifact = R.read_json(self.workspace / "distribution/release-artifact.json")
        self.assertEqual(artifact["sha256"], R.digest(fixture_zip))
        self.assertEqual(value["status"], "PACKAGED_NOT_PUBLISHED")
        self.assertEqual(artifact["gatekeeper"], "NOT_RUN")
        self.assertEqual(artifact["publicReleaseApproval"], "NOT_GRANTED_BY_TOOL")

    def test_update_plan_does_not_copy_launch_or_claim_data_compatibility(self):
        self.stage("STAPLED")
        current = self.root / "Current.app"; shutil.copytree(self.app, current)
        path = current / "Contents/Info.plist"; info = plistlib.loads(path.read_bytes())
        info["CFBundleVersion"] = "1"; path.write_bytes(plistlib.dumps(info))
        before = {str(p): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        args = self.args(package=self.package, manifest_sha256=R.digest(self.package / R.MANIFEST), current_app=current)
        with patch.object(R.platform, "machine", return_value="arm64"), patch.object(R, "verify_signature", return_value=signature()), patch.object(R, "run", side_effect=AssertionError("must not launch app")):
            value = R.update_plan(args)
        self.assertEqual(value["direction"], "upgrade"); self.assertEqual(value["actionsPerformed"], [])
        self.assertEqual(value["dataCompatibility"], "REVIEW_REQUIRED")
        self.assertEqual(before, {str(p): p.read_bytes() for p in self.root.rglob("*") if p.is_file()})

    def test_rollback_is_not_approved_by_smaller_build_number(self):
        self.stage("STAPLED")
        current = self.root / "Current.app"; shutil.copytree(self.app, current)
        path = current / "Contents/Info.plist"; info = plistlib.loads(path.read_bytes()); info["CFBundleVersion"] = "3"; path.write_bytes(plistlib.dumps(info))
        args = self.args(package=self.package, manifest_sha256=R.digest(self.package / R.MANIFEST), current_app=current)
        with patch.object(R.platform, "machine", return_value="arm64"), patch.object(R, "verify_signature", return_value=signature()):
            value = R.update_plan(args)
        self.assertEqual(value["direction"], "rollback")
        self.assertEqual(value["rollback"], "BLOCKED_UNTIL_CURRENT_DATA_COMPATIBILITY_IS_PROVEN")

    def test_existing_and_app_install_workspaces_are_never_overwritten(self):
        self.error("output_already_exists", R.fresh_workspace, self.workspace)
        self.error("installed_app_location_forbidden", R.fresh_workspace, "/Applications/nonexistent-riftlet-release-fixture")
        self.error("app_output_location_forbidden", R.fresh_workspace, self.root / "Foreign.app/staging")

    def test_command_arguments_are_never_shell_expanded_and_failure_logs_survive(self):
        literal = "$(touch should-not-exist); `echo nope`"
        log = self.root / "failure.log"
        with patch.object(R.subprocess, "run", return_value=result(b"out", b"error", 7)) as native:
            self.error("command_failed_example", R.run, ["example", literal], log=log)
        self.assertEqual(native.call_args.args[0], ["example", literal])
        self.assertNotIn("shell", native.call_args.kwargs)
        self.assertEqual(log.read_bytes(), b"outerror")

    def test_export_uses_exact_commit_even_when_working_tree_is_dirty(self):
        repository = self.root / "repo"; repository.mkdir()
        def git(*args):
            return subprocess.run(["git", "-C", str(repository), *args], capture_output=True, check=True).stdout.decode().strip()
        git("init", "-q"); git("config", "user.name", "Offline fixture"); git("config", "user.email", "fixture@invalid.example")
        for item in R.BUILD_INPUTS:
            target = repository / item
            if item.endswith(".swift"): target.write_text("committed package\n")
            else: target.mkdir(); (target / "fixture.txt").write_text("committed content\n")
        git("add", "."); git("commit", "-qm", "offline fixture")
        source = git("rev-parse", "HEAD")
        (repository / "Sources/fixture.txt").write_text("unreviewed dirty bytes\n")
        target = self.root / "export"; target.mkdir()
        source_identity = R.export_source(repository, source, target)
        self.assertEqual((target / "Sources/fixture.txt").read_text(), "committed content\n")
        self.assertEqual(source_identity["commit"], source)
        self.assertEqual(source_identity["tree"], git("rev-parse", "HEAD^{tree}"))

    def test_preflight_cli_reports_blocked_not_pass(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), patch.object(R, "run", side_effect=AssertionError("credentials absent")):
            code = R.main(["preflight"])
        self.assertEqual(code, 3)
        self.assertEqual(json.loads(output.getvalue())["status"], "BLOCKED_CREDENTIALS")


if __name__ == "__main__":
    unittest.main()
