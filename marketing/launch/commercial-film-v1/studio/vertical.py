"""Portrait edit of the One Click master, rendered from the same desktop plates.

Install next to film.py. Use --project when running outside the campaign folder.
Without --render, this exports an optional editorial contact sheet.
"""

import argparse
import subprocess
import sys
import tempfile
import wave
from functools import lru_cache
from pathlib import Path

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw

SIZE = (1080, 1920)
FPS = 30
CUTS = ((0, 6), (10, 15.5), (16.5, 20))
PANEL = (48, 558, 1032, 1402)
PAPER, INK, GREEN = "#F7F7EE", "#173B33", "#116B5D"


def master_time(portrait_time):
    for start, end in CUTS:
        if portrait_time < end - start:
            return portrait_time + start
        portrait_time -= end - start
    return CUTS[-1][1]


def splice_score(source, target):
    """Two room-tail crossfades before the cuts. Incoming beats stay at exact sample times."""
    with wave.open(str(source), "rb") as fp:
        rate, depth, channels = fp.getframerate(), fp.getsampwidth(), fp.getnchannels()
        if (rate, depth, channels) != (48000, 3, 2):
            raise ValueError("Expected the original stereo 48 kHz 24-bit master")
        raw = np.frombuffer(fp.readframes(fp.getnframes()), dtype=np.uint8).reshape(-1, 3)
    samples = (
        (raw[:, 0].astype(np.int32) << 8)
        + (raw[:, 1].astype(np.int32) << 16)
        + (raw[:, 2].astype(np.int32) << 24)
    ) >> 8
    samples = samples.reshape(-1, 2)
    out = []
    ramp = np.linspace(0, np.pi / 2, round(0.035 * rate))[:, None]
    for i, (start, end) in enumerate(CUTS):
        segment = samples[round(rate * start) : round(rate * end)].copy()
        if i:
            incoming_room = samples[round(start * rate) - len(ramp) : round(start * rate)]
            out[-1][-len(ramp) :] = np.rint(
                out[-1][-len(ramp) :] * np.cos(ramp) ** 2 + incoming_room * np.sin(ramp) ** 2
            )
        out.append(segment)
    audio = np.concatenate(out).astype("<i4").reshape(-1)
    with wave.open(str(target), "wb") as fp:
        fp.setframerate(rate)
        fp.setnchannels(channels)
        fp.setsampwidth(depth)
        fp.writeframes(audio.view("u1").reshape(-1, 4)[:, :3].copy().tobytes())


