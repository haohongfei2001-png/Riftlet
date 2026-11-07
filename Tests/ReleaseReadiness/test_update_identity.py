"""Exercise the offline preflight against real signatures on unlaunched fixture apps."""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from uuid import uuid4


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "requires macOS Security.framework and codesign")
class UpdateIdentityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="riftlet-identity-tools-")
        cls.addClassCleanup(temporary.cleanup)
        cls.tool = Path(temporary.name) / "check-update-identity"
        cls.executable = Path(temporary.name) / "Fixture"
        subprocess.run(
            ["/usr/bin/xcrun", "swiftc", ROOT / "scripts/check-update-identity.swift", "-o", cls.tool],
            check=True, capture_output=True, timeout=60,
        )
        subprocess.run(
            ["/usr/bin/xcrun", "clang", "-x", "c", "-", "-o", cls.executable],
            input=b"int main(void) { return 0; }\n", check=True, capture_output=True, timeout=60,
        )

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="riftlet-identity-apps-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.identifier = "org.example.riftlet-identity." + uuid4().hex
        self.fixture_scope = uuid4().hex

    def app(self, folder, resource=b"original", identifier=None, requirement=None, executable=None):
        app = self.directory / folder / "Fixture.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        shutil.copy2(executable or self.executable, contents / "MacOS/Fixture")
        (contents / "Resources/value").write_bytes(resource)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "Fixture",
            "CFBundleIdentifier": identifier or self.identifier,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "PreflightFixture": self.fixture_scope,
        }))
        sign = ["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none"]
        if requirement:
            sign.extend(["--requirements", "=" + requirement])
        subprocess.run([*sign, app], check=True, capture_output=True, timeout=20)
        return app

    def run_tool(self, *arguments):
        completed = subprocess.run([self.tool, *arguments], capture_output=True, timeout=20)
        result = json.loads(completed.stdout)
        self.assertEqual(completed.returncode, result["exitCode"])
        self.assertFalse(result["permissionStateRead"])
        self.assertFalse(result["permissionStateChanged"])
        self.assertEqual(result["directoryAccess"], "notEvaluated")
        return result

    def compare(self, installed, candidate):
        return self.run_tool("--installed", installed, "--candidate", candidate)

    def test_identical_copy_matches_at_another_path(self):
        installed = self.app("original")
        candidate = self.directory / "another folder" / "Moved App.app"
        shutil.copytree(installed, candidate)
        result = self.run_tool("--candidate", candidate, "--installed", installed)
        self.assertEqual((result["exitCode"], result["result"], result["requirementCheckOSStatus"]),
                         (0, "match", 0))
        self.assertEqual(result["installed"], result["candidate"])
        self.assertEqual(result["installed"]["bundleIdentifier"], self.identifier)
        self.assertTrue(result["installed"]["signatureValid"])
        self.assertTrue(result["installed"]["adHocSignature"])

    def test_changed_resigned_resource_breaks_default_ad_hoc_requirement(self):
        result = self.compare(self.app("old"), self.app("new", b"new resource"))
        self.assertTrue(result["installed"]["signatureValid"])
        self.assertTrue(result["candidate"]["signatureValid"])
        self.assertEqual(result["installed"]["bundleIdentifier"], result["candidate"]["bundleIdentifier"])
        self.assertNotEqual(result["installed"]["cdHash"], result["candidate"]["cdHash"])
        self.assertEqual((result["exitCode"], result["result"], result["reason"]),
                         (2, "mismatch", "installedRequirementNotSatisfied"))
        self.assertEqual(result["requirementCheckOSStatus"], -67050)

    def test_identical_universal_app_matches_using_its_complete_requirement(self):
        source = self.directory / "fixture.c"
        source.write_text("int main(void) { return 0; }\n")
        fat = self.directory / "universal"
        subprocess.run(
            ["/usr/bin/xcrun", "clang", "-arch", "arm64", "-arch", "x86_64",
             "-mmacosx-version-min=13.0", source, "-o", fat],
            check=True, capture_output=True, timeout=60,
        )
        installed = self.app("universal original", executable=fat)
        candidate = self.directory / "universal copy.app"
        shutil.copytree(installed, candidate)
        result = self.compare(installed, candidate)
        self.assertEqual((result["exitCode"], result["result"], result["requirementCheckOSStatus"]),
                         (0, "match", 0))

    def test_different_hash_can_match_the_installed_requirement_only_in_one_direction(self):
        # This private fixture accepts only its fresh synthetic ID and sealed Info.plist value.
        requirement = (f'designated => identifier "{self.identifier}" '
                       f'and info[PreflightFixture] = "{self.fixture_scope}"')
        installed = self.app("old", requirement=requirement)
        candidate = self.app("new", b"updated")
        forward = self.compare(installed, candidate)
        self.assertNotEqual(forward["installed"]["cdHash"], forward["candidate"]["cdHash"])
        self.assertNotEqual(forward["installed"]["designatedRequirement"],
                            forward["candidate"]["designatedRequirement"])
        self.assertEqual((forward["exitCode"], forward["result"], forward["requirementCheckOSStatus"]),
                         (0, "match", 0))
        reverse = self.compare(candidate, installed)
        self.assertEqual((reverse["exitCode"], reverse["result"], reverse["requirementCheckOSStatus"]),
                         (2, "mismatch", -67050))

    def test_valid_app_with_another_bundle_id_is_a_distinct_mismatch(self):
        result = self.compare(self.app("old"), self.app("new", identifier=self.identifier + ".other"))
        self.assertTrue(result["installed"]["signatureValid"])
        self.assertTrue(result["candidate"]["signatureValid"])
        self.assertEqual((result["exitCode"], result["result"], result["reason"]),
                         (2, "mismatch", "bundleIdentifierChanged"))
        self.assertNotIn("requirementCheckOSStatus", result)

    def test_invalid_signature_on_either_side_precedes_identity_comparison(self):
        valid = self.app("valid")
        altered = self.app("altered")
        (altered / "Contents/Resources/value").write_bytes(b"tampered after signing")
        for side, old, new in (("candidate", valid, altered), ("installed", altered, valid)):
            with self.subTest(side=side):
                result = self.compare(old, new)
                self.assertEqual((result["exitCode"], result["result"]), (1, "invalid"))
                self.assertEqual(result[side]["failure"], "signatureValidation")
                self.assertFalse(result[side]["signatureValid"])
                self.assertNotIn("requirementCheckOSStatus", result)

    def test_missing_bundle_or_plain_executable_cannot_match(self):
        valid = self.app("valid")
        raw = self.directory / "raw.app"
        shutil.copy2(self.executable, raw)
        for path in (raw, self.directory / "absent.app"):
            with self.subTest(path=path):
                result = self.compare(valid, path)
                self.assertEqual((result["exitCode"], result["result"]), (1, "invalid"))
                self.assertEqual(result["candidate"]["failure"], "notAnApplicationBundle")

    def test_unsigned_candidate_is_invalid(self):
        valid = self.app("valid")
        unsigned = self.app("unsigned")
        subprocess.run(["/usr/bin/codesign", "--remove-signature", unsigned],
                       check=True, capture_output=True, timeout=20)
        result = self.compare(valid, unsigned)
        self.assertEqual((result["exitCode"], result["result"]), (1, "invalid"))
        self.assertEqual(result["candidate"]["failure"], "signatureValidation")
        self.assertFalse(result["candidate"]["signatureValid"])

    def test_signed_resource_only_bundle_is_not_an_application(self):
        app = self.directory / "resource-only.app"
        (app / "Contents/Resources").mkdir(parents=True)
        (app / "Contents/Resources/value").write_bytes(b"sealed resource")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": self.identifier, "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        }))
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", app],
                       check=True, capture_output=True, timeout=20)
        result = self.compare(self.app("valid"), app)
        self.assertEqual((result["exitCode"], result["result"]), (1, "invalid"))
        self.assertTrue(result["candidate"]["signatureValid"])
        self.assertEqual(result["candidate"]["failure"], "missingApplicationExecutable")

    def test_missing_or_duplicated_arguments_return_usage(self):
        for arguments in (("--installed", "old.app"), ("--candidate", "a.app", "--candidate", "b.app")):
            with self.subTest(arguments=arguments):
                result = self.run_tool(*arguments)
                self.assertEqual((result["exitCode"], result["result"]), (64, "usage"))


if __name__ == "__main__":
    unittest.main()
