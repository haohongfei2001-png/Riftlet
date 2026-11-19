"""Edit the 1.0.3 desktop take and a visibly labelled attachment illustration.

macOS · Pillow, PyAV, NumPy, imageio-ffmpeg · python native-demo/edit/at_hand_zh.py
"""
from __future__ import annotations

import argparse
from functools import lru_cache
from pathlib import Path
import subprocess
import tempfile
import wave

import av
import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
W, H, FPS, SECONDS = 1920, 1080, 60, 23
PAPER=(252,251,248)
INK='#122d29'; SUB='#405b54'; JADE='#157968'; WHITE='#fffcf0'
TITLE='/System/Library/Fonts/Supplemental/Songti.ttc'
BODY='/System/Library/Fonts/Hiragino Sans GB.ttc'
SERIF='/System/Library/Fonts/HelveticaNeue.ttc'
RESAMPLE=Image.Resampling.LANCZOS


def clamp(x):
    return min(1.,max(0.,x))


def ease(x):
    x=clamp(x)
    return x*x*(3.-2.*x)


def phase(t,start,end):
    return ease((t-start)/(end-start))


def mix(a,b,f):
    return a+(b-a)*f


@lru_cache(maxsize=32)
def font(size,kind='body'):
    return ImageFont.truetype({'title':TITLE,'body':BODY,'latin':SERIF}[kind],size,index=1 if kind=='title' else 0)


def write(draw,xy,txt,size,kind='body',color=INK,anchor='lm'):
    draw.text(xy,txt,font=font(size,kind),fill=color,anchor=anchor)


def fill_crop(im,box,size):
    return im.resize(size,Image.Resampling.BICUBIC,box=tuple(map(float,box)))


def blend_on(page,im,xy,alpha=1.):
    if alpha>=1: page.paste(im,xy,im)
    elif alpha>0: page.paste(im,xy,im.getchannel('A').point(lambda a:round(a*alpha)))


def draw_tag(page,text,dark=False):
    d=ImageDraw.Draw(page)
    write(d,(W-89,75),text,28,'body',WHITE if dark else SUB,'rm')