class Portrait:
    def __init__(self, lang, film):
        self.f = film
        self.lang = lang
        self.cn = lang == "zh-CN"
        self.master = film.Spot(lang)
        self.caption_face = "zh" if self.cn else "medium"
        self.display_face = "song" if self.cn else "serif"
        self.accent_face = "song" if self.cn else "italic"

    def tr(self, zh, en):
        return zh if self.cn else en

    def write(self, im, x, y, value, size, face, color, width=None, anchor="lt"):
        self.f.txt(im, x, y, value, size, face, color, anchor=anchor, limit=width)

    def viewport(self, t):
        # The first and final shots keep the existing orange image and its text.
        # A match cut between two real coordinates of the single master desktop
        # gives the empty physical edge seven frames before its thumbnail enters.
        if t < 1.30:
            keys = [
                (0, (1095, 428, 797)),
                (0.28, (1095, 428, 797)),
                (1.18, (989, 458, 502)),
                (1.30, (989, 458, 502)),
            ]
        elif t < 2.94:
            keys = [(1.30, (380, 386, 733)), (2.94, (374, 391, 688))]
        else:
            # A detail cut makes the existing and added file readable on a phone.
            # For the long English question, follow the second clause to its caret,
            # then restore the full composition and the untouched send button.
            writing_end = (985, 548, 490) if self.cn else (1103, 454, 752)
            keys = [
                (2.94, (1471, 412, 308)),
                (4.43, (1474, 410, 298)),
                (4.82, (1178, 453, 875)),
                (5.54, (985, 548, 490)),
                (10, (985, 548, 490)),
                (11.70, (985, 548, 490)),
                (14.46, writing_end),
                (15.49, (1094, 443, 768)),
                (16.50, (1094, 443, 768)),
                (17.05, (1094, 443, 785)),
            ]
        cx, cy, w = self.f.track(t, keys)
        pw, ph = PANEL[2] - PANEL[0], PANEL[3] - PANEL[1]
        h = w * ph / pw
        left = max(0, min(self.f.W - w, cx - w / 2))
        top = max(0, min(self.f.H - h, cy - h / 2))
        return tuple(v * self.f.S for v in (left, top, left + w, top + h))

    @lru_cache(maxsize=2)
    def mask(self, size):
        return self.f.rounded(size, 29)

    def heading(self, t):
        if t < 5.27:
            return self.tr(
                ("刚截的图，", "点一下就进 ChatGPT。"),
                ("Just took a screenshot?", "One click adds it", "to ChatGPT."),
            )
        if t < 10.93:
            return self.tr(("原来的草稿，", "多了刚截的图。"), ("Same draft.", "New screenshot."))
        if t < 14.63:
            return self.tr(("原来的问题，", "接着写。"), ("Your question stays.", "Keep writing."))
        return self.tr(("不用找文件，", "也不用拖图。"), ("No file hunting.", "No dragging."))

    def direction(self, t):
        if t < 1.30:
            return self.tr(
                ("周报写到一半", "还想给草稿补一张趋势图。"),
                ("Writing a weekly report", "The draft needs one more chart."),
            )
        if t < 2.94:
            return self.tr(
                ("Mac 系统截屏", "照平常的方式，截下趋势图。"),
                ("Mac screenshot", "Capture the chart as usual."),
            )
        if t < 4.80:
            return self.tr(
                ("Riftlet 屏幕边缘", "点一下刚出现的缩略图。"),
                ("At the edge of the screen", "Click the thumbnail that just appeared."),
            )
        if t < 10.93:
            return self.tr(
                ("当前的 ChatGPT 草稿", "旧附件和原来的问题都还在。"),
                ("In the current ChatGPT draft", "The earlier attachment and question stay."),
            )
        if t < 14.63:
            return self.tr(
                ("接着刚才的问题", "想补一句，就在这里继续写。"),
                ("Back in the same draft", "Keep typing. You decide when to send."),
            )
        return self.tr(
            ("给当前草稿补图", "什么时候发送，由你决定。"),
            ("Adding an image to the draft", "Send it when you’re ready."),
        )

    @lru_cache(maxsize=14)
    def layout(self, heading, direction):
        im = Image.new("RGB", SIZE, PAPER)
        d = ImageDraw.Draw(im)
        mark = self.f.logo(65)
        im.paste(mark, (59, 96), mark)
        self.write(im, 141, 92, "Riftlet", 69, "serif", INK)
        self.write(
            im,
            1006,
            123,
            self.tr("Mac 上的 Chrome", "Chrome on Mac"),
            29,
            self.caption_face,
            GREEN,
            anchor="rm",
        )
        d.line([(56, 199), (1023, 199)], fill="#C8D3C4", width=2)
        if len(heading) == 3:
            # The English opening is broken on natural phrases and leaves ChatGPT intact.
            positions, sizes = (253, 340, 426), (82, 91, 91)
        else:
            positions, sizes = (266, 391), (107, 110) if self.cn else (101, 111)
        for i, (row, y, size) in enumerate(zip(heading, positions, sizes)):
            self.write(
                im,
                55,
                y,
                row,
                size,
                self.display_face if i == 0 else self.accent_face,
                INK if i == 0 else GREEN,
                963,
            )
        label, instruction = direction
        d.line([(59, 1481), (1020, 1481)], fill="#C8D3C4", width=2)
        self.write(im, 60, 1525, label, 33, self.caption_face, GREEN, 952)
        self.write(im, 55, 1599, instruction, 59, self.display_face, INK, 959)
        self.write(
            im, 61, 1790, self.tr("交互示意", "Illustrated interaction"), 26, self.caption_face, "#4F6C5F"
        )
        self.write(im, 1015, 1790, "riftlet.com", 29, "medium", GREEN, anchor="rt")
        return im

    @lru_cache(maxsize=1)
    def end_base(self):
        im = Image.new("RGB", SIZE, "#163C34")
        self.write(
            im,
            64,
            316,
            self.tr("截图之后，", "After the screenshot,"),
            62,
            self.display_face,
            "#D1E1D0",
            945,
        )
        mark = self.f.logo(137)
        im.paste(mark, (61, 503), mark)
        self.write(im, 230, 481, "Riftlet", 189, "serif", "#FAF7EC", 780)
        rows = self.tr(
            ("刚截的图，", "点一下就进 ChatGPT。"),
            ("Just took a screenshot?", "One click adds it to ChatGPT."),
        )
        for i, row in enumerate(rows):
            self.write(
                im,
                62,
                781 + i * 100,
                row,
                86,
                self.display_face if i == 0 else self.accent_face,
                "#CCEBD2",
                949,
            )
        self.write(
            im, 63, 1550, self.tr("下载 Mac 版", "Download for Mac"), 38, self.caption_face, "#D1E1D0", 948
        )
        self.write(im, 59, 1642, "riftlet.com", 100, "serif", "#FBF8EC", 949)
        return im

    def ending(self, t):
        im = self.end_base().copy()
        d = ImageDraw.Draw(im)
        points = [(-190, 1233), (202, 1177), (536, 1334), (835, 1168), (1160, 1108)]
        progress = self.f.ease(t, 16.78, 18.0)
        for i, (first, next_point) in enumerate(zip(points, points[1:])):
            u = max(0, min(1, progress * 4 - i))
            if u > 0:
                endpoint = tuple(round((1 - u) * a + u * b) for a, b in zip(first, next_point))
                d.line([first, endpoint], fill="#628B76", width=4)
        if progress >= 0.5:
            d.ellipse((525, 1323, 547, 1345), fill="#E68B64")
        return im

    def frame(self, v):
        t = master_time(v)
        if t >= 17.05:
            return self.ending(t)
        im = self.layout(self.heading(t), self.direction(t)).copy()
        scene = self.master.screen(t)
        x, y, r, b = PANEL
        view = scene.resize((r - x, b - y), Image.Resampling.BICUBIC, box=self.viewport(t))
        im.paste(view, (x, y), self.mask(view.size))
        if t >= 16.78:
            end = self.ending(t)
            u = self.f.ease(t, 16.78, 17.05)
            x = round(1380 * (1 - u)) - 300
            wipe = Image.new("L", SIZE)
            ImageDraw.Draw(wipe).polygon([(x, 0), (1080, 0), SIZE, (x + 300, 1920)], fill=255)
            im = Image.composite(end, im, wipe)
        return im


