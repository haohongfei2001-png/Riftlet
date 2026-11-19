"""Build native-sized launch artwork from the film plate and a release-App frame.

Requires Python 3.10+, Pillow, fonttools[woff], and macOS Songti SC, PingFang SC,
and Helvetica Neue. The three raster source files live in ../originals. The
repository's official logo SVG and Instrument Serif are read directly at build.
"""
import argparse
from functools import lru_cache
from io import BytesIO
from pathlib import Path
import re
from xml.etree import ElementTree as ET

from fontTools.pens.basePen import BasePen
from fontTools.svgLib.path import parse_path
from fontTools.ttLib import TTFont
from PIL import Image, ImageCms, ImageDraw, ImageFont, ImageOps

PAPER = '#F4F1E8'
INK = '#172621'
MUTED = '#4C5B52'
CAPTURE_PAPER = '#FCFBF8'  # Original backdrop in the white-listed WindowServer capture.
SANS = Path('/System/Library/Fonts/HelveticaNeue.ttc')
SONGTI = Path('/System/Library/Fonts/Supplemental/Songti.ttc')
LANCZOS = Image.Resampling.LANCZOS
# LittleCMS sets creation time in its sRGB header. Normalize that optional
# metadata so repeated image exports are byte-for-byte identical.
_profile = bytearray(ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes())
_profile[24:36] = bytes.fromhex('07ea000b000e000000000000')
_profile[84:100] = bytes(16)
PROFILE = bytes(_profile)


class LogoPen(BasePen):
    """Flatten the approved SVG's cubic outlines at 6× output resolution."""
    def __init__(self, draw, transform, color):
        super().__init__(None)
        self.draw, self.transform, self.color = draw, transform, color
        self.points = []

    def _moveTo(self, point):
        self.points = [point]

    def _lineTo(self, point):
        self.points.append(point)

    def _curveToOne(self, point1, point2, point3):
        x0, y0 = self.points[-1]
        for n in range(1, 33):
            t = n / 32
            s = 1 - t
            self.points.append((s**3*x0 + 3*s*s*t*point1[0] + 3*s*t*t*point2[0] + t**3*point3[0],
                                s**3*y0 + 3*s*s*t*point1[1] + 3*s*t*t*point2[1] + t**3*point3[1]))

    def _closePath(self):
        self.draw.polygon([self.transform(x, y) for x, y in self.points], fill=self.color)
        self.points = []


def official_mark(svg, size=240):
    root = ET.parse(svg).getroot()
    ns = {'s': 'http://www.w3.org/2000/svg'}
    rect, group = root.find('s:rect', ns), root.find('s:g', ns)
    scale = size * 6 / float(rect.attrib['width'])
    canvas = Image.new('RGBA', (size*6, size*6))
    painter = ImageDraw.Draw(canvas)
    painter.rounded_rectangle((0, 0, size*6-1, size*6-1),
                              radius=float(rect.attrib['rx'])*scale, fill=rect.attrib['fill'])
    tx, ty, factor = map(float, re.findall(r'[-+]?(?:[0-9]*\.)?[0-9]+', group.attrib['transform']))
    def transform(x, y):
        return ((tx+x*factor)*scale, (ty+y*factor)*scale)
    pen = LogoPen(painter, transform, group.attrib['fill'])
    for shape in group.findall('s:path', ns):
        parse_path(shape.attrib['d'], pen)
    return canvas.resize((size, size), LANCZOS)


class Type:
    def __init__(self, website_fonts):
        self.serif_bytes = {}
        for name in ['instrument-serif', 'instrument-serif-italic']:
            with TTFont(website_fonts / (name+'.woff2')) as face:
                face.flavor = None
                buffer = BytesIO()
                face.save(buffer)
            self.serif_bytes[name] = buffer.getvalue()
        self.ping = sorted(Path('/System/Library/AssetsV2/com_apple_MobileAsset_Font8').glob('*/AssetData/PingFang.ttc'))
        if not self.ping:
            self.ping = [Path('/System/Library/Fonts/PingFang.ttc')]

    @lru_cache(maxsize=100)
    def font(self, family, size):
        if family.startswith('instrument-'):
            return ImageFont.truetype(BytesIO(self.serif_bytes[family]), size)
        path, index = {'sans':(SANS,0), 'medium':(SANS,1), 'song':(SONGTI,3), 'ping':(self.ping[0],3)}[family]
        return ImageFont.truetype(str(path), size, index=index)


