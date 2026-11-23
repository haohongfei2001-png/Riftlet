"""Build the 20-second One Click campaign from the same public chart as the web and social artwork."""

import argparse
import io
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

import av
import imageio_ffmpeg
import numpy as np
import resvg_py
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont, ImageFilter

from composer import window
from appearances import insert

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT.parents[2] / "website-assets"
FONTS = Path("/System/Library/Fonts")
SCRATCH = tempfile.TemporaryDirectory(prefix="riftlet-value-type-")
BG = "#F7F7EE"
INK = "#173B33"
GREEN = "#116B5D"
ACID = "#ACDCC2"
R = Image.Resampling.LANCZOS
W, H, S = 1600, 820, 2
FPS = 30


def ease(t, a, b):
    u = max(0, min(1, (t - a) / (b - a)))
    return u * u * (3 - 2 * u)


def track(t, keys):
    for (a, va), (b, vb) in zip(keys, keys[1:]):
        if t <= b:
            e = ease(t, a, b)
            return tuple(x + (y - x) * e for x, y in zip(va, vb))
    return keys[-1][1]


@lru_cache(maxsize=192)
def font(which, n):
    if which in ("serif", "italic"):
        name = "instrument-serif" + ("-italic" if which == "italic" else "")
        path = Path(SCRATCH.name) / (name + ".ttf")
        if not path.exists():
            ff = TTFont(BRAND / "fonts" / (name + ".woff2"))
            ff.flavor = None
            ff.save(path)
        return ImageFont.truetype(str(path), n)
    file, index = {
        "sans": ("HelveticaNeue.ttc", 0),
        "medium": ("HelveticaNeue.ttc", 10),
        "bold": ("HelveticaNeue.ttc", 1),
        "zh": ("STHeiti Medium.ttc", 1),
        "song": ("Supplemental/Songti.ttc", 6),
        "mono": ("Menlo.ttc", 0),
        "keys": ("SFNS.ttf", 0),
    }[which]
    return ImageFont.truetype(str(FONTS / file), n, index=index)


def txt(im, x, y, text, sz, f, ink, scale=1, anchor="lt", limit=None):
    ft = font(f, max(1, round(sz * scale)))
    if limit and ft.getlength(text) > limit * scale:
        ft = font(f, max(1, int(ft.size * limit * scale / ft.getlength(text))))
    ImageDraw.Draw(im).text((round(x * scale), round(y * scale)), text, font=ft, fill=ink, anchor=anchor)
    return ft.getlength(text) / scale


@lru_cache
def logo(size):
    return Image.open(
        io.BytesIO(resvg_py.svg_to_bytes(svg_path=str(BRAND / "riftlet.svg"), width=size, height=size))
    ).convert("RGBA")


@lru_cache
def chart(lang):
    path = ROOT / "capture-props" / f"trend-{lang}.svg"
    png = resvg_py.svg_to_bytes(
        svg_path=str(path),
        zoom=2,
        font_files=[str(FONTS / "HelveticaNeue.ttc"), str(FONTS / "STHeiti Medium.ttc")],
        sans_serif_family="Heiti SC",
    )
    return Image.open(io.BytesIO(png)).convert("RGB")


def p(*a):
    return tuple(round(v * S) for v in a)


def layer(im, plate, x, y):
    im.paste(plate, p(x, y), plate if plate.mode == "RGBA" else None)


def roundrect(im, b, r, fill, edge=None, sw=1):
    ImageDraw.Draw(im).rounded_rectangle(p(*b), r * S, fill=fill, outline=edge, width=sw * S)


