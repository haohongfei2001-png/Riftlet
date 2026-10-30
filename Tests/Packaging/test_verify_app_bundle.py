"""Synthetic layout tests; no executable is run or signed by this suite."""

import importlib.util
import json
import os
import subprocess
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "verify_app_bundle", REPOSITORY / "scripts/verify-app-bundle.py")
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class BundleVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="riftlet-bundle-test-")
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "Riftlet.app"
        self.contents = self.app / "Contents"
        self.binary = self.contents / "MacOS/Riftlet"
        self.binary.parent.mkdir(parents=True)
        # Deliberately not a runnable program. Native execution belongs to CI.
        self.binary.write_bytes(b"\xcf\xfa\xed\xfeSYNTHETIC-NONEXECUTABLE-FIXTURE")
        self.binary.chmod(0o755)
        self.plist = self.contents / "Info.plist"
        shutil.copy2(REPOSITORY / "Resources/Info.plist", self.plist)
        self.resources = self.contents / "Resources"
        self.bundle = self.resources / "Riftlet_RiftletAdapters.bundle"
        self.bundle.mkdir(parents=True)
        for name in VERIFY.RESOURCE_NAMES:
            shutil.copy2(REPOSITORY / "Sources/RiftletAdapters/Resources" / name, self.bundle / name)
        shutil.copytree(REPOSITORY / "ThirdPartyNotices", self.resources / "ThirdPartyNotices")

    def alter_plist(self, key, value):
        info = plistlib.loads(self.plist.read_bytes())
        if value is None:
            info.pop(key, None)
        else:
            info[key] = value
        self.plist.write_bytes(plistlib.dumps(info))

    def assert_rejected(self, code, repository=None):
        with self.assertRaisesRegex(VERIFY.VerificationError, "^" + code + "$"):
            VERIFY.verify_bundle(self.app, repository)

    def test_current_bundle_and_exact_source_resources(self):
        result = VERIFY.verify_bundle(self.app, REPOSITORY)
        self.assertEqual(result["channel"], "development")
        self.assertFalse(result["developer_id_signed"])
        self.assertFalse(result["notarized"])

    def test_internal_ordinary_channel_is_explicit_and_exact(self):
        info = plistlib.loads(self.plist.read_bytes())
        self.plist.write_bytes(plistlib.dumps(VERIFY.ordinary_acceptance_plist(info)))
        with self.assertRaises(VERIFY.VerificationError):
            VERIFY.verify_bundle(self.app, REPOSITORY)
        result = VERIFY.verify_bundle(self.app, REPOSITORY, "ordinary-acceptance")
        self.assertEqual(result["channel"], "ordinary-acceptance")
        for key, value in (("UnexpectedAdmission", True), ("NSDownloadsFolderUsageDescription", "A different sufficiently long permission text")):
            with self.subTest(key=key):
                self.plist.write_bytes(plistlib.dumps(VERIFY.ordinary_acceptance_plist(info)))
                self.alter_plist(key, value)
                with self.assertRaisesRegex(VERIFY.VerificationError, "^plist_differs_from_source$"):
                    VERIFY.verify_bundle(self.app, REPOSITORY, "ordinary-acceptance")

    def test_ordinary_channel_does_not_accept_product_bundle_or_weaken_resources(self):
        with self.assertRaisesRegex(VERIFY.VerificationError, "^invalid_CFBundleIdentifier$"):
            VERIFY.verify_bundle(self.app, REPOSITORY, "ordinary-acceptance")
        self.plist.write_bytes(plistlib.dumps(VERIFY.ordinary_acceptance_plist(plistlib.loads(self.plist.read_bytes()))))
        (self.bundle / VERIFY.RESOURCE_NAMES[0]).write_text("// changed")
        with self.assertRaisesRegex(VERIFY.VerificationError, "^resource_differs_from_source_"):
            VERIFY.verify_bundle(self.app, REPOSITORY, "ordinary-acceptance")

    def test_internal_binary_identity_rejects_wrong_root_mode_policy_and_types(self):
        valid = {"internalAcceptance": True, "mode": "capture", "dataDirectory": "Riftlet-Ordinary-Acceptance",
                 "input": True, "start": True, "completion": True, "safeRetry": False, "continuation": False}
        VERIFY.verify_ordinary_build_info(valid)
        for key, value in (("internalAcceptance", False), ("dataDirectory", "Riftlet"), ("mode", "systemScreenshotCandidate"),
                           ("input", False), ("start", 1), ("completion", False), ("safeRetry", True), ("continuation", True),
                           ("extra", True)):
            with self.subTest(key=key):
                with self.assertRaises(VERIFY.VerificationError):
                    VERIFY.verify_ordinary_build_info({**valid, key: value})

    def test_development_binary_identity_remains_closed_and_cannot_be_mislabeled(self):
        valid = {"internalAcceptance": False, "mode": "capture", "dataDirectory": "Riftlet",
                 "input": False, "start": False, "completion": False, "safeRetry": False, "continuation": False}
        VERIFY.verify_ordinary_build_info(valid, "development")
        with self.assertRaises(VERIFY.VerificationError):
            VERIFY.verify_ordinary_build_info(valid, "ordinary-acceptance")
        for key, value in (("internalAcceptance", True), ("dataDirectory", "Riftlet-Ordinary-Acceptance"),
                           ("input", True), ("start", True), ("completion", True), ("safeRetry", True),
                           ("continuation", True), ("input", 0)):
            with self.subTest(key=key):
                with self.assertRaises(VERIFY.VerificationError):
                    VERIFY.verify_ordinary_build_info({**valid, key: value}, "development")

    def test_internal_build_mocked_pipeline_preserves_product_and_previous_outputs(self):
        # Mock Swift and codesign only: this proves orchestration, not native compilation/signing.
        root = Path(self.temporary.name) / "repo"
        (root / "scripts").mkdir(parents=True)
        for name in ("build-macos.sh", "build-ordinary-acceptance.sh", "verify-app-bundle.py"):
            shutil.copy2(REPOSITORY / "scripts" / name, root / "scripts" / name)
        for name in ("Resources", "ThirdPartyNotices", "Sources/RiftletAdapters/Resources"):
            shutil.copytree(REPOSITORY / name, root / name)
        product = root / "build/Riftlet.app"
        product.mkdir(parents=True)
        (product / "sentinel").write_bytes(b"original production package")
        fake_product = root / "fake-products"
        fake_product.mkdir()
        shutil.copy2(self.binary, fake_product / "Riftlet")
        shutil.copytree(self.bundle, fake_product / self.bundle.name)
        commands = root / "commands"
        commands.mkdir()
        log = root / "commands.jsonl"
        for name in ("swift", "codesign", "uname"):
            command = commands / name
            command.write_text("#!/usr/bin/env python3\n"
                "import json, os, pathlib, sys\n"
                "with open(os.environ['RIFTLET_TEST_LOG'], 'a') as f: f.write(json.dumps([pathlib.Path(sys.argv[0]).name, *sys.argv[1:]]) + '\\n')\n"
                "if pathlib.Path(sys.argv[0]).name == 'uname': print('Darwin')\n"
                "if pathlib.Path(sys.argv[0]).name == 'swift' and '--show-bin-path' in sys.argv: print(os.environ['RIFTLET_TEST_PRODUCTS'])\n")
            command.chmod(0o755)
        # A synthetic Mach-O cannot execute. The mock signer temporarily substitutes
        # a Python identity responder which restores the fixture before returning.
        responder = ("#!/usr/bin/env python3\nimport json, os, pathlib\n"
            "pathlib.Path(__file__).write_bytes((pathlib.Path(os.environ['RIFTLET_TEST_PRODUCTS']) / 'Riftlet').read_bytes())\n"
            "internal = os.environ.get('RIFTLET_TEST_INTERNAL', '1') == '1'\n"
            "print(json.dumps({'internalAcceptance': internal, 'mode': 'capture', 'dataDirectory': 'Riftlet-Ordinary-Acceptance' if internal else 'Riftlet', "
            "'input': internal, 'start': internal, 'completion': internal, 'safeRetry': False, 'continuation': False}))\n")
        signer = commands / "codesign"
        with signer.open("a") as output:
            output.write("if '--verify' in sys.argv: (pathlib.Path(sys.argv[-1]) / 'Contents/MacOS/Riftlet').write_text(" + repr(responder) + ")\n")
        env = {**os.environ, "PATH": str(commands) + os.pathsep + os.environ["PATH"],
               "RIFTLET_TEST_LOG": str(log), "RIFTLET_TEST_PRODUCTS": str(fake_product)}
        for _ in range(2):
            result = subprocess.run(["bash", str(root / "scripts/build-ordinary-acceptance.sh")],
                                    env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        outputs = list((root / "build").glob(".riftlet-package.*/Riftlet Ordinary Test.app"))
        self.assertEqual(len(outputs), 2)
        for output in outputs:
            VERIFY.verify_bundle(output, root, "ordinary-acceptance")
        self.assertEqual((product / "sentinel").read_bytes(), b"original production package")
        self.assertEqual(list((root / "build").glob(".ordinary-acceptance-swift.*")), [])
        invocations = [json.loads(line) for line in log.read_text().splitlines()]
        swift = [call for call in invocations if call[0] == "swift"]
        self.assertEqual(len(swift), 4)
        for call in swift:
            self.assertIn("RIFTLET_ORDINARY_ACCEPTANCE", call)
            self.assertIn("--scratch-path", call)
            self.assertIn(".ordinary-acceptance-swift.", call[call.index("--scratch-path") + 1])
        self.assertEqual(len([call for call in invocations if call[:3] == ["codesign", "--verify", "--strict"]]), 2)
        # Ordinary packaging must reject an accidentally internal binary before
        # replacing any previous product, even with a development plist.
        rejected = subprocess.run(["bash", str(root / "scripts/build-macos.sh")], env=env, text=True, capture_output=True)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual((product / "sentinel").read_bytes(), b"original production package")
        accepted = subprocess.run(["bash", str(root / "scripts/build-macos.sh")],
                                  env={**env, "RIFTLET_TEST_INTERNAL": "0"}, text=True, capture_output=True)
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        VERIFY.verify_bundle(product, root)
        self.assertEqual(len(list((root / "build").glob(".riftlet-package.*/Riftlet Ordinary Test.app"))), 2)

    def test_mac_resource_bundle_layout_and_post_signing_directory(self):
        nested = self.bundle / "Contents/Resources"
        nested.mkdir(parents=True)
        for name in VERIFY.RESOURCE_NAMES:
            (self.bundle / name).rename(nested / name)
        signature = self.contents / "_CodeSignature"
        signature.mkdir()
        (signature / "CodeResources").write_text("synthetic signature placeholder")
        VERIFY.verify_bundle(self.app, REPOSITORY)

    def test_missing_or_malformed_plist_is_closed_failure(self):
        self.plist.unlink()
        self.assert_rejected("missing_info_plist")
        self.plist.write_bytes(b"not a plist")
        self.assert_rejected("invalid_info_plist")

    def test_renamed_executable_cannot_pass(self):
        self.alter_plist("CFBundleExecutable", "Other")
        self.assert_rejected("invalid_CFBundleExecutable")

    def test_missing_non_macho_and_non_executable_binary_rejected(self):
        original = self.binary.read_bytes()
        self.binary.unlink()
        self.assert_rejected("missing_executable")
        self.binary.write_bytes(b"#!/bin/sh\n")
        self.binary.chmod(0o755)
        self.assert_rejected("invalid_executable_format")
        self.binary.write_bytes(original)
        self.binary.chmod(0o644)
        self.assert_rejected("executable_not_executable")

    def test_missing_usage_description_and_wrong_minimum_os_rejected(self):
        for key in VERIFY.USAGE_KEYS:
            with self.subTest(key=key):
                shutil.copy2(REPOSITORY / "Resources/Info.plist", self.plist)
                self.alter_plist(key, " ")
                self.assert_rejected("invalid_" + key)
        shutil.copy2(REPOSITORY / "Resources/Info.plist", self.plist)
        self.alter_plist("LSMinimumSystemVersion", "12.0")
        self.assert_rejected("invalid_LSMinimumSystemVersion")

    def test_false_public_release_metadata_rejected(self):
        for key, value in (("RiftletBuildChannel", "release"),
                           ("RiftletDeveloperIDSigned", True), ("RiftletNotarized", True),
                           ("LSUIElement", 1)):
            with self.subTest(key=key):
                shutil.copy2(REPOSITORY / "Resources/Info.plist", self.plist)
                self.alter_plist(key, value)
                self.assert_rejected("invalid_" + key)

    def test_missing_and_duplicate_page_resources_rejected(self):
        name = VERIFY.RESOURCE_NAMES[0]
        resource = self.bundle / name
        original = resource.read_bytes()
        resource.unlink()
        self.assert_rejected("missing_or_ambiguous_" + name.replace(".", r"\."))
        resource.write_bytes(original)
        duplicate = self.bundle / "Contents/Resources" / name
        duplicate.parent.mkdir(parents=True)
        duplicate.write_bytes(original)
        self.assert_rejected("missing_or_ambiguous_" + name.replace(".", r"\."))

    def test_stale_page_resource_cannot_pass_source_comparison(self):
        name = VERIFY.RESOURCE_NAMES[1]
        (self.bundle / name).write_text("// stale but well-formed UTF-8\n")
        self.assert_rejected("resource_differs_from_source_" + name.replace(".", r"\."), REPOSITORY)

    def test_notices_must_be_present_and_unchanged(self):
        notice = self.resources / "ThirdPartyNotices/Sukurini/NOTICE"
        notice.unlink()
        self.assert_rejected("missing_notice_Sukurini/NOTICE")
        notice.write_text("shortened copyright")
        self.assert_rejected("notices_differ_from_source", REPOSITORY)

    def test_symlinked_resource_and_bundle_root_rejected(self):
        target = self.bundle / VERIFY.RESOURCE_NAMES[0]
        target.unlink()
        target.symlink_to(REPOSITORY / "Sources/RiftletAdapters/Resources" / target.name)
        self.assert_rejected("unsafe_bundle_entry")
        target.unlink()
        linked = Path(self.temporary.name) / "Linked.app"
        linked.symlink_to(self.app, target_is_directory=True)
        with self.assertRaisesRegex(VERIFY.VerificationError, "^invalid_app_root$"):
            VERIFY.verify_bundle(linked)

    def test_unexpected_executable_and_bundle_root_entries_rejected(self):
        extra = self.binary.parent / "stale-helper"
        extra.write_text("left over")
        self.assert_rejected("unexpected_executable")
        extra.unlink()
        (self.app / "stale-resource").write_text("left over")
        self.assert_rejected("unexpected_bundle_root_entry")


if __name__ == "__main__":
    unittest.main()
