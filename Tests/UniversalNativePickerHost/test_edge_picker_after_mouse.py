import importlib.util
from pathlib import Path
import unittest

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
