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
import math
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


def finite_number(value: object) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def positive_rect(value: object) -> bool:
    return (isinstance(value, list) and len(value) == 4 and all(finite_number(item) for item in value)
            and value[2] > 0 and value[3] > 0)


def contains_rect(outer: list[float], inner: list[float]) -> bool:
    return (outer[0] <= inner[0] and outer[1] <= inner[1]
            and outer[0] + outer[2] >= inner[0] + inner[2]
            and outer[1] + outer[3] >= inner[1] + inner[3])


def intersects_rect(first: list[float], second: list[float]) -> bool:
    return (first[0] < second[0] + second[2] and second[0] < first[0] + first[2]
            and first[1] < second[1] + second[3] and second[1] < first[1] + first[3])


def verify_entry_readiness(event: dict, frame: dict) -> None:
    required = ("fixedSlotsUnchanged", "countdownVisible", "nextModeVisible", "entrySettled", "statusWindowVisible",
                "statusAvoidsInputs", "statusTextFits", "statusDisplayComplete")
    if (any(event.get(key) is not True for key in required) or event.get("captureExecuted") is not False
            or event.get("mode") != "fullScreen" or event.get("entryFrameScheduled") is not False
            or not finite_number(event.get("entryExpansion")) or event["entryExpansion"] != 1
            or type(event.get("cancelTargetSlot")) is not int or event["cancelTargetSlot"] not in range(3)
            or not finite_number(event.get("cancelSlotPosition")) or event["cancelSlotPosition"] != event["cancelTargetSlot"]):
        raise ValueError("entryFrozenRequestPresentationNotObserved")
    if (any(not finite_number(event.get(key)) or not 0.99 <= event[key] <= 1
            for key in ("statusWindowAlpha", "statusContentAlpha", "statusLabelAlpha"))
            or not finite_number(event.get("displayCommitWaitSeconds")) or event["displayCommitWaitSeconds"] < 0.05):
        raise ValueError("entryNativeDisplayNotReady")
    rect_keys = ("statusFrame", "statusContentBounds", "statusLabelFrame", "statusLabelScreenFrame", "captureRect")
    if any(not positive_rect(event.get(key)) for key in rect_keys):
        raise ValueError("entryStatusGeometryInvalid")
    capture, status = event["captureRect"], event["statusFrame"]
    inputs = event.get("inputFrames")
    if (capture[2:] != frame.get("points") or not contains_rect(capture, status)
            or not contains_rect(event["statusContentBounds"], event["statusLabelFrame"])
            or not contains_rect(status, event["statusLabelScreenFrame"])
            or not isinstance(inputs, list) or len(inputs) != 10
            or any(not positive_rect(rect) or intersects_rect(status, rect) for rect in inputs)
            or type(event.get("statusWindowNumber")) is not int or event["statusWindowNumber"] <= 0
            or event["statusWindowNumber"] not in frame.get("ownWindowNumbersFrontToBack", [])):
        raise ValueError("entryStatusNotInsideCapturedWindowGeometry")


