"""Offline visual reconstruction of a Chrome ChatGPT draft for the Riftlet campaign.

window(t, lang, scale=2) returns a transparent, rounded, 760 x 550 pt window.
Geometry is in logical points. The draft body and its existing attachment stay
in place while a second attachment appears. There is no send operation.
"""

from base64 import b64decode
from functools import lru_cache
from io import BytesIO
from math import cos, pi, sin
from os import environ
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps
import resvg_py

WIDTH, HEIGHT = 760, 550
COMPOSER = (36, 254, 688, 222)
EXISTING_TILE = (62, 270, 94, 84)
NEW_TILE = (170, 270, 94, 84)
TEXT_ORIGIN = (62, 380)
SEND_CENTER = (691, 446)
CLICK_TIME, ATTACH_TIME = 4.33, 4.80
TYPE_START, TYPE_END = 11.0, 14.4
DRAFT = {
    "zh-CN": ("有什么可以帮忙的？", "为什么周三下滑？", "和上周比呢？"),
    "en": (
        "What’s on your mind today?",
        "Why did visits drop on Wednesday?",
        " How does that compare with last week?",
    ),
}
INK, MUTED = "#171717", "#676767"
FONT_PATHS = ("/System/Library/Fonts/HelveticaNeue.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")


@lru_cache(maxsize=64)
def _font(px, medium=False, lang="en"):
    if lang == "zh-CN":
        weight = "Medium" if medium else "Light"
        # Face 1 selects the Simplified Chinese glyph forms in this macOS collection.
        for name, index in (
            (f"/System/Library/Fonts/STHeiti {weight}.ttc", 1),
            ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", 2),
        ):
            if Path(name).is_file():
                return ImageFont.truetype(name, px, index=index)
        raise FileNotFoundError("Install a Simplified Chinese font for the Chinese cut.")
    for name in FONT_PATHS:
        if Path(name).is_file():
            return ImageFont.truetype(name, px, index=(10 if name.endswith(".ttc") and medium else 0))
    return ImageFont.truetype("DejaVuSans.ttf", px)


class _Pen:
    def __init__(self, im, scale):
        self.im, self.s, self.d = im, scale, ImageDraw.Draw(im)

    def p(self, xy):
        return [round(v * self.s) for v in xy]

    def rect(self, box, color, radius=0, stroke=None, sw=1):
        self.d.rounded_rectangle(
            self.p(box),
            radius=round(radius * self.s),
            fill=color,
            outline=stroke,
            width=max(1, round(sw * self.s)),
        )

    def ellipse(self, xy, fill, stroke=None, sw=1):
        self.d.ellipse(self.p(xy), fill, stroke, max(1, round(sw * self.s)))

    def line(self, points, fill, sw=1):
        pts = [tuple(self.p(pt)) for pt in points]
        self.d.line(pts, fill=fill, width=max(1, round(sw * self.s)), joint="curve")

    def label(self, x, y, value, size, color=INK, medium=False, anchor="lm", lang="en"):
        f = _font(round(size * self.s), medium, lang)
        self.d.text(self.p((x, y)), value, font=f, fill=color, anchor=anchor)
        return self.d.textlength(value, font=f) / self.s


