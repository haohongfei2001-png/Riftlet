"""Offline proxy-policy boundary checks. Every HTTPS connection is replaced;
no network, real feedback state, platform credential, or real proxy is accessed.
"""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import ssl
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("acceptance", Path(__file__).with_name("cloud_acceptance.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeHTTPSConnection:
    debuglevel = 0
    instances = []
    fail_write = False

    def __init__(self, host, timeout, context):
        self.host = host
        self.timeout = timeout
        self.context = context
        self.tunnel = None
        self.close_count = 0
        self.origin_response_called = False
        self.sent = None
        self.instances.append(self)

    def set_debuglevel(self, value):
        assert value == 0

    def set_tunnel(self, host, headers):
        self.tunnel = (host, headers)

    def request(self, method, selector, data, headers, encode_chunked):
        if self.fail_write:
            raise OSError("synthetic write failure")
        self.sent = (method, selector, data, headers, encode_chunked)

    def getresponse(self):
        self.origin_response_called = True
        raise AssertionError("Origin receipt must never be read")

    def close(self):
        self.close_count += 1


class DropResponsePolicyTests(unittest.TestCase):
    def run_case(self, environment, write_failure=False):
        FakeHTTPSConnection.instances = []
        FakeHTTPSConnection.fail_write = write_failure
        payload = {
            "schema": 1,
            "id": "11111111-1111-4111-8111-111111111111",
            "kind": "problem",
            "text": "SYNTHETIC OFFLINE PROXY TEST",
            "appVersion": "0.1.0",
            "createdAt": 1,
        }
        state = {
            "endpoint": "https://receiver.invalid/v1/feedback",
            "reports": {"lost_receipt": {"payload": payload, "secret": "f" * 64}},
        }
        stdout = io.StringIO()

        def observe_linger(seconds):
            self.assertEqual(seconds, 3.0)
            self.assertEqual(len(FakeHTTPSConnection.instances), 1)
            connected = FakeHTTPSConnection.instances[0]
            self.assertIsNotNone(connected.sent)
            self.assertEqual(connected.close_count, 0)
            self.assertFalse(connected.origin_response_called)

        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, environment, clear=True), patch.object(MODULE.http.client, "HTTPSConnection", FakeHTTPSConnection), patch.object(MODULE.time, "sleep", side_effect=observe_linger) as linger, contextlib.redirect_stdout(stdout):
                outcome = MODULE.drop_response(None, Path(directory), state)
            event = json.loads(stdout.getvalue())
            self.assertEqual(json.loads((Path(directory) / "events.jsonl").read_text()), event)
        self.assertEqual(len(FakeHTTPSConnection.instances), 1)
        connection = FakeHTTPSConnection.instances[0]
        self.assertEqual(connection.timeout, 15)
        self.assertEqual(connection.context.verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(connection.context.check_hostname)
        self.assertFalse(connection.origin_response_called)
        self.assertGreater(connection.close_count, 0)
        self.assertFalse(event["receiptRead"])
        self.assertEqual(event["transportOutcome"], "unknown")
        expected_body = MODULE.canonical(payload).encode()
        self.assertEqual(event["requestPayloadSHA256"], hashlib.sha256(expected_body).hexdigest())
        self.assertNotIn("f" * 64, stdout.getvalue())
        self.assertEqual(event["configuredPostWriteLingerMilliseconds"], 3000)
        if write_failure:
            linger.assert_not_called()
            self.assertFalse(event["postWriteLingerCompleted"])
            self.assertFalse(outcome)
            self.assertFalse(event["requestBytesWritten"])
            self.assertEqual(event["exceptionType"], "URLError")
        else:
            linger.assert_called_once_with(3.0)
            self.assertTrue(event["postWriteLingerCompleted"])
            self.assertTrue(outcome)
            self.assertTrue(event["requestBytesWritten"])
            method, selector, data, headers, chunked = connection.sent
            self.assertEqual((method, selector, data, chunked), ("POST", "/v1/feedback", expected_body, False))
            self.assertEqual(headers["Authorization"], "Bearer " + "f" * 64)
            self.assertEqual(headers["User-Agent"], "Riftlet-Cloud-Acceptance/0.1")
            self.assertNotIn("Proxy-Authorization", headers)
        return connection

    def test_environment_https_proxy_uses_connect_and_origin_tls(self):
        connection = self.run_case({"https_proxy": "http://synthetic-proxy.invalid:8080"})
        self.assertEqual(connection.host, "synthetic-proxy.invalid:8080")
        self.assertEqual(connection.tunnel, ("receiver.invalid", {}))

    def test_no_proxy_preserves_direct_policy(self):
        connection = self.run_case({"https_proxy": "http://synthetic-proxy.invalid:8080", "no_proxy": "receiver.invalid"})
        self.assertEqual(connection.host, "receiver.invalid")
        self.assertIsNone(connection.tunnel)

    def test_proxy_credentials_remain_only_in_connect_headers(self):
        connection = self.run_case({"https_proxy": "http://fixture-user:fixture-password@synthetic-proxy.invalid:8080"})
        self.assertEqual(connection.host, "synthetic-proxy.invalid:8080")
        self.assertEqual(connection.tunnel[0], "receiver.invalid")
        self.assertEqual(set(connection.tunnel[1]), {"Proxy-Authorization"})

    def test_failed_write_never_claims_request_written(self):
        self.run_case({"https_proxy": "http://synthetic-proxy.invalid:8080"}, write_failure=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
