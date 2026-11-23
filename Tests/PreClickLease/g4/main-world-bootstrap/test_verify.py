"""In-memory controls for the projection contract. These are not browser observations."""

import hashlib
import unittest

import verify


def digest(label):
    return hashlib.sha256(label.encode()).hexdigest()


def fixture():
    nonce, route, doc = map(digest, ("test-challenge", "test-route", "test-document"))
    run = {
        "challenge": nonce,
        "before": {"route": route, "document": doc, "markerAbsent": True},
        "set": {"route": route, "osStatus": 0, "challenge": nonce},
        "effect": {"document": doc, "challenge": nonce, "via": "native-set"},
        "isolated": {"document": doc, "sharedChallenge": nonce, "globalVisible": False,
                     "xhrVisible": False, "contextVerified": True},
        "main": {"document": doc, "globalChallenge": nonce, "xhrChallenge": nonce,
                 "unopened": True, "contextVerified": True},
        "cleanup": {"document": doc, "globalAbsent": True, "xhrAbsent": True,
                    "sharedMarkerAbsent": True, "mainContextVerified": True},
        "after": {"route": route, "document": doc},
        "network": {"coverage": "unmeasured", "requests": None, "uploads": None},
    }
    return {"schema": 1, "browser": "edge", "scope": "owned-local", "entry": "native-set",
            "run": run, "evidenceSHA256": {stage: digest("test-artifact-" + stage)
                                          for stage in verify.STAGE_NAMES}}


def page_network():
    return {"coverage": "page-resource-timing", "requests": None, "uploads": None,
            "resourceEntries": 0, "cspViolations": 0,
            "localPage": {"fileScheme": True, "fixedFixtureSHA256": digest("test-fixture"),
                          "fixtureHashMatched": True, "policyActiveFromPreparationThroughCleanup": True,
                          "connectionAndWorkerSourcesDenied": True, "remoteSubresourcesAndFormDenied": True,
                          "continuousCountersOnOriginalDocument": True, "counterOverflowOrLoss": False}}


