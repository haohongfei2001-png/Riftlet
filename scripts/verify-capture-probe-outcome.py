#!/usr/bin/env python3
"""Reject actual CLI output failures without turning unavailable capture into PASS.

This checks only the screencapture file-output contract exercised by the owned
synthetic probe. It does not admit a backend, prove pixels/HDR, or accept the UI.
"""
import argparse
import json
from pathlib import Path

NOT_RUN_REASONS = frozenset((
    "SCREEN_CAPTURE_PERMISSION_NOT_ALREADY_GRANTED",
    "SELECTED_DISPLAY_NOT_AVAILABLE",
    "DISPLAY_TOO_SMALL_OR_NO_ID",
    "REGION_NOT_STRICTLY_INSIDE_FIXTURE",
))


def evaluate(report):
    result = {"schemaVersion": 1, "status": "FAIL", "scope": "SCREENCAPTURE_FILE_OUTPUT_ONLY",
              "physicalAcceptance": "NOT_RUN", "pixelColorAcceptance": "NOT_GRANTED",
              "uploadAdmission": "NOT_GRANTED"}
    if not isinstance(report, dict) or report.get("schemaVersion") != 1:
        return dict(result, reason="INVALID_REPORT_SCHEMA")
    if report.get("permissionRequested") is not False or report.get("rawImagesPersistedAsArtifacts") is not False:
        return dict(result, reason="PROBE_BOUNDARY_NOT_CONFIRMED")
    if report.get("status") == "NOT_RUN" and report.get("reason") in NOT_RUN_REASONS:
        return dict(result, status="NOT_RUN", reason=report["reason"])
    if report.get("status") != "COMPLETED_MEASUREMENT_PROBE" or not isinstance(report.get("samples"), list):
        return dict(result, reason="MEASUREMENT_NOT_COMPLETED")
    samples = [sample for sample in report["samples"]
               if isinstance(sample, dict) and sample.get("backend") == "screencapture"]
    if not samples:
        return dict(result, reason="CLI_SAMPLES_MISSING")
    captured = refused = omitted = 0
    errors = []
    for sample in samples:
        status = sample.get("status")
        if status == "CAPTURED":
            metadata = sample.get("metadata", {})
            if not isinstance(metadata, dict) or any(type(metadata.get(key)) is not int or metadata[key] <= 0
                                                     for key in ("width", "height", "rawPNGBytes")):
                errors.append("CAPTURED_SAMPLE_MISSING_VALID_PNG_METADATA")
            else:
                captured += 1
        elif status == "ERROR" and sample.get("reason") == "FIXTURECHANGED":
            refused += 1
        elif status == "NOT_RUN":
            omitted += 1
        else:
            # Do not print arbitrary sample text, paths or native error messages.
            errors.append("ACTUAL_CLI_OUTPUT_ERROR")
    result.update(capturedSamples=captured, fixtureRefusals=refused, omittedVariants=omitted,
                  outputErrorCount=len(errors))
    if errors:
        return dict(result, reason="CLI_OUTPUT_CONTRACT_FAILED", errors=sorted(set(errors)))
    if captured:
        return dict(result, status="PASS_FILE_OUTPUT_ONLY", reason="VALID_EXACT_PATH_PNG_SAMPLES")
    if refused:
        return dict(result, status="NOT_RUN", reason="OWN_FIXTURE_NOT_AVAILABLE")
    return dict(result, reason="CLI_CAPTURE_NOT_EXERCISED")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    arguments = parser.parse_args()
    try:
        result = evaluate(json.loads(arguments.report.read_text()))
    except (OSError, UnicodeError, ValueError, TypeError):
        result = {"schemaVersion": 1, "status": "FAIL", "reason": "REPORT_UNREADABLE"}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if result["status"] == "FAIL" else 0


if __name__ == "__main__":
    raise SystemExit(main())
