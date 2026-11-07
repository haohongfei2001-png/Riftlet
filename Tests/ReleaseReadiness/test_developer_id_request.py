"""Real PKCS#10 signatures using only in-memory test keys. Never generate a login key."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CSR = "Riftlet-Developer-ID-Application.certSigningRequest"
OPENSSL = "/usr/bin/openssl"


def run(*args, data=None):
    return subprocess.run(args, input=data, capture_output=True, timeout=60)


@unittest.skipUnless(sys.platform == "darwin", "requires macOS Security.framework")
class DeveloperIDRequestTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tools = tempfile.TemporaryDirectory(prefix="riftlet-csr-tools-")
        cls.addClassCleanup(tools.cleanup)
        cls.tool = Path(tools.name) / "developer-id-request"
        result = run("/usr/bin/xcrun", "swiftc", ROOT / "scripts/developer-id-request.swift", "-o", cls.tool)
        if result.returncode:
            raise RuntimeError(result.stderr.decode())

    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix="riftlet-ephemeral-csr-")
        self.addCleanup(folder.cleanup)
        self.data = Path(folder.name)

    def tool_result(self, action, *args, expected=0):
        result = run(self.tool, action, "--directory", self.data, *args)
        self.assertEqual(result.returncode, expected, result.stdout.decode())
        return json.loads(result.stdout)

    def assert_csr(self, result, bits):
        csr = self.data / CSR
        self.assertEqual(result["keyStorage"], "ephemeralTestOnly")
        self.assertFalse(result["keyReportedExtractable"])
        self.assertFalse(result["privateKeyExported"])
        self.assertFalse((self.data / "request-state.json").exists())
        verified = run(OPENSSL, "req", "-in", csr, "-noout", "-verify")
        self.assertEqual(verified.returncode, 0)
        self.assertRegex((verified.stderr + verified.stdout).decode().lower(), r"(verify ok|verify success|verification ok)")
        parsed = run(OPENSSL, "req", "-in", csr, "-noout", "-text")
        self.assertEqual(parsed.returncode, 0)
        self.assertIn(f"({bits} bit", parsed.stdout.decode())
        self.assertIn("sha256WithRSAEncryption", parsed.stdout.decode())
        public = run(OPENSSL, "req", "-in", csr, "-pubkey", "-noout")
        self.assertEqual(public.returncode, 0)
        spki = run(OPENSSL, "pkey", "-pubin", "-outform", "DER", data=public.stdout)
        self.assertEqual(spki.returncode, 0)
        self.assertEqual(spki.stdout, (self.data / "public-key.spki.der").read_bytes())
        self.assertEqual(hashlib.sha256(spki.stdout).hexdigest(), result["publicKeySPKISHA256"])
        self.assertEqual(hashlib.sha256(csr.read_bytes()).hexdigest(), result["csrSHA256"])

    def test_rsa2048_subject_and_signature(self):
        result = self.tool_result("test-request")
        self.assert_csr(result, 2048)
        self.assertFalse(result["emailIncluded"])
        name = run(OPENSSL, "req", "-in", self.data / CSR, "-noout", "-subject").stdout.decode()
        self.assertIn("Riftlet Developer ID Application", name)
        self.assertNotIn("emailAddress", name)

    def test_rsa3072_with_explicit_utf8_name_and_email(self):
        result = self.tool_result("test-request", "--bits", "3072", "--common-name", "界面 Fixture",
                                  "--email", "fixture@example.invalid")
        self.assert_csr(result, 3072)
        self.assertTrue(result["emailIncluded"])
        printed = run(OPENSSL, "req", "-in", self.data / CSR, "-noout", "-subject",
                      "-nameopt", "RFC2253,utf8,-esc_msb")
        self.assertEqual(printed.returncode, 0)
        name = printed.stdout.decode()
        self.assertIn("界面 Fixture", name)
        self.assertIn("fixture@example.invalid", name)

    def test_invalid_parameters_do_not_write_outputs(self):
        for args in (("--bits", "1024"), ("--email", "user@"), ("--common-name", "two\nlines")):
            with self.subTest(args=args):
                result = self.tool_result("test-request", *args, expected=1)
                self.assertEqual(result["reason"], "invalidSubjectOrKeySize")
                self.assertEqual(list(self.data.iterdir()), [])

    def test_existing_csr_is_never_replaced(self):
        original = b"preserve another request"
        (self.data / CSR).write_bytes(original)
        result = self.tool_result("test-request", expected=1)
        self.assertEqual(result["reason"], "existingOutputDiffers")
        self.assertEqual((self.data / CSR).read_bytes(), original)

    def test_symlink_output_is_refused(self):
        target = self.data / "untouched"
        target.write_bytes(b"keep")
        (self.data / "public-key.spki.der").symlink_to(target)
        result = self.tool_result("test-request", expected=1)
        self.assertEqual(result["reason"], "outputIsNotARegularFile")
        self.assertEqual(target.read_bytes(), b"keep")

    def test_concurrent_requests_publish_one_consistent_csr(self):
        args = [self.tool, "test-request", "--directory", self.data]
        first = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        second = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        outputs = [json.loads(process.communicate(timeout=60)[0]) for process in (first, second)]
        self.assertEqual(sorted([first.returncode, second.returncode]), [0, 1])
        successful = next(result for result in outputs if result["result"] == "CSR_READY")
        self.assert_csr(successful, 2048)

    def test_invalid_certificate_cannot_enter_the_install_step(self):
        bad = self.data / "invalid.cer"
        bad.write_bytes(b"not an X.509 certificate")
        for action in ("verify-certificate", "install-certificate"):
            with self.subTest(action=action):
                result = self.tool_result(action, "--certificate", bad, "--team", "ABCDE12345", expected=1)
                self.assertEqual(result["reason"], "invalidDERCertificate")
        self.assertFalse((self.data / "request-state.json").exists())

    def test_public_apple_root_with_matching_spki_still_is_not_a_developer_id_leaf(self):
        # Read a public Apple trust anchor from the OS system roots; no user keychain access.
        found = run("/usr/bin/security", "find-certificate", "-a", "-p", "-c", "Apple Root CA",
                    "/System/Library/Keychains/SystemRootCertificates.keychain")
        self.assertEqual(found.returncode, 0)
        for pem in re.findall(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", found.stdout, re.S):
            leaf = run(OPENSSL, "x509", "-outform", "DER", data=pem)
            if hashlib.sha256(leaf.stdout).hexdigest() == "b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024":
                break
        else:
            self.fail("missing public Apple Inc. Root")
        der = self.data / "public-root.cer"
        der.write_bytes(leaf.stdout)
        public = run(OPENSSL, "x509", "-pubkey", "-noout", data=pem)
        spki = run(OPENSSL, "pkey", "-pubin", "-outform", "DER", data=public.stdout)
        self.assertEqual(spki.returncode, 0)
        (self.data / "public-key.spki.der").write_bytes(spki.stdout)
        result = self.tool_result("verify-certificate", "--certificate", der, "--team", "ABCDE12345", expected=1)
        self.assertEqual(result["reason"], "notDeveloperIDApplication")
        (self.data / "public-key.spki.der").write_bytes(b"another request")
        result = self.tool_result("verify-certificate", "--certificate", der, "--team", "ABCDE12345", expected=1)
        self.assertEqual(result["reason"], "certificatePublicKeyMismatch")


if __name__ == "__main__":
    unittest.main()
