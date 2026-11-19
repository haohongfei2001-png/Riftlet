# Acceptance · 2026-11-14

## 交付核对

| 成片 | 解码帧数 | 原生播放器 | 音轨 |
|---|---:|---|---|
| Brand Film | 888 | 37.00 秒，自然结束 | 48 kHz 双声道 AAC |
| Product Demo 桌面节选 | 720 | 24.00 秒，自然结束 | 保留实录静音 |
| Capture | 192 | 8.00 秒，自然结束 | 48 kHz 双声道 AAC |
| At hand | 192 | 8.00 秒，自然结束 | 48 kHz 双声道 AAC |
| Draft | 204 | 8.50 秒，自然结束 | 48 kHz 双声道 AAC |

五个 MP4 均在无窗口的本地 macOS AVPlayer 按正常时钟播放到结束。检查每一秒输出的画面及末帧。另以 PyAV 解码每一帧，核对顺序、帧率、尺寸、总时长、音频采样和电平。四条配乐的解码峰值在 −3.64 至 −2.98 dBFS 之间。播放器静音运行，听感未做监听音箱复核。 [播放回执](player/) · [全部最终导出 SHA-256 与技术数据](technical.json)

四个 640 × 360 GIF 两轮解码的所有帧和延时一致，均可无限循环。六张展示图、三张封面及五张平台图均实际打开检查，复看了中英字符、边缘、按钮、极细线和取景框。播放中看到的稿件只停留在可编辑状态。修订时去除了托盘扩展过程中的重影，延后到达镜头的标题与说明，给中文视频封面安排日光交点构图，并修复初次合成音轨时的浮点包络端点。 [平台图片验收](platform-art-review.md)

本机为 Apple 芯片 Mac，macOS 27.0，具备 ScreenCapture、AppKit、AVFoundation、Swift 和 IINA。命令行环境使用现有 ImageIO 内置的 arm64 FFmpeg 9、PyAV、Pillow、NumPy。首次在沙箱中启动 AVPlayer 收到了 Cannot Decode，开启本机媒体服务访问后五片全部完整播放。 [初次回执](player/sandbox-attempt.json)

## 发行来源与可见范围

2026-11-14 直接核对官网和 GitHub Releases 列表。唯一公开条目为 2026-11-13 发布的 0.3.5（20）Public Beta，标记 prerelease，发布标签指向 939e3af47ba18d4850311528130934c586cfcb76。DMG 的 SHA-256 为 c4bdeeca1410cc42649c3e3b8437ddd704605013d90ed9553bdc242f2d74cc7a。公开操作及支持范围取自发行页、实际托盘画面、发布标签内的网格布局代码以及公开支持矩阵。 [GitHub Release](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1) · [官网](https://riftlet.com/) · [发行版托盘布局](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletUI/RiftTrayLayout.swift)

早期推广工作树已有创意提交 7ce0f9b 和独立拍摄工作。本次复用其中原创的潮位图、白名单 WindowServer 素材及播放器验证程序，在新目录另行剪辑。实际产品节选保留公开发行包的 24 秒原生托盘像素。记录中两张输入均保留，附加操作数为零；品牌片展示其余工作流程时使用设计动画。 [取景、时钟和两个原件](../native-demo/source/record.json) · [解码比对](source-equivalence.json)

此次交付覆盖剪辑、合成与成片检查。平台素材尚未通过各平台投稿工具预览或发布。
