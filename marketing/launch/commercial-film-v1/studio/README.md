# 制作和复查

在完整的 macOS 仓库中，用 Python 虚拟环境安装 `studio/requirements.txt`。工程使用官网已有的 Riftlet 标识及 Instrument Serif，字幕和本地化界面用 macOS 随附字体。品牌文件在仓库的 `website-assets/`。横版的画面、鼠标、窗口、镜头和声音从本地源码生成。

从本宣传目录运行：

```sh
python studio/make_capture_props.py
python studio/score.py --out film/score.wav
python studio/film.py zh-CN
python studio/film.py en
```

`studio/composer.py` 绘制两种语言的 Chrome 草稿。`studio/appearances.py` 绘制托盘与微缝的并列表现。`studio/film.py` 用同一张趋势图生成桌面选区、屏幕边缘缩略图和草稿里的新附件。字幕单独放在各主片旁，可供平台上传。画面不依赖字幕文件也能独立播放。仓库内的图表均为项目专用的虚构周报数据，品牌图案、界面和字体由确定性合成生成，本次未使用生成式图像、视频或音乐服务，无生成提示词。

`studio/score.py` 使用确定性软件合成器生成 48 kHz、24 位 PCM 的双声道音乐及拟音。截屏、微图出现、点击和附加提示依次落在 2.73、3.16、4.33、4.80 秒。声音时间用于这支片子的剪辑，不能当作产品性能数据。

验收可用 `python studio/verify.py film/zh-CN/master.mp4 film/en/master.mp4` 查看逐帧时间戳、音视频完整性、响度与校验和。macOS 上可编译 `swiftc studio/Playback.swift -o /tmp/riftlet-playback` 后执行 `/tmp/riftlet-playback film/zh-CN/master.mp4 /tmp/riftlet-zh-observations 0.5`，由 AVPlayer 按正常速率播放至片尾，按时钟保存观察帧。播放器默认静音，以避免占用本机扬声器。

横版高清缩略图从成片第 172 帧（0 起算 171，第 5.70 秒）解码为 1920 × 1080 JPEG，由横版渲染脚本自动写出。另行设计的传播封面在 `social/covers/`。

竖版脚本复用同一份场景、图表与音乐母带，以手机阅读尺寸重新构图。从本宣传目录运行 `python studio/vertical.py zh-CN --render` 和 `python studio/vertical.py en --render`。竖版工程与样片说明见[竖版剪辑记录](../review/vertical.md)。
