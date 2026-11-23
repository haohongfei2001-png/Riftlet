"""Bilingual 16:9 title art and fifth Xiaohongshu spread, using campaign graphic primitives."""

from argparse import ArgumentParser
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent
SIGNED_REFERENCE = ROOT.parents[3] / "docs/releases/1.0.4/evidence/signed-rc27"
NATIVE_IMAGE = {"tray": "desktop-tray-3.png", "slit": "desktop-dark-rightMiddle-microSlit.png"}


def load_style(module_path, assets):
    spec = spec_from_file_location("campaign_style", module_path)
    style = module_from_spec(spec)
    spec.loader.exec_module(style)
    style.ASSETS = assets
    return style


def cropped_thumbnail(chart, width):
    scale = width * g.S / chart.width
    tile = chart.resize((round(chart.width * scale), round(chart.height * scale)), g.R)
    return tile.crop((0, 0, round(tile.width * 0.75), tile.height))


def draft_after(en):
    art = g.paper(405, 149, "#FFFEF8")
    g.text(art, 16, 12, "ChatGPT", 15, "bold")
    label = "Current draft" if en else "当前草稿"
    g.text(art, 390, 14, label, 11, "latin" if en else "zh", g.MUTE, "rt")
    g.line(art, [(0, 35), (405, 35)], "#D7DFD3")
    for index, old in enumerate([True, False]):
        img = g.chart(en, old).resize(g.pix(83, 47), g.R)
        g.paste(art, img, 16 + index * 90, 45)
    question = "Why did Wednesday dip?" if en else "为什么周三下滑？"
    text_width = g.text(art, 16, 111, question, 18, "latin" if en else "zh")
    g.line(art, [(19 + text_width, 108), (19 + text_width, 128)], "#367C5C", 1)
    g.circle(art, 377, 119, 10, "#24483D")
    g.line(art, [(377, 123), (377, 115)], g.PAPER, 1.35)
    g.line(art, [(373, 119), (377, 115), (381, 119)], g.PAPER, 1.35)
    return art


def product_scene(poster, en):
    # A slice of a report beside its active draft. Its screenshot only appears inside the edge.
    x, y, w, h = 493, 74, 428, 352
    g.rect(poster, (x, y, x + w, y + h), "#31584B", 15)
    chart = g.chart(en)
    g.mounted(poster, chart, x + 15, y + 13, 347, 3)
    edge_x = x + w - 14
    g.line(poster, [(edge_x, y + 46), (edge_x, y + 211)], "#D7ECDD", 0.9)
    tile = cropped_thumbnail(chart, 118)
    tile_width, tile_height = [n / g.S for n in tile.size]
    tile_x, tile_y = edge_x - tile_width, y + 92
    g.rect(poster, (tile_x - 1.5, tile_y - 1.5, edge_x, tile_y + tile_height + 1.5), "#F3F4E7", 2)
    g.paste(poster, tile, tile_x, tile_y)
    # Ordinal belongs to the exposed picture; keep it outside the clipped bitmap.
    g.text(poster, tile_x - 5, tile_y + tile_height / 2, "1", 11, "mono", "#EDF8EA", "rm")
    g.pointer(poster, tile_x + 48, tile_y + 39, 0.67)
    g.mounted(poster, draft_after(en), x + 12, y + 194, 401)


def cover(en):
    art = g.paper(960, 540, "#102D28")
    g.brand(art, 40, 33, dark=True, size=32)
    g.text(art, 920, 44, "riftlet.com", 16, "latin", "#CCE1D0", "rt")
    if en:
        g.text(art, 38, 112, "Just took a", 59, "serif", g.PAPER)
        g.text(art, 37, 170, "screenshot?", 75, "italic", "#ADE6C4")
        g.text(art, 40, 263, "One click adds it", 46, "bold", g.PAPER, maxw=431)
        g.text(art, 40, 319, "to ChatGPT.", 46, "bold", g.PAPER)
    else:
        g.text(art, 37, 110, "刚截的图，", 71, "song", g.PAPER)
        g.text(art, 40, 201, "点一下就进", 65, "zh", g.PAPER)
        length = g.text(art, 36, 275, "ChatGPT", 107, "italic", "#ADE6C4")
        g.text(art, 43 + length, 346, "。", 35, "song", "#ADE6C4")
    product_scene(art, en)
    g.line(art, [(40, 451), (920, 451)], "#5A7C6E")
    if en:
        g.text(
            art,
            40,
            471,
            "Click the edge thumbnail. Keep writing in the same draft.",
            21,
            "latin",
            g.PAPER,
            maxw=790,
        )
        g.text(art, 40, 505, "Mac · ChatGPT in Chrome", 14, "latin", "#AEC9B9")
        g.text(art, 920, 505, "Illustrated scene", 12, "latin", "#AEC9B9", "rt")
    else:
        g.text(art, 40, 466, "点屏幕边缘的缩略图，附加到当前草稿。", 25, "zh", g.PAPER)
        g.text(art, 40, 505, "Mac · Chrome 网页版 ChatGPT", 14, "zh", "#AEC9B9")
        g.text(art, 920, 505, "场景示意", 12, "zh", "#AEC9B9", "rt")
    return art


