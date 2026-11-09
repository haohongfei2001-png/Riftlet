"""Count actual row pixels inside/outside the native tray, using saved exposures.

With a raw paired-capture directory as a second argument, reconstruct the
lossless evidence image. With the PNG alone, reproduce its counts. Requires
Pillow. No browser, screenshot permission or running application is needed.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops


def exposure(directory, name):
    with Image.open(directory / (name + ".png")) as source:
        return source.convert("RGBA")


def extract(directory):
    capture = json.loads((directory / "paired.json").read_text())
    if capture["beforeAll"] != capture["afterAll"]:
        raise ValueError("native windows changed during layer capture")
    first = exposure(directory, "pair-full-start")
    last = exposure(directory, "pair-full-end")
    if first.size != last.size or first.tobytes() != last.tobytes():
        raise ValueError("composed pixels changed during layer capture")
    shell = exposure(directory, "pair-glass-noshadow").getchannel("A")
    cards = exposure(directory, "pair-all-rows").getchannel("A")
    without = exposure(directory, "pair-no-rows").convert("RGB")
    if not all(im.size == first.size for im in (shell, cards, without)):
        raise ValueError("raw layers must have the same capture bounds")
    r, g, b = ImageChops.difference(first.convert("RGB"), without).split()
    delta = ImageChops.lighter(r, ImageChops.lighter(g, b))
    return Image.merge("RGB", (shell, cards, delta))


def measure(image):
    if image.mode != "RGB":
        raise ValueError("expected RGB = glass alpha, card alpha, maximum RGB difference")
    shell, card, delta = image.split()
    bands = [("outside", 0, 0), ("fringe1to127", 1, 127),
             ("fringe128to254", 128, 254), ("opaque", 255, 255)]
    result = {}
    for name, low, high in bands:
        region = shell.point(lambda alpha: 255 if low <= alpha <= high else 0)
        cards, diffs = card.histogram(region), delta.histogram(region)
        result[name] = {"areaPx": sum(cards), "cardAlphaNonzeroPx": sum(cards[1:]),
                        "compositeChangedPx": sum(diffs[1:]),
                        "maxCompositeDelta": max((i for i, n in enumerate(diffs) if n), default=0)}
    if not result["opaque"]["cardAlphaNonzeroPx"]:
        raise ValueError("empty card exposure")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("raw", type=Path, nargs="?")
    args = parser.parse_args()
    if args.raw:
        measured = extract(args.raw)
        if args.image.exists():
            with Image.open(args.image) as expected:
                if expected.mode != measured.mode or expected.size != measured.size or expected.tobytes() != measured.tobytes():
                    raise ValueError("stored planes differ from raw native layers")
        else:
            measured.save(args.image)
    with Image.open(args.image) as evidence:
        print(json.dumps(measure(evidence), indent=2))
