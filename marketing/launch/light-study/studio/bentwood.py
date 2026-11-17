"""A continuous, photographed design desk. All movement is authored at delivery cadence."""
from functools import lru_cache
from math import cos, sin, pi, floor
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from art import ROOT, MARK, tray_sprite, POSITIONS
from platforms import SONGTI
from bentwood_score import make_mix

FPS, SECONDS = 60, 31
W,H=1600,900
PHOTO=Image.open(ROOT/"originals/bentwood.png").convert("RGB")
BOX=(882,310,1432,690)
CROP=PHOTO.crop(BOX)
S=1.5
CREAM="#fdfbf4"
INK="#262837"
PLUM="#36384d"
GRAY="#626578"
TAU=2*pi


def ramp(t,a,b):
    v=min(1,max(0,(t-a)/(b-a)))
    return v*v*v*(10+v*(-15+6*v))


def interpolate(t,keys):
    for (a,one),(b,two) in zip(keys,keys[1:]):
        if t<=b:
            u=ramp(t,a,b)
            return tuple(x+(y-x)*u for x,y in zip(one,two))
    return keys[-1][1]


@lru_cache(maxsize=128)
def font(size,style):
    if style=="title":
        return ImageFont.truetype(str(SONGTI),round(size*S),index=3)
    if style=="latin":
        return ImageFont.truetype(str(ROOT/"native-demo/edit/instrument-serif.ttf"),round(size*S))
    if style=="mono":
        return ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf",round(size*S))
    return ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc",round(size*S),index=0)


class Surface:
    def __init__(self,w,h):
        self.im=Image.new("RGBA",(round(w*S),round(h*S)))
        self.pen=ImageDraw.Draw(self.im)
    def rect(self,b,ink,r=0,stroke=None):
        self.pen.rounded_rectangle(tuple(round(v*S) for v in b),round(r*S),fill=ink,outline=stroke,width=2)
    def line(self,xy,ink,width=1):
        self.pen.line(tuple(round(v*S) for v in xy),fill=ink,width=max(1,round(width*S)))
    def words(self,x,y,words,size,style="body",ink=INK):
        self.pen.text((x*S,y*S),words,font=font(size,style),fill=ink,anchor="lt")
    def pic(self,im,box):
        x,y,w,h=box
        p=im.resize((round(w*S),round(h*S)),Image.Resampling.LANCZOS)
        self.im.paste(p,(round(x*S),round(y*S)),p if p.mode=="RGBA" else None)


def shadow_frame(w,h,r,color):
    a=Surface(w+80,h+90)
    a.rect((40,52,w+40,h+52),(28,23,48,74),r)
    a.im=a.im.filter(ImageFilter.GaussianBlur(16*S));a.pen=ImageDraw.Draw(a.im)
    a.rect((40,35,w+40,h+35),color,r,"#fffcff")
    return a


class Shot:
    def __init__(self,sz=1.2):
        self.s=sz
        self.im=Image.new("RGB",(round(W*sz),round(H*sz)))
    def layer(self,sprite,x,y,w,alpha=1,angle=0):
        # Map the centre of one texture to the film plane with a floating-point
        # inverse affine. This retains subpixel translation at 60 Hz.
        if alpha<=0:return
        sw,sh=sprite.size
        k=w*self.s/sw
        xx=x*self.s; yy=y*self.s
        co,si=cos(angle),sin(angle)
        dx=k*(abs(co)*sw+abs(si)*sh)/2+2
        dy=k*(abs(si)*sw+abs(co)*sh)/2+2
        l=max(0,floor(xx-dx));r=min(self.im.width,int(xx+dx+1))
        top=max(0,floor(yy-dy));bot=min(self.im.height,int(yy+dy+1))
        if l>=r or top>=bot:return
        mat=(co/k,si/k,sw/2+((l-xx)*co+(top-yy)*si)/k,-si/k,co/k,sh/2+(-(l-xx)*si+(top-yy)*co)/k)
        tile=sprite.transform((r-l,bot-top),Image.Transform.AFFINE,mat,Image.Resampling.BICUBIC)
        mask=tile.getchannel("A") if tile.mode=="RGBA" else None
        if alpha<.999:
            mask=mask.point(lambda v:round(v*alpha)) if mask else Image.new("L",tile.size,round(255*alpha))
        self.im.paste(tile,(l,top),mask)


