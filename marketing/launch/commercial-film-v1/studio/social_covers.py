"""Render localized publishing artwork from the editable commercial layers."""
from functools import lru_cache
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

from chrome.composer import draw_window
from sets import ART, INK, ROOT, arrow, font, mark
from tray.tray import Tray


WHITE = '#FFFCF3'
PALE = '#C3D7CD'
ACCENT = '#63DCC6'
RESAMPLE = Image.Resampling.LANCZOS


@lru_cache(maxsize=96)
def cover_font(style, size):
    if style not in ('headline', 'copy'):
        return font(style, size)
    # Font collections move between macOS releases. Select the face by name.
    weight = 'Semibold' if style == 'headline' else 'Medium'
    path, indices = pingfang()
    return ImageFont.truetype(str(path), size, index=indices[weight])


@lru_cache
def pingfang():
    candidates = [Path('/System/Library/Fonts/PingFang.ttc')]
    candidates += sorted(Path('/System/Library/AssetsV2').glob(
        'com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc'))
    for path in candidates:
        if path.exists():
            indices = {}
            for i in range(64):
                try:
                    family, weight = ImageFont.truetype(str(path), 20, index=i).getname()
                except OSError:
                    break
                if family == 'PingFang SC':
                    indices[weight] = i
            if {'Medium', 'Semibold'} <= indices.keys():
                return path, indices
    raise FileNotFoundError('Install the macOS PingFang SC font to render this artwork.')


class Cover:
    def __init__(self, width, height, pixel_width):
        self.scale = pixel_width / width
        self.im = Image.new('RGB', self.p((width, height)), INK)
        self.d = ImageDraw.Draw(self.im)

    def p(self, values):
        return tuple(round(v * self.scale) for v in values)

    def line(self, vertices, color, weight=1):
        self.d.line([self.p(p) for p in vertices], fill=color,
                    width=max(1, round(self.scale * weight)), joint='curve')

    def type(self, x, y, text, size, style, color, max_width=None, anchor='lt'):
        face = cover_font(style, round(size * self.scale))
        if max_width is not None and face.getlength(text) > max_width * self.scale:
            size *= max_width * self.scale / face.getlength(text)
            face = cover_font(style, int(size * self.scale))
        self.d.text(self.p((x, y)), text, font=face, fill=color, anchor=anchor)

    def image(self, im, x, y, width, height=None):
        height = width * im.height / im.width if height is None else height
        layer = im.resize(self.p((width, height)), RESAMPLE)
        self.im.paste(layer, self.p((x, y)), layer if layer.mode == 'RGBA' else None)

    def brand(self, x, y, size):
        self.image(mark(round(size * self.scale)), x, y, size)
        self.type(x + size * 1.26, y + size * .02, 'Riftlet', size * 1.04,
                  'serif', WHITE)

    def picture(self, box, center=(.57, .38)):
        x, y, w, h = box
        src = rider()
        # The rider, the selected tray cell and the attachment are one image.
        shot = ImageOps.fit(src, self.p((w, h)), method=RESAMPLE,
                            centering=center)
        self.im.paste(shot, self.p((x, y)))
        # A light area-selection outline ties the photograph to the Mac capture.
        margin, arm = w * .073, min(w, h) * .066
        for u, dx in ((x+margin, 1), (x+w-margin, -1)):
            for v, dy in ((y+margin, 1), (y+h-margin, -1)):
                self.line([(u+arm*dx, v), (u, v), (u, v+arm*dy)], WHITE, 1.8)

    def tray(self, x, y, width):
        # x, y and width describe the native glass, including all three cells.
        ratio = width / 246
        self.image(tray_plate(), x-42*ratio, y-42*ratio, 330*ratio)
        arrow(self.im, *self.p((x+(105.75-42)*ratio, y+(99-42)*ratio)),
              1.45*ratio*self.scale)

    def draft(self, lang, x, y, width):
        self.image(composer(lang), x, y, width)


@lru_cache
def rider():
    return Image.open(ART/'banked.png').convert('RGB')


@lru_cache
def tray_plate():
    return Tray(ART/'banked.png', ART/'infield.png').render(13.2)


@lru_cache
def composer(lang):
    # Clip along the real draft border. The page around the field is white.
    s = 4
    win = draw_window(16.25, rider(), s, lang=lang)
    box = (42, 257, 598, 425)
    face = win.crop(tuple(v*s for v in box))
    mask = Image.new('L', face.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, face.width-1, face.height-1),
                                           radius=26*s, fill=255)
    face.putalpha(mask)
    # Keep the fine edge of the composer visible against the dark cover.
    pad = 18*s
    layer = Image.new('RGBA', (face.width+2*pad, face.height+2*pad))
    shadow = Image.new('RGBA', layer.size)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad+4*s, pad+face.width, pad+face.height+4*s),
        radius=26*s, fill=(26, 43, 35, 32))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(8*s)))
    layer.alpha_composite(face, (pad, pad))
    return layer


