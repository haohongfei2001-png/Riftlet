"""Audit the actual exported streams and hashes, including AAC loudness and front-loaded index."""
import argparse
import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path
import av
import imageio_ffmpeg

def boxes(path):
    out=[]
    with path.open('rb') as f:
        while data:=f.read(8):
            length,kind=struct.unpack('>I4s',data)
            if length==1:
                length=struct.unpack('>Q',f.read(8))[0]; f.seek(length-16,1)
            elif length==0: break
            else:f.seek(length-8,1)
            out.append(kind.decode())
    return out

def inspect(path,expected):
    with av.open(str(path)) as inp:
        vid=inp.streams.video[0]; aud=inp.streams.audio[0]
        w,h=vid.width,vid.height
        vid_info=(int(vid.color_primaries),int(vid.colorspace),int(vid.color_trc),int(vid.color_range))
        with path.open('rb') as source:
            digest=hashlib.file_digest(source,'sha256').hexdigest()
        out=dict(sha256=digest,bytes=path.stat().st_size,
                 codec=vid.codec_context.name,profile=vid.codec_context.profile,width=w,height=h,
                 fps=float(vid.average_rate),pixelFormat=vid.format.name,
                 durationSeconds=float(vid.duration*vid.time_base), audio=aud.codec_context.name,
                 audioSeconds=float(aud.duration*aud.time_base),sampleRate=aud.rate,layout=aud.layout.name)
        pts=[round(float(frame.pts*frame.time_base)*30) for frame in inp.decode(vid)]
        out['decodedFrames']=len(pts)
        out['unbrokenPresentationTimestamps']=pts==list(range(expected))
    ff=imageio_ffmpeg.get_ffmpeg_exe()
    res=subprocess.run([ff,'-hide_banner','-nostats','-i',str(path),'-vn','-af','ebur128=peak=true','-f','null','-'],
                       capture_output=True,text=True,check=True).stderr
    report=res.rsplit('Summary:',1)[1]
    out['integratedLUFS']=float(re.search(r'I:\s*([-\d.]+) LUFS',report)[1])
    out['truePeakDBTP']=float(re.search(r'Peak:\s*([-\d.]+) dBFS',report)[1])
    out['loudnessRangeLU']=float(re.search(r'LRA:\s*([-\d.]+) LU',report)[1])
    out['bt709PrimariesAndMatrix']=vid_info == (1,1,13,1)
    out['transfer']='sRGB' if vid_info[2]==13 else str(vid_info[2])
    out['boxes']=boxes(path)
    assert out['boxes'].index('moov')<out['boxes'].index('mdat')
    assert out['unbrokenPresentationTimestamps'] and out['decodedFrames']==expected
    assert out['codec']=='h264' and out['profile']=='High' and out['fps']==30 and out['pixelFormat']=='yuv420p' and out['bt709PrimariesAndMatrix']
    assert (w,h)==((1920,1080) if expected==900 else (1080,1920))
    assert abs(out['durationSeconds']-expected/30)<.001 and abs(out['audioSeconds']-expected/30)<.025
    assert out['audio']=='aac' and out['sampleRate']==48000 and out['layout']=='stereo' and out['truePeakDBTP'] < -1.
    return out

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('file',type=Path);p.add_argument('frames',type=int);p.add_argument('receipt',type=Path)
    a=p.parse_args();v=inspect(a.file,a.frames)
    a.receipt.write_text(json.dumps(v,indent=2)+'\n')
    print(json.dumps(v,indent=2))
