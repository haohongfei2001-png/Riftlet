"""New gate wiring; generic rejection faults live in the reused 21-case suite."""
from dataclasses import replace
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/verify-builtin-capture-composition.py"
SPEC = importlib.util.spec_from_file_location("builtin_capture_gate", SCRIPT)
GATE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = GATE
SPEC.loader.exec_module(GATE)


class BuiltInCaptureGateTests(unittest.TestCase):
    def test_reuses_exact_reviewed_engine_blob(self):
        actual = GATE.ENGINE.git(ROOT, "rev-parse", GATE.BASELINE + ":" + GATE.ENGINE_PATH).decode().strip()
        self.assertEqual(actual, GATE.ENGINE_BLOB)

    def test_all_historical_composition_checks_still_execute(self):
        passed, report = GATE.ENGINE.run_historical(ROOT, GATE.POLICY.histories[0])
        self.assertTrue(passed)
        self.assertEqual(report["revision"], GATE.BASELINE)
        self.assertEqual(set(report["historicalAudits"]), {"internal-beta", "capture-entry", "arrival"})
        self.assertTrue(all(item["result"] == "PASS" for item in report["checks"]))

    def test_missing_source_pin_fails_closed(self):
        report = GATE.audit(ROOT, GATE.BASELINE, replace(GATE.POLICY, reviewed_source=None))
        self.assertEqual(report["result"], "FAIL")
        self.assertTrue(any(c["id"] == "audit:inputs" and c["result"] == "FAIL" for c in report["checks"]))

    def test_post_review_exceptions_are_three_exact_regular_paths(self):
        self.assertEqual(GATE.METADATA_PATHS, frozenset((GATE.GATE_PATH,
            "docs/BUILTIN_CAPTURE_HANDOFF_2026-10-29.md",
            "engineering/evidence/2026-10-29-builtin-capture/results.json")))
        self.assertTrue(all(GATE.ENGINE.valid_path(path) for path in GATE.METADATA_PATHS))
        self.assertNotIn(GATE.ENGINE_PATH, GATE.METADATA_PATHS)

    def test_cli_cannot_override_source_review(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--reviewed-source", GATE.BASELINE],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
