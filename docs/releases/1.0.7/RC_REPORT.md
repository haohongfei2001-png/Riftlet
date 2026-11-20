# Riftlet 1.0.7（49）验收

[**查看 G1–G6 最终验收报告、逐图记录与推广判断**](https://github.com/haohongfei2001-png/Riftlet/pull/119#issuecomment-7028325810)。报告固定在同一个 Draft PR 的这条记录，按下列包身份补入实测，以及 GitHub 对最终准入提交的检查。放行前，公开版仍为 1.0.5（31）。[Issue #118](https://github.com/haohongfei2001-png/Riftlet/issues/118)

## 候选身份

| 项目 | 值 |
| --- | --- |
| 产品源码 | `b431931eba1d31b5ac7a5fcc110db8613e11ac7d` |
| 安装包 | Riftlet 1.0.7（49），arm64 与 x86_64，13,415,624 字节 |
| DMG SHA-256 | `67aea5fd067d405701e10cdc512d8657e91db569d0ba6715614a035fb9891023` |
| 包内网页程序 SHA-256 | `efb30a094e6488d0642c949b39981410e7e06545d8bf8b899c9587a2ea63a945` |
| 签名和公证 | App、DMG 均通过 Developer ID 签名、Apple 公证、装订与 Gatekeeper 核验 |

[最终包核验收据](evidence/build49.json)

## 集成与现场修复

- #119 在原分支上继承 #117 的完整 build 44，逐个筛选 #69 的 68 个生产源码文件。Chrome 和 Edge 使用同一个截图、操作、回执与资料恢复模型。点击绑定原浏览器进程、窗口、标签、文档和编辑器。旧 UNKNOWN 只读核对，用户决定是否再次附加和发送。[移植清单](EDGE_PORT_AUDIT.md)
- 45 在登录 Edge 临时草稿已经显示正确图片，却因移除按钮在悬停前透明而漏收起。46 的独立反例又暴露了其他附件内嵌的次级弹出卡可能被误认。47 要求可见原图、精确内容、文件名和本卡有归属的移除按钮同时成立。该版本在原真实草稿得到了 START 并收起，受控核验涵盖错误一个像素、嵌套卡、移位、换图和失败后恢复。[真实分组记录](evidence/host-47.json) · [独立原卡反例](evidence/independent-edge-47.json)
- 47 在真实 Chrome 两次于输入前超时，其中一组鼠标按下相隔 1.726 秒。49 对原目标一次发送约 17 KB 的只读见证脚本。建立文档见证仍使用原生 150 毫秒预算，等待同一请求的回执移到后台，再核对原进程、窗口、标签与原稿。旧页面经历系统校时时，使用与原生一致的墙钟和单调经过时间校验，晚执行的见证不能用于输入。只读续查、同 URL 刷新、换编辑器、失焦与重新聚焦均做了独立对照。[时钟与见证独立复核](evidence/independent-pin-49.json)
- 在 47 的独立机器上，实际走通 Edge 系统授权拒绝及恢复、JavaScript 关闭及开启、分进程窗口、废纸篓 17 份逐图恢复、千图资料库、公开 31 经 Sparkle 和手工替换。49 的同包结果在本报告顶部逐项登记。这些原始收据始终保留 47 的身份。[权限](evidence/permission-47.json) · [资料清理](evidence/storage-47.json) · [负载](evidence/load-47.json) · [升级](evidence/upgrade-47.json)

[本轮进度](PROGRESS.md) · [公开渠道核对](evidence/public-31.json)