@lru_cache
def desk(lang):
    zh = lang == "zh-CN"
    # A matte desktop with two soft, oblique paper-coloured contours. Render
    # decoration once; all windows, the application edge and the pointer are separate.
    x, y = np.meshgrid(np.linspace(0, 1, 600), np.linspace(0, 1, 320))
    amount = (0.20 + 0.72 * x + 0.16 * y).clip(0, 1)[:, :, None]
    rgb = np.array([202, 221, 199]) * (1 - amount) + np.array([107, 161, 142]) * amount
    for curve, pigment in [
        (0.91 - 0.70 * x + 0.09 * np.sin(x * 6), [94, 144, 120]),
        (1.22 - 0.76 * x, [126, 162, 135]),
    ]:
        mask = ((y - curve) * 25).clip(0, 1)[:, :, None]
        rgb = rgb * (1 - mask * 0.76) + np.array(pigment) * mask * 0.76
    base = Image.fromarray(rgb.astype("uint8")).resize(p(W, H), Image.Resampling.BICUBIC)
    roundrect(base, (0, 0, W, 32), 0, "#DCE7DA")
    txt(base, 22, 8, "Chrome", 16, "bold", INK, S)
    txt(
        base,
        102,
        8,
        "文件     编辑     查看     历史记录     书签     窗口"
        if zh
        else "File     Edit     View     History     Bookmarks     Window",
        14,
        "zh" if zh else "sans",
        INK,
        S,
    )
    txt(base, 1577, 9, "10:24", 14, "medium", INK, S, anchor="rt")
    # Work document. The source graphic fills exactly the system selection.
    for box in [(44, 140, 704, 610), (717, 110, 1477, 660)]:
        shadow = Image.new("RGBA", base.size)
        ImageDraw.Draw(shadow).rounded_rectangle(
            p(box[0], box[1] + 13, box[2], box[3] + 13), radius=18 * S, fill=(22, 39, 32, 73)
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(16 * S))
        base.paste(shadow, (0, 0), shadow)
    roundrect(base, (44, 140, 704, 610), 13, "#FAFAF4", "#C6CFC3")
    roundrect(base, (45, 141, 703, 183), 12, "#E8ECE2")
    for x0 in [65, 84, 103]:
        ImageDraw.Draw(base).ellipse(p(x0 - 5, 157, x0 + 5, 167), fill="#BCC6B8")
    txt(
        base,
        374,
        154,
        "周报 · 分日访问量" if zh else "Weekly report · Visits by day",
        16,
        "zh" if zh else "medium",
        "#53665A",
        S,
        anchor="mt",
    )
    layer(base, chart(lang).resize(p(628, 392.5), R), 60, 195)
    return base


def pointer(im, x, y):
    coords = [(0, 0), (1, 19), (6.4, 14.7), (10.1, 22.2), (13.3, 20.6), (9.6, 13.4), (16.1, 13.1)]
    pts = [p(x + i, y + j) for i, j in coords]
    d = ImageDraw.Draw(im)
    d.polygon(pts, fill="#192520")
    d.line(pts + pts[:1], fill="white", width=3, joint="curve")


@lru_cache
def thumb(lang):
    # Native Micro Slit fits the full source into 72×56 pt and masks its rightmost 25%.
    src = chart(lang).resize(p(72, 45), R)
    tile = Image.new("RGBA", p(76, 49))
    ImageDraw.Draw(tile).rounded_rectangle(
        (0, 0, tile.width - 1, tile.height - 1), radius=6 * S, fill="#FAFBF4"
    )
    tile.paste(src, p(2, 2))
    return tile.crop((0, 0, round(tile.width * 0.75), tile.height))


