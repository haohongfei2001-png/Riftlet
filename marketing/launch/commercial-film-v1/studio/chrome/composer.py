"""Editable, offline Chrome / ChatGPT draft composite. All geometry is in points.

draw_window(t, picture, scale=2) produces a transparent, rounded 640x560 window.
The image visible in the editable draft is sampled from the caller's picture.
The Chrome / ChatGPT layout is reconstructed and does not control a browser.
"""
from functools import lru_cache
from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

WIDTH, HEIGHT = 640, 560
ATTACH_TIME = 13.45
QUESTION = "What stands out in this photo?"
CONTINUATION = " Look at the lean."
TYPE_START, TYPE_END = 17.8, 20.65
ROOT = Path(__file__).resolve().parent
INK, MUTED, HAIR = "#1b1b1b", "#565656", "#DADADC"
FONT_PATHS = (
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
)
_MATERIAL_KEY = None
_MATERIAL = None


@lru_cache(maxsize=64)
def _font(px, medium=False):
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
        self.d.rounded_rectangle(self.p(box), radius=round(radius*self.s),
                                 fill=color, outline=stroke, width=max(1, round(sw*self.s)))

    def ellipse(self, xy, fill, stroke=None, sw=1):
        self.d.ellipse(self.p(xy), fill, stroke, max(1, round(sw*self.s)))

    def line(self, points, fill, sw=1):
        pts = [tuple(self.p(pt)) for pt in points]
        self.d.line(pts, fill=fill, width=max(1, round(sw*self.s)), joint="curve")

    def label(self, x, y, value, size, color=INK, medium=False, anchor="lm"):
        f = _font(round(size*self.s), medium)
        self.d.text(self.p((x, y)), value, font=f, fill=color, anchor=anchor)
        return self.d.textlength(value, font=f) / self.s


@lru_cache(maxsize=4)
def _favicon(scale):
    asset = ROOT / "chatgpt-favicon.webp"
    with Image.open(asset) as f:
        return f.convert("RGBA").resize((round(15*scale),)*2, Image.Resampling.LANCZOS)


@lru_cache(maxsize=4)
def _base(scale):
    W,H = round(WIDTH*scale),round(HEIGHT*scale)
    im=Image.new("RGBA",(W,H),"#ffffff")
    q=_Pen(im,scale)
    # Chrome for macOS, light theme. A single tab is selected. The omnibox
    # shows only the public origin. There is no personal account or tab data.
    q.rect((0,0,640,37),"#DCE2EB")
    q.rect((0,36,640,76),"#F3F5F9")
    q.line([(0,75.75),(640,75.75)],"#CDD2D8",.75)
    for x,fill,edge in ((16,"#FF6058","#DD5049"),(36,"#FFBD2D","#E3A424"),(56,"#28C841","#22B138")):
        q.ellipse((x-5.5,13.8,x+5.5,24.8),fill,edge,.55)
    q.rect((79,6,289,45),"#F3F5F9",12)
    q.rect((76,32,292,38),"#F3F5F9")
    im.alpha_composite(_favicon(scale),(round(94*scale),round(13.75*scale)))
    q.label(117,21.2,"ChatGPT",12.3,color="#25282C")
    q.line([(267.5,17.7),(274.2,24.4)],"#5B6269",1.25)
    q.line([(274.2,17.7),(267.5,24.4)],"#5B6269",1.25)
    q.line([(306.4,20.6),(317,20.6)],"#515861",1.4)
    q.line([(311.7,15.3),(311.7,25.9)],"#515861",1.4)
    q.line([(17,55.4),(28.5,55.4)],"#626974",1.5)
    q.line([(22.8,49.7),(17,55.4),(22.8,61.1)],"#626974",1.5)
    q.line([(48.5,55.4),(60,55.4)],"#A6ADB7",1.4)
    q.line([(54.2,49.7),(60,55.4),(54.2,61.1)],"#A6ADB7",1.4)
    q.d.arc(q.p((79.4,49.5,91.3,61.4)),start=9,end=312,fill="#5D6570",width=max(1,round(1.45*scale)))
    q.line([(90.2,48.5),(90.2,52.7),(86.2,52.7)],"#5D6570",1.3)
    q.rect((105,41,608,69),"#E5EAF2",14)
    q.ellipse((111,45.6,130.6,65.2),"#F6F8FA")
    q.line([(116.2,52.7),(125,52.7)],"#515963",1.1)
    q.line([(116.2,57.8),(125,57.8)],"#515963",1.1)
    q.ellipse((117.4,50.8,120.9,54.3),"#515963")
    q.ellipse((121.1,56,124.6,59.5),"#515963")
    q.label(137,55,"chatgpt.com",13.1,color="#20242A")
    star=[(590+(6.4 if i%2==0 else 2.9)*cos(-pi/2+i*pi/5),55+(6.4 if i%2==0 else 2.9)*sin(-pi/2+i*pi/5)) for i in range(10)]
    q.line(star+[star[0]],"#59626D",1.12)
    for y in (50.6,55,59.4):
        q.ellipse((622.1,y-1.15,624.4,y+1.15),"#555D67")
    # Collapsed navigation. Chrome frame controls and ChatGPT controls belong
    # to separate rows, as on desktop.
    q.rect((20.7,94,37,108.3),None,3,INK,1.55)
    q.line([(26,94.9),(26,107.3)],INK,1.55)
    q.label(56,101.9,"ChatGPT",17.8,medium=True)
    q.line([(133.9,100.3),(137.8,104.2),(141.7,100.3)],MUTED,1.3)
    return im


