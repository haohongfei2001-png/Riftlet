"""Photographic set, original magazine proofs and compositing surfaces."""
import io
import math
import tempfile
from pathlib import Path
from functools import lru_cache

import cv2
import numpy as np
import resvg_py
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter
from chrome.composer import draw_window
from tray.tray import Tray

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[2]
ART = ROOT / 'originals'
FONTS = REPO / 'website-assets' / 'fonts'
IVORY, INK, MINT = '#FCFBF8', '#102A27', '#19B7A4'
cv2.setNumThreads(2)
TMP = tempfile.TemporaryDirectory(prefix='riftlet-type-')

@lru_cache(maxsize=120)
def font(which, size):
    size = max(1, round(size))
    if which in ('serif','italic'):
        target = Path(TMP.name)/(which+'.ttf')
        if not target.exists():
            face = TTFont(FONTS/('instrument-serif'+('-italic' if which=='italic' else '')+'.woff2'))
            face.flavor = None
            face.save(target)
        return ImageFont.truetype(str(target), size)
    system = Path('/System/Library/Fonts')
    path, index = ('HelveticaNeue.ttc', {'sans':0,'medium':10,'bold':1}.get(which,0))
    if which in ('zh','zh-light'):
        path, index = ('STHeiti Medium.ttc' if which == 'zh' else 'STHeiti Light.ttc'), 1
    if which == 'zh-serif': path, index = 'Supplemental/Songti.ttc', 6
    if which == 'mono': path = 'SFNSMono.ttf'
    if which == 'keys': path = 'SFNS.ttf'
    return ImageFont.truetype(str(system/path), size, index=index)

def txt(im, xy, string, size, style='sans', color=INK, anchor='la', stroke=0):
    f = font(style, round(size))
    ImageDraw.Draw(im).text(xy,string,font=f,fill=color,anchor=anchor,stroke_width=stroke)
    return f.getlength(string)

@lru_cache(maxsize=12)
def mark(size):
    svg = REPO/'website-assets/riftlet.svg'
    png = resvg_py.svg_to_bytes(svg_path=str(svg),width=size,height=size)
    return Image.open(io.BytesIO(png)).convert('RGBA')

def fit(im,size):
    return ImageOps.fit(im,size,method=Image.Resampling.LANCZOS)

def ease(a):
    v = min(1.,max(0.,a))
    return v*v*(3.-2.*v)

def mix(a,b,v): return a+(b-a)*v

def s(t,a,b): return ease((t-a)/(b-a))

def smoothpoints(t, points):
    for (ta,a),(tb,b) in zip(points,points[1:]):
        if t < tb:
            v=s(t,ta,tb)
            return tuple(mix(x,y,v) for x,y in zip(a,b))
    return points[-1][1]

def viewport(im,cx,cy,wide,out,angle=0):
    """Rectilinear virtual lens. Coordinates are in source pixels."""
    w,h=out
    z=wide/w
    theta=math.radians(angle)
    ux,uy=z*math.cos(theta),z*math.sin(theta)
    mat=np.array([[ux,-uy,cx-.5*w*ux+.5*h*uy],
                  [uy,ux,cy-.5*w*uy-.5*h*ux]],dtype=np.float32)
    return Image.fromarray(cv2.warpAffine(np.asarray(im),mat,out,flags=cv2.INTER_CUBIC|cv2.WARP_INVERSE_MAP,borderMode=cv2.BORDER_REPLICATE))

PROOF = {
    'en': dict(masthead='P A C E', desk='PHOTO DESK     /     06', title='Track study',
               captions=('THE BANKED TURN', 'THE INNER LINE'), series='VELODROME  /  SERIES 06',
               stamp='STUDIO PROOF', category='CYCLING   /   CONTACT SHEET', filename='Track study.pdf'),
    'zh-CN': dict(masthead='节  奏', desk='图片编辑部     /     06', title='赛道习作',
                  captions=('压弯瞬间', '赛道内线'), series='自行车场  /  系列 06',
                  stamp='工作室校样', category='场地自行车   /   摄影样张', filename='赛道习作.pdf'),
}
MENUS = {
    'en': ('File     Edit     View     History     Bookmarks     Profiles     Tab     Window     Help',
           'Sat Nov 14    10:24'),
    'zh-CN': ('文件     编辑     视图     历史记录     书签     个人资料     标签页     窗口     帮助',
              '11月14日 周六    10:24'),
}