class Spot:
    def __init__(self, lang):
        self.lang = lang
        self.cn = lang == "zh-CN"
        self.panel = (38, 185, 1242, 666)
        self.arrive, self.click, self.attach = 3.16, 4.33, 4.80

    def tr(self, cn, en):
        return cn if self.cn else en

    def screen(self, t):
        im = desk(self.lang).copy()
        layer(im, window(t, self.lang, scale=S), 717, 110)
        left, top, right, bottom = 60, 195, 688, 587.5
        if 1.43 < t < 2.81:
            k = ease(t, 1.54, 2.65)
            xx = left + (right - left) * k
            yy = top + (bottom - top) * k
            mask = Image.new("RGBA", im.size, (12, 24, 18, 69))
            ImageDraw.Draw(mask).rectangle(p(left, top, xx, yy), fill=(0, 0, 0, 0))
            im.paste(mask, (0, 0), mask)
            d = ImageDraw.Draw(im)
            d.rectangle(p(left, top, xx + 1, yy + 1), outline="white", width=2)
            d.line(p(xx - 9, yy, xx + 9, yy), fill="#17382D", width=4)
            d.line(p(xx, yy - 9, xx, yy + 9), fill="#17382D", width=4)
            d.line(p(xx - 8, yy, xx + 8, yy), fill="white", width=2)
            d.line(p(xx, yy - 8, xx, yy + 8), fill="white", width=2)
            if t > 2.30:
                txt(im, xx - 13, yy - 18, "628 × 393", 12, "mono", "#143D32", S, anchor="rt")
        if 2.73 < t < 2.87:
            alpha = round(103 * (1 - ease(t, 2.73, 2.87)))
            flash = Image.new("RGBA", p(right - left, bottom - top), (255, 255, 249, alpha))
            layer(im, flash, left, top)
        if self.arrive <= t < self.attach + 0.12:
            appear = ease(t, self.arrive, self.arrive + 0.16)
            gone = ease(t, self.attach, self.attach + 0.12)
            a = thumb(self.lang)
            exposed = round(a.width * appear * (1 - gone))
            if exposed > 0:
                x = (W - 17) - exposed / S
                y = 408 - a.height / S / 2
                tile = a.crop((0, 0, exposed, a.height))
                layer(im, tile, x, y)
                edge = W - 17
                ImageDraw.Draw(im).line(p(edge, y - 3, edge, y + a.height / S + 3), fill="#496F59", width=S)
                roundrect(im, (x - 18, 399, x - 6, 417), 5, "#ECEEE3")
                txt(im, x - 12, 402, "1", 12, "mono", "#455F51", S, anchor="mt")
        if not (1.39 < t < 2.85):
            x, y = track(
                t,
                [
                    (0, (1096, 494)),
                    (0.96, (1096, 494)),
                    (1.43, (60, 195)),
                    (2.72, (688, 587)),
                    (3.22, (1510, 541)),
                    (4.18, (1552, 410)),
                    (4.54, (1552, 410)),
                    (5.57, (1168, 520)),
                    (8.90, (1168, 520)),
                    (10.83, (1038, 501)),
                    (16, (1038, 501)),
                ],
            )
            if self.click <= t <= self.click + 0.23:
                progress = ease(t, self.click, self.click + 0.23)
                radius = 4 + progress * 13
                halo = Image.new("RGBA", p(40, 40))
                ImageDraw.Draw(halo).ellipse(
                    p(20 - radius, 20 - radius, 20 + radius, 20 + radius),
                    outline=(245, 255, 242, round(245 * (1 - progress))),
                    width=3 * S,
                )
                layer(im, halo, x - 20, y - 20)
            pointer(im, x, y)
        return im

    def camera(self, t):
        return track(
            t,
            [
                (0, (841, 402, 1640)),
                (0.78, (816, 405, 1640)),
                (1.47, (410, 394, 1100)),
                (2.77, (398, 394, 1060)),
                (3.42, (1364, 432, 477)),
                (3.92, (1381, 429, 442)),
                (4.46, (1381, 429, 442)),
                (4.89, (1204, 502, 829)),
                (5.68, (1110, 511, 839)),
                (8.7, (1110, 503, 823)),
                (10.68, (1090, 514, 772)),
                (14.40, (1090, 515, 772)),
                (15.72, (1134, 454, 949)),
                (17.0, (1138, 447, 1004)),
            ],
        )

    def editorial(self, t, canvas, scale):
        # The app icon and the brand name share a single masthead.
        lg = logo(round(33 * scale))
        canvas.paste(lg, (round(40 * scale), round(24 * scale)), lg)
        txt(canvas, 84, 26, "Riftlet", 36, "serif", INK, scale)
        txt(
            canvas,
            1237,
            37,
            self.tr("Mac 上的 Chrome", "Mac  /  Chrome"),
            17,
            "zh" if self.cn else "medium",
            GREEN,
            scale,
            anchor="rt",
        )
        if t < 5.22:
            a = self.tr("刚截的图，", "Just took a screenshot?")
            b = self.tr("点一下就进 ChatGPT。", "One click adds it to ChatGPT.")
        elif t < 10.50:
            a = self.tr("原来的草稿，", "Same draft.")
            b = self.tr("多了刚截的图。", "New screenshot.")
        elif t < 14.80:
            a = self.tr("原来的问题，", "Your question stays.")
            b = self.tr("接着写。", "Keep writing.")
        else:
            a = self.tr("不用找文件，", "No file hunting.")
            b = self.tr("也不用拖图。", "No dragging.")
        size = 65 if self.cn else 58
        f = "song" if self.cn else "serif"
        g = "song" if self.cn else "italic"
        width = txt(canvas, 39, 88, a, size, f, INK, scale)
        txt(canvas, (41 if self.cn else 52) + width, 88, b, size, g, GREEN, scale, limit=1187 - width)
        if t < 1.60:
            desc = self.tr(
                "周报写到一半，还差一张趋势图。", "The question is drafted. It needs one more chart."
            )
        elif t < 3.15:
            desc = self.tr("用 Mac 自带的截屏。", "Use the usual Mac screenshot shortcut.")
        elif t < 4.85:
            desc = self.tr("点屏幕边缘的这张缩略图。", "Click the thumbnail at the edge of the screen.")
        elif t < 10.50:
            desc = self.tr(
                "旧附件、原文字，都留在当前草稿里。", "The existing attachment and text stay in this draft."
            )
        elif t < 14.80:
            desc = self.tr("想补一句就继续输入，发送由你。", "Keep typing. You decide when to send.")
        else:
            desc = self.tr(
                "刚截的图，一次点击就能附加。", "One click to attach the screenshot you just took."
            )
        txt(canvas, 43, 688, desc, 19, "zh" if self.cn else "medium", INK, scale, anchor="lm")
        txt(canvas, 1236, 688, "riftlet.com", 18, "medium", GREEN, scale, anchor="rm")

    def ending(self, t, scale):
        size = (round(1280 * scale), round(720 * scale))
        im = Image.new("RGB", size, "#163C34")
        draw = ImageDraw.Draw(im)
        # Print the data curve at poster scale; the coral low point is the same one
        # the audience saw in the screenshot, not a new UI affordance.
        pts = [(-70, 541), (139, 496), (423, 637), (782, 461), (1367, 411)]
        end = ease(t, 16.84, 18.1)
        for i in range(len(pts) - 1):
            amount = max(0, min(1, end * 4 - i))
            if not amount:
                continue
            x, y = pts[i]
            nx, ny = pts[i + 1]
            draw.line(
                tuple(round(v * scale) for v in (x, y, x + (nx - x) * amount, y + (ny - y) * amount)),
                fill="#507966",
                width=max(1, round(2 * scale)),
            )
        if end > 0.55:
            draw.ellipse(tuple(round(v * scale) for v in (415, 629, 431, 645)), fill="#E68B64")
        txt(
            im,
            65,
            67,
            self.tr("Mac 上的 Chrome 网页版 ChatGPT", "ChatGPT in Chrome on Mac"),
            37,
            "song" if self.cn else "serif",
            "#C8DCCA",
            scale,
        )
        lg = logo(round(97 * scale))
        im.paste(lg, (round(62 * scale), round(183 * scale)), lg)
        txt(im, 183, 169, "Riftlet", 124, "serif", "#FBF8EC", scale)
        txt(
            im,
            64,
            354,
            self.tr(
                "刚截的图，点一下就进 ChatGPT。", "Just took a screenshot? One click adds it to ChatGPT."
            ),
            46 if self.cn else 45,
            "song" if self.cn else "serif",
            "#C6E9CF",
            scale,
            limit=1150,
        )
        txt(
            im,
            65,
            651,
            self.tr("下载 Mac 版", "Download for Mac"),
            24,
            "zh" if self.cn else "medium",
            "#EFF5E9",
            scale,
        )
        txt(im, 1210, 647, "riftlet.com", 35, "medium", "#EFF5E9", scale, anchor="rt")
        return im

    def frame(self, t, scale=1.5):
        if 6.65 <= t < 10.50:
            return insert(t, self.lang, scale)
        if t >= 17.05:
            return self.ending(t, scale)
        outsize = (round(1280 * scale), round(720 * scale))
        im = Image.new("RGB", outsize, BG)
        self.editorial(t, im, scale)
        x, y, rx, by = self.panel
        pw, ph = rx - x, by - y
        cx, cy, width = self.camera(t)
        height = width * ph / pw
        # Stop the camera at the physical display edge.
        left = max(0, min(W - width, cx - width / 2))
        top = max(0, min(H - height, cy - height / 2))
        width = min(W, width)
        height = width * ph / pw
        screen = self.screen(t)
        view = screen.resize(
            (round(pw * scale), round(ph * scale)),
            Image.Resampling.BICUBIC,
            box=(left * S, top * S, (left + width) * S, (top + height) * S),
        )
        mask = rounded(view.size, round(18 * scale))
        im.paste(view, (round(x * scale), round(y * scale)), mask)
        if t > 16.78:
            n = self.ending(t, scale)
            u = ease(t, 16.78, 17.05)
            offset = round((1 - u) * (1280 + 190) * scale) - round(190 * scale)
            mask = Image.new("L", outsize)
            ImageDraw.Draw(mask).polygon(
                [(offset, 0), (outsize[0], 0), outsize, (offset + round(190 * scale), outsize[1])], fill=255
            )
            im = Image.composite(n, im, mask)
        return im