def render(spot, out, project):
    out.mkdir(parents=True, exist_ok=True)
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    final = out / "vertical.mp4"
    temp = out / "vertical.partial.mp4"
    with tempfile.TemporaryDirectory(prefix="riftlet-vertical-") as scratch:
        audio = Path(scratch) / "edit.wav"
        splice_score(project / "film" / "score.wav", audio)
        call = [
            ffmpeg,
            "-loglevel",
            "error",
            "-y",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-s",
            "1080x1920",
            "-r",
            str(FPS),
            "-i",
            "pipe:0",
            "-i",
            str(audio),
            "-vf",
            "scale=out_color_matrix=bt709:out_range=tv",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-profile:v",
            "high",
            "-crf",
            "16",
            "-preset",
            "fast",
            "-threads",
            "3",
            "-colorspace",
            "bt709",
            "-color_trc",
            "bt709",
            "-color_primaries",
            "bt709",
            "-c:a",
            "aac",
            "-b:a",
            "320k",
            "-t",
            "15",
            "-movflags",
            "+faststart",
            str(temp),
        ]
        proc = subprocess.Popen(call, stdin=subprocess.PIPE)
        try:
            for k in range(15 * FPS):
                proc.stdin.write(spot.frame(k / FPS).tobytes())
            proc.stdin.close()
            if proc.wait():
                raise RuntimeError("Portrait encoder failed")
            temp.replace(final)
            # Decode the first clear two-attachment detail from the encoded film.
            subprocess.run(
                [
                    ffmpeg,
                    "-loglevel",
                    "error",
                    "-y",
                    "-i",
                    str(final),
                    "-vf",
                    "select=eq(n\\,171)",
                    "-frames:v",
                    "1",
                    str(out / "vertical-thumbnail.png"),
                ],
                check=True,
            )
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()


def previews(spot, out):
    out.mkdir(parents=True, exist_ok=True)
    times = (0, 2.50, 3.04, 3.63, 4.36, 4.86, 5.64, 8.6, 10.97, 13.24)
    grid = Image.new("RGB", (5 * 216, 2 * 384), "white")
    for i, t in enumerate(times):
        frame = spot.frame(t).resize((216, 384), Image.Resampling.LANCZOS)
        grid.paste(frame, (i % 5 * 216, i // 5 * 384))
    return grid


def main():
    arg = argparse.ArgumentParser()
    arg.add_argument("lang", choices=("en", "zh-CN"))
    arg.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    arg.add_argument("--out", type=Path)
    arg.add_argument("--sheet", type=Path, help="Optional portrait editorial contact sheet")
    arg.add_argument("--render", action="store_true", help="Encode the 15-second edit")
    args = arg.parse_args()
    project = args.project.resolve()
    sys.path.insert(0, str(project / "studio"))
    import film

    out = args.out or project / "film" / args.lang
    spot = Portrait(args.lang, film)
    if args.sheet:
        previews(spot, out).save(args.sheet)
    if args.render:
        render(spot, out, project)


if __name__ == "__main__":
    main()
