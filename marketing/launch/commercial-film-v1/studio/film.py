"""Picture edit. Times are elapsed seconds on the 30 fps master reel."""
import argparse
import io
import math
from pathlib import Path
import subprocess
import tempfile
import sys

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageOps
from sets import Set, ROOT, ART, IVORY, INK, MINT, txt, font, mark, ease, mix, s, smoothpoints, viewport

CAPTIONS = [
 (0.00,2.83,'思路不断。Mac 截图，一点就到 ChatGPT 草稿。'),
 (2.83,5.50,'用 Mac 截下想问的画面。'),
 (5.50,7.20,'截图就在 Riftlet 托盘。'),
 (7.20,8.55,'再截一张蓝色内道。'),
 (8.55,10.98,'两张截图，都在手边。'),
 (10.98,13.45,'点选骑手这张。'),
 (13.45,17.65,'图片已附加到 Chrome 中的 ChatGPT 草稿。'),
 (17.65,21.27,'“这张照片里，什么最引人注目？看看这个倾角。”'),
 (21.27,24.85,'不用找文件，也不用拖放。'),
 (24.85,30.00,'截屏、点选、继续。'),
]

def subtitle(im,string,portrait=False):
    w,h=im.size
    sz=round(w*(.035 if portrait else .0156))
    f=font('zh',sz); a=f.getlength(string)
    cx=w/2; y=round(h*(.92 if portrait else .934))
    band=Image.new('RGBA',im.size)
    dr=ImageDraw.Draw(band)
    dr.rounded_rectangle((cx-a/2-sz*.59,y-sz*.23,cx+a/2+sz*.59,y+sz*1.09),radius=sz*.22,fill=(11,24,23,204))
    dr.text((cx,y),string,anchor='mt',font=f,fill=(255,255,252))
    im.paste(band,(0,0),band)

def on_disk(im, over, x,y): im.paste(over,(round(x),round(y)),over)

def split_color(im,tone,amount):
    return Image.blend(im,Image.new('RGB',im.size,tone),amount)

def lower_shade(im,strength=.82):
    w,h=im.size
    col=np.arange(h,dtype=np.float32)/h
    a=(np.clip((col-.44)/.56,0,1)**.9*255*strength).astype('uint8')
    mask=Image.fromarray(a[:,None]).resize((w,h))
    im.paste(Image.new('RGB',im.size,'#071311'),(0,0),mask)

def brandbug(im,x,y,size,white=False):
    tile=mark(round(size))
    on_disk(im,tile,x,y)
    txt(im,(x+size*1.27,y+size*.00),'Riftlet',size*.99,'serif','#FFFFFF' if white else INK,'lt')

def locator(im,x,y,label,color=INK):
    txt(im,(x,y),label,19,'medium',color,'lt')

