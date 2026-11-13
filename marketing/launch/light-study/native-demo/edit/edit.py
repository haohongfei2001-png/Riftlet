"""Rebuild the public-build desktop excerpt. Requirements in README.md."""
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

import av
import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
DEMO = HERE.parent
SOURCE = DEMO / 'source'
DURATION_FRAMES = 720
W, H = 1920, 1080
PAPER, INK, LEAF, MUTED = '#fcfbf8', '#102a27', '#205e54', '#536862'
RULE = '#c9d2cb'
SERIF = str(HERE / 'instrument-serif.ttf')
SANS = '/System/Library/Fonts/HelveticaNeue.ttc'


def font(size, serif=False, bold=False):
    return ImageFont.truetype(SERIF if serif else SANS, size, index=1 if bold else 0)


def draw_label(canvas, xy, label, size=27, fill=MUTED, anchor='la'):
    ImageDraw.Draw(canvas).text(xy, label, font=font(size), fill=fill, anchor=anchor)


def smooth(value):
    u = max(0, min(1, value))
    return u*u*(3-2*u)


def lerp(a, b, u):
    return round(a+(b-a)*u)


def make_shell():
    shell = Image.new('RGB', (W, H), PAPER)
    pen = ImageDraw.Draw(shell)
    icon = Image.open(SOURCE / 'riftlet-app-icon.png').resize((66, 66), Image.Resampling.LANCZOS)
    shell.paste(icon, (82, 48), icon)
    pen.text((161, 44), 'Riftlet', font=font(58, serif=True), fill=INK)
    draw_label(shell, (W-95, 77), 'Desktop recording   /   Public Beta 0.3.5 (20)', 26, anchor='rm')
    pen.line((93, 140, W-94, 140), fill=RULE, width=2)
    return shell


def plate_window(name):
    # Preserve macOS window composition and the actual screenshot contents.
    src = Image.open(SOURCE / f'meridian-{name}-pixels.png').convert('RGB')
    src.thumbnail((993, 714), Image.Resampling.LANCZOS)
    w, h = src.size
    item = Image.new('RGBA', (w+78, h+88))
    shadow = Image.new('L', item.size)
    painter = ImageDraw.Draw(shadow)
    painter.rounded_rectangle((34, 33, w+33, h+32), radius=17, fill=36)
    shadow = shadow.filter(ImageFilter.GaussianBlur(12))
    item.putalpha(shadow)
    mask = Image.new('L', (w,h)); ImageDraw.Draw(mask).rounded_rectangle((0,0,w-1,h-1), radius=19, fill=255)
    item.paste(src, (34,23), mask)
    return item


def bottom_line(canvas, primary, secondary):
    pen = ImageDraw.Draw(canvas)
    pen.line((93, 925, W-94, 925), fill=RULE, width=2)
    pen.text((94, 947), primary, font=font(62, serif=True), fill=INK)
    draw_label(canvas, (W-94,997), secondary, 27, anchor='rm')


def macro_title(panel, y, first, second):
    pen = ImageDraw.Draw(panel)
    pen.text((94, y), first, font=font(94, serif=True), fill=INK)
    pen.text((94, y+95), second, font=font(94, serif=True), fill=INK)


def copy_area(t, shell):
    panel = shell.copy()
    if t < 16.0:
        draw_label(panel, (95, 233), 'Capture controls', 27, LEAF)
        macro_title(panel, 327, 'Choose a', 'capture mode.')
        lines = ['Open the camera control to see', 'the capture tools in place.']
    elif t < 20.35:
        draw_label(panel, (95, 233), 'Thumbnail input', 27, LEAF)
        macro_title(panel, 327, 'Press the', 'thumbnail.')
        lines = ['Two images are available', 'in the same tray.']
    else:
        draw_label(panel, (95, 233), 'Desktop result', 27, LEAF)
        macro_title(panel, 327, 'Both images', 'stay in the tray.')
        lines = ['This recording ends on the Mac.', 'A ChatGPT draft was not open.']
    for n, line in enumerate(lines):
        draw_label(panel, (97, 603+44*n), line, 31, MUTED)
    return panel


def render(output, preview=None):
    shell = make_shell()
    low, high = plate_window('low'), plate_window('high')
    plates = []
    for plate in (low, high):
        page = shell.copy()
        draw_label(page, (95, 167), 'Screenshot subject', 26, LEAF)
        page.paste(plate, (60, 191), plate)
        draw_label(page, (1161, 167), 'Native tray', 26, LEAF)
        plates.append(page)
    with av.open(str(SOURCE/'tray-native-lossless.mp4')) as recording:
        writer = None
        if preview is None:
            output.parent.mkdir(parents=True, exist_ok=True)
            writer = subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-loglevel','error', '-y',
                '-f','rawvideo','-pixel_format','rgb24','-video_size',f'{W}x{H}','-framerate','30','-i','-',
                '-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p',
                '-c:v','libx264','-preset','medium','-threads','3','-crf','16','-color_range','tv',
                '-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-an','-movflags','+faststart',str(output)],stdin=subprocess.PIPE)
        count = 0
        for n, frame in enumerate(recording.decode(video=0)):
            if preview and n not in preview: continue
            t = n/30
            subject = smooth((t-5.95)/.5)
            pivot = smooth((t-10.35)/.8)
            if subject <= 0: page = plates[0].copy()
            elif subject >= 1: page = plates[1].copy()
            else: page = Image.blend(plates[0],plates[1],subject)
            if pivot:
                macro = copy_area(t, shell)
                if pivot == 1: page = macro
                else: page = Image.blend(page,macro,pivot)
            # Each source frame occupies the original 1/30 s. Only the editorial crop moves.
            native = frame.to_image().convert('RGB')
            size = (lerp(735,1015,pivot),lerp(685,946,pivot))
            native = native.resize(size,Image.Resampling.LANCZOS)
            # Join the cropped native background seamlessly with the studio paper.
            page.paste(native,(lerp(1099,824,pivot),lerp(211,84,pivot)))
            if t < 6.25: bottom_line(page, 'Capture the inlet at low water.', 'macOS window capture')
            elif t < 10.74: bottom_line(page,'A second view, at high water.', 'Two consecutive captures')
            elif t < 16.0: bottom_line(page, 'The capture tools live in the tray.', 'Riftlet on macOS')
            elif t < 20.35: bottom_line(page, 'One tray. Two original captures.', 'Native desktop recording')
            else: bottom_line(page, 'Desktop excerpt', 'ChatGPT attachment was not recorded.')
            if preview:
                page.save(preview[n])
                continue
            writer.stdin.write(page.tobytes()); count += 1
        if writer:
            writer.stdin.close()
            if writer.wait() or count != DURATION_FRAMES: raise RuntimeError(f'Incomplete export: {count} frames')


if __name__ == '__main__':
    cli=argparse.ArgumentParser()
    cli.add_argument('--output',type=Path,default=DEMO.parent/'films'/'product-demo-native-excerpt.mp4')
    cli.add_argument('--previews',type=Path)
    arg=cli.parse_args()
    previews = None
    if arg.previews:
        arg.previews.mkdir(exist_ok=True,parents=True)
        previews = {n:arg.previews/f'{n:04}.jpg' for n in (3,109,268,329,390,560,638)}
    render(arg.output,previews)