# OpenAI public favicon from cdn.oaistatic.com/assets/favicon-32x32-p4ktpm1x.webp.
# This identifiable third-party icon appears only inside the illustrated browser tab.
FAVICON_WEBP = (
    "UklGRnICAABXRUJQVlA4WAoAAAAQAAAAHwAAHwAAQUxQSI8AAAABd6A2kg06/T5EcqGIzkREILWfPrI5"
    "RTitte1pXprvniGwKHzbgMMgjMAkHAaB9HhUevJ9U+T/6T6i/wzctm0kde/27hVA1LJgHQAoiCX2Hvw3"
    "S62UnAc0rkOEtyHir7C+QPMbSg48lz0vKU1fl0ZUNyHRH8Pf4Tt0/Wb4Ow5/53QI3XzKKRVk8v/IxeB/"
    "BgBWUDggvAEAABALAJ0BKiAAIAA+aSqQRaQioZv6rABABoS0gAnAHJxnoP3rMm/kBkKFPL/yvok/1/87"
    "8zXyp/g/cC/jv9A/x35fdjN7Hf7ANdIJ5yn1lcylRWD9msH+g4lCVG3DwlB27AAA/v/b7x/k//Og4rBa"
    "kFx39Od09+fJ1x4C+DLOrn57IHc1Tex5U/5cB8l2f3fZBiD+5/7/IowL/9h145ee+E8Tn9Mx//ya2jMr"
    "sF0MWumdxn7zRJ7f7BEicBZVfKYEwPy/e9nUZPOkR9QyW1vCwpKLT4HeJVe7ayZ4dcQRfzMR0TeGbvw8"
    "U5I+jHciOCqPs43iwvLybOhARP2A/54Jx8B2XKJ3NgHNzVi3W2HkTpisnFaSV2NcPAhURRCHCp9wAwR1"
    "2+PxPlPateeyuKpswYl1DEzNt/SkXzDPkSq/LyuOSsHuqlcmY8ch6wMlzG7JlrkvSIL3kuB6BS6sByZZ"
    "XCNqJoa/4vqVhG8NdvpsjyX6hpz5DqxYMDrvqnl1//oedvi9KU2f/8I6YzFjiLYx5bH31D5eTMZBT8kq"
    "CpoNVnHwfQz5KqJRnU9pk4JVJRwRO0gt0GsehqDyZAAAAA=="
)


@lru_cache(maxsize=4)
def _favicon(scale):
    with Image.open(BytesIO(b64decode(FAVICON_WEBP))) as im:
        return im.convert("RGBA").resize((round(15 * scale),) * 2, Image.Resampling.LANCZOS)