def crop_shot(st,t,dims,second=False):
    w,h=dims
    # The viewfinder corners frame every pixel later seen in the chosen tile.
    # Top and bottom accent margins are part of the photograph's paper mount.
    pic=st.b if second else st.a
    paper='#DFE7E7' if second else '#F6F2E9'
    im=Image.new('RGB',dims,paper)
    start,end=(7.20,8.10) if second else (2.83,5.10)
    u=s(t,start,end); drift=s(t,start,end+.35)
    d=ImageDraw.Draw(im)
    cx=round(w*(.61 if second else .637)); cy=round(h*.492)
    fh=round(h*mix(.83,.82,drift)); fw=round(fh*1.5)
    pos=(cx-fw//2,cy-fh//2)
    # Macro rack-out on the source paper, finishing on the entire photograph.
    # The PNG used by the tray and draft is the complete selected rectangle.
    if second: pos=(round(w*.25),pos[1])
    q=pic.resize((fw,fh),Image.Resampling.LANCZOS)
    im.paste(q,pos)
    x,y=pos; ox=x+fw; oy=y+fh
    # Crop marks belong to the magazine proof, outside the screenshot rectangle.
    for ex,dx in ((x,-1),(ox,1)):
        for ey,dy in ((y,-1),(oy,1)):
            d.line((ex+6*dx,ey,ex+23*dx,ey),fill='#7D8077',width=2)
            d.line((ex,ey+6*dy,ex,ey+23*dy),fill='#7D8077',width=2)
    if second:
        txt(im,(w*.048,h*.16),'02',w*.098,'serif',INK,'lt')
        txt(im,(w*.051,h*.38),'The inner line',w*.026,'italic',INK,'lt')
    else:
        brandbug(im,w*.05,h*.077,h*.043)
        txt(im,(w*.05,h*.356),'Capture.',w*.074,'serif',INK,'lt')
        txt(im,(w*.053,h*.56),'Mac screenshot',w*.018,'medium',INK,'lt')
        txt(im,(w*.053,h*.617),'Shift + Command + 4',w*.0145,'sans','#426459','lt')
    # Native region selection grows from a mouse-down corner to the release corner.
    if t <= end+1/30:
        a=s(t,start+.12,end-.14)
        xx=x+max(2,fw*a); yy=y+max(2,fh*a)
        ov=Image.new('RGBA',im.size)
        od=ImageDraw.Draw(ov)
        od.rectangle((x,y,ox,oy),fill=(11,17,20,66))
        od.rectangle((x,y,xx,yy),fill=(0,0,0,0),outline=(253,254,249,235),width=2)
        for off in (-1,1):
            od.line((xx+4*off,yy,xx+16*off,yy),fill='white',width=2)
            od.line((xx,yy+4*off,xx,yy+16*off),fill='white',width=2)
        im.paste(ov,(0,0),ov)
    if end<=t<end+.13:
        im=split_color(im,'#FFFFFA',.45*(1-(t-end)/.13)**2)
    return im

def plate_shot(st,t,dims):
    """Product macro, with natural sampled desktop behind the true 1:8-width tray."""
    w,h=dims
    if t<7.20:
        a=s(t,5.5,6.5)
        cx,cy,wide=mix(1334,1337,a),mix(505,512,a),mix(408,422,a)
        head='At hand.';label='Riftlet screenshot tray'
    else:
        a=s(t,8.54,10.2);cx,cy,wide=mix(1344,1335,a),mix(491,481,a),mix(430,457,a)
        head='Both here.';label='Riftlet screenshot tray'
    # Macro photograph to right, actual plate on an extended copy of the
    # same wallpaper. Left copy remains clear of every product pixel.
    plate=st.tray.render(t)
    im=Image.new('RGB',dims,'#DCE4D7')
    # The editorial camera photographs the actual wallpaper away from the
    # Chrome edge; the product remains an independently composited plane.
    tex=viewport(st.empty,2*cx,2*cy,wide*2,dims)
    tex=split_color(tex,'#D4DFCC',.12)
    im.paste(tex)
    scale=w/wide*(180/246)
    pw,ph=round(330*scale),round(296*scale)
    p=plate.resize((pw,ph),Image.Resampling.LANCZOS)
    # Film camera trucks around the product, racking to a flat readable face.
    # Perspective affects the editorial plate as a whole, never its slot positions.
    import cv2
    a=s(t,5.50,7.20) if t<7.2 else s(t,8.5,10.98)
    tilt=mix(.12,-.012,a) if t<7.2 else mix(-.07,.005,a)
    source=np.float32([(0,0),(pw-1,0),(pw-1,ph-1),(0,ph-1)])
    dest=source+np.float32([(0,ph*tilt*.35),(-pw*abs(tilt)*.31,-ph*tilt*.24),(-pw*abs(tilt)*.31,ph*tilt*.24),(0,-ph*tilt*.35)])
    mat=cv2.getPerspectiveTransform(source,dest)
    # Premultiply for clean, antialiased edges.
    p=Image.frombytes('RGBa',(pw,ph),cv2.warpPerspective(np.asarray(p.convert('RGBa')),mat,(pw,ph),flags=cv2.INTER_LINEAR).tobytes()).convert('RGBA')
    glass_scale=246*scale
    left=w*.68-glass_scale/2-42*scale
    top=h*.57-(180 if t<7.20 else 150)*scale
    on_disk(im,p,left,top)
    txt(im,(w*.057,h*.36),head,w*.086,'serif','#FBFBF1','lt')
    txt(im,(w*.062,h*.59),label,w*.0175,'medium','#F2F4E7','lt')
    return im

def signature(im,t):
    w,h=im.size
    # First line on one solid brand surface; the ad's three-beat movement
    # resolves into one still lockup, ink and mint on warm paper.
    im.paste(IVORY,(0,0,w,h))
    k=s(t,24.75,25.45)
    z=round(h*(.123+.012*(1-k)))
    word=font('serif',round(h*.19)); wd=word.getlength('Riftlet')
    total=z+w*.025+wd; left=(w-total)/2
    y=h*.397+(1-k)*35
    on_disk(im,mark(z),left,y)
    txt(im,(left+z+w*.025,y+z*.54),'Riftlet',h*.19,'serif',INK,'lm')
    verbs=('Capture.','Click.','Continue.')
    f=font('sans',round(h*.045)); widths=[f.getlength(a) for a in verbs]
    gap=w*.009;x=(w-sum(widths)-gap*2)/2
    for i,(word,wd) in enumerate(zip(verbs,widths)):
        p=s(t,25.47+i*.35,25.97+i*.35)
        c=tuple(round(mix(v,b,p)) for v,b in zip((252,251,248),(29,55,48)))
        txt(im,(x,h*.618+(1-p)*19),word,h*.045,'sans',c,'lt')
        x+=wd+gap
    a=s(t,26.6,27.06)
    col=tuple(round(mix(v,b,a)) for v,b in zip((252,251,248),(37,89,75)))
    txt(im,(w/2,h*.758),'riftlet.com',h*.041,'medium',col,'mt')
    txt(im,(w/2,h*.818),'Download for macOS  ·  Public Beta',h*.020,'sans',col,'mt')
    return im

def master(st,t,sub=True):
    dims=(1920,1080);w,h=dims
    if t<2.83:
        # Pull the spectator from a close screen onto the photographer's desk.
        k=s(t,0,2.8)
        im=st.physical(t,dims,(mix(848,836,k),mix(453,469,k)),mix(1270,1630,k))
        lower_shade(im)
        brandbug(im,w*.055,h*.648,44,True)
        txt(im,(w*.053,h*.725),'Keep the thought.',h*.12,'serif',IVORY,'lt')
        txt(im,(w*.565,h*.785),'Mac screenshots to ChatGPT in Chrome.',h*.035,'medium',IVORY,'lt')
    elif t<5.50: im=crop_shot(st,t,dims)
    elif t<7.20: im=plate_shot(st,t,dims)
    elif t<8.50: im=crop_shot(st,t,dims,True)
    elif t<10.98: im=plate_shot(st,t,dims)
    elif 10.98<=t<11.94:
        # A one-second tactile insert anticipates the single onscreen press.
        # A local displacement of the fingertip brings the pad toward its shadow.
        import cv2
        pic=np.asarray(st.finger)
        yy,xx=np.mgrid[:pic.shape[0],:pic.shape[1]].astype('float32')
        q=s(t,10.98,11.94)
        weight=np.exp(-((xx-909)/345)**2-((yy-469)/175)**2)
        pp=cv2.remap(pic,xx,yy-14*q*weight,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
        im=viewport(Image.fromarray(pp),mix(843,845,q),mix(475,483,q),mix(1540,1480,q),dims)
        txt(im,(w*.055,h*.555),'One click.',h*.128,'serif',IVORY,'lt')
    elif t<16.35:
        # Single uninterrupted view contains target, pointer, tile and draft.
        cx,cy,wide=smoothpoints(t,[(10.98,(1017,469,976)),(12.40,(1022,478,873)),(14.07,(1022,478,873)),(16.35,(975,476,856))])
        im=st.world_view(t,cx,cy,wide,dims)
    elif t<21.27:
        v=s(t,16.35,17.75)
        im=st.world_view(t,mix(911,912,v),mix(500,505,v),mix(685,675,v),dims)
    elif t<24.85:
        p=s(t,21.27,24.85)
        im=st.physical(t,dims,(mix(829,836,p),mix(410,466,p)),mix(1230,1648,p))
        lower_shade(im)
        txt(im,(w*.05,h*.725),'No file hunt. No dragging.',h*.107,'serif',IVORY,'lt')
    else: im=signature(Image.new('RGB',dims),t)
    if sub:
        for a,b,label in CAPTIONS:
            if a<=t<b: subtitle(im,label);break
    return im

def encode(render,st,frames,dims,wav,out):
    # Convert display-referred sRGB artwork to limited-range BT.709 YUV.
    cmd=[imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-loglevel','error','-y','-f','rawvideo',
         '-pixel_format','rgb24','-video_size',f'{dims[0]}x{dims[1]}','-framerate','30','-i','-',
         '-i',str(wav),'-map','0:v:0','-map','1:a:0','-vf','scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,setparams=range=limited:color_primaries=bt709:color_trc=iec61966-2-1:colorspace=bt709',
         '-c:v','libx264','-preset','fast','-crf','17','-profile:v','high','-threads','4','-g','60','-color_primaries','bt709',
         '-color_trc','iec61966-2-1','-colorspace','bt709','-color_range','tv','-c:a','aac','-b:a','256k',
         '-ar','48000','-ac','2','-bsf:v','h264_metadata=colour_primaries=1:transfer_characteristics=13:matrix_coefficients=1','-movflags','+faststart+write_colr',str(out)]
    with subprocess.Popen(cmd,stdin=subprocess.PIPE) as proc:
        try:
            for i in range(frames):
                proc.stdin.write(render(st,i/30).convert('RGB').tobytes())
                if i%120==0: print(f'{i}/{frames}',flush=True)
        finally: proc.stdin.close()
        if proc.wait(): raise RuntimeError('FFmpeg failed')
    return out

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['master','frame']);p.add_argument('--time',type=float,default=0);p.add_argument('--out',type=Path)
    args=p.parse_args();st=Set()
    if args.action=='frame': master(st,args.time).save(args.out)
    else: encode(master,st,900,(1920,1080),ART/'score-master.wav',args.out or ROOT/'films/riftlet-commercial.mp4')
if __name__=='__main__': main()