class VerifierTests(unittest.TestCase):
    def setUp(self):
        self.data = fixture()

    def report(self):
        return verify.evaluate(self.data)

    def test_unmeasured_network_independent_of_world(self):
        result = self.report()
        self.assertTrue(result["worldVerified"])
        self.assertEqual(result["localExecutionWorld"], "PASS")
        self.assertEqual(result["overall"], "INCONCLUSIVE")
        self.assertIsNone(result["originalDocumentResourcesNoHTTP"])
        self.assertFalse(result["wholeNetworkObserved"])

    def test_fixed_local_page_pass_preserves_scope(self):
        self.data["run"]["network"] = page_network()
        for browser in ("edge", "chrome"):
            self.data["browser"] = browser
            result = self.report()
            self.assertEqual(result["overall"], "PASS")
            self.assertEqual(result["overallScope"], "owned-local-original-document")
            self.assertTrue(result["originalDocumentResourcesNoHTTP"])
            self.assertFalse(result["wholeNetworkObserved"])
            self.assertFalse(result["checks"]["measuredZeroWholeAttemptRequestsAndUploads"])

    def test_page_performance_counts_alone_are_insufficient(self):
        net = page_network()
        del net["localPage"]
        self.data["run"]["network"] = net
        result = self.report()
        self.assertTrue(result["worldVerified"])
        self.assertIsNone(result["originalDocumentResourcesNoHTTP"])
        self.assertEqual(result["overall"], "INCONCLUSIVE")

    def test_local_page_bounds_required_for_page_result(self):
        for key in verify.LOCAL_PAGE:
            with self.subTest(key=key):
                net = page_network()
                val = net["localPage"][key]
                net["localPage"][key] = not val if type(val) is bool else None
                self.data["run"]["network"] = net
                self.assertEqual(self.report()["overall"], "INCONCLUSIVE")
        self.data["run"]["network"] = page_network()
        self.data["scope"] = "enrolled-temporary"
        self.assertEqual(self.report()["overall"], "INCONCLUSIVE")

    def test_counters_or_csp_violations_do_not_pass(self):
        for key in ("resourceEntries", "cspViolations"):
            for count in (1, None):
                with self.subTest(key=key, count=count):
                    net = page_network()
                    net[key] = count
                    self.data["run"]["network"] = net
                    result = self.report()
                    self.assertEqual(result["overall"], "INCONCLUSIVE")
                    self.assertIsNone(result["originalDocumentResourcesNoHTTP"])

    def test_whole_attempt_requires_separate_counts_and_source(self):
        net = {"coverage": "whole-attempt", "requests": 0, "uploads": 0}
        self.data["run"]["network"] = net
        self.assertEqual(self.report()["overall"], "PASS")
        self.assertTrue(self.report()["wholeNetworkObserved"])
        self.assertIsNone(self.report()["originalDocumentResourcesNoHTTP"])
        net["requests"] = 1
        self.assertEqual(self.report()["overall"], "INCONCLUSIVE")
        net["requests"] = None
        self.assertFalse(self.report()["wholeNetworkObserved"])

    def test_no_attempt(self):
        self.data.update(entry="none", run=None)
        del self.data["evidenceSHA256"]
        result = self.report()
        self.assertEqual(result["overall"], "NOT_RUN")
        self.assertFalse(result["worldVerified"])

    def test_page_authored_link_cannot_establish_native_entry(self):
        self.data["run"]["network"] = page_network()
        self.data["run"]["effect"]["via"] = "page-link"
        self.assertEqual(self.report()["overall"], "INCONCLUSIVE")
        self.assertTrue(self.report()["checks"]["nativeSetReplySucceeded"])
        self.data["entry"] = "page-link"
        self.assertEqual(self.report()["overall"], "CONTROL_ONLY")
        self.assertFalse(self.report()["worldVerified"])

    def test_set_osstatus_zero_does_not_prove_page_execution(self):
        self.data["run"]["effect"] = None
        result = self.report()
        self.assertEqual(result["observedOSStatus"], 0)
        self.assertTrue(result["checks"]["nativeSetReplySucceeded"])
        self.assertFalse(result["checks"]["nativeSetEffectInOriginalDocument"])
        self.assertFalse(result["worldVerified"])

    def test_stale_route_document_challenge_and_context(self):
        for stage, fields in verify.STAGES.items():
            if stage == "cleanup":
                continue
            for key, kind in fields.items():
                with self.subTest(stage=stage, key=key):
                    self.data = fixture()
                    row = self.data["run"][stage]
                    if kind == "hash":
                        row[key] = digest("mismatched")
                    elif kind == "bool":
                        row[key] = not row[key]
                    elif kind == "os-status":
                        row[key] = -1712
                    else:
                        row[key] = "unattributed"
                    self.assertFalse(self.report()["worldVerified"])

    def test_unknown_cannot_match_unknown(self):
        for label in ("document", "challenge", "route"):
            with self.subTest(label=label):
                self.data = fixture()
                for stage, specification in verify.STAGES.items():
                    for name in specification:
                        if label in name.lower():
                            self.data["run"][stage][name] = None
                if label == "challenge":
                    self.data["run"]["challenge"] = None
                self.assertFalse(self.report()["worldVerified"])

    def test_cleanup_requires_all_original_markers_and_context(self):
        for key in verify.STAGES["cleanup"]:
            with self.subTest(key=key):
                self.data = fixture()
                self.data["run"]["network"] = page_network()
                self.data["run"]["cleanup"][key] = None
                result = self.report()
                self.assertTrue(result["worldVerified"])
                self.assertFalse(result["checks"]["cleanedInOriginalMain"])
                self.assertEqual(result["overall"], "INCONCLUSIVE")

    def test_each_positive_stage_requires_source_digest(self):
        for stage in verify.STAGE_NAMES:
            with self.subTest(stage=stage):
                self.data = fixture()
                self.data["run"]["network"] = page_network()
                del self.data["evidenceSHA256"][stage]
                self.assertEqual(self.report()["overall"], "INCONCLUSIVE")
                self.assertEqual(self.report()["missingStageReferences"], [stage])

    def test_invalid_counters_and_osstatus_bool(self):
        for coverage, requests, uploads in (
                ("unmeasured", 0, None), ("whole-attempt", True, 0),
                ("whole-attempt", -1, 0), ("whole-attempt", 1, 2)):
            with self.subTest(coverage=coverage, requests=requests):
                self.data["run"]["network"] = dict(coverage=coverage, requests=requests, uploads=uploads)
                with self.assertRaises(verify.InvalidReceipt):
                    self.report()
        self.data = fixture()
        self.data["run"]["set"]["osStatus"] = False
        with self.assertRaises(verify.InvalidReceipt):
            self.report()

    def test_strict_redacted_schema(self):
        for mutation in (
            lambda d: d["run"].pop("cleanup"),
            lambda d: d.update(extra="private content"),
            lambda d: d["run"]["main"].update(extra="private content"),
            lambda d: d["run"]["before"].update(route="https://invalid.example"),
            lambda d: d["evidenceSHA256"].update(set="file-path"),
        ):
            with self.subTest(mutation=mutation):
                mutation(self.data)
                with self.assertRaises(verify.InvalidReceipt):
                    self.report()
                self.data = fixture()

    def test_parser_rejects_duplicates_nonfinite_and_oversize(self):
        for raw in (b'{"schema":0,"schema":1}', b'{"count":NaN}', b"x" * (verify.LIMIT + 1), b"1" * 5000):
            with self.subTest(raw_bytes=len(raw)), self.assertRaises(verify.InvalidReceipt):
                verify.read(raw)


if __name__ == "__main__":
    unittest.main()