@lru_cache(maxsize=1)
def backdrop():
    # Raking studio light on a lavender set. Colour noise is fixed in the set.
    w,h=2160,1400
    x,y=np.meshgrid(np.linspace(-1,1,w,dtype='f'),np.linspace(-1,1,h,dtype='f'))
    light=10*np.exp(-((x+.73)**2+(y+.6)**2)*2)-22*(1/(1+np.exp(-11*(x*.28+y-.38))))-8*x
    noise=np.random.default_rng(23).normal(0,.52,(h,w))
    return Image.fromarray(np.stack([(v+light+noise).clip(0,255) for v in (210,209,223)],axis=-1).astype('uint8'))


@lru_cache(maxsize=1)
def board():
    a=shadow_frame(1040,648,11,"#f8f6ee")
    a.pic(PHOTO,(59,54,1002,564))
    a.words(61,638,"弯木椅",25,"title")
    a.words(825,642,"材料与结构研究",19,"body",GRAY)
    return a.im


def board_box(x,y,w):
    # Coordinates of the exact selected image sample on the moving board.
    scale=w/1120
    ox=x-w/2+59*scale;oy=y-738*scale/2+54*scale
    return tuple((ox+v*1002/PHOTO.width*scale if i%2==0 else oy+v*564/PHOTO.height*scale) for i,v in enumerate(BOX))


@lru_cache(maxsize=60)
def draft(attached,typed,continuation):
    a=shadow_frame(860,449,26,CREAM)
    for i,c in enumerate(("#e5a59b","#e8d49b","#adc7ab")):a.rect((68+i*19,60,77+i*19,69),c,5)
    a.words(161,53,"ChatGPT",22)
    a.words(674,57,"Chrome",19,"body",GRAY)
    a.line((41,99,898,99),"#dedbd4")
    a.words(82,128,"家具设计评审",25,"body",GRAY)
    a.rect((70,191,866,453),"#ffffff",25,"#d7d7cf")
    if attached:
        a.pic(CROP,(100,208,135,93))
    baseline=315 if attached else 268
    a.words(100,baseline,"这个弯角能再薄一点吗？"[:typed],41,"title")
    if continuation:
        a.words(102,371,"想保留这几层木纹。"[:continuation],30)
    a.words(96,411,"+",26)
    a.rect((803,397,842,436),PLUM,20)
    a.line((822,426,822,406),"#ffffff",2)
    a.line((815,414,822,406,829,414),"#ffffff",2)
    return a.im


def label(words,size,style="body",ink=INK):
    f=font(size,style)
    b=f.getbbox(words,anchor="lt")
    a=Surface((b[2]-b[0])/S+12,(b[3]-b[1])/S+12)
    a.words(4,4,words,size,style,ink)
    return a.im


label=lru_cache(maxsize=70)(label)


def lettering(s,x,y,words,size,alpha=1,style="body",ink=INK,scale=1):
    tex=label(words,size,style,ink)
    w,h=tex.width/S*scale,tex.height/S*scale
    s.layer(tex,x+w/2,y+h/2,w,alpha)


@lru_cache(maxsize=1)
def cursor_sprite():
    a=Surface(44,55)
    pts=[(3,3),(4,39),(13,30),(21,48),(28,44),(20,27),(35,25),(3,3)]
    px=[(int(x*S),int(y*S)) for x,y in pts]
    a.pen.polygon(px,fill="#282936");a.pen.line(px,fill="#fff",width=3)
    return a.im


def pointer(s,x,y,k=1,alpha=1):
    s.layer(cursor_sprite(),x+18*k,y+22*k,42*k,alpha)


