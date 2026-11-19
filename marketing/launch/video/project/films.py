"""Offline bilingual film and vertical edits. All native motion is source footage at 1x."""
import argparse
from functools import lru_cache
import subprocess
import wave

import imageio_ffmpeg
import numpy as np

from graphics import (KIT, WORK, NATIVE, PAPER, INK, GREEN, MUTED, WHITE,
                      PALE, DARK, brand, chart, label, line, lines,
                      new, paste_fit, photo, tr)

FPS = 30
FF = imageio_ffmpeg.get_ffmpeg_exe()
WIDE = (1920, 1080)
TALL = (1080, 1920)
MASTER_LENGTH = 40
SHORT_LENGTHS = {"value": 18, "controls": 19, "pair": 20}
MEDIA = {"master": "riftlet", "value": "01-by-sight", "controls": "02-tray-controls", "pair": "03-two-tides"}


def imtext(im, zh, x, y, cn, en, size, role="sans", color=INK, maxw=None):
    label(im, (x, y), tr(zh, cn, en), size, role=role, color=color, zh=zh, maximum=maxw)


def title(im, zh, x, y, cn, en, size, spacing, color=INK, width=None):
    lines(im, (x, y), tr(zh, cn, en), size, role="serif", color=color, zh=zh,
          leading=spacing, maximum=width)


def inset_source(im, high, box):
    paste_fit(im, photo("high-window.png" if high else "low-window.png"), box)


@lru_cache(maxsize=32)
def wide_base(phase, zh):
    im = new(WIDE)
    if phase == "open":
        brand(im, 112, 92, 48)
        title(im, zh, 108, 324, ["同一处海湾，", "哪里变了？"],
              ["One inlet.", "What changed?"], 121 if zh else 151, 151, width=832)
        imtext(im, zh, 114, 810, "把这张图，带进 ChatGPT 草稿。",
               "Bring the detail into your ChatGPT draft.", 38, color=MUTED, maxw=820)
        imtext(im, zh, 114, 943, "Mac 截图  /  Chrome 网页版 ChatGPT",
               "Mac screenshots  /  ChatGPT in Chrome", 28, color=MUTED)
    elif phase == "capture":
        im = new(WIDE, PALE)
        inset_source(im, False, (120, 114, 1035, 815))
        imtext(im, zh, 129, 960, "低潮  ·  macOS 窗口截图", "Low water  /  macOS window capture", 28, color=MUTED)
        title(im, zh, 1200, 344, ["照常截图。"], ["Take your", "screenshot."],
              103 if zh else 119, 117, width=630)
        lines(im, (1205, 650), tr(zh, ["macOS 将这张图存成文件。", "Riftlet 从截图文件夹收录。"],
              ["macOS saves the image.", "Riftlet picks up the new file."]), 34,
              leading=56, zh=zh, color=MUTED, maximum=617)
    elif phase in {"arrive", "pair", "menu", "press"}:
        imtext(im, zh, 118, 112, "桌面托盘  /  发行版实录", "Desktop tray  /  Release footage", 32, color=GREEN)
        if phase == "arrive":
            cn, en = ["刚截的图，", "就在手边。"], ["There’s your", "screenshot."]
            foot = ("桌面边缘出现第一张微图。", "The first thumbnail arrives at the edge.")
        elif phase == "pair":
            cn, en = ["再截一张。", "凭图认出来。"], ["A second tide.", "Side by side."]
            foot = ("同一处海湾，两个潮位。", "Same inlet. Two water levels.")
        elif phase == "menu":
            cn, en = ["托盘里，", "还有截图方式。"], ["A closer look", "inside the tray."]
            foot = ("展开相机键查看截图方式。", "Open the camera control to see capture modes.")
        else:
            cn, en = ["选中要用的", "那一张。"], ["Choose the", "detail you need."]
            foot = ("通过 macOS 辅助功能按下右侧微图。", "A macOS accessibility press selects the right thumbnail.")
        title(im, zh, 112, 325, cn, en, 102 if zh else 119, 121, width=795)
        imtext(im, zh, 117, 798, *foot, 34, color=MUTED, maxw=785)
        imtext(im, zh, 115, 953, "Riftlet  0.3.5（20）", "Riftlet  0.3.5 (20)", 26, color=MUTED)
    elif phase == "draft":
        im = new(WIDE, DARK)
        imtext(im, zh, 128, 126, "接下来  /  Google Chrome", "Next  /  Google Chrome", 32, color="#ABE1D0")
        title(im, zh, 122, 285, ["打开当前 ChatGPT 草稿，", "点图附加，自己发送。"],
              ["Bring your ChatGPT draft forward.", "Click to attach. You decide when to send."],
              106 if zh else 111, 152, color=WHITE, width=1640)
        line(im, (128, 795, 1790, 795), "#52796B", 2)
        imtext(im, zh, 129, 849, "build 18 已实测同一草稿接收两张图。此片的 build 20 实录止于桌面。",
               "Two images reached one draft in build 18. This build 20 film shows the desktop only.",
               36, color="#D3E7DD", maxw=1635)
    else:
        brand(im, 820, 206, 70)
        s = tr(zh, "把这一处，带进草稿。", "Bring this detail into the draft.")
        label(im, (960, 389), s, 107 if zh else 119, role="serif", zh=zh, anchor="mt", maximum=1650)
        label(im, (960, 632), "riftlet.com", 68, role="medium", color=GREEN, anchor="mt")
        msg = tr(zh, "Mac 公开测试版  ·  macOS 13 及以上", "Mac Public Beta  ·  macOS 13 or later")
        label(im, (960, 872), msg, 32, color=MUTED, zh=zh, anchor="mt")
    return im


