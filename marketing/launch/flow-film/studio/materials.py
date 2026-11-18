"""Work pages and compositing plates for the two Riftlet case studies.

shot(kind, lang) is the actual RGB crop. spread(kind, lang) returns that crop
pasted pixel-for-pixel in a 1440 by 960 source page, plus its PIL crop box.
Treat the returned, cached images as read-only.
"""
from functools import lru_cache
from io import BytesIO
from math import ceil
from pathlib import Path

import resvg_py
from PIL import Image, ImageDraw, ImageFont, ImageOps


def _find_assets():
    for folder in (*Path(__file__).resolve().parents, Path.cwd(), *Path.cwd().parents):
        assets = folder / 'website-assets'
        if (assets / 'reading.svg').is_file():
            return assets
    raise FileNotFoundError('Run inside the Riftlet checkout or store materials.py in it.')


ASSETS = _find_assets()
ROOT_FONTS = Path('/System/Library/Fonts')
DARK = '#16332E'
SAGE = '#166C5F'
PEACH = '#CA785B'
PAPER = '#F7F5EC'
LANCZOS = Image.Resampling.LANCZOS
SHEETS = ('source', 'trace', 'code', 'math', 'reading', 'detail', 'color')


@lru_cache(maxsize=180)
def _font(family, size):
    names = {
        'text': ('HelveticaNeue.ttc', 0), 'bold': ('HelveticaNeue.ttc', 1),
        'serif': ('Supplemental/Georgia.ttf', 0), 'italic': ('Supplemental/Georgia Italic.ttf', 0),
        'mono': ('Menlo.ttc', 0), 'zh': ('STHeiti Light.ttc', 1),
        'zhbold': ('STHeiti Medium.ttc', 1), 'zhserif': ('Supplemental/Songti.ttc', 6),
    }
    path, index = names[family]
    return ImageFont.truetype(str(ROOT_FONTS / path), round(size), index=index)


def _label(canvas, xy, value, size, face, color=DARK, anchor='lt', limit=None):
    x, y = xy
    f = _font(face, size)
    if limit is not None and f.getlength(value) > limit:
        f = _font(face, int(size * limit / f.getlength(value)))
    ImageDraw.Draw(canvas).text((x, y), value, font=f, anchor=anchor, fill=color)


def _line(canvas, points, color, width=1):
    ImageDraw.Draw(canvas).line(points, fill=color, width=width, joint='curve')


@lru_cache(maxsize=8)
def _site_svg(kind, zh):
    source = (ASSETS / f'{kind}.svg').read_text()
    if kind == 'reading' and zh:
        # Translate the three prose labels, preserving the site's plotted geometry,
        # mathematical text, page proportions, insets, highlight and colours.
        source = source.replace('THE NEXT LINE', '阅读摘记').replace(
            'Near x = 1', '在 x = 1 附近').replace(
            'For small h · error = h²', '当 h 很小时，误差为 h²')
        source = source.replace('system-ui, sans-serif', "Heiti SC, sans-serif")
    png = resvg_py.svg_to_bytes(
        svg_string=source, zoom=2,
        sans_serif_family='Helvetica Neue', monospace_family='Menlo', serif_family='Georgia',
        font_files=[str(ROOT_FONTS / x) for x in (
            'HelveticaNeue.ttc', 'Menlo.ttc', 'STHeiti Light.ttc',
            'Supplemental/Georgia Italic.ttf', 'Supplemental/Georgia.ttf')])
    with Image.open(BytesIO(png)) as src:
        back = Image.new('RGB', src.size, '#23322F' if kind == 'error' else '#FAF5E9')
        back.paste(src, mask=src.getchannel('A'))
    return back


def _source(zh):
    im = Image.new('RGB', (840, 484), '#18342F')
    _label(im, (40, 36), 'app.js', 25, 'mono', '#B9D4C4')
    _line(im, (40, 90, 800, 90), '#547065')
    rows = [
        [('const ', '#8CD3B5'), ('response', '#FAF7DF'), (' = {};', '#D1DFCE')],
        [('const ', '#8CD3B5'), ('items', '#FAF7DF'), (' = response.items;', '#D1DFCE')],
        [('items', '#FAF7DF'), ('.map', '#EAB69A'), ('(x => x.id);', '#D1DFCE')],
    ]
    for i, line in enumerate(rows):
        y = 139+i*85
        if i == 2:
            ImageDraw.Draw(im).rounded_rectangle((30, y-14, 807, y+46), 8, '#29473D')
            _line(im, (31, y-11, 31, y+40), '#DF9779', 4)
        _label(im, (46, y+4), str(i+1), 26, 'mono', '#8CA698')
        x = 107
        for val, color in line:
            _label(im, (x, y), val, 35, 'mono', color)
            x += _font('mono', 35).getlength(val)
    _line(im, (40, 394, 800, 394), '#547065')
    _label(im, (43, 428), 'JS', 21, 'mono', '#B9D4C4')
    _label(im, (800, 431), 'UTF-8', 19, 'mono', '#B9D4C4', anchor='rt')
    return im