def selection(s,box,z,alpha):
    if alpha<=0:return
    x,y,r,b=box
    r=x+max(2,(r-x)*z); b=y+max(2,(b-y)*z)
    layer=Image.new("RGBA",s.im.size);p=ImageDraw.Draw(layer)
    rect=tuple(int(v*s.s) for v in (x,y,r,b))
    p.rectangle(rect,outline=(255,255,255,round(240*alpha)),width=max(1,round(2*s.s)))
    for cx,cy in ((x,y),(x,b),(r,y),(r,b)):
        radius=3*s.s;p.ellipse((cx*s.s-radius,cy*s.s-radius,cx*s.s+radius,cy*s.s+radius),fill=(255,255,255,round(255*alpha)))
    s.im.paste(layer,(0,0),layer)


# Centre x, centre y, screen width. Shot positions share their easing at every
# boundary; the board and draft overlap in depth as the user's attention shifts.
BOARD=((0,(1339,432,1210)),(3.1,(1221,436,1130)),(5.45,(776,440,1590)),
       (8.8,(770,429,1460)),(12.3,(480,419,1090)),(15.6,(153,478,720)),
       (18.3,(42,488,620)),(24,(-195,469,460)),(26,(-350,466,420)))
DRAFT=((0,(526,497,1000)),(3.1,(555,477,960)),(5.45,(-400,585,855)),
       (12.3,(-421,563,824)),(15.6,(605,468,936)),(18.3,(583,476,1007)),
       (20.15,(576,484,1001)),(23.8,(746,476,1240)),(26,(786,478,1248)))
TRAY=((0,(1870,512,400)),(8.0,(1845,508,430)),(11.05,(1290,525,478)),
      (12.8,(1227,499,600)),(15.6,(1377,505,369)),(18.3,(1335,501,422)),
      (20.15,(1369,518,389)),(23.8,(1783,540,338)),(26,(1791,540,318)))


def scene(t,scale):
    s=Shot(scale)
    s.layer(backdrop(),784-22*sin(t*.22),430+14*cos(t*.18),1810)
    bp=interpolate(t,BOARD); dp=interpolate(t,DRAFT); tr=interpolate(t,TRAY)
    typed=min(len("这个弯角能再薄一点吗？"),4+int(t*5.6))
    received=t>=18.9
    cont=round(9*ramp(t,20.65,23.23))
    dr=draft(received,typed,cont)
    def put_board():
        s.layer(board(),*bp,angle=-.028*(1-ramp(t,3.0,5.4))+.025*ramp(t,11.0,13.3))
    def put_draft():
        s.layer(dr,*dp)
    if 3.9<t<14.0:
        put_draft();put_board()
    else:
        put_board();put_draft()
    # Authored cut-out follows the exact sampled surface until capture, then
    # takes a shallow arc to the first cell. No fake filesystem or dialog.
    box=board_box(*bp)
    sel=ramp(t,6.0,7.75)
    selection(s,box,sel,ramp(t,5.83,6.05)*(1-ramp(t,8.16,8.5)))
    tx,ty,tw=tr
    empty_sprite=tray_sprite("")
    filled=tray_sprite("w")
    landing=ramp(t,8.32,10.95)
    swallowed=ramp(t,19.0,19.27)
    # 294 is the native sprite width including its shadow margins.
    unit=tw/294
    x1=tx+(63.75-123)*unit
    y1=ty+(57-57.5)*unit
    if landing<1:
        s.layer(empty_sprite if landing<.08 else tray_sprite("-"),tx,ty,tw)
    else:
        s.layer(empty_sprite,tx,ty,tw)
        if swallowed<1:
            s.layer(filled,tx,ty,tw,1-swallowed)
    if 0<landing<1:
        x0=(box[0]+box[2])/2;y0=(box[1]+box[3])/2
        x=x0+(x1-x0)*landing;y=y0+(y1-y0)*landing-64*sin(pi*landing)
        w=(box[2]-box[0])*(1-landing)+106.9*unit*landing
        s.layer(CROP,x,y,w,angle=-.035*sin(pi*landing))
    if 16.1<t<20.2:
        z=ramp(t,16.1,18.4)
        x=mix1(958,x1,z); y=mix1(686,y1,z)-48*sin(pi*z)
        pulse=sin(pi*ramp(t,18.46,18.78))
        pointer(s,x,y,1.2-.19*pulse,ramp(t,16.1,16.38)*(1-ramp(t,19.6,20.2)))
    # Editorial copy lives on the same film plane; UI is a labelled composition.
    if t<3.91:
        lettering(s,82,103-12*ramp(t,0,3.2),"就差一张图。",65,1-ramp(t,3.2,3.9),"title")
    if 10.7<t<15.0:
        a=ramp(t,10.7,11.5)*(1-ramp(t,14.15,15))
        lettering(s,83,778-18*ramp(t,10.7,12.1),"刚截的弯角，就在手边。",43,a,"title")
    if 15.3<t<24.85:
        a=ramp(t,15.3,16.0)*(1-ramp(t,24.15,24.85))
        words="不用翻文件。点一下就好。" if t<19.7 else "原来的问题，接着写。"
        switch=(1-ramp(t,19.3,19.7)) if t<19.7 else ramp(t,19.7,20.17)
        lettering(s,82,104-9*ramp(t,15.3,16.4),words,54,a*switch,"title")
    lettering(s,67,840,"Riftlet",22,.92,"latin")
    lettering(s,1411,843,"操作示意",19,.93)
    return s