def native_position(im, frame, portrait=False):
    if portrait:
        paste_fit(im, frame, (66, 610, 947, 882))
    else:
        paste_fit(im, frame, (953, 112, 922, 860))


def wide_frame(t, zh, footage):
    if t < 4.5:
        im = wide_base("open", zh).copy()
        sea = chart("low", False)
        shift = round(25 * min(1, t / 4.1))
        crop = sea.crop((247 + shift, 4, 869 + shift, 594))
        paste_fit(im, crop, (986, 0, 934, 1080), cover=True)
        return im
    if t < 9:
        return wide_base("capture", zh)
    if t < 29.5:
        raw_t = .7 + t - 9
        phase = "arrive" if raw_t < 6.7 else ("pair" if raw_t < 11.8 else ("menu" if raw_t < 16.65 else "press"))
        im = wide_base(phase, zh).copy()
        native_position(im, footage.at(raw_t))
        return im
    return wide_base("draft" if t < 35.8 else "end", zh)


@lru_cache(maxsize=40)
def tall_base(kind, phase, zh):
    im = new(TALL, DARK if phase == "end" else PAPER)
    if phase == "end":
        brand(im, 96, 268, 71, color=WHITE)
        title(im, zh, 93, 575, ["把这一处，", "带进草稿。"], ["Bring this detail", "into the draft."],
              107 if zh else 120, 142, color=WHITE, width=893)
        label(im, (98, 1090), "riftlet.com", 79, color="#8CE0CA", role="medium")
        imtext(im, zh, 100, 1352, "Mac 公开测试版", "Mac Public Beta", 42, color=WHITE)
        imtext(im, zh, 100, 1422, "macOS 13 及以上", "macOS 13 or later", 32, color="#C6DDD0")
        return im
    brand(im, 96, 121, 49)
    if kind == "value":
        lead = (["刚截的图，", "还要翻文件夹？"], ["Where did that", "screenshot go?"]) if phase == "intro" else (
            ["回到托盘，", "凭图来选。"], ["Find it", "by sight."])
        foot = ("准备给草稿提个关于海湾的问题。", "A shoreline detail for a question in your draft.") if phase == "intro" else (
               "在 Chrome 打开 ChatGPT 草稿，\n点图附加。", "Click to attach to your open ChatGPT draft in Chrome.")
    elif kind == "controls":
        lead = (["这个相机键，", "展开是什么？"], ["What’s inside", "the camera key?"]) if phase != "press" else (
            ["选中截图，", "留在手边。"], ["Choose", "a screenshot."])
        foot = ("托盘里有窗口、区域等截图方式。", "The tray gives you window and area capture controls.") if phase != "press" else (
               "实录到桌面选择为止。", "The recorded action ends at the desktop.")
    else:
        lead = (["低潮。", "再看一次高潮。"], ["Low water.", "Now high water."]) if phase == "intro" else (
            ["两张截图，", "同一个托盘。"], ["Two tides.", "One tray."])
        foot = ("同一处海湾，两次观察。", "Two observations of the same inlet.") if phase == "intro" else (
               "两次独立收录，按图选用。", "Two separate captures, ready to choose from.")
    title(im, zh, 91, 271, *lead, 100 if zh else 115, 122, width=902)
    if zh:
        subject_lines = foot[0].splitlines()
    else:
        import textwrap
        subject_lines = textwrap.wrap(foot[1], width=43)
    lines(im, (96, 1494), subject_lines, 40, leading=64, zh=zh, color=MUTED, maximum=895)
    return im


def tall_frame(t, kind, zh, footage):
    final = SHORT_LENGTHS[kind] - 3.5
    if t >= final:
        return tall_base(kind, "end", zh)
    intro = (kind != "controls" and t < (4.8 if kind == "value" else 4))
    selecting = kind == "controls" and t > 7.2
    phase = "intro" if intro else ("press" if selecting else "tray")
    im = tall_base(kind, phase, zh).copy()
    if intro:
        if kind == "value":
            inset_source(im, False, (63, 659, 954, 745))
        else:
            for i, name in enumerate(("low", "high")):
                y = 631 + i * 386
                paste_fit(im, chart(name, False), (96, y, 887, 318), cover=True)
                imtext(im, zh, 98, y + 327, ("低潮","高潮")[i], ("Low water","High water")[i], 27, color=GREEN)
    else:
        if kind == "controls":
            raw_t = min(23.5, 10.3 + t)
        elif kind == "value":
            raw_t = .6 + (t-4.8)
        else:
            raw_t = .5 + t-4
        native_position(im, footage.at(raw_t), portrait=True)
    return im


