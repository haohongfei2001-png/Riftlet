# Riftlet · 截屏、点选、继续。

一位图片编辑想问车手入弯时的倾角。他在 Mac 上截下照片，点选托盘里的骑手，再回到已经写了一半的 ChatGPT 草稿。

| 语言 | 30 秒主片 · 1920 × 1080 | 15 秒竖版 · 1080 × 1920 | 高清封面原图 | 可选同语字幕 |
|---|---|---|---|---|
| 简体中文 | [播放主片](films/zh-CN/riftlet-commercial.mp4) | [播放竖版](films/zh-CN/riftlet-vertical.mp4) | [横版封面](thumbnails/zh-CN/riftlet-commercial.jpg) · [竖版封面](thumbnails/zh-CN/riftlet-vertical.jpg) | [主片 SRT](captions/zh-CN/riftlet-commercial.zh-CN.srt) · [竖版 SRT](captions/zh-CN/riftlet-vertical.zh-CN.srt) |
| English | [Play the commercial](films/en/riftlet-commercial.mp4) | [Play the vertical cut](films/en/riftlet-vertical.mp4) | [Landscape cover](thumbnails/en/riftlet-commercial.jpg) · [Portrait cover](thumbnails/en/riftlet-vertical.jpg) | [Commercial SRT](captions/en/riftlet-commercial.en.srt) · [Vertical SRT](captions/en/riftlet-vertical.en.srt) |

两个语言版各有自己的广告标题、摄影校样、桌面菜单、草稿和下载文案。简体中文版保留产品与平台名称、网址和真实快捷键。英文版采用全英文界面和文案。同语 SRT 可单独启用。每种时长使用一套原创配乐与拟音，全片无旁白。

四张封面均为嵌入 sRGB 配置的高清 JPEG，长宽与对应视频一致。封面的摄影原图、相机键和双图托盘直接取自本片制作工程。

## 制作工程

- [分镜及导演说明](studio/DIRECTION.md) · [原始图片、音乐母带和提示词](originals/)
- [公开版原生托盘及相机键](studio/tray/TRAY.md) · [两种语言的草稿画面](studio/chrome/composer-art.md) · [声音与同步点](studio/sound/SOUND.md)
- [公开版功能核验](review/product-verification.json) · [交付文件验收](review/REVIEW.md)

## 复现

在完整的 Riftlet 仓库中进入本目录。制作使用 macOS、Python 3.14、Helvetica Neue、SF Mono、Heiti SC、Songti SC 与 SF 系统符号。Instrument Serif 与正式标识从仓库 website-assets 读取。

```sh
python3 -m venv /tmp/riftlet-film-venv
source /tmp/riftlet-film-venv/bin/activate
python -m pip install -r studio/requirements.txt
python studio/sound/score.py originals/score-master.wav
python studio/sound/short_score.py originals/score-vertical.wav
python studio/subtitles.py
python studio/thumbnails.py
for lang in zh-CN en
do
    python studio/film.py master --lang "$lang"
    python studio/portrait.py --lang "$lang"
    python studio/inspect_export.py "films/$lang/riftlet-commercial.mp4" 900 "review/$lang/master-technical.json"
    python studio/inspect_export.py "films/$lang/riftlet-vertical.mp4" 450 "review/$lang/vertical-technical.json"
done
```

相机键的四倍分辨率原生图层随工程保存。若要从公开版本的 Git 对象重建，请按托盘工程说明运行 Swift 编译器。完整画面审片使用本机 AVPlayer，通过 `swiftc studio/Playback.swift -o /tmp/riftlet-watch` 编译，再运行 `/tmp/riftlet-watch films/zh-CN/riftlet-commercial.mp4 /tmp/riftlet-observations`。