def _trace(zh):
    im = Image.new('RGB', (840, 496), '#F2D6BF')
    _label(im, (40, 36), '控制台' if zh else 'Console', 30, 'zhbold' if zh else 'bold', '#55352C')
    _line(im, (40, 96, 800, 96), '#BF9A83')
    _label(im, (42, 151), '›', 46, 'mono', '#A35139')
    _label(im, (93, 148), 'response.items', 42, 'mono', '#54332B')
    _label(im, (36, 269), 'undefined', 112, 'serif', '#65412F')
    _line(im, (40, 430, 800, 430), '#BF9A83')
    _label(im, (40, 456), '求值结果' if zh else 'Evaluation result', 21,
           'zh' if zh else 'text', '#714D3F')
    return im


def _math(zh):
    # 2x stroke rendering keeps the shallow tangent and gradient-free vector
    # curves clean under a moving virtual camera.
    s = 2
    im = Image.new('RGB', (840*s, 560*s), '#E6EDDD')
    d = ImageDraw.Draw(im)
    def text(x, y, v, size, style, color=DARK):
        _label(im, (x*s, y*s), v, size*s, style, color)
    def line(pts, color, weight=1):
        d.line([(round(x*s), round(y*s)) for x, y in pts], fill=color,
               width=max(1, round(weight*s)), joint='curve')
    text(38, 30, '曲线与切线' if zh else 'Curve and tangent', 32, 'zhbold' if zh else 'bold')
    line([(38, 86), (802, 86)], '#BBCBB6')
    # x=1 sits on both paths, and the coloured gap at x=1+h has exact height h².
    def P(x, y):
        return (93 + x*275, 467-y*73)
    for y in range(1, 5):
        line([P(0,y), P(2.4,y)], '#CFDAC8')
    for x in (.5, 1, 1.5, 2):
        line([P(x,0), P(x,4.6)], '#CFDAC8')
    line([P(0,4.6),P(0,0),P(2.45,0)], '#7D9481', 1.7)
    xs = np_range(.0,2.16,112)
    line([P(x,x*x) for x in xs], '#0F7464', 4)
    line([P(.48,-.04),P(2.40,3.80)], '#C57655', 3.5)
    x1 = 1.92
    upper, lower = P(x1,x1*x1), P(x1,2*x1-1)
    line([upper,lower], '#9D5439', 3)
    for dot in [P(1,1),upper,lower]:
        cx, cy = dot
        d.ellipse(((cx-4)*s,(cy-4)*s,(cx+4)*s,(cy+4)*s), fill='#136A59')
    text(upper[0]+11, .5*(upper[1]+lower[1])-10, 'h²', 28, 'italic', '#984D35')
    text(624, 110, 'x²', 32, 'italic', SAGE)
    text(696, 207, '2x−1', 25, 'italic', '#99573D')
    text(359, 482, '1', 20, 'mono', '#526D59')
    text(591, 482, '1+h', 21, 'italic', '#526D59')
    text(38, 526, '在 x = 1 处线性化' if zh else 'Linearized at x = 1', 19,
         'zh' if zh else 'text', '#536B5A')
    return im.resize((840,560), LANCZOS)


def np_range(a, b, steps):
    return [a + (b-a)*i/(steps-1) for i in range(steps)]


def _detail(zh):
    im = Image.new('RGB',(840,514),'#F4DBCF')
    _label(im,(40,33),'误差项' if zh else 'The error term',30,
           'zhbold' if zh else 'bold','#603F38')
    _line(im,(40,94,800,94),'#C8ABA0')
    _label(im,(40,148),'(1+h)²',71,'italic','#70453A')
    _label(im,(43,264),'= 1 + 2h +',61,'italic','#70453A')
    _label(im,(452,233),'h²',103,'italic','#993F27')
    _line(im,(454,365,564,365),'#A44E37',3)
    _label(im,(454,390),'二阶余项' if zh else 'Second-order term',24,
           'zh' if zh else 'text','#904D3C')
    return im


