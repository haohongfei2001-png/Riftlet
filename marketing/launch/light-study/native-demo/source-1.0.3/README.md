# 1.0.3 中文桌面演示

2026 年 11 月 17 日，已安装的 1.0.3（25）通过单独的 `--settings-review` 实例运行。可执行文件与 GitHub 公开 ZIP 内的文件 SHA-256 相同。独立资料目录下的实际收录器接收 macOS 生成的两张窗口截图。窗口只显示为 Riftlet 创作的低潮和高潮示意图，两个原件都自带系统截图标记。托盘的窗口层和专用背景按进程白名单取景，系统指针未入镜。[公开发行](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.3-zip) · [录制回执与校验值](record.json)

| 时间 | 可核对的动作 |
| --- | --- |
| 2.33 秒 | 低潮图被收录。 |
| 7.33 秒 | 高潮图被收录。两份本地副本的字节分别与系统原件一致。 |
| 12.11 秒 | 原生截图方式菜单展开，列出区域、全屏与窗口截图等入口。 |
| 19.13 秒 | 向第一张缩略图定向投递鼠标按下、抬起动作。 |
| 20.12 秒 | 第二张缩略图的辅助功能按下动作返回。 |
| 21.04 秒 | 两张图仍在托盘，状态均为 `pending`，操作表记录数为零。 |
| 24–30 秒 | 切至中文「使用指引」，说明在 Chrome 的可编辑 ChatGPT 草稿中附加的步骤。 |

剪辑连续使用本次桌面取景的 720 帧。源视频采用无损 RGB 压缩，原始影片与公开文件逐帧像素及显示时间相同。两张公开 PNG 保留原件 RGBA 像素并去除设备元数据。录制回执只保留动作、相对时间和素材身份。原生定向输入与用户手动操作不同，本次隔离模式不执行网页附加。

在 macOS 上安装本工程使用的 Pillow、PyAV、imageio-ffmpeg 后，从 `light-study` 目录运行 `python native-demo/edit/edit_zh.py` 生成[中文影片](../../films/product-demo.zh-CN.mp4)。录制使用[原有拍摄工程](https://github.com/haohongfei2001-png/Riftlet/tree/352dd33ab5f3acf3350ce32e4c614fa30c42b5c4/marketing/launch/video/project/capture)和相同的原创图版；本轮只更新录制脚本中的版本检查及发行标签。原生来源、剪辑和实时播放分别留有记录。[相对采样时刻](samples.json)
