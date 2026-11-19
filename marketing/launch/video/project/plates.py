"""Draw the two original illustrative tide plates used as screenshot subjects."""
from pathlib import Path

import contourpy
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

KIT = Path(__file__).resolve().parents[2]
SITE = KIT.parents[1] / "website-assets" / "fonts"
WORK = KIT.parents[1] / "build" / "launch-production"
OUTPUT = KIT / "source" / "plates"
PAPER = "#FCFBF8"
INK = "#102A27"
SANS = "/System/Library/Fonts/HelveticaNeue.ttc"
MONO = "/System/Library/Fonts/SFNSMono.ttf"


def roman(italic=False):
    stem = "instrument-serif" + ("-italic" if italic else "")
    target = WORK / (stem + ".ttf")
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        face = TTFont(SITE / (stem + ".woff2"))
        face.flavor = None
        face.save(target)
    return str(target)


def relief(x, y):
    # A gently meandering channel with a narrow saddle and exposed banks.
    mid = .55 + .22 * np.sin(x * 5.9 - .9) - .10 * np.cos(x * 9.6 + y * 2.1)
    banks = (np.abs(y - mid) - (.14 + .10 * np.cos(x * 4.8))) * 2.3
    ripple = .065 * np.sin(x * 18 - y * 11) + .04 * np.cos(y * 20 + .6 * np.sin(x * 13))
    shoal = .41 * np.exp(-((x - .57) / .13) ** 2 - ((y - .51) / .09) ** 2)
    return banks + ripple + shoal - .22 * x


def draw_plate(high):
    width, height = 1200, 800
    s = 2
    w, h = width * s, height * s
    fieldw, fieldh = w, 598 * s
    x = np.linspace(-.06, 1.07, fieldw)
    y = np.linspace(-.07, 1.03, fieldh)
    xx, yy = np.meshgrid(x, y)
    z = relief(xx, yy) - (.23 if high else -.015)
    steps = [-.65, -.45, -.29, -.17, -.08, 0, .12, .29, .5]
    colors = ["#174C4A", "#23635E", "#30776E", "#438C7F", "#67A499", "#A2BFB0",
              "#DFD4AE", "#E7DDB9", "#EEE5C9", "#F3EBD2"]
    swatch = np.array([tuple(bytes.fromhex(c[1:])) for c in colors], dtype=np.uint8)
    raster = swatch[np.digitize(z, steps)]
    im = Image.new("RGB", (w, h), PAPER)
    im.paste(Image.fromarray(raster), (0, 0))
    d = ImageDraw.Draw(im, "RGBA")
    cx = np.linspace(0, fieldw, 220)
    cy = np.linspace(0, fieldh, 128)
    gx, gy = np.meshgrid(x[0] + (x[-1]-x[0])*cx/fieldw, y[0] + (y[-1]-y[0])*cy/fieldh)
    contour = contourpy.contour_generator(x=cx, y=cy, z=relief(gx, gy)-(.23 if high else -.015))
    for j, level in enumerate(np.arange(-.74, 1.51, .030)):
        for segment in contour.lines(level):
            if len(segment) < 2:
                continue
            points = [tuple(p) for p in segment]
            color = (227, 245, 217, 110) if level < 0 else (111, 104, 71, 90)
            d.line(points, fill=color, width=(2 if j % 5 == 0 else 1))
    def font(face, size):
        return ImageFont.truetype(face, int(size*s))
    def text(xy, t, face, size, col=INK, **kw):
        d.text(tuple(int(n*s) for n in xy), t, font=font(face, size), fill=col, **kw)
    def line(coords, color, weight=1):
        d.line(tuple(int(n*s) for n in coords), fill=color, width=weight*s)
    # The datum is fixed on both plates, as in a paired field observation.
    for xmark, ymark in ((681, 275), (773, 373)):
        d.ellipse(((xmark-7)*s, (ymark-7)*s, (xmark+7)*s, (ymark+7)*s), fill="#EE7247", outline=PAPER, width=2*s)
    line((1080, 546, 1150, 546), PAPER, 2)
    line((1080, 540, 1080, 546), PAPER, 2)
    line((1150, 540, 1150, 546), PAPER, 2)
    text((49, 629), "TIDAL STUDIES     /     MERIDIAN INLET", MONO, 16, "#416158")
    text((47, 654), "High water" if high else "Low water", roman(), 97)
    text((1150, 644), "PLATE  II" if high else "PLATE  I", MONO, 18, "#416158", anchor="ra")
    text((1150, 708), "Water at the saddle" if high else "The exposed saddle", roman(True), 37, INK, anchor="ra")
    im.resize((width, height), Image.Resampling.LANCZOS).save(OUTPUT / ("high.png" if high else "low.png"), optimize=True)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for condition in (False, True):
        draw_plate(condition)
