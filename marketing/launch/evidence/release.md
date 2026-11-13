# 公开版本与官网核验

核对日期为 2026-11-14（北京时间）。版本从 Releases 列表取出，包含标记为 prerelease 且已公开的条目。当天该仓库列出一个公开发行。

| 核对项 | 结果 |
| --- | --- |
| 公开发行 | 0.3.5（20）Public Beta，`draft=false`、`prerelease=true`。发布时间 2026-11-13 10:09:32（北京时间）。[发行页](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1) |
| 运行版本源码 | `v0.3.5-beta.1` → `939e3af47ba18d4850311528130934c586cfcb76`。[固定源树](https://github.com/haohongfei2001-png/Riftlet/tree/939e3af47ba18d4850311528130934c586cfcb76) |
| 制作工作树基线 | 远程 main 的 `280be2f8422ccf6c0864f53b8f83e80552b2ec32`。此提交的 `Sources/` 相对发行标签无差异。当前消费者文档使用 build 20；发行标签内部分消费者文档页首仍标为 build 19。[制作基线](https://github.com/haohongfei2001-png/Riftlet/tree/280be2f8422ccf6c0864f53b8f83e80552b2ec32) |
| 下载入口 | 读取线上 `https://riftlet.com/` 得 HTTP 200。页面版本 `2026-11-14-v2.1`，页眉与结尾的两个 DMG 链接均指向同一版本化资产。跟随重定向，下载端响应 HTTP 200、`application/octet-stream`，文件名 `Riftlet-0.3.5-20-universal.dmg`，长度 11,244,473 字节。[官网](https://riftlet.com/) |
| 发布校验值 | GitHub Release API 的资产 digest 与公开校验表一致，均为 `c4bdeeca1410cc42649c3e3b8437ddd704605013d90ed9553bdc242f2d74cc7a`。两份语言版发行说明、校验表和一个 universal DMG 是四个手工上传的资产。[官方校验表](https://github.com/haohongfei2001-png/Riftlet/releases/download/v0.3.5-beta.1/SHA256SUMS.txt) · [发布核对](https://github.com/haohongfei2001-png/Riftlet/pull/62) |
| 品牌出处 | 当天线上 Logo 与基线 `website-assets/riftlet.svg` 的 SHA-256 均为 `f31d71318e1aaef2464bbcc25c5a105fa6959d10006eb7c64d30aac42fbb3e90`。官方图稿底色 `#19B7A4`，两道深墨形状 `#102A27`；站点底色 `#FCFBF8`。官网说明互动演示使用示例内容。[品牌原图](../../../website-assets/riftlet.svg) · [站点样式](../../../website-v2.css) |

## 源码连续性

对比三份源树：三形态合并点 `b2983a60725ec733cb2f4a799bd615cb21f20dd4`、共享安装修复 `9f43c5a99bbbcf3e038c94ea4c625aa16f6bba24`、公开发行 `939e3af47ba18d4850311528130934c586cfcb76`。三者以下 Git 对象相同。此比对支持追溯实现，并不提供新的设备或网页运行证据。

| 对象 | Git 对象 ID |
| --- | --- |
| `Sources/RiftletCapture` | `f8771f1f64d13a78210cdc8bbea505ed097345bf` |
| `Sources/RiftletAdapters` | `b48b0ffce795bd8e560bed9ae040fefc1cd64fd6` |
| `Sources/RiftletCore` | `0ab9465926fa8c7622a113d3a64ddfd6808fc0b6` |
| `Sources/RiftletUI/RiftPanelController.swift` | `44eeeb5eecf546edf1fbffa88d874dff9cf7713e` |

在这段范围内 App 接线包含首次权限说明和菜单措辞更新。公开资料把连续附加记录归到 build 18；build 19 有单独的管理员安装与收录记录。对 build 20 的当轮结论要读实际取景记录。[公开支持矩阵](../../../docs/consumer/SUPPORT-MATRIX.md) · [消费者审核 PR](https://github.com/haohongfei2001-png/Riftlet/pull/61) · [当轮取景](../video/capture-log.md)

## 现有影像的来源检查

在制作基线以 `git ls-files '*.mov' '*.mp4' '*.gif' '*.webm'` 枚举到 18 个既有动态文件。8 个在 `design/` 的早期探索/动效稿，5 个在 10 月 29 日的薄边原生动作实验，5 个在 11 月 7 日的原生 UI/收尾验收。逐组核对其命名及所属说明，均未找到可作发行版真实 ChatGPT 附加镜头的公开原片。早期个人 Beta 的双图及五图有公开文字记录，PR 将截图、原始日志、测试聊天身份列作私有材料。官网的网页演示也不能代替原生 App 与真实目标在同一操作中的录制。[早期个人 Beta 操作证据](https://github.com/haohongfei2001-png/Riftlet/pull/41) · [原生实验边界](../../../engineering/evidence/2026-10-29-thin-edge-native/README.md) · [原生窗口集](../../../engineering/productization-20261107/native/README.md)
