"""Render the Chinese native desktop demo with its separate attachment instructions.

Run on macOS with the same libraries as edit.py (Pillow, PyAV, imageio-ffmpeg).
The final six seconds are editorial type. No browser footage is composited.
"""
from __future__ import annotations

import argparse
from functools import lru_cache
from pathlib import Path
import subprocess

import av
import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

from edit import W, H, INK, PAPER, LEAF, MUTED, RULE, smooth

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / 'source-1.0.3'
FPS = 30
RECORDING_FRAMES = 720
TOTAL_FRAMES = 900
SONGTI = '/System/Library/Fonts/Supplemental/Songti.ttc'
SANS = '/System/Library/Fonts/Hiragino Sans GB.ttc'
PREVIEW_FRAMES = [5, 107, 230, 391, 556, 578, 609, 684, 777, 895]


@lru_cache(maxsize=40)
def face(size, family):
    if family == 'title':
        return ImageFont.truetype(SONGTI, size, index=1)
    if family == 'brand':
        return ImageFont.truetype(str(HERE/'instrument-serif.ttf'), size)
    return ImageFont.truetype(SANS, size, index=2 if family == 'bold' else 0)


def words(draw, xy, value, size, family='body', color=INK, anchor='la'):
    draw.text(xy, value, font=face(size, family), fill=color, anchor=anchor)


def masthead(dark=False):
    ground = '#123832' if dark else PAPER
    color = '#fafaf2' if dark else INK
    page = Image.new('RGB', (W,H), ground)
    draw = ImageDraw.Draw(page)
    with Image.open(SOURCE/'riftlet-app-icon.png') as source_icon:
        icon = source_icon.convert('RGBA').resize((69,69), Image.Resampling.LANCZOS)
    page.paste(icon,(91,53),icon)
    words(draw,(177,46),'Riftlet',59,'brand',color)
    words(draw,(1817,87),'使用指引' if dark else '桌面实录    /    录制版本 1.0.3（25）',30,color=color,anchor='rm')
    draw.line((98,151,1821,151),fill='#54726a' if dark else RULE,width=2)
    return page


@lru_cache(maxsize=2)
def subject_page(name):
    page = masthead()
    draw = ImageDraw.Draw(page)
    words(draw,(100,183),'窗口截图',28,color=LEAF)
    words(draw,(1157,183),'Riftlet 托盘',28,color=LEAF)
    with Image.open(SOURCE / f'meridian-{name}-pixels.png') as image:
        plate = image.convert('RGBA')
        plate.thumbnail((944,680), Image.Resampling.LANCZOS)
        page.paste(plate,(102,245),plate)
    return page


@lru_cache(maxsize=8)
def closeup_page(heading, row1, row2):
    page = masthead()
    draw = ImageDraw.Draw(page)
    words(draw,(101,259),'托盘操作',30,color=LEAF)
    words(draw,(97,360),heading,86,'title')
    words(draw,(102,555),row1,38,color=MUTED)
    words(draw,(102,616),row2,38,color=MUTED)
    return page


def lower_third(page, text):
    draw = ImageDraw.Draw(page)
    draw.line((98,941,1821,941),fill=RULE,width=2)
    words(draw,(99,965),text,45,'title')


def desktop(frame, n):
    t = n/FPS
    if t < 10.75:
        mix = smooth((t-5.97)/.40)
        if mix == 0:
            page = subject_page('low').copy()
        elif mix == 1:
            page = subject_page('high').copy()
        else:
            page = Image.blend(subject_page('low'),subject_page('high'),mix)
        x, y, width = 1108, 235, 721
        if t < 2.34: caption = '先截取低潮时的河湾。'
        elif t < 6.25: caption = '第一张系统截图，出现在托盘里。'
        elif t < 7.35: caption = '再截取高潮时的同一处河湾。'
        else: caption = '第二张紧随其后，两张图都在手边。'
    else:
        if t < 16.18:
            page = closeup_page('展开截图方式','点托盘里的相机，可以选择','截取区域、全屏或窗口。').copy()
            caption = '原生截图菜单在托盘内展开。'
        elif t < 20.42:
            page = closeup_page('依次按下两张图','先选左边的低潮图，','再选右边的高潮图。').copy()
            if t < 18.73: caption = '两张图可以分别选择。'
            elif t < 20.02: caption = '操作记录 · 按下第一张缩略图'
            else: caption = '操作记录 · 按下第二张缩略图'
        else:
            page = closeup_page('两张图仍在托盘','拍摄时没有打开 ChatGPT 草稿，','这次操作停在桌面。').copy()
            caption = '本段实录到此，未产生网页附加。'
        x, y, width = 818, 108, 1009
    frame = frame.crop((115, 40, 652, 540))
    height = round(width*frame.height/frame.width)
    # Leave the masthead and lower-third undisturbed. The product pixels and shadows
    # are confined to this payload throughout the locked-off desktop shot.
    live = frame.resize((width,height),Image.Resampling.LANCZOS)
    top = max(0,154-y); bottom = min(height,938-y)
    page.paste(live.crop((0,top,width,bottom)),(x,y+top))
    lower_third(page,caption)
    return page


def attachment_guide():
    page = masthead(dark=True)
    draw = ImageDraw.Draw(page)
    words(draw,(100,224),'在 Chrome 里继续',32,color='#9fdbca')
    words(draw,(91,305),'附加到当前草稿',115,'title','#fffdf5')
    words(draw,(101,538),'打开可编辑的 ChatGPT 草稿，让 Chrome 保持在前台。',44,color='#fffdf5')
    words(draw,(101,637),'点一下托盘里的缩略图。草稿开始接收时，缩略图收起。',44,color='#fffdf5')
    draw.line((99,849,1821,849),fill='#54726a',width=2)
    words(draw,(101,897),'何时发送，由你决定。',39,'title','#b7e9d5')
    return page


def encode(output, previews):
    writer=None
    if previews is not None:
        previews.mkdir(parents=True,exist_ok=True)
    else:
        output.parent.mkdir(parents=True,exist_ok=True)
        writer=subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-loglevel','error','-y',
            '-f','rawvideo','-pixel_format','rgb24','-video_size',f'{W}x{H}','-framerate',str(FPS),'-i','-',
            '-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p',
            '-c:v','libx264','-preset','medium','-crf','16','-threads','4',
            '-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709',
            '-metadata:s:v:0','language=zho','-an','-movflags','+faststart',str(output)],stdin=subprocess.PIPE)

    def emit(image, n):
        if previews is not None:
            image.save(previews/f'{n:04d}.jpg',quality=92)
        else:
            writer.stdin.write(image.tobytes())

    with av.open(str(SOURCE/'tray-native-lossless.mp4')) as recording:
        count=0
        for n,source_frame in enumerate(recording.decode(video=0)):
            count+=1
            if previews is None or n in PREVIEW_FRAMES:
                emit(desktop(source_frame.to_image().convert('RGB'),n),n)
        if count != RECORDING_FRAMES:
            raise RuntimeError(f'Expected 720 native frames, got {count}')
    guide=attachment_guide()
    for n in range(RECORDING_FRAMES,TOTAL_FRAMES):
        if previews is None or n in PREVIEW_FRAMES:
            emit(guide,n)
    if writer is not None:
        writer.stdin.close()
        if writer.wait():
            raise RuntimeError('Encoder failed')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=HERE.parents[1]/'films'/'product-demo.zh-CN.mp4')
    parser.add_argument('--previews',type=Path)
    args=parser.parse_args()
    encode(args.output,args.previews)