def _smooth(x):
    a = max(0.0,min(1.0,x))
    return a*a*(3-2*a)


def _typed(t):
    # A pause after the first word, with the last period landing at TYPE_END.
    times=(17.80,17.95,18.07,18.22,18.34,18.60,18.76,18.89,19.08,19.24,19.37,19.50,19.71,19.88,20.05,20.19,20.42,20.65)
    return CONTINUATION[:sum(t>=at for at in times)]


def _picture_tile(picture, size):
    global _MATERIAL_KEY, _MATERIAL
    if picture is None:
        raise ValueError("The selected original picture is required once the attachment appears.")
    if _MATERIAL_KEY is not None and _MATERIAL_KEY[0] is picture and _MATERIAL_KEY[1]==size:
        return _MATERIAL
    src=picture if isinstance(picture,Image.Image) else Image.open(picture)
    try:
        tile=ImageOps.fit(src.convert("RGB"),size,method=Image.Resampling.LANCZOS,centering=(.5,.5)).convert("RGBA")
    finally:
        if src is not picture: src.close()
    _MATERIAL_KEY=(picture,size)
    _MATERIAL=tile
    return tile


@lru_cache(maxsize=8)
def _clip(scale):
    mask=Image.new("L",(round(WIDTH*scale),round(HEIGHT*scale)),0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,mask.width-1,mask.height-1),radius=round(11*scale),fill=255)
    return mask


def draw_window(t, picture, scale=2, *, attachment_time=ATTACH_TIME):
    """t is seconds on the 30-second master. Sibling source image stays untouched."""
    im = _base(scale).copy()
    q = _Pen(im,scale)
    reveal = 0.0 if t<attachment_time else .24 + .76*_smooth((t-attachment_time)/.14)
    # The page centers a heading and the growing draft together. The other
    # elements move only as much as is required to make room for the picture.
    top = 282 - 25*reveal
    bottom = 375 + 50*reveal
    q.label(320,234-25*reveal,"What’s on your mind today?",31.4,anchor="mm")
    box=(42,top,598,bottom)
    q.rect((42,top+1.7,598,bottom+1.7),"#E8E8E8",26)
    q.rect(box,"#FFFFFF",26,"#DCDCDD",.9)
    if t>=attachment_time:
        # A single actual-image chip. The small x is the existing removal
        # affordance; it gets neither focus nor a click.
        w=max(1,round(66*scale))
        tile=_picture_tile(picture,(w,w)).copy()
        mask=Image.new("L",(w,w),0)
        ImageDraw.Draw(mask).rounded_rectangle((0,0,w-1,w-1),round(9*scale),fill=255)
        if reveal<1:
            # Clip to the amount of real estate available on this animation frame.
            cutoff=round(w*reveal)
            if cutoff<w: ImageDraw.Draw(mask).rectangle((0,cutoff,w,w),fill=0)
        tile.putalpha(mask)
        im.alpha_composite(tile,(round(56*scale),round((top+13)*scale)))
        if reveal>.75:
            q.ellipse((108,top+12,125,top+29),"#292929","#FFFFFF",1.4)
            q.line([(113.8,top+17.7),(119,top+22.9)],"white",1.25)
            q.line([(119,top+17.7),(113.8,top+22.9)],"white",1.25)
    text_y=top+27+75*reveal
    text=QUESTION+_typed(t)
    length=q.label(61,text_y,text,19.2)
    if (TYPE_START<=t<TYPE_END+.26) or (t%1.08<.55):
        q.line([(61+length+1,text_y-9),(61+length+1,text_y+10)],"#212121",1)
    y=bottom-23
    q.line([(61.5,y),(77,y)],INK,1.6)
    q.line([(69.25,y-7.75),(69.25,y+7.75)],INK,1.6)
    q.rect((522.7,y-7.7,529.5,y+2.7),None,3.2,INK,1.45)
    q.d.arc(q.p((519.9,y-4.3,532.1,y+6.6)),start=0,end=180,fill=INK,width=max(1,round(1.45*scale)))
    q.line([(526.1,y+6.5),(526.1,y+9)],INK,1.4)
    q.ellipse((550,y-16,582,y+16),"#171717")
    q.line([(566,y+6.5),(566,y-6.5)],"white",1.9)
    q.line([(559.9,y-.4),(566,y-6.5),(572.1,y-.4)],"white",1.9)
    im.putalpha(_clip(scale))
    return im
