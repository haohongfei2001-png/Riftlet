"""Two editorial workspaces on one timeline. Render a localized horizontal or vertical cut."""
import argparse
import io
import math
import os
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

import cv2
import imageio_ffmpeg
import numpy as np
import resvg_py
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter

from materials import ASSETS, shot, spread
from product import Product

ROOT = Path(__file__).resolve().parents[1]
CACHE = tempfile.TemporaryDirectory(prefix='riftlet-flow-fonts-')
PAPER, INK, TEAL = '#F9F7EE', '#152F29', '#146E5B'
FPS = 30
KINDS = (('source','trace','code'), ('math','reading','detail'))
cv2.setNumThreads(1)

def clamp(v):
    return max(0., min(1., v))

def ease(t, a, b):
    u = clamp((t-a)/(b-a))
    return u*u*(3-2*u)

def mix(a,b,t):
    return a+(b-a)*t

@lru_cache(maxsize=200)
def face(name, size):
    base=Path('/System/Library/Fonts')
    if name in ('serif','italic'):
        fname='instrument-serif'+('-italic' if name=='italic' else '')
        path=Path(CACHE.name)/(fname+'.ttf')
        if not path.exists():
            t=TTFont(ASSETS/'fonts'/(fname+'.woff2')); t.flavor=None; t.save(path)
        return ImageFont.truetype(str(path),size)
    file,index={'zh':('STHeiti Medium.ttc',1),'song':('Supplemental/Songti.ttc',6),
                'body':('HelveticaNeue.ttc',0),'medium':('HelveticaNeue.ttc',10),
                'mono':('Menlo.ttc',0)}[name]
    return ImageFont.truetype(str(base/file),size,index=index)

@lru_cache
def logo(size):
    return Image.open(io.BytesIO(resvg_py.svg_to_bytes(svg_path=str(ASSETS/'riftlet.svg'),
                                                      width=size,height=size))).convert('RGBA')

class Canvas:
    def __init__(self, size, s, background):
        self.size,self.s=size,s
        self.im=background.copy() if isinstance(background,Image.Image) else Image.new('RGB',self.xy(*size),background)

    def xy(self,*values):
        return tuple(round(v*self.s) for v in values)

    def text(self,x,y,text,size,name,color=INK,anchor='lt',width=None):
        f=face(name,max(1,self.xy(size)[0]))
        if width and f.getlength(text)>width*self.s:
            f=face(name,max(1,int(f.size*width*self.s/f.getlength(text))))
        ImageDraw.Draw(self.im).text(self.xy(x,y),text,font=f,fill=color,anchor=anchor)
        return f.getlength(text)/self.s

    def line(self,points,color,weight=1):
        ImageDraw.Draw(self.im).line([self.xy(*p) for p in points],fill=color,
                                     width=max(1,self.xy(weight)[0]),joint='curve')

    def roundbox(self,box,r,fill,edge=None,stroke=1):
        ImageDraw.Draw(self.im).rounded_rectangle(self.xy(*box),radius=self.xy(r)[0],fill=fill,
                                                   outline=edge,width=max(1,self.xy(stroke)[0]))

    def place(self,im,x,y):
        self.im.paste(im,self.xy(x,y),im if im.mode=='RGBA' else None)

    def brand(self,x,y,size,color):
        self.place(logo(self.xy(size)[0]),x,y)
        self.text(x+size*1.27,y+size*.015,'Riftlet',size*1.04,'serif',color)

@lru_cache(maxsize=24)
def ground(w,h,s,act):
    sw,sh=round(w*s),round(h*s)
    u,v=np.meshgrid(np.linspace(0,1,420,dtype='float32'),np.linspace(0,1,300,dtype='float32'))
    if act==0:
        c0,c1,c2=(19,44,40),(54,91,77),(30,67,62)
    else:
        c0,c1,c2=(253,250,240),(210,229,209),(240,213,187)
    a=np.exp(-((u-.78)**2/.21+(v-.31)**2/.42))[:,:,None]
    b=(.68*np.exp(-((u-.24)**2/.15+(v-.88)**2/.14)))[:,:,None]
    rgb=np.array(c0)*(1-a)+np.array(c1)*a
    rgb=rgb*(1-b)+np.array(c2)*b
    if act==1:
        # The light pages and the 0.5pt slit need a darker local surround.
        # Change the editorial desktop colour, keeping the native line intact.
        edge=np.exp(-((u-.946)**2/.025+(v-.49)**2/.27))[:,:,None]*.92
        rgb=rgb*(1-edge)+np.array([129,164,146])*edge
    return Image.fromarray(np.uint8(rgb)).resize((sw,sh),Image.Resampling.BICUBIC)

