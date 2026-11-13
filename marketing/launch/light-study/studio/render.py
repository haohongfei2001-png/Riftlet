"""Render, mix and package individually art-directed campaign cuts and stills."""
import argparse
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

import imageio_ffmpeg
from PIL import Image, ImageOps

from art import ROOT, RES, master
from editions import short, print_panels
from score import write_score
from platforms import PROFILE

FFMPEG=imageio_ffmpeg.get_ffmpeg_exe()
CUTS={
    "brand": ("brand-film",37,1920,1080,1.2),
    "capture": ("short-capture",8,1080,1920,1.2),
    "at-hand": ("short-at-hand",8,1080,1080,1.08),
    "draft": ("short-draft",8.5,1080,1350,1.2),
}


def film(key):
    stem,duration,w,h,scale=CUTS[key]
    with TemporaryDirectory(prefix="riftlet-score-") as scratch:
        wav=Path(scratch)/"mix.wav"
        write_score(wav,duration,key)
        dest=ROOT/"films"/(stem+".mp4")
        args=[FFMPEG,"-y","-hide_banner","-loglevel","error","-f","rawvideo","-pixel_format","rgb24",
              "-video_size",f"{w}x{h}","-framerate","24","-i","pipe:0","-i",str(wav),
              "-map","0:v","-map","1:a","-vf","scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p",
              "-c:v","libx264","-crf","16","-preset","fast","-threads","4","-c:a","aac","-b:a","192k",
              "-colorspace","bt709","-color_trc","bt709","-color_primaries","bt709","-color_range","tv",
              "-movflags","+faststart","-metadata","title=Riftlet — "+stem,str(dest)]
        with subprocess.Popen(args,stdin=subprocess.PIPE) as proc:
            for frame in range(round(duration*24)):
                t=frame/24
                img=master(t,scale) if key=="brand" else short(key,t,scale)
                assert img.size==(w,h)
                proc.stdin.write(img.tobytes())
            proc.stdin.close()
            if proc.wait(): raise RuntimeError(stem+" encode failed")


def loops():
    # A designed tail-to-head dissolve resets each study without a jump.
    shots=[("01-select",4.83,7.5),("02-arrive",9,12.4),("03-pair",14,17.45),("04-attach",22.5,25.6)]
    for name,start,end in shots:
        frames=[master(start+i/12,.4) for i in range(round((end-start)*12))]
        head=frames[0]
        frames += [Image.blend(frames[-1],head,i/8) for i in range(1,9)]
        sample=Image.new('RGB',(160,90*len(frames)))
        for i,f in enumerate(frames):sample.paste(f.resize((160,90),RES.BILINEAR),(0,90*i))
        palette=sample.quantize(colors=256,method=Image.Quantize.MEDIANCUT)
        indexed=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
        delays=[80 if i%3!=2 else 90 for i in range(len(indexed))]
        indexed[0].save(ROOT/'loops'/(name+'.gif'),save_all=True,append_images=indexed[1:],
                        duration=delays,loop=0,disposal=1,optimize=False)


if __name__=="__main__":
    cli=argparse.ArgumentParser()
    cli.add_argument("target",choices=[*CUTS,"loops","stills"])
    target=cli.parse_args().target
    if target=="stills":
        for name,panel in print_panels().items():
            panel.save(ROOT/(name+".jpg"),quality=95,subsampling=0,optimize=True,icc_profile=PROFILE)
    elif target=="loops": loops()
    else: film(target)
