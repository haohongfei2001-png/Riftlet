"""Transparent, four-times-resolution movie plate for the violet 0.3.5 (20) screenshot tray.

Coordinates are the 246-unit reference in RiftTrayLayout.swift. The returned 330×296-unit
plate has an invariant glass left x=42 and lower edge y=254 (origin is top left).
This module consumes the two very PNGs used in the film's source view and draft chip.
"""
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SCALE = 4
CANVAS = (330 * SCALE, 296 * SCALE)
GLASS_LEFT, GLASS_BOTTOM = 42, 254
SLOT_WIDTH, SLOT_HEIGHT = 113.5, 80

@dataclass(frozen=True)
class Timing:
    first: float = 5.55
    second: float = 8.55
    press: float = 13.20
    attachment_start: float = 13.45
    refill: float = 14.70  # after mouse has left and the OS double-click guard expires

def px(value):
    return round(value * SCALE)

def blank():
    return Image.new("RGBA", CANVAS)

def rounded_mask(size, xy, radius):
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).rounded_rectangle(tuple(px(v) for v in xy), radius=px(radius), fill=255)
    return mask

def tint(mask, rgba):
    paint = Image.new("RGBA", mask.size, (*rgba[:3], 0))
    paint.putalpha(mask.point(lambda a: round(a * rgba[3] / 255)))
    return paint

def progress(t, since, duration):
    return min(1.0, max(0.0, (t - since) / duration))

def cubic(t):
    return 1 - (1 - t) ** 3

def mix(a, b, t):
    return a + (b - a) * t

def ease_in_out(t):
    # Core Animation's built-in easeInEaseOut uses these control points.
    low, high = 0.0, 1.0
    for _ in range(13):
        v = (low + high) * 0.5
        x = 3 * (1-v)**2 * v * .42 + 3 * (1-v) * v*v * .58 + v**3
        if x < t:
            low = v
        else:
            high = v
    v = (low + high) / 2
    return 3 * (1-v) * v*v + v**3

@lru_cache(maxsize=28)
def surface(height_pixels):
    layer = blank()
    top = GLASS_BOTTOM - height_pixels / SCALE
    box = (GLASS_LEFT, top, GLASS_LEFT+246, GLASS_BOTTOM)
    silhouette = rounded_mask(CANVAS, box, 24)
    # Native decoration panel and the lower-radius contact edge of the glass window.
    cast = rounded_mask(CANVAS, (box[0], box[1]+10.5, box[2], box[3]+10.5), 24)
    layer.alpha_composite(tint(cast.filter(ImageFilter.GaussianBlur(px(11))), (13,15,38,51)))
    contact = rounded_mask(CANVAS, (box[0], box[1]+1, box[2], box[3]+1), 24)
    layer.alpha_composite(tint(contact.filter(ImageFilter.GaussianBlur(px(1.25))), (7,10,22,43)))
    # Exterior cast must not darken the translucent fill inside the glass.
    layer.paste((0,0,0,0), mask=silhouette)
    wash = Image.new("RGBA", CANVAS, (239,240,253,0))
    gradient = Image.new("L", (1, height_pixels+1))
    gradient.putdata([round(138 - 3*y/max(1,height_pixels)) for y in range(height_pixels+1)])
    alpha = Image.new("L", CANVAS, 0)
    alpha.paste(gradient.resize((px(246)+1, height_pixels+1)), (px(box[0]), px(box[1])))
    wash.putalpha(alpha)
    wash = Image.composite(wash, blank(), silhouette)
    layer.alpha_composite(wash)
    line = Image.new("RGBA", CANVAS)
    ImageDraw.Draw(line).rounded_rectangle(tuple(px(v) for v in box), radius=px(24),
                                          outline=(255,255,255,54), width=px(.75))
    layer.alpha_composite(line)
    return layer

def load_art(art):
    if isinstance(art, Image.Image):
        return art.convert("RGBA")
    with Image.open(art) as image:
        return image.convert("RGBA")

def card(art, *, pressed=False, hovered=False):
    # Actual rows use a 4pt input/paint window outset and only the backing corners are rounded.
    width, height = SLOT_WIDTH, SLOT_HEIGHT
    size = (px(width + 8), px(height + 8))
    rim, foot = 2.75, .75
    factor = min((width-2*rim)/art.width, (height-2*rim-foot)/art.height)
    w, h = art.width * factor, art.height * factor
    left = 4 + (width - w) / 2
    top = 4 + (height - h - foot) / 2
    box = (left-rim, top-rim, left+w+rim, top+h+rim+foot)
    radius = (box[2]-box[0])*9/114
    shadow_offset = .5 if pressed else 1.5
    shadow_radius = 1 if pressed else min(3,radius/3)
    shadow = rounded_mask(size, (box[0],box[1]+shadow_offset,box[2],box[3]+shadow_offset), radius)
    layer = tint(shadow.filter(ImageFilter.GaussianBlur(px(shadow_radius))), (51,48,86,38))
    backing = rounded_mask(size, box, radius)
    layer.alpha_composite(tint(backing, (234,232,253,255)))
    layer.alpha_composite(art.resize((max(1,px(w)),max(1,px(h))), Image.Resampling.LANCZOS),
                          (px(left),px(top)))
    rim_layer = Image.new("RGBA", size)
    ImageDraw.Draw(rim_layer).rounded_rectangle(tuple(px(v) for v in box), radius=px(radius),
                                              outline=(255,255,255,214 if hovered else 128),width=2)
    layer.alpha_composite(rim_layer)
    return layer, w