def verify_feedback_display(event: dict, frame: dict) -> None:
    alphas = event.get("feedbackAlphas")
    if (event.get("failureVisible") is not True or event.get("feedbackFailureState") != "draftSaveFailed"
            or event.get("feedbackDisplayComplete") is not True
            or not finite_number(event.get("displayCommitWaitSeconds")) or event["displayCommitWaitSeconds"] < 0.05
            or type(event.get("feedbackWindowNumber")) is not int or event["feedbackWindowNumber"] <= 0
            or event["feedbackWindowNumber"] not in frame.get("ownWindowNumbersFrontToBack", [])
            or not isinstance(alphas, list) or len(alphas) != 6
            or any(not finite_number(value) or not 0.99 <= value <= 1 for value in alphas)):
        raise ValueError("feedbackFailureNativeDisplayNotReady")
    content = event.get("feedbackContentBounds")
    status = event.get("feedbackStatusFrame")
    viewport = event.get("feedbackEditorViewportFrame")
    recovery = event.get("feedbackRecoveryFrames")
    alignment = event.get("feedbackRecoveryAlignmentFrames")
    if (not all(positive_rect(rect) for rect in (content, status, viewport))
            or not isinstance(recovery, list) or len(recovery) != 2 or not all(positive_rect(rect) for rect in recovery)
            or not isinstance(alignment, list) or len(alignment) != 2 or not all(positive_rect(rect) for rect in alignment)
            or any(value > bound for value, bound in zip(content[2:], frame["points"]))
            or any(not contains_rect(content, rect) for rect in [status, viewport, *recovery])
            or any(not contains_rect(full, aligned) for full, aligned in zip(recovery, alignment))
            or intersects_rect(alignment[0], alignment[1])
            or any(intersects_rect(status, rect) or intersects_rect(viewport, rect) for rect in recovery)
            or intersects_rect(status, viewport)):
        raise ValueError("feedbackFailureControlsOutsideVisibleViewport")


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
        viewport = event.get("previewViewportPoints")
        if (event.get("previewDisplayComplete") is not True
                or not finite_number(event.get("displayCommitWaitSeconds")) or event["displayCommitWaitSeconds"] < 0.05
                or type(event.get("previewWindowNumber")) is not int or event["previewWindowNumber"] <= 0
                or event["previewWindowNumber"] not in frames[0].get("ownWindowNumbersFrontToBack", [])
                or not isinstance(viewport, list) or len(viewport) != 2
                or any(not finite_number(value) or value <= 0 for value in viewport)
                or any(value > bound for value, bound in zip(viewport, frames[0]["points"]))):
            raise ValueError("historyPreviewNativeDisplayNotReady")
        if missing and frames[0].get("points") != [360, 280]:
            raise ValueError("historyMinimumWindowNotCaptured")
    elif name == "feedback-save-failure":
        if (any(event.get(key) is not True for key in ("retryEnabled", "copyEnabled", "draftRetained",
                "savedDraftUnchanged", "recordsEmpty"))
                or event.get("persistenceFault") != "ownedSQLiteJournalPathCollision"
                or [event.get("windowWidth"), event.get("windowHeight")] != [560, 500]
                or frames[0].get("points") != [560, 500]):
            raise ValueError("feedbackFailureRecoveryNotObserved")
        verify_feedback_display(event, frames[0])
    elif name == "queue-feedback":
        if (event.get("noteVisible") is not True or event.get("noteAvoidsInputs") is not True
                or event.get("captureExecuted") is not False):
            raise ValueError("queueExplanationNotObserved")
    elif name == "entry-countdown":
        verify_entry_readiness(event, frames[0])
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
                         windowWidth=points[0], windowHeight=points[1], previewDisplayComplete=True,
                         previewWindowNumber=99, previewViewportPoints=[points[0] - 32, points[1] - 82],
                         displayCommitWaitSeconds=0.05)
            required = ["titleMatches", "parentOrderedOut", "previewDisplayComplete"]
        elif name == "feedback-save-failure":
            points = [560, 500]
            required = ["retryEnabled", "copyEnabled", "draftRetained", "savedDraftUnchanged", "recordsEmpty",
                        "failureVisible", "feedbackDisplayComplete"]
            event.update({key: True for key in required})
            event.update(persistenceFault="ownedSQLiteJournalPathCollision", windowWidth=560, windowHeight=500,
                         feedbackFailureState="draftSaveFailed", feedbackWindowNumber=99, feedbackAlphas=[1] * 6,
                         displayCommitWaitSeconds=0.05, feedbackContentBounds=[0, 0, 560, 472],
                         feedbackStatusFrame=[24, 80, 512, 18], feedbackRecoveryFrames=[[17, 37, 125, 32], [136, 37, 86, 32]],
                         # Synthetic validator fixture: overlapping outer frames
                         # with separate content alignment, never an amended capture.
                         feedbackRecoveryAlignmentFrames=[[24, 44, 111, 20], [143, 44, 72, 20]],
                         feedbackEditorViewportFrame=[25, 201, 494, 148])
        elif name == "queue-feedback":
            required = ["noteVisible", "noteAvoidsInputs"]
            event.update(noteVisible=True, noteAvoidsInputs=True, captureExecuted=False)
        else:
            points = [1024, 684]
            required = ["fixedSlotsUnchanged", "countdownVisible", "nextModeVisible", "entrySettled", "statusWindowVisible",
                        "statusAvoidsInputs", "statusTextFits", "statusDisplayComplete"]
            event.update({key: True for key in required})
            event.update(captureExecuted=False, mode="fullScreen", entryExpansion=1, entryFrameScheduled=False,
                         cancelSlotPosition=2, cancelTargetSlot=2, statusWindowNumber=99,
                         statusWindowAlpha=1, statusContentAlpha=1, statusLabelAlpha=1, displayCommitWaitSeconds=0.05,
                         statusFrame=[700, 400, 240, 60], statusContentBounds=[0, 0, 240, 60],
                         statusLabelFrame=[12, 12, 216, 36], statusLabelScreenFrame=[712, 412, 216, 36],
                         captureRect=[0, 0, *points], inputFrames=[[950, 100 + 40 * i, 30, 30] for i in range(10)])
        report = {"status": "CAPTURED_NATIVE_WINDOWSERVER", "supplementalCase": name, "supplementalStage": "ready",
                  "events": [event], "frames": [{"status": "CAPTURED_NATIVE_WINDOWSERVER", "points": points}]}
        if name in ("entry-countdown", "feedback-save-failure") or name.startswith("history-preview-"):
            report["frames"][0]["ownWindowNumbersFrontToBack"] = [99, 100]
        verify_supplement(flags, report)
        for key in required + ["physical", "networkEnabled", "receiptEvidence"]:
            changed = copy.deepcopy(report); changed["events"][0][key] = not event[key]
            try: verify_supplement(flags, changed)
            except ValueError: negative_checks += 1
            else: raise AssertionError("unsafe supplemental observation accepted: " + key)
        if name == "feedback-save-failure":
            assert intersects_rect(*event["feedbackRecoveryFrames"])
            assert not intersects_rect(*event["feedbackRecoveryAlignmentFrames"])
            for key, value in {"feedbackFailureState": "saving", "feedbackWindowNumber": 101,
                               "feedbackAlphas": [1, 1, 0, 1, 1, 1], "displayCommitWaitSeconds": 0,
                               "feedbackContentBounds": [0, 0, 0, 472], "feedbackStatusFrame": [24, 480, 512, 18],
                               "feedbackRecoveryFrames": [[24, 48, 115, 24]] * 2,
                               "feedbackEditorViewportFrame": [24, 48, 494, 148]}.items():
                changed = copy.deepcopy(report); changed["events"][0][key] = value
                try: verify_supplement(flags, changed)
                except ValueError: negative_checks += 1
                else: raise AssertionError("undrawn Feedback recovery accepted: " + key)
            for invalid in (None, [], [[24, 44, 0, 20], [143, 44, 72, 20]],
                            [[16, 44, 111, 20], [143, 44, 72, 20]],
                            [[137, 44, 4, 20], [137, 44, 4, 20]]):
                changed = copy.deepcopy(report); changed["events"][0]["feedbackRecoveryAlignmentFrames"] = invalid
                try: verify_supplement(flags, changed)
                except ValueError: negative_checks += 1
                else: raise AssertionError("missing, out-of-bounds or overlapping button alignment accepted")
            missing = copy.deepcopy(report); del missing["events"][0]["feedbackRecoveryAlignmentFrames"]
            try: verify_supplement(flags, missing)
            except ValueError: negative_checks += 1
            else: raise AssertionError("unobserved button alignment accepted")
        if name.startswith("history-preview-"):
            for key, value in {"previewWindowNumber": 101, "previewViewportPoints": [0, 100],
                               "displayCommitWaitSeconds": 0}.items():
                changed = copy.deepcopy(report); changed["events"][0][key] = value
                try: verify_supplement(flags, changed)
                except ValueError: negative_checks += 1
                else: raise AssertionError("undrawn history preview accepted: " + key)
        if name == "entry-countdown":
            invalid_readiness = {
                "entryFrameScheduled": True, "entryExpansion": 0.9, "cancelSlotPosition": 0.5,
                "cancelTargetSlot": True, "mode": "region", "statusWindowAlpha": 0,
                "statusContentAlpha": float("nan"), "statusLabelAlpha": 0, "displayCommitWaitSeconds": 0,
                "statusFrame": [1000, 400, 240, 60], "statusContentBounds": [0, 0, 0, 60],
                "statusLabelFrame": [0, 0, 241, 36], "statusLabelScreenFrame": [0, 0, 216, 36],
                "captureRect": [0, 0, 800, 684], "inputFrames": [event["statusFrame"]] * 10,
                "statusWindowNumber": 101,
            }
            for key, value in invalid_readiness.items():
                changed = copy.deepcopy(report); changed["events"][0][key] = value
                try: verify_supplement(flags, changed)
                except ValueError: negative_checks += 1
                else: raise AssertionError("unready native countdown accepted: " + key)
            missing = copy.deepcopy(report); missing["events"][0]["inputFrames"] = event["inputFrames"][:4]
            try: verify_supplement(flags, missing)
            except ValueError: negative_checks += 1
            else: raise AssertionError("missing queue avoidance evidence accepted")
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
