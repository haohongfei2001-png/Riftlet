"""Four original editorial graphics and two link previews for the Riftlet value campaign."""

from functools import lru_cache
from io import BytesIO
from pathlib import Path
import argparse
import tempfile

import resvg_py
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
CACHE = tempfile.TemporaryDirectory(prefix="riftlet-campaign-type-")
PAPER = "#F7F5EA"
DARK = "#102D28"
GREEN = "#166956"
MINT = "#65DCC0"
PALE = "#D8ECDB"
RED = "#BE513C"
MUTE = "#486457"
R = Image.Resampling.LANCZOS
S = 2
VALUES = (86, 91, 54, 78, 95)


def pix(*v):
    return tuple(round(x * S) for x in v)


@lru_cache
def font(which, size):
    if which in ("serif", "italic"):
        name = "instrument-serif" + ("-italic" if which == "italic" else "")
        file = Path(CACHE.name) / (name + ".ttf")
        if not file.exists():
            tt = TTFont(ASSETS / "fonts" / (name + ".woff2"))
            tt.flavor = None
            tt.save(file)
        return ImageFont.truetype(str(file), round(size * S))
    sysfont = Path("/System/Library/Fonts")
    path, idx = {
        "zh": ("STHeiti Medium.ttc", 1),
        "song": ("Supplemental/Songti.ttc", 6),
        "latin": ("HelveticaNeue.ttc", 10),
        "bold": ("HelveticaNeue.ttc", 1),
        "mono": ("Menlo.ttc", 0),
        "keys": ("SFNS.ttf", 0),
    }[which]
    return ImageFont.truetype(str(sysfont / path), round(size * S), index=idx)


@lru_cache
def logo(size):
    return Image.open(
        BytesIO(
            resvg_py.svg_to_bytes(
                svg_path=str(ASSETS / "riftlet.svg"), width=round(size * S), height=round(size * S)
            )
        )
    ).convert("RGBA")


def text(im, x, y, value, size, face="zh", fill=DARK, anchor="lt", maxw=None):
    ff = font(face, size)
    if maxw and ff.getlength(value) > maxw * S:
        ff = font(face, round(size * maxw * S / ff.getlength(value), 2))
    ImageDraw.Draw(im).text(pix(x, y), value, font=ff, fill=fill, anchor=anchor)
    return ff.getlength(value) / S


def line(im, pts, color, weight=1):
    ImageDraw.Draw(im).line(
        [pix(*p) for p in pts], fill=color, width=max(1, round(weight * S)), joint="curve"
    )


def rect(im, bounds, fill, radius=0, edge=None, stroke=1):
    ImageDraw.Draw(im).rounded_rectangle(
        pix(*bounds), round(radius * S), fill=fill, outline=edge, width=max(1, round(stroke * S))
    )


def circle(im, x, y, r, color):
    ImageDraw.Draw(im).ellipse(pix(x - r, y - r, x + r, y + r), fill=color)


def paste(im, layer, x, y):
    im.paste(layer, pix(x, y), layer if layer.mode == "RGBA" else None)


def brand(im, x=43, y=42, dark=False, size=37):
    paste(im, logo(size), x, y)
    text(im, x + size * 1.25, y - 2, "Riftlet", size * 1.13, "serif", PAPER if dark else DARK)


def paper(w, h, color=PAPER):
    return Image.new("RGB", pix(w, h), color)


def mounted(im, sheet, x, y, w, angle=0, shadow=True):
    layer = sheet.resize(pix(w, w * sheet.height / sheet.width), R).convert("RGBA")
    if angle:
        layer = layer.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    if shadow:
        pad = 24 * S
        base = Image.new("RGBA", (layer.width + 2 * pad, layer.height + 2 * pad))
        alpha = Image.new("L", base.size)
        alpha.paste(layer.getchannel("A"), (pad + 4 * S, pad + 7 * S))
        alpha = alpha.filter(ImageFilter.GaussianBlur(10 * S)).point(lambda v: round(v * 0.17))
        base.paste((11, 39, 30), mask=alpha)
        base.alpha_composite(layer, (pad, pad))
        im.paste(base, (round(x * S) - pad, round(y * S) - pad), base)
    else:
        paste(im, layer, x, y)