class Editor:
    def __init__(self,source):
        self.take=source
        self.originals={}
        for name in ('low','high'):
            self.originals[name]=Image.open(source/f'meridian-{name}-pixels.png').convert('RGB')
        self.icon=Image.open(source/'riftlet-app-icon.png').convert('RGBA').resize((63,63),RESAMPLE)
        self.macros={key:im.crop((0,63,1200,660)) for key,im in self.originals.items()}
        # This is just a paper backing. Every control and thumbnail on it comes from the native take.
        self.base=Image.new('RGB',(W,H),PAPER)
        self.inkglass=self._glass()
        self.card=self._draft()
        self.draft_shadow=Image.new('RGBA',(1240,630));shadow=Image.new('L',self.draft_shadow.size)
        ImageDraw.Draw(shadow).rounded_rectangle((35,54,1206,577),radius=55,fill=37)
        self.draft_shadow.putalpha(shadow.filter(ImageFilter.GaussianBlur(26)))
        self.with_attachment=self._attachment(self.originals['low'])
        self._raw=[]
        with av.open(str(source/'tray-native-lossless.mp4')) as video:
            for frame in video.decode(video=0):
                self._raw.append(frame.to_image().convert('RGB').crop((205,92,651,501)))
        if len(self._raw)!=720: raise ValueError('Wrong number of native frames')

    def _glass(self):
        # An editorial tint along the bottom preserves contrast across the changing topography.
        shades=np.zeros((H,1,4),dtype=np.uint8);shades[:,:,:3]=(12,37,34)
        y=np.linspace(0,1,H); shades[:,0,3]=np.clip(42+144*y**1.7+66*np.exp(-y*8),0,255).astype(np.uint8)
        return Image.fromarray(shades).resize((W,H))

    def _draft(self):
        card=Image.new('RGBA',(1160,536));d=ImageDraw.Draw(card)
        d.rounded_rectangle((2,2,1157,533),radius=50,fill='#fffefa',outline='#d0dbd4',width=2)
        write(d,(59,73),'ChatGPT',33,'latin',SUB);write(d,(224,73),'当前草稿',30,'body',SUB)
        write(d,(1099,73),'附加示意',36,'body',JADE,'rm')
        d.line((58,122,1095,122),fill='#dce3db',width=2)
        write(d,(59,332),'为什么低潮时，这块浅滩会露出来？',47,'body',INK)
        d.ellipse((66,431,108,473),outline='#68807a',width=2)
        d.line((78,452,96,452),fill=SUB,width=2);d.line((87,443,87,461),fill=SUB,width=2)
        d.ellipse((1049,417,1121,489),fill='#193e37');d.line((1085,467,1085,440),fill=WHITE,width=4)
        d.line((1074,451,1085,440,1096,451),fill=WHITE,width=4)
        return card

    def _attachment(self,im):
        img=im.resize((194,139),RESAMPLE).convert('RGBA'); border=Image.new('L',img.size);ImageDraw.Draw(border).rounded_rectangle((0,0,193,138),radius=15,fill=255);img.putalpha(border);return img

    def opening(self,t):
        u=phase(t,0,2.68)
        cx=mix(635,658,u);cy=mix(270,280,u);wide=mix(929,870,u);high=wide*H/W
        page=fill_crop(self.macros['low'],(cx-wide/2,cy-high/2,cx+wide/2,cy+high/2),(W,H));page.paste(self.inkglass,(0,0),self.inkglass)
        d=ImageDraw.Draw(page)
        write(d,(97,71),'Riftlet',44,'latin',WHITE);write(d,(W-90,72),'桌面演示',28,'body',WHITE,'rm')
        write(d,(99,665),'正在写的问题',33,'body','#b0ead4')
        write(d,(91,820),'为什么低潮时，',108,'title',WHITE)
        write(d,(91,947),'这块浅滩会露出来？',108,'title',WHITE)
        return page

    def native(self,t):
        # Cut from 10.45 s to 16.45 s at an identical resting tray. Discard the camera menu.
        time_on_take=t-1.55 if t<12.0 else 16.45+(t-12.0)
        n=max(0,min(len(self._raw)-1,int(np.floor(time_on_take*30+1e-7))))
        page=self.base.copy(); d=ImageDraw.Draw(page)
        blend_on(page,self.icon,(84,43));write(d,(159,74),'Riftlet',42,'latin');draw_tag(page,'原生托盘实录   /   1.0.3（25）')
        # Captured plates and tray remain legible at 480p; editorial moves stay outside the product UI.
        side_switch=phase(t,7.72,8.30); zoom=phase(t,2.46,11.70); shift=phase(t,10.9,13.2)
        sw=1104; sh=644
        for key,amount in [('low',1.),('high',side_switch)]:
            if amount<=0:continue
            im=self.macros[key]; h=mix(583,535,zoom);w=h*sw/sh
            cx=mix(581,604,zoom);cy=mix(297,295,zoom)
            plate=fill_crop(im,(cx-w/2,cy-h/2,cx+w/2,cy+h/2),(sw,sh))
            if key=='low': page.paste(plate,(0,168))
            else: page.paste(plate,(0,168),Image.new('L',plate.size,round(255*amount)))
        d=ImageDraw.Draw(page);write(d,(89,874),'低潮' if side_switch<.45 else '高潮',42,'title');write(d,(211,874),'Meridian Inlet',28,'latin',SUB)
        # Optical pull-in toward the true tray just before the recorded thumbnail press.
        nw=round(mix(650,760,shift));nh=round(nw*self._raw[n].height/self._raw[n].width)
        x=round(mix(1163,1100,shift)); y=round(mix(214,156,shift))
        page.paste(self._raw[n].resize((nw,nh),RESAMPLE),(x,y))
        d=ImageDraw.Draw(page);d.line((91,936,1822,936),fill='#cfdbd1',width=2)
        caption='截下眼前这处浅滩。' if t<3.89 else ('第一张图，已经在托盘。' if t<7.84 else ('再留一张高潮时的对照。' if t<10.28 else '用哪张，就点哪张。'))
        write(d,(91,997),caption,52,'title')
        if 13.77 < t < 14.78:
            # A thin editorial reticle locates the actual first-thumbnail mouse event in the take.
            mx=round(x+139*nw/446);my=round(y+118*nh/409)
            approach=phase(t,13.77,14.25); xx=mx+(1-approach)*50; yy=my+(1-approach)*65
            scale=.93-.12*np.sin(np.pi*phase(t,14.25,14.56))
            points=[(0,0),(1,39),(11,29),(18,42),(24,39),(18,26),(31,26)]
            pts=[(round(xx+px*scale),round(yy+py*scale)) for px,py in points]
            # Visible editorial pointer over the real, time-stamped first input action.
            d.polygon(pts,fill=INK);d.line(pts+[pts[0]],fill='white',width=2)
            if t>14.25:
                strength=np.sin(np.pi*clamp((t-14.25)/.53));radius=round(13+17*phase(t,14.25,14.78))
                outline=tuple(round(mix(a,b,strength*.86)) for a,b in zip((234,239,229),(21,121,104)))
                d.ellipse((mx-radius,my-radius,mx+radius,my+radius),outline=outline,width=3)
        return page

    def concept(self,t):
        page=Image.new('RGB',(W,H),'#eaf2ed'); d=ImageDraw.Draw(page)
        blend_on(page,self.icon,(84,43));write(d,(159,74),'Riftlet',42,'latin');draw_tag(page,'Chrome 中的 ChatGPT 草稿   /   操作示意')
        progress=phase(t,14.78,17.45);arrived=phase(t,17.43,17.80);drift=phase(t,17.45,22.98)
        # The miniature is made from the same exact low-tide window screenshot used in the real tray.
        cx=round(mix(654,624,drift));cy=round(mix(264,256,drift))
        blend_on(page,self.draft_shadow,(cx-32,cy-33))
        blend_on(page,self.card,(cx,cy));d=ImageDraw.Draw(page)
        write(d,(91,320),'接着写。',65,'title');write(d,(95,418),'低潮图，放进同一个草稿。',37,'body',SUB)
        start=(1278,322);end=(cx+60,cy+153);fx=mix(start[0],end[0],progress);fy=mix(start[1],end[1],progress)-66*np.sin(np.pi*progress)
        size=mix(1.44,1.,progress);img=self.with_attachment.resize((round(194*size),round(139*size)),RESAMPLE)
        blend_on(page,img,(round(fx),round(fy)))
        if 0<arrived<1:
            d=ImageDraw.Draw(page);k=round(5*arrived);d.rounded_rectangle((end[0]-k-2,end[1]-k-2,end[0]+194+k,end[1]+139+k),radius=19,outline='#72aa94',width=max(1,round(3*(1-arrived))))
        # End on the actual question illustrated above; no send or completed-response action.
        d=ImageDraw.Draw(page);d.line((91,936,1822,936),fill='#bfcec3',width=2)
        write(d,(91,997),'截图进草稿，问题接着写。' if t<20.08 else '什么时候发送，由你决定。',52,'title')
        return page

    def render(self,n):
        t=n/FPS
        if t<2.44:return self.opening(t)
        if t<2.77:return Image.blend(self.opening(t),self.native(t),phase(t,2.44,2.77))
        if t<14.78:return self.native(t)
        if t<15.12:return Image.blend(self.native(t),self.concept(t),phase(t,14.78,15.12))
        return self.concept(t)


