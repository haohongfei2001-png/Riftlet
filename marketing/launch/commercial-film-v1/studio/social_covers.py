"""Studio photographs, perspective-tracked desktop and editorial press close-up."""
from functools import lru_cache
from io import BytesIO
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

from chrome.composer import draw_window
from sets import ART, INK, ROOT, font, mark
from tray.tray import Tray


RESAMPLE = Image.Resampling.LANCZOS
FOREST = '#116555'
PAPER = (246, 249, 241)


@lru_cache
def pingfang():
    candidates = [Path('/System/Library/Fonts/PingFang.ttc')]
    candidates.extend(sorted(Path('/System/Library/AssetsV2').glob(
        'com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc')))
    for path in candidates:
        if not path.exists():
            continue
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
    raise FileNotFoundError('Install the macOS PingFang SC font to render the Chinese artwork.')


@lru_cache(maxsize=96)
def cover_font(style, size):
    if style not in ('headline', 'copy'):
        return font(style, size)
    path, indices = pingfang()
    return ImageFont.truetype(str(path), size,
                              index=indices['Semibold' if style == 'headline' else 'Medium'])


@lru_cache
def device(lang):
    with Image.open(ART/'social-mac-plate.png') as original:
        photo = original.convert('RGB')
    with Image.open(ART/'infield.png') as original:
        desktop = ImageOps.fit(original.convert('RGB'), (1520, 1000),
                               method=RESAMPLE, centering=(.25, .51))
    with Image.open(ART/'banked.png') as picture:
        chrome = draw_window(16.25, picture, 3, lang=lang).resize((1073, 939), RESAMPLE)
    desktop.paste(chrome, (66, 29), chrome)

    # Four interior display corners measured on the unlettered 1536x1024 plate.
    # Work above the source resolution so tab glyphs survive the YouTube export.
    oversample = 1.55
    photo = photo.resize(tuple(round(v*oversample) for v in photo.size), RESAMPLE)
    screen = np.float32([(122, 44), (1208, 108), (1281, 759), (178, 803)]) * oversample
    source = np.float32([(0, 0), (1519, 0), (1519, 999), (0, 999)])
    transform = cv2.getPerspectiveTransform(source, screen)
    projection = cv2.warpPerspective(np.asarray(desktop), transform, photo.size,
                                     flags=cv2.INTER_CUBIC)
    mask = np.zeros(photo.size[::-1], np.uint8)
    cv2.fillConvexPoly(mask, np.rint(screen).astype(np.int32), 255, lineType=cv2.LINE_AA)
    return Image.composite(Image.fromarray(projection), photo, Image.fromarray(mask))


@lru_cache
def pointer():
    # A cut path on the enamel pointer photograph. It is artwork resting over
    # the native press point, independent of the software cursor and glass.
    with Image.open(ART/'social-pointer-plate.png') as original:
        image = original.convert('RGBA')
    contour = [(122,260),(135,119),(139,111),(146,106),(157,105),(168,109),
               (1024,624),(1037,633),(1042,646),(1043,663),(1033,720),(1027,735),
               (1016,745),(840,777),(933,913),(943,933),(942,958),(933,1035),
               (926,1047),(911,1058),(751,1124),(733,1127),(719,1123),(707,1116),
               (527,863),(317,1004),(298,1010),(285,1007),(277,1000),(273,990),
               (123,272)]
    mask = Image.new('L', image.size)
    ImageDraw.Draw(mask).polygon(contour, fill=255)
    image.putalpha(mask.filter(ImageFilter.GaussianBlur(.9)))
    return image


@lru_cache
def press():
    return Tray(ART/'banked.png', ART/'infield.png').render(13.20)