def mix1(a,b,u):
    return a+(b-a)*u


@lru_cache(maxsize=1)
def closeback():
    # Close on the actual selected laminate, with ink falling across the left
    # margin. The photographed layers supply the line leading into the CTA.
    pic=PHOTO.crop((270,186,1510,884)).resize((1920,1080),Image.Resampling.LANCZOS)
    arr=np.asarray(pic,dtype='float32')
    x=np.linspace(0,1,arr.shape[1])
    attenuation=(.14+.74*ramp_array(x,.28,.96))[None,:,None]
    tint=np.array([15,17,24],dtype='float32')
    return Image.fromarray((arr*attenuation+tint*(1-attenuation)).astype('uint8'))


def ramp_array(x,a,b):
    u=np.clip((x-a)/(b-a),0,1);return u*u*(3-2*u)


def close(t,scale):
    s=Shot(scale)
    u=(t-24.8)/(SECONDS-24.8)
    s.layer(closeback(),842-48*u,457+7*u,1764-52*u)
    word=ramp(t,25.0,26.15)
    benefit=ramp(t,25.65,26.85)
    cta=ramp(t,26.80,27.75)
    s.layer(MARK,115,159-10*word,81,word)
    lettering(s,73,245-18*word,"Riftlet",126,word,"latin",CREAM)
    lettering(s,78,451-19*benefit,"Mac 截图，一键附到草稿。",49,benefit,"title",CREAM)
    lettering(s,83,664-13*cta,"下载 Mac 版",32,cta,"body","#d4ffe4")
    lettering(s,80,736-13*cta,"riftlet.com",37,cta,"mono",CREAM)
    return s


def frame(t,scale=1.2):
    POSITIONS["w"]=CROP
    if t<24.8:return scene(t,scale).im
    end=close(t,scale)
    if t>=25.55:return end.im
    return Image.blend(scene(t,scale).im,end.im,ramp(t,24.8,25.55))


def render():
    out=ROOT/"films/at-hand.brand.zh-CN.mp4"
    with TemporaryDirectory() as tmp:
        wav=Path(tmp)/"desk.wav";make_mix(wav,FPS,SECONDS)
        args=[imageio_ffmpeg.get_ffmpeg_exe(),"-y","-loglevel","error","-f","rawvideo","-pixel_format","rgb24","-video_size","1920x1080","-framerate",str(FPS),"-i","-","-i",str(wav),"-vf","scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p","-c:v","libx264","-crf","17","-preset","fast","-threads","4","-color_range","tv","-colorspace","bt709","-color_trc","bt709","-color_primaries","bt709","-c:a","aac","-b:a","192k","-movflags","+faststart",str(out)]
        with subprocess.Popen(args,stdin=subprocess.PIPE) as proc:
            for i in range(FPS*SECONDS):
                proc.stdin.write(frame(i/FPS).tobytes())
            proc.stdin.close()
            if proc.wait():raise RuntimeError("encode failed")


if __name__=="__main__":render()