def score(path):
    sr=48000;t=np.arange(SECONDS*sr)/sr; music=np.zeros((t.size,2));rng=np.random.default_rng(464)
    # Hand-written quiet plucks. The capture and attachment marks correspond to cuts, not system audio.
    notes=[(.10,55,1.8,.13),(1.12,62,1.65,.08),(2.50,67,2.5,.08),(3.89,74,.6,.10),(5.22,67,2.1,.07),(7.50,62,1.45,.08),(8.88,76,.67,.10),(10.3,71,1.9,.08),(12.43,67,1.8,.07),(14.35,74,.8,.10),(15.76,69,1.4,.08),(17.45,67,2.4,.12),(17.55,71,2.8,.07),(19.02,62,2.5,.07),(20.3,55,2.6,.13)]
    for idx,(when,midi,tail,gain) in enumerate(notes):
        start=round(when*sr);u=np.arange(min(round(tail*sr),t.size-start))/sr;freq=440*2**((midi-69)/12)
        env=(1-np.exp(-u/.018))*np.exp(-4*u/tail)*(1-np.exp(-np.maximum(tail-u,0)/.06));signal=(np.sin(2*np.pi*freq*u)+.24*np.sin(4.003*np.pi*freq*u)+.08*np.sin(6.007*np.pi*freq*u))*env*gain
        pan=.38+.24*(idx%3)/2;music[start:start+len(u),:]+=signal[:,None]*[1-pan,pan]
    for when in (3.89,8.88,14.35,17.45):
        start=round(when*sr);u=np.arange(round(.08*sr))/sr;tick=rng.standard_normal(len(u))*.011*np.exp(-u*120)*(1-np.exp(-u*800));music[start:start+len(u)]+=tick[:,None]
    with wave.open(str(path),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(sr);w.writeframes(np.int16(np.clip(music*1.9,-1,1)*32767).tobytes())


def main():
    arg=argparse.ArgumentParser();arg.add_argument('--source',type=Path,default=ROOT/'native-demo/source-1.0.3');arg.add_argument('--output',type=Path,default=ROOT/'films/at-hand.demo.zh-CN.mp4');arg.add_argument('--preview',type=Path);opts=arg.parse_args();e=Editor(opts.source)
    if opts.preview:
        opts.preview.mkdir(parents=True,exist_ok=True)
        for t in (.05,2.9,4.2,8.2,9.3,13.3,14.69,15.32,16.4,17.8,21.8):e.render(round(t*FPS)).save(opts.preview/f'{t:.2f}.jpg',quality=88)
        return
    opts.output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        audio=Path(tmp)/'score.wav';score(audio)
        cmd=[imageio_ffmpeg.get_ffmpeg_exe(),'-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-i',str(audio),'-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p','-c:v','libx264','-crf','16','-preset','fast','-threads','4','-colorspace','bt709','-color_trc','bt709','-color_primaries','bt709','-color_range','tv','-c:a','aac','-b:a','192k','-movflags','+faststart',str(opts.output)]
        p=subprocess.Popen(cmd,stdin=subprocess.PIPE)
        for n in range(FPS*SECONDS):p.stdin.write(e.render(n).tobytes())
        p.stdin.close()
        if p.wait():raise RuntimeError('Encoding failed')


if __name__=='__main__':
    main()