@lru_cache
def chart(en=False, old=False):
    im = paper(400, 227, "#F4D9B3" if old else "#DAECDB")
    if old:
        text(im, 21, 18, "Weekly overview" if en else "周报总览", 26, "serif" if en else "song", "#643E2E")
        vals = (0.65, 0.84, 0.58, 0.70, 0.79)
        for i, d in enumerate(vals):
            x = 29 + 69 * i
            rect(im, (x, 170 - d * 110, x + 50, 171), "#AB6549" if i != 2 else "#CD8964")
        line(im, [(19, 188), (381, 188)], "#B99571")
        text(im, 22, 201, "Overview" if en else "周报", 12, "latin" if en else "zh", "#805A43")
        return im
    text(im, 19, 15, "Daily trend" if en else "分日趋势", 29, "serif" if en else "song")
    line(im, [(20, 55), (380, 55)], "#A7C4AD")
    xs = [36 + i * 81 for i in range(5)]
    ys = [166 - (v - 50) * 1.95 for v in VALUES]
    for y in (83, 125, 166):
        line(im, [(23, y), (378, y)], "#BFD4BC", 0.8)
    line(im, list(zip(xs, ys)), GREEN, 3.8)
    for i, (x, y, v) in enumerate(zip(xs, ys, VALUES)):
        circle(im, x, y, 6 if i == 2 else 4, RED if i == 2 else GREEN)
        text(
            im,
            x,
            y + (12 if i == 2 else -11),
            str(v),
            16,
            "bold",
            RED if i == 2 else GREEN,
            "mt" if i == 2 else "mb",
        )
    for x, k in zip(
        xs, ("Mon", "Tue", "Wed", "Thu", "Fri") if en else ("周一", "周二", "周三", "周四", "周五")
    ):
        text(im, x, 197, k, 15, "latin" if en else "zh", MUTE, "mt")
    return im


def pointer(im, x, y, size=1):
    shape = ((0, 0), (2, 48), (14, 36), (22, 52), (31, 47), (22, 32), (40, 31))
    pts = [(x + a * size, y + b * size) for a, b in shape]
    ImageDraw.Draw(im).polygon([pix(*p) for p in pts], fill=DARK)
    line(im, pts + [pts[0]], PAPER, 2.9 * size)


def frame(im, x, y, w, h, color, arm=18):
    for xx, a in [(x, 1), (x + w, -1)]:
        for yy, b in [(y, 1), (y + h, -1)]:
            line(im, [(xx + a * arm, yy), (xx, yy), (xx, yy + b * arm)], color, 2.6)


def footer(im, dark=False):
    fg = "#BDDBCA" if dark else MUTE
    line(im, [(43, 905), (677, 905)], "#456C5D" if dark else "#B5C9B7")
    text(im, 43, 922, "Mac · Chrome 网页版 ChatGPT", 17, "zh", fg)
    text(im, 677, 924, "场景示意", 15, "zh", fg, "rt")


def panel_draft(en=False):
    im = paper(610, 280, "#FFFEFA")
    text(im, 21, 16, "ChatGPT", 24, "latin")
    text(
        im, 586, 20, "Draft in Chrome" if en else "Chrome 中的草稿", 17, "latin" if en else "zh", MUTE, "rt"
    )
    line(im, [(0, 55), (610, 55)], "#D7DFD4")
    for i, old in enumerate((True, False)):
        thumb = chart(en, old).resize(pix(126, 72), R)
        paste(im, thumb, 24 + i * 139, 75)
    text(im, 24, 174, "Why did Wednesday dip?" if en else "为什么周三下滑？", 26, "latin" if en else "zh")
    width = text(
        im,
        24,
        210,
        "How does it compare to last week?" if en else "和上周比呢？",
        23,
        "latin" if en else "zh",
        GREEN,
    )
    line(im, [(28 + width, 209), (28 + width, 237)], GREEN, 2)
    circle(im, 571, 239, 18, DARK)
    line(im, [(571, 247), (571, 231)], PAPER, 2)
    line(im, [(565, 237), (571, 231), (577, 237)], PAPER, 2)
    return im


def cover():
    im = paper(720, 960)
    brand(im)
    text(im, 677, 49, "riftlet.com", 18, "latin", MUTE, "rt")
    text(im, 40, 130, "刚截的图，", 86, "song")
    text(im, 42, 232, "点一下就进", 73, "zh")
    advance = text(im, 38, 323, "ChatGPT", 113, "italic", GREEN)
    text(im, 43 + advance, 396, "。", 42, "song", GREEN)
    # Cut the actual chart out of a hand-arranged weekly report spread. Its
    # particular Wednesday dip is recognizable when the print is seen small.
    mounted(im, chart(old=True), 379, 455, 328, -9)
    mounted(im, chart(), 66, 467, 458, 7)
    frame(im, 106, 504, 374, 201, GREEN, 21)
    pointer(im, 371, 621, 1.24)
    text(im, 43, 796, "点屏幕边缘的缩略图，", 30, "zh")
    text(im, 43, 841, "附加到当前 ChatGPT 草稿。", 30, "zh")
    footer(im)
    return im


def capture():
    im = paper(720, 960, DARK)
    brand(im, dark=True)
    text(im, 677, 49, "系统截屏", 19, "zh", "#B5D7C4", "rt")
    text(im, 41, 126, "问题写好了，", 68, "song", PAPER)
    text(im, 40, 219, "还差一张图。", 77, "song", PAPER)
    # The open question in this issue gives the save-and-attach action a reason.
    text(im, 43, 346, "「为什么周三下滑？」", 32, "zh", "#A8DBBD")
    mounted(im, chart(), 52, 435, 588)
    frame(im, 46, 429, 600, 346, MINT, 22)
    xx, yy = 637, 777
    line(im, [(xx - 14, yy), (xx + 14, yy)], PAPER, 2.2)
    line(im, [(xx, yy - 14), (xx, yy + 14)], PAPER, 2.2)
    text(im, 44, 824, "照常用 Mac 系统截屏。", 31, "zh", PAPER)
    for i, k in enumerate(("⇧", "⌘", "4")):
        x = 493 + i * 58
        rect(im, (x, 815, x + 45, 858), None, 7, "#89AA98", 1.5)
        text(im, x + 22.5, 827, k, 23, "keys", "#D9F6E6", "mt")
    footer(im, True)
    return im


