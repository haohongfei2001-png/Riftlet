# 重建与编辑

本目录是可编辑的剪辑与设计工程。发布包的不可重演部分已经作为 [无损片源](../../source/edit/) 入库；原始屏幕采样、图片、工程与成品之间的对应关系见 [拍摄记录](../capture-log.md)。重剪现有素材只需本机字体、发行库中的输入和离线编辑依赖。

## 从工作树重建

在仓库根目录运行。记录环境为 macOS 27.0 / arm64，Python 3.14，FFmpeg 9.0（imageio-ffmpeg 自带）。命令写入本分支的素材目录和被忽略的 `build/launch-production` 工作目录。输入文件、声音、拍摄包均有单独来源。

```sh
python3 -m venv build/launch-production/venv
build/launch-production/venv/bin/pip install -r marketing/launch/video/project/requirements.txt
build/launch-production/venv/bin/python marketing/launch/video/project/plates.py
build/launch-production/venv/bin/python marketing/launch/video/project/films.py
build/launch-production/venv/bin/python marketing/launch/video/project/gifs.py
build/launch-production/venv/bin/python marketing/launch/video/project/print.py
```

- [films.py](films.py) 定义中英主片、三种竖片的镜头时长、文字、画幅及原创配乐。用 `--kind master --language zh-CN` 只导出一个版本。`--kind` 也接受 `value`、`controls` 和 `pair`。时间线按秒选择真实源帧。
- [graphics.py](graphics.py) 管理字体、品牌和窗口图层。简体中文默认匹配 macOS 的宋体与苹方。若系统字体存放位置不同，可用 `RIFTLET_PINGFANG` 指定 PingFang.ttc。英文展示字由仓库中的 Instrument Serif 字体解包到临时目录，只用于渲染。
- [plates.py](plates.py) 以同一高程面绘制两张原创潮汐图；[gifs.py](gifs.py) 保存四个循环的入点、出点与裁框；[print.py](print.py) 保存每张产品图、封面的单独版式。
- [capture/](capture/README.md) 使用已核对的正式包、专用 UUID 与新样张重新取景。已有的剪辑输入不依赖重新取景。原始录屏留在本工作树的 `marketing/launch/source/raw/tray-native.mov`，约 33 MiB；[公开片源](../../source/edit/tray-lossless.mp4) 约 1.9 MiB。
- [verify/](verify/README.md) 通过系统 AVPlayer 实时逐片播放与取帧，检查字幕、AAC 编码与原始配乐同步，并逐图核对 GIF 和 PNG。数据和审阅结论见 [质量验收](../../evidence/quality.md)。