def attachment_path(cover, start, end):
    # Printed annotation in the space between the two successive product states.
    x0, y0 = start
    x1, y1 = end
    reach = (x0-x1) * .47
    points = []
    for sample in range(61):
        t = sample / 60
        u = 1 - t
        x = u**3*x0 + 3*u*u*t*(x0-reach) + 3*u*t*t*(x1+reach) + t**3*x1
        y = (u**3+3*u*u*t)*y0 + (3*u*t*t+t**3)*y1
        points.append((x, y))
    cover.line(points, ACCENT, 3)
    cover.line([(x1+10, y1-8), (x1, y1), (x1+10, y1+8)], ACCENT, 3)


def landscape(lang, height, pixel_width):
    width = 1200
    cover = Cover(width, height, pixel_width)
    chinese = lang == 'zh-CN'
    four_three = height == 900
    photo_x = 718 if chinese else 732
    photo_height = 508 if four_three else 329
    cover.picture((photo_x, 0, width-photo_x, photo_height), center=(.57, .28))
    cover.brand(48, 54 if four_three else 32, 48 if four_three else 40)
    cover.type(photo_x-30, 84 if four_three else 54, 'riftlet.com', 20,
               'medium', PALE, anchor='rm')

    title_y = 153 if four_three else 115
    if chinese:
        cover.type(43, title_y, 'Mac 截图', 99 if four_three else 85, 'headline', WHITE)
        cover.type(41, title_y+(118 if four_three else 96), '一点就进 ChatGPT',
                   84 if four_three else 75, 'headline', ACCENT, photo_x-76)
        cover.type(48, title_y+(253 if four_three else 201), '不用找文件、切窗口、拖图。',
                   39 if four_three else 34, 'copy', WHITE)
    else:
        cover.type(43, title_y-14, 'Mac screenshots.', 86, 'serif', WHITE, photo_x-75)
        cover.type(43, title_y+73, 'One click to ChatGPT.', 73, 'bold', ACCENT, photo_x-66)
        cover.type(47, title_y+195, 'No file hunting. No dragging.', 34, 'medium', WHITE)

    tray_x = 831
    tray_width = 304 if four_three else 254
    tray_y = photo_height - (77 if four_three else 45)
    tray_bottom = tray_y + tray_width*212/246
    caption_face = 'copy' if chinese else 'medium'
    cover.tray(tray_x, tray_y, tray_width)
    cover.type(tray_x+tray_width/2, tray_bottom+20,
               '点选托盘里的截图' if chinese else 'Pick a screenshot',
               33 if four_three else 29, caption_face, WHITE, anchor='mt')

    draft_y = 579 if four_three else 421
    draft_width = 718 if four_three else 691
    cover.type(47, draft_y-45,
               '截图进草稿，在 Chrome 里接着写' if chinese else 'Attached to your draft in Chrome',
               34 if four_three else 29, caption_face, WHITE)
    cover.draft(lang, 24, draft_y, draft_width)
    attachment_path(cover, (tray_x-15, tray_y+tray_width*.48),
                    (31+draft_width*.97, draft_y+draft_width*.11))
    return cover.im


def portrait():
    w, h = 720, 960
    cover = Cover(w, h, 1440)
    cover.brand(36, 26, 43)
    cover.type(680, 47, 'riftlet.com', 23, 'medium', PALE, anchor='rm')
    cover.type(31, 96, 'Mac 截图', 83, 'headline', WHITE)
    cover.type(30, 191, '一点就进 ChatGPT', 78, 'headline', ACCENT, 660)
    cover.type(36, 278, '不用找文件、切窗口、拖图。', 39, 'copy', WHITE)
    cover.picture((0, 351, w, 250), center=(.56,.14))
    # Keep the rider's head and the two tray thumbnails clear at feed size.
    cover.tray(39, 475, 224)
    cover.type(306, 637, '点选托盘里的截图', 38, 'copy', WHITE)
    cover.line([(273, 647), (288, 647)], ACCENT, 2.2)
    cover.line([(280, 641), (273, 647), (280, 653)], ACCENT, 2.2)
    cover.type(38, 710, '截图进草稿，在 Chrome 里接着写', 35, 'copy', WHITE,
               max_width=649)
    cover.draft('zh-CN', 17, 734, 640)
    return cover.im


def save(im, name):
    out = ROOT/'social-covers'/name
    out.parent.mkdir(exist_ok=True)
    profile = Path('/System/Library/ColorSync/Profiles/sRGB Profile.icc').read_bytes()
    for quality in (94, 92, 90, 88, 85):
        data = BytesIO()
        im.save(data, 'JPEG', quality=quality, subsampling=0, optimize=True,
                progressive=True, icc_profile=profile)
        if data.tell() < 2_000_000:
            out.write_bytes(data.getvalue())
            return
    raise ValueError(f'{name} exceeds the mobile upload size at quality 85')


def main():
    save(landscape('zh-CN', 900, 1920), 'bilibili-feed-zh-CN.jpg')
    save(landscape('zh-CN', 675, 1920), 'bilibili-player-zh-CN.jpg')
    save(portrait(), 'xiaohongshu-zh-CN.jpg')
    save(landscape('en', 675, 3840), 'youtube-en.jpg')


if __name__ == '__main__':
    main()
