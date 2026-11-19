"""Portrait conform. The product state follows the approved 30 s editorial clock."""
import argparse
from functools import partial
from pathlib import Path

from PIL import Image, ImageDraw

from chrome.composer import draw_window
from film import brandbug, encode, lower_shade, on_disk
from sets import ART, INK, IVORY, ROOT, Set, mark, mix, s, txt, viewport


SIZE = (1080, 1920)
COPY = {
    "en": {
        "opening": "Keep the thought.",
        "purpose": "Mac screenshots to ChatGPT in Chrome.",
        "capture": "Capture.",
        "line": "The inner line.",
        "proof": "Track study   /   02",
        "one": "At hand.",
        "two": "Both here.",
        "tray": "Riftlet screenshot tray",
        "click": "One click.",
        "draft": "Your draft.",
        "attached": "Attached.",
        "continue": "Continue.",
        "benefit": "No file hunt. No dragging.",
        "signature": "Capture. Click. Continue.",
        "download": "Download for macOS  ·  Public Beta",
    },
    "zh-CN": {
        "opening": "让思路继续。",
        "purpose": "Mac 截图，一点就到 Chrome 中的 ChatGPT 草稿。",
        "capture": "截屏",
        "line": "蓝色内道",
        "proof": "赛道影像   /   02",
        "one": "就在手边",
        "two": "两张都在",
        "tray": "Riftlet 截图托盘",
        "click": "点一下",
        "draft": "当前草稿",
        "attached": "已附加",
        "continue": "继续",
        "benefit": "不用找文件，也不用拖放。",
        "signature": "截屏、点选、继续。",
        "download": "下载 macOS 公测版",
    },
}

# Release of the selection, tray arrival, pointer press and attachment START
# remain separate events on both edits.
CLOCK = [
    (0., 0.), (1.55, 2.83), (2.53, 5.1), (3.03, 5.55), (4.07, 7.2),
    (4.43, 8.10), (4.83, 8.55), (6.6, 10.98), (7.01, 11.94), (7.54, 13.20),
    (7.75, 13.45), (8.72, 14.70), (9.55, 17.71), (9.60, 17.80), (11.2, 20.65),
    (12., 24.85), (15., 30.),
]


def source_time(t):
    for (start, source_start), (end, source_end) in zip(CLOCK, CLOCK[1:]):
        if t < end:
            return mix(source_start, source_end, (t - start) / (end - start))
    return 30.


def photo(im, picture, t, begin, shutter):
    x, y, w, h = 52, 603, 976, 651
    im.paste(picture.resize((w, h), Image.Resampling.LANCZOS), (x, y))
    draw = ImageDraw.Draw(im)
    for xx, dx in ((x, -1), (x + w, 1)):
        for yy, dy in ((y, -1), (y + h, 1)):
            draw.line((xx + 4 * dx, yy, xx + 18 * dx, yy), fill="#777D72", width=2)
            draw.line((xx, yy + 4 * dy, xx, yy + 18 * dy), fill="#777D72", width=2)
    if t <= shutter:
        k = s(t, begin, shutter - .04)
        shade = Image.new("RGBA", (w, h), (0, 0, 0, 71))
        ImageDraw.Draw(shade).rectangle((0, 0, max(1, w*k), max(1, h*k)),
                                       fill=(0, 0, 0, 0), outline="white", width=3)
        im.paste(shade, (x, y), shade)
    if shutter <= t < shutter + .12:
        return Image.blend(im, Image.new("RGB", SIZE, IVORY), .42 * (1 - (t-shutter)/.12))
    return im


