# Editable production

Run from `marketing/launch/light-study` on macOS. Use Python 3.12+ with Pillow, NumPy, PyAV, fonttools with Brotli, and imageio-ffmpeg. The production host used Python 3.14, Pillow 13, NumPy 2.5 and PyAV 19. System Helvetica Neue, STHeiti, SF Mono, Songti and PingFang must be available. The repository contains Instrument Serif under its OFL license. ImageIO provides FFmpeg/x264, including when no ffmpeg is on PATH.

```sh
python studio/render.py brand
python studio/render.py capture
python studio/render.py at-hand
python studio/render.py draft
python studio/render.py loops
python studio/render.py stills
python studio/platforms.py
python native-demo/edit/edit.py
```

Edit timing and composition in [art.py](art.py) and [editions.py](editions.py), font sizes and native tray dimensions in art.py, and the music cues in [score.py](score.py). The [storyboard](direction.md) describes the cut. The platform script reads the same originals. [Captions](../captions/) are optional sidecar tracks. Each output section is independently rebuildable. The product demo retains its own camera source and timeline.

The MP4 masters use progressive H.264, 4:2:0 limited-range BT.709 and front-loaded MP4 headers. Brand edits use stereo 48 kHz AAC. The GIFs use a shared palette within each file and a return dissolve. Stills carry an embedded sRGB profile. All frames use original typography and the shipped product's 246-unit tray layout as the reference.
