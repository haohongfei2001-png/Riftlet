"""Decode the deliverables and report the exact files a reviewer watched."""

import argparse
import hashlib
import json
import re
import subprocess
from fractions import Fraction
from pathlib import Path

import av
import imageio_ffmpeg


def inspect_video(path, expected_size, seconds):
    with av.open(path) as container:
        assert len(container.streams) == 2, path
        v = container.streams.video[0]
        a = container.streams.audio[0]
        assert (v.width, v.height) == expected_size
        assert v.average_rate == 30 and v.codec_context.name == "h264"
        assert v.codec_context.format.name == "yuv420p"
        assert a.codec_context.name == "aac" and a.codec_context.sample_rate == 48000
        assert a.codec_context.channels == 2
        assert Fraction(v.duration) * v.time_base == seconds
        stamps = [frame.pts * frame.time_base for frame in container.decode(v)]
        assert stamps == [Fraction(i, 30) for i in range(seconds * 30)]
    with av.open(path) as container:
        audio = container.streams.audio[0]
        samples = sum(frame.samples for frame in container.decode(audio))
        # AAC can include a padded final unit of up to 1023 samples.
        assert abs(samples - seconds * 48000) <= 1024
    analysis = subprocess.run(
        [
            imageio_ffmpeg.get_ffmpeg_exe(),
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-vn",
            "-filter:a",
            "ebur128=peak=true",
            "-f",
            "null",
            "-",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stderr.split("Summary:")[-1]
    loudness = float(re.search(r"I:\s+([-\d.]+) LUFS", analysis).group(1))
    peak = float(re.search(r"Peak:\s+([-\d.]+) dBFS", analysis).group(1))
    assert -21 < loudness < -12 and peak < -0.5
    with path.open("rb") as movie:
        header = movie.read(65536)
        assert 0 <= header.find(b"moov") < header.find(b"mdat")
    return {
        "file": str(path.relative_to(ROOT)),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "size_bytes": path.stat().st_size,
        "dimensions": list(expected_size),
        "duration_seconds": seconds,
        "frame_count": len(stamps),
        "fps": 30,
        "video_codec": "H.264",
        "pixel_format": "yuv420p",
        "profile": v.codec_context.profile,
        "fast_start": True,
        "audio_codec": "AAC stereo",
        "sample_rate": 48000,
        "decoded_audio_samples": samples,
        "integrated_lufs": loudness,
        "true_peak_dbtp": peak,
    }


ROOT = Path(__file__).resolve().parents[1]

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("files", type=Path, nargs="+")
    args = parser.parse_args()
    results = []
    for requested in args.files:
        path = requested.resolve()
        with av.open(path) as source:
            vertical = source.streams.video[0].height > source.streams.video[0].width
        results.append(
            inspect_video(path, (1080, 1920) if vertical else (1920, 1080), 15 if vertical else 20)
        )
    print(json.dumps(results, indent=2, ensure_ascii=False))