def draw_portrait(st, t, lang="en"):
    mt = source_time(t)
    w, h = SIZE
    copy = COPY[lang]
    chinese = lang == "zh-CN"
    display = "zh-serif" if chinese else "serif"
    ui = "zh" if chinese else "medium"
    if t < 1.55:
        k = s(t, 0, 1.55)
        im = st.physical(mt, SIZE, (mix(779, 776, k), 431), mix(560, 675, k))
        lower_shade(im, .95)
        brandbug(im, 62, 91, 58, True)
        txt(im, (59, 1357), copy["opening"], 115 if chinese else 119, display, IVORY, "lt")
        txt(im, (65, 1527 if chinese else 1500), copy["purpose"],
            40 if chinese else 42, ui, IVORY, "lt")
    elif t < 3.03 or 4.07 <= t < 4.83:
        second = t >= 4.07
        im = Image.new("RGB", SIZE, "#E1E7E7" if second else "#F6F2E9")
        brandbug(im, 62, 99, 55)
        label = "line" if second else "capture"
        point_size = (112 if second else 150) if chinese else (120 if second else 169)
        txt(im, (60, 350), copy[label], point_size, display, INK, "lt")
        im = photo(im, st.b if second else st.a, t, 4.07 if second else 1.55, 4.43 if second else 2.53)
        if second:
            txt(im, (62, 1328), copy["proof"], 42, ui, INK, "lt")
        elif chinese:
            txt(im, (62, 1328), "⇧   ⌘   4", 47, "keys", INK, "lt")
        else:
            txt(im, (62, 1328), "Shift + Command + 4", 42, ui, INK, "lt")
    elif t < 6.60:
        im = viewport(st.empty, 2690, 952, 590, SIZE)
        brandbug(im, 65, 101, 54, True)
        txt(im, (60, 330), copy["two" if t >= 4.83 else "one"], 137 if chinese else 165,
            display, IVORY, "lt")
        txt(im, (68, 532), copy["tray"], 43, ui, IVORY, "lt")
        plate = st.tray.render(mt)
        scale = 3.28 + .07*s(t, 3.03, 6.6)
        plate = plate.resize((round(330*scale), round(296*scale)), Image.Resampling.LANCZOS)
        on_disk(im, plate, (w-330*scale)/2, 1150-180*scale)
    elif t < 7.01:
        im = viewport(st.finger, 935, 485, 614, SIZE)
        lower_shade(im, .85)
        txt(im, (59, 1350), copy["click"], 147 if chinese else 160, display, IVORY, "lt")
    elif t < 9.55:
        # Simultaneous editorial views of the original tray and current browser.
        im = Image.new("RGB", SIZE, IVORY)
        im.paste(st.world_view(mt, 1340, 469, 288, (w, 792)), (0, 0))
        txt(im, (57, 857), copy["draft" if mt < 13.45 else "attached"],
            98 if chinese else 112, display, INK, "lt")
        window = draw_window(mt, st.a, scale=2, lang=lang)
        draft = window.crop((0, 140, 1280, 1040)).convert("RGB")
        im.paste(draft.resize((1080, 759), Image.Resampling.LANCZOS), (0, 1015))
    elif t < 12:
        im = Image.new("RGB", SIZE, IVORY)
        txt(im, (62, 293), copy["continue"], 148 if chinese else 166, display, INK, "lt")
        window = draw_window(mt, st.a, scale=2, lang=lang)
        on_disk(im, window.resize((1000, 875), Image.Resampling.LANCZOS), 40, 595)
        txt(im, (60, 1530), copy["benefit"], 59 if chinese else 55, display, INK, "lt")
    else:
        im = Image.new("RGB", SIZE, IVORY)
        a = s(t, 12, 12.37)
        on_disk(im, mark(156), (w-156)/2, 535+(1-a)*28)
        txt(im, (540, 755), "Riftlet", 205, "serif", INK, "mt")
        p = s(t, 12.30, 12.75)
        col = tuple(round(mix(v, b, p)) for v, b in zip((252, 251, 248), (27, 52, 45)))
        txt(im, (540, 1042), copy["signature"], 66 if chinese else 64,
            "zh-serif" if chinese else "sans", col, "mt")
        q = s(t, 12.8, 13.16)
        col = tuple(round(mix(v, b, q)) for v, b in zip((252, 251, 248), (36, 91, 76)))
        txt(im, (540, 1350), "riftlet.com", 64, "medium", col, "mt")
        txt(im, (540, 1447), copy["download"], 37 if chinese else 35, "zh" if chinese else "sans", col, "mt")
    return im


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lang", required=True, choices=tuple(COPY))
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    target = args.out or ROOT / "films" / args.lang / "riftlet-vertical.mp4"
    target.parent.mkdir(parents=True, exist_ok=True)
    encode(partial(draw_portrait, lang=args.lang), Set(args.lang), 450, SIZE,
           ART / "score-vertical.wav", target)
