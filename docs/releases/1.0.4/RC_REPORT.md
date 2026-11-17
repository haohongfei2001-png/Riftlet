# Riftlet 1.0.4 私有候选

本轮在 `dev/1.0.4-consumer` 实施 [PR #109 的 T00–T10](CODEX_HANDOFF.md)。规划基线和旧用户兼容策略、完整性能实测及首次验收记录见[前一候选的固定记录](BUILD_26_REPORT.md)。[实施与五项正式 CI 在 Draft PR #110](https://github.com/haohongfei2001-png/Riftlet/pull/110)。

**本次产品变化。** 设置收为通用、外观、截图和帮助四页，首次使用可分两步完成或延期。新档案默认使用三张截图的托盘，旧档案保留原布局。玻璃透明度与相机机身颜色可单独调整。截图仓库从全库搜索再分页；带重音的旧文件名、图像尺寸、原记录 UUID 仍可找回。附加目标与 START、UNKNOWN、截图原件和数据库格式沿用原产品契约。

**最后两个修复。** build 26 的正式 macOS CI 在英文网格的 680pt 窗口测得内容需要 708pt，且设置页重复展示 Chrome JavaScript 拒绝的恢复说明。保留[首次原生失败记录](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44054602340)。`c7934adc82d382e78cf23ab96ed6d6784e88b905` 让长截图标题按当前详情列宽换行，并在原附件错误已经给出入口时收起重复说明。修复前本机测得英文网格需要 697.5pt，修复后为 575.5pt，16 组原生缩放检查均通过。原 XCTest 断言不变。与已签名 build 26 比，产品输入只改这两份界面源码和内部构建号。两版独立保留签名与测试身份。

**旧版真实升级。** 在独立的 ARM64 macOS 27.2 图形会话，从公开 1.0.3（25）的菜单和 1.0.2（24）的设置分别触发了 Sparkle「安装并重新启动」。两个进程均实际运行下方 build 27 的签名二进制。隔离使用[已验签的私有更新源](evidence/signed-rc27/private-update-identity.json)。四份升级前后快照逐字节相同，包含六张表、12 个文件、目录书签和反馈草稿；样本中有 1 条旧 UNKNOWN、3 个 checkpoint、0 条 START。因此此项不能证明有非空 START、共享 Applications 需要管理员授权或现有 Chrome 自动化授权的全部情形。

**原生界面。** 这份签名 App 在 WindowServer 中跑完中文设置 15/15、英文设置 15/15（各 38 帧）、仓库 8/8（20 帧）、三种桌面形态 43/43（73 帧），四组重启均通过；24 组托盘像素对照通过。[实测清单与签名身份](evidence/signed-rc27/receipt.json)包含每组实际输入方式、用例及原始截图散列。窗口使用隔离的合成素材。

**辅助功能、性能及环境。** 30 分钟空闲采样、状态菜单的 VoiceOver 焦点循环在上一签名包 26 的普通安装中运行。该次实测有 31 个样本，6 张图库样本的平均单核 CPU 为 0.013%，进程物理读写增量均为 0；这不是满库性能保证。VoiceOver 字幕表明 Tab 可依次访问设置、截图仓库、检查更新、退出，并通过 Space 打开设置；没有覆盖全部控件或朗读发音。[进程数据](evidence/signed-rc27/build26-signed-guest-idle-30m.json) · [原始计数](evidence/signed-rc27/build26-signed-guest-idle-30m.csv) · [VoiceOver 范围](evidence/signed-rc27/build26-signed-voiceover.json)。1.1 GB 图片的逐文件散列、420 张截图的两小时数据试验、128 MiB 磁盘满与 10,000 条记录的查询测量保留[原始运行身份及条件](BUILD_26_REPORT.md)。

**普通首用。** 隔离 Mac 的四份全新应用档案中，分别用红色关闭按钮、Escape、稍后和 macOS 系统辅助功能键盘的 Cmd-W 关闭引导。四次都把状态从开始变为延期；退出再启动，更换进程后没有再次弹出。[同一 build 27 的逐项回执](evidence/signed-rc27/onboarding.json)。

**发行裁决：BLOCKED。** 专用 Chrome 在新草稿连接超时，一次受支持的恢复尝试又返回 TLS 错误。没有向私人对话添加图片，没有发送消息。最终包的真实 ChatGPT 首次冷点击及三组间隔 ≤2 秒的连续双图均为 **NOT_RUN**。126 项页面测试、61 项旧操作观察与 31 项隔离浏览器回归只证明受控路径；不代替真实附件的 START、吞噬、草稿保留和不自动发送。恢复条件为专用测试 Mac 能通过正常 TLS 稳定访问可编辑的 ChatGPT 草稿。其余环境缺口包括：macOS 13 原生启动、完整中文组字和 VoiceOver、真实多屏热插拔及跨 Space。没有用用户的正式安装或个人数据补测。

**安装包及直接安装。** 私有发行工作区中的 `formal-dmg/Riftlet-1.0.4.dmg` 共 12,717,001 字节，SHA-256 `b841402653082510d82e2278eb5a047ac64166e951b2e74694b9e7aa244fcdd3`。主可执行文件 SHA-256 `2f83a996f1a9738754ed001fa221af7d782e54e350a970b8b1c9ff6c8c57a2ab`。Developer ID Team `ZB9D4T66QB`，Bundle ID `com.riftlet.app`；含 arm64 及 x86_64，最低目标 macOS 13。Apple 对 App（`a253b079-2ded-45be-aa4a-b72129250a72`）和 DMG（`f4b1ca22-0b75-4cb2-8118-192e7a623115`）分别返回 Accepted。两层票据均通过官方 stapler 验证，DMG 及其内 App 的 Gatekeeper 分别接受。此前 Apple 票据服务有 TLS 瞬断，使用相同安装包和原公证任务恢复核验，没有再提交。隔离机验证 DMG 哈希后只读挂载、复制、推出，再从用户 Applications 正常打开。系统截图新增 1 张，原图与私有副本散列一致，并在原生仓库中选中。[两次更新、DMG 安装和系统截图记录](evidence/signed-rc27/upgrade.json)。这不是从公开网站下载的 quarantine 首装。

[中文设置](evidence/signed-rc27/settings-zh-settings-light-display.png) · [英文最小窗口](evidence/signed-rc27/settings-en-settings-minimum-capture.png) · [截图仓库](evidence/signed-rc27/history-history-library-cross-page-uuid.png) · [托盘](evidence/signed-rc27/desktop-tray-3.png) · [风铃](evidence/signed-rc27/desktop-light-leftMiddle-windChime.png) · [微缝](evidence/signed-rc27/desktop-dark-rightMiddle-microSlit.png)。

[62 个验收项及逐项边界](evidence/signed-rc27/cases.json)与[验收标准](ACCEPTANCE.md)一一对应。实际源码审查绑定该实施 PR 的 G 和 tree，直接子提交 H 仅更新 `engineering/mainline/source-admission.json`。最终 H 的五项运行结果见 [PR #110 Checks](https://github.com/haohongfei2001-png/Riftlet/pull/110/checks)；前版测试或规划 CI 不移记到新 H。main 仍为基线 `3f8149e`；读取时远端 `protected=false`、rulesets 为空，未修改远端策略。公开 1.0.3 安装包、官网和 stable appcast 均未变；未替换个人安装。真实服务与旧系统缺口沿用 [#82](https://github.com/haohongfei2001-png/Riftlet/issues/82)、[#97](https://github.com/haohongfei2001-png/Riftlet/issues/97)，整体进度见 [#106](https://github.com/haohongfei2001-png/Riftlet/issues/106)。
