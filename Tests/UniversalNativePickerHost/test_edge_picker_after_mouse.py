import importlib.util
from pathlib import Path
import unittest
import json
import tempfile

helper_path = Path(__file__).resolve().parents[1] / "LiveCompatibility/edge_host.py"
spec = importlib.util.spec_from_file_location("isolated_edge_host", helper_path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class IndependentPickerTests(unittest.TestCase):
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
        sent = [(asset, window, tag)]
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
        value = helper.summarize_mouse_receipts(evidence, [(asset, window, tag)])
        row = value["dispatches"][0]
        self.assertEqual((value["selectionCount"], value["refusalCount"], value["targetResolvedCount"]), (1, 1, 1))
        self.assertTrue(row["assetMatched"] and row["tagMatched"] and row["sameSession"] and row["refusalAfterSelection"])
        self.assertFalse(row["windowMatched"] or row["combinedIdentityMatched"])
        self.assertEqual(row["refusalStatuses"], ["browserNotFrontmost"])
        for secret in (asset, other, str(tag), str(window), "private-session"):
            self.assertNotIn(secret, json.dumps(value))
        self.assertFalse(helper.original_mouse_refusals(evidence, [(asset, window, tag)]))

    def test_missing_or_unexpected_failure_records_cannot_become_evidence(self):
        sent = [("private-asset", 19, 382920)]
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
            result = helper.observe_mouse_failure(Path(directory) / "missing.jsonl", [("private-asset", 7, 91)],
                Path(directory) / "missing.sqlite", {}, unavailable, lambda: True, draft)
        self.assertEqual(result["originalProductAlive"], "READ_UNAVAILABLE")
        self.assertIs(result["originalEdgeFrontWindow"], True)
        self.assertEqual(result["fixture"]["receiverCompletes"], 1)
        self.assertEqual(result["fixture"]["postRequests"], 1)
        self.assertFalse(result["fixture"]["candidateEnabled"])
        self.assertNotIn("private", json.dumps(result))
        report = dict(pressAttempts=1, mouseDispatchCalls=1, confirmedDistinctRefusals=0, result="FAILED_CONTROLLED_CHECK",
            rounds=[dict(action="ONE_GLOBAL_MOUSE_DOWN_UP_POSTED")])
        self.assertFalse(helper.picker_after_mouse_safe(report, [("private-asset", 7, 91)], []))