@lru_cache(maxsize=42)
def panel(w,h,r,s,color):
    pad=36
    shape=(round((w+2*pad)*s),round((h+2*pad)*s))
    box=(round(pad*s),round(pad*s),round((w+pad)*s)-1,round((h+pad)*s)-1)
    sh=Image.new('RGBA',shape)
    d=ImageDraw.Draw(sh)
    d.rounded_rectangle((box[0],box[1]+round(7*s),box[2],box[3]+round(7*s)),radius=r*s,fill=(21,40,31,52))
    sh=sh.filter(ImageFilter.GaussianBlur(11*s))
    ImageDraw.Draw(sh).rounded_rectangle(box,radius=r*s,fill=color,outline='#F5F5E9',width=max(1,round(s)))
    return sh

@lru_cache(maxsize=64)
def chip(kind,lang,size):
    im=ImageOps.fit(shot(kind,lang),(size,size),method=Image.Resampling.LANCZOS)
    mask=Image.new('L',im.size); ImageDraw.Draw(mask).rounded_rectangle((0,0,size-1,size-1),radius=size*.16,fill=255)
    im.putalpha(mask);return im

def cursor(c,x,y,scale=1):
    pts=[(0,0),(.8,22),(6.2,16.9),(11.2,25),(14.9,22.8),(10.1,15.7),(18.2,15)]
    coords=[(x+a*scale,y+b*scale) for a,b in pts]
    d=ImageDraw.Draw(c.im);d.polygon([c.xy(*p) for p in coords],fill='#14201D')
    c.line(coords+[coords[0]],'#FAFAF4',1.7*scale)

