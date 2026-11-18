"""Publish-ready still artwork using the same plates, studio colors and type as the film."""
from argparse import ArgumentParser
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

from film import Canvas, INK, PAPER, TEAL, cursor, ground
from materials import shot
from product import Product


RESAMPLE = Image.Resampling.LANCZOS
ARRIVALS = ((0., 0), (.5, 1), (1., 2))


@lru_cache
def queue(lang, mode):
    kinds = ('code', 'trace', 'source') if mode == 'tray' else ('math', 'reading', 'detail')
    return Product([shot(name, lang) for name in kinds])


def plate(canvas, lang, mode, x, y, width):
    """Locate the optical bounds of the native UI, rather than its transparent film plate."""
    p = queue(lang, mode)
    scale = width / (246 if mode == 'tray' else 100)
    full = p.frame(mode, 2, ARRIVALS, scale=canvas.s*scale)
    if mode == 'tray':
        left, top = x-38*scale, y-43*scale
    else:
        left, top = x-184*scale, y-6*scale
    canvas.place(full, left, top)
    if mode == 'tray':
        tx, ty = p.target(mode, 2, ARRIVALS, index=0)
        cursor(canvas, left+tx*scale, top+ty*scale, scale*1.12)


def field(width,height,scale,portrait):
    """Freeze the two website-inspired sets on opposite sides of the film's diagonal wipe."""
    a = ground(width,height,scale,0).copy()
    b = ground(width,height,scale,1).copy()
    w,h = b.size
    # Fragments of the actual selected source art are printed into the two
    # paper fields. No extra app windows or controls are drawn.
    def print_fragment(dest, source, x, y, target_width, ink, opacity):
        src = ImageOps.grayscale(source).resize((round(target_width*scale),
                 round(target_width*source.height/source.width*scale)),RESAMPLE)
        if source.mode!='L':
            src=ImageOps.invert(src)
        mask=src.point(lambda v: round(max(0,v-42)*opacity))
        dest.paste(ink, (round(x*scale), round(y*scale),
                         round(x*scale)+src.width, round(y*scale)+src.height),mask)

    # Crop on the axes and two mathematical curves; no prose becomes a watermark.
    graph = shot('math','en')
    graph = graph.crop((38,145,graph.width-25,graph.height-30))
    if portrait:
        print_fragment(b,graph,-64, height*.56,width*.97,'#356455',.24)
        polygon=((0,round(h*.51)),(w,round(h*.435)),(w,h),(0,h))
    else:
        print_fragment(b,graph,width*.45,height*.36,width*.49,'#456C5A',.28)
        polygon=((round(w*.56),0),(w,0),(w,h),(round(w*.47),h))
    # Enlarge one literal token from each source on the corresponding paper.
    # Both remain behind the foreground product and use the film's own inks.
    code=Canvas((width,height),scale,a)
    math=Canvas((width,height),scale,b)
    if portrait:
        code.text(-26,height*.296,'items.map',122,'mono','#2D4D41')
        math.text(31,height*.654,'h',162,'italic','#9DB9A0')
        math.text(99,height*.651,'2',69,'serif','#9DB9A0')
    else:
        code.text(-22,height*.504,'items.map',129,'mono','#2E4C40')
        math.text(width*.592,height*.386,'h',177,'italic','#9AB69D')
        math.text(width*.592+74,height*.382,'2',74,'serif','#9AB69D')
    a,b=code.im,math.im
    mask=Image.new('L',(w,h)); ImageDraw.Draw(mask).polygon(polygon,fill=255)
    return Image.composite(b,a,mask)


def wide(lang, pixel_width=1920, height=720):
    w,h=1280,height
    tall=h==960
    s=pixel_width/w
    cn=lang=='zh-CN'
    c=Canvas((w,h),s,field(w,h,s,False))
    c.brand(45,31,35,PAPER)
    c.text(1232,39,'riftlet.com',23,'medium',TEAL,anchor='rt')
    title_font='song' if cn else 'serif'
    c.text(41,143 if tall else 109,'截图托盘' if cn else 'Screenshot Tray',81 if cn else 76,title_font,PAPER,width=628)
    c.text(759,146 if tall else 113,'微缝' if cn else 'Micro Slit',81 if cn else 84,title_font,INK,width=410)

    plate(c,lang,'tray',130 if tall else 169,295 if tall else 231,405 if tall else 341)
    plate(c,lang,'slit',982 if tall else 1025,260 if tall else 188,225 if tall else 195)
    c.text(47,h-127,'点一下，进 ChatGPT 草稿。' if cn else 'One click to your draft.',
           50 if cn else 54,'zh' if cn else 'medium','#AAEACB',width=560)
    c.text(49,h-50,'Mac 截图，在 Chrome 里接着写' if cn else 'Mac screenshots to ChatGPT in Chrome',
           21,'zh' if cn else 'medium',PAPER)
    return c.im


def portrait(lang,pixel_width=1080,height=1280):
    cn=lang=='zh-CN';w,h=720,height;s=pixel_width/w
    short=h==960
    c=Canvas((w,h),s,field(w,h,s,True))
    c.brand(38,37,39,PAPER)
    c.text(680,48,'riftlet.com',22,'medium','#C1DBBF',anchor='rt')
    display='song' if cn else 'serif'
    c.text(34,102 if short else 128,'截图托盘' if cn else 'Screenshot Tray',69 if short else 83 if cn else 81,display,PAPER,width=645)
    plate(c,lang,'tray',289 if short else 249,174 if short else 236,274 if short else 344)
    c.text(36,527 if short else 696,'微缝' if cn else 'Micro Slit',74 if short else 87 if cn else 85,display,INK,width=413)
    plate(c,lang,'slit',506 if short else 470,447 if short else 631,143 if short else 179)
    c.text(36,809 if short else 1060,'点一下，进 ChatGPT 草稿。' if cn else 'One click to your draft.',
           56 if cn else 58,'zh' if cn else 'medium',TEAL,width=645)
    c.text(41,899 if short else 1181,'Mac 截图，在 Chrome 里接着写' if cn else 'Mac screenshots to ChatGPT in Chrome',
           26,'zh' if cn else 'medium',INK)
    return c.im


def main():
    p=ArgumentParser()
    p.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'covers')
    args=p.parse_args()
    icc=Path('/System/Library/ColorSync/Profiles/sRGB Profile.icc').read_bytes()
    for lang in ('zh-CN','en'):
        folder=args.output/lang
        folder.mkdir(parents=True,exist_ok=True)
        designs=[('master',wide(lang,3840 if lang=='en' else 1920)),('vertical',portrait(lang))]
        if lang=='zh-CN':
            designs.extend([('bilibili-feed',wide(lang,1920,960)),('xiaohongshu',portrait(lang,1440,960))])
        for name,im in designs:
            im.save(folder/(name+'.jpg'),quality=94,progressive=True,optimize=True,subsampling=0,icc_profile=icc)


if __name__=='__main__':
    main()
