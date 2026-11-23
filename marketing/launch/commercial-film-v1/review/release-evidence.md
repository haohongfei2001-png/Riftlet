# 宣传承诺核验 · 2026-11-23

## 版本依据

GitHub 最新正式发行是 1.0.5（31），标签源提交为 fe9c227。稳定更新源与产品下载按钮均指向 1.0.5。远端 main 为 9fd8ad15。直接读取在线首页与更新源，Git blob 分别为 39967aba 和 6f5891ab，与 main 完全一致。本机安装包的 Info.plist 和发行 manifest 与此版本、构建号及标签源提交一致，严格代码签名检查通过。[正式发行](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.5) · [官网](https://riftlet.com/) · [稳定更新源](https://riftlet.com/updates/stable.xml) · [对应 main](https://github.com/haohongfei2001-png/Riftlet/tree/9fd8ad15fca043915069904113e5fb67d82b4948)

## 可以向用户说明的行为

| 场景 | 公开版本行为 | 表达要点 |
|---|---|---|
| 截图 | macOS 照常截图并保存文件。获准访问截图目录的 Riftlet 收录系统截图，在边缘显示缩略图。 | 保留原来的截图快捷键、截图原件。仅存于剪贴板的截图不属于此入口。 |
| 附加 | 当前台 Google Chrome 打开可编辑的 ChatGPT 网页草稿，点击一张边缘截图只附加选中的图。 | 主张后交代 Chrome 和草稿，展示“点一下”的明确对象。 |
| 继续写 | 原有正文和已有附件保留。草稿开始接收图时边缘缩略图收起，上传进度在 ChatGPT 中显示。 | 通过画面呈现原问题和原附件仍在。用户自己决定何时发送。 |
| 省下的步骤 | 用户可以省去打开文件夹找图、选择文件或拖放。若其他应用当前在最前，先将目标草稿带到 Chrome 前台。 | 用同时可见的图表与前台草稿拍摄。不要把任意前台 App、任意窗口自动识别为目标。 |
| 条件和次级功能 | macOS 13+、Apple 芯片与 Intel。首次设置需截图目录访问、Chrome 自动化和 Apple 事件的 JavaScript 权限。托盘、风铃、微缝共用队列。关闭内建截图按钮时可展示空队列完整隐去。若开启托盘截图按钮，空托盘仍可保留相机入口。 | 首屏保留支持范围，设置详见安装说明。点击附加可能令图片上传；发送消息是下一次独立动作。 |

[正式支持矩阵](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/docs/consumer/SUPPORT-MATRIX.md) · [首次使用步骤](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/docs/consumer/QUICK-START.zh-CN.md) · [安装与权限](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/docs/consumer/INSTALL-AND-PERMISSIONS.md) · [原文和已有附件保留](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/README.md)

## 开发与实录证据边界

- 0.3.5（20）是历史 Public Beta。1.0.6、1.0.7 Edge、跨浏览器与多 AI 草稿、1.0.8（61）有开发或签名候选，但当前公开 1.0.5 的支持范围仍是 Google Chrome 网页版 ChatGPT。宣传不承诺其他浏览器或 AI 服务。[版本列表](https://github.com/haohongfei2001-png/Riftlet/releases) · [Edge 集成候选](https://github.com/haohongfei2001-png/Riftlet/pull/119) · [多浏览器与多 AI 开发](https://github.com/haohongfei2001-png/Riftlet/pull/122) · [1.0.8 候选](https://github.com/haohongfei2001-png/Riftlet/pull/125)
- 1.0.2 同源签名候选在实际匿名 ChatGPT 草稿有三张连续独立的附加记录。1.0.5 隔离发行测试当时未连到可用草稿；正式包网页模块的本地受控 Chrome 检查只验证其受控场景。本次广告按照用户确认的合成方向呈现核心交互，另行注明镜头来源。上述记录用于核对行为与版本，不能作为本片的实录证明。[历史真实记录](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/engineering/quality/2026-11-14/actual-chatgpt-attachment.json) · [1.0.5 签名模块检查](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/docs/releases/1.0.5/evidence/rc31/signed-chrome-comparison.json)
- 既有品牌资产分别涵盖真实托盘、桌面实录、设计动画与离线草稿合成。#65、#66 的采集素材有各自版本和拍摄范围；#67 和 #116 中的附加镜头明确属于合成。不得将这些镜头包装为同一次线上操作的连续实录。[Light study](https://github.com/haohongfei2001-png/Riftlet/pull/65) · [Launch Kit](https://github.com/haohongfei2001-png/Riftlet/pull/66) · [商业片](https://github.com/haohongfei2001-png/Riftlet/pull/67) · [外观片](https://github.com/haohongfei2001-png/Riftlet/pull/116)

本次复验另以安装在本机的正式签名包内网页程序及干净的无头 Chrome 对受控草稿执行两次分别附加。两次均观察到独立附件开始，原文、已有附件、文字选区保留，无自动发送。[环境、命令与观察字段](controlled-attachment.json)
