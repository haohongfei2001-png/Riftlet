#!/usr/bin/env python3
"""Additional native product-window pixels; the original 46 cases/5 MOVs remain required.

Uses the original verifier without modifying its registry or execution path.
All state is helper-owned synthetic presentation. Physical input, real system
screenshots, real rejection/upload, and cloud Feedback acceptance remain NOT_RUN.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time


BASE_PATH = Path(__file__).with_name("capture-native-visual-evidence.py")
SPEC = importlib.util.spec_from_file_location("riftlet_original_native_visual", BASE_PATH)
assert SPEC is not None and SPEC.loader is not None
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)


def cases() -> list[tuple[str, list[str]]]:
    return [
        ("history-preview-portrait-light", ["--appearance", "light", "--visual-window", "history",
            "--visual-supplement", "history-preview-portrait"]),
        ("history-preview-wide-dark", ["--appearance", "dark", "--visual-window", "history",
            "--visual-supplement", "history-preview-wide"]),
        ("history-preview-missing-minimum-light", ["--appearance", "light", "--visual-window", "history",
            "--visual-supplement", "history-preview-missing"]),
        ("feedback-save-failure-minimum-light", ["--appearance", "light", "--visual-window", "feedback",
            "--visual-supplement", "feedback-save-failure"]),
        ("queue-feedback-dark", ["--appearance", "dark", "--visual-scene", "3",
            "--visual-supplement", "queue-feedback"]),
        ("entry-countdown-next-mode-light", ["--appearance", "light", "--visual-scene", "3",
            "--visual-entry", "--visual-entry-expanded", "--visual-supplement", "entry-countdown"]),
    ]


def verify_supplement(flags: list[str], report: dict) -> None:
    name = flags[flags.index("--visual-supplement") + 1]
    if report.get("supplementalCase") != name:
        raise ValueError("supplementalCaseMismatch")
    if "movie" in report:
        raise ValueError("supplementalStaticCaseHasMovie")
    if report.get("status") == "NOT_RUN":
        return
    if report.get("supplementalStage") != "ready":
        raise ValueError("supplementalPreparationIncomplete")
    events = [event for event in report.get("events", []) if event.get("event") == "native_evidence_supplemental"]
    if len(events) != 1:
        raise ValueError("missingUniqueSupplementalObservation")
    event = events[0]
    if (event.get("supplementalCase") != name or event.get("softwareSelection") is not True
            or any(event.get(key) is not False for key in ("physical", "networkEnabled", "receiptEvidence"))):
        raise ValueError("supplementalScopeMismatch")
    frames = report.get("frames", [])
    if len(frames) != 1 or frames[0].get("status") != "CAPTURED_NATIVE_WINDOWSERVER":
        raise ValueError("supplementalOriginalFrameMissing")
    if name.startswith("history-preview-"):
        missing = name == "history-preview-missing"
        wide = name == "history-preview-wide"
        if (event.get("titleMatches") is not True or event.get("parentOrderedOut") is not True
                or event.get("imageLoaded") is not (not missing) or event.get("imageAbsent") is not missing
                or event.get("failureVisible") is not missing
                or event.get("fixtureSequence") != (5 if wide else 4)
                or [event.get("fixturePixelWidth"), event.get("fixturePixelHeight")] != ([768, 96] if wide else [96, 768])):
            raise ValueError("historyPreviewOutcomeNotObserved")
        if frames[0].get("points") != [event.get("windowWidth"), event.get("windowHeight")]:
            raise ValueError("historyPreviewWindowMismatch")
        if missing and frames[0].get("points") != [360, 280]:
            raise ValueError("historyMinimumWindowNotCaptured")
    elif name == "feedback-save-failure":
        if (any(event.get(key) is not True for key in ("retryEnabled", "copyEnabled", "draftRetained",
                "savedDraftUnchanged", "recordsEmpty"))
                or event.get("persistenceFault") != "ownedSQLiteJournalPathCollision"
                or [event.get("windowWidth"), event.get("windowHeight")] != [560, 500]
                or frames[0].get("points") != [560, 500]):
            raise ValueError("feedbackFailureRecoveryNotObserved")
    elif name == "queue-feedback":
        if (event.get("noteVisible") is not True or event.get("noteAvoidsInputs") is not True
                or event.get("captureExecuted") is not False):
            raise ValueError("queueExplanationNotObserved")
    elif name == "entry-countdown":
        if (any(event.get(key) is not True for key in ("fixedSlotsUnchanged", "countdownVisible", "nextModeVisible"))
                or event.get("captureExecuted") is not False):
            raise ValueError("entryFrozenRequestPresentationNotObserved")
    else:
        raise ValueError("unknownSupplementalCase")


def self_check() -> None:
    original = BASE.cases()
    assert len(original) == 46
    assert [name for name, flags in original if "--visual-timeline" in flags] == [
        "motion-magnet", "motion-none", "motion-reduce-motion", "motion-interrupt", "motion-missing-source"]
    registered = cases()
    assert len(registered) == 6 and len({name for name, _ in registered}) == 6
    assert not {name for name, _ in registered} & {name for name, _ in original}
    assert all("--visual-timeline" not in flags for _, flags in registered)
    negative_checks = 0
    for _, flags in registered:
        name = flags[flags.index("--visual-supplement") + 1]
        event = {"event": "native_evidence_supplemental", "supplementalCase": name,
                 "softwareSelection": True, "physical": False, "networkEnabled": False, "receiptEvidence": False}
        points = [640, 502]
        if name.startswith("history-preview-"):
            missing, wide = name.endswith("missing"), name.endswith("wide")
            if missing: points = [360, 280]
            event.update(titleMatches=True, parentOrderedOut=True, imageLoaded=not missing, imageAbsent=missing,
                         failureVisible=missing, fixtureSequence=5 if wide else 4,
                         fixturePixelWidth=768 if wide else 96, fixturePixelHeight=96 if wide else 768,
                         windowWidth=points[0], windowHeight=points[1])
            required = ["titleMatches", "parentOrderedOut"]
        elif name == "feedback-save-failure":
            points = [560, 500]
            required = ["retryEnabled", "copyEnabled", "draftRetained", "savedDraftUnchanged", "recordsEmpty"]
            event.update({key: True for key in required})
            event.update(persistenceFault="ownedSQLiteJournalPathCollision", windowWidth=560, windowHeight=500)
        elif name == "queue-feedback":
            required = ["noteVisible", "noteAvoidsInputs"]
            event.update(noteVisible=True, noteAvoidsInputs=True, captureExecuted=False)
        else:
            required = ["fixedSlotsUnchanged", "countdownVisible", "nextModeVisible"]
            event.update({key: True for key in required}); event["captureExecuted"] = False
        report = {"status": "CAPTURED_NATIVE_WINDOWSERVER", "supplementalCase": name, "supplementalStage": "ready",
                  "events": [event], "frames": [{"status": "CAPTURED_NATIVE_WINDOWSERVER", "points": points}]}
        verify_supplement(flags, report)
        for key in required + ["physical", "networkEnabled", "receiptEvidence"]:
            changed = copy.deepcopy(report); changed["events"][0][key] = not event[key]
            try: verify_supplement(flags, changed)
            except ValueError: negative_checks += 1
            else: raise AssertionError("unsafe supplemental observation accepted: " + key)
        unavailable = copy.deepcopy(report); unavailable["status"] = "NOT_RUN"
        verify_supplement(flags, unavailable)
    print(f"SUPPLEMENTAL_MANIFEST_SELF_CHECK_PASS: 6 static cases; {negative_checks} rejected unsafe observations; original 46 cases/5 movies unchanged; GUI_NOT_RUN")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--helper", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-system-accessibility", choices=("normal",), default="normal")
    args = parser.parse_args()
    if args.self_check:
        self_check(); return 0
    if args.helper is None or args.output is None:
        parser.error("--helper and --output are required for native evidence")
    repository = Path(__file__).resolve().parents[1]
    source = BASE.git(repository, "rev-parse", os.environ.get("RIFTLET_BUILD_HEAD_SHA", "HEAD") + "^{commit}")
    checkout = BASE.git(repository, "rev-parse", "HEAD")
    if BASE.git(repository, "status", "--porcelain", "--untracked-files=no"):
        parser.error("Native evidence requires a clean tracked source tree.")
    helper = args.helper.resolve(strict=True)
    output = args.output.absolute()
    if output.exists() or output.is_symlink() or output.resolve() != output:
        parser.error("Output must be a new directory without symlink parents.")
    output.mkdir(parents=True); (output / "scenes").mkdir()
    report = {"schemaVersion": 1, "source": source, "checkout": checkout,
              "helperSHA256": hashlib.sha256(helper.read_bytes()).hexdigest(),
              "scope": "Supplemental synthetic native WindowServer pixels; original full suite separately required",
              "baseFullSuiteAcceptance": "SEPARATE_REQUIRED", "expectedSystemAccessibility": "normal",
              "physicalInput": "NOT_RUN", "realScreenshot": "NOT_RUN", "realUpload": "NOT_RUN",
              "realRejection": "NOT_RUN", "cloudFeedback": "NOT_RUN", "cases": []}
    if platform.system() != "Darwin":
        report.update(status="NOT_RUN", reason="macOSWindowServerRequired")
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        return 0
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="riftlet-supplemental-process-") as temporary:
        for name, flags in cases():
            destination = output / "scenes" / name
            command = [str(helper), "--visual-clean", "--export-native-evidence", str(destination),
                       "--evidence-source", source, "--evidence-checkout", checkout] + flags
            case = {"name": name, "arguments": flags, "status": "FAIL"}
            process_log = Path(temporary) / (name + ".log")
            with process_log.open("wb") as log:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                try: process.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    try: process.wait(timeout=1)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
                    case["reason"] = "helperTimedOut"
                case["returnCode"] = process.returncode
            try:
                capture = json.loads((destination / "capture.json").read_text(encoding="utf-8"))
                BASE.verify_capture(destination, capture, source, checkout)
                BASE.verify_case_behavior(flags, capture, "normal")
                verify_supplement(flags, capture)
                if process.returncode != 0: raise ValueError("helperExitFailure")
                case["capture"] = capture; case["status"] = capture["status"]
            except (OSError, ValueError, TypeError, KeyError) as error:
                detail = str(error) if isinstance(error, ValueError) else "missingOrMalformedCaptureManifest"
                case.setdefault("reason", detail); case["manifestError"] = detail
            if case["status"] == "FAIL":
                destination.mkdir(exist_ok=True)
                if not destination.is_symlink():
                    with process_log.open("rb") as log:
                        log.seek(0, os.SEEK_END); length = log.tell()
                        log.seek(max(0, length - 2 * 1024 * 1024)); diagnostic = log.read()
                    (destination / "helper.log").write_bytes(diagnostic)
                    case["helperLog"] = f"scenes/{name}/helper.log"
                    case["helperLogTruncated"] = length > len(diagnostic)
            report["cases"].append(case)
            print(f'{name}: {case["status"]}' + (f' ({case["reason"]})' if "reason" in case else ""), flush=True)
    statuses = [case["status"] for case in report["cases"]]
    report["status"] = "FAIL" if "FAIL" in statuses else "NOT_RUN" if "NOT_RUN" in statuses else "CAPTURED_NATIVE_WINDOWSERVER"
    report["capturedImageCount"] = sum(1 for case in report["cases"]
        for frame in case.get("capture", {}).get("frames", []) if "file" in frame)
    report["durationSeconds"] = round(time.monotonic() - started, 3)
    (output / "summary.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    BASE.write_index(output, report)
    print(f'SUPPLEMENTAL_NATIVE_VISUAL_{report["status"]}: {report["capturedImageCount"]}/6 original static images; ORIGINAL_FULL_SUITE_SEPARATELY_REQUIRED; PHYSICAL_NOT_RUN; REAL_UPLOAD_NOT_RUN')
    return 1 if report["status"] == "FAIL" else 0


if __name__ == "__main__":
    raise SystemExit(main())