def native_print(poster, name, destination):
    asset = Image.open(SIGNED_REFERENCE / NATIVE_IMAGE[name]).convert("RGBA")
    # Only the image wells receive our report, maintaining the signed sample's
    # native border, shade, cut-off, ordinal, relative position and empty area.
    if name == "tray":
        wells = [(15, 39, 175, 132), (246, 31, 300, 140), (91, 177, 99, 286)]
        sources = [g.chart(), g.chart(old=True), g.chart()]
    else:
        wells = [(78, 247, 181, 257), (78, 333, 181, 412), (144, 438, 181, 552)]
        sources = [g.chart(old=True), g.chart(), g.chart(old=True)]
    for bounds, source in zip(wells, sources):
        rect = (bounds[2] - bounds[0], bounds[3] - bounds[1])
        bitmap = ImageOps.fit(source, rect, method=g.R)
        asset.paste(bitmap, bounds[:2])
    if name == "slit":
        asset = asset.crop((0, 225, 208, 556))
    asset = asset.crop(asset.getchannel("A").getbbox())
    w, h = destination[2] - destination[0], destination[3] - destination[1]
    factor = min(w * g.S / asset.width, h * g.S / asset.height)
    image = asset.resize((round(asset.width * factor), round(asset.height * factor)), g.R)
    x = destination[0] + (w - image.width / g.S) / 2
    y = destination[1] + (h - image.height / g.S) / 2
    g.paste(poster, image, x, y)


def appearance_page():
    art = g.paper(720, 960)
    g.brand(art)
    g.text(art, 677, 49, "外观", 19, "zh", g.MUTE, "rt")
    g.text(art, 40, 119, "连截几张，", 69, "song")
    g.text(art, 40, 207, "挑一张给草稿。", 66, "song", g.GREEN)
    g.text(art, 43, 314, "同一份截图队列，可以换一种外观。", 25, "zh")
    g.line(art, [(43, 365), (677, 365)], "#B5C9B7")
    g.text(art, 43, 387, "托盘", 32, "song")
    g.text(art, 374, 387, "微缝", 32, "song")
    g.text(art, 43, 432, "两列格位", 19, "zh", g.MUTE)
    g.text(art, 374, 432, "边缘纵列 · 局部放大", 19, "zh", g.MUTE)
    for x in (43, 374):
        g.rect(art, (x, 478, x + 303, 706), "#234B40", 10)
    native_print(art, "tray", (67, 500, 322, 687))
    native_print(art, "slit", (393, 488, 652, 698))
    g.text(art, 43, 751, "点中一张，后面的图就补位。", 34, "zh")
    g.text(art, 43, 808, "微缝里的图向上补，托盘里的图按格补齐。", 24, "zh")
    g.text(art, 43, 851, "每次使用一种外观，设置中另有风铃。", 22, "zh", g.MUTE)
    g.line(art, [(43, 905), (677, 905)], "#B5C9B7")
    g.text(art, 43, 923, "Mac · Chrome 网页版 ChatGPT", 16, "zh", g.MUTE)
    g.text(art, 677, 925, "原生外观 · 配图示意", 14, "zh", g.MUTE, "rt")
    return art


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--style", type=Path, default=ROOT / "render.py")
    parser.add_argument("--assets", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT)
    args = parser.parse_args()
    assets = args.assets or next(
        p / "website-assets" for p in ROOT.parents if (p / "website-assets/riftlet.svg").is_file()
    )
    g = load_style(args.style, assets)
    g.OUTPUT = args.output
    for language in ("zh-CN", "en"):
        g.export(cover(language == "en"), "covers/" + language + ".jpg", (1920, 1080))
    g.export(appearance_page(), "xiaohongshu/05-appearances.jpg", (1440, 1920))
