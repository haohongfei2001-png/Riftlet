# 中文版与英文版成片验收

每种语言各交付一条 30 秒主片与一条 15 秒竖版。两个语言版沿用同一张骑手原图、蓝色跑道原图和既有点击时序。四个文件逐一进行了播放和技术核查。

## 画面与语言

| 镜头 | 简体中文版 | 英文版 |
|---|---|---|
| 开场 | 「让思路继续。」及 Mac 截图进入 Chrome 中 ChatGPT 草稿的说明 | “Keep the thought.” and “Mac screenshots to ChatGPT in Chrome.” |
| 桌面与校样 | 「赛道习作」、中文菜单与日期、中文图片编辑部信息 | “Track study”, English menus, English date and editorial labels |
| 截屏与托盘 | 「截屏」「就在手边」「两张都在」，使用 ⇧、⌘ 和数字 4 | “Capture.”, “At hand.”, “Both here.” and the English key names |
| 单击与续写 | 骑手图进入原草稿，用户接写「看看车手的倾角。」 | The rider appears in the draft. The writer adds “Look at the lean.” |
| 片尾 | 「截屏、点选、继续。」与「下载 macOS 公测版」 | “Capture. Click. Continue.” and “Download for macOS · Public Beta” |

两种语言的广告、桌面和编辑框均在原图层按各自文字宽度重排。中文的产品名称、系统名称、网址、文件扩展名和键盘标记沿用实际写法。原图中的物理键盘保留自身键帽标记。简体中文与英文均提供独立 UTF-8 SRT；每个 MP4 的画面只呈现该语言版本的文案。

## 技术验收

| 版本 | 时长与尺寸 | 完整解码 | AAC | 明细 |
|---|---|---|---|---|
| 中文主片 | 30.000 秒 · 1920 × 1080 | 900 帧 | −15.9 LUFS / −3.1 dBTP | [技术记录](zh-CN/master-technical.json) |
| English master | 30.000 秒 · 1920 × 1080 | 900 帧 | −15.9 LUFS / −3.1 dBTP | [Technical record](en/master-technical.json) |
| 中文竖版 | 15.000 秒 · 1080 × 1920 | 450 帧 | −15.9 LUFS / −3.7 dBTP | [技术记录](zh-CN/vertical-technical.json) |
| English vertical | 15.000 秒 · 1080 × 1920 | 450 帧 | −15.9 LUFS / −3.7 dBTP | [Technical record](en/vertical-technical.json) |

四个文件使用 H.264 High、30 fps、有限范围 4:2:0、BT.709 原色及矩阵、sRGB 传递曲线、48 kHz 双声道 AAC。共解码 2,700 帧，时间戳连续，MP4 索引位于媒体数据之前。

使用无窗口 AVPlayer 连续 1× 放映，按实际播放中的画面核对语言、红图的来源和选择、蓝图留在托盘、原问题之后的续写、待用的发送箭头和片尾网址。检查同语字幕的顺序、语言与时间。静音画面审片与音轨的客观核对独立进行。未进行主观耳听或观众转化测试。每个最终文件的播放结果与文件标识汇集于[逐版放映记录](localized-playback.json)。

## 素材与功能验证

工作台与自行车图片由 ImageGen 生成，发布版相机键由原生 AppKit 绘制，托盘状态、Chrome 窗框和 ChatGPT 草稿为离线合成。已记录的 0.3.5（20）签名包通过四项隔离自检，包内程序在受控 Chrome 草稿完成五次输入并保留原文、选区、已有附件。此次改版只涉及宣传片本地化，未重测登录的 ChatGPT；验证范围与历史证据见[产品实测记录](product-verification.json)。前一次中英混排样片的验收记录单独存放于[历史归档](historical/mixed-language/)。
