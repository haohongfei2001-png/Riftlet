# 官网、正式包与受控草稿核验

核验于 2026 年 11 月 18 日，macOS / Apple Silicon。成片使用两种公开外观的正式名称「截图托盘 / Screenshot Tray」与「微缝 / Micro Slit」。官网还提供「风铃 / Wind Chime」，三者共用同一截图队列和历史。[官网外观说明](https://riftlet.com/#faq)

## 官网与发布身份

- 在本机用 `curl` 经系统配置的 HTTPS 代理读取官网、稳定更新源与四项美术资源。以 Git blob 的 SHA‑1 对实际 HTTP 正文逐字节比对。首页为 `39967aba09f0a85be72faddca4fcdc046e59c906`，稳定更新 XML 为 `6f5891abf0c88007098f4cb4c9c29e4077313208`，两者与 GitHub Pages 部署提交完全一致。页面明确列出三种外观的中英文名称，下载链接指向 1.0.5 的 DMG。[首页](https://riftlet.com/) · [稳定更新源](https://riftlet.com/updates/stable.xml)
- GitHub REST 的 Pages 配置返回 `main:/`、自定义域名 `riftlet.com`。最新构建为 `built`，提交 `9fd8ad15fca043915069904113e5fb67d82b4948`。该提交合入 PR #114，将 1.0.5（31）的官网、文档和更新源发布到 main。父提交 `314f42e5a682f67085f3c95b87ecaace7b88156c` 来自正式产品合并。GitHub Compare 显示，从发布标签到此次官网提交未改动 `Sources/`、`website-assets/` 或 `site.css`。[PR #114](https://github.com/haohongfei2001-png/Riftlet/pull/114) · [在线对应源码](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/index.html)
- 正式标签 `v1.0.5` 指向 `fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee`。GitHub Release 记录显示 DMG 大小为 12,686,160 字节，公布的 SHA‑256 为 `99276347932e231adf743664a54cfc782d8e345d89221587d54b7299a5c9f315`。该摘要来自发布资产元数据，本次功能检查直接使用已安装的签名 App。[正式发布](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.5)

| 官网资产 | 网站正文与安装包资源一致的 Git blob |
|---|---|
| riftlet.svg | `8742e132f43b61819e8550ad24eb8552d8621d9f` |
| reading.svg | `336ad5196625501271106b8f82561c45759c2750` |
| error.svg | `7ae4e464d40b0fca66a92c7be38ba0aed0fecf44` |
| glass-study.png | `2f4593262ab240d0b16e2b2c2b6ea098dbfdf492` |

## 正式安装包

用 PlistBuddy 检查安装包 Info.plist，版本为 1.0.5、构建号为 31。随包 `release-build.json` 记录的源提交是上述正式标签。`codesign --verify --deep --strict` 通过，Team ID 为 `ZB9D4T66QB`。主可执行文件 SHA‑256 为 `9408b891e805c141108b64019e523a45e30221a03a10c2b91ae97bb16cb66207`，与发布工程留下的签名包自检记录相同。[发布自检记录](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/docs/releases/1.0.5/evidence/rc31/package-selfchecks.json)

从安装目录的主可执行文件分别运行 `--ordinary-build-info`、`--self-check`、`--web-acceptance-self-check`、`--first-use-self-check`、`--system-screenshot-candidate-self-check`。普通包报告输入与开始检测启用、自动安全重试关闭。四项自检最终全部 PASS。首次受限沙箱运行时，两个涉及 ImageIO 的用例分别报告 `unsupportedImage`、`CaptureError code=7`。在普通 macOS 环境重跑这两个独立自检后均通过，另外两个用例第一次即通过。候选截图自检使用生成图，验证原始文件导入、两个独立软件输入和两次 START、开始后退出及重启保留状态。

## 独立的受控 Chrome 复现

使用 Google Chrome 157.0.8103.79 的 `--headless=new`、独立临时配置和 127.0.0.1 本地用例，不打开可见窗口。测试运行器是仓库原有的 `Tests/WebPageProgram/chrome-input-resource.test.cjs`，场景为 `actual-marked-zh-composer-four-direct-fields`。通过 `RIFTLET_WEB_SOURCE_OVERRIDE` 读取签名包中的 `Riftlet_RiftletAdapters.bundle/Contents/Resources/chatgpt-web-20261027.js`，实测 SHA‑256 为 `47b2ad88fecd29f91127fd5b04c4279db2db3e77f23a3e4cfd1aee4234c726ee`。[测试用例](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/Tests/WebPageProgram/chrome-input-resource.test.cjs)

结果为 5 次独立输入、5 次原生 setter、5 次 change、5 次受控附件开始信号。5 个原始 FileList 均通过检查，原草稿文字、选区和已有附件保留。错误目标输入、自动发送以及用例统计的上传请求均为 0。测试进程正常退出并清理自有配置。

## 画面证据范围

- 空队列镜头采用关闭托盘截图键的配置。原生 `RiftPanelController` 在队列和截图键都为空时隐藏托盘，也会在微缝没有行时隐藏装饰线。选择到达和补位依据原生布局与生命周期，无需赋予截图内容自动识别或自动发送能力。[原生控制器](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletUI/RiftPanelController.swift)
- 正式包自检验证了软件处理路径，受控 Chrome 验证了本地网页草稿语义。此次未在登录后的 ChatGPT 上实传，也未实录物理系统截屏、原生指针点击或真实服务回执。片中的截图出现、两种外观、补位和当前草稿画面是品牌动效合成。
