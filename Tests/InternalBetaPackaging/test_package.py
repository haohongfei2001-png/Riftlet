"""Package/launcher regressions; synthetic Mach-O header, no GUI or real open."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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
                         "feedbackEndpointConfigured": False, "feedbackEndpoint": None,
                         "feedbackDelivery": "local-outbox-only",
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

    def test_configured_receiver_is_a_capability_not_cloud_success(self):
        endpoint = "https://feedback-test.example.invalid/v1/feedback"
        self.manifest.update(feedbackEndpointConfigured=True, feedbackEndpoint=endpoint,
                             feedbackDelivery="https-receiver-configured")
        self.save_manifest()
        result = VERIFY.verify_package(self.package)
        self.assertEqual(result["feedbackEndpoint"], endpoint)
        self.assertFalse(self.calls.exists())
        for claim in ("cloud-pass", "received", "delivered", "local-outbox-only"):
            with self.subTest(claim=claim):
                self.manifest["feedbackDelivery"] = claim
                self.save_manifest()
                with self.assertRaisesRegex(ValueError, "invalid_feedback_boundary"):
                    VERIFY.verify_package(self.package)

    def test_receiver_manifest_rejects_missing_and_unsafe_addresses(self):
        for endpoint in ("", "PENDING_DEPLOYMENT", "http://feedback-test.example.invalid/v1/feedback",
                         "https://secret@feedback-test.example.invalid/v1/feedback",
                         "https://feedback-test.example.invalid:8443/v1/feedback",
                         "https://feedback-test.example.invalid/v1/feedback?token=private",
                         "https://feedback-test.example.invalid/v1/feedback#private",
                         "https://feedback-test.example.invalid/v1/feedback?",
                         "https://feedback-test.example.invalid/v1/feedback/",
                         "https://feedback-test..example.invalid/v1/feedback",
                         "https://feedback-test.example.invalid/v1/feedback\n"):
            with self.subTest(endpoint=endpoint):
                self.manifest.update(feedbackEndpointConfigured=True, feedbackEndpoint=endpoint,
                                     feedbackDelivery="https-receiver-configured")
                self.save_manifest()
                with self.assertRaisesRegex(ValueError, "invalid_feedback_boundary"):
                    VERIFY.verify_package(self.package)
        self.manifest.update(feedbackEndpointConfigured=True, feedbackEndpoint=None,
                             feedbackDelivery="https-receiver-configured")
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "invalid_feedback_boundary"):
            VERIFY.verify_package(self.package)

    def test_disabled_manifest_cannot_hide_configured_receiver_or_coerce_boolean(self):
        self.manifest["feedbackEndpoint"] = "https://feedback-test.example.invalid/v1/feedback"
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "invalid_feedback_boundary"):
            VERIFY.verify_package(self.package)
        self.manifest["feedbackEndpoint"] = None
        self.manifest["feedbackEndpointConfigured"] = 0
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "invalid_feedback_boundary"):
            VERIFY.verify_package(self.package)

    def test_host_source_requires_one_explicit_reviewable_literal(self):
        disabled = "    static let endpoint: URL? = nil\n"
        self.assertFalse(VERIFY.feedback_source_configuration(disabled)["feedbackEndpointConfigured"])
        endpoint = "https://feedback-test.example.invalid:443/v1/feedback"
        configured = '    static let endpoint: URL? = URL(string: "' + endpoint + '")\n'
        self.assertEqual(VERIFY.feedback_source_configuration(configured)["feedbackEndpoint"], endpoint)
        for source in ("", disabled + disabled,
                       "    static let endpoint: URL? = ProcessInfo.processInfo.environment[\"ENDPOINT\"].flatMap(URL.init)\n",
                       '    static let endpoint: URL? = URL(string: "https://\\(host)/v1/feedback")\n',
                       '    static let endpoint: URL? = URL(string: "PENDING_DEPLOYMENT")\n'):
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, "invalid_feedback_(source|boundary)"):
                VERIFY.feedback_source_configuration(source)

    def test_manifest_configuration_must_match_its_committed_host(self):
        endpoint = "https://feedback-test.example.invalid/v1/feedback"
        self.manifest.update(feedbackEndpointConfigured=True, feedbackEndpoint=endpoint,
                             feedbackDelivery="https-receiver-configured")
        self.save_manifest()
        requested_source = ("show", self.manifest["sourceHeadSHA"] + ":" + VERIFY.FEEDBACK_HOST)
        for committed, accepted in (("    static let endpoint: URL? = nil\n", False),
                ('    static let endpoint: URL? = URL(string: "' + endpoint + '")\n', True)):
            def read_git(repository, *args):
                if args == requested_source:
                    return committed
                self.assertEqual(args[0], "rev-parse")
                return "e" * 40
            with self.subTest(accepted=accepted), patch.object(VERIFY, "git", side_effect=read_git) as read:
                if accepted:
                    VERIFY.verify_package(self.package, REPOSITORY)
                else:
                    with self.assertRaisesRegex(ValueError, "manifest_feedback_source_mismatch"):
                        VERIFY.verify_package(self.package, REPOSITORY)
                read.assert_any_call(REPOSITORY, *requested_source)

    def test_manifest_creation_derives_capability_from_committed_host(self):
        repository = self.root / "source-checkpoint"
        repository.mkdir()
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        for path in VERIFY.INPUTS:
            target = repository / path
            if path == "Package.swift":
                target.write_text("// synthetic build identity\n")
            else:
                target.mkdir(parents=True)
                (target / "fixture").write_text("synthetic build identity\n")
        host = repository / VERIFY.FEEDBACK_HOST
        host.parent.mkdir(parents=True)
        host.write_text("    static let endpoint: URL? = nil\n")

        def commit():
            subprocess.run(["git", "-C", str(repository), "add", "."], check=True)
            subprocess.run(["git", "-C", str(repository), "-c", "user.name=Package Test",
                            "-c", "user.email=package-test@example.invalid", "commit", "-qm", "Synthetic identity"], check=True)

        commit()
        local = VERIFY.create_manifest(self.package, repository, "HEAD")
        self.assertIs(local["feedbackEndpointConfigured"], False)
        self.assertIsNone(local["feedbackEndpoint"])
        endpoint = "https://feedback-test.example.invalid/v1/feedback"
        host.write_text('    static let endpoint: URL? = URL(string: "' + endpoint + '")\n')
        commit()
        configured = VERIFY.create_manifest(self.package, repository, "HEAD")
        self.assertIs(configured["feedbackEndpointConfigured"], True)
        self.assertEqual(configured["feedbackEndpoint"], endpoint)
        self.assertEqual(configured["feedbackDelivery"], "https-receiver-configured")
        self.assertNotEqual(local["sourceHeadSHA"], configured["sourceHeadSHA"])


if __name__ == "__main__":
    unittest.main()
