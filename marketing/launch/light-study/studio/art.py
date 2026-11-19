"""Editable art direction for the Light study sequence. Coordinates are in design pixels."""
from functools import lru_cache
from io import BytesIO
from math import cos, pi, sin
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
FONTS = ROOT.parents[2] / "website-assets" / "fonts"
PAPER = "#f4f1e8"
INK = "#172621"
MUTED = "#516258"
LIGHT = "#f8f7ed"
MINT = "#bfdec8"
PLATE = Image.open(ROOT / "originals/wedge.png").convert("RGB")
DARK = Image.open(ROOT / "originals/grazing-light.png").convert("RGB")
DETAIL = PLATE.crop((181, 490, 825, 935))
ANGLE = DARK.crop((600, 419, 1312, 911))
MARK = Image.open(ROOT / "originals/riftlet-mark.png").convert("RGBA")
KEY = Image.open(ROOT / "originals/native-camera-key.png").convert("RGB")
RES = Image.Resampling
POSITIONS = {"a": DETAIL, "b": ANGLE}


def clamp(t):
    return max(0, min(1, t))


def ease(t):
    t = clamp(t)
    return t*t*(3-2*t)


def mix(a, b, t):
    return a + (b-a)*t


@lru_cache(maxsize=4)
def instrument(style):
    f = TTFont(FONTS / ("instrument-serif-italic.woff2" if style == "italic" else "instrument-serif.woff2"))
    f.flavor = None
    out = BytesIO()
    f.save(out)
    return out.getvalue()


@lru_cache(maxsize=600)
def face(style, size):
    size = max(1, size)
    if style in ("serif","italic"):
        return ImageFont.truetype(BytesIO(instrument(style)),size)
    paths = {
        "sans": "/System/Library/Fonts/HelveticaNeue.ttc",
        "mono": "/System/Library/Fonts/SFNSMono.ttf",
        "zh": "/System/Library/Fonts/STHeiti Light.ttc",
        "zhbold": "/System/Library/Fonts/STHeiti Medium.ttc",
    }
    return ImageFont.truetype(paths[style],size)


class Art:
    def __init__(self,w=1600,h=900,scale=1,base=PAPER):
        self.w, self.h, self.s = w,h,scale
        self.img = Image.new("RGB",(round(w*scale),round(h*scale)),base)
        self.d = ImageDraw.Draw(self.img)

    def points(self,coords):
        return tuple(round(v*self.s) for v in coords)

    def txt(self,x,y,value,size,style="sans",color=INK,anchor="la"):
        self.d.text(self.points((x,y)),value,font=face(style,round(size*self.s)),fill=color,anchor=anchor,stroke_width=0)

    def line(self,pts,color,width=1):
        self.d.line(self.points(pts),fill=color,width=max(1,round(width*self.s)))

    def box(self,box,fill,rad=0,outline=None,width=1):
        self.d.rounded_rectangle(self.points(box),radius=round(rad*self.s),fill=fill,outline=outline,width=max(1,round(width*self.s)))

    def put(self,im,x,y,w,h=None,alpha=1):
        h = w*im.height/im.width if h is None else h
        size=self.points((w,h))
        if min(size)<=0 or alpha<=0:
            return
        scaled=im.resize(size,RES.LANCZOS if w>80 else RES.BICUBIC)
        mask = scaled.getchannel("A") if scaled.mode=="RGBA" else None
        if alpha < 1:
            mask = mask.point(lambda z:int(z*alpha)) if mask is not None else Image.new("L",size,round(255*alpha))
        self.img.paste(scaled,self.points((x,y)),mask)

    def full(self,im,zoom=1,focus=(.5,.5)):
        size=self.img.size
        aspect=self.w/self.h
        cw=min(im.width,im.height*aspect)/zoom
        ch=cw/aspect
        x=(im.width-cw)*focus[0]
        y=(im.height-ch)*focus[1]
        self.img.paste(im.resize(size,RES.BICUBIC,(x,y,x+cw,y+ch)))

    def mark(self,x,y,size):
        self.put(MARK,x,y,size,size)

    def foot(self,dark=False,caption="DESIGN ANIMATION"):
        color=MINT if dark else MUTED
        self.txt(75,self.h-53,"RIFTLET   /   LIGHT STUDY",15,"mono",color)
        self.txt(self.w-75,self.h-53,caption,15,"mono",color,"ra")


