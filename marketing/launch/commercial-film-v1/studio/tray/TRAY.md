# 托盘画面

广告选择公开版已有的“截图托盘 / 紫蓝玻璃 / 右中”组合，内建截图键开启，缩略图遮挡为零。实际拍摄情节采用 macOS 系统区域截图。托盘中的相机键保留，鼠标只点击第一张截图。两张画稿分别来自视频使用的同一份源 PNG。

## 来源

所有图层参照公开标签 `v0.3.5-beta.1`，提交 `939e3af47ba18d4850311528130934c586cfcb76`。在实查的 main `280be2f8422ccf6c0864f53b8f83e80552b2ec32` 中，以下五个文件仍与标签逐字节一致。

| 图层 / 动作 | 依据 |
| --- | --- |
| 相机键、键面、底沿、取景器和镜头轮廓 | [RiftTraySurfaceView.swift](https://github.com/haohongfei2001-png/Riftlet/blob/939e3af47ba18d4850311528130934c586cfcb76/Sources/RiftletUI/RiftTraySurfaceView.swift) |
| 托盘宽度、图槽、原图等比完整放置和相机位置 | [RiftTrayLayout.swift](https://github.com/haohongfei2001-png/Riftlet/blob/939e3af47ba18d4850311528130934c586cfcb76/Sources/RiftletUI/RiftTrayLayout.swift) |
| 浅色紫蓝玻璃及独立投影 | [RiftTrayGlass.swift](https://github.com/haohongfei2001-png/Riftlet/blob/939e3af47ba18d4850311528130934c586cfcb76/Sources/RiftletUI/RiftTrayGlass.swift) |
| 缩略图薄框、底衬、按压及阴影 | [RiftThumbnailAppearance.swift](https://github.com/haohongfei2001-png/Riftlet/blob/939e3af47ba18d4850311528130934c586cfcb76/Sources/RiftletUI/RiftThumbnailAppearance.swift) |
| 真实附加开始后的 120ms 吞入、保护空位、160ms 补位 | [RiftPanelController.swift](https://github.com/haohongfei2001-png/Riftlet/blob/939e3af47ba18d4850311528130934c586cfcb76/Sources/RiftletUI/RiftPanelController.swift) |

`plates/camera.png` 由标签原有 AppKit 私有 `TrayButton.draw(_:)` 在透明位图上绘制。为使输入可控，辅助程序只在临时目录编译未改写的原生按键绘制路径。无可见窗口、系统屏幕采集、上传或账户数据读取。缩略图直接取原图，保留全部内容和比例。外框、材质、色调、玻璃投影和路径时序在 Pillow 内重建。透明叠层没有重放系统 WindowServer 折射。画面来自离屏原生图层与合成动画。

## 合成接口

在 `tray.py` 所在目录，安装 Pillow，通过 `Tray(a_png, b_png).render(seconds)` 取得 1320 × 1184 RGBA 层。图层原点在左上，每参考单位为四个像素。246 单位宽、115 或 212 单位高的玻璃固定在 x=42、下沿 y=254。按电影工作区比例统一缩放，成片窗口中的玻璃宽为虚拟 Mac 显示器宽度的八分之一。相机键在空队列中保留。调用方在放置层时保留四周透明阴影。输出图像可在调用方重采样或拷贝；请勿直接修改渲染缓存。

首图出现于 5.55s，第二张出现于 8.55s。13.20s 按下的是第一张原图。13.45s 情节中同张图的附件开始出现，托盘在 120ms 内退出第一张。指针及时离开后，14.70s 开始补位，第二张继续可选。若重剪改变指针或附件节拍，初始化时传入 `Timing(first=..., second=..., press=..., attachment_start=..., refill=...)`。首图点击点在双图时为图层坐标 (105.75, 99) 参考单位。

如须从 Git 对象重新生成原生相机键，在装有 Xcode 命令行工具的 Mac 执行下列命令。四倍 PNG 已随工程保存，日常渲染直接读取该文件。

```sh
python3 make_native_plate.py /path/to/Riftlet plates
```
