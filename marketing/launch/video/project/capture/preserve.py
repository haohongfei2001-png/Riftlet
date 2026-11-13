"""Turn one continuous successful take into a compact, auditable source.

Usage: python preserve.py TAKE_DIRECTORY LAUNCH_DIRECTORY
Run after record.py. ffmpeg, imageio-ffmpeg and Pillow are
required. Each local system screenshot retains its original metadata. Each Git-friendly
window photograph retains the exact decoded RGBA samples but omits EXIF/XMP,
ICC display metadata and file-system attributes.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from imageio_ffmpeg import get_ffmpeg_exe
from PIL import Image


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixel_digest(tool, movie):
    with subprocess.Popen([tool, "-v", "error", "-i", movie, "-an", "-f", "rawvideo",
                           "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE) as proc:
        digest = hashlib.sha256()
        for block in iter(lambda: proc.stdout.read(1048576), b""):
            digest.update(block)
        if proc.wait():
            raise RuntimeError(f"Decoder failed for {movie}")
    return digest.hexdigest()


def copy_identical(source, destination):
    if destination.exists():
        if sha(source) != sha(destination):
            raise RuntimeError(f"A different take is already stored at {destination}")
    else:
        subprocess.run(["/bin/cp", "-p", source, destination], check=True)


def preserve():
    take, kit = [Path(arg).resolve() for arg in sys.argv[1:]]
    raw, share = kit / "source/raw", kit / "source/edit"
    raw.mkdir(parents=True, exist_ok=True)
    share.mkdir(parents=True, exist_ok=True)
    results = json.loads((take / "record.json").read_text())
    assert results["events"][-1]["name"] == "recording-complete"
    for name in ["tray-native.mov", "samples.json", "record.json"]:
        copy_identical(take / name, raw / name)
    tool = get_ffmpeg_exe()
    master = raw / "tray-native.mov"
    rgb = share / "tray-lossless.mp4"
    if not rgb.exists():
        subprocess.run([tool, "-v", "error", "-i", master, "-map_metadata", "-1", "-an",
                        "-c:v", "libx264rgb", "-crf", "0", "-preset", "medium", "-g", "120",
                        "-movflags", "+faststart", rgb], check=True)
    raw_hash, git_hash = (pixel_digest(tool, m) for m in (master, rgb))
    if raw_hash != git_hash:
        raise ValueError("RGB frame values changed in transcode")
    results["movie"]["decodedAllFramesRGBSHA256"] = raw_hash
    results["movie"]["repositoryFile"] = "source/edit/tray-lossless.mp4"
    results["movie"]["repositoryFileSHA256"] = sha(rgb)
    results["movie"]["repositoryBytes"] = rgb.stat().st_size
    for picture in results["sourcePhotos"]:
        key = picture["name"]
        original = raw / ("meridian-" + key + "-window.png")
        copy_identical(take / (key + "-window.png"), original)
        if sha(original) != picture["privateCopySHA256"]:
            raise RuntimeError("Window screenshot differs from the file in the collection")
        with Image.open(original) as native:
            if native.mode != "RGBA":
                raise ValueError("Expected an RGBA screenshot of the controlled native window")
            pixels = Image.frombytes("RGBA", native.size, native.tobytes())
        path = share / (key + "-window.png")
        pixels.save(path, optimize=True)
        with Image.open(path) as check:
            assert check.mode == "RGBA" and not check.info and check.tobytes() == pixels.tobytes()
        picture.update(repositoryFile="source/edit/" + path.name, repositorySHA256=sha(path),
                       repositoryRGBASHA256=hashlib.sha256(pixels.tobytes()).hexdigest(),
                       transparentPixels=pixels.getchannel("A").histogram()[0],
                       repositoryColor="Original RGBA samples including window corner transparency; display ICC, EXIF and XMP removed.")
    # Every successful launch uses a distinct source root. Event times are
    # relative and the public receipt omits home paths, PIDs and user metadata.
    del results["uuid"]
    results["captureScope"] = {
        "desktop": "Local macOS WindowServer, 1920 × 1080 points, Retina 2×",
        "sourceAllowlist": "This take's paper window plus floating layers of just the verified release process.",
        "audio": "none", "systemCursor": "excluded", "browser": "not opened by this capture",
        "adapter": "UUID settings-review mode with actual collector and native UI; Web input disabled",
        "messages": "no send", "finalQueue": "two original image hashes, pending, zero operations"}
    data = json.dumps(results, indent=2, ensure_ascii=False) + "\n"
    (kit / "evidence/native-capture.json").write_text(data)


if __name__ == "__main__":
    preserve()