@lru_cache(maxsize=8)
def rounded(size, r):
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=r, fill=255)
    return mask


def render(lang):
    dest = ROOT / "film" / lang / "master.mp4"
    dest.parent.mkdir(exist_ok=True, parents=True)
    tmp = dest.with_suffix(".partial.mp4")
    cmd = [
        imageio_ffmpeg.get_ffmpeg_exe(),
        "-v",
        "error",
        "-y",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-s",
        "1920x1080",
        "-r",
        "30",
        "-i",
        "pipe:0",
        "-i",
        str(ROOT / "film" / "score.wav"),
        "-vf",
        "scale=out_color_matrix=bt709:out_range=tv",
        "-c:v",
        "libx264",
        "-crf",
        "16",
        "-preset",
        "fast",
        "-threads",
        "4",
        "-pix_fmt",
        "yuv420p",
        "-colorspace",
        "bt709",
        "-color_trc",
        "bt709",
        "-color_primaries",
        "bt709",
        "-c:a",
        "aac",
        "-aac_coder",
        "fast",
        "-b:a",
        "320k",
        "-t",
        "20",
        "-movflags",
        "+faststart",
        str(tmp),
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    spot = Spot(lang)
    try:
        for k in range(600):
            proc.stdin.write(spot.frame(k / 30).tobytes())
        proc.stdin.close()
        if proc.wait():
            raise RuntimeError("Encoder failed")
        tmp.replace(dest)
        with av.open(dest) as movie:
            for frame in movie.decode(video=0):
                if frame.time >= 5.70 - 1e-7:
                    frame.to_image().convert("RGB").save(
                        dest.with_name("thumbnail.jpg"), quality=96, subsampling=0
                    )
                    break
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("lang", choices=["en", "zh-CN"])
    render(parser.parse_args().lang)