def sheet_picture(pic, blue=False, lang='en'):
    # A designed photographic spread, displayed in a real-world working context.
    # Both photo rectangles have the exact same aspect as the screenshot bitmap.
    im=Image.new('RGB',(1312,1344),'#F3EFE6')
    d=ImageDraw.Draw(im)
    copy=PROOF[lang]
    zh=lang=='zh-CN'
    mast='zh' if zh else 'bold'
    notes='zh-light' if zh else 'mono'
    title='zh-serif' if zh else 'serif'
    txt(im,(64,51),copy['masthead'],43,mast)
    txt(im,(1248,67),copy['desk'],19,notes,anchor='ra')
    d.line((64,122,1248,122),fill=INK,width=2)
    txt(im,(58,146),copy['title'],134 if zh else 147,title)
    txt(im,(1246,239),'02' if blue else '01',50,'serif',anchor='ra')
    im.paste(fit(pic,(1184,790)),(64,345))
    txt(im,(64,1160),copy['captions'][int(blue)],27,mast)
    txt(im,(1248,1161),copy['series'],20,notes,anchor='ra')
    d.line((64,1248,1248,1248),fill='#908E85',width=2)
    txt(im,(64,1277),copy['stamp'],17,notes)
    txt(im,(1246,1277),copy['category'],17,notes,anchor='ra')
    return im

def rounded(size,r):
    mask=Image.new('L',size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,size[0]-1,size[1]-1),radius=r,fill=255)
    return mask

@lru_cache(maxsize=5)
def shade_box(w,h,r):
    im=Image.new('RGBA',(w+100,h+100))
    d=ImageDraw.Draw(im); d.rounded_rectangle((50,56,50+w,56+h),radius=r,fill=(17,22,24,74))
    return im.filter(ImageFilter.GaussianBlur(19))

def window_paste(base, top, xy):
    x,y=xy
    sh=shade_box(*top.size,20)
    base.paste(sh,(x-50,y-48),sh)
    base.paste(top,xy,top)