class Film:
    def __init__(self,lang,vertical,s=1.5):
        self.lang,self.zh,self.v,self.s=lang,lang=='zh-CN',vertical,s
        self.W,self.H=(720,1280) if vertical else (1280,720)
        self.duration=15 if vertical else 24
        self.arr=([1.,1.9,2.8],[6.2,7.12,8.]) if vertical else ([2.30,3.63,4.97],[10.30,11.63,12.97])
        self.click=([3.83],[9.,10.15]) if vertical else ([6.60],[15.,16.55])
        self.change=5.22 if vertical else 8.73
        self.outro=13.19 if vertical else 21.23
        self.prod=[Product([shot(k,lang) for k in group]) for group in KINDS]
        self.font='zh' if self.zh else 'medium'
        self.display='song' if self.zh else 'serif'
        self.plates={}

    def words(self,cn,en):
        return cn if self.zh else en

    def header(self,c,act):
        w,v=self.W,self.v
        light=PAPER if not act else INK
        muted='#B4D2C2' if not act else '#587869'
        c.brand(38 if v else 49,30,31,light)
        c.text(w-(38 if v else 50),40,'macOS   /   Chrome',16,'medium',muted,anchor='rt')
        c.line([(39,82),(w-39,82)],'#557569' if not act else '#B4C8B7',1)
        title=(self.words('调试，接着问。','Debug. Keep thinking.'),self.words('读题，接着算。','Read. Keep thinking.'))[act]
        c.text(35 if v else 46,111 if v else 103,title,65 if v else 61,self.display,light,width=w-130)
        form=(self.words('截图托盘','Screenshot Tray'),self.words('微缝','Micro Slit'))[act]
        if v: c.text(40,202,form,25,self.font,muted)
        else: c.text(w-52,130,form,27,self.font,muted,anchor='rt')

    def document(self,c,t,act,focus):
        arrivals=self.arr[act]
        # Incoming pages travel on the cut, then become still during the system capture.
        idx=sum(t>=at+.28 for at in arrivals[:-1])
        kind=KINDS[act][idx]
        page,box=spread(kind,self.lang)
        start=arrivals[idx-1]+.28 if idx else (self.change if act else 0)
        turn=1-ease(t,start,start+.32) if idx else 0.
        if self.v:
            x=mix(28,-752,focus); y=253+turn*43-85*focus; width=mix(660,670,focus)
        else:
            x=mix(49,-820,focus); y=198+turn*52+44*focus; width=mix(696,756,focus)
        # Flat camera over a printed page. A living registration frame marks the
        # exact pixels that also supply the edge thumbnail and the final attachment.
        ratio=width/page.width
        pw,ph=c.xy(width,width*page.height/page.width)
        # An opaque paper edge and two light sheets give the source page thickness.
        c.roundbox((x+5,y+9,x+width+5,y+width*2/3+9),2,'#99AA99' if act else '#799584')
        c.roundbox((x+3,y+4,x+width+3,y+width*2/3+4),1,'#DADDCF')
        key=(kind,pw,ph)
        if key not in self.plates:
            if len(self.plates)>34:self.plates.clear()
            self.plates[key]=page.resize((pw,ph),Image.Resampling.BICUBIC)
        c.place(self.plates[key],x,y)
        at=arrivals[idx]
        left,top,right,bottom=[x+z*ratio if i%2==0 else y+z*ratio for i,z in enumerate(box)]
        if at-.52<=t<=at+.19:
            hot_y=max(y+4,top-33)
            c.roundbox((left,hot_y,left+92,hot_y+27),6,'#182C26')
            c.text(left+10,hot_y+5,'⇧  ⌘  4',17,'mono','#FBFCF3')
        if at-.46<=t<=at+.23:
            drag=ease(t,at-.46,at-.025)
            rx,by=mix(left+10,right,drag),mix(top+7,bottom,drag)
            color='#0B8D74' if act or idx==1 else '#76E3B1'
            c.roundbox((left-2,top-2,rx+2,by+2),1,None,color,2)
            for xx,yy,dx,dy in ((left,top,1,1),(rx,top,-1,1),(left,by,1,-1),(rx,by,-1,-1)):
                c.line([(xx+dx*12,yy),(xx,yy),(xx,yy+dy*12)],color,3)
            c.line([(rx-7,by),(rx+7,by)],color,1.5);c.line([(rx,by-7),(rx,by+7)],color,1.5)
            if 0<=t-at<.115:
                alpha=round(105*(1-(t-at)/.115))
                overlay=Image.new('RGBA',c.xy(right-left,bottom-top),(255,254,239,alpha))
                c.place(overlay,left,top)
        return x,y

    def draft(self,c,t,act,focus):
        if self.v:
            w,h=639,246; x=38; y=mix(975,978,focus)
        else:
            w,h=637,168; x=mix(358,47,focus); y=mix(531,486,focus)
        c.place(panel(w,h,20,self.s,'#FFFDF8'),x-36,y-36)
        # The website separates current draft, typed words, and a user-controlled send arrow.
        head=44 if self.v else 35
        c.text(x+22,y+12,'ChatGPT',19,'medium',INK)
        c.text(x+w-23,y+13,self.words('Chrome 中的草稿','Draft in Chrome'),15,self.font,'#688073',anchor='rt')
        c.line([(x+1,y+head),(x+w-1,y+head)],'#DBE3D8',1)
        cs=self.click[act]
        attached=[(i,at+.23) for i,at in enumerate(cs) if t>=at+.23]
        tile=77 if self.v else 55
        for i,at in attached:
            z=.67+.33*ease(t,at,at+.17)
            sz=max(1,round(tile*z*self.s))
            c.place(chip(KINDS[act][i],self.lang,sz),x+20+i*(tile+12),y+head+10+(1-z)*tile)
        q=(self.words('为什么不能调用 map？','Why can’t I call map?'),self.words('为什么误差是 h²？','Why is the error h²?'))[act]
        tail=(self.words('items 有值吗？',' Is items undefined?'),self.words('请从展开式讲起。',' Start with the expansion.'))[act]
        write_start=((4.29 if self.v else 7.13),(10.82 if self.v else 17.25))[act]
        write_end=((5.07 if self.v else 8.47),(12.75 if self.v else 20.25))[act]
        n=int(len(tail)*ease(t,write_start,write_end))
        lift=ease(t,cs[0]+.23,cs[0]+.39)
        text_y=y+head+(23 if self.v else 17)+lift*(tile+2)
        line=q+tail[:n]
        available=w-(96 if not self.v else 59)
        length=c.text(x+21,text_y,line,25 if self.v else 22,self.font,INK,width=available)
        if t%1.05<.64 or write_start<t<write_end:
            c.line([(x+24+length,text_y-1),(x+24+length,text_y+(25 if self.v else 22))],TEAL,1.7)
        cy=y+h-22
        c.line([(x+21,cy),(x+35,cy)],'#4D6559',1.5);c.line([(x+28,cy-7),(x+28,cy+7)],'#4D6559',1.5)
        cx=x+w-28
        c.roundbox((cx-13,cy-13,cx+13,cy+13),13,INK)
        c.line([(cx,cy+6),(cx,cy-6)],'#FFFFFF',1.7)
        c.line([(cx-5,cy-1),(cx,cy-6),(cx+5,cy-1)],'#FFFFFF',1.7)
        return x+max(55,length*.7),text_y

    def workspace(self,t,act):
        v,w,h=self.v,self.W,self.H
        c=Canvas((w,h),self.s,ground(w,h,self.s,act))
        # Source-derived marginalia belong to the desk, behind the app.
        # The traced parabola crosses its tangent at x=1, as in the reading.
        if act:
            phase=ease(t,self.change+.15,self.arr[1][1]+.30)
            x0,y0=(80,884) if v else (533,577)
            sx,sy=(270,91) if v else (290,98)
            xs=np.linspace(0,2.08*phase,52)
            if phase>.025:
                c.line([(x0+j*sx,y0-j*j*sy) for j in xs],'#ABBB9F',1.35)
                c.line([(x0+.54*sx,y0-.08*sy),(x0+2.08*sx,y0-3.16*sy)],'#C8A58C',1.3)
        else:
            c.text(72 if v else 608,657 if v else 369,'items.map',89 if v else 111,
                   'mono','#355B4F')
        self.header(c,act)
        click=self.click[act]
        focus=ease(t,self.arr[act][-1]+.19,click[0]-.46)
        if focus<.999:self.document(c,t,act,focus)
        mode=('tray','slit')[act]
        events=list(zip(self.arr[act],range(3)))
        clicks=[(at,at+.23,at+.50,i) for i,at in enumerate(click)]
        # Match the same thumbnails across a continuous dolly to the edge.
        # Reserve room below for the unchanged editable draft throughout.
        if act:
            scale=mix(1.52,2.42 if v else 2.38,focus)
            py=mix(616,376,focus) if v else mix(166,141,focus)
        else:
            scale=mix(1.27,1.99 if v else 2.06,focus)
            py=mix(607,338,focus) if v else mix(160,101,focus)
        ps=round(scale*self.s,2)
        plate=self.prod[act].frame(mode,t,events,clicks,scale=ps)
        right=mix(w-38,w-(45 if v else 62),focus)
        px=right-284*ps/self.s
        push_start=(10.98 if v else 17.41) if act else (4.64 if v else 7.68)
        push=ease(t,push_start,push_start+(.60 if v else .77))
        if focus>.91 and (not act or push<.44):
            h1=self.words('轻点一张。','Click a screenshot.') if not act else self.words('点走一张。','Pick one.')
            h2=self.words('接着问。','Keep writing.') if not act else self.words('下一张跟上。','Next in line.')
            shift=(1-ease(focus,.60,1))*38
            x=40 if v else 47
            y=(250 if v else 218)+shift
            ink=INK if act else PAPER
            sage=TEAL if act else '#AFE6C4'
            c.text(x,y,h1,66 if v else 81,self.display,ink)
            if t>=click[0]+.16:
                advance=ease(t,click[0]+.16,click[0]+.51)
                c.text(x,y+(85 if v else 99)+13*(1-advance),h2,64 if v else 83,
                       'song' if self.zh else 'italic',sage)
        c.place(plate,px,py)
        field=self.draft(c,t,act,focus)
        for index,at in enumerate(click):
            if at+.055<=t<at+.23:
                # A match move, separate from the pointer, joins the exact selected
                # source bitmap and the corresponding tile of the existing draft.
                z=ease(t,at+.055,at+.23)
                pos=self.prod[act].target(mode,at,events,clicks,index,scale=ps)
                tx,ty=px+pos[0]/self.s,py+pos[1]/self.s
                tile=77 if v else 55
                dx=(38 if v else mix(358,47,focus))+20+index*(tile+12)+tile/2
                dy=(mix(975,978,focus) if v else mix(531,486,focus))+(44 if v else 35)+10+tile/2
                size=mix(92,tile,z)
                im=chip(KINDS[act][index],self.lang,max(1,c.xy(size)[0]))
                c.place(im,mix(tx,dx,z)-size/2,mix(ty,dy,z)-size/2-39*math.sin(z*math.pi))
        for index,at in enumerate(click):
            if at-.73<t<at+.74:
                target=self.prod[act].target(mode,min(t,at),events,clicks,index,scale=ps)
                if target is None:break
                tx,ty=px+target[0]/self.s,py+target[1]/self.s
                enter=ease(t,at-.73,at-.065); leave=ease(t,at+.18,at+.73)
                ix=mix(tx-146,tx,enter); iy=mix(ty+88,ty,enter)
                ix=mix(ix,field[0],leave);iy=mix(iy,field[1]+12,leave)
                cursor(c,ix,iy,(1.45 if not v else 1.55)*(1-.12*(ease(t,at-.02,at+.03)-ease(t,at+.07,at+.12))))
                break
        if push and act:
            if push>=.44:
                sub=self.words('原来的问题，接着写。','Keep writing in the same draft.')
                c.text(42 if v else 51,865 if v else 416,sub,32 if v else 34,self.display,INK)
            zoom=1+push*(.08 if v else .50)
            bw,bh=w/zoom,h/zoom
            left=min(w-bw,8*push if v else 20*push)
            top=(h-bh)*(.95 if v else .98)
            rect=(left*self.s,top*self.s,(left+bw)*self.s,(top+bh)*self.s)
            return c.im.resize(c.im.size,Image.Resampling.BICUBIC,box=rect)
        return c.im

    def intro(self,t):
        w,h=self.W,self.H
        c=Canvas((w,h),self.s,ground(w,h,self.s,0))
        c.brand(44,39,38,PAPER)
        # A travelling trim across the two case-study prints introduces their
        # palettes. The following live workspace begins genuinely empty.
        scale=1+ease(t,0,1.35)*.045
        width=round((700 if not self.v else 585)*scale)
        x=(667 if not self.v else 115)-12*ease(t,0,1)
        y=(94 if not self.v else 620)-8*ease(t,0,1)
        for kind,top,bottom,center in [('code',0,280,.58),('math',285,548,.61)]:
            height=bottom-top
            image=ImageOps.fit(shot(kind,self.lang),c.xy(width,height),
                               method=Image.Resampling.BICUBIC,centering=(.51,center))
            c.place(image,x,y+top)
        c.text(46,164,self.words('一只托盘。','A tray.'),104 if not self.v else 93,self.display,PAPER)
        c.text(43,296,self.words('一道微缝。','A micro slit.'),110 if not self.v else 99,
               'song' if self.zh else 'italic','#A3EACB')
        c.text(50,484,self.words('点选 Mac 截图，附加到 Chrome 中的 ChatGPT 草稿。',
                                 'Add Mac screenshots to ChatGPT in Chrome with one click.'),
               26,self.font,PAPER,width=575 if not self.v else 620)
        return c.im

    def end(self,t):
        w,h=self.W,self.H
        c=Canvas((w,h),self.s,ground(w,h,self.s,2))
        since=t-self.outro
        y=(440 if self.v else 185)+18*(1-ease(since,0,.57))
        sz=90
        namew=face('serif',round(110*self.s)).getlength('Riftlet')/self.s
        x=(w-(sz+22+namew))/2
        c.place(logo(c.xy(sz)[0]),x,y)
        c.text(x+sz+22,y-1,'Riftlet',110,'serif')
        verbs=('截屏、','点选、','继续。') if self.zh else ('Capture. ','Click. ','Continue.')
        f=face(self.display,c.xy(50)[0])
        x=(w-sum(f.getlength(v) for v in verbs)/self.s)/2
        for i,verb in enumerate(verbs):
            appear=ease(since,.17+i*.10,.41+i*.10)
            if appear:
                c.text(x,y+143+10*(1-appear),verb,50,self.display,TEAL)
            x+=f.getlength(verb)/self.s
        c.text(w/2,y+241,'riftlet.com',27,'medium',INK,anchor='mt')
        c.text(w/2,y+288,self.words('下载 Mac 版','Download for Mac'),17,self.font,'#597366',anchor='mt')
        return c.im

    def frame(self,t):
        cut=self.change
        first=.59 if self.v else 1.53
        if not self.v and t<first:
            if t<first-.41:return self.intro(t)
            return reveal(self.intro(t),self.workspace(t,0),ease(t,first-.41,first),self.s)
        if t<cut:return self.workspace(t,0)
        if t<cut+.34:
            return reveal(self.workspace(t,0),self.workspace(t,1),ease(t,cut,cut+.34),self.s)
        if t<self.outro:return self.workspace(t,1)
        if t<self.outro+.41:
            return reveal(self.workspace(t,1),self.end(t),ease(t,self.outro,self.outro+.41),self.s)
        return self.end(t)