@lru_cache(maxsize=20)
def tray_sprite(keys):
    # Intrinsic grid follows the release's 246 unit tray with two columns.
    # Three extra pixels of inner rim frame the contained bitmap; no crop.
    u=3
    w=246*u
    h=(212 if len(keys)>=2 else 115)*u
    margin=24*u
    sz=(w+margin*2,h+margin*2)
    shape=(margin,margin,w+margin-1,h+margin-1)
    mask=Image.new("L",sz)
    ImageDraw.Draw(mask).rounded_rectangle(shape,25*u,fill=255)
    xx,yy=np.meshgrid(np.linspace(0,1,sz[0]),np.linspace(0,1,sz[1]))
    tone=6*np.cos((xx*.8+yy*.48)*pi)+3*np.exp(-((xx-.82)/.15)**2)
    rgb=np.stack([233+tone,233+tone,229+tone],axis=-1).clip(0,255).astype("uint8")
    body=Image.fromarray(rgb).convert("RGBA")
    body.putalpha(mask)
    cast=Image.new("RGBA",sz)
    shadow=Image.new("L",sz)
    ImageDraw.Draw(shadow).rounded_rectangle((margin+u,margin+u*6,w+margin,h+margin+u*6),u*25,fill=75)
    cast.putalpha(shadow.filter(ImageFilter.GaussianBlur(u*8)))
    cast=Image.alpha_composite(cast,body)
    d=ImageDraw.Draw(cast)
    d.rounded_rectangle(shape,25*u,outline=(255,255,251,210),width=2)
    def place(payload,col,row,camera=False):
        cellw,cellh=113.5,80
        cx=(7 if col==0 else 125.5)+cellw/2
        cy=17+row*97+cellh/2
        fac=min((cellw-5.5)/payload.width,(cellh-5.5)/payload.height)
        width,height=(cellw,cellh) if camera else (payload.width*fac,payload.height*fac)
        x=round(margin+(cx-width/2)*u)
        y=round(margin+(cy-height/2)*u)
        ww,hh=round(width*u),round(height*u)
        if camera:
            elem=payload.resize((ww,hh),RES.LANCZOS).convert("RGBA")
            m=Image.new("L",elem.size)
            ImageDraw.Draw(m).rounded_rectangle((0,0,ww-1,hh-1),11*u,fill=255)
            elem.putalpha(m)
            cast.alpha_composite(elem,(x,y))
        else:
            pad=round(2.75*u)
            b=(x-pad,y-pad,x+ww+pad,y+hh+pad+u)
            d.rounded_rectangle((b[0],b[1]+2,b[2],b[3]+3),9*u,fill="#cecfca")
            d.rounded_rectangle(b,9*u,fill="#fbfaf8")
            elem=payload.resize((ww,hh),RES.LANCZOS).convert("RGBA")
            m=Image.new("L",elem.size)
            ImageDraw.Draw(m).rounded_rectangle((0,0,ww-1,hh-1),5*u,fill=255)
            elem.putalpha(m)
            cast.alpha_composite(elem,(x,y))
    for index,key in enumerate(keys):
        if key != "-":
            place(POSITIONS[key],index%2,index//2)
    place(KEY,len(keys)%2,len(keys)//2,True)
    return cast


def tray(a,x,bottom,width,keys,alpha=1):
    im=tray_sprite(keys)
    factor=width/246
    height=(212 if len(keys)>=2 else 115)*factor
    a.put(im,x-24*factor,bottom-height-24*factor,294*factor,alpha=alpha)


def grow_tray(a,x,bottom,width,progress):
    """Open upward, shifting the camera into its native lower-left cell."""
    q=ease(progress)
    if q<=0:
        tray(a,x,bottom,width,"a")
        return
    if q>=1:
        tray(a,x,bottom,width,"ab")
        return
    unit=width/246
    h=(115+97*q)*unit
    top=bottom-h
    a.box((x+1,top+4,x+width+1,bottom+6),"#ced0c6",25*unit)
    a.box((x,top,x+width,bottom),"#ecece8",25*unit,"#fffefa",1)
    def tile(im,cx,cy,opacity=1):
        tw=106.9*unit
        th=tw*im.height/im.width
        pad=2.5*unit
        if opacity==1:
            a.box((cx-tw/2-pad,cy-th/2-pad,cx+tw/2+pad,cy+th/2+pad),"#fafaf8",8*unit)
        a.put(im,cx-tw/2,cy-th/2,tw,th,opacity)
    tile(DETAIL,x+63.5*unit,top+57*unit)
    if q>.17:
        tile(ANGLE,x+182*unit,top+57*unit,ease((q-.17)/.83))
    kx=x+mix(125.5,7,q)*unit
    ky=bottom-(115-17)*unit
    corner=Image.new("L",KEY.size,0)
    ImageDraw.Draw(corner).rounded_rectangle((0,0,KEY.width-1,KEY.height-1),21,fill=255)
    key=KEY.convert("RGBA")
    key.putalpha(corner)
    a.put(key,kx,ky,113.5*unit,80*unit)


def cursor(a,x,y,press=0):
    factor = 1-.12*press
    pts=[(0,0),(1,29),(8,23),(13,34),(18,31),(13,20),(24,19),(0,0)]
    pts=[(round((x+dx*factor)*a.s),round((y+dy*factor)*a.s)) for dx,dy in pts]
    a.d.polygon(pts,fill="#192721")
    a.d.line(pts,fill="#fffef8",width=max(1,round(2*a.s)))


def corners(a,box,color,width=2,length=20):
    l,t,r,b=box
    for x,y,sx,sy in ((l,t,1,1),(r,t,-1,1),(l,b,1,-1),(r,b,-1,-1)):
        a.line((x+sx*length,y,x,y,x,y+sy*length),color,width)


def aperture_scene(a,t):
    a.full(DARK,1.025+.07*ease(t/4.5),(.58,.58))
    a.mark(77,61,42)
    a.txt(134,68,"Riftlet",28,"sans",LIGHT)
    y=192-16*ease(t/2.7)
    a.txt(75,y,"Look",145,"serif",LIGHT)
    a.txt(75,y+120,"closer.",145,"italic",MINT)
    a.foot(True,"OPTICAL STUDY  /  A")


def selection_scene(a,t):
    # Locked crop coordinates let the selected image and tray thumbnail match.
    a.full(PLATE)
    a.txt(72,58,"OPTICAL STUDY   /   DAYLIGHT",19,"mono",INK)
    a.txt(72,108,"Where do the",76,"serif",INK)
    a.txt(72,184,"two lines meet?",76,"italic",INK)
    z=ease((t-.45)/1.4)
    l,top,r,b=181/1672*a.w,490/941*a.h,825/1672*a.w,935/941*a.h
    right=mix(l+18,r,z)
    bottom=mix(top+18,b,z)
    if t>.42:
        corners(a,(l,top,right,bottom),LIGHT,2,22)
        if z>.94:
            a.box((l+9,top+10,l+149,top+40),"#192e25",3)
            a.txt(l+20,top+15,"DETAIL  A",15,"mono",LIGHT)


def page(a):
    a.full(paper_stage(a.w,a.h))


@lru_cache(maxsize=12)
def paper_stage(w,h):
    # Oblique window light: calibrated falloff and one penumbra on a matte desk.
    xx,yy=np.meshgrid(np.linspace(0,1,w,dtype='float32'),np.linspace(0,1,h,dtype='float32'))
    shade=12/(1+np.exp(-14*(xx+.24*yy-.93)))+7*yy+5*np.exp(-((xx-.9+.33*yy)/.13)**2)
    dither=np.random.default_rng(17).normal(0,.52,(h,w))
    return Image.fromarray(np.stack([248-shade+dither,246-shade+dither,237-shade+dither],axis=-1).clip(0,255).astype('uint8'))


def arrival_scene(a,t):
    page(a)
    e=ease(t/2.35)
    x,bot,w=900-12*e,668-13*e,555+10*e
    a.txt(75,62,"RIFTLET    /    MACOS",19,"mono",MUTED)
    if t>.70:
        reveal=ease((t-.70)/.75)
        tone=tuple(round(mix(bg,fg,reveal)) for bg,fg in zip((245,244,235),(23,38,33)))
        a.txt(74,247-11*e,"Keep that",108,"serif",tone)
        a.txt(74,347-11*e,"detail.",116,"italic",tone)
    if t>2.0:
        reveal=ease((t-2.0)/.4)
        tone=tuple(round(mix(bg,fg,reveal)) for bg,fg in zip((245,244,235),(81,98,88)))
        a.txt(77,544,"One screenshot, at the edge of your Mac.",29,color=tone)
    a.foot()
    tray(a,x,bot,w,"a" if t>=2.35 else "-")
    if t<2.35:
        # At the cut, the whole frame matches the previous shot. Only the
        # selected patch remains as the camera pulls back from the specimen.
        plate=Art(a.w,a.h,a.s)
        selection_scene(plate,4.5)
        reveal=ease(t/1.0)
        if reveal<1:
            a.img.paste(Image.blend(plate.img,a.img,reveal))
        unit=w/246
        tw,th=107.8*unit,74.5*unit
        dw,dh=mix(644/1672*a.w,tw,e),mix(445/941*a.h,th,e)
        tx=x+(7+(113.5-107.8)/2)*unit
        ty=bot-115*unit+(17+(80-74.5)/2)*unit
        a.put(DETAIL,mix(181/1672*a.w,tx,e),mix(490/941*a.h,ty,e),dw,dh)


def pair_scene(a,t):
    # A second image motivates a reverse angle. Its sampled crop travels into the
    # second cell; the camera tile below stays in the native release position.
    a.full(DARK,1.12-.09*ease(t/5),(.75,.58))
    a.txt(75,62,"OPTICAL STUDY   /   GRAZING LIGHT",19,"mono",MINT)
    a.txt(75,202,"Another",96,"serif",LIGHT)
    a.txt(75,296,"angle.",109,"italic",MINT)
    a.foot(True)
    e=ease((t-.9)/2.05)
    w=mix(511,577,e)
    x=mix(970,905,e)
    bottom=mix(696,712,e)
    if t<1:
        tray(a,x,bottom,w,"a",ease((t-.32)/.45))
    else:
        grow_tray(a,x,bottom,w,(t-1)/.48)
    if .2<t<1:
        corners(a,(572,397,1019,705),MINT,2,16)


def composer(a,x,y,w,h,received=False,typed="",caret=False):
    a.box((x,y+3,x+w,y+h+6),"#d0d0c6",31)
    a.box((x,y,x+w,y+h),"#fffefb",31,"#cfcec3",2)
    a.txt(x+32,y+24,"ChatGPT",25,"sans",INK)
    a.txt(x+w-32,y+27,"chatgpt.com",18,"mono",MUTED,"ra")
    a.line((x+2,y+76,x+w-2,y+76),"#e2e2d8",1)
    top=y+109
    if received:
        thumb=96
        a.put(DETAIL,x+34,top,thumb,thumb*DETAIL.height/DETAIL.width)
        top+=89
    a.txt(x+33,top,"Where do the two lines meet?",min(42,round(w*.052)),"sans",INK)
    if typed:
        a.txt(x+34,top+62,typed,29,"sans",MUTED)
        if caret:
            advance=a.d.textlength(typed,font=face("sans",round(29*a.s)))/a.s
            a.line((x+37+advance,top+69,x+37+advance,top+100),MUTED,2)
    elif caret:
        caret_x=x+33+a.d.textlength("Where do the two lines meet?",font=face("sans",round(min(42,round(w*.052))*a.s)))/a.s+2
        a.line((caret_x,top+8,caret_x,top+45),MUTED,2)
    a.txt(x+36,y+h-57,"+",34,color=MUTED)
    a.box((x+w-74,y+h-69,x+w-32,y+h-27),"#25332c",21)
    a.line((x+w-53,y+h-40,x+w-53,y+h-57),LIGHT,2)
    a.line((x+w-60,y+h-50,x+w-53,y+h-57,x+w-46,y+h-50),LIGHT,2)


def draft_scene(a,t):
    page(a)
    a.txt(75,62,"GOOGLE CHROME    /    CHATGPT DRAFT",19,"mono",MUTED)
    a.txt(74,127,"A click away.",94,"serif",INK)
    after=t>=4.45
    composer(a,75,312,905,390,after,caret=(not after and int(t*2)%2==0))
    x,bot,w=1121,647,405
    withdraw=ease((t-4.52)/.26)
    if withdraw<1:
        tray(a,x,bot,w,"ab")
    if withdraw>0:
        tray(a,x,bot,w,"b",withdraw)
    z=ease((t-.8)/2.65)
    if t<6.9:
        cursor(a,mix(1047,1199,z)+18*ease((t-5.6)/1.2),mix(733,399,z)+29*ease((t-5.6)/1.2),1-abs(clamp((t-3.67)/.42)*2-1))
    a.foot()


def close_scene(a,t):
    page(a)
    a.txt(75,62,"GOOGLE CHROME    /    CHATGPT DRAFT",19,"mono",MUTED)
    a.txt(77,202,"Your next",100,"serif",INK)
    a.txt(77,304,"thought.",107,"italic",INK)
    z=ease(t/3.5)
    typed="Follow the brighter ray."[:round(24*clamp((t-.2)/2.4))]
    composer(a,675-12*z,182,844,476,True,typed,caret=int(t*2)%2==0)
    a.foot()


def end_scene(a,t):
    a.full(DARK,1.075-.045*ease(t/4),(.35,.68))
    a.mark(75,82,78)
    a.txt(74,191,"Riftlet",162,"serif",LIGHT)
    a.txt(79,402,"From screenshot to draft.",53,"italic",MINT)
    a.txt(80,520,"For ChatGPT in Google Chrome on Mac",27,"sans",LIGHT)
    a.foot(True,"RIFTLET.COM    /    PUBLIC BETA")


def master(t,scale=1):
    a=Art(scale=scale)
    timeline=[(0,aperture_scene),(4.5,selection_scene),(9,arrival_scene),(14,pair_scene),(20,draft_scene),(29.5,close_scene),(33,end_scene)]
    for start,scene in reversed(timeline):
        if t>=start:
            scene(a,t-start)
            break
    return a.img
