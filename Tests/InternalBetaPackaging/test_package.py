"""Package/launcher regressions; synthetic Mach-O header, no GUI or real open."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("beta_package", REPOSITORY / "scripts/verify-internal-beta-package.py")
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class InternalBetaPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="riftlet beta $(literal) ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = self.root / "Riftlet Internal Beta"
        self.contents = self.package / "Riftlet.app/Contents"
        self.binary = self.contents / "MacOS/Riftlet"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"\xcf\xfa\xed\xfeSYNTHETIC-NONEXECUTABLE-FIXTURE")
        self.binary.chmod(0o755)
        shutil.copy2(REPOSITORY / "Resources/Info.plist", self.contents / "Info.plist")
        bundle = self.contents / "Resources/Riftlet_RiftletAdapters.bundle"
        bundle.mkdir(parents=True)
        for name in VERIFY.BUNDLE.RESOURCE_NAMES:
            shutil.copy2(REPOSITORY / "Sources/RiftletAdapters/Resources" / name, bundle / name)
        shutil.copytree(REPOSITORY / "ThirdPartyNotices", self.contents / "Resources/ThirdPartyNotices")
        for name in (VERIFY.ENTRY, VERIFY.README):
            shutil.copy2(REPOSITORY / "packaging/internal-beta" / name, self.package / name)
        (self.package / VERIFY.ENTRY).chmod(0o755)
        self.manifest = {"schemaVersion": 1, "kind": "internal-beta-development",
                         "sourceHeadSHA": "a" * 40, "checkoutSHA": "b" * 40,
                         "realAcceptanceSourceSHA": "c" * 40, "realAcceptanceEvidenceSHA": "d" * 40,
                         "launchArgument": "--system-screenshot-candidate",
                         "ordinaryAppDefault": "capture-upload-disabled",
                         "dataDirectory": "Riftlet-System-Screenshot-Candidate",
                         "feedbackEndpointConfigured": False, "feedbackDelivery": "local-outbox-only",
                         "buildInputObjects": {path: "e" * 40 for path in VERIFY.INPUTS},
                         "sha256": VERIFY.package_hashes(self.package)}
        self.save_manifest()
        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.calls = self.root / "open-arguments"
        fake_open = self.fake_bin / "open"
        fake_open.write_text('#!/bin/sh\nprintf "%s\\0" "$@" > "$RIFTLET_TEST_OPEN_ARGS"\n')
        fake_open.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(self.fake_bin) + os.pathsep + os.environ["PATH"],
                                RIFTLET_TEST_OPEN_ARGS=str(self.calls))

    def save_manifest(self):
        (self.package / "build-info.json").write_text(json.dumps(self.manifest))

    def launch(self):
        return subprocess.run(["bash", str(self.package / VERIFY.ENTRY)], cwd=self.root,
                              env=self.environment, capture_output=True, text=True)

    def test_complete_package_is_verified_without_launch(self):
        result = VERIFY.verify_package(self.package)
        self.assertEqual(result["launchArgument"], "--system-screenshot-candidate")
        self.assertFalse(self.calls.exists())

    def test_launcher_uses_adjacent_app_and_one_explicit_mode_with_spaces(self):
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.calls.read_bytes().decode().split("\0")[:-1]
        self.assertEqual(arguments, ["-n", "-a", str((self.package / "Riftlet.app").resolve()),
                                     "--args", "--system-screenshot-candidate"])

    def test_missing_executable_does_not_launch_or_fall_back_to_installed_app(self):
        self.binary.unlink()
        result = self.launch()
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.calls.exists())

    def test_modified_launcher_and_resource_are_rejected(self):
        launcher = self.package / VERIFY.ENTRY
        original = launcher.read_text()
        launcher.write_text(original.replace("--system-screenshot-candidate", "--simulate"))
        with self.assertRaisesRegex(ValueError, "package_source_mismatch"):
            VERIFY.verify_package(self.package, REPOSITORY)
        launcher.write_text(original)
        page = self.contents / "Resources/Riftlet_RiftletAdapters.bundle/chatgpt-web-20261027.js"
        page.write_text(page.read_text() + "\n// stale package\n")
        with self.assertRaisesRegex(ValueError, "package_hash_mismatch"):
            VERIFY.verify_package(self.package)

    def test_linked_entry_and_missing_execute_permission_are_rejected(self):
        launcher = self.package / VERIFY.ENTRY
        launcher.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "launcher_not_executable"):
            VERIFY.verify_package(self.package)
        launcher.unlink()
        launcher.symlink_to(REPOSITORY / "packaging/internal-beta" / VERIFY.ENTRY)
        with self.assertRaisesRegex(ValueError, "unsafe_package_entry"):
            VERIFY.verify_package(self.package)

    def test_wrong_mode_or_cloud_success_claim_is_rejected(self):
        self.manifest["ordinaryAppDefault"] = "production-upload-enabled"
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "invalid_launch_profile"):
            VERIFY.verify_package(self.package)
        self.manifest["ordinaryAppDefault"] = "capture-upload-disabled"
        self.manifest["feedbackEndpointConfigured"] = True
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "invalid_feedback_boundary"):
            VERIFY.verify_package(self.package)

    def test_incomplete_build_identity_is_rejected(self):
        self.manifest["buildInputObjects"].pop("Sources")
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "invalid_build_inputs"):
            VERIFY.verify_package(self.package)


if __name__ == "__main__":
    unittest.main()