@lru_cache(maxsize=1)
def camera_key():
    with Image.open(Path(__file__).parent/"plates"/"camera.png") as original:
        rgba = original.convert("RGBA")
    # The exported native button face is padded 7 units for the cast shadow.
    mask = rounded_mask(rgba.size, (7,8.8,7+SLOT_WIDTH,8.8+SLOT_HEIGHT), 12)
    result = tint(mask.filter(ImageFilter.GaussianBlur(px(2.4))), (46,41,74,38))
    result.alpha_composite(rgba)
    return result

class Tray:
    """render(t) -> immutable RGBA plate. Reposition or resize to suit the virtual camera."""
    def __init__(self, first_png, second_png, timing=Timing()):
        self.time = timing
        a,b = load_art(first_png),load_art(second_png)
        self._first, self._image_width = card(a)
        self._hover, _ = card(a, hovered=True)
        self._pressed, _ = card(a, pressed=True, hovered=True)
        self._second, _ = card(b)

    def geometry(self, t):
        k = self.time
        # Local coordinates for top left of the two queue columns; the camera acts as one slot.
        left, right = 49., 167.5
        lower, upper = 156., 59.
        camera_x, camera_y = left, lower
        first_id, second_id = None, None
        h = 115.
        if t >= k.first:
            kr = ease_in_out(progress(t,k.first,.18))
            camera_x = mix(left,right,kr)
            first_id = (left,lower)
        if t >= k.second:
            mov = cubic(progress(t,k.second,.16))
            key = ease_in_out(progress(t,k.second,.18))
            h = mix(115,212,mov)
            first_id = (left,mix(lower,upper,mov))
            second_id = (right,upper)
            camera_x = mix(right,left,key)
        if t >= k.attachment_start + .12:
            first_id = None
        if t >= k.refill:
            mov = cubic(progress(t,k.refill,.16))
            key = ease_in_out(progress(t,k.refill,.18))
            h = mix(212,115,mov)
            second_id = (mix(right,left,mov),mix(upper,lower,mov))
            camera_x = mix(left,right,key)
        return {"glass": (GLASS_LEFT,GLASS_BOTTOM-h,246,h), "first": first_id, "second": second_id,
                "camera": (camera_x,camera_y)}

    def _frame(self, t):
        k, geo = self.time, self.geometry(t)
        layer = surface(px(geo["glass"][3])).copy()
        x,y = geo["camera"]
        layer.alpha_composite(camera_key(), (px(x-7),px(y-7)))
        if geo["first"]:
            x,y = geo["first"]
            first = self._first
            if k.press-.09 <= t < k.press:
                first = self._hover
            elif k.press <= t < k.press+.09:
                first = self._pressed
            if t >= k.attachment_start:
                s = progress(t,k.attachment_start,.12)
                # Translate + fade inside the original screenshot's stationary row window.
                masked = Image.new("RGBA", first.size)
                masked.alpha_composite(first, (px((self._image_width + 4) * s**1.35),0))
                masked.putalpha(masked.getchannel("A").point(lambda a: int(a*(1-s))))
                first = masked
            layer.alpha_composite(first,(px(x-4),px(y-4)))
        if geo["second"]:
            x,y = geo["second"]
            layer.alpha_composite(self._second,(px(x-4),px(y-4)))
        return layer

    @lru_cache(maxsize=36)
    def render(self, t):
        # Most of the film holds an unchanged product state. Canonical keys make
        # this inexpensive even when a compositor samples at fractional shutter times.
        k = self.time
        if t < k.first:
            return self._still("empty")
        if k.first+.19 <= t < k.second:
            return self._still("one")
        if k.second+.19 <= t < k.press-.09:
            return self._still("two")
        if k.press+.09 <= t < k.attachment_start:
            return self._still("two")
        if k.attachment_start+.12 <= t < k.refill:
            return self._still("tombstone")
        if t >= k.refill+.19:
            return self._still("remaining")
        return self._frame(t)

    @lru_cache(maxsize=5)
    def _still(self, name):
        t = self.time
        lookup = {"empty":t.first-1,"one":t.first+.2,"two":t.second+.2,
                  "tombstone":t.attachment_start+.13,"remaining":t.refill+.2}
        return self._frame(lookup[name])
