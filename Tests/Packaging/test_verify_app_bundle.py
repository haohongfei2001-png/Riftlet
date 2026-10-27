"""Synthetic layout tests; no executable is run or signed by this suite."""

import importlib.util
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