def click():
    im = paper(720, 960, "#D6EAD9")
    brand(im)
    text(im, 677, 49, "屏幕边缘", 19, "zh", MUTE, "rt")
    text(im, 40, 132, "点刚截的", 73, "song")
    text(im, 39, 220, "那一张。", 89, "song", GREEN)
    # Detail of the right-edge Micro Slit, with the rightmost quarter concealed.
    # The number outside the crop separates the source label from the action.
    trim = 633
    line(im, [(trim + 1, 341), (trim + 1, 739)], "#537961", 2)
    src = chart()
    full = src.resize(pix(446, 446 * src.height / src.width), R)
    clipped = full.crop((0, 0, round(full.width * 0.75), full.height))
    x = trim - clipped.width / S
    rect(im, (x - 4, 404, trim + 1, 412 + clipped.height / S), "#F9FAF0", 7)
    paste(im, clipped, x, 408)
    circle(im, x - 38, 532, 21, "#EDF5E9")
    text(im, x - 38, 521, "1", 22, "mono", GREEN, "mt")
    pointer(im, 465, 538, 1.56)
    text(im, 43, 768, "Riftlet 把缩略图放在屏幕边缘。", 28, "zh")
    text(im, 43, 819, "点一下，附加到当前草稿。", 30, "zh")
    footer(im)
    return im


def finish():
    im = paper(720, 960, PAPER)
    brand(im)
    text(im, 677, 49, "当前草稿", 19, "zh", MUTE, "rt")
    text(im, 40, 129, "原来的问题，", 70, "song")
    text(im, 38, 219, "接着写。", 94, "song", GREEN)
    mounted(im, panel_draft(), 43, 389, 634)
    text(im, 43, 739, "已有文字和附件都留着。", 30, "zh")
    text(im, 43, 797, "什么时候发送，由你决定。", 31, "zh")
    line(im, [(43, 894), (677, 894)], "#B5C9B7")
    text(im, 43, 915, "下载 Mac 版", 21, "zh", DARK)
    text(im, 207, 915, "riftlet.com", 22, "latin", GREEN)
    text(im, 677, 920, "场景示意", 15, "zh", MUTE, "rt")
    return im


def share(en):
    im = paper(1200, 630, PAPER)
    brand(im, 50, 36, size=40)
    text(im, 1145, 49, "riftlet.com", 22, "latin", GREEN, "rt")
    if en:
        text(im, 46, 127, "Just took a", 64, "serif")
        text(im, 46, 193, "screenshot?", 94, "italic", GREEN)
        text(im, 47, 311, "One click adds it", 48, "bold")
        text(im, 47, 371, "to ChatGPT.", 48, "bold")
        text(im, 50, 487, "Click the thumbnail at the edge of your Mac screen.", 21, "latin")
        text(im, 50, 521, "It attaches to your current ChatGPT draft in Chrome.", 21, "latin")
    else:
        text(im, 46, 129, "刚截的图，", 78, "song")
        text(im, 46, 226, "点一下就进", 72, "zh")
        adv = text(im, 43, 303, "ChatGPT", 104, "italic", GREEN)
        text(im, 47 + adv, 365, "。", 39, "song", GREEN)
        text(im, 50, 475, "点屏幕边缘的缩略图，附加到当前草稿。", 25, "zh")
        text(im, 50, 522, "适用于 Mac 上的 Chrome 网页版 ChatGPT。", 21, "zh", MUTE)
    mounted(im, chart(en, True), 774, 133, 359, -9)
    mounted(im, chart(en), 638, 211, 450, 4)
    pointer(im, 901, 354, 1.16)
    text(
        im, 1148, 580, "Illustrated example" if en else "场景示意", 17, "latin" if en else "zh", MUTE, "rt"
    )
    return im


def export(im, destination, dim):
    dest = OUTPUT / destination
    dest.parent.mkdir(parents=True, exist_ok=True)
    profile = Path("/System/Library/ColorSync/Profiles/sRGB Profile.icc").read_bytes()
    im.resize(dim, R).save(
        dest, "JPEG", quality=94, subsampling=0, optimize=True, progressive=True, icc_profile=profile
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT)
    args = parser.parse_args()
    ASSETS = args.assets or next(
        p / "website-assets" for p in ROOT.parents if (p / "website-assets/riftlet.svg").is_file()
    )
    OUTPUT = args.output
    for fn, tag in [
        (cover, "01-claim"),
        (capture, "02-capture"),
        (click, "03-click"),
        (finish, "04-draft"),
    ]:
        export(fn(), f"xiaohongshu/{tag}.jpg", (1440, 1920))
    for en, tag in [(False, "zh-CN"), (True, "en")]:
        export(share(en), f"share/{tag}.jpg", (1200, 630))