def reveal(old,new,p,s):
    # A page edge crosses the fixed desktop. Each side keeps its own perspective.
    w,h=old.size
    k=round((w+h*.16)*(1-p)-h*.16)
    mask=Image.new('L',(w,h));d=ImageDraw.Draw(mask)
    d.polygon([(k,0),(w+1,0),(w+1,h),(k+round(h*.16),h)],fill=255)
    out=Image.composite(new,old,mask)
    if .015<p<.985:
        ImageDraw.Draw(out).line([(k,0),(k+round(h*.16),h)],fill='#A2D7BC',width=round(3*s))
    return out


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('cut',choices=('master','vertical'))
    parser.add_argument('lang',choices=('zh-CN','en'))
    parser.add_argument('--audio',type=Path,required=True)
    parser.add_argument('--scale',type=float,default=1.5)
    parser.add_argument('--out',type=Path)
    args=parser.parse_args()
    film=Film(args.lang,args.cut=='vertical',args.scale)
    out=args.out or ROOT/'films'/args.lang/f'{args.cut}.mp4'
    out.parent.mkdir(parents=True,exist_ok=True)
    tmp=out.with_suffix('.partial.mp4')
    w,h=round(film.W*args.scale),round(film.H*args.scale)
    ff=imageio_ffmpeg.get_ffmpeg_exe()
    cmd=[ff,'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24',
         '-s',f'{w}x{h}','-r',str(FPS),'-i','pipe:0','-i',str(args.audio/f'{args.cut}.wav'),
         '-vf','scale=out_color_matrix=bt709:out_range=tv','-c:v','libx264','-preset','fast',
         '-threads','3','-crf','16','-pix_fmt','yuv420p','-color_primaries','bt709',
         '-colorspace','bt709','-color_trc','bt709','-c:a','aac','-aac_coder','fast','-b:a','320k',
         '-t',str(film.duration),'-movflags','+faststart',str(tmp)]
    proc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
    try:
        for frame in range(film.duration*FPS):
            proc.stdin.write(film.frame(frame/FPS).tobytes())
        proc.stdin.close()
        if proc.wait():raise RuntimeError('H.264 encoder failed')
        os.replace(tmp,out)
    finally:
        if proc.poll() is None:proc.kill();proc.wait()
    print(out,flush=True)

if __name__=='__main__':main()
