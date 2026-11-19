"""Shared typography, colour and real-source image placement for the launch kit."""
import io
import os
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps
from resvg_py import svg_to_bytes
from plates import KIT, WORK, roman

PAPER = "#FCFBF8"
INK = "#102A27"
GREEN = "#357367"
MUTED = "#4D625A"
WHITE = "#FCFBF8"
PALE = "#E2EBDF"
DARK = "#123A34"
NATIVE = KIT / "source" / "edit"
PLATES = KIT / "source" / "plates"
SYSTEM_FONTS = Path("/System/Library/Fonts")
SONG = SYSTEM_FONTS / "Supplemental/Songti.ttc"
SANS = SYSTEM_FONTS / "HelveticaNeue.ttc"
MONO = SYSTEM_FONTS / "SFNSMono.ttf"
RESAMPLE = Image.Resampling.LANCZOS


@lru_cache(maxsize=None)
def font(role, size, zh=False):
    if role == "serif" or role == "italic":
        path, i = (str(SONG), 6) if zh else (roman(role == "italic"), 0)
    elif role == "mono":
        path, i = str(MONO), 0
    elif zh:
        if "RIFTLET_PINGFANG" in os.environ:
            path = os.environ["RIFTLET_PINGFANG"]
        else:
            path = str(next(Path("/System/Library/AssetsV2").glob("com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc"),
                            SYSTEM_FONTS / "PingFang.ttc"))
        i = 7 if role == "medium" else 3
    else:
        path, i = str(SANS), 1 if role == "medium" else 0
    return ImageFont.truetype(path, round(size), index=i)


def label(image, xy, text, size, *, role="sans", color=INK, zh=False, anchor="lt", maximum=None):
    f = font(role, size, zh)
    if maximum and f.getlength(text) > maximum:
        size = int(size * maximum / f.getlength(text))
        f = font(role, size, zh)
    ImageDraw.Draw(image).text(xy, text, font=f, fill=color, anchor=anchor)


def lines(image, xy, strings, size, *, leading, **kwargs):
    for index, value in enumerate(strings):
        label(image, (xy[0], xy[1] + leading * index), value, size, **kwargs)


@lru_cache(maxsize=16)
def logo(width):
    path = KIT.parents[1] / "website-assets" / "riftlet.svg"
    return Image.open(io.BytesIO(svg_to_bytes(svg_path=str(path), width=width, height=width))).convert("RGBA")


def brand(im, x, y, size=48, color=INK):
    symbol = logo(size)
    im.paste(symbol, (x, y), symbol)
    label(im, (x + size * 1.28, y + size * .22), "Riftlet", int(size * .76), role="medium", color=color)


@lru_cache(maxsize=12)
def photo(name):
    with Image.open(NATIVE / name) as im:
        return im.convert("RGBA")


@lru_cache(maxsize=6)
def chart(name, full=True):
    path = PLATES / (name + ".png")
    with Image.open(path) as im:
        canvas = im.convert("RGB")
    return canvas if full else canvas.crop((0, 0, canvas.width, 597))


def paste_fit(canvas, original, box, *, cover=False, center=(.5, .5)):
    x, y, w, h = box
    if cover:
        src = ImageOps.fit(original, (w, h), method=RESAMPLE, centering=center)
        canvas.paste(src, (x, y))
    else:
        sw, sh = original.size
        scale = min(w / sw, h / sh)
        size = (max(1, round(sw * scale)), max(1, round(sh * scale)))
        pos = (x + (w - size[0]) // 2, y + (h - size[1]) // 2)
        resized = original.resize(size, RESAMPLE)
        mask = resized.getchannel("A") if resized.mode == "RGBA" else None
        canvas.paste(resized, pos, mask)


def line(im, points, color, width=1):
    ImageDraw.Draw(im).line(points, fill=color, width=width)


def new(size, color=PAPER):
    return Image.new("RGB", size, color)


def tr(zh, cn, en):
    return cn if zh else en
