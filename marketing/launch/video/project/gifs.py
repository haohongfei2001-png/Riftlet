"""Four local product loops cut from the original window capture.

The looping edit dissolves briefly to the same paper at both ends. No product
action is reversed. Frame times are in seconds on the lossless capture.
"""
import subprocess

from PIL import Image
from films import FF, Footage
from graphics import KIT, WORK, NATIVE, MUTED, GREEN, label, new, paste_fit

CUTS = [
    ("01-arrival", 1.30, 4.45, "截图来到托盘", "第一张系统截图", None),
    ("02-tray-menu", 11.10, 16.65, "展开截图方式", "桌面托盘", None),
    ("03-thumbnail-press", 19.10, 21.70, "按下右侧微图", "macOS 辅助功能按压 · 局部原速", (262, 64, 650, 403)),
    ("04-two-captures", 1.13, 9.26, "两张图，先后到达", "连续收录", None),
]


def main():
    footage = Footage(NATIVE / "tray-lossless.mp4")
    directory = WORK / "gif"
    directory.mkdir(parents=True, exist_ok=True)
    output = KIT / "gif"
    output.mkdir(exist_ok=True)
    for name, start, end, heading, sub, crop in CUTS:
        fps = 25
        tmp = directory / (name + ".mov")
        basic = new((768, 570))
        label(basic, (44, 32), heading, 39, role="serif", zh=True)
        label(basic, (46, 512), sub, 22, color=MUTED, zh=True)
        label(basic, (723, 514), "Riftlet", 22, color=GREEN, role="medium", anchor="rt")
        proc = subprocess.Popen([FF,"-hide_banner","-loglevel","error","-y","-f","rawvideo","-pix_fmt","rgb24",
                                 "-s","768x570","-r",str(fps),"-i","pipe:0","-an","-c:v","qtrle",str(tmp)],stdin=subprocess.PIPE)
        length = round((end - start + .7)*fps)
        for i in range(length):
            t = i/fps
            rawtime = min(end, start + max(0,t-.35))
            still = footage.at(rawtime)
            subject = still.crop(crop or (60, 14, 652, 575))
            canvas = basic.copy()
            if crop:
                paste_fit(canvas, subject, (134, 105, 514, 378))
            else:
                paste_fit(canvas, subject, (82, 75, 604, 414))
            fade = min(1, max(0,t/.3), max(0,((length-1)/fps-t)/.30))
            if fade < 1:
                canvas = Image.blend(basic, canvas, fade)
            proc.stdin.write(canvas.tobytes())
        proc.stdin.close()
        if proc.wait(): raise RuntimeError("GIF mezzanine failed")
        graph = "[0:v]split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle"
        subprocess.run([FF,"-hide_banner","-loglevel","error","-y","-i",str(tmp),"-filter_complex",graph,
                        "-loop","0",str(output / (name+".gif"))],check=True)
        print(name,flush=True)


if __name__ == "__main__":
    main()