class Artwork:
    def __init__(self, work, repo, destination):
        self.destination = destination
        self.type = Type(repo / 'website-assets' / 'fonts')
        self.mark = official_mark(repo / 'website-assets' / 'riftlet.svg')
        self.wedge = Image.open(work / 'originals' / 'wedge.png').convert('RGB')
        self.grazing = Image.open(work / 'originals' / 'grazing-light.png').convert('RGB')
        self.tray = Image.open(work / 'originals' / 'native-tray-film-still.png').convert('RGB')
        if self.tray.size != (652, 608) or self.tray.getpixel((0, 0)) != (252, 251, 248):
            raise ValueError('Use the approved original release-App frame on its warm paper field')
        self.left = self.tray.crop((90, 47, 652, 595))

    def text(self, canvas, pos, string, font, size, fill=INK, anchor='lt'):
        ImageDraw.Draw(canvas).text(pos, string, fill=fill, anchor=anchor, font=self.type.font(font, size))

    def lockup(self, canvas, x, y, size=38, ink=INK):
        logo = self.mark.resize((size, size), LANCZOS)
        canvas.paste(logo, (x, y), logo)
        self.text(canvas, (x+size+12, y+size//2), 'Riftlet', 'medium', round(size*.76), fill=ink, anchor='lm')

    def photo(self, canvas, box, center=(.5,.5)):
        x, y, w, h = box
        canvas.paste(ImageOps.fit(self.wedge, (w,h), LANCZOS, centering=center), (x,y))

    @staticmethod
    def crop_marks(canvas, rect, arm, color, width=2):
        x,y,r,b = rect
        pen = ImageDraw.Draw(canvas)
        for px,py,dx,dy in ((x,y,1,1),(r,y,-1,1),(x,b,1,-1),(r,b,-1,-1)):
            pen.line([(px+arm*dx,py),(px,py),(px,py+arm*dy)],fill=color,width=width)

    def save(self, canvas, name):
        target = self.destination / name
        if target.suffix == '.jpg':
            canvas.save(target, quality=94, subsampling=0, optimize=True, icc_profile=PROFILE)
        else:
            canvas.save(target, optimize=True, icc_profile=PROFILE)

    def product_hunt(self):
        canvas = Image.new('RGB', (1270,760), CAPTURE_PAPER)
        # The glass negative's lower edge leads into the real screenshot tray.
        self.lockup(canvas, 57, 48, 39)
        self.text(canvas, (55,144), 'A place for', 'instrument-serif', 91)
        self.text(canvas, (55,226), 'the next shot.', 'instrument-serif-italic', 91)
        self.photo(canvas, (56,362,447,237), (.51,.52))
        self.text(canvas, (58,647), 'Keep your Mac screenshots at the edge.', 'sans', 25)
        self.text(canvas, (58,685), 'Click one to attach it to your ChatGPT draft in Chrome.', 'sans', 23, MUTED)
        canvas.paste(self.left.resize((599,584), LANCZOS), (627,65))
        self.text(canvas, (1220,684), 'Public Beta · macOS 13+', 'sans', 20, MUTED, 'rt')
        self.save(canvas, 'product-hunt-gallery.jpg')
        self.save(self.mark, 'product-hunt-icon.png')

    def x_reddit(self):
        canvas = ImageOps.fit(self.grazing, (1600, 900), LANCZOS)
        self.lockup(canvas, 58, 54, 40, PAPER)
        self.text(canvas, (59,184), 'Catch', 'instrument-serif', 115, PAPER)
        self.text(canvas, (55,293), 'the light.', 'instrument-serif-italic', 115, PAPER)
        self.text(canvas, (61,463), 'Click a screenshot to attach it', 'sans', 31, PAPER)
        self.text(canvas, (61,508), 'to your ChatGPT draft in Chrome.', 'sans', 31, PAPER)
        self.crop_marks(canvas, (945,464,1332,719), 25, '#F4F1E8', 3)
        self.text(canvas, (1532,824), 'riftlet.com', 'medium', 23, PAPER, 'rt')
        self.save(canvas,'x-reddit-card.jpg')

    def xiaohongshu(self):
        canvas = Image.new('RGB',(1080,1440),PAPER)
        self.lockup(canvas,62,51,45)
        self.text(canvas,(1019,77),'Mac 截图工具','ping',24,MUTED,'rm')
        self.text(canvas,(59,154),'截下一束光。','song',105)
        self.photo(canvas,(0,316,1080,796),(.55,.52))
        self.crop_marks(canvas,(184,689,604,993),34,'#F4F1E8',4)
        self.text(canvas,(61,1180),'想聊的细节，就在手边。','song',63)
        self.text(canvas,(64,1322),'在 Chrome 打开 ChatGPT 草稿，点一下桌面边缘的微图。','ping',31,MUTED)
        self.save(canvas,'xiaohongshu-cover.jpg')

    def bilibili(self):
        canvas = Image.new('RGB',(1200,900),CAPTURE_PAPER)
        self.lockup(canvas,59,51,42)
        self.text(canvas,(1141,74),'Mac · 产品演示','ping',26,MUTED,'rm')
        ImageDraw.Draw(canvas).line((60,125,1141,125),fill='#D1D2C8',width=1)
        self.text(canvas,(59,191),'两张截图，','song',89)
        self.text(canvas,(59,296),'一处收好。','song',89)
        canvas.paste(self.left.resize((604,589),LANCZOS),(546,162))
        # A magnified detail from the first real thumbnail ties the close-up back
        # to the App pixels; both tide plates stay in their original tray slots.
        detail = self.tray.crop((161, 154, 360, 250))
        canvas.paste(ImageOps.fit(detail, (409, 196), LANCZOS), (60, 476))
        self.text(canvas, (60,691), '低潮 · 第一张缩略图局部', 'ping', 21, MUTED)
        self.text(canvas,(60,795),'桌面边缘的截图托盘', 'ping',29)
        self.text(canvas,(1141,803),'Riftlet · 0.3.5 (20) Public Beta', 'sans',23,MUTED,'rt')
        self.save(canvas,'bilibili-cover.jpg')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--repo',type=Path)
    parser.add_argument('--out',type=Path)
    args=parser.parse_args()
    out=args.out or args.work / 'platforms'
    out.mkdir(parents=True,exist_ok=True)
    repo = args.repo or args.work.resolve().parents[2]
    artwork=Artwork(args.work,repo,out)
    artwork.product_hunt()
    artwork.x_reddit()
    artwork.xiaohongshu()
    artwork.bilibili()


if __name__=='__main__':
    main()
