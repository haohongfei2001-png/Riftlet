# Riftlet · Capture. Click. Continue.

一位图片编辑在 Mac 上挑中了弯道里那位红衣骑手。他把照片点进手头的 ChatGPT 草稿，接着写完有关倾角的问题。

| 成片 | 播放文件 | 简体中文字幕 |
|---|---|---|
| 主宣传片 · 30 秒 | [1920 × 1080 MP4](films/riftlet-commercial.mp4) | [SRT](captions/riftlet-commercial.zh-CN.srt) |
| 竖屏剪辑 · 15 秒 | [1080 × 1920 MP4](films/riftlet-vertical.mp4) | [SRT](captions/riftlet-vertical.zh-CN.srt) |

两片均为英文画面文案、画面烧录简体中文字幕、原创配乐与拟音。SRT 可用于平台的可访问字幕轨；画面内已经有中文字幕。

## 查看工程

- [分镜及导演说明](studio/DIRECTION.md) 记录主片的镜头、配色、声音落点及素材取舍。
- [原始素材](originals/) 包含四张生成原图、逐字提示词及无损声音母带。字幕、产品界面、摄影校样、选区、指针和所有品牌文字在后期独立绘制。
- [托盘工程](studio/tray/TRAY.md) 记录原生相机键的公开版本与透明图层来源。[草稿工程](studio/chrome/composer-art.md) 提供界面绘制、坐标和输入时序。[声音工程](studio/sound/SOUND.md) 保留各声部、乐句和交互拟音。
- [公开版验证](review/product-verification.json) 记录签名包、自检和本机受控 Chrome 运行。[成片验收](review/REVIEW.md) 包含逐段观察及交付文件技术结果。

## 复现

从完整的 Riftlet 仓库检出本 PR，进入本目录。制作使用 Apple Silicon macOS、Python 3.14、Helvetica Neue、SF Mono 及华文黑体。Instrument Serif 与标识直接从仓库的 website-assets 读取。

```sh
python3 -m venv /tmp/riftlet-film-venv
source /tmp/riftlet-film-venv/bin/activate
python -m pip install -r studio/requirements.txt
python studio/sound/score.py originals/score-master.wav
python studio/sound/short_score.py originals/score-vertical.wav
python studio/film.py master
python studio/portrait.py
python studio/subtitles.py
python studio/inspect_export.py films/riftlet-commercial.mp4 900 review/master-technical.json
python studio/inspect_export.py films/riftlet-vertical.mp4 450 review/vertical-technical.json
```

相机键的 4× 原生图层已随工程保留。若要重新输出该图层，按托盘工程说明读取公开版本的 Git 对象，并在 macOS 使用 Swift 编译器。其余画面和音轨渲染完全在本机离线进行。

完整审片使用本机 AVPlayer 的 1× 媒体时钟。查看实时图像输出可编译并运行 `swiftc studio/Playback.swift -o /tmp/riftlet-watch`，再运行 `/tmp/riftlet-watch films/riftlet-commercial.mp4 /tmp/riftlet-observations`。该工具静音播放，声音检验记录来自独立的母带和导出混音。