class Cover:
    def __init__(self, width, height, pixel_width):
        self.s = pixel_width/width
        self.width, self.height = width, height
        self.size = self.px(width, height)
        self.image = Image.new('RGB', self.size, PAPER)

    def px(self, *values):
        return tuple(round(v*self.s) for v in values)

    def photograph(self, lang, x, y, width, tilt=False):
        # Extend the real studio sweep beyond the crop. Keep the contact shadow
        # and metal edge from the photograph itself, including along the trim.
        photo = device(lang)
        ratio = width*self.s/photo.width
        matrix = np.float32([[ratio, 0, x*self.s], [0, ratio, y*self.s]])
        pixels = cv2.warpAffine(np.asarray(photo), matrix, self.size,
                                flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
        set_image = Image.fromarray(pixels)
        # Sample an edge extension with a soft filter so grain does not stretch
        # out into long stripes across the extra negative space.
        small = (round(self.width/3), round(self.height/3))
        xx, yy = np.meshgrid(np.linspace(0, self.width, small[0]),
                             np.linspace(0, self.height, small[1]))
        dx = np.maximum(x-xx, 0)
        dy = np.maximum(y-yy, 0)
        distance = np.hypot(dx, dy)
        def field(value):
            return Image.fromarray(np.uint8(np.clip(value, 0, 1)*255)).resize(
                self.size, Image.Resampling.BICUBIC)
        softened = set_image.resize(small, Image.Resampling.BOX).filter(
            ImageFilter.GaussianBlur(2.2)).resize(self.size, Image.Resampling.BICUBIC)
        set_image.paste(softened, (0, 0), field(distance/28))
        set_image.paste(PAPER, (0, 0, *self.size), field(1-np.exp(-distance/180)))
        if tilt:
            rotation = cv2.getRotationMatrix2D(self.px(393, 650), -5, 1.04)
            rotation[1, 2] += self.px(20)[0]
            set_image = Image.fromarray(cv2.warpAffine(
                np.asarray(set_image), rotation, self.size, flags=cv2.INTER_CUBIC,
                borderMode=cv2.BORDER_REPLICATE))
        self.image = set_image

    def layer(self, picture, x, y, width):
        layer = picture.resize(self.px(width, width*picture.height/picture.width), RESAMPLE)
        self.image.paste(layer, self.px(x, y), layer)

    def text(self, x, y, message, size, face, color=INK):
        ImageDraw.Draw(self.image).text(
            self.px(x, y), message, font=cover_font(face, self.px(size)[0]),
            fill=color, anchor='lt')

    def brand(self, x, y, size):
        self.layer(mark(self.px(size)[0]), x, y, size)
        self.text(x+1.22*size, y, 'Riftlet', size*1.04, 'serif')

    def selection(self, x, y, width):
        # Ground glass diffuses the underlying bezel and text. Its exact bounds
        # come from the movie tray. Keep both thumbnails and the camera key.
        unit = width/246
        bounds = self.px(x, y, x+width, y+212*unit)
        patch = self.image.crop(bounds)
        mask = Image.new('L', patch.size)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, patch.width-1, patch.height-1),
                                              radius=round(24*unit*self.s), fill=255)
        self.image.paste(patch.filter(ImageFilter.GaussianBlur(25*self.s)),
                         bounds[:2], mask)
        self.layer(press(), x-42*unit, y-42*unit, 330*unit)
        pointer_width = width*.356
        tip_x, tip_y = x+(105.75-42)*unit, y+(99-42)*unit
        self.layer(pointer(), tip_x-pointer_width*148/1254,
                   tip_y-pointer_width*108/1254, pointer_width)


def landscape(lang, height, pixel_width):
    cover = Cover(1200, height, pixel_width)
    tall = height == 900
    x, y, width = (506, 215, 1040) if tall else (584, 154, 857)
    cover.photograph(lang, x, y, width)
    cover.brand(48, 47 if tall else 31, 44 if tall else 38)
    title_y = 173 if tall else 123
    if lang == 'zh-CN':
        cover.text(42, title_y, '截张图，', 111 if tall else 100, 'headline')
        cover.text(39, title_y+(124 if tall else 111), '接着问。',
                   133 if tall else 118, 'headline', FOREST)
        body_y = title_y+(304 if tall else 264)
        cover.text(49, body_y, '一点就进 ChatGPT 草稿。', 40 if tall else 37, 'copy')
        cover.text(49, body_y+(59 if tall else 53), '不用找文件，也不用拖图。', 31 if tall else 28, 'copy')
        cover.text(49, height-64, '适用于 Mac 上的 Chrome', 21, 'copy')
    else:
        cover.text(46, title_y-5, 'Screenshot.', 108, 'serif')
        cover.text(44, title_y+102, 'Keep writing.', 78, 'bold', FOREST)
        cover.text(49, title_y+249, 'One click to your ChatGPT draft.', 34, 'medium')
        cover.text(49, title_y+298, 'No file hunting or dragging.', 27, 'medium')
        cover.text(49, height-64, 'For Chrome on Mac', 21, 'medium')
    cover.text(49, height-34, 'riftlet.com', 16, 'medium', FOREST)
    tray_box = (754, 141, 374) if tall else (773, 44, 368)
    cover.selection(*tray_box)
    return cover.image


def portrait():
    cover = Cover(720, 960, 1440)
    cover.photograph('zh-CN', -2, 434, 874, tilt=True)
    cover.brand(37, 31, 41)
    cover.text(266, 46, 'Mac 上的 Chrome', 20, 'copy')
    cover.text(557, 46, 'riftlet.com', 23, 'medium')
    cover.text(31, 100, '截张图，', 102, 'headline')
    cover.text(43, 220, '接着问。', 104, 'headline', FOREST)
    cover.text(39, 348, '一点就进 ChatGPT 草稿。', 32, 'copy')
    cover.text(39, 392, '不用找文件，也不用拖图。', 24, 'copy')
    cover.selection(420, 269, 272)
    return cover.image


def save(image, name):
    destination = ROOT/'social-covers'/name
    destination.parent.mkdir(exist_ok=True)
    profile = Path('/System/Library/ColorSync/Profiles/sRGB Profile.icc').read_bytes()
    for quality in (94, 92, 90, 88, 85):
        data = BytesIO()
        image.save(data, 'JPEG', quality=quality, subsampling=0, optimize=True,
                   progressive=True, icc_profile=profile)
        if data.tell() < 2_000_000:
            destination.write_bytes(data.getvalue())
            return
    raise ValueError(f'{name} exceeds the mobile upload size at quality 85')


def main():
    save(landscape('zh-CN', 900, 1920), 'bilibili-feed-zh-CN.jpg')
    save(landscape('zh-CN', 675, 1920), 'bilibili-player-zh-CN.jpg')
    save(portrait(), 'xiaohongshu-zh-CN.jpg')
    save(landscape('en', 675, 3840), 'youtube-en.jpg')


if __name__ == '__main__':
    main()