@lru_cache(maxsize=16)
def shot(kind, lang='zh-CN'):
    if lang not in ('zh-CN','en'):
        raise ValueError(lang)
    zh = lang == 'zh-CN'
    if kind == 'source': return _source(zh)
    if kind == 'trace': return _trace(zh)
    if kind == 'code': return _site_svg('error', zh)
    if kind == 'math': return _math(zh)
    if kind == 'reading':
        return _site_svg('reading', zh).resize((480,624), LANCZOS)
    if kind == 'detail': return _detail(zh)
    if kind == 'color':
        with Image.open(ASSETS/'glass-study.png') as pic:
            return pic.convert('RGB').resize((800,600), LANCZOS)
    raise KeyError(kind)


# Each page pairs one capture area with concise original working notes.
PAGES = {
 'source':(('三行代码','Three lines'), ('数据检查','Data inspection'),
           ('空对象里没有 items。','The object has no items field.')),
 'trace':(('检查返回值','Inspect the value'),('求值记录','Evaluation log'),
          ('先看属性，再读报错。','Inspect the property before the call.')),
 'code':(('定位报错','Locate the error'),('运行日志','Runtime log'),
         ('调用 map 时，程序停在这里。','Execution stops at the map call.')),
 'math':(('一条切线','A tangent line'),('微积分笔记','Calculus notes'),
         ('靠近切点时，两条线慢慢贴合。','Near the contact point the two paths meet.')),
 'reading':(('局部近似','A local estimate'),('阅读摘记','Reading notes'),
            ('在 x = 1 附近观察函数。','Read the curve near x = 1.')),
 'detail':(('展开平方','Expand the square'),('展开式','Expansion'),
           ('保留一次项，再比较差值。','Keep the linear terms, then compare.')),
 'color':(('颜色之间','Between colours'),('色彩笔记','Colour notes'),
          ('把颜色放在一起观察。','Look at the colours side by side.')),
}


@lru_cache(maxsize=16)
def spread(kind, lang='zh-CN'):
    tile = shot(kind,lang)
    zh = lang == 'zh-CN'
    code = kind in ('source','trace','code')
    page = Image.new('RGB', (1440,960), '#F4F4E9' if code else '#F7F5EC')
    title, section, memo = [pair[0 if zh else 1] for pair in PAGES[kind]]
    face = 'zh' if zh else 'text'
    title_face = 'zhserif' if zh else 'serif'
    _label(page,(62,57), '调试手记' if zh and code else
           ('微积分手记' if zh and kind!='color' else '图像手记') if zh else
           ('Debug journal' if code else 'Calculus journal' if kind!='color' else 'Image journal'),
           34, title_face)
    _label(page,(1378,67),section,25,face,anchor='rt')
    _line(page,(62,125,1378,125),'#889D8D',2)
    _label(page,(63,230),section,28,face,SAGE)
    _label(page,(59,309),title,81 if zh else 68,title_face,limit=420)
    _line(page,(62,425,460,425),'#BFCBBE')
    # Short prose lines remain separate from the screenshot source.
    if not zh and len(memo)>30:
        cut = memo.rfind(' ',0,26)
        rows = (memo[:cut],memo[cut+1:])
    else:
        rows = (memo,)
    for i,row in enumerate(rows):
        _label(page,(63,461+i*47),row,27,face,limit=415)
    symbol = ['{}','›','map','x²','≈','h²','◯'][SHEETS.index(kind)]
    _label(page,(61,593),symbol,110,'italic',color='#749384')
    if kind=='reading':
        x,y=724,182
        line_x=686
    else:
        x,y=1378-tile.width,468-tile.height//2
        line_x=x-26
    page.paste(tile,(x,y))
    _line(page,(line_x,176,line_x,810),'#C8CEC2')
    _line(page,(62,858,1378,858),'#B0BFAF')
    tail='断点记录' if zh and code else '草稿' if zh else 'Working notes'
    _label(page,(64,887),tail,21,face,'#657B6D')
    folio= {'source':1,'trace':2,'code':3,'math':1,'reading':2,'detail':3,'color':1}[kind]
    _label(page,(1378,884),f'{folio:02d}',24,'mono','#657B6D',anchor='rt')
    return page,(x,y,x+tile.width,y+tile.height)


if __name__ == '__main__':
    out = Path(__file__).resolve().parent
    for lang in ('zh-CN','en'):
        sheet = Image.new('RGB',(1440,700),'#CFD7CD')
        for i,k in enumerate(SHEETS[:6]):
            picture,box = spread(k,lang)
            assert picture.crop(box).tobytes() == shot(k,lang).tobytes()
            sheet.paste(ImageOps.contain(picture,(468,314),method=LANCZOS),
                        (8+(i%3)*478,10+(i//3)*348))
        sheet.save(out/f'pages-{lang}.jpg',quality=94)
