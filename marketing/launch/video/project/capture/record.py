"""Record the released native app, targeting only fresh isolated processes and files.

Usage: python record.py VERIFIED_RELEASE_APP WORK_DIR PLATE_DIR
Compile Stage.swift and Take.swift into WORK_DIR as stage and take first.
The output is a new capture subdirectory inside WORK_DIR. Reruns never
overwrite an earlier take. Uses imageio-ffmpeg and macOS Accessibility /
Screen Recording. No Chromium, AppleScript, permission requests or network.
"""
from __future__ import annotations

import hashlib
import json
import plistlib
import sqlite3
import subprocess
import sys
import time
import uuid
from pathlib import Path

from imageio_ffmpeg import get_ffmpeg_exe


def save(path, obj):
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")


def wait(callback, seconds=12):
    start = time.monotonic()
    while time.monotonic() - start < seconds:
        value = callback()
        if value:
            return value
        time.sleep(0.10)
    raise RuntimeError(f"Timeout waiting for {callback.__name__}")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run():
    app, work, plates = [Path(x).resolve() for x in sys.argv[1:]]
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert (info["CFBundleShortVersionString"], info["CFBundleVersion"]) == ("0.3.5", "20")
    exe = app / "Contents/MacOS" / info["CFBundleExecutable"]
    take = work / "take"
    ident = str(uuid.uuid4())
    local = work / ident
    local.mkdir()
    root = Path.home() / "Library/Application Support" / ("Riftlet-Settings-Review-" + ident)
    root.mkdir(mode=0o700, exist_ok=False)
    (root / "settings-review-identity.txt").write_text(ident + "\n")
    # Ordinary user-selectable values in the fresh UUID's independent preference.
    save(root / "rift-configuration.json", {"desktopForm": "tray", "placement": "rightMiddle",
                                           "placementSource": "user", "outerInset": 18,
                                           "trayTheme": "system", "trayOcclusion": 0})
    # Suppress only the one-time guide in the UUID review suite, before the
    # camera runs. This operation cannot address the production domain.
    domain = "com.riftlet.settings-review." + ident
    first_key = "Riftlet.firstUse.presented.v1." + root.name
    subprocess.run(["/usr/bin/defaults", "write", domain, first_key, "-bool", "true"], check=True)

    receipt = {"version": "0.3.5 (20)", "tag": "v0.3.5-beta.1", "uuid": ident,
               "releaseExecutableSHA256": digest(exe), "events": [], "sourcePhotos": [],
               "parameters": {"form": "tray", "placement": "rightMiddle", "theme": "system",
                              "outerInset": 18, "trayOcclusion": 0, "captureEntry": True}}
    children = []

    def rows():
        path = root / "queue.sqlite"
        if not path.exists():
            return []
        with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True) as db:
            return db.execute("SELECT id,file_name,image_json,status FROM assets ORDER BY sequence").fetchall()

    def buttons():
        p = subprocess.run([str(take), "control", str(rift.pid), "list"], capture_output=True, check=True)
        return json.loads(p.stdout)

    def has(labels, prefix):
        return any(any(s.startswith(prefix) for s in row) for row in labels)

    def event(name, **extra):
        record = {"name": name, "time": round(time.monotonic() - t0, 4), **extra}
        receipt["events"].append(record)
        save(local / "record.json", receipt)
        print(record, flush=True)

    def at(seconds):
        delay = t0 + seconds - time.monotonic()
        if delay > 0:
            time.sleep(delay)

    def photo(key):
        assert rift.poll() is None and stage.poll() is None and stage_meta["owner"] == stage.pid
        filename = "Meridian Inlet - " + ("Low" if key == "low" else "High") + " water.png"
        path = root / "fixture-source" / filename
        assert not path.exists()
        event(key + "-screenshot-command")
        subprocess.run(["/usr/sbin/screencapture", "-x", "-o", "-l" + str(stage_meta["windows"][key]), str(path)], check=True)
        original = digest(path)
        tag = "com.apple.metadata:kMDItemIsScreenCapture"
        attr = subprocess.run(["/usr/bin/xattr", "-px", tag, path], capture_output=True)
        apple_marker = attr.returncode == 0 and plistlib.loads(bytes.fromhex(attr.stdout.decode())) is True
        if not apple_marker:
            raise RuntimeError(f"System screenshot marker missing from {key}; the take is incomplete")
        archived = local / (key + "-window.png")
        subprocess.run(["/bin/cp", "-p", path, archived], check=True)
        archived_tag = subprocess.check_output(["/usr/bin/xattr", "-px", tag, archived], text=True)
        assert plistlib.loads(bytes.fromhex(archived_tag)) is True
        event(key + "-system-image-saved", nativeScreenshotMarker=apple_marker)
        def matching_row():
            for row in rows():
                meta = json.loads(row[2])
                if meta.get("sha256") == original:
                    return row
            return None
        record = wait(matching_row)
        media_path = root / "media" / record[1]
        assert digest(media_path) == original
        meta = json.loads(record[2])
        receipt["sourcePhotos"].append({"name": key, "windowPixels": [meta["pixelWidth"], meta["pixelHeight"]],
                                        "sha256": original, "privateCopySHA256": digest(media_path),
                                        "deviceSource": "/usr/sbin/screencapture -x -o -l <owned plate window>",
                                        "systemMarkerOriginallyPresent": apple_marker})
        event(key + "-collector-observed", count=len(rows()), status=record[3])

    log = (local / "process.log").open("wb")
    try:
        stage_file = local / "stage.json"
        stage = subprocess.Popen([work / "stage", plates / "low.png", plates / "high.png", stage_file],
                                 stdout=log, stderr=log)
        children.append(stage)
        wait(lambda: stage_file.exists())
        stage_meta = json.loads(stage_file.read_text())
        assert stage_meta["owner"] == stage.pid and stage.poll() is None
        rift = subprocess.Popen([exe, "--settings-review", ident], stdout=log, stderr=log)
        children.append(rift)
        wait(lambda: has(buttons(), "展开截图方式"))
        assert not rows()
        fps = 30
        size = [int(v * stage_meta["scale"]) for v in stage_meta["crop"][2:]]
        duration = 24
        timing = local / "samples.json"
        rec = subprocess.Popen([take, "record", str(rift.pid), stage_file, timing, str(duration)],
                               stdout=subprocess.PIPE, stderr=log)
        children.append(rec)
        movie = local / "tray-native.mov"
        enc = subprocess.Popen([get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-f", "rawvideo",
                                "-pixel_format", "bgra", "-s", f"{size[0]}x{size[1]}", "-framerate", str(fps),
                                "-i", "-", "-an", "-c:v", "qtrle", "-pix_fmt", "rgb24", movie],
                               stdin=rec.stdout, stdout=log, stderr=log)
        rec.stdout.close()
        children.append(enc)
        wait(lambda: Path(str(timing) + ".start").exists())
        t0 = json.loads(Path(str(timing) + ".start").read_text())["start"]
        event("empty-tray", buttons=buttons())
        at(2)
        photo("low")
        at(7)
        photo("high")
        at(12)
        event("open-menu-request")
        subprocess.run([take, "control", str(rift.pid), "展开截图方式"], check=True, stdout=log)
        wait(lambda: has(buttons(), "默认截图"), 2)
        event("open-menu-observed", buttons=buttons())
        at(15.6)
        if has(buttons(), "展开截图方式"):
            event("menu-already-closed-observed", method="native dismissal before our event; input not attributed")
        else:
            event("close-menu-request")
            result = subprocess.run([take, "control", str(rift.pid), "escape"], capture_output=True)
            try:
                wait(lambda: has(buttons(), "展开截图方式"), 1.25)
                event("close-menu-observed", escapePosted=result.returncode == 0)
            except RuntimeError:
                event("menu-remained-open-after-targeted-escape")
        at(18.7)
        before = buttons()
        target = next((name for row in before for name in row if name.startswith("截图 1，")), None)
        assert target is not None
        event("thumbnail-press-request", originalLabel=target)
        cmd = subprocess.run([take, "control", str(rift.pid), "mouse:"+target], capture_output=True)
        if cmd.returncode == 0:
            event("thumbnail-targeted-down-up-posted", geometry=json.loads(cmd.stdout), buttons=buttons())
        else:
            event("thumbnail-targeted-down-up-unavailable", buttons=buttons())
        at(20)
        # An independent press on the other image supplies an unambiguous action
        # receipt even if the OS does not route off-cursor mouse events.
        before = buttons()
        other = next(name for row in before for name in row if name.startswith("截图 2，"))
        event("second-thumbnail-accessibility-request", originalLabel=other)
        subprocess.run([take, "control", str(rift.pid), other], check=True, stdout=log)
        event("second-thumbnail-accessibility-returned", buttons=buttons())
        at(21)
        event("after-press", buttons=buttons(), assets=[r[3] for r in rows()])
        with sqlite3.connect((root/"queue.sqlite").as_uri()+"?mode=ro", uri=True) as db:
            receipt["operations"] = db.execute("SELECT count(*) FROM operations").fetchone()[0]
        assert len(rows()) == 2 and receipt["operations"] == 0
        assert rec.wait(timeout=35) == 0
        assert enc.wait(timeout=10) == 0
        samples = json.loads(timing.read_text())
        times = samples["times"]
        deltas = sorted(b-a for a,b in zip(times, times[1:]))
        receipt["movie"] = {"filename": movie.name, "sha256": digest(movie), "width": size[0],
                            "height": size[1], "frames": len(times), "timelineFps": fps,
                            "actualCaptureSeconds": times[-1]-times[0],
                            "medianFrameInterval": deltas[len(deltas)//2], "maxFrameInterval": max(deltas),
                            "uniqueCapture": "one fresh PID-window-array sample per stored video frame; lossless RGB"}
        event("recording-complete")
        print("READY", local, flush=True)
    finally:
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
        save(local / "record.json", receipt)
        log.close()


if __name__ == "__main__":
    run()
