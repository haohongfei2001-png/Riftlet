"""Inspect launch exports; use together with the macOS Player.swift verifier."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
from statistics import median
import json
import math

import av
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps


def sheet(panels, dest, columns=4, size=(320, 200)):
    if not panels:
        return
    width, height = size
    font = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 13)
    stride_x, stride_y = width + 18, height + 37
    page = Image.new('RGB', (columns * stride_x + 18, math.ceil(len(panels)/columns)*stride_y+18), '#f4f1ea')
    draw = ImageDraw.Draw(page)
    for i, (label, pic) in enumerate(panels):
        rgb = ImageOps.contain(pic.convert('RGB'), size, Image.Resampling.LANCZOS)
        x, y = 18 + i % columns * stride_x, 18 + i // columns * stride_y
        page.paste(rgb, (x + (width-rgb.width)//2, y+(height-rgb.height)//2))
        draw.text((x,y+height+4), label, fill='#162821', font=font)
    page.save(dest, quality=91)


def movie(path, out):
    with av.open(str(path)) as container:
        v=container.streams.video[0]
        info=dict(dimensions=[v.width,v.height],codec=v.codec_context.name,fps=float(v.average_rate),audioTracks=len(container.streams.audio))
        stamps=[float(frame.pts * frame.time_base) for frame in container.decode(video=0)]
    gaps=np.diff(stamps)
    assert len(gaps)>0 and np.all(gaps>0), path
    duration=stamps[-1]+median(gaps)-stamps[0]
    info.update(frames=len(stamps),videoDuration=round(duration,4),firstPTS=stamps[0],maxPTSDelta=round(float(gaps.max()),5))
    if info['audioTracks']:
        with av.open(str(path)) as container:
            stream=container.streams.audio[0]
            peaks, energies, first, end, nsamples=[],0.0,None,None,0
            for frame in container.decode(audio=0):
                raw=frame.to_ndarray()
                samples=raw.astype(np.float64)
                if raw.dtype.kind in 'iu': samples /= max(abs(np.iinfo(raw.dtype).min),np.iinfo(raw.dtype).max)
                pts=float(frame.pts * frame.time_base)
                if first is None: first=pts
                end=pts+frame.samples/frame.sample_rate
                peaks.append(float(np.max(np.abs(samples))))
                energies+=np.sum(samples**2); nsamples+=samples.size
            assert peaks and nsamples and end is not None, path
            info['audio']=dict(codec=stream.codec_context.name,rate=stream.rate,channels=stream.codec_context.channels,
                               firstPTS=first,endPTS=round(end,5),peak=round(max(peaks),6),
                               rms=round(float(np.sqrt(energies/nsamples)),6),framesWithSignal=sum(x>.002 for x in peaks),
                               digitalPeakDbFS=round(20*math.log10(max(max(peaks),1e-9)),2))
    return info


def animation(path, out):
    hashes, delays, panels = [], [], []
    with Image.open(path) as im:
        n=im.n_frames; size=im.size; loop=im.info.get('loop'); first=None
        for i in range(n):
            im.seek(i); rgb=im.convert('RGB'); hashes.append(sha256(rgb.tobytes()).hexdigest()); delays.append(im.info['duration'])
            if i==0: first=rgb.copy()
            if i in (0,n//4,n//2,3*n//4,n-1): panels.append((f'frame {i:03}',rgb.copy()))
        close=np.abs(np.array(first.resize((160,90)),dtype=int)-np.array(rgb.resize((160,90)),dtype=int)).mean()
    with Image.open(path) as im:
        for i,(h,d) in enumerate(zip(hashes,delays)):
            im.seek(i); assert sha256(im.convert('RGB').tobytes()).hexdigest()==h and im.info['duration']==d
    assert loop==0 and n>1 and len(set(hashes))>1 and min(delays)>0
    sheet(panels,out/(path.stem+'-loop.jpg'),columns=len(panels),size=(225,170))
    return dict(dimensions=list(size),frames=n,distinctFrames=len(set(hashes)),cycleSeconds=sum(delays)/1000,
                minDelayMs=min(delays),maxDelayMs=max(delays),loop=loop,repeatPixelMatch=True,
                meanPixelDifferenceAtSeam=round(float(close),3))


def inspect(kit,out):
    out.mkdir(parents=True,exist_ok=True); records={}; static=[]
    for path in sorted(kit.rglob('*')):
        rel=path.relative_to(kit)
        if rel.parts[0] not in ['films','stills','covers','platforms','loops','gifs','images','gif']:continue
        ext=path.suffix.lower()
        if ext not in ['.mp4','.mov','.png','.webp','.jpg','.jpeg','.gif']:continue
        if ext in ['.mp4','.mov']: info=movie(path,out)
        elif ext=='.gif': info=animation(path,out)
        else:
            with Image.open(path) as im:
                im.load(); rgb=im.convert('RGB'); assert sum(b-a for a,b in rgb.getextrema())>0
                info=dict(dimensions=list(im.size),format=im.format,fullDecode=True)
                display=ImageOps.contain(rgb,(640,400),Image.Resampling.LANCZOS)
                static.append((path.stem,display))
        records[rel.as_posix()]={'sha256':sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,**info}
    for page in range(math.ceil(len(static)/6)):
        sheet(static[page*6:page*6+6],out/f'graphics-{page+1}.jpg',columns=2,size=(530,335))
    (out/'technical.json').write_text(json.dumps(records,indent=2,ensure_ascii=False)+'\n')


if __name__=='__main__':
    cli=ArgumentParser(description=__doc__);cli.add_argument('kit',type=Path);cli.add_argument('out',type=Path)
    args=cli.parse_args();inspect(args.kit,args.out)