@lru_cache(maxsize=4)
def _base(scale, lang):
    W, H = round(WIDTH * scale), round(HEIGHT * scale)
    im = Image.new("RGBA", (W, H), "#ffffff")
    q = _Pen(im, scale)
    # Chrome for macOS, light theme. A single tab is selected. The omnibox
    # shows only the public origin. There is no personal account or tab data.
    q.rect((0, 0, 760, 37), "#DCE2EB")
    q.rect((0, 36, 760, 76), "#F3F5F9")
    q.line([(0, 75.75), (760, 75.75)], "#CDD2D8", 0.75)
    for x, fill, edge in (
        (16, "#FF6058", "#DD5049"),
        (36, "#FFBD2D", "#E3A424"),
        (56, "#28C841", "#22B138"),
    ):
        q.ellipse((x - 5.5, 13.8, x + 5.5, 24.8), fill, edge, 0.55)
    q.rect((79, 6, 289, 45), "#F3F5F9", 12)
    q.rect((76, 32, 292, 38), "#F3F5F9")
    im.alpha_composite(_favicon(scale), (round(94 * scale), round(13.75 * scale)))
    q.label(117, 21.2, "ChatGPT", 12.3, color="#25282C")
    q.line([(267.5, 17.7), (274.2, 24.4)], "#5B6269", 1.25)
    q.line([(274.2, 17.7), (267.5, 24.4)], "#5B6269", 1.25)
    q.line([(306.4, 20.6), (317, 20.6)], "#515861", 1.4)
    q.line([(311.7, 15.3), (311.7, 25.9)], "#515861", 1.4)
    q.line([(17, 55.4), (28.5, 55.4)], "#626974", 1.5)
    q.line([(22.8, 49.7), (17, 55.4), (22.8, 61.1)], "#626974", 1.5)
    q.line([(48.5, 55.4), (60, 55.4)], "#A6ADB7", 1.4)
    q.line([(54.2, 49.7), (60, 55.4), (54.2, 61.1)], "#A6ADB7", 1.4)
    q.d.arc(
        q.p((79.4, 49.5, 91.3, 61.4)), start=9, end=312, fill="#5D6570", width=max(1, round(1.45 * scale))
    )
    q.line([(90.2, 48.5), (90.2, 52.7), (86.2, 52.7)], "#5D6570", 1.3)
    q.rect((105, 41, 726, 69), "#E5EAF2", 14)
    q.ellipse((111, 45.6, 130.6, 65.2), "#F6F8FA")
    q.line([(116.2, 52.7), (125, 52.7)], "#515963", 1.1)
    q.line([(116.2, 57.8), (125, 57.8)], "#515963", 1.1)
    q.ellipse((117.4, 50.8, 120.9, 54.3), "#515963")
    q.ellipse((121.1, 56, 124.6, 59.5), "#515963")
    q.label(137, 55, "chatgpt.com", 13.1, color="#20242A")
    star = [
        (
            708 + (6.4 if i % 2 == 0 else 2.9) * cos(-pi / 2 + i * pi / 5),
            55 + (6.4 if i % 2 == 0 else 2.9) * sin(-pi / 2 + i * pi / 5),
        )
        for i in range(10)
    ]
    q.line(star + [star[0]], "#59626D", 1.12)
    for y in (50.6, 55, 59.4):
        q.ellipse((740.1, y - 1.15, 742.4, y + 1.15), "#555D67")
    # Collapsed navigation. Chrome frame controls and ChatGPT controls belong
    # to separate rows, as on desktop.
    q.rect((20.7, 94, 37, 108.3), None, 3, INK, 1.55)
    q.line([(26, 94.9), (26, 107.3)], INK, 1.55)
    q.label(56, 101.9, "ChatGPT", 17.8, medium=True)
    q.line([(133.9, 100.3), (137.8, 104.2), (141.7, 100.3)], MUTED, 1.3)
    q.label(380, 205, DRAFT[lang][0], 29.5, anchor="mm", lang=lang)
    # Reserved attachment row keeps the question and button completely stable.
    q.rect((36, 256, 724, 477), "#F2F2F2", 27)
    q.rect((36, 254, 724, 475), "#FFFFFF", 27, "#D7D7D7", 1.1)
    y = SEND_CENTER[1]
    q.line([(62, y), (78, y)], INK, 1.8)
    q.line([(70, y - 8), (70, y + 8)], INK, 1.8)
    # Dictation and the ready-to-send control remain untouched throughout.
    q.rect((643, y - 8.9, 650, y + 2), None, 3.3, INK, 1.6)
    q.d.arc(q.p((640, y - 4, 653, y + 7)), 0, 180, fill=INK, width=max(1, round(1.6 * scale)))
    q.line([(646.5, y + 6.5), (646.5, y + 10)], INK, 1.5)
    x = SEND_CENTER[0]
    q.ellipse((x - 16.5, y - 16.5, x + 16.5, y + 16.5), "#161616")
    q.line([(x, y + 6.5), (x, y - 6.5)], "#FFFFFF", 1.85)
    q.line([(x - 6.2, y - 0.3), (x, y - 6.5), (x + 6.2, y - 0.3)], "#FFFFFF", 1.85)
    im.putalpha(_clip(scale))
    return im


@lru_cache(maxsize=8)
def _clip(scale):
    mask = Image.new("L", (round(WIDTH * scale), round(HEIGHT * scale)), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, mask.width - 1, mask.height - 1), radius=round(11 * scale), fill=255
    )
    return mask


@lru_cache(maxsize=1)
def _props():
    override = environ.get("RIFTLET_CAPTURE_PROPS")
    candidates = [Path(override)] if override else []
    for parent in Path(__file__).resolve().parents:
        candidates.extend(
            (
                parent / "capture-props",
                parent / "film" / "capture-props",
                parent / "assets" / "capture-props",
            )
        )
    for folder in candidates:
        if (folder / "trend-en.svg").is_file():
            return folder
    raise FileNotFoundError("Set RIFTLET_CAPTURE_PROPS to the campaign capture-props folder.")