class Set:
    scale=2
    world=(1440,875)
    chrome_xy=(593,172)
    tray_xy=(1223.27,370.18)
    def __init__(self,lang='en'):
        self.lang=lang
        self.a,self.b,self.desk=[Image.open(ART/(n+'.png')).convert('RGB') for n in ('banked','infield','workbench')]
        self.finger=Image.open(ART/'trackpad.png').convert('RGB')
        self.sheets=[sheet_picture(self.a,lang=lang),sheet_picture(self.b,True,lang=lang)]
        self.tray=Tray(ART/'banked.png',ART/'infield.png')
        # A matte-paper desktop with a broad, dark green sweep. Both windows
        # have a mild ambient and contact shadow, without synthetic light effects.
        w,h=self.world; sw,sh=w*2,h*2
        yy,xx=np.mgrid[0:sh,0:sw].astype(np.float32)
        pigment=np.clip(.07+.83*(xx/sw)**1.5+.26*(yy/sh)+.12*np.sin(xx/sw*5+yy/sh*4),0,1)
        rng=np.random.default_rng(176)
        pigments=np.array([217,209,185])[None,None,:]*(1-pigment[:,:,None])+np.array([63,95,86])[None,None,:]*pigment[:,:,None]
        wall=np.clip(pigments+rng.normal(0,1.10,(sh,sw,1)),0,255).astype('uint8')
        base=Image.fromarray(wall); menu=Image.new('RGB',(sw,49),'#D8DCD1')
        txt(menu,(29,7),'\uf8ff',27,'sans')
        txt(menu,(81,10),'Chrome',25,'bold')
        labels, clock=MENUS[lang]
        ui='zh-light' if lang=='zh-CN' else 'sans'
        txt(menu,(211,11),labels,24,ui)
        txt(menu,(sw-27,11),clock,24,ui,anchor='ra')
        base.paste(menu,(0,0)); self.empty=base
        self.walls=[self.proof_window(i) for i in range(2)]
        self._tray_frames={}

    def proof_window(self,idx):
        # Preview document in the adjacent window; Chrome remains frontmost.
        im=self.empty.copy()
        win=Image.new('RGBA',(1136,1376),'#EFEDE7')
        d=ImageDraw.Draw(win)
        d.rectangle((0,0,1136,63),fill='#EFECE5'); d.line((0,62,1135,62),fill='#C2BEB5',width=2)
        for x,c in zip((29,58,87),('#DA827D','#D9BB73','#83B990')):
            d.ellipse((x-9,23,x+9,41),fill=c)
        txt(win,(550,19),PROOF[self.lang]['filename'],24,'zh' if self.lang=='zh-CN' else 'medium',anchor='ma')
        # Both proofs keep the same margins. Switching pages does not change the draft.
        win.paste(self.sheets[idx].resize((1136,1164),Image.Resampling.LANCZOS),(0,95))
        win.putalpha(rounded(win.size,20))
        window_paste(im,win,(34,132))
        return im

    def frame_world(self,t,cursor=True):
        im=self.walls[int(t>=7.19)].copy()
        ch=draw_window(t,self.a,scale=2,lang=self.lang)
        window_paste(im,ch,tuple(v*2 for v in self.chrome_xy))
        plate=self.tray.render(t)
        # Bound the cache to the six stable product states; transition keys are ephemeral.
        key=id(plate)
        if key in self._tray_frames and self._tray_frames[key][0] is plate: scaled=self._tray_frames[key][1]
        else:
            ratio=180/246*2/4
            scaled=plate.resize((round(plate.width*ratio),round(plate.height*ratio)),Image.Resampling.LANCZOS)
            if len(self._tray_frames)>12:self._tray_frames.clear()
            self._tray_frames[key]=(plate,scaled)
        im.paste(scaled,tuple(round(v*2) for v in self.tray_xy),scaled)
        if cursor:
            x,y=smoothpoints(t,[(0,(890,533)),(3,(890,533)),(5.6,(524,526)),(8.9,(539,500)),(11.70,(1035,536)),(12.62,(1110,517)),(13.13,(1300.7,442.6)),(13.40,(1300.7,442.6)),(13.89,(1113,619)),(14.6,(829,573)),(16.7,(888,549)),(17.45,(902,552)),(22,(907,555))])
            arrow(im,2*x,2*y,2)
        return im
    def world_view(self,t,cx,cy,width,dims):
        return viewport(self.frame_world(t),2*cx,2*cy,2*width,dims)
    def physical(self,t,dims,center,wide):
        # Calibrated screen replacement in the original 1672 x 941 photo.
        im=self.desk.copy()
        content=self.frame_world(t).resize((1057,642),Image.Resampling.LANCZOS)
        content=Image.blend(content,Image.new('RGB',content.size,(103,96,91)),.055)
        panel=rounded(content.size,12); pd=ImageDraw.Draw(panel)
        pd.rounded_rectangle((479,-5,579,17),radius=5,fill=0)
        im.paste(content,(328,33),panel)
        return viewport(im,*center,wide,dims)

def arrow(im,x,y,scale):
    d=ImageDraw.Draw(im); pts=[(0,0),(1,20),(6.2,15.2),(10.2,23),(13.7,21.4),(9.8,14),(17,13.4)]
    p=[(round(x+i*scale),round(y+j*scale)) for i,j in pts]
    d.polygon(p,fill='#191919');d.line(p+[p[0]],fill='#FAFAFA',width=max(1,round(1.35*scale)),joint='curve')
