import importlib.util
from pathlib import Path
import unittest
import json
import tempfile
import sqlite3
from unittest.mock import patch

helper_path = Path(__file__).resolve().parents[1] / "LiveCompatibility/edge_host.py"
spec = importlib.util.spec_from_file_location("isolated_edge_host", helper_path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class IndependentPickerTests(unittest.TestCase):
    def test_distinct_system_capture_geometry(self):
        first = ("first", (1000, 800))
        for size in [(160, 96), (320, 192)]:
            helper.verify_capture_geometry("second", size, "23,41,160,96", first)
        # Metadata-only differences and duplicate PNGs cannot prove two frames.
        with self.assertRaisesRegex(RuntimeError, "two_distinct_captures_unproven"):
            helper.verify_capture_geometry("different-metadata", first[1], None, first)
        with self.assertRaisesRegex(RuntimeError, "two_distinct_captures_unproven"):
            helper.verify_capture_geometry(first[0], (160, 96), "23,41,160,96", first)
        for wrong_size in [(160, 100), (80, 48)]:
            with self.assertRaisesRegex(RuntimeError, "region_pixel_shape_mismatch"):
                helper.verify_capture_geometry("second", wrong_size, "23,41,160,96", first)
        helper.verify_capture_geometry("second", (320, 192), "23,41,160,96", ("first", (256, 144)))

    def mouse_pair(self, asset, window, tag, event_number, sequence):
        return [dict(event="selection_boundary", source="mouse", targetRequested=True, assetIDDigest=asset,
                     windowNumber=window, clickCount=1, eventNumber=event_number, mouseProbeTag=tag,
                     diagnosticSessionDigest="owned-session", diagnosticSequence=sequence),
                dict(event="click_input_refused", assetIDDigest=asset, diagnosticSessionDigest="owned-session",
                     diagnosticSequence=sequence + 1, phase="resolveSelection", error="browserNotFrontmost", critical=True)]

    def test_default_duplicate_event_number_does_not_mean_product_receipt_was_missing(self):
        sent = [("first-owned", 20, 100001, 101), ("second-owned", 21, 100002, 102)]
        evidence = self.mouse_pair(*sent[0][:3], 0, 1) + self.mouse_pair(*sent[1][:3], 0, 3)
        summary = helper.summarize_mouse_receipts(evidence, sent)
        self.assertEqual((summary["selectionCount"], summary["refusalCount"]), (2, 2))
        self.assertTrue(all(r["combinedIdentityMatched"] and r["criticalRefusal"] and r["refusalAfterSelection"]
                            for r in summary["dispatches"]))
        self.assertFalse(summary["nativeEventNumbersDistinct"])
        self.assertFalse(summary["originalReceiptMatcherPassed"])
        self.assertTrue(all(not r["sentEventNumberMatched"] for r in summary["dispatches"]))
        self.assertFalse(helper.original_mouse_refusals(evidence, sent))

    def test_sender_uses_lossless_signed_16_bit_range_and_distinct_numbers(self):
        with patch.object(helper.secrets, "randbelow", side_effect=[0, 0, 32766]) as random:
            first = helper.next_mouse_event_number([])
            second = helper.next_mouse_event_number([("first-owned", 20, 100001, first)])
        self.assertEqual((first, second), (1, 32767))
        self.assertEqual([call.args for call in random.call_args_list], [(32767,), (32767,), (32767,)])
        for number in (1, 32767):
            sent = [("owned", 20, 100001, number)]
            self.assertTrue(helper.original_mouse_refusals(self.mouse_pair(*sent[0], 1), sent))
        for number in (-32768, -1, 0, 32768, 65535, 65536, 0x12345678, 2147483647):
            sent = [("owned", 20, 100001, number)]
            self.assertFalse(helper.original_mouse_refusals(self.mouse_pair(*sent[0], 1), sent))

    def test_receipt_exports_actual_test_number_without_accepting_its_narrowed_value(self):
        sent = [("owned", 20, 100001, 32767)]
        evidence = self.mouse_pair("owned", 20, 100001, -1, 1)
        summary = helper.summarize_mouse_receipts(evidence, sent)
        self.assertEqual(summary["dispatches"][0]["sentEventNumber"], 32767)
        self.assertEqual(summary["dispatches"][0]["receivedEventNumbers"], [-1])
        self.assertFalse(summary["dispatches"][0]["sentEventNumberMatched"])
        self.assertFalse(summary["originalReceiptMatcherPassed"])

    def test_explicit_pair_numbers_match_original_receipts_and_do_not_relax_other_identity(self):
        sent = [("first-owned", 20, 100001, 101), ("second-owned", 21, 100002, 102)]
        evidence = self.mouse_pair(*sent[0], 1) + self.mouse_pair(*sent[1], 3)
        self.assertTrue(helper.original_mouse_refusals(evidence, sent))
        summary = helper.summarize_mouse_receipts(evidence, sent)
        self.assertTrue(summary["nativeEventNumbersDistinct"] and summary["originalReceiptMatcherPassed"])
        self.assertTrue(all(r["sentEventNumberMatched"] for r in summary["dispatches"]))
        for key, value in (("eventNumber", 103), ("mouseProbeTag", 100003), ("windowNumber", 22),
                           ("assetIDDigest", "different-owned"), ("diagnosticSequence", 1)):
            changed = [dict(r) for r in evidence]
            changed[2][key] = value
            self.assertFalse(helper.original_mouse_refusals(changed, sent), key)
        repeated_sent = [sent[0], (sent[1][0], sent[1][1], sent[0][2], sent[1][3])]
        repeated_evidence = self.mouse_pair(*repeated_sent[0], 1) + self.mouse_pair(*repeated_sent[1], 3)
        self.assertFalse(helper.original_mouse_refusals(repeated_evidence, repeated_sent))
        report = dict(pressAttempts=2, confirmedDistinctRefusals=1, mouseDispatchCalls=2,
                      result="FAILED_CONTROLLED_CHECK", rounds=[dict(action="ONE_GLOBAL_MOUSE_DOWN_UP_POSTED")] * 2)
        self.assertFalse(helper.picker_after_mouse_safe(report, sent, evidence))

    def test_only_closed_original_resolve_selection_permission_refusals_are_accepted(self):
        sent = [("first-owned", 20, 100001, 101)]
        for error in ("nativeEventFailed(-1744)", "nativeEventFailed(-1743)", "nativeEventFailed(12)"):
            evidence = self.mouse_pair(*sent[0], 1)
            evidence[1]["error"] = error
            self.assertTrue(helper.original_mouse_refusals(evidence, sent))
            self.assertTrue(helper.original_permission_refusal(evidence, sent))
            summary = helper.summarize_mouse_receipts(evidence, sent)
            self.assertEqual(summary["dispatches"][0]["refusalStatuses"], [error])
            for key, wrong in (("phase", "submitSelection"), ("assetIDDigest", "other-owned"), ("critical", False)):
                changed = [dict(r) for r in evidence]
                changed[1][key] = wrong
                self.assertFalse(helper.original_permission_refusal(changed, sent))
        for error in ("nativeEventFailed(-1712)", "nativeEventFailed(-600)", "nativeEventFailed(0)", "private-message"):
            evidence = self.mouse_pair(*sent[0], 1)
            evidence[1]["error"] = error
            self.assertFalse(helper.original_mouse_refusals(evidence, sent))
            self.assertFalse(helper.original_permission_refusal(evidence, sent))

    def test_pending_consent_cannot_complete_second_round_or_enable_candidate(self):
        sent = [("first-owned", 20, 100001, 101)]
        evidence = self.mouse_pair(*sent[0], 1)
        evidence[1]["error"] = "nativeEventFailed(-1744)"
        self.assertIsNone(helper.explicit_consent_result(evidence, sent))
        reply = dict(event="edge_automation_permission", purpose="explicitClickConsent", result="denied",
                     diagnosticSessionDigest="owned-session", diagnosticSequence=3)
        for changes in ({"diagnosticSessionDigest": "other-session"}, {"diagnosticSequence": 1}, {"purpose": "background"}):
            self.assertIsNone(helper.explicit_consent_result(evidence + [dict(reply, **changes)], sent))
        self.assertEqual(helper.explicit_consent_result(evidence + [reply], sent), "denied")
        self.assertFalse(helper.original_mouse_refusals(evidence + [reply], sent + [("second-owned", 21, 100002, 102)]))
        report = dict(pressAttempts=1, confirmedDistinctRefusals=1, mouseDispatchCalls=1,
                      result="NOT_RUN_SYSTEM_AUTOMATION_CONSENT",
                      rounds=[dict(action="ONE_GLOBAL_MOUSE_DOWN_UP_POSTED", retained="BOTH_ORIGINAL_ASSETS_VISIBLE_PENDING"),
                              dict(action="NOT_RUN", rejection="NOT_RUN_SYSTEM_AUTOMATION_CONSENT")])
        self.assertFalse(helper.picker_after_mouse_safe(report, sent, evidence + [reply]))
        # Two separately matched permission refusals remain two host refusals,
        # never successful attachment or permission evidence.
        second = ("second-owned", 21, 100002, 102)
        second_evidence = self.mouse_pair(*second, 4)
        second_evidence[1]["error"] = "nativeEventFailed(-1743)"
        self.assertTrue(helper.original_mouse_refusals(evidence + [reply] + second_evidence, sent + [second]))

    def test_actual_receiver_coordinates_are_bounded_typed_metadata(self):
        expected = dict(ordinal=2, window=51, x=100.5, y=201.25)
        self.assertEqual(helper.mouse_receiver(json.dumps(expected)), expected)
        for changes in ({"window": True}, {"ordinal": 3}, {"x": float("nan")}, {"y": "private-path"}, {"extra": 1}):
            with self.assertRaises(RuntimeError):
                helper.mouse_receiver(json.dumps(dict(expected, **changes)))

    def test_safe_first_preflight_and_pre_down_veto(self):
        base = {"pressAttempts": 0, "confirmedDistinctRefusals": 0, "mouseDispatchCalls": 0,
                "result": "PARTIAL_NATIVE_THUMBNAIL_MOUSE_TARGET_UNVERIFIED", "rounds": [{"action": "NOT_RUN"}]}
        self.assertTrue(helper.picker_after_mouse_safe(base, [], []))
        before_down = dict(base, mouseDispatchCalls=1, result="PARTIAL_NATIVE_MOUSE_TARGET_CHANGED_BEFORE_DOWN",
                           rounds=[{"action": "VETO_BEFORE_MOUSE_DOWN"}])
        self.assertTrue(helper.picker_after_mouse_safe(before_down, [], []))
        self.assertFalse(helper.picker_after_mouse_safe(before_down, [], [{"event": "selection_boundary"}]))
        self.assertFalse(helper.picker_after_mouse_safe(base, [], [{"event": "click_target_resolved"}]))
        self.assertFalse(helper.picker_after_mouse_safe(dict(base, mouseDispatchCalls=1), [], []))
        self.assertFalse(helper.picker_after_mouse_safe(dict(before_down, rounds=[{"action": "DISPATCH_ENTERED"}]), [], []))

    def test_second_preflight_requires_the_complete_first_refusal(self):
        asset, window, tag = "a", 20, 31
        selected = dict(event="selection_boundary", source="mouse", targetRequested=True, assetIDDigest=asset,
                        windowNumber=window, clickCount=1, eventNumber=12, mouseProbeTag=tag,
                        diagnosticSessionDigest="s", diagnosticSequence=1)
        refused = dict(event="click_input_refused", assetIDDigest=asset, diagnosticSessionDigest="s",
                       diagnosticSequence=2, phase="resolveSelection", error="browserNotFrontmost", critical=True)
        evidence = [selected, refused]
        sent = [(asset, window, tag, 12)]
        report = {"pressAttempts": 1, "confirmedDistinctRefusals": 1, "mouseDispatchCalls": 1,
                  "result": "PARTIAL_NATIVE_THUMBNAIL_MOUSE_TARGET_UNVERIFIED",
                  "rounds": [{"action": "ONE_GLOBAL_MOUSE_DOWN_UP_POSTED", "retained": "BOTH_ORIGINAL_ASSETS_VISIBLE_PENDING"},
                             {"action": "NOT_RUN"}]}
        self.assertTrue(helper.picker_after_mouse_safe(report, sent, evidence))
        self.assertFalse(helper.picker_after_mouse_safe(report, sent, [selected]))
        self.assertFalse(helper.picker_after_mouse_safe(report, sent, [selected, dict(refused, phase="submitSelection")]))
        self.assertFalse(helper.picker_after_mouse_safe(dict(report, pressAttempts=2), sent, evidence))


    def test_failure_receipts_report_which_identity_did_not_match_without_exporting_it(self):
        asset, other, tag, window = "private-asset", "private-other", 902875921321, 19887
        selection = dict(event="selection_boundary", source="mouse", assetIDDigest=asset, mouseProbeTag=tag,
            windowNumber=window + 1, clickCount=1, eventNumber=13, diagnosticSequence=8,
            diagnosticSessionDigest="private-session", targetRequested=True)
        refusal = dict(event="click_input_refused", assetIDDigest=asset, diagnosticSequence=9,
            diagnosticSessionDigest="private-session", critical=True, phase="resolveSelection", error="browserNotFrontmost")
        evidence = [selection, refusal, dict(event="click_target_resolved", assetIDDigest=other)]
        value = helper.summarize_mouse_receipts(evidence, [(asset, window, tag, 12)])
        row = value["dispatches"][0]
        self.assertEqual((value["selectionCount"], value["refusalCount"], value["targetResolvedCount"]), (1, 1, 1))
        self.assertTrue(row["assetMatched"] and row["tagMatched"] and row["sameSession"] and row["refusalAfterSelection"])
        self.assertFalse(row["windowMatched"] or row["combinedIdentityMatched"])
        self.assertEqual(row["refusalStatuses"], ["browserNotFrontmost"])
        for secret in (asset, other, str(tag), str(window), "private-session"):
            self.assertNotIn(secret, json.dumps(value))
        self.assertFalse(helper.original_mouse_refusals(evidence, [(asset, window, tag, 12)]))

    def test_missing_or_unexpected_failure_records_cannot_become_evidence(self):
        sent = [("private-asset", 19, 382920, 13)]
        missing = helper.summarize_mouse_receipts([], sent)
        self.assertEqual(missing["selectionCount"], 0)
        self.assertFalse(missing["dispatches"][0]["criticalRefusal"])
        unknown = helper.summarize_mouse_receipts([dict(event="click_input_refused", assetIDDigest=sent[0][0],
            error="private-url", phase="other")], sent)
        self.assertEqual(unknown["dispatches"][0]["refusalStatuses"], ["OTHER"])
        self.assertNotIn("private-url", json.dumps(unknown))

    def test_failed_probe_reads_keep_other_observations_and_never_enable_candidate(self):
        def unavailable():
            raise RuntimeError("private error")
        with tempfile.TemporaryDirectory() as directory:
            draft = helper.Draft("private-title")
            draft.post_requests = 1
            draft.picker_events = ["firstBodyByte", "exactCompleteBody"]
            result = helper.observe_mouse_failure(Path(directory) / "missing.jsonl", [("private-asset", 7, 91, 14)],
                Path(directory) / "missing.sqlite", {}, unavailable, lambda: True, draft)
        self.assertEqual(result["originalProductAlive"], "READ_UNAVAILABLE")
        self.assertIs(result["originalEdgeFrontWindow"], True)
        self.assertEqual(result["fixture"]["receiverCompletes"], 1)
        self.assertEqual(result["fixture"]["postRequests"], 1)
        self.assertFalse(result["fixture"]["candidateEnabled"])
        self.assertNotIn("private", json.dumps(result))
        report = dict(pressAttempts=1, mouseDispatchCalls=1, confirmedDistinctRefusals=0, result="FAILED_CONTROLLED_CHECK",
            rounds=[dict(action="ONE_GLOBAL_MOUSE_DOWN_UP_POSTED")])
        self.assertFalse(helper.picker_after_mouse_safe(report, [("private-asset", 7, 91, 14)], []))


    def test_failed_dispatch_observes_original_queue_and_upload_counts_read_only(self):
        with tempfile.TemporaryDirectory() as directory:
            dbfile = Path(directory) / "own.sqlite"
            with sqlite3.connect(dbfile) as db:
                db.executescript("CREATE TABLE assets(id TEXT,file_name TEXT,status TEXT,visibility TEXT,image_json TEXT);"
                                 "CREATE TABLE operations(id INTEGER); CREATE TABLE upload_starts(id INTEGER);")
                db.execute("INSERT INTO assets VALUES(?,?,?,?,?)", ("private-id", "own.png", "pending", "visible",
                    json.dumps(dict(origin="systemScreenshot", sha256="private-hash"))))
                db.execute("INSERT INTO operations VALUES(1)")
            before = helper.read_assets(dbfile)
            result = helper.observe_mouse_failure(Path(directory) / "missing.jsonl", [("private-id", 1, 2, 15)],
                dbfile, before, lambda: True, lambda: False, helper.Draft("private-title"))
            self.assertEqual(helper.read_assets(dbfile), before)
        self.assertEqual(result["queue"], dict(assetCount=1, originalAssetCount=1, originalRowsPresent=True,
            originalRowsPendingVisible=True, unchangedFromImport=True, operations=1, upload_starts=0))
        self.assertFalse(result["originalEdgeFrontWindow"])
        self.assertNotIn("private", json.dumps(result))