class Footage:
    def __init__(self, path):
        import av
        self.frames = []
        # Store original RGB frames once; identical adjacent native samples share storage.
        last = None
        with av.open(str(path)) as container:
            stream = container.streams.video[0]
            self.fps = float(stream.average_rate)
            for sample in container.decode(stream):
                image = sample.to_image().convert("RGB")
                pixels = image.tobytes()
                if last is None or pixels != last:
                    saved = image
                    last = pixels
                self.frames.append(saved)
        if not self.frames:
            raise ValueError("No native samples")

    def at(self, second):
        return self.frames[min(len(self.frames)-1, max(0, int(second * self.fps)))]


def score(kind, seconds):
    work = WORK / "audio"
    work.mkdir(parents=True, exist_ok=True)
    path = work / (kind + ".wav")
    rate = 48000
    # Original three-note editorial motif. No interface-sound samples.
    notes = {
        "master": [(0.18,196,1.6),(0.65,293.66,1.35),(4.55,329.63,.6),(9.05,246.94,1.2),(21.4,329.63,.75),(29.6,220,1.3),(35.9,196,2),(36.23,293.66,1.6),(36.6,392,1.9)],
        "value": [(.12,196,1.4),(4.85,293.66,1),(seconds-3.4,246.94,1.5),(seconds-3.08,369.99,1.65)],
        "controls": [(.12,293.66,1.2),(2,392,.6),(seconds-3.4,196,1.7),(seconds-3.08,293.66,1.55)],
        "pair": [(.12,196,1.3),(1.12,246.94,1.25),(4.05,293.66,1.1),(seconds-3.4,246.94,1.7),(seconds-3.08,369.99,1.65)]}
    audio = np.zeros(round(rate*seconds), dtype=np.float64)
    for at, pitch, length in notes[kind]:
        t = np.arange(round(length*rate)) / rate
        env = (1-np.exp(-t*50)) * np.exp(-3.8*t/length) * np.minimum(1,(length-t)*15)
        wavelet = np.sin(2*np.pi*pitch*t) + .16*np.sin(2*np.pi*pitch*2*t) + .065*np.sin(2*np.pi*pitch*3*t)
        start = round(at*rate)
        audio[start:start+len(t)] += .155 * env * wavelet
    with wave.open(str(path), "wb") as sound:
        sound.setparams((1,2,rate,0,"NONE","uncompressed"))
        sound.writeframes((audio*32767).astype("<i2").tobytes())
    return path


def render(kind, language, footage):
    zh = language == "zh-CN"
    wide = kind == "master"
    width, height = WIDE if wide else TALL
    seconds = MASTER_LENGTH if wide else SHORT_LENGTHS[kind]
    out = KIT / "video" / ("master" if wide else "shorts") / (MEDIA[kind] + "-" + language + ".mp4")
    command = [FF,"-hide_banner","-loglevel","error","-y","-f","rawvideo","-pix_fmt","rgb24",
               "-s",f"{width}x{height}","-r",str(FPS),"-i","pipe:0","-i",str(score(kind,seconds)),
               "-map","0:v","-map","1:a","-c:v","libx264","-preset","fast","-crf","17",
               "-pix_fmt","yuv420p","-colorspace","bt709","-color_primaries","bt709","-color_trc","bt709",
               "-vf","scale=in_range=pc:out_range=tv:out_color_matrix=bt709","-r",str(FPS),
               "-c:a","aac","-b:a","128k","-movflags","+faststart","-t",str(seconds),str(out)]
    out.parent.mkdir(parents=True, exist_ok=True)
    bake = subprocess.Popen(command, stdin=subprocess.PIPE)
    try:
        for i in range(seconds*FPS):
            t = i / FPS
            frame = wide_frame(t,zh,footage) if wide else tall_frame(t,kind,zh,footage)
            bake.stdin.write(frame.tobytes())
    finally:
        bake.stdin.close()
    if bake.wait() != 0:
        raise RuntimeError("Failed to export " + out.name)
    print(out.name, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=["master", *SHORT_LENGTHS, "all"], default="all")
    parser.add_argument("--language", choices=["zh-CN","en-US","both"], default="both")
    options = parser.parse_args()
    footage = Footage(NATIVE / "tray-lossless.mp4")
    for kind in ([options.kind] if options.kind != "all" else ["master", *SHORT_LENGTHS]):
        for locale in ([options.language] if options.language != "both" else ["zh-CN","en-US"]):
            render(kind, locale, footage)
