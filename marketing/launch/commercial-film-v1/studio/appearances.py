"""Two editorial close-ups of alternative 1.0.5 right-edge presentation modes.

insert(t, lang, scale) returns a complete 1280 x 720 canvas at the given scale.
The two panels are synchronized previews. Each depicts a separate desktop.
"""

from functools import lru_cache
from importlib import import_module
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

from product_geometry import Product, RIGHT

ARRIVALS = ((7.03, 0), (7.69, 1))
PRESS, START, REFILL = 8.82, 8.97, 9.53
CLICKS = ((PRESS, START, REFILL, 0),)
PANELS = ((40, 223, 630, 652), (650, 223, 1240, 652))
# Rightmost point and vertical origin of each native demonstration relative
# to its desktop crop. Magnification is editorial, preserving shape ratios.
CAMERAS = {"tray": (573, 47, 1.28), "slit": (573, 86, 1.68)}


def _film():
    active = sys.modules.get("__main__")
    if Path(getattr(active, "__file__", "") or "").name == "film.py":
        return active
    return import_module("film")


@lru_cache(maxsize=2)
def _product(lang):
    art = _film()
    with Image.open(art.ROOT / "capture-props" / f"overview-{lang}.png") as old:
        return Product((art.chart(lang), old))


def _px(values, s):
    return tuple(round(n * s) for n in values)


def _blend(a, b, amount):
    return a * (1 - amount) + b * amount


@lru_cache(maxsize=4)
def _desktop(width, height, scale):
    # Same muted, untextured contour desktop as the preceding overview. The
    # harder right bezel makes the physical desk edge unambiguous in close-up.
    w, h = _px((width, height), scale)
    y, x = np.mgrid[0:h, 0:w]
    u, v = x / w, y / h
    amount = (0.20 + 0.48 * u + 0.16 * v)[..., None]
    rgb = _blend(np.array((199, 220, 197)), np.array((103, 157, 134)), amount)
    for top, pigment, opacity in (
        (1.13 - 0.47 * u + 0.038 * np.sin(u * 4), (114, 159, 132), 0.53),
        (1.31 - 0.46 * u + 0.032 * np.sin(u * 4), (97, 142, 119), 0.68),
    ):
        mask = np.clip((v - top) * 55, 0, 1)[..., None]
        rgb = _blend(rgb, np.array(pigment), mask * opacity)
    stage = Image.fromarray(rgb.astype("uint8"))
    d = ImageDraw.Draw(stage)
    d.rectangle(_px((573, 0, width, height), scale), fill="#5E7D6D")
    d.rectangle(_px((575, 0, width, height), scale), fill="#526F61")
    d.rectangle(_px((578, 0, width, height), scale), fill="#426254")
    d.rectangle(_px((587, 0, width, height), scale), fill="#38564A")
    return stage


@lru_cache(maxsize=4)
def _mask(w, h, s):
    im = Image.new("L", _px((w, h), s))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, im.width - 1, im.height - 1), round(17 * s), fill=255)
    return im


def _pointer(stage, x, y, scale):
    points = [(0, 0), (0.6, 24), (7.3, 18.3), (12.4, 27.6), (16.8, 25.5), (11.9, 16.2), (20, 15.9)]
    pts = [_px((x + i, y + j), scale) for i, j in points]
    d = ImageDraw.Draw(stage)
    d.polygon(pts, fill="#182923")
    d.line(pts + pts[:1], fill="white", width=max(1, round(1.8 * scale)), joint="curve")


def _window(t, lang, mode, scale):
    width = PANELS[0][2] - PANELS[0][0]
    height = PANELS[0][3] - PANELS[0][1]
    stage = _desktop(width, height, scale).copy()
    edge, top, zoom = CAMERAS[mode]
    left = edge - RIGHT * zoom
    product = _product(lang)
    plate = product.frame(mode, t, ARRIVALS, CLICKS, scale=zoom * scale)
    stage.paste(plate, _px((left, top), scale), plate)
    # Follow the first screenshot. Only the initial screenshot is selected.
    # The second remains in place until the pointer has cleared the controls.
    if 8.18 <= t < 9.78:
        center = product.target(mode, 8.65, ARRIVALS, index=0)
        target = (left + center[0] * zoom + 8, top + center[1] * zoom + 3)
        outside = (target[0] - 83, target[1] + 106)
        h = _film().ease(t, 8.18, 8.70) if t < 9.12 else 1 - _film().ease(t, 9.12, 9.51)
        x, y = (_blend(a, b, h) for a, b in zip(outside, target))
        # Light pressure feedback stays on the selected thumbnail.
        if PRESS <= t < START + 0.10:
            progress = _film().ease(t, PRESS, START + 0.10)
            r = 4.2 + 13 * progress
            ring = Image.new("RGBA", stage.size)
            ImageDraw.Draw(ring).ellipse(
                _px((x - r, y - r, x + r, y + r), scale),
                outline=(252, 255, 242, round(218 * (1 - progress))),
                width=max(1, round(1.6 * scale)),
            )
            stage.paste(ring, (0, 0), ring)
        _pointer(stage, x, y, scale)
    return stage


@lru_cache(maxsize=8)
def _layout(lang, scale):
    film = _film()
    cn = lang == "zh-CN"
    stage = Image.new("RGB", _px((1280, 720), scale), film.BG)
    mark = film.logo(round(33 * scale))
    stage.paste(mark, _px((40, 24), scale), mark)
    film.txt(stage, 84, 26, "Riftlet", 36, "serif", film.INK, scale)
    film.txt(
        stage,
        1237,
        37,
        "Mac 上的 Chrome" if cn else "Mac  /  Chrome",
        17,
        "zh" if cn else "medium",
        film.GREEN,
        scale,
        anchor="rt",
    )
    size = 65 if cn else 58
    first = "两种外观，" if cn else "Two looks."
    second = "同一组截图。" if cn else "The same screenshots."
    length = film.txt(stage, 39, 88, first, size, "song" if cn else "serif", film.INK, scale)
    film.txt(
        stage,
        40 + length + (0 if cn else 12),
        88,
        second,
        size,
        "song" if cn else "italic",
        film.GREEN,
        scale,
        limit=1170 - length,
    )
    for idx, name in enumerate(("截图托盘", "微缝") if cn else ("Screenshot Tray", "Micro Slit")):
        x = PANELS[idx][0]
        film.txt(stage, x + 3, 196, name, 25, "zh" if cn else "medium", film.INK, scale, anchor="lm")
    film.txt(
        stage,
        43,
        688,
        "连截几张，点哪张就附加哪张。"
        if cn
        else "Take a few screenshots. Click the one you want to attach.",
        19,
        "zh" if cn else "medium",
        film.INK,
        scale,
        anchor="lm",
    )
    film.txt(stage, 1236, 688, "riftlet.com", 18, "medium", film.GREEN, scale, anchor="rm")
    return stage


def insert(t, lang, scale=1.5):
    lang = "zh-CN" if lang.lower().startswith("zh") else lang
    if lang not in ("zh-CN", "en") or scale <= 0:
        raise ValueError("Use zh-CN or en and a positive scale.")
    stage = _layout(lang, scale).copy()
    for rect, mode in zip(PANELS, ("tray", "slit")):
        x, y, r, b = rect
        panel = _window(t, lang, mode, scale)
        stage.paste(panel, _px((x, y), scale), _mask(r - x, b - y, scale))
    return stage
