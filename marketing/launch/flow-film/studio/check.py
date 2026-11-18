"""Decode every frame and audio packet, and verify the deliverable specifications."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

import av
import imageio_ffmpeg
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def inspect(path):
    vertical = path.stem == 'vertical'
    expected = 15 if vertical else 24
    dims = (1080, 1920) if vertical else (1920, 1080)
    with av.open(str(path)) as movie:
        video, audio = movie.streams.video[0], movie.streams.audio[0]
        assert video.codec_context.name == 'h264' and video.codec_context.format.name=='yuv420p'
        assert (video.width,video.height)==dims and video.average_rate==30
        assert audio.codec_context.name=='aac' and audio.rate==48000 and audio.layout.name=='stereo'
        assert movie.duration==expected*av.time_base
        frames=samples=0
        for packet in movie.demux(video,audio):
            for frame in packet.decode():
                if isinstance(frame,av.VideoFrame):
                    assert abs(float(frame.pts*frame.time_base)-frames/30)<.0001
                    frames+=1
                else:
                    samples+=frame.samples
        assert frames==expected*30 and expected*48000<=samples<expected*48000+1024
        profile=video.codec_context.profile
    probe=subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-nostats','-i',str(path),
                          '-vn','-af','ebur128=peak=true','-f','null','-'],capture_output=True,check=True)
    summary=probe.stderr.decode().split('Summary:')[-1]
    lufs=float(re.search(r'I:\s*([-\d.]+) LUFS',summary).group(1))
    peak=float(re.search(r'Peak:\s*([-\d.]+) dBFS',summary).group(1))
    assert -19<lufs<-13 and peak<0
    return {'file':str(path.relative_to(ROOT)),'seconds':expected,'frames':frames,'size':dims,
            'fps':30,'h264_profile':profile,'audio':'AAC stereo 48000 Hz',
            'integrated_LUFS':lufs,'true_peak_dBTP':peak,'bytes':path.stat().st_size,
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


if __name__=='__main__':
    results=[inspect(p) for p in sorted((ROOT/'films').glob('*/*.mp4'))]
    assert len(results)==4
    covers={}
    for file in sorted((ROOT/'covers').glob('*/*.jpg')):
        with Image.open(file) as im:
            im.load()
            assert im.format=='JPEG' and im.info.get('icc_profile') and file.stat().st_size<2000000
            covers[str(file.relative_to(ROOT))]=im.size
    assert len(covers)==6
    data=json.dumps({'films':results,'covers':covers},indent=2,ensure_ascii=False)+'\n'
    (ROOT/'review/technical.json').write_text(data)
    print(data)
