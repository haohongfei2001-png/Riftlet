#!/usr/bin/env python3
"""Capture bounded, synthetic-only AppKit evidence on a macOS WindowServer.

The helper captures only its own windows; this driver never calls screencapture
or requests screen-recording/accessibility permission. It records NOT_RUN when
the native capture API is unavailable. Native frames are evidence for visual
review, not an automatic aesthetic PASS, physical input, or real upload proof.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import os
from pathlib import Path
import platform
import re
import struct
import subprocess
import sys
import tempfile
import time


def cases():
    result = []
    for appearance in ("light", "dark"):
        base = ["--appearance", appearance]
        for page in range(3):
            result.append((f"setup-{page}-{appearance}", base + ["--visual-window", "setup", "--visual-onboarding-page", str(page)]))
        for section in range(5):
            result.append((f"settings-{section}-{appearance}", base + ["--visual-window", "settings", "--visual-settings-section", str(section)]))
        for name in ("history", "feedback"):
            result.append((f"{name}-{appearance}", base + ["--visual-window", name]))
        for state in ("archived", "unknown"):
            result.append((f"history-{state}-{appearance}", base + ["--visual-window", "history", "--visual-history-state", state]))
        result.append((f"queue-{appearance}", base + ["--visual-scene", "16"]))
        result.append((f"entry-{appearance}", base + ["--visual-scene", "3", "--visual-entry", "--visual-entry-expanded"]))
        result.append((f"last-page-{appearance}", base + ["--visual-scene", "16", "--visual-last-page"]))
        for ordinal, shape in ((4, "portrait"), (5, "wide")):
            result.append((f"preview-{shape}-{appearance}", base + ["--visual-scene", "16", "--visual-preview-index", str(ordinal)]))
    for appearance, background in (("light", "bright"), ("light", "textured"), ("dark", "textured")):
        result.append((f"entry-{background}-{appearance}", ["--appearance", appearance,
            "--visual-scene", "3", "--visual-entry", "--visual-entry-expanded", "--visual-background", background]))
    for page in (0, 2):
        result.append((f"firstuse-local-{page}-light", ["--appearance", "light", "--visual-window", "setup",
            "--visual-onboarding-page", str(page), "--visual-local-onboarding"]))
    for name, flags in (("magnet", ["--visual-magnet"]), ("none", []),
                        ("reduce-motion", ["--visual-magnet", "--visual-reduced-motion"]),
                        ("interrupt", ["--visual-magnet", "--visual-cancel-arrival"]),
                        ("missing-source", ["--visual-missing-source"])):
        result.append((f"motion-{name}", ["--appearance", "dark", "--visual-scene", "3", "--visual-timeline"] + flags))
    return result


def verify_capture(directory: Path, report: dict, source: str, checkout: str) -> None:
    if report.get("source") != source or report.get("checkout") != checkout:
        raise ValueError("sourceMismatch")
    required_false = ("otherApplicationPixelsCaptured", "screenCapturePermissionRequested", "performanceBenchmark")
    if any(report.get(key) is not False for key in required_false) or report.get("syntheticOnly") is not True:
        raise ValueError("invalidEvidenceScope")
    for key in ("physicalInput", "realScreenshot", "realUpload", "crossApplicationFocus", "productionWindowOrder"):
        if report.get(key) != "NOT_RUN":
            raise ValueError("unsupportedAcceptanceClaim")
    capture_kind = report.get("captureKind")
    if capture_kind not in ("single-product-window", "owned-product-composite"):
        raise ValueError("missingCaptureKind")
    for key in ("systemAccessibilityAtStart", "systemAccessibilityAtEnd"):
        value = report.get(key)
        if (not isinstance(value, dict) or set(value) != {"reduceMotion", "increaseContrast", "reduceTransparency"}
                or any(type(v) is not bool for v in value.values())):
            raise ValueError("missingSystemAccessibility")
    frames = report.get("frames")
    if not isinstance(frames, list) or not frames:
        raise ValueError("missingFrames")
    captured = 0
    for frame in frames:
        if frame.get("status") == "NOT_RUN":
            if "file" in frame:
                raise ValueError("notRunHasImage")
            continue
        name = frame.get("file", "")
        if frame.get("status") != "CAPTURED_NATIVE_WINDOWSERVER" or not re.fullmatch(r"[a-z0-9-]+\.png", name):
            raise ValueError("unsafeFramePathOrStatus")
        path = directory / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("missingRegularFrame")
        data = path.read_bytes()
        if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError("invalidPNG")
        pixels = list(struct.unpack(">II", data[16:24]))
        if min(pixels) <= 0 or pixels != frame.get("pixels"):
            raise ValueError("pixelDimensionMismatch")
        if len(data) != frame.get("bytes") or hashlib.sha256(data).hexdigest() != frame.get("sha256"):
            raise ValueError("frameHashMismatch")
        if frame.get("resized") is not False or frame.get("source") != source or frame.get("checkout") != checkout:
            raise ValueError("frameSourceOrResizeMismatch")
        if frame.get("syntheticOnly") is not True or frame.get("receiptEvidence") is not False:
            raise ValueError("frameScopeMismatch")
        own_count, product_count = frame.get("selectedOwnWindowCount"), frame.get("productWindowCount")
        numbers = frame.get("ownWindowNumbersFrontToBack")
        if (type(own_count) is not int or type(product_count) is not int
                or not isinstance(numbers, list) or any(type(n) is not int or n <= 0 for n in numbers)
                or len(numbers) != own_count or len(set(numbers)) != own_count
                or frame.get("windowOrdering") != "NSApplication.enumerateWindows(orderedFrontToBack)"):
            raise ValueError("invalidOwnWindowSet")
        if capture_kind == "single-product-window":
            if own_count != 1 or product_count != 1:
                raise ValueError("invalidSingleProductWindow")
        else:
            if own_count < 2 or product_count != own_count - 1:
                raise ValueError("missingProductWindow")
            difference = frame.get("productDifferencePixelCount")
            if (type(difference) is not int or frame.get("minimumProductDifferencePixels") != 64
                    or not 64 <= difference <= pixels[0] * pixels[1]):
                raise ValueError("missingProductPixels")
        captured += 1
    if report.get("status") == "CAPTURED_NATIVE_WINDOWSERVER" and captured != len(frames):
        raise ValueError("partialCaptureClaimedComplete")
    if report.get("status") not in ("NOT_RUN", "CAPTURED_NATIVE_WINDOWSERVER"):
        raise ValueError("captureFailed")
    if "movie" in report:
        verify_movie(directory, report["movie"], source, checkout, [frame for frame in frames if "file" in frame])


def verify_movie(directory: Path, movie: dict, source: str, checkout: str, frames: list) -> None:
    if movie.get("status") == "NOT_RUN":
        if "file" in movie:
            raise ValueError("notRunMovieHasFileClaim")
        return
    if movie.get("status") != "RECORDED_NATIVE_WINDOWSERVER" or movie.get("file") != "native-motion.mov":
        raise ValueError("unsafeMoviePathOrStatus")
    if movie.get("source") != source or movie.get("checkout") != checkout:
        raise ValueError("movieSourceMismatch")
    if (movie.get("syntheticOnly") is not True or movie.get("receiptEvidence") is not False
            or movie.get("physicalInput") != "NOT_RUN" or movie.get("performanceBenchmark") is not False
            or movie.get("contentResized") is not False):
        raise ValueError("movieScopeMismatch")
    content, encoded, padding = (movie.get(key) for key in ("contentPixels", "encodedPixels", "paddingPixels"))
    if any(not isinstance(value, list) or len(value) != 2 or any(type(v) is not int for v in value)
           for value in (content, encoded, padding)):
        raise ValueError("movieDimensionsMalformed")
    if (min(content) <= 0 or padding != [v % 2 for v in content]
            or encoded != [content[i] + padding[i] for i in range(2)]
            or any(frame.get("pixels") != content for frame in frames)):
        raise ValueError("movieDimensionsMismatch")
    times = movie.get("presentationSeconds")
    if (not isinstance(times, list) or not 2 <= len(times) <= 200
            or movie.get("encodedFrameCount") != len(times)
            or any(type(t) not in (int, float) or not math.isfinite(t) or t < 0 or t > 6.5 for t in times)
            or any(b <= a for a, b in zip(times, times[1:]))):
        raise ValueError("movieTimestampsInvalid")
    if movie.get("targetFrameRate") != 30 or movie.get("maximumPoolBuffers") != 3:
        raise ValueError("movieLimitsMismatch")
    path = directory / movie["file"]
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 64 * 1024 * 1024:
        raise ValueError("missingOrOversizedMovie")
    data = path.read_bytes()
    if len(data) != movie.get("bytes") or hashlib.sha256(data).hexdigest() != movie.get("sha256"):
        raise ValueError("movieHashMismatch")
    # Check the actual QuickTime container, not only the suffix or metadata.
    position, types = 0, set()
    while position + 8 <= len(data):
        size, kind = struct.unpack(">I4s", data[position:position + 8])
        header = 8
        if size == 1:
            if position + 16 > len(data): raise ValueError("movieContainerMalformed")
            size = struct.unpack(">Q", data[position + 8:position + 16])[0]; header = 16
        elif size == 0:
            size = len(data) - position
        if size < header or position + size > len(data): raise ValueError("movieContainerMalformed")
        types.add(kind); position += size
    if position != len(data) or not {b"ftyp", b"moov", b"mdat"}.issubset(types):
        raise ValueError("movieContainerMalformed")


def verify_case_behavior(flags: list, report: dict, expected_system_accessibility: str = "normal") -> None:
    # This suite is a normal-material baseline. The dedicated reduce-motion
    # scene uses only the existing helper override, never a product guard bypass.
    expected = expected_system_accessibility == "reduced"
    if any(any(value is not expected for value in report[key].values())
           for key in ("systemAccessibilityAtStart", "systemAccessibilityAtEnd")):
        raise ValueError("normalSystemAccessibilityRequired" if not expected else "reducedSystemAccessibilityRequired")
    override = "--visual-reduced-motion" in flags
    reduced = expected or override
    if report.get("helperReducedMotionOverride") is not override:
        raise ValueError("reducedMotionFixtureMismatch")
    if "--visual-timeline" not in flags or report.get("status") == "NOT_RUN":
        return
    events = report.get("events", [])
    arrivals = [e for e in events if e.get("event") == "native_arrival_boundary"]
    started = [e for e in arrivals if e.get("phase") == "decorationStarted"]
    ended = [e for e in arrivals if e.get("phase") == "decorationEnded"]
    sources = [e for e in events if e.get("event") == "synthetic_asset_ready"]
    if "--visual-magnet" in flags and not reduced:
        if (not any(e.get("sourceProvided") is True for e in sources)
                or not any(e.get("mode") == "magnet" for e in started)):
            raise ValueError("magnetWasNotExercised")
        reason = "cancelled" if "--visual-cancel-arrival" in flags else "finished"
        if not any(e.get("mode") == "magnet" and e.get("reason") == reason for e in ended):
            raise ValueError("magnetCompletionNotObserved")
    else:
        if started:
            raise ValueError("unexpectedArrivalDecoration")
        if reduced and (not arrivals or any(e.get("mode") != "none" for e in arrivals)):
            raise ValueError("reducedArrivalPolicyNotObserved")
        if "--visual-missing-source" in flags and not any(e.get("sourceProvided") is False for e in sources):
            raise ValueError("missingSourceFallbackNotExercised")
    if not any(e.get("event") == "native_presentation_boundary" and e.get("phase") == "swallowClose" for e in events):
        raise ValueError("nativeSwallowNotObserved")
    if reduced and not any(e.get("event") == "native_presentation_boundary" and e.get("phase") == "swallowScheduled"
                           and type(e.get("duration")) in (int, float) and 0 < e["duration"] <= 0.08 for e in events):
        raise ValueError("reducedSwallowPolicyNotObserved")


def selected_cases(names: list) -> list:
    registered = cases()
    unknown = set(names) - {name for name, _ in registered}
    if unknown:
        raise ValueError("Unknown registered case: " + ", ".join(sorted(unknown)))
    return [(name, flags) for name, flags in registered if not names or name in set(names)]


def git(repository: Path, *args: str) -> str:
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    return subprocess.check_output(["git", "--no-replace-objects", "-C", str(repository), *args],
                                   env=env, text=True).strip()


def write_index(output: Path, report: dict) -> None:
    cards = []
    for case in report["cases"]:
        name = html.escape(case["name"])
        frames = case.get("capture", {}).get("frames", [])
        movie = case.get("capture", {}).get("movie")
        links = []
        movie_html = ""
        if movie and movie.get("status") == "RECORDED_NATIVE_WINDOWSERVER":
            path = f"scenes/{name}/native-motion.mov"
            movie_html = f'<p>原生录屏：{movie["encodedFrameCount"]} 个实际帧；目标 30Hz ≠ 固定实际帧率。H.264 有损编码，原 PNG 保留。<a href="{path}">下载原 MOV</a> · <a href="scenes/{name}/capture.json">实际 PTS / 完整元数据</a></p><video controls preload="metadata" src="{path}" style="max-width:100%;max-height:650px"></video>'
        elif movie:
            movie_html = f'<p>影片 NOT_RUN：{html.escape(str(movie.get("reason", "unavailable")))}。下方静帧不代表影片已完成。</p>'
        for frame in frames:
            if "file" not in frame:
                continue
            path = f"scenes/{name}/{html.escape(frame['file'])}"
            caption = html.escape(frame["name"])
            links.append(f'<figure><a href="{path}"><img src="{path}" loading="lazy" alt="{caption}"></a><figcaption>{caption} · {frame["pixels"][0]} × {frame["pixels"][1]} 原像素</figcaption></figure>')
        cards.append(f'<section><h2>{name}</h2><p>{html.escape(case["status"])}</p>{movie_html}<div class="frames">{"".join(links)}</div></section>')
    document = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Riftlet 原生视觉证据</title><style>body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;background:#161a1d;color:#e8edf0;margin:32px;line-height:1.6}h1{font-size:28px}h2{font-size:19px}section{padding:24px 0;border-top:1px solid #424950}.frames{display:flex;gap:20px;overflow:auto;align-items:flex-start}figure{margin:0;flex:0 0 auto;max-width:100%}img{display:block;max-width:min(760px,90vw);max-height:600px;object-fit:contain}figcaption{color:#aebbc2}code{overflow-wrap:anywhere}a{color:#b5dce9}</style>
<h1>Riftlet · 本轮原生视觉证据</h1><p>真实 AppKit / WindowServer 自有窗口，全部为隔离的合成素材。页面缩放预览；点击图片查看未缩放原图。每张原图的点/像素尺寸、倍率、捕获方法、时间、源 SHA 与 SHA-256 保存在相邻 capture.json。</p>
<p>物理鼠标、真实系统截图、真实上传、跨应用焦点、正常产品窗口层级：NOT_RUN。动效是按实测时间采样的原生帧，采集开销已包含，不代表固定帧率或产品延迟。视觉是否合格由独立审查作出。</p>'''
    document += f'<p>source: <code>{html.escape(report["source"])}</code><br>checkout: <code>{html.escape(report["checkout"])}</code></p>'
    document += "".join(cards) + "</html>"
    (output / "index.html").write_text(document, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--only-case", action="append", default=[], help="Repeat to select registered cases only")
    parser.add_argument("--expected-system-accessibility", choices=("normal", "reduced"), default="normal")
    args = parser.parse_args()
    try:
        requested_cases = selected_cases(args.only_case)
    except ValueError as error:
        parser.error(str(error))
    repository = Path(__file__).resolve().parents[1]
    source = git(repository, "rev-parse", os.environ.get("RIFTLET_BUILD_HEAD_SHA", "HEAD") + "^{commit}")
    checkout = git(repository, "rev-parse", "HEAD")
    if git(repository, "status", "--porcelain", "--untracked-files=no"):
        parser.error("Native evidence requires a clean tracked source tree.")
    helper = args.helper.resolve(strict=True)
    output = args.output.absolute()
    if output.exists() or output.is_symlink() or output.resolve() != output:
        parser.error("Output must be a new directory without symlink parents.")
    output.mkdir(parents=True)
    (output / "scenes").mkdir()
    report = {"schemaVersion": 1, "source": source, "checkout": checkout,
              "helperSHA256": hashlib.sha256(helper.read_bytes()).hexdigest(),
              "scope": "Synthetic native WindowServer visual evidence; independent review required",
              "expectedSystemAccessibility": args.expected_system_accessibility,
              "physicalInput": "NOT_RUN", "realScreenshot": "NOT_RUN", "realUpload": "NOT_RUN",
              "cases": []}
    if platform.system() != "Darwin":
        report.update(status="NOT_RUN", reason="macOSWindowServerRequired")
        (output / "summary.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 0
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="riftlet-native-visual-process-") as temporary:
        for name, flags in requested_cases:
            destination = output / "scenes" / name
            command = [str(helper), "--visual-clean", "--export-native-evidence", str(destination),
                       "--evidence-source", source, "--evidence-checkout", checkout] + flags
            case = {"name": name, "arguments": flags, "status": "FAIL"}
            process_log = Path(temporary) / (name + ".log")
            with process_log.open("wb") as log:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                try:
                    process.wait(timeout=12 if "--visual-timeline" in flags else 7)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    try:
                        process.wait(timeout=1)
                    except subprocess.TimeoutExpired:
                        process.kill(); process.wait()
                    case["reason"] = "helperTimedOut"
                case["returnCode"] = process.returncode
            try:
                capture = json.loads((destination / "capture.json").read_text(encoding="utf-8"))
                verify_capture(destination, capture, source, checkout)
                verify_case_behavior(flags, capture, args.expected_system_accessibility)
                if process.returncode != 0:
                    raise ValueError("helperExitFailure")
                case["capture"] = capture
                case["status"] = capture["status"]
                if "--visual-timeline" in flags:
                    case["movieStatus"] = capture.get("movie", {}).get("status", "NOT_RUN")
            except (OSError, ValueError, TypeError, KeyError) as error:
                detail = str(error) if isinstance(error, ValueError) else "missingOrMalformedCaptureManifest"
                case.setdefault("reason", detail)
                case["manifestError"] = detail
            if case["status"] == "FAIL":
                # CI runs only this synthetic helper. Preserve actual AppKit/
                # Swift diagnostics instead of replacing them with a missing-
                # manifest message. Logs may contain CI temporary paths and
                # window metadata; no user content or real capture is involved.
                destination.mkdir(exist_ok=True)
                if not destination.is_symlink():
                    with process_log.open("rb") as log:
                        log.seek(0, os.SEEK_END)
                        length = log.tell()
                        log.seek(max(0, length - 2 * 1024 * 1024))
                        diagnostic = log.read()
                    (destination / "helper.log").write_bytes(diagnostic)
                    case["helperLog"] = f"scenes/{name}/helper.log"
                    case["helperLogTruncated"] = length > len(diagnostic)
                    print(f'{name} failure: {case.get("reason", "unknown")}; diagnostics: {case["helperLog"]}', flush=True)
            report["cases"].append(case)
            print(f'{name}: {case["status"]}', flush=True)
    statuses = [case["status"] for case in report["cases"]]
    report["status"] = "FAIL" if "FAIL" in statuses else "NOT_RUN" if "NOT_RUN" in statuses else "CAPTURED_NATIVE_WINDOWSERVER"
    report["imageStatus"] = report["status"]
    movie_cases = [case for case in report["cases"] if "--visual-timeline" in case["arguments"]]
    report["requestedMovieCount"] = len(movie_cases)
    report["recordedMovieCount"] = sum(case.get("movieStatus") == "RECORDED_NATIVE_WINDOWSERVER" for case in movie_cases)
    report["movieStatus"] = ("FAIL" if any(case["status"] == "FAIL" for case in movie_cases)
                             else "RECORDED_NATIVE_WINDOWSERVER" if report["recordedMovieCount"] == len(movie_cases)
                             else "NOT_RUN")
    if report["status"] == "CAPTURED_NATIVE_WINDOWSERVER" and report["movieStatus"] == "NOT_RUN":
        report["status"] = "CAPTURED_NATIVE_IMAGES_MOVIE_NOT_RUN"
    report["durationSeconds"] = round(time.monotonic() - started, 3)
    report["capturedImageCount"] = sum(1 for case in report["cases"] for frame in case.get("capture", {}).get("frames", []) if "file" in frame)
    (output / "summary.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_index(output, report)
    print(f'NATIVE_VISUAL_EVIDENCE_{report["status"]}: {report["capturedImageCount"]} original images; MOVIES {report["recordedMovieCount"]}/{report["requestedMovieCount"]} {report["movieStatus"]}; PHYSICAL_NOT_RUN; REAL_UPLOAD_NOT_RUN')
    return 1 if report["status"] == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main())
