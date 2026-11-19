#!/usr/bin/env python3
"""Verify exported files and collect review frames, without opening a GUI."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import wave

import av
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps


HERE = Path(__file__).resolve()
KIT = HERE.parents[3]
REPO = KIT.parents[1]
DEFAULT_WORK = REPO / "build/launch-production/qa"
MONO = "/System/Library/Fonts/Menlo.ttc"
PAPER = "#f4f3ef"
INK = "#122921"


def font(size):
    return ImageFont.truetype(MONO, size) if Path(MONO).is_file() else ImageFont.load_default(size=size)


def sheet(panels, path, columns, box):
    """Each panel carries its own displayed filename or frame time."""
    if not panels:
        return
    w, h = box
    margin, title = 18, 26
    rows = math.ceil(len(panels) / columns)
    canvas = Image.new("RGB", (columns * (w + margin) + margin, rows * (h + title + margin) + margin), PAPER)
    draw = ImageDraw.Draw(canvas)
    for i, (label, frame) in enumerate(panels):
        x = margin + i % columns * (w + margin)
        y = margin + i // columns * (h + title + margin)
        resize = ImageOps.contain(frame, (w, h), Image.Resampling.LANCZOS)
        canvas.paste(resize, (x + (w - resize.width) // 2, y + (h - resize.height) // 2))
        draw.text((x, y + h + 4), label, fill=INK, font=font(14))
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path, quality=92, optimize=True)


def read_image(path):
    with Image.open(path) as f:
        f.load()
        return f.convert("RGB")


def pts_sample(pic):
    return np.asarray(pic.resize((96, 54), Image.Resampling.BILINEAR), dtype=np.int16)


def frame_diff(a, b):
    return float(np.mean(np.abs(a - b)))


def digest(path):
    state = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            state.update(chunk)
    return state.hexdigest()


def score_alignment(wav_path, decoded):
    with wave.open(str(wav_path), "rb") as wav:
        if wav.getnchannels() != 1 or wav.getsampwidth() != 2 or wav.getframerate() != 48000:
            raise ValueError(f"Expected a mono 48 kHz 16-bit edit reference in {wav_path}")
        original = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float32) / 32768.0
    length = min(len(original), len(decoded)) // 480 * 480
    envelopes = []
    for signal in (original, decoded):
        windows = signal[:length].reshape(-1, 480)
        envelopes.append(np.sqrt(np.mean(windows ** 2, axis=1)))
    best = (-1.0, 0)
    for lag in range(-20, 21):
        a, b = envelopes
        if lag < 0:
            a, b = a[-lag:], b[:lag]
        elif lag > 0:
            a, b = a[:-lag], b[lag:]
        similarity = float(np.corrcoef(a, b)[0, 1])
        if similarity > best[0]:
            best = (similarity, lag)
    return dict(reference=wav_path.name, referenceSHA256=digest(wav_path),
                correlation=round(best[0], 6), audioLagMs=best[1] * 10)


def check_video(path, work, player, master, scores):
    frame_dir = work / "player" / path.stem
    frame_dir.mkdir(parents=True, exist_ok=True)
    if list(frame_dir.glob("*.jpg")):
        raise ValueError(f"Use a fresh --out directory for a new playback of {path.name}")
    with av.open(str(path)) as media:
        if len(media.streams.video) != 1:
            raise ValueError(f"Expected a single video stream in {path.name}")
        video = media.streams.video[0]
        size = [video.width, video.height]
        codec = video.codec_context.name
        fps = float(video.average_rate)
        if len(media.streams.audio) != 1:
            raise ValueError(f"Expected the sound-effects track in {path.name}")
        sound = media.streams.audio[0]
        audio_codec = sound.codec_context.name
        sample_rate = sound.codec_context.sample_rate
    played = subprocess.run([str(player), str(path), str(frame_dir)], capture_output=True, text=True)
    receipt_path = frame_dir / "player.json"
    if not receipt_path.exists():
        raise RuntimeError(f"AVPlayer did not issue a receipt for {path.name}: {played.stderr[-1000:]}")
    receipt = json.loads(receipt_path.read_text())
    if played.returncode or not receipt.get("completed"):
        raise RuntimeError(f"AVPlayer failed to play {path.name}: {receipt}")
    duration = receipt["duration"]
    with av.open(str(path)) as media:
        peak, audio_frames, active, audio_samples = 0.0, 0, 0, 0
        decoded = []
        start = None
        end = None
        first_signal = None
        last_signal = None
        for a in media.decode(audio=0):
            arr = a.to_ndarray()
            normalized = arr.astype(np.float32)
            if arr.dtype.kind in "iu":
                normalized /= max(abs(np.iinfo(arr.dtype).min), np.iinfo(arr.dtype).max)
            decoded.append(normalized[0])
            level = float(np.max(np.abs(normalized)))
            stamp = float(a.pts * a.time_base)
            if start is None:
                start = stamp
            end = stamp + a.samples / a.sample_rate
            audio_frames += 1
            audio_samples += a.samples
            peak = max(peak, level)
            if level > 0.002:
                active += 1
                first_signal = stamp if first_signal is None else first_signal
                last_signal = end
    portrait = not master
    lo, hi = (30, 45) if master else (15, 25)
    if master:
        size_ok = size[0] >= 1920 and size[1] >= 1080 and size[0] * 9 == size[1] * 16
    else:
        size_ok = size == [1080, 1920]
    ok = (size_ok and codec == "h264" and lo - 0.05 <= duration <= hi + 0.05
          and active > 0 and audio_samples > 0
          and abs(start) < 0.25 and abs(end - duration) < 0.25)
    alignment = None
    score_key = "master" if master else {"01": "value", "02": "controls", "03": "pair"}.get(path.stem[:2])
    if scores and score_key:
        reference = scores / (score_key + ".wav")
        alignment = score_alignment(reference, np.concatenate(decoded))
        ok = ok and alignment["correlation"] >= 0.97 and abs(alignment["audioLagMs"]) <= 30
    panels = []
    for frame_path in sorted(frame_dir.glob("[0-9]*.jpg")):
        sec = int(frame_path.stem)
        panels.append((f"{sec // 60:02}:{sec % 60:02}", read_image(frame_path)))
    panels.append((f"last  {receipt['lastDisplayTime']:.2f}s", read_image(frame_dir / "last.jpg")))
    sheet(panels, work / "sheets" / (path.stem + ".jpg"), 6 if portrait else 5,
          (170, 302) if portrait else (290, 164))
    return dict(passed=ok, size=size, frameRate=round(fps, 4), codec=codec, duration=round(duration, 4),
                player=receipt, audio=dict(codec=audio_codec, sampleRate=sample_rate, frames=audio_frames,
                samples=audio_samples, peak=round(peak, 5), signalFrames=active, firstSignal=first_signal,
                lastSignal=last_signal, streamStart=start, streamEnd=end, editScore=alignment))


def check_gif(path, work):
    results, durations, totals = [], [], []
    milestones = []
    diff = []
    scans = []
    size = None
    loop = None
    n = 0
    for cycle in range(2):
        hashes, delays = [], []
        last = None
        first = None
        with Image.open(path) as f:
            if f.format != "GIF":
                raise ValueError(f"Not a GIF: {path.name}")
            size, loop, n = f.size, f.info.get("loop"), f.n_frames
            indices = sorted(set([0, n // 4, n // 2, (3 * n) // 4, n - 1]))
            for i in range(n):
                f.seek(i)
                rgb = f.convert("RGB")
                hashes.append(hashlib.sha256(rgb.tobytes()).hexdigest())
                delays.append(f.info.get("duration", 0))
                if not cycle:
                    now = pts_sample(rgb)
                    if last is None:
                        first = now
                        first_full = rgb.copy()
                    else:
                        diff.append(frame_diff(now, last))
                    last = now
                    if i in indices:
                        milestones.append((f"f{i:03}   {sum(delays[:-1]) / 1000:.2f}s", rgb.copy()))
        if not cycle:
            seam = frame_diff(first, last)
            last_full = rgb.copy()
        scans.append(hashlib.sha256("".join(hashes).encode()).hexdigest())
        results.append(len(set(hashes)))
        durations.append(delays)
        totals.append(sum(delays))
    sheet(milestones, work / "sheets" / (path.stem + "-loop.jpg"), len(milestones), (240, 172))
    sheet([("end of cycle", last_full), ("start of next cycle", first_full)],
          work / "sheets" / (path.stem + "-seam.jpg"), 2, (450, 300))
    ok = (loop == 0 and n >= 2 and results[0] > 1 and size[0] >= 720 and scans[0] == scans[1]
          and durations[0] == durations[1] and min(durations[0]) > 0)
    return dict(passed=ok, size=list(size), framesPerCycle=n, loop=loop, cyclesDecoded=2,
                uniqueFrames=results[0], minFrameMs=min(durations[0]), maxFrameMs=max(durations[0]),
                durationsMs=totals, identicalCycles=scans[0] == scans[1],
                decodedCycleDigest=scans[0], meanPixelDeltaAtLoop=round(seam, 3),
                largestAdjacentMeanDelta=round(max(diff), 3))


def check_png(path):
    with Image.open(path) as f:
        if f.format != "PNG":
            raise ValueError(f"Not a PNG: {path.name}")
        f.verify()
    pic = read_image(path)
    varied = any(high > low for low, high in pic.getextrema())
    return dict(passed=varied, size=list(pic.size), fullDecode=True), pic


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kit", type=Path, default=KIT)
    parser.add_argument("--out", type=Path, default=DEFAULT_WORK)
    parser.add_argument("--player", type=Path, help="already compiled macOS AVPlayer checker")
    parser.add_argument("--scores", type=Path, help="compare exported sound timing to original 48 kHz edit scores")
    parser.add_argument("--groups", nargs="+", choices=["video", "gif", "images", "covers"],
                        default=["video", "gif", "images", "covers"], help="audit selected deliverable groups")
    args = parser.parse_args()
    kit = args.kit.resolve()
    work = args.out.resolve()
    work.mkdir(parents=True, exist_ok=True)
    if (work / "report.json").exists():
        raise SystemExit("Existing evidence at --out. Choose a new QA directory.")
    player = args.player.resolve() if args.player else work / "player-bin"
    if "video" in args.groups and not args.player:
        with tempfile.TemporaryDirectory(prefix="riftlet-verify-swift-") as cache:
            subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-suppress-warnings", "-module-cache-path",
                            cache, str(HERE.with_name("Player.swift")), "-o", str(player)], check=True)
    outputs = {}
    expected = {"video/master": 2, "video/shorts": 3, "gif": 4, "images": 6, "covers": 3}
    expected = {group: count for group, count in expected.items() if group.split("/")[0] in args.groups}
    counts = {}
    short_edits = {}
    for kind, count in expected.items():
        ext = "mp4" if kind.startswith("video/") else "gif" if kind == "gif" else "png"
        files = sorted((kit / kind).glob(f"*.{ext}"))
        counts[kind] = len(files)
        pictures = []
        for path in files:
            relative = path.relative_to(kit).as_posix()
            if kind == "video/shorts":
                locale = next((suffix for suffix in ("zh-CN", "en-US") if path.stem.endswith("-" + suffix)), "")
                edit = path.stem.removesuffix("-" + locale) if locale else path.stem
                short_edits.setdefault(edit, []).append(locale or "unspecified")
            if kind.startswith("video/"):
                receipt = check_video(path, work, player, kind == "video/master", args.scores)
            elif kind == "gif":
                receipt = check_gif(path, work)
            else:
                receipt, preview = check_png(path)
                pictures.append((path.stem, preview))
            outputs[relative] = dict(sha256=digest(path), **receipt)
            print(relative, "PASS" if receipt["passed"] else "FAIL", flush=True)
        if pictures:
            sheet(pictures, work / "sheets" / (kind + ".jpg"), 2, (600, 370))
        observed = len(short_edits) if kind == "video/shorts" else counts[kind]
        if observed != count:
            print(f"Expected {count} deliverables under {kind}, found {observed}", flush=True)
    logical_counts = dict(counts)
    if short_edits:
        logical_counts["video/shorts"] = len(short_edits)
    valid_counts = logical_counts == expected
    passed = valid_counts and all(v["passed"] for v in outputs.values())
    report = dict(passed=passed, counts=counts, shortEdits=short_edits, files=outputs)
    (work / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