@lru_cache(maxsize=32)
def _attachment(lang, scale, trend):
    if trend:
        source = (_props() / f"trend-{lang}.svg").read_text()
        fonts = [
            Path("/System/Library/Fonts") / name for name in ("HelveticaNeue.ttc", "STHeiti Medium.ttc")
        ]
        pixels = resvg_py.svg_to_bytes(
            svg_string=source,
            font_files=[str(p) for p in fonts if p.is_file()],
            sans_serif_family="Helvetica Neue",
        )
        art = Image.open(BytesIO(pixels))
    else:
        art = Image.open(_props() / f"overview-{lang}.png")
    w, h = EXISTING_TILE[2:]
    s = scale
    with art:
        tile = ImageOps.fit(
            art.convert("RGB"),
            (round(w * s), round(h * s)),
            Image.Resampling.LANCZOS,
            centering=(0.54 if trend else 0.05, 0.5),
        ).convert("RGBA")
    mask = Image.new("L", tile.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, tile.width - 1, tile.height - 1), round(10 * s), fill=255)
    tile.putalpha(mask)
    d = _Pen(tile, s)
    d.rect((0.5, 0.5, w - 1, h - 1), None, 10, "#D3D4C8", 0.6)
    d.ellipse((w - 18, 2, w - 2, 18), "#252525", "#FFFFFF", 1)
    d.line([(w - 12.5, 7.5), (w - 7.5, 12.5)], "white", 1.1)
    d.line([(w - 7.5, 7.5), (w - 12.5, 12.5)], "white", 1.1)
    return tile


@lru_cache(maxsize=12)
def _draft_base(scale, lang):
    im = _base(scale, lang).copy()
    x, y, _, _ = EXISTING_TILE
    im.alpha_composite(_attachment(lang, scale, False), (round(x * scale), round(y * scale)))
    return im


def _tail(t, lang):
    suffix = DRAFT[lang][2]
    if t < TYPE_START:
        return ""
    if t >= TYPE_END:
        return suffix
    if lang == "zh-CN":
        # Per-character reveal represents the committed IME output.
        times = (11.0, 11.47, 12.13, 12.83, 13.66, 14.4)
        count = sum(t >= moment for moment in times)
    else:
        # Preserve the initial whitespace of the English continuation.
        count = 1 + int((len(suffix) - 1) * (t - TYPE_START) / (TYPE_END - TYPE_START))
    return suffix[:count]


def window(t, lang, scale=2):
    """Render a single localized, unsubmitted ChatGPT draft at timeline second t."""
    lang = "zh-CN" if lang.lower().startswith("zh") else lang
    if lang not in DRAFT:
        raise ValueError("lang must be en or zh-CN")
    if scale <= 0:
        raise ValueError("scale must be positive")
    im = _draft_base(scale, lang).copy()
    if t >= ATTACH_TIME:
        x, y, _, _ = NEW_TILE
        tile = _attachment(lang, scale, True)
        progress = max(0.12, min(1.0, (t - ATTACH_TIME) / 0.12))
        if progress < 1.0:
            tile = tile.copy()
            tile.putalpha(tile.getchannel("A").point(lambda value: round(value * progress)))
        im.alpha_composite(tile, (round(x * scale), round(y * scale)))
    q = _Pen(im, scale)
    x, y = TEXT_ORIGIN
    text = DRAFT[lang][1] + _tail(t, lang)
    face_size = 19 if lang == "zh-CN" else 18.4
    length = q.label(x, y, text, face_size, lang=lang)
    if TYPE_START <= t < TYPE_END + 0.30 or t % 1.16 < 0.60:
        q.line([(x + length + 1.1, y - 9), (x + length + 1.1, y + 10)], "#232323", 1)
    return im
